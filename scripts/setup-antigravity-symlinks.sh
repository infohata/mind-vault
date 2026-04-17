#!/usr/bin/env bash
# Setup Google Antigravity symlinks to mind-vault.
#
# Antigravity is a VS Code fork:
#   ~/.antigravity/extensions/         VS Code-style extension packs
#   ~/.config/Antigravity/User/        VS Code-style user profile
#   ~/.gemini/antigravity/             Gemini brain / conversation data (not user config)
#
# There is no native user-level "skills" / "commands" / "agents" directory convention
# for Antigravity's built-in Gemini chat. To surface mind-vault inside Antigravity,
# use one of two extension paths:
#
#   (a) Claude Code extension (anthropic.claude-code-*) inside Antigravity
#       → reads from ~/.claude/ — run setup-claude-code-symlinks.sh (separate script).
#       This is typically the simpler option if you already use Claude Code.
#
#   (b) GitHub Copilot extension inside Antigravity
#       → reads prompts/instructions from ~/.config/Antigravity/User/*
#       → this script wires that path via the VS Code Copilot helper.
#
# You can use both (a) and (b) simultaneously — they don't conflict.
# Run setup-claude-code-symlinks.sh for (a), this script for (b).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

export VSCODE_USER="$HOME/.config/Antigravity/User"

if [[ ! -d "$VSCODE_USER" ]]; then
  echo "Error: Antigravity user directory not found at $VSCODE_USER"
  echo "  - Launch Antigravity at least once so it creates the profile dir."
  echo "  - Or adjust the path in this script / set VSCODE_USER manually."
  exit 1
fi

echo "Setting up Antigravity (VS Code fork) Copilot-style symlinks."
echo "Target: $VSCODE_USER"
echo ""
echo "Note: if you also use the Claude Code extension in Antigravity, also run:"
echo "  bash $SCRIPT_DIR/setup-claude-code-symlinks.sh"
echo ""

exec bash "$SCRIPT_DIR/setup-vscode-copilot-symlinks.sh"
