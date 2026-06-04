#!/usr/bin/env bash
# Setup OpenCode user-level symlinks to mind-vault (skills, commands, agents, rules).
# Single source of truth: edit in mind-vault, OpenCode sees updates.
# Uses XDG path (~/.config/opencode/). If your install prefers ~/.opencode/,
# set OPENCODE_HOME=~/.opencode before invoking.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_symlink-lib.sh"
mv_resolve_root

OC="${OPENCODE_HOME:-$HOME/.config/opencode}"
mkdir -p "$OC"

echo "Setting up OpenCode symlinks from $MV into $OC"
echo ""

# Skills: OpenCode requires strict naming (^[a-z0-9]+(-[a-z0-9]+)*$) per directory.
# Per-skill symlinks so each is validated independently.
mv_link_skills_per_dir "$OC/skills"
echo ""

mv_link_tree commands "$OC/commands"
echo ""

mv_link_tree agents "$OC/agents"
echo ""

# Rules: no native rules discovery at the time of writing; symlink for future support.
mv_link_tree rules "$OC/rules"
echo ""

# Rule rationale: rules link out via `../docs/rules/<rule>-rationale.md` relative
# paths to keep always-loaded rule bodies short. Symlinking docs/rules alongside
# makes those relative paths resolve from the symlinked rules location.
mv_link_tree docs/rules "$OC/docs/rules"
echo ""

echo "Done. Restart OpenCode sessions to pick up changes."
echo ""
echo "Verify: invoke the 'skill' tool in OpenCode; mind-vault skills should appear in the list"
