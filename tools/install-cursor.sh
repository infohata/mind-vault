#!/bin/bash
# Description: Install Cursor IDE on Debian/Ubuntu from Cursor's official apt repo
# Usage: sudo ./tools/install-cursor.sh [--check]
# Supports: Debian 11+ (bullseye, bookworm, trixie), Ubuntu 20.04+ (focal, jammy, noble, etc.); amd64 + arm64
#
# Why: Cursor (https://cursor.com) publishes an official apt repository at
# https://downloads.cursor.com/aptrepo signed by
# https://downloads.cursor.com/keys/anysphere.asc — same shape as Google Cloud's
# / Docker's / Microsoft's (signed-by keyring + sources.list.d entry). Vendor docs
# at cursor.com/docs/downloads are correct but copy-paste in three steps; this
# script makes it idempotent, OS-aware, and rerunable. System-wide install,
# auto-updates via `apt upgrade`, auditable, repeatable.
#
# What it does:
#   1. Idempotency check: exit early if cursor is already installed and reports a version.
#   2. OS detection via /etc/os-release — refuses anything other than debian/ubuntu
#      (accepts derivatives — Mint, Pop!_OS, Zorin, Kali — via ID_LIKE).
#   3. Installs apt prerequisites (ca-certificates, curl, gnupg).
#   4. Drops Cursor's signing key into /etc/apt/keyrings/cursor.gpg (dearmored;
#      no deprecated `apt-key`).
#   5. Writes /etc/apt/sources.list.d/cursor.list pointing at the official repo,
#      pinned to amd64,arm64 so multi-arch hosts don't try foreign arches.
#   6. apt-get update + apt-get install cursor.
#   7. Verifies with `cursor --version` and prints first-launch hints.
#
# Flags:
#   --check      Report current install state and exit. No writes, no network.
#                Exit 0 when cursor is installed, 1 when missing.

set -eo pipefail

CHECK_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK_ONLY=1; shift ;;
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

# --- Idempotency check ---
echo "🔍 Checking current Cursor install state..."
if command -v cursor >/dev/null 2>&1; then
    # `cursor --version` prints three lines (version, commit, electron) — first
    # line is the version. Capture full output then take first line via bash
    # parameter expansion: piping into `head -1` under `set -eo pipefail` can
    # produce SIGPIPE (exit 141) when head closes stdin before the producer
    # finishes. Same pattern as install-mosh-tmux.sh:484-491.
    CURSOR_VER_RAW="$(cursor --version 2>/dev/null || true)"
    CURSOR_VER_LINE="${CURSOR_VER_RAW%%$'\n'*}"
    echo "✅ Cursor already installed: ${CURSOR_VER_LINE:-installed}"
    if [ "$CHECK_ONLY" = "1" ]; then
        exit 0
    fi
    echo ""
    echo "Nothing to install. Re-run with --check to confirm state without prompts."
    echo "Upgrade later with: sudo apt-get update && sudo apt-get upgrade cursor"
    exit 0
fi

if [ "$CHECK_ONLY" = "1" ]; then
    echo "❌ Cursor not installed. Run without --check to install."
    exit 1
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
        # Accept Debian/Ubuntu derivatives (Mint, Pop!_OS, Zorin, Kali) via ID_LIKE.
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

echo "📦 Detected: ${PRETTY_NAME:-${ID}}"

# --- Root check ---
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ This script must be run as root. Re-run with: sudo $0 $*" >&2
    exit 1
fi

# --- Arch sanity check (Cursor publishes amd64 + arm64 only) ---
DPKG_ARCH="$(dpkg --print-architecture)"
case "$DPKG_ARCH" in
    amd64|arm64) ;;
    *)
        echo "❌ Unsupported architecture: ${DPKG_ARCH}" >&2
        echo "   Cursor publishes amd64 and arm64 only." >&2
        exit 1
        ;;
esac

# --- Install prerequisites ---
echo ""
echo "📥 Installing apt prerequisites..."
apt-get update -qq
apt-get install -y ca-certificates curl gnupg >/dev/null

# --- Add Cursor signing key ---
echo ""
echo "🔑 Adding Cursor apt signing key..."
install -m 0755 -d /etc/apt/keyrings
# --batch --yes makes gpg non-interactive on re-runs (existing keyring file).
curl -fsSL https://downloads.cursor.com/keys/anysphere.asc \
    | gpg --dearmor --batch --yes -o /etc/apt/keyrings/cursor.gpg
chmod a+r /etc/apt/keyrings/cursor.gpg

# --- Add Cursor repo ---
echo ""
echo "📝 Adding Cursor apt repository..."
# Pin to amd64,arm64 — Cursor's repo only ships those, and unpinned multi-arch
# hosts would otherwise try (and fail to fetch) foreign arches every `apt update`.
echo "deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/cursor.gpg] https://downloads.cursor.com/aptrepo stable main" \
    > /etc/apt/sources.list.d/cursor.list
apt-get update -qq

# --- Install Cursor ---
echo ""
echo "⬇️  Installing cursor..."
DEBIAN_FRONTEND=noninteractive apt-get install -y cursor >/dev/null

# --- Verify ---
echo ""
echo "🎉 Install complete:"
if command -v cursor >/dev/null 2>&1; then
    # `|| true` so a non-zero exit from cursor (headless host, no display) doesn't
    # propagate through `set -eo pipefail` and abort the script before "Next steps"
    # prints.
    { cursor --version 2>/dev/null || true; } | sed 's/^/   /'
else
    echo "   ⚠️  'cursor' command not on PATH. Check /usr/share/cursor or re-login to refresh PATH."
fi
echo ""
echo "Next steps:"
echo "  1. Launch from your app menu (Cursor) or run:           cursor"
echo "  2. Sign in to Cursor on first launch (browser flow)."
echo "  3. Upgrade later via apt:                               sudo apt-get update && sudo apt-get upgrade cursor"
