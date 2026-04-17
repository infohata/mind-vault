#!/usr/bin/env bash
# Setup Cursor user-level symlinks to mind-vault (skills, commands, agents, rules).
# Single source of truth: edit in mind-vault, all tools see updates.
# Requires: Cursor 2.4+ (verified through 3.x — user-level paths unchanged).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_symlink-lib.sh"
mv_resolve_root

CURSOR="$HOME/.cursor"
mkdir -p "$CURSOR"

echo "Setting up Cursor symlinks from $MV"
echo ""

mv_link_skills_per_dir "$CURSOR/skills"
echo ""

mv_link_tree commands "$CURSOR/commands"
echo ""

mv_link_tree agents "$CURSOR/agents"
echo ""

# Rules: Cursor project rules use .cursor/rules/; User Rules live in Settings.
# Symlink ~/.cursor/rules for projects that reference it and for future Cursor support.
mv_link_tree rules "$CURSOR/rules"
echo ""

echo "Done. Restart Cursor or reload window (Cmd+Shift+P → Developer: Reload Window) to rescan."
echo ""
echo "Verify: Cursor Settings → Rules → Agent Decides (skills), /commands in chat"
