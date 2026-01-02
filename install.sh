#!/usr/bin/env bash
set -euo pipefail

# DS Events AP installer (Ubuntu 20.04+)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "ERROR: please run as root (sudo)." >&2
    exit 1
  fi
}

norm_mac() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

validate_mac() {
  local m
  m="$(norm_mac "$1")"
  if [[ ! "$m" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]]; then
    echo "ERROR: invalid MAC address: $1" >&2
    echo "Expected format: aa:bb:cc:dd:ee:ff" >&2
    exit 1
  fi
}

get_default_uplink_if() {
  ip route 2>/dev/null | awk '/^default / {print $5; exit 0}'
}

prompt_default() {
  local prompt="$1"
  local default="$2"
  local var
  read -r -p "${prompt} [${default}]: " var
  if [[ -z "$var" ]]; then
    echo "$default"
  else
    echo "$var"
  fi
}

normalize_dnsmasq_base_conf() {
  local conf="/etc/dnsmasq.conf"

  # Create a minimal base config if the file doesn't exist.
  if [[ ! -f "$conf" ]]; then
    cat > "$conf" <<'EOF'
# dnsmasq base config (managed by ds-events-ap installer)
# Load additional config files from /etc/dnsmasq.d
conf-dir=/etc/dnsmasq.d,.dpkg-dist,.dpkg-old,.dpkg-new
EOF
    return 0
  fi

  # Detect DS-AP style directives that would conflict with our drop-in.
  if grep -qE '^(listen-address=192\.168\.4\.1|bind-interfaces|port=0|dhcp-range=192\.168\.4\.10|dhcp-option=3,192\.168\.4\.1|dhcp-option=6,)' "$conf"; then
    local ts backup
    ts="$(date +%Y%m%d-%H%M%S)"
    backup="${conf}.ds-events-backup.${ts}"
    cp -a "$conf" "$backup"

    cat > "$conf" <<'EOF'
# dnsmasq base config (managed by ds-events-ap installer)
# Previous /etc/dnsmasq.conf contained DS-AP directives and was backed up.
# Load additional config files from /etc/dnsmasq.d
conf-dir=/etc/dnsmasq.d,.dpkg-dist,.dpkg-old,.dpkg-new
EOF

    echo "Backed up existing /etc/dnsmasq.conf to ${backup}"
    echo "Replaced /etc/dnsmasq.conf with minimal base config to avoid duplicate keywords."
  fi

  # Ensure dnsmasq loads /etc/dnsmasq.d (some custom configs omit it).
  if ! grep -qE '^conf-dir=/etc/dnsmasq\.d' "$conf"; then
    echo "conf-dir=/etc/dnsmasq.d,.dpkg-dist,.dpkg-old,.dpkg-new" >> "$conf"
  fi
}


require_root

echo "Installing DS Events AP..."

# Dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y hostapd dnsmasq iptables

# Install directories
install -d -m 0755 /etc/ds-events-ap
install -d -m 0755 /usr/local/share/ds-events-ap
install -d -m 0755 /usr/local/sbin

# Copy templates
install -m 0644 "$REPO_ROOT/templates/hostapd.conf.template" /usr/local/share/ds-events-ap/hostapd.conf.template
install -m 0644 "$REPO_ROOT/templates/dnsmasq.dsap.conf.template" /usr/local/share/ds-events-ap/dnsmasq.dsap.conf.template

# Copy scripts
install -m 0755 "$REPO_ROOT/scripts/lib.sh" /usr/local/share/ds-events-ap/lib.sh

# Install command scripts into /usr/local/sbin
install -m 0755 "$REPO_ROOT/scripts/dsap-up.sh" /usr/local/sbin/dsap-up
install -m 0755 "$REPO_ROOT/scripts/dsap-down.sh" /usr/local/sbin/dsap-down
install -m 0755 "$REPO_ROOT/scripts/dsap-status.sh" /usr/local/sbin/dsap-status

# Adjust installed scripts to source installed lib.sh
sed -i 's|source "\$HERE/lib.sh"|source "/usr/local/share/ds-events-ap/lib.sh"|g' /usr/local/sbin/dsap-up
sed -i 's|source "\$HERE/lib.sh"|source "/usr/local/share/ds-events-ap/lib.sh"|g' /usr/local/sbin/dsap-down
sed -i 's|source "\$HERE/lib.sh"|source "/usr/local/share/ds-events-ap/lib.sh"|g' /usr/local/sbin/dsap-status

# Prompt user config
echo
echo "Configuration"
echo "------------"
echo "1) Plug in your Wi-Fi adapter (e.g., Netgear A6150)."
echo "2) Find its MAC address (example commands):"
echo "   - ip -br link"
echo "   - ip link show"
echo

AP_MAC_IN="${AP_MAC:-}"
if [[ -z "$AP_MAC_IN" ]]; then
  read -r -p "AP adapter MAC address (aa:bb:cc:dd:ee:ff): " AP_MAC_IN
fi
validate_mac "$AP_MAC_IN"
AP_MAC_IN="$(norm_mac "$AP_MAC_IN")"

UPLINK_DEFAULT="${UPLINK_IF:-$(get_default_uplink_if || true)}"
if [[ -z "$UPLINK_DEFAULT" ]]; then
  UPLINK_DEFAULT="<enter interface name>"
fi
UPLINK_IN="$(prompt_default "Uplink interface (internet-facing)" "$UPLINK_DEFAULT")"

SSID_IN="$(prompt_default "SSID" "${SSID:-DS-Events}")"
CHANNEL_IN="$(prompt_default "Channel (2.4GHz; 1/6/11 recommended)" "${CHANNEL:-6}")"
EVENT_DNS_IN="$(prompt_default "Event DNS server" "${EVENT_DNS:-178.62.43.212}")"

# Advanced network defaults (configurable but we don't prompt by default)
AP_GW_IN="${AP_GW:-192.168.4.1}"
AP_CIDR_IN="${AP_CIDR:-24}"
DHCP_START_IN="${DHCP_START:-192.168.4.10}"
DHCP_END_IN="${DHCP_END:-192.168.4.50}"
NETMASK_IN="${NETMASK:-255.255.255.0}"

# Paths
HOSTAPD_CONF_OUT="${HOSTAPD_CONF:-/etc/hostapd/hostapd.conf}"
DNSMASQ_DROPIN_OUT="${DNSMASQ_DROPIN:-/etc/dnsmasq.d/ds-events-ap.conf}"

# Backup existing hostapd.conf if present
if [[ -f "$HOSTAPD_CONF_OUT" ]]; then
  TS="$(date +%Y%m%d-%H%M%S)"
  cp -a "$HOSTAPD_CONF_OUT" "${HOSTAPD_CONF_OUT}.bak.${TS}"
  echo "Backed up existing hostapd.conf to ${HOSTAPD_CONF_OUT}.bak.${TS}"
fi

# Write config.env
cat > /etc/ds-events-ap/config.env <<EOF_CONF
# DS Events AP configuration
#
# Required
AP_MAC="${AP_MAC_IN}"
UPLINK_IF="${UPLINK_IN}"

# Wi-Fi
SSID="${SSID_IN}"
CHANNEL="${CHANNEL_IN}"

# Event DNS advertised to DS clients
EVENT_DNS="${EVENT_DNS_IN}"

# AP network (defaults match this project guide)
AP_GW="${AP_GW_IN}"
AP_CIDR="${AP_CIDR_IN}"
DHCP_START="${DHCP_START_IN}"
DHCP_END="${DHCP_END_IN}"
NETMASK="${NETMASK_IN}"

# Output paths (advanced)
HOSTAPD_CONF="${HOSTAPD_CONF_OUT}"
DNSMASQ_DROPIN="${DNSMASQ_DROPIN_OUT}"
EOF_CONF

chmod 0644 /etc/ds-events-ap/config.env
normalize_dnsmasq_base_conf

# Install optional systemd unit (not enabled by default)
install -m 0644 "$REPO_ROOT/systemd/dsap.service" /etc/systemd/system/dsap.service
systemctl daemon-reload

echo
echo "Install complete."
echo
echo "Commands:"
echo "  Start : sudo dsap-up"
echo "  Stop  : sudo dsap-down"
echo "  Status: sudo dsap-status"
echo
echo "Optional (systemd):"
echo "  sudo systemctl start dsap"
echo "  sudo systemctl stop dsap"
echo "  sudo systemctl enable dsap   # enable at boot"
echo
echo "Config file: /etc/ds-events-ap/config.env"
echo
echo "Next step: run 'sudo dsap-up' and connect your DS to SSID '${SSID_IN}'."
