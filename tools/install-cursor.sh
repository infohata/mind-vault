#!/bin/bash
# Description: Install Cursor IDE on Debian/Ubuntu using apt to handle the .deb's dependencies
# Usage: sudo ./tools/install-cursor.sh [--check] [--upgrade]
# Supports: Debian 11+ (bullseye, bookworm, trixie), Ubuntu 20.04+ (focal, jammy, noble, etc.); x86_64 + arm64
#
# Why: Cursor (https://cursor.com) does not publish an apt repository. The vendor's
# Linux distribution options are AppImage (single-file, no system integration) or a
# downloadable .deb. The .deb is the right artefact for a system install — desktop
# entry, MIME associations, /usr/bin/cursor on PATH — but the vendor's docs leave
# you to download-and-double-click. Done that way you also miss apt's dependency
# resolution: a fresh Debian 12 host typically lacks libnss3 / libxkbfile1 /
# libsecret-1-0 / libasound2 / libgtk-3-0 etc., and `dpkg -i` will half-install
# then leave you running `apt-get install -f` to clean up.
# This script takes the official .deb path done right: resolve the latest version
# via Cursor's update endpoint (302 redirect), download once to /tmp, then
# `apt-get install ./path.deb` so apt — not dpkg — drives the install and pulls
# every transitive lib in one transaction.
#
# What it does:
#   1. Idempotency check: exits early if `cursor --version` already reports a version
#      and --upgrade was not passed.
#   2. OS detection via /etc/os-release — refuses anything other than debian/ubuntu.
#   3. Arch detection via `dpkg --print-architecture` — picks linux-x64-deb / linux-arm64-deb.
#   4. Resolves the latest stable .deb URL by following Cursor's update endpoint:
#        https://api2.cursor.sh/updates/download/golden/linux-<arch>-deb/cursor/0.0.0
#      The 0.0.0 placeholder forces the server to treat the client as out-of-date
#      and 302-redirect to the current production .deb on downloads.cursor.com.
#   5. On --upgrade: parses the version out of the redirect filename
#      (cursor_<version>_<arch>.deb) and compares to the installed version; skips
#      the download if they match.
#   6. Downloads the .deb to /tmp.
#   7. apt-get install -y ./tmp/cursor_<ver>_<arch>.deb — apt resolves and installs
#      every transitive shared-lib dep (libnss3, libxkbfile1, libsecret-1-0, etc.)
#      in a single transaction.
#   8. Cleans up the downloaded .deb.
#   9. Verifies with `cursor --version`.
#
# Note on upgrades: Cursor's .deb does NOT register an apt source on the host —
# `apt upgrade` will never bump it. Re-run this script with --upgrade to fetch a
# newer version. The script's redirect-resolution + version-compare logic makes
# that re-run idempotent (no download if already current).
#
# Flags:
#   --check      Report current install state and exit. No writes, no network.
#                Exit 0 when cursor is installed, 1 when missing. Overrides
#                --upgrade — `--check --upgrade` reports state and exits without
#                touching the system. To actually probe upstream for a newer
#                version, run `--upgrade` (the redirect-resolution + version-
#                compare in the install path is idempotent — no download if
#                already current).
#   --upgrade    Re-fetch the latest .deb and reinstall if the upstream version is
#                newer than the installed one. Equivalent to a fresh install when
#                cursor isn't yet present.

set -eo pipefail

CHECK_ONLY=0
UPGRADE=0

# Snapshot original args before the parser loop consumes them — the root-check
# error message below re-prints the invocation, and `shift`-ed positional
# parameters can't be reconstructed after the loop.
ORIGINAL_ARGS=("$@")

while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK_ONLY=1; shift ;;
        --upgrade) UPGRADE=1; shift ;;
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
        # Many Debian/Ubuntu derivatives (Linux Mint, Pop!_OS, Zorin, Kali) carry
        # ID_LIKE=debian or =ubuntu. Accept those rather than refusing outright.
        if echo " ${ID_LIKE:-} " | grep -qE ' (debian|ubuntu) '; then
            :
        else
            echo "❌ Unsupported OS: ${PRETTY_NAME:-$ID}" >&2
            echo "   This script handles Debian / Ubuntu (and derivatives) only." >&2
            echo "   For other distros, see https://www.cursor.com/downloads" >&2
            exit 1
        fi
        ;;
esac

# --- Arch detection ---
DPKG_ARCH="$(dpkg --print-architecture)"
case "$DPKG_ARCH" in
    amd64) CURSOR_ARCH="linux-x64-deb" ;;
    arm64) CURSOR_ARCH="linux-arm64-deb" ;;
    *)
        echo "❌ Unsupported architecture: ${DPKG_ARCH}" >&2
        echo "   Cursor publishes amd64 and arm64 .deb only." >&2
        exit 1
        ;;
esac

# --- Idempotency check ---
INSTALLED_VERSION=""
if command -v cursor >/dev/null 2>&1; then
    # `cursor --version` prints three lines (version, commit, electron) — first
    # line is the version. Capture full output then take first line via bash
    # parameter expansion: piping into `head -1` under `set -eo pipefail` can
    # produce SIGPIPE (exit 141) when head closes stdin before the producer
    # finishes, which would silently empty INSTALLED_VERSION and re-trigger a
    # fresh install on an already-installed host. Mirrors install-mosh-tmux.sh:484-491.
    CURSOR_VER_RAW="$(cursor --version 2>/dev/null || true)"
    INSTALLED_VERSION="${CURSOR_VER_RAW%%$'\n'*}"
    INSTALLED_VERSION="${INSTALLED_VERSION//[[:space:]]/}"
fi

echo "🔍 Checking current Cursor install state..."
if [ -n "$INSTALLED_VERSION" ]; then
    echo "✅ Cursor already installed: ${INSTALLED_VERSION}"
else
    echo "ℹ️  Cursor not installed."
fi

# --- --check is a hard no-writes contract; overrides --upgrade ---
# Always exits before any network or apt call, regardless of --upgrade.
# Combine `--check --upgrade` to confirm install state without touching the
# system; to actually probe upstream for a newer version, run `--upgrade`
# alone (the redirect-resolution + version-compare in the install path is
# idempotent and skips the download if already current).
if [ "$CHECK_ONLY" = "1" ]; then
    if [ -n "$INSTALLED_VERSION" ]; then
        exit 0
    fi
    echo "   Run without --check to install."
    exit 1
fi

# --- Idempotent skip when already installed and no upgrade requested ---
if [ -n "$INSTALLED_VERSION" ] && [ "$UPGRADE" = "0" ]; then
    echo ""
    echo "Nothing to do. Re-run with --upgrade to fetch the latest version,"
    echo "or with --check to confirm state without changes."
    exit 0
fi

if [ -z "$INSTALLED_VERSION" ]; then
    echo "ℹ️  Proceeding with fresh install."
fi

# --- Root check (needed for apt-get install) ---
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ This script must be run as root. Re-run with: sudo $0 ${ORIGINAL_ARGS[*]}" >&2
    exit 1
fi

# --- Install prerequisites for download ---
echo ""
echo "📥 Ensuring download prerequisites (curl, ca-certificates)..."
apt-get update -qq
apt-get install -y ca-certificates curl >/dev/null

# --- Resolve latest .deb URL ---
# Cursor's update API: any version older than current → 302 to the latest .deb.
# Using 0.0.0 as the "current client version" guarantees the redirect fires.
UPDATE_ENDPOINT="https://api2.cursor.sh/updates/download/golden/${CURSOR_ARCH}/cursor/0.0.0"

echo ""
echo "🔎 Resolving latest Cursor .deb from update endpoint..."
RESOLVED_URL="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$UPDATE_ENDPOINT")"
if [ -z "$RESOLVED_URL" ] || [ "$RESOLVED_URL" = "$UPDATE_ENDPOINT" ]; then
    echo "❌ Update endpoint did not redirect to a .deb URL." >&2
    echo "   Endpoint: $UPDATE_ENDPOINT" >&2
    echo "   Resolved: ${RESOLVED_URL:-<empty>}" >&2
    exit 1
fi

DEB_FILENAME="$(basename "$RESOLVED_URL")"
# cursor_<version>_<arch>.deb → extract <version>
LATEST_VERSION="$(echo "$DEB_FILENAME" | sed -n 's/^cursor_\(.*\)_[^_]*\.deb$/\1/p')"
if [ -z "$LATEST_VERSION" ]; then
    echo "⚠️  Could not parse version from filename '$DEB_FILENAME'. Continuing without version check."
fi

echo "   Latest available: ${LATEST_VERSION:-unknown} (${DEB_FILENAME})"
if [ -n "$INSTALLED_VERSION" ] && [ -n "$LATEST_VERSION" ] && [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
    echo "✅ Already on the latest version (${INSTALLED_VERSION}). Nothing to do."
    exit 0
fi

# --- Download .deb ---
DEB_PATH="/tmp/${DEB_FILENAME}"
echo ""
echo "⬇️  Downloading ${DEB_FILENAME}..."
# -L follows redirects; -f errors on HTTP 4xx/5xx instead of saving the error body.
curl -fL --progress-bar -o "$DEB_PATH" "$RESOLVED_URL"

# --- Install via apt (resolves transitive deps in one transaction) ---
echo ""
echo "📦 Installing Cursor via apt (resolves shared-lib dependencies)..."
# DEBIAN_FRONTEND prevents any postinst from popping a dialog on minimal hosts.
DEBIAN_FRONTEND=noninteractive apt-get install -y "$DEB_PATH"

# --- Cleanup ---
rm -f "$DEB_PATH"

# --- Verify ---
echo ""
echo "🎉 Install complete:"
if command -v cursor >/dev/null 2>&1; then
    # `|| true` so a non-zero exit from cursor (headless host, no display) doesn't
    # propagate through `set -eo pipefail` and abort the script before "Next steps"
    # prints. Mirrors the same guard on the idempotency-check pipeline above.
    { cursor --version 2>/dev/null || true; } | sed 's/^/   /'
else
    echo "   ⚠️  'cursor' command not on PATH. Check /usr/share/cursor or re-login to refresh PATH."
fi
echo ""
echo "Next steps:"
echo "  1. Launch from your app menu (Cursor) or run:           cursor"
echo "  2. Sign in to Cursor on first launch (browser flow)."
echo "  3. To upgrade later, re-run:                            sudo $0 --upgrade"
echo "     (Cursor's .deb does NOT add an apt source — 'apt upgrade' will not bump it.)"
