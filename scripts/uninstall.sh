#!/bin/bash
set -euo pipefail
APP_TARGET=${SEVRA_APP_INSTALL_DIR:-"$HOME/Applications"}
CLI_TARGET=${SEVRA_CLI_INSTALL_DIR:-"$HOME/.local/bin"}
TRASH=${SEVRA_UNINSTALL_TRASH_DIR:-"$HOME/.Trash"}
APP="$APP_TARGET/Sevra.app"
LINK="$CLI_TARGET/sevra"
if [ -e "$APP" ]; then
  [ ! -L "$APP" ] || { echo 'Refusing a symlinked application.' >&2; exit 1; }
  ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)
  [ "$ID" = com.sevra.workbooks ] || { echo 'This is not the Sevra workbook app.' >&2; exit 1; }
  mkdir -p "$TRASH"
  DEST="$TRASH/Sevra-$(date +%Y%m%d-%H%M%S)-$$.app"
  mv "$APP" "$DEST"
  echo "Moved app to $DEST"
fi
if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$APP/Contents/CLI/sevra" ]; then rm "$LINK"; fi
echo 'Your workbooks, preferences and downloaded model remain.'
