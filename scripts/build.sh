#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
python3 scripts/generate_brand.py --check
CONFIG=${SEVRA_CONFIGURATION:-release}
JOBS=${SEVRA_BUILD_JOBS:-4}
[ "$(uname -m)" = arm64 ] || { echo 'Sevra currently requires Apple Silicon.' >&2; exit 1; }
swift build -c "$CONFIG" -j "$JOBS"
BIN=$(swift build -c "$CONFIG" --show-bin-path)
METAL="$ROOT/.build/metal/mlx.metallib"
OUT="$METAL" /bin/bash "$ROOT/.build/checkouts/slotstream/Tools/fetch_metallib.sh"
cp "$METAL" "$BIN/mlx.metallib"
APP="$ROOT/output/Sevra.app"
if [ -d "$APP" ]; then rm -rf "$APP"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/output/bin"
cp "$BIN/SevraDesktop" "$APP/Contents/MacOS/Sevra"
cp "$BIN/sevra" "$ROOT/output/bin/sevra"
cp "$METAL" "$APP/Contents/MacOS/mlx.metallib"
cp "$METAL" "$ROOT/output/bin/mlx.metallib"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Sevra.icns "$APP/Contents/Resources/Sevra.icns"
for bundle in "$BIN/"*.bundle; do
  [ -d "$bundle" ] || continue
  # All app resources stay in the standard sealed macOS resource location.
  ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
  ditto "$bundle" "$ROOT/output/bin/$(basename "$bundle")"
done
python3 "$ROOT/scripts/licenses.py"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
echo "CLI: $ROOT/output/bin/sevra"
