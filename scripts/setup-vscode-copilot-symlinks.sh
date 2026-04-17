#!/usr/bin/env bash
# Setup VS Code GitHub Copilot symlinks to mind-vault (best-effort).
#
# Copilot's file conventions:
#   prompts       -> ~/.config/Code/User/prompts/<name>.prompt.md
#   instructions  -> ~/.config/Code/User/instructions/<name>.instructions.md
#   chat modes    -> ~/.config/Code/User/chatmodes/<name>.chatmode.md
#
# ⚠️  Format caveats:
#   - Copilot expects .prompt.md / .instructions.md extensions (this script handles the rename).
#   - Copilot frontmatter schema (mode: ask|edit|agent, model:, tools:) differs from mind-vault's
#     (agent: general/test-engineer, etc.). Files will be discovered but frontmatter-specific
#     features (mode selection, model pinning) will not activate.
#   - Copilot has no native skill or subagent equivalent — skills/ and agents/ are NOT linked.
#
# For full Copilot fidelity, author .prompt.md files natively. This script exists to get
# mind-vault's command body text surfaced in VS Code Copilot chat at zero extra maintenance cost.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_symlink-lib.sh"
mv_resolve_root

# VS Code user dir. Override with VSCODE_USER for non-standard installs:
#   Linux   : ~/.config/Code/User                   (default)
#   macOS   : ~/Library/Application Support/Code/User
#   Windows : %APPDATA%\Code\User
#   Insiders: swap 'Code' for 'Code - Insiders'
VSC="${VSCODE_USER:-$HOME/.config/Code/User}"

if [[ ! -d "$VSC" ]]; then
  echo "Error: VS Code user directory not found at $VSC"
  echo "Set VSCODE_USER env var to point at your VS Code profile dir."
  exit 1
fi

echo "Setting up VS Code Copilot symlinks from $MV into $VSC"
echo "⚠️  Format mismatch: Copilot frontmatter schema differs from mind-vault's."
echo "    Files will be discovered; frontmatter-specific features may not activate."
echo ""

# Commands -> Copilot prompt files
mv_link_files_renamed commands "$VSC/prompts" .prompt
echo ""

# Rules -> Copilot instructions files
mv_link_files_renamed rules "$VSC/instructions" .instructions
echo ""

echo "Skills and agents: skipped — Copilot has no native equivalent."
echo ""
echo "Done. Reload VS Code (Cmd/Ctrl+Shift+P → Developer: Reload Window)."
echo ""
echo "Verify: /<command-name> should autocomplete in the Copilot chat box."
