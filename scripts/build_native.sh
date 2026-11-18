#!/bin/bash
# Builds the isolated qualification app or a standalone distribution image.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[ "$(uname -m)" = arm64 ] || { echo 'The native candidate requires Apple Silicon.' >&2; exit 1; }
export SEVRA_NATIVE_CANDIDATE=1
CONFIG=${SEVRA_CONFIGURATION:-release}
JOBS=${SEVRA_BUILD_JOBS:-4}
SCRATCH="$ROOT/.build/native-product"
DISTRIBUTION=0
if [ "${1:-}" = --distribution ]; then
  DISTRIBUTION=1
  shift
  CONFIG=release
  SEVRA_SPARKLE_FRAMEWORK_DIR=$(python3 scripts/sparkle_release.py prepare)
  export SEVRA_SPARKLE_FRAMEWORK_DIR
elif [ "$#" -ne 0 ]; then
  echo 'Usage: build_native.sh [--distribution RELEASE_OPTIONS]' >&2
  exit 2
else
  unset SEVRA_SPARKLE_FRAMEWORK_DIR
fi
python3 scripts/generate_brand.py --check
python3 scripts/fetch_splash.py
python3 scripts/build_guidance.py
swift build --scratch-path "$SCRATCH" -c "$CONFIG" --product SevraDesktop -j "$JOBS"
swift build --scratch-path "$SCRATCH" -c "$CONFIG" --product sevra -j "$JOBS"
swift build --scratch-path "$SCRATCH" -c "$CONFIG" --product sevra-extract -j "$JOBS"
swift build --scratch-path "$SCRATCH" -c "$CONFIG" --product sevra-app-worker -j "$JOBS"
BIN=$(swift build --scratch-path "$SCRATCH" -c "$CONFIG" --show-bin-path)
if [ "$DISTRIBUTION" = 1 ]; then
  python3 scripts/package_release.py "$BIN" "$SCRATCH" "$@"
else
  python3 scripts/package_native.py "$BIN" "$SCRATCH"
fi
