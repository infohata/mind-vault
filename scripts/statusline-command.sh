#!/usr/bin/env bash
# Claude Code statusLine command
# Segments: topic | ctx% | turn-tokens | 7d-rate | effort | vim-mode

input=$(cat)

# --- Raw values from JSON ---
session_name=$(echo "$input" | jq -r '.session_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
seven_day=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
in_tok=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // empty')
out_tok=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // empty')
cache_write=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
effort=$(echo "$input" | jq -r '.effort.level // empty')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')

# ANSI helpers
# Orange (#FB8C00 ≈ 256-color 214)
ORANGE='\033[38;5;214m'
ORANGE_BOLD='\033[1;38;5;214m'
YELLOW='\033[33m'
YELLOW_BOLD='\033[1;33m'
CYAN='\033[36m'
GREEN_BOLD='\033[1;32m'
RED_BOLD='\033[1;31m'
DIM='\033[2m'
RESET='\033[0m'

SEP=" $(printf "${DIM}│${RESET}") "

parts=()

# ── 1. Topic (session name, truncated to 20 chars) ──────────────────────────
if [ -n "$session_name" ]; then
    topic="$session_name"
    if [ "${#topic}" -gt 20 ]; then
        topic="${topic:0:19}…"
    fi
    parts+=("$(printf "${ORANGE_BOLD}📌 %s${RESET}" "$topic")")
fi

# ── 2. Context window usage ──────────────────────────────────────────────────
if [ -n "$used_pct" ]; then
    used_int=$(printf '%.0f' "$used_pct")
    if [ "$used_int" -ge 80 ]; then
        parts+=("$(printf "${RED_BOLD}ctx:%d%%${RESET}" "$used_int")")
    elif [ "$used_int" -ge 50 ]; then
        parts+=("$(printf "${YELLOW_BOLD}ctx:%d%%${RESET}" "$used_int")")
    else
        parts+=("$(printf "${DIM}ctx:%d%%${RESET}" "$used_int")")
    fi
fi

# ── 3. Turn token meters (input / output) ────────────────────────────────────
# Format large numbers with k suffix for readability
fmt_tok() {
    local n="$1"
    if [ -z "$n" ] || [ "$n" = "0" ]; then
        echo "0"
    elif [ "$n" -ge 1000 ]; then
        printf '%.1fk' "$(echo "scale=1; $n / 1000" | bc)"
    else
        echo "$n"
    fi
}

if [ -n "$in_tok" ] || [ -n "$out_tok" ]; then
    in_fmt=$(fmt_tok "${in_tok:-0}")
    out_fmt=$(fmt_tok "${out_tok:-0}")
    # Show cache indicators if non-zero
    cache_str=""
    if [ "${cache_read:-0}" -gt 0 ] || [ "${cache_write:-0}" -gt 0 ]; then
        cr_fmt=$(fmt_tok "$cache_read")
        cw_fmt=$(fmt_tok "$cache_write")
        cache_str=" $(printf "${DIM}↺%s+%s${RESET}" "$cr_fmt" "$cw_fmt")"
    fi
    parts+=("$(printf "${ORANGE}⬆%s${RESET}${DIM}/${RESET}${CYAN}⬇%s${RESET}%s" \
        "$in_fmt" "$out_fmt" "$cache_str")")
fi

# ── 4. 7-day rolling rate limit ──────────────────────────────────────────────
if [ -n "$seven_day" ]; then
    week_int=$(printf '%.0f' "$seven_day")
    if [ "$week_int" -ge 80 ]; then
        parts+=("$(printf "${RED_BOLD}7d:%d%%${RESET}" "$week_int")")
    elif [ "$week_int" -ge 50 ]; then
        parts+=("$(printf "${YELLOW}7d:%d%%${RESET}" "$week_int")")
    else
        parts+=("$(printf "${DIM}7d:%d%%${RESET}" "$week_int")")
    fi
fi

# ── 5. Thinking effort ───────────────────────────────────────────────────────
if [ -n "$effort" ]; then
    case "$effort" in
        low)    effort_str="🧠 low"  ; effort_color="$DIM" ;;
        medium) effort_str="🧠 med"  ; effort_color="$YELLOW" ;;
        high)   effort_str="🧠 high" ; effort_color="$ORANGE" ;;
        xhigh)  effort_str="🧠 xhi"  ; effort_color="$ORANGE_BOLD" ;;
        max)    effort_str="🧠 MAX"  ; effort_color="$RED_BOLD" ;;
        *)      effort_str="🧠 $effort" ; effort_color="$DIM" ;;
    esac
    parts+=("$(printf "${effort_color}%s${RESET}" "$effort_str")")
fi

# ── 6. Vim mode ──────────────────────────────────────────────────────────────
if [ -n "$vim_mode" ]; then
    case "$vim_mode" in
        INSERT)      parts+=("$(printf "${GREEN_BOLD}-- INSERT --${RESET}")") ;;
        VISUAL*)     parts+=("$(printf "${ORANGE_BOLD}-- VISUAL --${RESET}")") ;;
        *)           parts+=("$(printf "${YELLOW_BOLD}-- NORMAL --${RESET}")") ;;
    esac
fi

# ── Join with " │ " separator ────────────────────────────────────────────────
result=""
for part in "${parts[@]}"; do
    if [ -z "$result" ]; then
        result="$part"
    else
        result="${result}${SEP}${part}"
    fi
done

printf '%s' "$result"
