#!/usr/bin/env bash
# Remove the herklaude-skills symlink from ~/.claude/skills/.
#
# Leaves this repo untouched; only the link is removed. Thin wrapper around
# `install.sh --uninstall`, which holds the actual logic.

set -euo pipefail

exec "$(dirname "${BASH_SOURCE[0]}")/install.sh" --uninstall
