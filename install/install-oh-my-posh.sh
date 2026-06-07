#!/bin/bash
# Description: Install Oh My Posh prompt theme engine for the current user + wire it into the shell rc
# Usage: ./install/install-oh-my-posh.sh [flags]
# Supports: Linux / macOS, bash / zsh (pwsh init line emitted but rc edit not attempted)
#
# Why: Fresh servers don't ship Oh My Posh, and the getting-started docs assume
# you'll copy-paste curl-sh + one init line + one theme download. This script
# does all three idempotently, defaults to the `atomic` theme (author's pick),
# and supports a numbered interactive menu for picking a different prompt style.
#
# What it does:
#   1. Idempotency check: if oh-my-posh is already on PATH and the rc file is
#      already wired, re-use the install. Theme change still supported.
#   2. Downloads the latest oh-my-posh binary to $INSTALL_DIR (default
#      ~/.local/bin) via the official install.sh.
#   3. Downloads the selected theme JSON to $POSH_THEMES_PATH
#      (default ~/.cache/oh-my-posh/themes).
#   4. Wires an init block into ~/.bashrc or ~/.zshrc (detected from $SHELL),
#      bounded by BEGIN/END markers so re-runs overwrite instead of duplicate.
#   5. Optional Nerd Font check — warns but does not block.
#
# Flags:
#   --theme NAME         Install & activate the named theme (default: atomic)
#   --interactive        Show a numbered menu of common themes; pick one
#   --check              Report current install state and exit. No writes.
#   --install-dir PATH   Where to install the oh-my-posh binary (default: ~/.local/bin)
#   --themes-dir PATH    Where to store theme JSONs (default: ~/.cache/oh-my-posh/themes)
#   --shell bash|zsh|pwsh  Force shell (default: derived from $SHELL)
#   --no-rc-edit         Install binary + theme but don't touch the shell rc
#   -h, --help           Show this header and exit

set -eo pipefail

CHECK_ONLY=0
INTERACTIVE=0
THEME="atomic"
INSTALL_DIR="${HOME}/.local/bin"
THEMES_DIR="${POSH_THEMES_PATH:-${HOME}/.cache/oh-my-posh/themes}"
FORCE_SHELL=""
RC_EDIT=1

# Curated interactive menu — popular, stylistically distinct themes.
MENU_THEMES=(
    "atomic"
    "jandedobbeleer"
    "agnoster"
    "paradox"
    "powerlevel10k_classic"
    "powerlevel10k_lean"
    "robbyrussell"
    "star"
    "tokyonight_storm"
    "zash"
)

while [ $# -gt 0 ]; do
    case "$1" in
        --theme) THEME="$2"; shift 2 ;;
        --interactive) INTERACTIVE=1; shift ;;
        --check) CHECK_ONLY=1; shift ;;
        --install-dir) INSTALL_DIR="$2"; shift 2 ;;
        --themes-dir) THEMES_DIR="$2"; shift 2 ;;
        --shell) FORCE_SHELL="$2"; shift 2 ;;
        --no-rc-edit) RC_EDIT=0; shift ;;
        -h|--help)
            # Print only the contiguous top-of-file comment header (skip the
            # shebang, stop at the first non-`#` line). Preemptive fix of the
            # same issue bugbot flagged on install/install-docker.sh in PR #52 —
            # a body-scoped `grep '^# '` would mix section dividers and inline
            # comments into the help output and drop `#`-only paragraph lines.
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

# --- Detect shell ---
if [ -n "$FORCE_SHELL" ]; then
    SHELL_NAME="$FORCE_SHELL"
else
    SHELL_NAME="$(basename "${SHELL:-bash}")"
fi

case "$SHELL_NAME" in
    bash) RC_FILE="${HOME}/.bashrc" ;;
    zsh)  RC_FILE="${HOME}/.zshrc" ;;
    pwsh) RC_FILE="" ;;
    *)
        echo "⚠️  Unsupported shell: $SHELL_NAME (bash / zsh / pwsh supported)"
        echo "   Skipping rc edit. Use --no-rc-edit to silence, or --shell bash|zsh."
        RC_EDIT=0
        RC_FILE=""
        ;;
esac

# --- State report ---
POSH_BIN=""
POSH_VERSION=""
if command -v oh-my-posh >/dev/null 2>&1; then
    POSH_BIN="$(command -v oh-my-posh)"
    POSH_VERSION="$(oh-my-posh --version 2>/dev/null || echo unknown)"
fi

RC_WIRED=0
if [ -n "$RC_FILE" ] && [ -f "$RC_FILE" ] && grep -q 'BEGIN oh-my-posh' "$RC_FILE" 2>/dev/null; then
    RC_WIRED=1
fi

echo "🔍 Oh My Posh install state:"
if [ -n "$POSH_BIN" ]; then
    echo "   ✅ binary: $POSH_BIN ($POSH_VERSION)"
else
    echo "   ❌ binary: not found on PATH"
fi
if [ -n "$RC_FILE" ]; then
    if [ "$RC_WIRED" = "1" ]; then
        echo "   ✅ rc file wired: $RC_FILE"
    else
        echo "   ❌ rc file not wired: $RC_FILE (will add BEGIN/END block)"
    fi
fi
echo "   Selected theme: $THEME"
echo "   Install dir:    $INSTALL_DIR"
echo "   Themes dir:     $THEMES_DIR"

if [ "$CHECK_ONLY" = "1" ]; then
    # Install is complete when the binary exists AND either the rc file is
    # wired OR the selected shell doesn't use an rc file (pwsh / unsupported).
    # Previous `[ -z "$POSH_BIN" ] && [ "$RC_WIRED" = "1" ]` always failed for
    # pwsh because $RC_FILE is empty → RC_WIRED stays 0 even on a correct install.
    if [ -n "$POSH_BIN" ] && { [ -z "$RC_FILE" ] || [ "$RC_WIRED" = "1" ]; }; then
        exit 0
    else
        exit 1
    fi
fi

# --- Interactive menu ---
if [ "$INTERACTIVE" = "1" ]; then
    echo ""
    echo "📜 Pick a theme:"
    for i in "${!MENU_THEMES[@]}"; do
        num=$((i + 1))
        name="${MENU_THEMES[$i]}"
        marker=""
        [ "$name" = "atomic" ] && marker=" (default)"
        printf "  %2d) %s%s\n" "$num" "$name" "$marker"
    done
    echo ""
    read -r -p "Number [1 = atomic]: " choice
    choice="${choice:-1}"
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#MENU_THEMES[@]}" ]; then
        echo "❌ Invalid selection: $choice" >&2
        exit 1
    fi
    THEME="${MENU_THEMES[$((choice - 1))]}"
    echo "   → $THEME"
fi

# --- Nerd Font advisory ---
if command -v fc-list >/dev/null 2>&1; then
    if ! fc-list 2>/dev/null | grep -qi "nerd font"; then
        echo ""
        echo "⚠️  No Nerd Font detected. Oh My Posh prompt glyphs will render as tofu."
        echo "   Install one from https://www.nerdfonts.com (FiraCode Nerd Font is a popular pick),"
        echo "   then point your terminal emulator's font_family at it."
    fi
fi

# --- Ensure install dir ---
mkdir -p "$INSTALL_DIR"
if ! echo ":$PATH:" | grep -q ":$INSTALL_DIR:"; then
    echo ""
    echo "⚠️  $INSTALL_DIR is not on your PATH."
    echo "   Add to your rc file: export PATH=\"$INSTALL_DIR:\$PATH\""
fi

# --- Install binary ---
if [ -z "$POSH_BIN" ]; then
    echo ""
    echo "⬇️  Installing oh-my-posh binary to $INSTALL_DIR..."
    curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d "$INSTALL_DIR"
else
    echo ""
    echo "✅ oh-my-posh binary already present; skipping download."
    echo "   To upgrade: curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d \"$INSTALL_DIR\""
fi

# --- Download theme ---
mkdir -p "$THEMES_DIR"
THEME_FILE="$THEMES_DIR/$THEME.omp.json"
if [ ! -f "$THEME_FILE" ]; then
    echo ""
    echo "⬇️  Downloading theme $THEME..."
    THEME_URL="https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/$THEME.omp.json"
    if ! curl -fsSL "$THEME_URL" -o "$THEME_FILE"; then
        echo "❌ Failed to download theme $THEME from $THEME_URL" >&2
        echo "   Theme list: https://ohmyposh.dev/docs/themes" >&2
        rm -f "$THEME_FILE"
        exit 1
    fi
    echo "   → $THEME_FILE"
else
    echo ""
    echo "✅ Theme already cached at $THEME_FILE"
fi

# --- RC edit ---
if [ "$RC_EDIT" = "1" ] && [ -n "$RC_FILE" ]; then
    echo ""
    echo "📝 Wiring $RC_FILE..."
    # Remove any existing managed block
    if [ -f "$RC_FILE" ] && grep -q 'BEGIN oh-my-posh (managed by install-oh-my-posh.sh)' "$RC_FILE"; then
        # Portable block-delete: keep everything outside the markers, AND
        # strip trailing blank lines. Without the blank-strip, each re-run
        # would accumulate one extra blank before `# BEGIN` (the awk removal
        # only strips lines inside the markers, so the leading blank from a
        # previous install's append survives and compounds on the next).
        #
        # Logic: blank lines are buffered in `pending` and only emitted when
        # a non-blank line follows. At EOF, buffered blanks are dropped. This
        # preserves legitimate single-blank separators between user content
        # paragraphs while dropping the trailing ones before the (now removed)
        # managed block.
        #
        # NOTE: `mv` from an mktemp (0600) file would destroy the rc file's
        # original permissions (typically 0644) on re-run. Use `cat >` +
        # `rm` to write content in place while preserving the original file's
        # inode and permissions.
        tmpfile="$(mktemp)"
        awk '
            /# BEGIN oh-my-posh \(managed by install-oh-my-posh.sh\)/ { skip=1; next }
            /# END oh-my-posh \(managed by install-oh-my-posh.sh\)/   { skip=0; next }
            !skip {
                if ($0 ~ /^[[:space:]]*$/) {
                    pending = pending $0 "\n"
                } else {
                    printf "%s", pending
                    pending = ""
                    print
                }
            }
        ' "$RC_FILE" > "$tmpfile"
        cat "$tmpfile" > "$RC_FILE"
        rm -f "$tmpfile"
    fi

    # Append the fresh block.
    {
        echo ""
        echo "# BEGIN oh-my-posh (managed by install-oh-my-posh.sh)"
        echo "export POSH_THEMES_PATH=\"$THEMES_DIR\""
        echo "if command -v oh-my-posh >/dev/null 2>&1; then"
        echo "    eval \"\$(oh-my-posh init $SHELL_NAME --config \"\$POSH_THEMES_PATH/$THEME.omp.json\")\""
        echo "fi"
        echo "# END oh-my-posh (managed by install-oh-my-posh.sh)"
    } >> "$RC_FILE"
    echo "   ✅ block added to $RC_FILE"
fi

# --- Done ---
echo ""
echo "🎉 Install complete:"
echo "   Binary:  $(command -v oh-my-posh 2>/dev/null || echo "$INSTALL_DIR/oh-my-posh")"
echo "   Theme:   $THEME_FILE"
if [ "$RC_EDIT" = "1" ] && [ -n "$RC_FILE" ]; then
    echo "   Wired:   $RC_FILE"
    echo ""
    echo "Next: open a new shell (or: source $RC_FILE) to see the new prompt."
else
    if [ "$SHELL_NAME" = "pwsh" ]; then
        echo ""
        echo "PowerShell init line (add to your \$PROFILE):"
        echo "    oh-my-posh init pwsh --config \"$THEME_FILE\" | Invoke-Expression"
    else
        echo ""
        echo "RC edit skipped. Add this to your shell rc manually:"
        echo "    eval \"\$(oh-my-posh init $SHELL_NAME --config \"$THEME_FILE\")\""
    fi
fi
