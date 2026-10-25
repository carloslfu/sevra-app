#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
case "${1:-}" in
  codex) TARGET="${SEVRA_SKILL_ROOT:-$HOME/.codex/skills}/sevra" ;;
  claude) TARGET="${SEVRA_SKILL_ROOT:-$HOME/.claude/skills}/sevra" ;;
  *) echo 'Usage: scripts/install_skill.sh codex|claude' >&2; exit 1 ;;
esac
if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
  echo "A skill already exists at $TARGET. Review it before replacing it." >&2
  exit 1
fi
mkdir -p "$(dirname "$TARGET")"
ditto "$ROOT/skills/sevra" "$TARGET"
echo "Installed skill at $TARGET"
