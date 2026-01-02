#!/usr/bin/env bash
set -euo pipefail

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "ERROR: please run as root (sudo)." >&2
    exit 1
  fi
}

require_root

echo "Uninstalling DS Events AP..."

# Stop services if present
systemctl stop dsap 2>/dev/null || true
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true

# Remove drop-in dnsmasq config (generated)
rm -f /etc/dnsmasq.d/ds-events-ap.conf

# Remove config
rm -rf /etc/ds-events-ap

# Remove installed scripts
rm -f /usr/local/sbin/dsap-up /usr/local/sbin/dsap-down /usr/local/sbin/dsap-status

# Remove installed templates/lib
rm -rf /usr/local/share/ds-events-ap

# Remove systemd unit
rm -f /etc/systemd/system/dsap.service
systemctl daemon-reload

echo "Uninstall complete."
echo "Note: hostapd/dnsmasq packages were not removed. Remove them manually if desired."
