#!/bin/bash
# Description: Install Docker Engine + Compose plugin on a fresh Debian/Ubuntu host
# Usage: sudo ./tools/install-docker.sh [--check] [--no-group] [--no-test-run]
# Supports: Debian 12+ (bookworm, trixie), Ubuntu 22.04+ (jammy, noble, etc.)
#
# Why: mind-vault's RULE_parallel-worktree-docker and the sprint-auto / deployment
# workflows assume Docker Engine + the `docker compose` plugin (v2) are installed
# on the host. Fresh VPS images usually ship without them, and the distro-packaged
# `docker.io` is often too old for the docker-compose-v2 `!override` syntax the
# parallel-worktree pattern depends on. This script installs directly from Docker's
# official apt repo — the production-grade path, not the get.docker.com curl-sh
# convenience script — so the install is auditable and repeatable.
#
# What it does:
#   1. Idempotency check: exit early if docker + compose plugin already work.
#   2. OS detection via /etc/os-release — refuses anything other than debian/ubuntu.
#   3. Removes any distro-packaged docker.io / containerd / runc / podman-docker that
#      would conflict with the official packages.
#   4. Installs Docker's apt signing key + repo for the detected distro + codename.
#   5. Installs docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin,
#      docker-compose-plugin.
#   6. Adds the invoking user ($SUDO_USER) to the docker group so rootless `docker`
#      commands work after a re-login. Skip with --no-group.
#   7. Runs `docker run --rm hello-world` as a smoke test. Skip with --no-test-run.
#
# Flags:
#   --check          Report current install state and exit. No writes.
#   --no-group       Don't touch the docker group. Useful when the target user is
#                    managed externally (LDAP, Ansible, etc.).
#   --no-test-run    Skip the hello-world smoke test. Faster; useful in CI.

set -e

CHECK_ONLY=0
ADD_GROUP=1
TEST_RUN=1

for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        --no-group) ADD_GROUP=0 ;;
        --no-test-run) TEST_RUN=0 ;;
        -h|--help)
            grep -E '^# ' "$0" | sed 's/^# //; s/^#$//'
            exit 0
            ;;
        *)
            echo "❌ Unknown argument: $arg" >&2
            echo "   Run with --help to see supported flags." >&2
            exit 1
            ;;
    esac
done

# --- Idempotency check ---
echo "🔍 Checking current Docker install state..."
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    echo "✅ Docker Engine + compose plugin already installed:"
    echo "   $(docker --version)"
    echo "   $(docker compose version)"
    if [ "$CHECK_ONLY" = "1" ]; then
        exit 0
    fi
    echo ""
    echo "Nothing to install. Re-run with --check to confirm state without prompts."
    echo "If docker commands fail for your user, verify group membership:"
    echo "   groups | tr ' ' '\\n' | grep -q docker && echo 'in docker group' || echo 'NOT in docker group (log out/in or run: newgrp docker)'"
    exit 0
fi

# Partial install detection — docker present but compose plugin missing is a
# common "distro-packaged docker" state that we want to call out.
if command -v docker >/dev/null 2>&1; then
    echo "⚠️  docker CLI present but 'docker compose' plugin missing."
    echo "   Likely a distro-packaged install. The script will uninstall it and"
    echo "   replace with the official packages (same binaries + compose plugin)."
fi

if [ "$CHECK_ONLY" = "1" ]; then
    echo "❌ Docker not fully installed. Run without --check to install."
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
        echo "   For other distros, see https://docs.docker.com/engine/install/" >&2
        exit 1
        ;;
esac

CODENAME="${VERSION_CODENAME:-}"
if [ -z "$CODENAME" ]; then
    echo "❌ Could not determine distribution codename from /etc/os-release" >&2
    exit 1
fi

echo "📦 Detected: ${PRETTY_NAME} (codename: ${CODENAME})"

# --- Root check ---
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ This script must be run as root. Re-run with: sudo $0 $*" >&2
    exit 1
fi

# --- Remove conflicting distro packages ---
echo ""
echo "🧹 Removing conflicting packages (if present)..."
CONFLICTING="docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc"
for pkg in $CONFLICTING; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        echo "   Removing $pkg"
        apt-get remove -y "$pkg" >/dev/null
    fi
done

# --- Install prerequisites ---
echo ""
echo "📥 Installing apt prerequisites..."
apt-get update -qq
apt-get install -y ca-certificates curl gnupg >/dev/null

# --- Add Docker's official GPG key ---
echo ""
echo "🔑 Adding Docker's apt signing key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# --- Add Docker repo ---
echo ""
echo "📝 Adding Docker apt repository for ${ID} ${CODENAME}..."
ARCH="$(dpkg --print-architecture)"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} ${CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update -qq

# --- Install Docker packages ---
echo ""
echo "⬇️  Installing docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin..."
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin >/dev/null

# --- Enable + start the daemon ---
echo ""
echo "🚀 Enabling + starting docker.service..."
systemctl enable --now docker >/dev/null 2>&1 || true

# --- Group membership ---
if [ "$ADD_GROUP" = "1" ]; then
    TARGET_USER="${SUDO_USER:-}"
    if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
        echo ""
        echo "⚠️  No non-root SUDO_USER detected — skipping docker group add."
        echo "   To add a user later: sudo usermod -aG docker <username>"
    elif ! id "$TARGET_USER" >/dev/null 2>&1; then
        echo ""
        echo "⚠️  User $TARGET_USER not found — skipping group add."
    else
        echo ""
        echo "👥 Adding $TARGET_USER to the docker group..."
        usermod -aG docker "$TARGET_USER"
        echo "   Note: $TARGET_USER must log out + back in (or run: newgrp docker)"
        echo "   before rootless 'docker' commands work."
    fi
fi

# --- Smoke test ---
if [ "$TEST_RUN" = "1" ]; then
    echo ""
    echo "🧪 Running 'docker run --rm hello-world' as smoke test..."
    if docker run --rm hello-world >/dev/null 2>&1; then
        echo "✅ hello-world ran successfully."
    else
        echo "⚠️  hello-world failed. Install succeeded but runtime smoke test didn't." >&2
        echo "   Check: systemctl status docker, journalctl -u docker --no-pager -n 50" >&2
        exit 1
    fi
fi

# --- Verify ---
echo ""
echo "🎉 Install complete:"
echo "   $(docker --version)"
echo "   $(docker compose version)"
echo ""
echo "Next steps:"
echo "  1. Log out and back in (or run: newgrp docker) if you were added to the group."
echo "  2. Verify rootless: docker ps"
echo "  3. For parallel-worktree stacks, see rules/RULE_parallel-worktree-docker.md"
