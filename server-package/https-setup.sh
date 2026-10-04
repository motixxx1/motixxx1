#!/bin/bash
# Zariz: HTTPS for the home server, in one command.   sudo ./https-setup.sh
#
# Before running:
#   1) duckdns.org → sign in → create a name (e.g. zariz-app) → copy the token.
#   2) In config.env:  DUCKDNS_DOMAIN=zariz-app   and   DUCKDNS_TOKEN=<the token>
#   3) In the router: forward ports 80 and 443 (TCP) to this computer.
#
# It installs Caddy (a small web server) that gets a free certificate from Let's Encrypt,
# renews it by itself, and passes everything to the Zariz server on port 3000.
set -euo pipefail
cd "$(dirname "$0")"
DIR="$(pwd)"

if [ "$(id -u)" != "0" ]; then echo "Run with sudo:  sudo ./https-setup.sh"; exit 1; fi
[ -f config.env ] || { echo "config.env not found in $DIR"; exit 1; }
get() { grep -E "^$1=" config.env | tail -1 | cut -d= -f2- | tr -d '\r' | sed 's/^"//;s/"$//'; }
NAME="$(get DUCKDNS_DOMAIN)"; TOKEN="$(get DUCKDNS_TOKEN)"; PORT="$(get PORT)"; PORT="${PORT:-3000}"
NAME="${NAME%.duckdns.org}"
if [ -z "$NAME" ] || [ -z "$TOKEN" ]; then
  echo "Fill DUCKDNS_DOMAIN and DUCKDNS_TOKEN in config.env first (see the top of this file)."; exit 1
fi
HOST="$NAME.duckdns.org"

echo "1/4 Pointing $HOST at this network..."
R="$(curl -fsS "https://www.duckdns.org/update?domains=$NAME&token=$TOKEN&ip=" || true)"
[ "$R" = "OK" ] || { echo "DuckDNS did not accept the name/token (answer: $R)"; exit 1; }

echo "2/4 Installing Caddy..."
case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; armv7l) ARCH=armv7 ;; armv6l) ARCH=armv6 ;;
  *) echo "Unsupported CPU: $(uname -m)"; exit 1 ;;
esac
mkdir -p "$DIR/https"
if [ ! -x "$DIR/https/caddy" ]; then
  curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=$ARCH" -o "$DIR/https/caddy"
  chmod +x "$DIR/https/caddy"
fi
setcap cap_net_bind_service=+ep "$DIR/https/caddy" 2>/dev/null || true

echo "3/4 Writing the configuration..."
cat > "$DIR/https/Caddyfile" <<EOF
$HOST {
	encode gzip
	reverse_proxy 127.0.0.1:$PORT
}
EOF

echo "4/4 Starting it now and on every boot..."
cat > /etc/systemd/system/zariz-https.service <<EOF
[Unit]
Description=Zariz HTTPS ($HOST)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$DIR/https/caddy run --config $DIR/https/Caddyfile --adapter caddyfile
Environment=XDG_DATA_HOME=$DIR/https/data XDG_CONFIG_HOME=$DIR/https/config
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now zariz-https.service
systemctl restart zariz-https.service
command -v ufw >/dev/null && ufw status | grep -q active && { ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null; } || true

echo
echo "Checking https://$HOST (the first certificate can take up to a minute)..."
for i in $(seq 1 12); do
  if curl -fsS -m 10 "https://$HOST/healthz" >/dev/null 2>&1; then
    echo "Done: https://$HOST is working."
    echo "Customers: https://$HOST    Pros: https://$HOST/pro"
    exit 0
  fi
  sleep 5
done
echo "Not reachable yet. Check that ports 80 and 443 are forwarded in the router to this computer,"
echo "then: sudo systemctl restart zariz-https   (logs: journalctl -u zariz-https -n 50)"
