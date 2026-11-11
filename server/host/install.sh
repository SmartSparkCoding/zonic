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

PUBLIC_PORT="${ZONIC_PUBLIC_PORT:-8080}"
STREAM_PORT="${ZONIC_STREAM_PORT:-8090}"
GATE_PORT="${ZONIC_GATE_PORT:-8091}"
IDLE_MINUTES="${ZONIC_IDLE_MINUTES:-10}"
USER_NAME="${ZONIC_USER:-jacob}"
CONTAINER="${ZONIC_CONTAINER:-zonic-session}"

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
python3 - "$SERVER/caddy/Caddyfile.template" "$CONF_DIR/Caddyfile" <<'PY'
import sys

template, target = sys.argv[1], sys.argv[2]
text = open(template, encoding="utf-8").read()
values = {}
for line in open("/etc/zonic/env", encoding="utf-8"):
    if "=" in line:
        key, value = line.rstrip("\n").split("=", 1)
        values[key] = value
replacement = {
    "__PUBLIC_PORT__": values.get("ZONIC_PUBLIC_PORT", "8080"),
    "__STREAM_PORT__": values.get("ZONIC_STREAM_PORT", "8090"),
    "__GATE_PORT__": values.get("ZONIC_GATE_PORT", "8091"),
    "__USER__": values.get("ZONIC_USER", "jacob"),
    "__HASH__": open("/etc/zonic/password.hash", encoding="utf-8").read().strip(),
}
for key, value in replacement.items():
    text = text.replace(key, value)
open(target, "w", encoding="utf-8").write(text)
PY

say "installing the services"
install -m 0644 "$SERVER/caddy/caddy.service" /etc/systemd/system/caddy.service
for unit in zonic-gate.service zonic-idle.service zonic-idle.timer; do
  sed "s#/opt/zonic/server#$SERVER#g; s#/opt/zonic#$REPO#g" \
    "$SERVER/host/$unit" >"/etc/systemd/system/$unit"
done

systemctl daemon-reload
/usr/local/bin/caddy validate --config "$CONF_DIR/Caddyfile" --adapter caddyfile >/dev/null
systemctl enable --now caddy.service >/dev/null
systemctl restart caddy.service
systemctl enable --now zonic-gate.service >/dev/null
systemctl restart zonic-gate.service
systemctl enable --now zonic-idle.timer >/dev/null

say "done"
cat <<EOF

  Session port  127.0.0.1:$STREAM_PORT (loopback only, Caddy is the door)
  Settings      http://127.0.0.1:$PUBLIC_PORT/settings
  Password      user $USER_NAME, the one you just typed

  Point Nest's reverse proxy or your tunnel at port $PUBLIC_PORT.
  Nothing starts until you ask it to: open /settings, hit Start, then open /.
  The session stops itself $IDLE_MINUTES minutes after the last client leaves.

  Useful commands:
    docker compose -f $SERVER/docker-compose.yml logs -f session
    journalctl -u zonic-gate -f
    systemctl list-timers zonic-idle.timer

EOF
