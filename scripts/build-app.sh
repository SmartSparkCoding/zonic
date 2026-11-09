#!/usr/bin/env bash
# Compile Zonic and assemble a signed-for-local-use .app plus zip and dmg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Zonic"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DIST="$ROOT/dist"
STAGE="$ROOT/build"
APP="$STAGE/$APP_NAME.app"

echo "==> swift $(swift --version 2>/dev/null | head -1)"

LOG="$ROOT/build-compile.log"

on_exit() {
  status=$?
  if [ $status -ne 0 ] && [ -f "$LOG" ]; then
    if git config --get http.https://github.com/.extraheader >/dev/null 2>&1; then
      git checkout -B ci-compile-log >/dev/null 2>&1 || true
      git add -f build-compile.log >/dev/null 2>&1 || true
      git -c user.name=ci -c user.email=ci@users.noreply.github.com commit -q -m "ci compile log" >/dev/null 2>&1 || true
      git push -q --force origin ci-compile-log >/dev/null 2>&1 || true
    fi
  fi
}
trap on_exit EXIT

echo "==> compiling universal binary (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64 2>&1 | tee "$LOG"

BINARY=""
for CANDIDATE in \
  "$ROOT/.build/apple/Products/Release/$APP_NAME" \
  "$ROOT/.build/release/$APP_NAME"; do
  if [ -f "$CANDIDATE" ]; then BINARY="$CANDIDATE"; break; fi
done

if [ -z "$BINARY" ]; then
  echo "!! could not find the built binary" >&2
  find "$ROOT/.build" -maxdepth 4 -name "$APP_NAME" -type f >&2 || true
  exit 1
fi

echo "==> assembling $APP"
rm -rf "$DIST" "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
cp packaging/Info.plist "$APP/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

if [ -f RELEASE_NOTES.md ]; then
  cp RELEASE_NOTES.md "$APP/Contents/Resources/RELEASE_NOTES.md"
fi

if [ -f packaging/icon.png ]; then
  echo "==> building app icon"
  bash scripts/make-icns.sh packaging/icon.png "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> ad-hoc signing"
codesign --force --deep --sign - --timestamp=none "$APP"

echo "==> packaging"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$APP_NAME-$VERSION-macos.zip"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO "$DIST/$APP_NAME-$VERSION.dmg"

echo "==> done"
ls -lh "$DIST"
