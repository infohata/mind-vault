#!/usr/bin/env bash
# Setup Cursor user-level symlinks to mind-vault (skills, commands, agents, rules)
# Single source of truth: edit in mind-vault, all tools see updates.
# Requires: Cursor 2.4+

set -e

MV="${MIND_VAULT:-$HOME/projects/mind-vault}"
CURSOR="$HOME/.cursor"

if [[ ! -d "$MV" ]]; then
  echo "Error: mind-vault not found at $MV"
  echo "Set MIND_VAULT env var or clone to ~/projects/mind-vault"
  exit 1
fi

echo "Setting up Cursor symlinks from $MV"
echo ""

# Skills: Cursor loads from ~/.cursor/skills/ or ~/.claude/skills/
# Use per-skill symlinks to avoid Cursor's symlink discovery bug (parent dir symlink)
if [[ ! -d "$CURSOR/skills" ]]; then
  mkdir -p "$CURSOR/skills"
  echo "Created $CURSOR/skills/"
fi
for d in "$MV"/skills/*/; do
  [[ -d "$d" ]] || continue
  name=$(basename "$d")
  if [[ -L "$CURSOR/skills/$name" ]] || [[ -d "$CURSOR/skills/$name" ]]; then
    ln -sf "$(cd "$d" && pwd)" "$CURSOR/skills/$name"
    echo "  Updated skills/$name"
  else
    ln -s "$(cd "$d" && pwd)" "$CURSOR/skills/$name"
    echo "  Linked skills/$name"
  fi
done
echo "Skills: $CURSOR/skills -> mind-vault/skills/*"
echo ""

# Commands: Cursor loads from ~/.cursor/commands/
if [[ -L "$CURSOR/commands" ]]; then
  rm "$CURSOR/commands"
fi
if [[ ! -e "$CURSOR/commands" ]]; then
  ln -s "$(cd "$MV/commands" && pwd)" "$CURSOR/commands"
  echo "Commands: $CURSOR/commands -> mind-vault/commands"
else
  echo "Commands: $CURSOR/commands exists (skip)"
fi
echo ""

# Agents (subagents): Cursor loads from ~/.cursor/agents/
if [[ -L "$CURSOR/agents" ]] || [[ ! -e "$CURSOR/agents" ]]; then
  ln -sf "$(cd "$MV/agents" && pwd)" "$CURSOR/agents"
  echo "Agents: $CURSOR/agents -> mind-vault/agents"
else
  echo "Agents: $CURSOR/agents exists (skip)"
fi
echo ""

# Rules: Cursor project rules use .cursor/rules/; User Rules are in Settings.
# Symlink ~/.cursor/rules for projects that might reference it, or future Cursor support.
if [[ -L "$CURSOR/rules" ]] || [[ ! -e "$CURSOR/rules" ]]; then
  ln -sf "$(cd "$MV/rules" && pwd)" "$CURSOR/rules"
  echo "Rules: $CURSOR/rules -> mind-vault/rules (reference; User Rules are in Cursor Settings)"
else
  echo "Rules: $CURSOR/rules exists (skip)"
fi
echo ""

echo "Done. Restart Cursor or reload window (Cmd+Shift+P → Developer: Reload Window) to rescan."
echo ""
echo "Verify: Cursor Settings → Rules → Agent Decides (skills), /commands in chat"
