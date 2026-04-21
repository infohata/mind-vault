#!/bin/bash
# Description: Install Google Cloud CLI (gcloud) on Debian/Ubuntu from Google's official apt repo
# Usage: sudo ./tools/install-gcloud-cli.sh [--check] [--with-components COMP[,COMP...]]
# Supports: Debian 11+ (bullseye, bookworm, trixie), Ubuntu 20.04+ (focal, jammy, noble, etc.)
#
# Why: Projects that talk to Google Cloud (GCP APIs, Cloud Storage, Pub/Sub, Cloud Run,
# Secret Manager, etc.) need `gcloud`. Google's own install paths are either:
#   (a) curl | bash convenience script that drops an SDK into $HOME — fine for a dev
#       box, poor for VPS / shared systems where multiple users expect gcloud on PATH;
#   (b) copy-paste apt repo + GPG key setup — correct but error-prone and the docs
#       still show the deprecated `apt-key add` flow.
# This script takes path (b) done right: keyring dropped into /usr/share/keyrings,
# repo file signed-by that keyring, no `apt-key`. System-wide install, auto-updates
# via `apt upgrade`, auditable, repeatable.
#
# What it does:
#   1. Idempotency check: exit early if gcloud is already installed and reports a version.
#   2. OS detection via /etc/os-release — refuses anything other than debian/ubuntu.
#   3. Installs apt prerequisites (ca-certificates, curl, gnupg, apt-transport-https).
#   4. Drops Google Cloud's apt signing key into /usr/share/keyrings/cloud.google.gpg
#      (dearmored; no deprecated `apt-key`).
#   5. Writes /etc/apt/sources.list.d/google-cloud-sdk.list pointing at the cloud-sdk
#      apt channel (same repo for all supported Debian/Ubuntu versions — Google ships
#      a single `cloud-sdk main` distribution, not per-codename).
#   6. apt-get update + apt-get install google-cloud-cli.
#   7. Optionally installs extra components via --with-components (e.g. gke-gcloud-auth-plugin,
#      kubectl, cloud-sql-proxy). Each becomes a separate apt package (google-cloud-cli-<comp>).
#   8. Verifies with `gcloud --version` and prints a hint to run `gcloud init`.
#
# Flags:
#   --check                    Report current install state and exit. No writes.
#   --with-components LIST     Comma-separated extra components to install alongside
#                              the base CLI. Each resolves to an apt package named
#                              google-cloud-cli-<component>. Examples:
#                                --with-components gke-gcloud-auth-plugin
#                                --with-components gke-gcloud-auth-plugin,cloud-sql-proxy
#                              Full package list: `apt-cache search google-cloud-cli-`
#                              after the base install.

set -e

CHECK_ONLY=0
EXTRA_COMPONENTS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK_ONLY=1; shift ;;
        --with-components)
            if [ -z "${2:-}" ]; then
                echo "❌ --with-components requires a comma-separated list." >&2
                exit 1
            fi
            EXTRA_COMPONENTS="$2"
            shift 2
            ;;
        -h|--help)
            # Print only the contiguous top-of-file comment header (skip the shebang,
            # stop at the first non-`#` line). Same pattern as install-docker.sh.
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
echo "🔍 Checking current gcloud install state..."
if command -v gcloud >/dev/null 2>&1 && gcloud --version >/dev/null 2>&1; then
    GCLOUD_VER_LINE="$(gcloud --version 2>/dev/null | head -1)"
    echo "✅ gcloud already installed: ${GCLOUD_VER_LINE}"
    if [ "$CHECK_ONLY" = "1" ]; then
        exit 0
    fi
    echo ""
    echo "Nothing to install. Re-run with --check to confirm state without prompts."
    echo "Upgrade later with: sudo apt-get update && sudo apt-get upgrade google-cloud-cli"
    echo "Install extra components: sudo apt-get install google-cloud-cli-<component>"
    echo "  (e.g. google-cloud-cli-gke-gcloud-auth-plugin)"
    exit 0
fi

if [ "$CHECK_ONLY" = "1" ]; then
    echo "❌ gcloud not installed. Run without --check to install."
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
        echo "❌ Unsupported OS: ${PRETTY_NAME:-$ID}" >&2
        echo "   This script handles Debian / Ubuntu only." >&2
        echo "   For other distros, see https://cloud.google.com/sdk/docs/install" >&2
        exit 1
        ;;
esac

echo "📦 Detected: ${PRETTY_NAME}"

# --- Root check ---
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ This script must be run as root. Re-run with: sudo $0 $*" >&2
    exit 1
fi

# --- Install prerequisites ---
echo ""
echo "📥 Installing apt prerequisites..."
apt-get update -qq
apt-get install -y apt-transport-https ca-certificates curl gnupg >/dev/null

# --- Add Google Cloud apt signing key ---
echo ""
echo "🔑 Adding Google Cloud apt signing key..."
install -m 0755 -d /usr/share/keyrings
# --batch --yes makes gpg non-interactive in case the keyring file exists already
# (re-run case: we want to replace the existing dearmored keyring, not prompt).
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor --batch --yes -o /usr/share/keyrings/cloud.google.gpg
chmod a+r /usr/share/keyrings/cloud.google.gpg

# --- Add Google Cloud repo ---
echo ""
echo "📝 Adding Google Cloud apt repository..."
# Google ships a single cloud-sdk distribution for all Debian/Ubuntu versions —
# not per-codename like Docker. Pinning arch keeps apt from trying foreign arches
# on multi-arch hosts.
ARCH="$(dpkg --print-architecture)"
echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list
apt-get update -qq

# --- Install Google Cloud CLI ---
echo ""
echo "⬇️  Installing google-cloud-cli..."
apt-get install -y google-cloud-cli >/dev/null

# --- Install optional components ---
if [ -n "$EXTRA_COMPONENTS" ]; then
    echo ""
    echo "⬇️  Installing extra components: ${EXTRA_COMPONENTS}..."
    # Convert comma-separated list into space-separated apt package names.
    COMP_PKGS=""
    IFS=',' read -ra COMPS <<< "$EXTRA_COMPONENTS"
    for comp in "${COMPS[@]}"; do
        comp_trimmed="$(echo "$comp" | tr -d '[:space:]')"
        [ -z "$comp_trimmed" ] && continue
        COMP_PKGS="$COMP_PKGS google-cloud-cli-${comp_trimmed}"
    done
    # shellcheck disable=SC2086
    apt-get install -y $COMP_PKGS >/dev/null
fi

# --- Verify ---
echo ""
echo "🎉 Install complete:"
gcloud --version | head -5 | sed 's/^/   /'
echo ""
echo "Next steps:"
echo "  1. Authenticate + pick a default project:    gcloud init"
echo "  2. (Or just login for API usage):            gcloud auth login"
echo "  3. Set application-default credentials:      gcloud auth application-default login"
echo "  4. List available components to add later:   apt-cache search google-cloud-cli-"
echo ""
echo "Upgrade via apt: sudo apt-get update && sudo apt-get upgrade google-cloud-cli"
