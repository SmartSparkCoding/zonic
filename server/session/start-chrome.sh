#!/bin/bash
# Opens Amazon Music as a chromeless window, which is the whole session as far as you are
# concerned. Started by the LXQt autostart entry next to it.
set -u

URL="${ZONIC_URL:-https://music.amazon.com/}"

# The image installs Google Chrome, but the binary name has moved before; find it rather
# than hardcoding one and ending up with an empty desktop.
CHROME=""
for candidate in google-chrome google-chrome-stable google-chrome-beta chromium; do
  if command -v "$candidate" >/dev/null 2>&1; then
    CHROME="$candidate"
    break
  fi
done

if [ -z "$CHROME" ]; then
  notify-send "Zonic" "No Chrome in this container, nothing to open." 2>/dev/null
  exit 1
fi

# --no-sandbox is required: a container's default seccomp profile gives Chrome neither the
# setuid helper's capabilities nor unprivileged user namespaces. The container is the
# isolation boundary instead.
#
# --app drops the address bar and tabs, so it reads as a music client rather than a
# browser someone left open.
exec "$CHROME" \
  --no-sandbox \
  --app="$URL" \
  --start-maximized \
  --no-first-run \
  --no-default-browser-check \
  --disable-features=Translate,ChromeWhatsNewUI,MediaRouter \
  --autoplay-policy=no-user-gesture-required
