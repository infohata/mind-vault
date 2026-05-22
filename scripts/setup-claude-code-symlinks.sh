#!/usr/bin/env bash
# Setup Claude Code user-level symlinks to mind-vault (skills, commands, agents, rules).
# Single source of truth: edit in mind-vault, Claude Code sees updates.
# Works with Claude Code CLI, IDE extensions (VS Code, JetBrains), and Desktop app.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_symlink-lib.sh"
mv_resolve_root

CLAUDE="$HOME/.claude"
mkdir -p "$CLAUDE"

echo "Setting up Claude Code symlinks from $MV"
echo ""

mv_link_skills_per_dir "$CLAUDE/skills"
echo ""

mv_link_tree commands "$CLAUDE/commands"
echo ""

mv_link_tree agents "$CLAUDE/agents"
echo ""

# Rules: Claude Code doesn't natively discover rules files; they're surfaced via
# ~/.claude/CLAUDE.md content references. Symlink keeps the reference path stable.
mv_link_tree rules "$CLAUDE/rules"
echo ""

# Rule rationale: rules link out via `../docs/rules/<rule>-rationale.md` relative
# paths to keep always-loaded rule bodies short. Symlinking docs/rules alongside
# makes those relative paths resolve from ~/.claude/rules/.
mv_link_tree docs/rules "$CLAUDE/docs/rules"
echo ""

# Status line: single file (not a tree). Symlink directly so edits in mind-vault
# propagate to ~/.claude/statusline-command.sh. Claude Code invokes it per the
# "statusLine" entry in ~/.claude/settings.json (see snippet below).
#
# Canonicalize the source path to an absolute path before linking (mirrors
# `_symlink-lib.sh:mv_link_tree`'s `$(cd "$MV/$subdir" && pwd)` pattern for the
# directory case) — otherwise a relative MIND_VAULT env var produces a relative
# symlink target that fails to resolve from ~/.claude/.
statusline_src="$(cd "$MV/scripts" && pwd)/statusline-command.sh"
statusline_dst="$CLAUDE/statusline-command.sh"
if [[ -f "$statusline_src" ]]; then
    if [[ -L "$statusline_dst" ]]; then
        ln -sfn "$statusline_src" "$statusline_dst"
        echo "statusline: $statusline_dst -> mind-vault/scripts/statusline-command.sh (updated)"
    elif [[ -e "$statusline_dst" ]]; then
        echo "statusline: $statusline_dst exists as non-symlink (skip — rm and re-run to adopt the mind-vault version)"
    else
        ln -s "$statusline_src" "$statusline_dst"
        echo "statusline: $statusline_dst -> mind-vault/scripts/statusline-command.sh (linked)"
    fi
fi
echo ""

echo "Done. Start a new Claude Code session to pick up changes."
echo ""
echo "Verify:"
echo "  - Skills: /help should list mind-vault skills; or ask 'what skills are available?'"
echo "  - Commands: /<command-name> autocomplete in chat"
echo "  - Agents: Agent tool's subagent_type picker should include AGENT_* personas"
echo "  - Status line: add this to ~/.claude/settings.json (top-level key) if missing,"
echo "    then restart Claude Code:"
echo ''
echo '      "statusLine": {'
echo '        "type": "command",'
echo '        "command": "bash ~/.claude/statusline-command.sh"'
echo '      }'
