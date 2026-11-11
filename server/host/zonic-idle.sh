#!/usr/bin/env bash
# Stops the session once nobody has been connected for a while.
#
# The session itself tells us when the last client left: Selkies runs
# SELKIES_RUN_AFTER_DISCONNECT, which touches the marker file, and
# SELKIES_RUN_AFTER_CONNECT, which deletes it. So this only has to look at one file and
# its age, which is a lot less fragile than guessing from sockets or traffic counters.
#
# Run from a systemd timer, once a minute.
set -euo pipefail

STATE_DIR="${ZONIC_STATE:-/var/lib/zonic}"
MARKER="${ZONIC_MARKER:-/opt/zonic/server/data/state/disconnected}"
CONTAINER="${ZONIC_CONTAINER:-zonic-session}"
DEFAULT_IDLE="${ZONIC_IDLE_MINUTES:-10}"

mkdir -p "$STATE_DIR"

running="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)"
if [ "$running" != "true" ]; then
  rm -f "$MARKER"
  exit 0
fi

# No marker means a client is connected right now. Leave it alone.
[ -e "$MARKER" ] || exit 0

idle_minutes="$(cat "$STATE_DIR/idle_minutes" 2>/dev/null || echo "$DEFAULT_IDLE")"
case "$idle_minutes" in
  '' | *[!0-9]*) idle_minutes="$DEFAULT_IDLE" ;;
esac

now="$(date +%s)"
since="$(stat -c %Y "$MARKER" 2>/dev/null || echo "$now")"
idle=$(( now - since ))

if [ "$idle" -ge $(( idle_minutes * 60 )) ]; then
  docker stop "$CONTAINER" >/dev/null 2>&1 || true
  rm -f "$MARKER"
  printf '%s stopped after %ss idle\n' "$(date -Is)" "$idle" >>"$STATE_DIR/idle.log"
fi
