#!/usr/bin/env bash
# Build an .icns from a 1024x1024 png using the macOS tooling.
set -euo pipefail

SOURCE="${1:?usage: make-icns.sh source.png output.icns}"
OUTPUT="${2:?usage: make-icns.sh source.png output.icns}"

WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

for SIZE in 16 32 64 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$WORK"
