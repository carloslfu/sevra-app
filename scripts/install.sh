#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [ "${1:-}" != --no-build ]; then "$ROOT/scripts/build.sh"; fi
APP_TARGET=${SEVRA_APP_INSTALL_DIR:-"$HOME/Applications"}
CLI_TARGET=${SEVRA_CLI_INSTALL_DIR:-"$HOME/.local/bin"}
APP="$APP_TARGET/Sevra.app"
LINK="$CLI_TARGET/sevra"
mkdir -p "$APP_TARGET" "$CLI_TARGET"
if [ -e "$APP" ] || [ -L "$APP" ]; then
  [ ! -L "$APP" ] || { echo 'Refusing to replace a symlinked app.' >&2; exit 1; }
  ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)
  [ "$ID" = com.sevra.workbooks ] || { echo 'Refusing to replace an unrelated application.' >&2; exit 1; }
fi
if [ -e "$LINK" ] || [ -L "$LINK" ]; then
  [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$APP/Contents/CLI/sevra" ] || {
    echo "Refusing to replace an unrelated CLI at $LINK." >&2; exit 1;
  }
fi
STAGE=$(mktemp -d "$APP_TARGET/.sevra-install.XXXXXX")
OLD="$STAGE/previous.app"
PUBLISHED=0
APP_MOVED=0
cleanup() {
  if [ "$PUBLISHED" = 0 ]; then
    if [ "$APP_MOVED" = 1 ] && [ -d "$APP" ]; then mv "$APP" "$STAGE/failed.app"; fi
    if [ -d "$OLD" ] && [ ! -e "$APP" ]; then mv "$OLD" "$APP"; fi
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT
ditto "$ROOT/output/Sevra.app" "$STAGE/Sevra.app"
ditto "$ROOT/output/bin" "$STAGE/Sevra.app/Contents/CLI"
codesign --force --deep --sign - "$STAGE/Sevra.app"
codesign --verify --deep --strict "$STAGE/Sevra.app"
"$STAGE/Sevra.app/Contents/CLI/sevra" version
if [ -d "$APP" ]; then mv "$APP" "$OLD"; fi
mv "$STAGE/Sevra.app" "$APP"
APP_MOVED=1
ln -sfn "$APP/Contents/CLI/sevra" "$LINK"
PUBLISHED=1
echo "Installed $APP"
echo "CLI: $LINK"
echo "Workbooks and model files were not changed."
