#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

require_root
load_config "${1:-}"

validate_mac "$AP_MAC"

AP_IF="$(get_if_from_mac "$AP_MAC" || true)"
if [[ -z "${AP_IF}" ]]; then
  echo "ERROR: AP adapter not found (MAC $AP_MAC). Is it plugged in?" >&2
  exit 1
fi

# Auto-detect uplink if not set
if [[ -z "${UPLINK_IF:-}" ]]; then
  UPLINK_IF="$(get_default_uplink_if || true)"
fi
if [[ -z "${UPLINK_IF}" ]]; then
  echo "ERROR: could not determine uplink interface. Set UPLINK_IF in config.env" >&2
  exit 1
fi

TEMPLATE_DIR="$(find_template_dir)"

# Defaults
SSID="${SSID:-DS-Events}"
CHANNEL="${CHANNEL:-6}"
AP_GW="${AP_GW:-192.168.4.1}"
AP_CIDR="${AP_CIDR:-24}"
AP_IP_CIDR="${AP_GW}/${AP_CIDR}"
DHCP_START="${DHCP_START:-192.168.4.10}"
DHCP_END="${DHCP_END:-192.168.4.50}"
NETMASK="${NETMASK:-255.255.255.0}"
EVENT_DNS="${EVENT_DNS:-178.62.43.212}"

# Bring up AP interface + assign IP (required after hotplug)
ip link set "$AP_IF" up
ip addr flush dev "$AP_IF"
ip addr add "$AP_IP_CIDR" dev "$AP_IF"

# Enable IPv4 forwarding
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# NAT + forwarding rules (idempotent)
if ! iptables -t nat -C POSTROUTING -o "$UPLINK_IF" -j MASQUERADE 2>/dev/null; then
  iptables -t nat -A POSTROUTING -o "$UPLINK_IF" -j MASQUERADE
fi
if ! iptables -C FORWARD -i "$UPLINK_IF" -o "$AP_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
  iptables -A FORWARD -i "$UPLINK_IF" -o "$AP_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT
fi
if ! iptables -C FORWARD -i "$AP_IF" -o "$UPLINK_IF" -j ACCEPT 2>/dev/null; then
  iptables -A FORWARD -i "$AP_IF" -o "$UPLINK_IF" -j ACCEPT
fi

# Render hostapd conf
HOSTAPD_CONF_OUT="${HOSTAPD_CONF:-/etc/hostapd/hostapd.conf}"
render_template \
  "$TEMPLATE_DIR/hostapd.conf.template" \
  "$HOSTAPD_CONF_OUT" \
  AP_IF "$AP_IF" \
  SSID "$SSID" \
  CHANNEL "$CHANNEL"

# Render dnsmasq drop-in
DNSMASQ_DROPIN="${DNSMASQ_DROPIN:-/etc/dnsmasq.d/ds-events-ap.conf}"
render_template \
  "$TEMPLATE_DIR/dnsmasq.dsap.conf.template" \
  "$DNSMASQ_DROPIN" \
  AP_IF "$AP_IF" \
  AP_GW "$AP_GW" \
  DHCP_START "$DHCP_START" \
  DHCP_END "$DHCP_END" \
  NETMASK "$NETMASK" \
  EVENT_DNS "$EVENT_DNS"

# Restart services
systemctl restart dnsmasq
systemctl restart hostapd

echo "DS Events AP is UP"
echo "  AP_IF      : $AP_IF (MAC $AP_MAC)"
echo "  UPLINK_IF  : $UPLINK_IF"
echo "  AP_IP      : $AP_IP_CIDR"
echo "  SSID       : $SSID"
echo "  CHANNEL    : $CHANNEL"
echo "  EVENT_DNS  : $EVENT_DNS"

ip -br addr show "$AP_IF" || true
systemctl --no-pager --full status dnsmasq hostapd | sed -n '1,30p'

echo
echo "Tip: to verify DHCP leases: sudo tail -f /var/lib/misc/dnsmasq.leases"
