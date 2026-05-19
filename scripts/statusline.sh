#!/usr/bin/env bash
# ~/.claude/statusline.sh
# Claude Code status line — reads JSON from stdin, emits one line.

input=$(cat)

# ANSI helpers (dim/reset only — status line is already rendered dimmed by Claude Code)
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

SEP=" ${DIM}│${RESET} "

# --- Session / location ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // ""')

# Show project dir basename if it differs from cwd, otherwise show cwd basename
if [ -n "$project_dir" ] && [ "$project_dir" != "$cwd" ]; then
    dir_label=$(basename "$project_dir")
    rel="${cwd#$project_dir}"
    rel="${rel#/}"
    [ -n "$rel" ] && dir_label="${dir_label}/${rel}"
else
    dir_label=$(basename "${cwd:-$PWD}")
fi

# Git branch (fast, no locks)
git_branch=""
if git_out=$(git -C "${cwd:-$PWD}" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null); then
    git_branch="$git_out"
fi

if [ -n "$git_branch" ]; then
    location="${CYAN}${dir_label}${RESET} ${DIM}(${git_branch})${RESET}"
else
    location="${CYAN}${dir_label}${RESET}"
fi

# --- Model ---
model=$(echo "$input" | jq -r '.model.display_name // .model.id // ""')
if [ -n "$model" ]; then
    model_str="${model}"
else
    model_str="unknown model"
fi

# --- Context window ---
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_str=""
if [ -n "$used_pct" ]; then
    # Colour-code by usage: green < 60, yellow 60-85, red > 85
    used_int=$(printf '%.0f' "$used_pct")
    remaining_int=$((100 - used_int))
    if [ "$used_int" -ge 85 ]; then
        ctx_colour="${RED}"
    elif [ "$used_int" -ge 60 ]; then
        ctx_colour="${YELLOW}"
    else
        ctx_colour="${GREEN}"
    fi
    ctx_str="ctx ${ctx_colour}${remaining_int}%${RESET} left"
fi

# --- Rate limits ---
rate_str=""
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

if [ -n "$five_pct" ] || [ -n "$week_pct" ]; then
    parts=""
    if [ -n "$five_pct" ]; then
        five_used=$(printf '%.0f' "$five_pct")
        five_remaining=$((100 - five_used))
        if [ "$five_used" -ge 85 ]; then
            rl_colour="${RED}"
        elif [ "$five_used" -ge 60 ]; then
            rl_colour="${YELLOW}"
        else
            rl_colour="${GREEN}"
        fi
        # Show reset time if heavily used
        reset_str=""
        if [ -n "$five_reset" ] && [ "$five_used" -ge 60 ]; then
            now=$(date +%s)
            diff=$(( five_reset - now ))
            if [ "$diff" -gt 0 ]; then
                mins=$(( diff / 60 ))
                if [ "$mins" -ge 60 ]; then
                    hrs=$(( mins / 60 ))
                    mins=$(( mins % 60 ))
                    reset_str=" ~${hrs}h${mins}m"
                else
                    reset_str=" ~${mins}m"
                fi
            fi
        fi
        parts="5h:${rl_colour}${five_remaining}%${RESET}${DIM}${reset_str}${RESET}"
    fi
    if [ -n "$week_pct" ]; then
        week_used=$(printf '%.0f' "$week_pct")
        week_remaining=$((100 - week_used))
        if [ "$week_used" -ge 85 ]; then
            wk_colour="${RED}"
        elif [ "$week_used" -ge 60 ]; then
            wk_colour="${YELLOW}"
        else
            wk_colour="${GREEN}"
        fi
        wk_str="7d:${wk_colour}${week_remaining}%${RESET}"
        [ -n "$parts" ] && parts="${parts} ${wk_str}" || parts="$wk_str"
    fi
    rate_str="$parts"
fi

# --- Effort / thinking ---
effort_str=""
effort_level=$(echo "$input" | jq -r '.effort.level // empty')
thinking=$(echo "$input" | jq -r '.thinking.enabled // false')
if [ -n "$effort_level" ]; then
    effort_str="effort:${effort_level}"
fi
if [ "$thinking" = "true" ]; then
    [ -n "$effort_str" ] && effort_str="${effort_str} think" || effort_str="think"
fi

# --- Assemble line ---
line="${location}${SEP}${model_str}"
[ -n "$ctx_str" ]    && line="${line}${SEP}${ctx_str}"
[ -n "$rate_str" ]   && line="${line}${SEP}${rate_str}"
[ -n "$effort_str" ] && line="${line}${SEP}${DIM}${effort_str}${RESET}"

printf "%b\n" "$line"
