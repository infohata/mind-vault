#!/bin/bash
# Description: Install Ubuntu-style shell convenience aliases + a set of git aliases for a user.
# Usage: ./tools/install-aliases.sh [--check] [--no-shell] [--no-git] [--target-user USER]
# Supports: any system with bash + git (Debian/Ubuntu/Fedora/Arch/macOS bash).
#
# Why: A fresh machine ships with none of the muscle-memory shortcuts — `ll`,
# `..`, `gs`, `git lg`. Re-creating them by hand on every new box (or copy-
# pasting a half-remembered dotfile) is error-prone. This installs two layers
# in one idempotent, re-runnable pass:
#
#   * Shell aliases  -> a marker-bounded block in ~/.bash_aliases (the Debian
#     idiom), with ~/.bashrc wired to source it if it isn't already.
#   * Git aliases    -> git's own `alias.*` config in the user's ~/.gitconfig,
#     so `git st`, `git lg`, `git amend` work in any shell.
#
# Flags:
#   --check                Report current state, exit. No writes.
#   --no-shell             Skip the shell aliases (git only).
#   --no-git               Skip the git aliases (shell only).
#   --target-user USER     User whose ~/.bash_aliases / ~/.gitconfig to set up.
#                          Default: $SUDO_USER under sudo, else the current user.
#   -h, --help             Show this header and exit.

set -eo pipefail

CHECK_ONLY=0
DO_SHELL=1
DO_GIT=1
TARGET_USER=""

while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK_ONLY=1; shift ;;
        --no-shell) DO_SHELL=0; shift ;;
        --no-git) DO_GIT=0; shift ;;
        --target-user)
            if [ -z "${2:-}" ]; then
                echo "❌ --target-user requires a value (e.g. --target-user kestas)." >&2
                exit 1
            fi
            TARGET_USER="$2"
            shift 2
            ;;
        -h|--help)
            awk 'NR==1 && /^#!/ { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
            exit 0
            ;;
        *)
            echo "❌ Unknown argument: $1" >&2
            echo "   Run with --help for usage." >&2
            exit 1
            ;;
    esac
done

if [ "$DO_SHELL" = "0" ] && [ "$DO_GIT" = "0" ]; then
    echo "❌ Nothing to do: --no-shell and --no-git together leave no work." >&2
    exit 1
fi

# --- Target-user resolution (pattern 13) ---
if [ -z "$TARGET_USER" ]; then
    TARGET_USER="${SUDO_USER:-$USER}"
fi
if [ "$TARGET_USER" = "root" ]; then
    echo "⚠️  Target user resolved to root; edits will land in /root."
    echo "    If you meant a non-root user, pass --target-user NAME."
fi
if ! id -u "$TARGET_USER" >/dev/null 2>&1; then
    echo "❌ User '$TARGET_USER' does not exist on this system." >&2
    echo "   Pass --target-user NAME with an existing account." >&2
    exit 1
fi
# Pipeline-in-assignment is safe here: existence pre-validated above (pattern 2).
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
    echo "❌ Could not resolve a home directory for '$TARGET_USER'." >&2
    exit 1
fi

CURRENT_USER=$(id -un)
ALIASES_FILE="$TARGET_HOME/.bash_aliases"
BASHRC="$TARGET_HOME/.bashrc"

# Managed-block markers (fixed strings — see patterns 7, 14).
ALIAS_BEGIN="# BEGIN mind-vault-aliases (managed by install-aliases.sh)"
ALIAS_END="# END mind-vault-aliases"
SRC_BEGIN="# BEGIN mind-vault-aliases-source (managed by install-aliases.sh)"
SRC_END="# END mind-vault-aliases-source"

# Run a git command AS the target user so --global hits their ~/.gitconfig.
# -H sets HOME to the target user's home, making --global deterministic.
run_git() {
    if [ "$TARGET_USER" = "$CURRENT_USER" ]; then
        git "$@"
    else
        sudo -H -u "$TARGET_USER" git "$@"
    fi
}

# chown a file we just wrote back to the target user (trailing colon = the
# user's primary group, portable — pattern 4). Only meaningful cross-user.
chown_if_needed() {
    if [ "$TARGET_USER" != "$CURRENT_USER" ]; then
        chown "$TARGET_USER:" "$1"
    fi
}

# Strip a marker-bounded block from a file, with orphan detection and
# BRE-escaped sed addresses (pattern 7). No-op if the file/block is absent.
strip_managed_block() {  # $1=file  $2=begin-marker  $3=end-marker
    local file="$1" begin="$2" end="$3" begin_re end_re
    [ -f "$file" ] || return 0
    if grep -qF "$begin" "$file" && ! grep -qF "$end" "$file"; then
        echo "❌ Orphan managed block in $file: BEGIN marker without END." >&2
        echo "   Restore the '$end' line or delete the block by hand, then re-run." >&2
        exit 1
    fi
    if grep -qF "$begin" "$file" && grep -qF "$end" "$file"; then
        begin_re=$(printf '%s' "$begin" | sed -e 's/[][\/.*^$]/\\&/g')
        end_re=$(printf '%s' "$end" | sed -e 's/[][\/.*^$]/\\&/g')
        sed -i "/$begin_re/,/$end_re/d" "$file"
    fi
}

# The git aliases. Split on the FIRST '=': alias names never contain '=', so
# values keep their internal '=' (e.g. lg's --format=format:...).
GIT_ALIASES=(
    "st=status"
    "co=checkout"
    "br=branch"
    "ci=commit"
    "cm=commit -m"
    "aa=add --all"
    "unstage=reset HEAD --"
    "last=log -1 HEAD --stat"
    "ll=log --oneline --decorate --graph -20"
    "amend=commit --amend --no-edit"
    "uncommit=reset --soft HEAD~1"
    "aliases=config --get-regexp ^alias\\."
    'wip=!git add -A && git commit -m "WIP"'
    "lg=log --graph --abbrev-commit --decorate --all --format=format:'%C(bold blue)%h%C(reset) %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(auto)%d%C(reset)'"
)

# ---------------------------------------------------------------------------
# State check
# ---------------------------------------------------------------------------
SHELL_OK=0
GIT_OK=0
GIT_HAVE=0
GIT_TOTAL=${#GIT_ALIASES[@]}

if [ "$DO_SHELL" = "1" ]; then
    if [ -f "$ALIASES_FILE" ] && grep -qF "$ALIAS_BEGIN" "$ALIASES_FILE" 2>/dev/null; then
        # block present AND .bashrc sources .bash_aliases somehow
        if grep -qsF '.bash_aliases' "$BASHRC"; then
            SHELL_OK=1
        fi
    fi
fi

if [ "$DO_GIT" = "1" ]; then
    for pair in "${GIT_ALIASES[@]}"; do
        name="${pair%%=*}"
        want="${pair#*=}"
        have=$(run_git config --global --get "alias.$name" 2>/dev/null || true)
        [ "$have" = "$want" ] && GIT_HAVE=$((GIT_HAVE + 1))
    done
    [ "$GIT_HAVE" -eq "$GIT_TOTAL" ] && GIT_OK=1
fi

echo "🔍 State for user '$TARGET_USER' (home: $TARGET_HOME):"
if [ "$DO_SHELL" = "1" ]; then
    [ "$SHELL_OK" = "1" ] && echo "   shell aliases: ✅ installed ($ALIASES_FILE)" \
                          || echo "   shell aliases: ❌ not installed"
else
    echo "   shell aliases: n/a (--no-shell)"
fi
if [ "$DO_GIT" = "1" ]; then
    [ "$GIT_OK" = "1" ] && echo "   git aliases:   ✅ all $GIT_TOTAL present" \
                        || echo "   git aliases:   ❌ $GIT_HAVE/$GIT_TOTAL present"
else
    echo "   git aliases:   n/a (--no-git)"
fi

if [ "$CHECK_ONLY" = "1" ]; then
    CHECK_FAIL=0
    [ "$DO_SHELL" = "1" ] && [ "$SHELL_OK" = "0" ] && CHECK_FAIL=1
    [ "$DO_GIT" = "1" ] && [ "$GIT_OK" = "0" ] && CHECK_FAIL=1
    [ "$CHECK_FAIL" -eq 0 ] && exit 0
    exit 1
fi

# ---------------------------------------------------------------------------
# Install: shell aliases
# ---------------------------------------------------------------------------
if [ "$DO_SHELL" = "1" ]; then
    echo ""
    echo "📝 Writing shell aliases to $ALIASES_FILE ..."
    [ -f "$ALIASES_FILE" ] || { : > "$ALIASES_FILE"; chown_if_needed "$ALIASES_FILE"; }

    strip_managed_block "$ALIASES_FILE" "$ALIAS_BEGIN" "$ALIAS_END"

    # Markers via printf (need the var values); body via quoted heredoc so
    # nothing inside expands. The blank line sits INSIDE the range so re-runs
    # reclaim it (pattern 12).
    {
        printf '%s\n\n' "$ALIAS_BEGIN"
        cat <<'ALIASBODY'
# Ubuntu-style convenience aliases. Managed block — edit the installer
# (tools/install-aliases.sh), not these lines: re-running overwrites them.

# --- ls family ---
alias ll='ls -alF'      # long listing, all files, type indicators
alias la='ls -A'        # all except . and ..
alias l='ls -CF'        # columns, type indicators
alias lt='ls -alFtr'    # long listing by time, newest last

# --- colorized grep ---
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# --- navigation ---
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# --- safety nets (prompt before clobbering) ---
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# --- git shortcuts ---
alias g='git'
alias gs='git status'
alias gss='git status -s'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gco='git checkout'
alias gb='git branch'
alias gd='git diff'
alias gds='git diff --staged'
alias gp='git push'
alias gpl='git pull'
alias gl='git log --oneline --decorate --graph -20'

# --- misc conveniences ---
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias mkdir='mkdir -pv'
alias h='history'
alias path='echo "$PATH" | tr ":" "\n"'
ALIASBODY
        printf '%s\n' "$ALIAS_END"
    } >> "$ALIASES_FILE"
    chown_if_needed "$ALIASES_FILE"

    # Ensure ~/.bashrc sources ~/.bash_aliases. Stock Debian/Ubuntu .bashrc
    # already does; only add our managed source-guard when nothing references
    # it. Strip our old guard first so the detection below is accurate.
    [ -f "$BASHRC" ] || { : > "$BASHRC"; chown_if_needed "$BASHRC"; }
    strip_managed_block "$BASHRC" "$SRC_BEGIN" "$SRC_END"
    if ! grep -qsF '.bash_aliases' "$BASHRC"; then
        {
            printf '%s\n' "$SRC_BEGIN"
            printf '%s\n' 'if [ -f ~/.bash_aliases ]; then . ~/.bash_aliases; fi'
            printf '%s\n' "$SRC_END"
        } >> "$BASHRC"
        chown_if_needed "$BASHRC"
        echo "   ↳ wired ~/.bashrc to source ~/.bash_aliases"
    fi
    echo "✅ Shell aliases installed."
fi

# ---------------------------------------------------------------------------
# Install: git aliases
# ---------------------------------------------------------------------------
if [ "$DO_GIT" = "1" ]; then
    echo ""
    echo "📝 Setting $GIT_TOTAL git aliases in ${TARGET_HOME}/.gitconfig ..."
    for pair in "${GIT_ALIASES[@]}"; do
        name="${pair%%=*}"
        value="${pair#*=}"
        run_git config --global "alias.$name" "$value"
    done
    echo "✅ Git aliases installed."
fi

# ---------------------------------------------------------------------------
# Verify + hints
# ---------------------------------------------------------------------------
echo ""
echo "🎉 Done."
if [ "$DO_SHELL" = "1" ]; then
    echo "   Shell aliases take effect in NEW shells. For the current one:"
    echo "       source ~/.bashrc"
fi
if [ "$DO_GIT" = "1" ]; then
    echo "   Git aliases are live immediately. List them anytime with:"
    echo "       git aliases"
fi
