#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH_DEFAULT="/etc/ds-events-ap/config.env"

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "ERROR: please run as root (sudo)." >&2
    exit 1
  fi
}

norm_mac() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

validate_mac() {
  local m
  m="$(norm_mac "$1")"
  if [[ ! "$m" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]]; then
    echo "ERROR: invalid MAC address: $1" >&2
    echo "Expected format: aa:bb:cc:dd:ee:ff" >&2
    exit 1
  fi
}

get_if_from_mac() {
  local mac_lower
  mac_lower="$(norm_mac "$1")"

  for d in /sys/class/net/*; do
    local ifname addr
    ifname="$(basename "$d")"
    [[ "$ifname" == "lo" ]] && continue

    addr="$(cat "$d/address" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
    if [[ "$addr" == "$mac_lower" ]]; then
      echo "$ifname"
      return 0
    fi
  done
  return 1
}

get_default_uplink_if() {
  # Print the interface for the default route (best effort)
  ip route 2>/dev/null | awk '/^default / {print $5; exit 0}'
}

script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

find_template_dir() {
  # Prefer installed templates, fallback to repo templates.
  if [[ -d "/usr/local/share/ds-events-ap" ]]; then
    echo "/usr/local/share/ds-events-ap"
    return 0
  fi
  local here
  here="$(script_dir)"
  if [[ -d "$here/../templates" ]]; then
    echo "$here/../templates"
    return 0
  fi
  echo "ERROR: could not find templates directory." >&2
  exit 1
}

load_config() {
  local cfg="${1:-$CONFIG_PATH_DEFAULT}"
  if [[ ! -f "$cfg" ]]; then
    echo "ERROR: config not found: $cfg" >&2
    echo "Run: sudo ./install.sh" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$cfg"
}

render_template() {
  local in="$1"
  local out="$2"
  shift 2

  local tmp
  tmp="$(mktemp)"
  cp "$in" "$tmp"

  # Replace pairs: __KEY__ VALUE
  while (( "$#" )); do
    local key="$1"; local val="$2"; shift 2
    # Escape sed replacement
    val="${val//\/\\}"
    val="${val//&/\&}"
    sed -i "s|__${key}__|${val}|g" "$tmp"
  done

  install -m 0644 "$tmp" "$out"
  rm -f "$tmp"
}
