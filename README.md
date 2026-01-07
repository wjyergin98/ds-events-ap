# DS Events AP (Nintendo DS Mystery Gift on modern networks)

This repository packages a reproducible "piggyback" Wi-Fi access point for **Nintendo DS (original/fat, DS Lite)** era Wi-Fi compatibility, using a Linux machine with:

- **Ethernet uplink** to your home network/internet
- A **USB Wi-Fi adapter that supports AP mode** (e.g., Netgear A6150)
- `hostapd` (to broadcast an open 2.4 GHz legacy SSID)
- `dnsmasq` (DHCP only; optionally advertises an event DNS)

It was built to support workflows like Gen IV Pokémon event / Mystery Gift retrieval where:

- Your primary router uses WPA2/WPA3
- Your phone hotspot cannot be set to "open"
- The Nintendo DS expects open/WEP and legacy 802.11b/g behavior

---

## What this tool does

- Creates an open SSID (default: `DS-Events`) on your USB Wi-Fi adapter
- Assigns the adapter a static gateway IP (default: `192.168.4.1/24`)
- Provides DHCP leases to the DS (`192.168.4.10`–`192.168.4.50`)
- Enables IPv4 forwarding + NAT so clients can reach the internet
- Advertises a configurable **event DNS server** to clients via DHCP option 6

---

## Supported platforms

This project has been validated on:

- **x86_64 Linux** (Ubuntu 20.04+)
- **Raspberry Pi 5 (ARM64)** running Raspberry Pi OS / Debian with **kernel ≥ 6.12**

### Raspberry Pi notes (important)

- Modern kernels (≥ 6.12) include an **in-kernel, standards-compliant driver** for the Netgear A6150 (`rtw_8822bu`).
- **No external DKMS / out-of-tree Wi-Fi driver is required** on these systems.
- The adapter must support **AP mode** (`iw list` → `Supported interface modes: * AP`).

On Raspberry Pi OS, `hostapd.service` is **masked by default**.  
The installer automatically **unmasks (but does not enable)** it so `dsap-up` can manage the AP lifecycle.

---

## Quick start

### 1) Install

```bash
git clone https://github.com/wjyergin98/ds-events-ap.git
cd ds-events-ap
sudo ./install.sh
```

The installer will prompt for:
- AP adapter MAC address (your USB Wi-Fi adapter)
- Uplink interface (auto-detected from default route; you can override)
- SSID / channel
- Event DNS server

### 2) Start / stop

```bash
sudo dsap-up
sudo dsap-status
sudo dsap-down
```

### 3) Optional: systemd service

Installed but not enabled by default.

```bash
sudo systemctl start dsap
sudo systemctl stop dsap
sudo systemctl enable dsap   # start at boot (optional)
```

## Nintendo DS settings

On the DS Wi-Fi connection setup:
- SSID: `DS-Events` (or your configured SSID)
- Security: **None**
- IP: **Auto-obtain**
- DNS:
  - If you want DHCP to handle it, leave DNS on auto.
  - If you want to set DNS manually, set:
    - Primary DNS: your chosen event DNS server
    - Secondary DNS: `0.0.0.0`

## Configuration

After install, edit:

- `/etc/ds-events-ap/config.env`

Defaults:
- Subnet: `192.168.4.0/24`
- Gateway: `192.168.4.1`
- DHCP: `192.168.4.10`–`192.168.4.50`
- SSID: `DS-Events`
- Channel: `6`

## Troubleshooting

### Symptom: DS cannot connect, and **dnsmasq.leases is empty**
This is the most common issue after unplug/replug of the Wi-Fi adapter.

Check leases:

```bash
sudo tail -f /var/lib/misc/dnsmasq.leases
```

If nothing appears when the DS tries, your AP interface likely **does not have** `192.168.4.1/24` assigned.

Fix:

```bash
sudo dsap-up
```

(`dsap-up` always re-applies the AP IP, which is required after hotplug.)

### Symptom: hostapd fails to start

```bash
sudo journalctl -u hostapd -n 120 --no-pager
sudo systemctl status hostapd --no-pager -l
```

Common causes:
- Adapter does not support AP mode
- Wrong channel/hw_mode
- Another service is managing the interface

### Symptom: dnsmasq fails to start

```bash
sudo journalctl -u dnsmasq -n 120 --no-pager
sudo systemctl status dnsmasq --no-pager -l
```

Common causes:
- Something else is already bound to port 53
- Interface not present at service start time

This project uses `port=0` in the drop-in config to avoid DNS conflicts; dnsmasq is used for DHCP only.

### DS error code heuristics (Mystery Gift / WFC)
These vary by server and era, but broadly:
- **No DHCP lease**: local AP/DHCP issue (fix your setup first)
- **52000/52001**: cannot establish TCP connection (server down or routing issue)
- **52100**: server responded incorrectly/empty
- **52201**: server reached; content rejected or Wonder Card album is full (Gen IV stores only 3)

## Security / safety notes

- The access point is **open** (no password). Use it only when needed.
- `dsap-down` removes the iptables rules it created.
- If you enable the systemd unit, understand you are broadcasting an open SSID whenever it runs.

## Uninstall

```bash
sudo ./uninstall.sh
```

This removes:
- `/etc/ds-events-ap/`
- `/usr/local/share/ds-events-ap/`
- `/usr/local/sbin/dsap-*`
- `/etc/dnsmasq.d/ds-events-ap.conf`
- `/etc/systemd/system/dsap.service`

Packages (`hostapd`, `dnsmasq`) are left installed.

## Development notes

This project intentionally:
- Avoids NetworkManager hot-spot helpers (for determinism)
- Resolves the AP interface by **MAC address** (not by `wlx...` name)
- Re-applies `192.168.4.1/24` on every bring-up (fixes hotplug regression)

