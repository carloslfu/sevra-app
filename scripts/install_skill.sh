#!/bin/bash
# Install or update the sevra agent skill for Codex or Claude Code. The skill is a pointer to
# `sevra agent`, which prints the guide from the installed CLI, so installing it is optional.
# An earlier Sevra skill at the target is replaced, after a copy is kept outside the skills
# folder so the agent does not load it twice. Anything else at the target is left alone.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
case "${1:-}" in
  codex) TARGET="${SEVRA_SKILL_ROOT:-$HOME/.codex/skills}/sevra" ;;
  claude) TARGET="${SEVRA_SKILL_ROOT:-$HOME/.claude/skills}/sevra" ;;
  *) echo 'Usage: scripts/install_skill.sh codex|claude' >&2; exit 1 ;;
esac
SOURCE="$ROOT/skills/sevra"
if [ -L "$TARGET" ] || { [ -e "$TARGET" ] && ! [ -d "$TARGET" ]; }; then
  echo "$TARGET is not a skill folder. Review it before replacing it." >&2
  exit 1
fi
if [ -d "$TARGET" ]; then
  if ! grep -qx 'name: sevra' "$TARGET/SKILL.md" 2>/dev/null; then
    echo "A different skill is installed at $TARGET. Review it before replacing it." >&2
    exit 1
  fi
  if diff -rq "$SOURCE" "$TARGET" >/dev/null; then
    echo "The skill at $TARGET is up to date."
    exit 0
  fi
  KEPT="${TMPDIR:-/tmp}"; KEPT=$(mktemp -d "${KEPT%/}/sevra-skill-previous.XXXXXX")
  ditto "$TARGET" "$KEPT/sevra"
  rm -rf "$TARGET"
  ditto "$SOURCE" "$TARGET"
  echo "Updated the skill at $TARGET. The previous copy is in $KEPT/sevra."
  exit 0
fi
mkdir -p "$(dirname "$TARGET")"
ditto "$SOURCE" "$TARGET"
echo "Installed skill at $TARGET"
