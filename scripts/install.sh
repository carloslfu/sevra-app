#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=1
for ARG in "$@"; do
  case "$ARG" in
    --no-build) BUILD=0 ;;
    *) echo 'Usage: install.sh [--no-build]' >&2; exit 2 ;;
  esac
done
NAME='Sevra Native Preview'
BUNDLE_ID=com.sevra.workbooks.native-preview
PRODUCT="$ROOT/output/native"
[ "$(uname -m)" = arm64 ] || { echo 'Sevra requires Apple Silicon.' >&2; exit 1; }
if [ "$BUILD" = 1 ]; then "$ROOT/scripts/build_native.sh"; fi
[ -d "$PRODUCT/$NAME.app" ] && [ -x "$PRODUCT/bin/sevra" ] || {
  echo 'Build the app before using --no-build.' >&2; exit 1;
}
APP_TARGET=${SEVRA_APP_INSTALL_DIR:-"$HOME/Applications"}
CLI_TARGET=${SEVRA_CLI_INSTALL_DIR:-"$HOME/.local/bin"}
APP="$APP_TARGET/$NAME.app"
LINK="$CLI_TARGET/sevra"
mkdir -p "$APP_TARGET" "$CLI_TARGET"
if [ -e "$APP" ] || [ -L "$APP" ]; then
  [ ! -L "$APP" ] || { echo 'Refusing to replace a symlinked app.' >&2; exit 1; }
  ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)
  [ "$ID" = "$BUNDLE_ID" ] || { echo 'Refusing to replace an unrelated application.' >&2; exit 1; }
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
ditto "$PRODUCT/$NAME.app" "$STAGE/Sevra.app"
ditto "$PRODUCT/bin" "$STAGE/Sevra.app/Contents/CLI"
# Upstream helpers are already signed. --deep would change pinned engine bytes.
codesign --force --sign - "$STAGE/Sevra.app"
codesign --verify --deep --strict "$STAGE/Sevra.app"
"$STAGE/Sevra.app/Contents/CLI/sevra" version
"$STAGE/Sevra.app/Contents/CLI/sevra" check-resources --paths-only
if [ -d "$APP" ]; then mv "$APP" "$OLD"; fi
mv "$STAGE/Sevra.app" "$APP"
APP_MOVED=1
ln -sfn "$APP/Contents/CLI/sevra" "$LINK"
PUBLISHED=1
echo "Installed $APP"
echo "CLI: $LINK"
echo "Workbooks and model files were not changed."
