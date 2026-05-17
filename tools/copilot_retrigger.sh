#!/bin/bash
# Request a GitHub Copilot code review on a PR by adding @copilot as a reviewer.
# Usage: ./tools/copilot_retrigger.sh [PR_NUMBER]
#        ./tools/copilot_retrigger.sh  # Uses current branch's PR
#
# Trigger mechanism: `gh pr edit <PR> --add-reviewer @copilot` (requires gh ≥ 2.88).
# Pre-approved in ~/.claude/settings.json so Claude Code can run it without
# prompting for arbitrary reviewer additions. Equivalent to ticking "Copilot"
# in the GitHub UI's Reviewers menu.
#
# Calibration caveat (first run): whether re-adding an already-requested
# reviewer actually re-triggers Copilot is empirically TBD. If the first PR
# test shows it does NOT re-trigger, swap the gh invocation for the
# remove-then-add fallback (see comment in the body).

set -eo pipefail

if [ -z "$1" ]; then
    BRANCH=$(git branch --show-current)
    if [ -z "$BRANCH" ]; then
        echo "❌ Could not determine current branch" >&2
        exit 1
    fi
    PR_NUMBER=$(gh pr list --head "$BRANCH" --json number -q '.[0].number' 2>/dev/null)
    # `gh pr list -q .[0].number` returns the literal string "null" (not empty)
    # when no PR exists, which would bypass the -z guard and call
    # `gh pr edit "null" ...` later. Reject "null" + require numeric.
    if [ -z "$PR_NUMBER" ] || [ "$PR_NUMBER" = "null" ] || ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
        echo "❌ No PR found for branch: $BRANCH" >&2
        exit 1
    fi
else
    PR_NUMBER="$1"
fi

echo "🔁 Requesting GitHub Copilot review on PR #$PR_NUMBER..."
gh pr edit "$PR_NUMBER" --add-reviewer @copilot

# Fallback (uncomment + comment-out the line above if re-add doesn't retrigger):
# gh pr edit "$PR_NUMBER" --remove-reviewer @copilot 2>/dev/null || true
# gh pr edit "$PR_NUMBER" --add-reviewer @copilot
