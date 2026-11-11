#!/usr/bin/env bash
# Sets up the Zonic web session on a Debian box: Docker Compose file, Caddy in front with
# a password, the settings app, and the timer that shuts the session down when idle.
#
# Safe to run again. It rewrites the units and the Caddyfile from the checkout each time,
# and leaves your .env and the Chrome profile alone.
#
#   sudo ./server/host/install.sh
set -euo pipefail

SERVER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(dirname "$SERVER")"
CONF_DIR=/etc/zonic
STATE_DIR=/var/lib/zonic

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run this with sudo"
command -v docker >/dev/null 2>&1 || die "docker is not installed"
docker compose version >/dev/null 2>&1 || die "docker compose (v2) is not installed"
command -v python3 >/dev/null 2>&1 || die "python3 is not installed"
if ! command -v curl >/dev/null 2>&1; then
  say "installing curl, it is needed to fetch caddy"
  apt-get update -qq && apt-get install -y -qq curl >/dev/null || die "could not install curl"
fi
if ! command -v stat >/dev/null 2>&1 || ! command -v systemctl >/dev/null 2>&1; then
  die "this expects a systemd system with coreutils"
fi

say "giving the session a place to keep its Chrome profile"
mkdir -p "$SERVER/data/chrome" "$SERVER/data/state" "$STATE_DIR" "$CONF_DIR"
mkdir -p "$STATE_DIR/caddy/data" "$STATE_DIR/caddy/config"
# The container runs as uid 1000 and has to write the idle marker into this one.
chmod 0777 "$SERVER/data/state"

say "configuring"
if [ ! -f "$SERVER/.env" ]; then
  cp "$SERVER/.env.example" "$SERVER/.env"
  say "wrote $SERVER/.env from the example"
fi

set -a
# shellcheck disable=SC1091
. "$SERVER/.env"
set +a

PUBLIC_PORT="${ZONIC_PUBLIC_PORT:-6769}"
STREAM_PORT="${ZONIC_STREAM_PORT:-8090}"
GATE_PORT="${ZONIC_GATE_PORT:-8091}"
IDLE_MINUTES="${ZONIC_IDLE_MINUTES:-10}"
USER_NAME="${ZONIC_USER:-jacob}"
CONTAINER="${ZONIC_CONTAINER:-zonic-session}"
DOMAIN="${ZONIC_DOMAIN:-}"

say "installing caddy if it is missing"
if [ ! -x /usr/local/bin/caddy ]; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64 | amd64) CADDY_ARCH=amd64 ;;
    aarch64 | arm64) CADDY_ARCH=arm64 ;;
    *) die "no caddy build picked for $ARCH" ;;
  esac
  curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=${CADDY_ARCH}" \
    -o /usr/local/bin/caddy
  chmod 0755 /usr/local/bin/caddy
fi
/usr/local/bin/caddy version >/dev/null || die "caddy will not run"

say "hashing the password"
HASH_FILE="$CONF_DIR/password.hash"
if [ -s "$HASH_FILE" ]; then
  HASH="$(cat "$HASH_FILE")"
  say "keeping the password already set (delete $HASH_FILE to change it)"
else
  read -r -s -p "choose a password for $USER_NAME: " PASS_A; echo
  read -r -s -p "again: " PASS_B; echo
  [ "$PASS_A" = "$PASS_B" ] || die "those do not match"
  [ "${#PASS_A}" -ge 10 ] || die "use at least 10 characters"
  HASH="$(/usr/local/bin/caddy hash-password --plaintext "$PASS_A")"
  printf '%s' "$HASH" >"$HASH_FILE"
  chmod 0600 "$HASH_FILE"
fi

say "writing the service environment"
cat >"$CONF_DIR/env" <<EOF
ZONIC_PUBLIC_PORT=$PUBLIC_PORT
ZONIC_DOMAIN=$DOMAIN
ZONIC_STREAM_PORT=$STREAM_PORT
ZONIC_GATE_PORT=$GATE_PORT
ZONIC_USER=$USER_NAME
ZONIC_IDLE_MINUTES=$IDLE_MINUTES
ZONIC_CONTAINER=$CONTAINER
ZONIC_STATE=$STATE_DIR
ZONIC_MARKER=$SERVER/data/state/disconnected
ZONIC_COMPOSE=$SERVER/docker-compose.yml
ZONIC_SERVICE=session
EOF
chmod 0644 "$CONF_DIR/env"

say "rendering the caddyfile"
CONF_FILE="$CONF_DIR/Caddyfile"
python3 "$SERVER/caddy/render.py" \
  --template "$SERVER/caddy/Caddyfile.template" \
  --env "$CONF_DIR/env" \
  --hash "$HASH_FILE" \
  --out "$CONF_FILE"
/usr/local/bin/caddy fmt --overwrite "$CONF_FILE" >/dev/null

say "installing the services"
install -m 0644 "$SERVER/caddy/caddy.service" /etc/systemd/system/caddy.service
for unit in zonic-gate.service zonic-idle.service zonic-idle.timer; do
  sed "s#/opt/zonic/server#$SERVER#g; s#/opt/zonic#$REPO#g" \
    "$SERVER/host/$unit" >"/etc/systemd/system/$unit"
done

systemctl daemon-reload
/usr/local/bin/caddy validate --config "$CONF_FILE" --adapter caddyfile >/dev/null
systemctl enable caddy.service >/dev/null 2>&1
systemctl restart caddy.service || true

# A config that validates can still fail to start, and systemd's own message says nothing
# useful. The usual cause is a port already in use, so say that instead of "job failed".
if ! systemctl is-active --quiet caddy.service; then
  echo
  echo "caddy did not start. Last lines from its log:"
  journalctl -u caddy.service -n 12 --no-pager -o cat | sed 's/^/    /'
  echo
  if [ -n "$DOMAIN" ]; then
    echo "  With ZONIC_DOMAIN set, caddy needs ports 80 and 443 to itself."
    echo "  Check what is holding them:  ss -ltnp | grep -E ':(80|443) '"
    echo "  If something else owns them, either free them or drop ZONIC_DOMAIN from"
    echo "  $SERVER/.env and use the plain port instead."
  else
    echo "  Check what is holding port $PUBLIC_PORT:  ss -ltnp | grep ':$PUBLIC_PORT '"
    echo "  Pick a free one in $SERVER/.env and run this again."
  fi
  die "caddy is not running"
fi
systemctl enable --now zonic-gate.service >/dev/null
systemctl restart zonic-gate.service
systemctl enable --now zonic-idle.timer >/dev/null

say "done"
if [ -n "$DOMAIN" ]; then
  URL="https://$DOMAIN"
  FORWARD="Forward 443 and 80 to this box. Caddy gets the certificate itself."
else
  URL="http://<this-box>:$PUBLIC_PORT"
  FORWARD="Forward $PUBLIC_PORT to this box, or put a tunnel in front of it. There is no TLS on this port."
fi

cat <<EOF

  Session port  127.0.0.1:$STREAM_PORT (loopback only, Caddy is the door)
  Settings      $URL/settings
  Password      user $USER_NAME, the one you set

  $FORWARD
  Nothing starts until you ask it to: open /settings, hit Start, then open /.
  The session stops itself $IDLE_MINUTES minutes after the last client leaves.

  Useful commands:
    docker compose -f $SERVER/docker-compose.yml logs -f session
    journalctl -u zonic-gate -f
    systemctl list-timers zonic-idle.timer

EOF
