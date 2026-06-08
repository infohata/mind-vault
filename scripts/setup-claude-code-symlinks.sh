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

# Best-effort double-load guard (IDEA-017, Q4). On a single CC machine use the
# plugin OR this symlink script, not both — running both double-loads every
# skill/command/agent. This warning is BEST-EFFORT and ONE-DIRECTIONAL: it only
# catches the plugin-then-script order (plugin already installed when you run
# this). The script-then-plugin order is unguardable (`/plugin install` has no
# hook here), and the `--plugin-dir` / `@skills-dir` dev-loop does NOT register
# under ~/.claude/plugins, so a dev deliberately running both is correctly exempt.
mv_plugin_dir="$CLAUDE/plugins"
if [[ -d "$mv_plugin_dir" ]] && grep -rqs -e '"name": *"mv"' -e 'mind-vault' "$mv_plugin_dir" 2>/dev/null; then
    echo "⚠️  Best-effort warning: the mind-vault plugin appears already installed"
    echo "    (found under $mv_plugin_dir). Running this symlink script too will"
    echo "    DOUBLE-LOAD every skill/command/agent on this machine. Use ONE channel"
    echo "    per machine — the plugin (/plugin) OR this script, not both. Continuing."
    echo "    (Dev-loop via --plugin-dir / @skills-dir is exempt and won't trip this.)"
    echo ""
fi

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
statusline_src="$(cd "$MV/tools" && pwd)/statusline-command.sh"
statusline_dst="$CLAUDE/statusline-command.sh"
if [[ -f "$statusline_src" ]]; then
    if [[ -L "$statusline_dst" ]]; then
        ln -sfn "$statusline_src" "$statusline_dst"
        echo "statusline: $statusline_dst -> mind-vault/tools/statusline-command.sh (updated)"
    elif [[ -e "$statusline_dst" ]]; then
        echo "statusline: $statusline_dst exists as non-symlink (skip — rm and re-run to adopt the mind-vault version)"
    else
        ln -s "$statusline_src" "$statusline_dst"
        echo "statusline: $statusline_dst -> mind-vault/tools/statusline-command.sh (linked)"
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
