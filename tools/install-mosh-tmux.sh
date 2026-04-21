#!/bin/bash
# Description: Install + configure mosh and tmux for resilient SSH sessions on Debian/Ubuntu
# Usage: sudo ./tools/install-mosh-tmux.sh [flags]
# Supports: Debian 11+ (bullseye, bookworm, trixie), Ubuntu 20.04+ (focal, jammy, noble, etc.)
#
# Why: Spotty networks + long-running Claude Code / CLI sessions = constant
# context loss on SSH drops. The fix is a two-layer combo:
#
#   * tmux keeps the shell session alive on the server across disconnects;
#     attach / detach cycles survive any network event.
#   * mosh replaces raw SSH for the *connection* layer — handles 30-min
#     disconnects, roaming networks, laptop sleep, cell handoff, all
#     gracefully. UDP-based, reconnects without dropping the session.
#
# Together: laptop wakes up an hour later, mosh transparently reconnects
# to its existing UDP server, tmux is still running the same pane with
# Claude mid-thought. Zero context loss.
#
# What it does:
#   1. Idempotency: installed packages + marked rc / conf blocks are detected
#      and re-affirmed, not duplicated. Safe to re-run.
#   2. Installs `mosh` and `tmux` via apt.
#   3. Writes `~/.tmux.conf` inside BEGIN/END markers so manual tuning
#      outside those markers survives re-runs.
#   4. Adds an SSH-only auto-attach snippet to `~/.bashrc` (also
#      marker-bounded) so every SSH/mosh login drops straight into tmux.
#   5. If ufw is active, opens UDP 60000:61000 (mosh's default port range).
#   6. Prints a client-side reminder (mosh needs a mosh-client on the
#      laptop end too).
#
# Flags:
#   --check                Report current install + config state, exit. No writes.
#   --session-name NAME    tmux session to auto-attach/create (default: main)
#   --no-ufw               Don't touch ufw (skip the 60000:61000/udp rule).
#   --no-autoattach        Install + write tmux.conf, but skip the .bashrc edit.
#   --no-tmux-config       Install packages + handle autoattach/ufw, but skip tmux.conf.
#   --target-user USER     User whose ~/.bashrc + ~/.tmux.conf to edit.
#                          Default: $SUDO_USER (the invoking user under sudo).
#   -h, --help             Show this header and exit.

set -eo pipefail

CHECK_ONLY=0
SESSION_NAME="main"
DO_UFW=1
DO_AUTOATTACH=1
DO_TMUX_CONFIG=1
TARGET_USER=""

while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK_ONLY=1; shift ;;
        --session-name)
            if [ -z "${2:-}" ]; then
                echo "❌ --session-name requires a value (e.g. --session-name main)." >&2
                exit 1
            fi
            SESSION_NAME="$2"
            shift 2
            ;;
        --no-ufw) DO_UFW=0; shift ;;
        --no-autoattach) DO_AUTOATTACH=0; shift ;;
        --no-tmux-config) DO_TMUX_CONFIG=0; shift ;;
        --target-user)
            if [ -z "${2:-}" ]; then
                echo "❌ --target-user requires a username." >&2
                exit 1
            fi
            TARGET_USER="$2"
            shift 2
            ;;
        -h|--help)
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

# --- Resolve target user + their home dir ---
# Under `sudo`, $SUDO_USER holds the original invoker; without it, we're
# running as a plain user and $USER is correct. The rc-file edits must
# target that user's HOME, not root's.
if [ -z "$TARGET_USER" ]; then
    TARGET_USER="${SUDO_USER:-$USER}"
fi
if [ "$TARGET_USER" = "root" ]; then
    echo "⚠️  Target user resolved to root; rc file edits will land in /root."
    echo "    If you meant to configure a non-root user, pass --target-user NAME."
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
    echo "❌ Could not resolve home directory for user '$TARGET_USER'." >&2
    exit 1
fi

BASHRC="$TARGET_HOME/.bashrc"
TMUX_CONF="$TARGET_HOME/.tmux.conf"
BEGIN_MARK="# BEGIN mind-vault-mosh-tmux (managed by install-mosh-tmux.sh)"
END_MARK="# END mind-vault-mosh-tmux"

# --- Check state ---
echo "🔍 Checking current mosh + tmux state..."
MOSH_OK=0; TMUX_OK=0; TMUX_CONF_OK=0; RC_OK=0
command -v mosh       >/dev/null 2>&1 && MOSH_OK=1
command -v tmux       >/dev/null 2>&1 && TMUX_OK=1
[ -f "$TMUX_CONF" ] && grep -q "$BEGIN_MARK" "$TMUX_CONF" 2>/dev/null && TMUX_CONF_OK=1
[ -f "$BASHRC" ]    && grep -q "$BEGIN_MARK" "$BASHRC"    2>/dev/null && RC_OK=1

echo "   mosh installed:        $([ $MOSH_OK      -eq 1 ] && echo ✅ || echo ❌)"
echo "   tmux installed:        $([ $TMUX_OK      -eq 1 ] && echo ✅ || echo ❌)"
echo "   ~/.tmux.conf managed:  $([ $TMUX_CONF_OK -eq 1 ] && echo ✅ || echo ❌)  ($TMUX_CONF)"
echo "   .bashrc auto-attach:   $([ $RC_OK        -eq 1 ] && echo ✅ || echo ❌)  ($BASHRC)"

if [ "$CHECK_ONLY" = "1" ]; then
    if [ $MOSH_OK -eq 1 ] && [ $TMUX_OK -eq 1 ] && [ $TMUX_CONF_OK -eq 1 ] && [ $RC_OK -eq 1 ]; then
        exit 0
    fi
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
        exit 1
        ;;
esac
echo "📦 Detected: ${PRETTY_NAME}"

# --- Root check (needed for apt install + optional ufw) ---
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ This script must be run as root for apt install. Re-run with: sudo $0 $*" >&2
    exit 1
fi

# --- Install mosh + tmux ---
NEED_INSTALL=()
[ $MOSH_OK -eq 0 ] && NEED_INSTALL+=("mosh")
[ $TMUX_OK -eq 0 ] && NEED_INSTALL+=("tmux")
if [ ${#NEED_INSTALL[@]} -gt 0 ]; then
    echo ""
    echo "⬇️  Installing: ${NEED_INSTALL[*]}"
    apt-get update -qq
    apt-get install -y "${NEED_INSTALL[@]}" >/dev/null
else
    echo "✅ mosh + tmux already installed."
fi

# --- Write ~/.tmux.conf ---
if [ "$DO_TMUX_CONFIG" = "1" ]; then
    echo ""
    echo "⚙️  Writing managed block to $TMUX_CONF"

    if [ -f "$TMUX_CONF" ] && [ $TMUX_CONF_OK -eq 0 ]; then
        BACKUP="${TMUX_CONF}.pre-mindvault.$(date +%s)"
        echo "   (backing up existing unmanaged config → $BACKUP)"
        cp "$TMUX_CONF" "$BACKUP"
        chown "$TARGET_USER:" "$BACKUP"
    fi

    # Strip any prior managed block (idempotent re-write).
    if [ -f "$TMUX_CONF" ] && [ $TMUX_CONF_OK -eq 1 ]; then
        sed -i "/$BEGIN_MARK/,/$END_MARK/d" "$TMUX_CONF"
    fi

    # Append the fresh managed block. HEREDOC is intentionally unquoted
    # so $BEGIN_MARK and $END_MARK expand; the tmux config body happens
    # to have no $-variables. If you add any tmux-format strings that
    # contain literal $ (e.g. #{s/foo/$bar/}), escape them as \$ or
    # switch to a single-quoted HEREDOC (<<'TMUXCONF') and inline the
    # marker strings literally.
    cat >> "$TMUX_CONF" <<TMUXCONF
$BEGIN_MARK
# Minimal quality-of-life defaults. Anything outside the BEGIN/END block is
# yours — this script will not touch it on re-runs.

# Colour + terminal compatibility (truecolor inside tmux, 256 outside).
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc,*256col*:Tc"

# Mouse: scroll + click-to-select-pane + drag-to-resize — make tmux
# feel like the IDE terminal even on a flaky SSH link.
set -g mouse on

# 50k lines of scrollback — Claude Code sessions with bugbot loops fill
# a default 2k buffer in a few cycles.
set -g history-limit 50000

# Fast Esc response (default 500ms breaks vim-style navigation in tools).
set -g escape-time 10

# Focus events on — helps tools like vim detect lost focus.
set -g focus-events on

# Start window + pane indices at 1 (0 is a pinky-stretch on most keyboards).
set -g base-index 1
setw -g pane-base-index 1

# One-key config reload after tweaks.
bind r source-file ~/.tmux.conf \\; display "tmux.conf reloaded"

# Minimal status bar — session name, hostname, ISO-ish clock.
set -g status-style "bg=black,fg=cyan"
set -g status-left  " [#S] "
set -g status-right " #h · %Y-%m-%d %H:%M "
set -g status-right-length 40
$END_MARK
TMUXCONF
    chown "$TARGET_USER:" "$TMUX_CONF"
    echo "✅ $TMUX_CONF written."
fi

# --- Append .bashrc auto-attach snippet ---
if [ "$DO_AUTOATTACH" = "1" ]; then
    echo ""
    echo "⚙️  Wiring SSH auto-attach into $BASHRC (session: $SESSION_NAME)"

    [ -f "$BASHRC" ] || { touch "$BASHRC"; chown "$TARGET_USER:" "$BASHRC"; }

    # Strip any prior managed block.
    if grep -q "$BEGIN_MARK" "$BASHRC" 2>/dev/null; then
        sed -i "/$BEGIN_MARK/,/$END_MARK/d" "$BASHRC"
    fi

    cat >> "$BASHRC" <<BASHRCBLOCK

$BEGIN_MARK
# Auto-attach to tmux on SSH (incl. mosh) login, creating the session if
# it doesn't exist yet. Skips non-SSH shells, nested tmux, and non-interactive
# shells (so scp/rsync/cron aren't affected).
# Override the session name by exporting TMUX_DEFAULT_SESSION before login.
if [ -z "\$TMUX" ] && [ -n "\$SSH_CONNECTION" ] && [ -t 0 ] && command -v tmux >/dev/null 2>&1; then
    _mv_session="\${TMUX_DEFAULT_SESSION:-$SESSION_NAME}"
    tmux attach -t "\$_mv_session" 2>/dev/null || tmux new-session -s "\$_mv_session"
    unset _mv_session
fi
$END_MARK
BASHRCBLOCK
    chown "$TARGET_USER:" "$BASHRC"
    echo "✅ Auto-attach snippet written."
fi

# --- UFW rule for mosh ---
if [ "$DO_UFW" = "1" ]; then
    if command -v ufw >/dev/null 2>&1; then
        # Only act if ufw is *active*; inactive ufw means a non-default
        # firewall (iptables rules, cloud-provider firewall, none) is in
        # charge and our rule wouldn't help.
        if ufw status | head -1 | grep -qi "active"; then
            echo ""
            echo "🔥 UFW active — allowing mosh UDP range 60000:61000"
            # `ufw allow` is idempotent — repeating adds a duplicate rule
            # only if the comment differs; pinning the comment keeps it
            # single-entry across re-runs.
            if ! ufw status | grep -q "60000:61000/udp"; then
                ufw allow 60000:61000/udp comment "mosh (managed by install-mosh-tmux.sh)"
            else
                echo "   Rule already present, skipping."
            fi
        else
            echo ""
            echo "ℹ️  UFW present but inactive — skipping firewall rule. If a cloud-"
            echo "   provider firewall is in use instead, open UDP 60000:61000 there"
            echo "   (Vultr, Hostinger, DigitalOcean all have a dashboard firewall)."
        fi
    else
        echo ""
        echo "ℹ️  UFW not installed — skipping firewall rule. If iptables/nftables"
        echo "   or a cloud-provider firewall is in use, open UDP 60000:61000 there."
    fi
fi

# --- Verify ---
echo ""
echo "🎉 Install complete:"
echo "   mosh: $(mosh-server --version 2>/dev/null | head -1 || echo installed)"
echo "   tmux: $(tmux -V)"
echo "   session auto-attach: $SESSION_NAME  (override via \$TMUX_DEFAULT_SESSION)"
echo ""
echo "Next steps:"
echo "  1. On your LOCAL machine, install a mosh client too:"
echo "       Debian/Ubuntu: sudo apt install mosh"
echo "       macOS:         brew install mosh"
echo "       Windows:       use WSL + apt, or mosh's native client"
echo "  2. Reconnect via mosh instead of ssh:"
echo "       mosh $TARGET_USER@<server-host>"
echo "     (or keep ssh — tmux alone still survives ssh drops, mosh just adds"
echo "      seamless roaming on top)."
echo "  3. First login auto-attaches to session '$SESSION_NAME'. Detach with"
echo "     Ctrl-b d; re-attach manually with: tmux attach -t $SESSION_NAME"
echo ""
echo "Re-run this script any time — it's idempotent. To remove: edit out the"
echo "managed blocks in ~/.tmux.conf and ~/.bashrc (they're clearly marked)."
