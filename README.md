# 🌐 ping-web

A lightweight web-based ping monitoring tool for Ubuntu servers.  
This script automatically pings a specific IP address every second and shows logs (including packet loss) via a web interface.

---

## 🚀 Features

- Realtime ping logs with timestamps
- Tracks and logs packet loss events
- Simple and auto-refreshing web interface
- Custom web port support (e.g. 63100)
- Runs as a systemd service
- Tehran timezone by default

---

## 📦 Quick Auto-Install (Recommended)

Run the following command on your Ubuntu server:

```bash
bash <(curl -s https://raw.githubusercontent.com/0fariid0/ping-web/master/setup_ping_monitor.sh)
