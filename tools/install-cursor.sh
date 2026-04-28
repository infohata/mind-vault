#!/bin/bash
# Description: Install Cursor IDE (apt) + Cursor Agent CLI (user-scope) on Debian/Ubuntu
# Usage: sudo ./tools/install-cursor.sh [--check] [--no-cli]
# Supports: Debian 11+ (bullseye, bookworm, trixie), Ubuntu 20.04+ (focal, jammy, noble, etc.); amd64 + arm64
#
# Why: Cursor ships TWO different products with different install shapes:
#
#   • Cursor IDE        → Debian/Ubuntu apt repo at downloads.cursor.com/aptrepo,
#                         signed by downloads.cursor.com/keys/anysphere.asc.
#                         Same shape as Google Cloud / Docker / Microsoft —
#                         signed-by keyring + sources.list.d entry. System-wide,
#                         auto-updates via `apt upgrade`.
#   • Cursor Agent CLI  → Vendor curl-bash installer at cursor.com/install.
#                         User-scope (~/.local/share/cursor-agent + ~/.local/bin
#                         symlinks `agent` and `cursor-agent`). No apt path.
#                         Vendor installer hard-codes the version, but re-publishes
#                         the URL on each release, so delegating is more durable
#                         than a version pin in this script.
#
# This script installs both by default. The IDE step needs root (apt); the CLI
# step drops privileges to $SUDO_USER so the user-scope tarball lands in the
# invoking user's home, not root's. Both steps are independently idempotent.
#
# What it does:
#   1. Idempotency check: report install state for both. Without --check or
#      --no-cli, proceed to install whichever piece is missing.
#   2. OS detection via /etc/os-release — refuses anything other than debian/ubuntu
#      (accepts derivatives — Mint, Pop!_OS, Zorin, Kali — via ID_LIKE).
#   3. IDE: apt prerequisites → signing key into /etc/apt/keyrings/cursor.gpg →
#      sources.list.d entry pinned to amd64,arm64 → apt-get install cursor.
#   4. CLI (unless --no-cli): drop to $SUDO_USER and run vendor installer.
#      Symlinks land at ~/.local/bin/{agent,cursor-agent}. Warn if ~/.local/bin
#      isn't on target user's PATH (vendor installer also prints PATH hints).
#   5. Verifies both with --version probes.
#
# Flags:
#   --check      Report current install state and exit. No writes, no network.
#                Exit 0 when both pieces are installed (or just IDE if --no-cli),
#                1 when anything required is missing.
#   --no-cli     Skip the Cursor Agent CLI step. IDE-only install.

set -eo pipefail

CHECK_ONLY=0
INSTALL_CLI=1

while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK_ONLY=1; shift ;;
        --no-cli) INSTALL_CLI=0; shift ;;
        -h|--help)
            # Print only the contiguous top-of-file comment header (skip the shebang,
            # stop at the first non-`#` line). Same pattern as install-gcloud-cli.sh.
            awk '
                NR==1 && /^#!/ { next }
                /^#/            { sub(/^# ?/, ""); print; next }
                                { exit }
            ' "$0"
            exit 0
            ;;
        *)
            echo "❌ Unknown argument: $1" >&2
            echo "   Run with --help to see supported flags." >&2
            exit 1
            ;;
    esac
done

# --- Resolve CLI target user (always the invoking user, never root) ---
# Cursor Agent CLI is user-scope: it installs to ~/.local/share/cursor-agent and
# symlinks into ~/.local/bin. When this script is run via sudo, $HOME is root's
# home — wrong target. Use $SUDO_USER (the user who invoked sudo) instead.
CLI_USER="${SUDO_USER:-$USER}"
CLI_USER_HOME="$(getent passwd "$CLI_USER" | cut -d: -f6 || true)"
CLI_BIN_PATH="${CLI_USER_HOME:-/nonexistent}/.local/bin/agent"

# --- Idempotency check (state report) ---
echo "🔍 Checking current install state..."

IDE_INSTALLED=0
IDE_VER=""
if command -v cursor >/dev/null 2>&1; then
    # `cursor --version` prints three lines (version, commit, electron) — first
    # line is the version. Capture full output then take first line via bash
    # parameter expansion: piping into `head -1` under `set -eo pipefail` can
    # produce SIGPIPE (exit 141) when head closes stdin before the producer
    # finishes. Same pattern as install-mosh-tmux.sh:484-491.
    CURSOR_VER_RAW="$(cursor --version 2>/dev/null || true)"
    IDE_VER="${CURSOR_VER_RAW%%$'\n'*}"
    IDE_INSTALLED=1
fi

CLI_INSTALLED=0
CLI_VER=""
if [ -x "$CLI_BIN_PATH" ]; then
    # Run as the target user so any $HOME-relative bookkeeping the binary does
    # resolves correctly. Param-expansion + `|| true` guards against SIGPIPE /
    # non-zero exit (same pattern as IDE check above).
    if [ "$CLI_USER" = "$USER" ]; then
        CLI_VER_RAW="$("$CLI_BIN_PATH" --version 2>/dev/null || true)"
    else
        CLI_VER_RAW="$(sudo -u "$CLI_USER" -H "$CLI_BIN_PATH" --version 2>/dev/null || true)"
    fi
    CLI_VER="${CLI_VER_RAW%%$'\n'*}"
    CLI_INSTALLED=1
fi

if [ "$IDE_INSTALLED" = "1" ]; then
    echo "✅ Cursor IDE: ${IDE_VER:-installed}"
else
    echo "ℹ️  Cursor IDE: not installed"
fi
if [ "$INSTALL_CLI" = "1" ] || [ "$CLI_INSTALLED" = "1" ]; then
    if [ "$CLI_INSTALLED" = "1" ]; then
        echo "✅ Cursor Agent CLI (user ${CLI_USER}): ${CLI_VER:-installed} at ${CLI_BIN_PATH}"
    else
        echo "ℹ️  Cursor Agent CLI (user ${CLI_USER}): not installed"
    fi
fi

if [ "$CHECK_ONLY" = "1" ]; then
    # Exit 0 only when everything required is present.
    if [ "$IDE_INSTALLED" = "1" ] && { [ "$INSTALL_CLI" = "0" ] || [ "$CLI_INSTALLED" = "1" ]; }; then
        exit 0
    fi
    exit 1
fi

# --- Decide what work to do ---
DO_IDE=0
DO_CLI=0
[ "$IDE_INSTALLED" = "0" ] && DO_IDE=1
[ "$INSTALL_CLI" = "1" ] && [ "$CLI_INSTALLED" = "0" ] && DO_CLI=1

if [ "$DO_IDE" = "0" ] && [ "$DO_CLI" = "0" ]; then
    echo ""
    echo "Nothing to install. Re-run with --check to confirm state."
    echo "Upgrade IDE later: sudo apt-get update && sudo apt-get upgrade cursor"
    echo "Upgrade CLI later: re-run vendor installer:"
    echo "                   curl https://cursor.com/install -fsS | bash"
    exit 0
fi

# --- OS detection ---
if [ ! -f /etc/os-release ]; then
    echo "❌ /etc/os-release not found — cannot detect OS." >&2
    exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release
case "${ID}" in
    debian|ubuntu) ;;
    *)
        if echo " ${ID_LIKE:-} " | grep -qE ' (debian|ubuntu) '; then
            :
        else
            echo "❌ Unsupported OS: ${PRETTY_NAME:-$ID}" >&2
            echo "   This script handles Debian / Ubuntu (and derivatives) only." >&2
            echo "   For other distros, see https://cursor.com/docs/downloads" >&2
            exit 1
        fi
        ;;
esac

echo ""
echo "📦 Detected: ${PRETTY_NAME:-${ID}}"

# --- Root check (only required if doing the IDE step) ---
if [ "$DO_IDE" = "1" ] && [ "$(id -u)" -ne 0 ]; then
    echo "❌ This script must be run as root for the IDE install. Re-run with: sudo $0 $*" >&2
    exit 1
fi

# --- Arch sanity check (Cursor publishes amd64 + arm64 only) ---
if [ "$DO_IDE" = "1" ]; then
    DPKG_ARCH="$(dpkg --print-architecture)"
    case "$DPKG_ARCH" in
        amd64|arm64) ;;
        *)
            echo "❌ Unsupported architecture: ${DPKG_ARCH}" >&2
            echo "   Cursor publishes amd64 and arm64 only." >&2
            exit 1
            ;;
    esac
fi

# --- IDE install ---
if [ "$DO_IDE" = "1" ]; then
    echo ""
    echo "📥 Installing apt prerequisites..."
    apt-get update -qq
    apt-get install -y ca-certificates curl gnupg >/dev/null

    echo ""
    echo "🔑 Adding Cursor apt signing key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://downloads.cursor.com/keys/anysphere.asc \
        | gpg --dearmor --batch --yes -o /etc/apt/keyrings/cursor.gpg
    chmod a+r /etc/apt/keyrings/cursor.gpg

    echo ""
    echo "📝 Adding Cursor apt repository..."
    echo "deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/cursor.gpg] https://downloads.cursor.com/aptrepo stable main" \
        > /etc/apt/sources.list.d/cursor.list
    apt-get update -qq

    echo ""
    echo "⬇️  Installing cursor (IDE)..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y cursor >/dev/null
fi

# --- Cursor Agent CLI install (user-scope; drops privileges to $SUDO_USER) ---
if [ "$DO_CLI" = "1" ]; then
    if [ "$CLI_USER" = "root" ]; then
        echo ""
        echo "⚠️  Skipping CLI install — refusing to install user-scope CLI as root."
        echo "   The CLI lives in ~/.local/bin and would land in /root, not the user's home."
        echo "   Re-run as a regular user via sudo (e.g. \`sudo ./tools/install-cursor.sh\`)" \
             "or run the vendor installer yourself: \`curl https://cursor.com/install -fsS | bash\`"
    else
        echo ""
        echo "⬇️  Installing Cursor Agent CLI for ${CLI_USER} (user-scope, no sudo)..."
        # Delegate to the vendor installer. It's user-scope, idempotent, and
        # re-publishes the URL on each release — trying to mirror its tarball
        # resolution here would just couple us to internal vendor URLs that
        # change shape (the installer body itself hard-codes the version pin).
        if [ "$CLI_USER" = "$USER" ]; then
            # Running directly as a non-root user; no privilege drop needed.
            curl -fsSL https://cursor.com/install | bash
        else
            # Running as root via sudo; drop to invoking user.
            # `-H` so $HOME is the user's home, not preserved-root-$HOME.
            sudo -u "$CLI_USER" -H bash -c 'curl -fsSL https://cursor.com/install | bash'
        fi
    fi
fi

# --- Verify ---
echo ""
echo "🎉 Install complete:"
if command -v cursor >/dev/null 2>&1; then
    # `|| true` so a non-zero exit from cursor (headless host, no display) doesn't
    # propagate through `set -eo pipefail` and abort the script before "Next steps".
    { cursor --version 2>/dev/null || true; } | sed 's/^/   IDE: /' | head -1
else
    echo "   IDE: ⚠️  'cursor' command not on PATH."
fi
if [ "$INSTALL_CLI" = "1" ] && [ -x "$CLI_BIN_PATH" ]; then
    if [ "$CLI_USER" = "$USER" ]; then
        AGENT_VER_RAW="$("$CLI_BIN_PATH" --version 2>/dev/null || true)"
    else
        AGENT_VER_RAW="$(sudo -u "$CLI_USER" -H "$CLI_BIN_PATH" --version 2>/dev/null || true)"
    fi
    AGENT_VER_LINE="${AGENT_VER_RAW%%$'\n'*}"
    echo "   CLI: ${AGENT_VER_LINE:-installed} at ${CLI_BIN_PATH}"

    # PATH hint for the target user — vendor installer prints its own hints,
    # but running via sudo suppresses interactive shell-detection so we re-state.
    if [ -n "$CLI_USER_HOME" ]; then
        TARGET_PATH="$(sudo -u "$CLI_USER" -H bash -c 'echo $PATH' 2>/dev/null || echo "")"
        case ":${TARGET_PATH}:" in
            *":${CLI_USER_HOME}/.local/bin:"*) ;;
            *)
                echo "   ⚠️  ${CLI_USER_HOME}/.local/bin is not on ${CLI_USER}'s PATH."
                echo "       Add to ~/.bashrc / ~/.zshrc:"
                echo "         export PATH=\"\$HOME/.local/bin:\$PATH\""
                ;;
        esac
    fi
fi
echo ""
echo "Next steps:"
echo "  1. Launch the IDE from your app menu (Cursor) or run:    cursor"
echo "  2. Sign in to Cursor on first launch (browser flow)."
if [ "$INSTALL_CLI" = "1" ]; then
    echo "  3. Try the CLI:                                         agent --help"
    echo "  4. CLI authentication: run \`agent\` once and follow the browser prompt."
fi
echo "  5. Upgrade IDE later via apt:  sudo apt-get update && sudo apt-get upgrade cursor"
if [ "$INSTALL_CLI" = "1" ]; then
    echo "     Upgrade CLI later (vendor installer is idempotent):"
    echo "                              curl https://cursor.com/install -fsS | bash"
fi
