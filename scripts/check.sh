#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
swift build --product sevra-checks -j "${SEVRA_BUILD_JOBS:-4}"
BIN=$(swift build --show-bin-path)
"$BIN/sevra-checks"
python3 scripts/check_links.py
if command -v dbmd >/dev/null; then dbmd validate --all db --json; else echo 'dbmd is required for specification validation.' >&2; exit 1; fi
