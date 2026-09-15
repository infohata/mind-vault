#!/usr/bin/env bash
# Setup Grok Build user-level symlinks to mind-vault (skills, commands, agents, rules).
# Single source of truth: edit in mind-vault, all tools see updates.
# Project-native .grok/{agents,skills} are committed separately; this wires ~/.grok/.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_symlink-lib.sh"
mv_resolve_root

GROK="${GROK_HOME:-$HOME/.grok}"
mkdir -p "$GROK"

echo "Setting up Grok Build symlinks from $MV → $GROK"
echo ""

mv_link_skills_per_dir "$GROK/skills"
echo ""

mv_link_tree commands "$GROK/commands"
echo ""

mv_link_tree agents "$GROK/agents"
echo ""

mv_link_tree rules "$GROK/rules"
echo ""

# Rule rationale: rules link out via `../docs/rules/<rule>-rationale.md` relative
# paths. Symlinking docs/rules alongside makes those relative paths resolve from
# ~/.grok/rules/.
mv_link_tree docs/rules "$GROK/docs/rules"
echo ""

echo "Done. Restart Grok Build or open a new session to rescan."
echo ""
echo "Verify: grok inspect  (skills / agents / rules cells)"
echo "Auth:   interactive login needs SuperGrok or X Premium+; CI uses XAI_API_KEY"
echo "Docs:   docs/GROK_BUILD.md"
