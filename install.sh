#!/usr/bin/env bash
# Install herklaude-skills as a user-level Claude Code skill, without going
# through the plugin marketplace.
#
# Symlinks ~/.claude/skills/herklaude-skills -> skills/herklaude-skills in
# this repo, so edits to the notes apply with no reinstall. Prefer this over
# the marketplace when the knowledge base is yours and you edit it often.
#
#   ./install.sh              install or repair the symlink
#   ./install.sh --uninstall  remove it (same as ./uninstall.sh)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${REPO}/skills/herklaude-skills"
DEST="${HOME}/.claude/skills/herklaude-skills"

if [ "${1:-}" = "--uninstall" ]; then
  if [ -L "$DEST" ]; then
    rm "$DEST"
    echo "removed $DEST"
    echo "the notes in $REPO are untouched"
  elif [ -e "$DEST" ]; then
    echo "refusing: $DEST exists but is not a symlink. Remove it by hand." >&2
    exit 1
  else
    echo "nothing to remove at $DEST"
  fi
  exit 0
fi

if [ ! -f "${SRC}/SKILL.md" ]; then
  echo "refusing: no SKILL.md under $SRC" >&2
  exit 1
fi

if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "refusing: $DEST exists and is not a symlink. Remove it by hand." >&2
  exit 1
fi

mkdir -p "$(dirname "$DEST")"
ln -sfn "$SRC" "$DEST"

echo "linked $DEST -> $SRC"
echo "knowledge base: $REPO"
echo
echo "Verify with /herklaude-skills in a new Claude Code session."
