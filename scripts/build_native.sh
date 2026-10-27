#!/bin/bash
# Internal qualification product. Does not replace output/Sevra.app or install it.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[ "$(uname -m)" = arm64 ] || { echo 'The native candidate requires Apple Silicon.' >&2; exit 1; }
export SEVRA_NATIVE_CANDIDATE=1
CONFIG=${SEVRA_CONFIGURATION:-release}
JOBS=${SEVRA_BUILD_JOBS:-4}
SCRATCH="$ROOT/.build/native-product"
python3 scripts/generate_brand.py --check
python3 scripts/fetch_splash.py
python3 scripts/build_guidance.py
swift build --scratch-path "$SCRATCH" -c "$CONFIG" --product SevraDesktop -j "$JOBS"
swift build --scratch-path "$SCRATCH" -c "$CONFIG" --product sevra -j "$JOBS"
BIN=$(swift build --scratch-path "$SCRATCH" -c "$CONFIG" --show-bin-path)
python3 scripts/package_native.py "$BIN" "$SCRATCH"
