# setup_ping_monitor.sh (English Version)
```bash
#!/usr/bin/env bash
set -euo pipefail

# This script installs and configures a ping monitoring panel on Ubuntu
# - sets system timezone to Iran (Tehran)
# - installs Apache, PHP, ufw
# - sets custom Apache port
# - deploys a ping logger service
# - generates a README.md
# - detects and shows public server IP at the end

# must run as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root. Use sudo." >&2
  exit 1
fi

# ask user for inputs
read -rp "Enter target IP to ping (e.g. 8.8.8.8): " TARGET_IP
read -rp "Enter web panel port (e.g. 63100): " WEB_PORT

# 1. set timezone
timedatectl set-timezone Asia/Tehran
echo "Timezone set to $(timedatectl show -p Timezone --value)"

# 2. update and install deps
apt update
apt install -y apache2 php libapache2-mod-php ufw curl git

# 3. configure Apache to listen on WEB_PORT
grep -qx "Listen ${WEB_PORT}" /etc/apache2/ports.conf || \
  echo "Listen ${WEB_PORT}" >> /etc/apache2/ports.conf

# 4. prioritize index.php
sed -i 's/\(DirectoryIndex \).*/\1index.php index.html/' /etc/apache2/mods-enabled/dir.conf

# 5. create VirtualHost
cat > /etc/apache2/sites-available/000-default.conf <<EOF
<VirtualHost *:${WEB_PORT}>
  ServerAdmin webmaster@localhost
  DocumentRoot /var/www/html
  <Directory /var/www/html>
    AllowOverride All
    Require all granted
  </Directory>
  ErrorLog \${APACHE_LOG_DIR}/error.log
  CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

a2dissite 000-default.conf || true
a2ensite 000-default.conf
systemctl reload apache2

# 6. open firewall
ufw allow "${WEB_PORT}/tcp"
ufw --force enable

echo "Firewall configured: port ${WEB_PORT} open"

# 7. prepare log dir
LOG_DIR=/var/www/html/logs
mkdir -p "$LOG_DIR"
chown www-data:www-data "$LOG_DIR"
chmod 755 "$LOG_DIR"

# 8. deploy ping_logger script
cat > /usr/local/bin/ping_logger.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail

TARGET_IP="${TARGET_IP}"
LOG_DIR="${LOG_DIR}"
PING_LOG="$LOG_DIR/ping_log.txt"
LOSS_LOG="$LOG_DIR/packet_loss_log.txt"

mkdir -p "\$LOG_DIR"
touch "\$PING_LOG" "\$LOSS_LOG"
chown www-data:www-data "\$LOG_DIR"/*.txt
chmod 664 "\$PING_LOG" "\$LOSS_LOG"

while true; do
  TIMESTAMP=\$(date +"%Y-%m-%d %H:%M:%S")
  PING_OUTPUT=\$(ping -c 1 -W 1 "\$TARGET_IP" 2>/dev/null || true)
  if echo "\$PING_OUTPUT" | grep -q '1 received'; then
    PING_TIME=\$(echo "\$PING_OUTPUT" | grep 'time=' | awk -F'time=' '{ print \$2 }' | cut -d' ' -f1)
    echo "\$TIMESTAMP – \${PING_TIME} ms" >> "\$PING_LOG"
  else
    echo "\$TIMESTAMP – PACKET LOSS" >> "\$PING_LOG"
    echo "\$TIMESTAMP – 100% Packet Loss" >> "\$LOSS_LOG"
  fi
  tail -n 100 "\$PING_LOG" > "\$PING_LOG.tmp" && mv "\$PING_LOG.tmp" "\$PING_LOG"
  sleep 1
done
EOF

chmod +x /usr/local/bin/ping_logger.sh

# 9. systemd service
cat > /etc/systemd/system/pinglogger.service <<EOF
[Unit]
Description=Ping Logger Service
After=network.target

[Service]
ExecStart=/usr/local/bin/ping_logger.sh
Restart=always
User=www-data
Group=www-data

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now pinglogger.service

echo "Ping logger service started"

# 10. deploy web panel
cat > /var/www/html/index.php <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="refresh" content="3">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Ping Monitor Panel</title>
  <style>
    body { font-family: Arial, sans-serif; background: #f4f7fa; margin:0; padding:20px; }
    .container { max-width:800px; margin:auto; }
    h1 { text-align:center; color:#333; }
    .card { background:#fff; border-radius:8px; box-shadow:0 2px 5px rgba(0,0,0,0.1); margin-bottom:20px; padding:15px; }
    .card h2 { margin-top:0; color:#444; }
    pre { background:#272822; color:#f8f8f2; padding:10px; border-radius:4px; overflow-x:auto; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Ping Monitor to <?= htmlspecialchars('$TARGET_IP', ENT_QUOTES) ?></h1>
    <div class="card">
      <h2>Latest Ping Results</h2>
      <pre><?php @readfile('logs/ping_log.txt'); ?></pre>
    </div>
    <div class="card">
      <h2 style="color:#c0392b;">Packet Loss Log</h2>
      <pre><?php @readfile('logs/packet_loss_log.txt'); ?></pre>
    </div>
  </div>
</body>
</html>
EOF

chown -R www-data:www-data /var/www/html

# 11. generate README.md
cat > README.md <<EOF
# Ping Web

**Ping Web** is a lightweight web-based ping monitor that logs round-trip times and packet loss to a target IP, refreshing the data every few seconds via a simple PHP-based panel.

## Features
- Ping a specified IP every second
- Detect and log packet loss with timestamps
- Automatically store logs and limit size
- Live web interface using Apache + PHP
- Customizable port and target IP

## Installation
Run this one-liner on your Ubuntu server:

```bash
bash <(curl -s https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/ping-web/main/setup_ping_monitor.sh)
```

> Make sure to replace `YOUR_GITHUB_USERNAME` with your actual GitHub username or repo owner.

Then follow the prompts to:
- Enter the IP you want to monitor
- Set the web interface port (e.g., 63100)

Access your monitor at:
```
http://<your-server-ip>:<port>/
```

## Logs
- All logs are saved in `/var/www/html/logs`
- `ping_log.txt` contains the ping history
- `packet_loss_log.txt` records loss events with timestamps

---
Maintained with ❤️ by [ping-web project](https://github.com/YOUR_GITHUB_USERNAME/ping-web)
EOF

# 12. show panel URL
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
echo "======================================="
echo "✅ Ping Monitor is ready!"
echo "🌐 Access it at: http://${SERVER_IP}:${WEB_PORT}/"
echo "======================================="
