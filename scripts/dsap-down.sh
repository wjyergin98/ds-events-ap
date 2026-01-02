#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

require_root
load_config "${1:-}"

validate_mac "$AP_MAC"

AP_IF="$(get_if_from_mac "$AP_MAC" || true)"

# Stop services first
systemctl stop hostapd || true
systemctl stop dnsmasq || true

# Remove iptables rules if we can identify AP_IF
if [[ -n "${AP_IF}" ]]; then
  UPLINK_IF="${UPLINK_IF:-$(get_default_uplink_if || true)}"
  if [[ -n "${UPLINK_IF:-}" ]]; then
    iptables -t nat -D POSTROUTING -o "$UPLINK_IF" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i "$UPLINK_IF" -o "$AP_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$AP_IF" -o "$UPLINK_IF" -j ACCEPT 2>/dev/null || true
  fi

  # Flush AP interface IP (optional tidy)
  ip addr flush dev "$AP_IF" 2>/dev/null || true
fi

echo "DS Events AP is DOWN"
