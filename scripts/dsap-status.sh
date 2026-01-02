#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

CFG="${1:-$CONFIG_PATH_DEFAULT}"
if [[ ! -f "$CFG" ]]; then
  echo "Config not found: $CFG" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CFG"

AP_IF="$(get_if_from_mac "${AP_MAC:-}" || true)"

echo "DS Events AP status"
echo "  Config    : $CFG"
echo "  AP_MAC    : ${AP_MAC:-<unset>}"
echo "  AP_IF     : ${AP_IF:-<not found>}"
echo "  UPLINK_IF : ${UPLINK_IF:-<unset>}"
echo

if [[ -n "${AP_IF}" ]]; then
  ip -br addr show "$AP_IF" || true
fi

systemctl --no-pager --full status dnsmasq hostapd | sed -n '1,40p'
