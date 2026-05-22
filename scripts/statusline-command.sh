#!/usr/bin/env bash
# Claude Code statusLine command
# Segments: topic | ctx% | turn-tokens | 7d-rate | effort | vim-mode
#
# Runtime dependency: jq. If missing, the status line falls back to a single
# "jq missing" segment so Claude Code keeps rendering without erroring out.

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

# Graceful degradation if jq isn't on PATH — print one segment and bail.
if ! command -v jq >/dev/null 2>&1; then
    printf "${DIM}📌${RESET} ${YELLOW_BOLD}jq missing — install jq for status line${RESET}"
    exit 0
fi

input=$(cat)

# --- Raw values from JSON — single jq invocation, newline-per-field, parsed below ---
# Hot path: Claude Code re-renders the status line on every tick, so 9 separate
# `echo | jq` calls (one per field) was 9 process spawns per render. Single
# invocation drops that to 1.
#
# Newline-per-field (not @tsv): bash `read` with IFS=$'\t' collapses consecutive
# tab separators because tab counts as whitespace, which loses leading-empty
# fields and shifts subsequent positions. A `while IFS= read -r` loop with
# default `\n` separator preserves empties as distinct lines.
#
# bash-3 compatibility: avoid `mapfile` (Bash 4+) so macOS's default Bash 3.2
# doesn't error with `mapfile: command not found`. The read-loop pattern below
# is portable.
_sl_fields=()
while IFS= read -r _sl_line; do
    _sl_fields+=("$_sl_line")
done < <(jq -r '
    .session_name // "",
    (.context_window.used_percentage // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.context_window.current_usage.input_tokens // ""),
    (.context_window.current_usage.output_tokens // ""),
    (.context_window.current_usage.cache_creation_input_tokens // 0),
    (.context_window.current_usage.cache_read_input_tokens // 0),
    (.effort.level // ""),
    (.vim.mode // "")
' <<< "$input")
session_name="${_sl_fields[0]:-}"
used_pct="${_sl_fields[1]:-}"
seven_day="${_sl_fields[2]:-}"
in_tok="${_sl_fields[3]:-}"
out_tok="${_sl_fields[4]:-}"
cache_write="${_sl_fields[5]:-0}"
cache_read="${_sl_fields[6]:-0}"
effort="${_sl_fields[7]:-}"
vim_mode="${_sl_fields[8]:-}"

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
# Format large numbers with k suffix for readability. Pure bash arithmetic
# (no `bc` dependency) — N >= 1000 emits "<int>.<tenth>k", smaller emits the
# raw integer. Negative/zero input collapses to "0".
fmt_tok() {
    local n="${1:-0}"
    if [ -z "$n" ] || [ "$n" -le 0 ]; then
        printf '0'
    elif [ "$n" -ge 1000 ]; then
        # integer division for the thousands, integer modulo for the tenth
        printf '%d.%dk' "$((n / 1000))" "$(((n % 1000) / 100))"
    else
        printf '%d' "$n"
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
# Tier colors mirror ctx exactly: dim (<50) / yellow-bold (50-79) / red-bold (≥80).
if [ -n "$seven_day" ]; then
    week_int=$(printf '%.0f' "$seven_day")
    if [ "$week_int" -ge 80 ]; then
        parts+=("$(printf "${RED_BOLD}7d:%d%%${RESET}" "$week_int")")
    elif [ "$week_int" -ge 50 ]; then
        parts+=("$(printf "${YELLOW_BOLD}7d:%d%%${RESET}" "$week_int")")
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
