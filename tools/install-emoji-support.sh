#!/bin/bash
# Description: Install color emoji font support on Linux terminals
# Usage: ./tools/install-emoji-support.sh [--check]
# Supports: Debian/Ubuntu (apt), Fedora/RHEL (dnf), Arch (pacman), openSUSE (zypper)
#
# Why: Many Linux installs ship without a color emoji font, so terminals render
# emojis as tofu or monochrome glyphs. This installs Noto Color Emoji (or the
# distro's equivalent) and refreshes the fontconfig cache.
#
# Terminal compatibility:
#   ✅ kitty, wezterm, gnome-terminal, konsole, foot — native color emoji
#   ⚠️  xfce4-terminal — works on recent versions, check font stack
#   ❌ xterm, urxvt — monochrome only, terminal limitation not fixable here

set -e

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then
    CHECK_ONLY=1
fi

# --- Detect current emoji font ---
echo "🔍 Checking current emoji font availability..."
EMOJI_FONTS=$(fc-list :lang=und-zsye family 2>/dev/null | sort -u || true)

if [ -n "$EMOJI_FONTS" ]; then
    # Check for any color emoji font (not just Symbola which is monochrome)
    if echo "$EMOJI_FONTS" | grep -qiE "noto color emoji|twemoji|emoji one|joypixels|apple color emoji|segoe ui emoji"; then
        echo "✅ Color emoji font already installed:"
        echo "$EMOJI_FONTS" | sed 's/^/   /'
        [ "$CHECK_ONLY" = "1" ] && exit 0
        echo ""
        echo "Nothing to do. If emojis still render as tofu, check:"
        echo "  1. Terminal emulator supports color glyphs (kitty/wezterm/gnome-terminal ✅)"
        echo "  2. Terminal's font_family config doesn't override the fontconfig fallback"
        exit 0
    fi
    echo "⚠️  Found monochrome emoji fonts only:"
    echo "$EMOJI_FONTS" | sed 's/^/   /'
else
    echo "⚠️  No emoji fonts installed."
fi

if [ "$CHECK_ONLY" = "1" ]; then
    echo ""
    echo "Run without --check to install a color emoji font."
    exit 1
fi

# --- Detect package manager ---
PKG=""
INSTALL_CMD=""
PACKAGE=""

if command -v apt-get >/dev/null 2>&1; then
    PKG="apt"
    INSTALL_CMD="sudo apt-get install -y"
    PACKAGE="fonts-noto-color-emoji"
elif command -v dnf >/dev/null 2>&1; then
    PKG="dnf"
    INSTALL_CMD="sudo dnf install -y"
    PACKAGE="google-noto-emoji-color-fonts"
elif command -v pacman >/dev/null 2>&1; then
    PKG="pacman"
    INSTALL_CMD="sudo pacman -S --noconfirm"
    PACKAGE="noto-fonts-emoji"
elif command -v zypper >/dev/null 2>&1; then
    PKG="zypper"
    INSTALL_CMD="sudo zypper install -y"
    PACKAGE="noto-coloremoji-fonts"
else
    echo "❌ Unsupported package manager."
    echo "   Install a color emoji font manually (Noto Color Emoji recommended)."
    exit 1
fi

echo ""
echo "📦 Detected $PKG — will install $PACKAGE"
echo "   Command: $INSTALL_CMD $PACKAGE"
echo ""

# --- Install ---
$INSTALL_CMD "$PACKAGE"

# --- Refresh fontconfig cache ---
echo ""
echo "🔄 Refreshing fontconfig cache..."
fc-cache -f

# --- Verify ---
echo ""
echo "✅ Verification:"
NEW_FONTS=$(fc-list :lang=und-zsye family 2>/dev/null | sort -u)
if echo "$NEW_FONTS" | grep -qi "noto color emoji\|twemoji\|joypixels"; then
    echo "$NEW_FONTS" | sed 's/^/   /'
    echo ""
    echo "🎉 Done. Restart your terminal (or open a new tab) to pick up the new font."
    echo ""
    echo "Test with: echo '✅ ⚠️ 🔍 📚 🎉 🚀'"
else
    echo "⚠️  Installation completed but no color emoji font detected — investigate manually."
    exit 1
fi
