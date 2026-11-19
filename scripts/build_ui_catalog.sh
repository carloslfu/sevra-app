#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export SEVRA_UI_CATALOG=1
CONFIG=${SEVRA_CONFIGURATION:-debug}
JOBS=${SEVRA_BUILD_JOBS:-4}
SCRATCH="$ROOT/.build/ui-catalog"
python3 scripts/fetch_splash.py
python3 scripts/build_guidance.py
for PRODUCT in SevraDesktop sevra-app-worker sevra-extract; do
  swift build --scratch-path "$SCRATCH" -c "$CONFIG" --product "$PRODUCT" -j "$JOBS"
done
BIN=$(swift build --scratch-path "$SCRATCH" -c "$CONFIG" --show-bin-path)
python3 scripts/package_ui_catalog.py "$BIN"
