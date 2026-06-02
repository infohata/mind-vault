#!/bin/bash
# Bootstrap a Claude Code Review on a PR by posting "@claude review once".
# Usage: ./tools/claude_retrigger.sh [PR_NUMBER]
#        ./tools/claude_retrigger.sh  # Uses current branch's PR
#
# ⚠️ FALLBACK ONLY — claude is a PUSH-TRIGGERED engine (architect A7 / R2).
# The `claude-code-review.yml` action auto-runs on every push (`synchronize`),
# so a fix push IS the retrigger. /review-loop's Phase 3 does NOT call this after
# a fix push — doing so would double-run the action on one head SHA (the
# synchronize auto-run + this explicit comment) and create a "which run is
# authoritative" race. (find_claude_comments.sh dedups by selecting the latest
# Actions run by run_started_at, but avoiding the double-run is cleaner.)
#
# This script exists for ONE case: the zero-activity bootstrap when
# find_claude_comments.sh finds NO Actions run at all for the head SHA (e.g. the
# auto-run never fired — fresh PR before the action settled, or a workflow that
# was just installed). Then the loop posts this once to kick a review.
#
# The body is hard-coded to "@claude review once" so Claude Code can pre-approve
# this script in ~/.claude/settings.json without risk of arbitrary comment
# injection. Idempotent: posting twice just queues another review; the action's
# run dedup (latest by run_started_at) collapses overlapping runs to one signal.
#
# CALIBRATE (Q2 — dogfood step 9): whether "@claude review once" triggers a
# `code-review` run THROUGH THE ACTION path (vs the managed service the docs
# describe) is empirically TBD. If the first run shows it does NOT trigger a
# code-review run, swap the body for the explicit plugin invocation fallback:
#   gh pr comment "$PR_NUMBER" --body "@claude /code-review:code-review $REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER"
# (wordier but deterministic — see the commented fallback below).

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
    # `gh pr comment "null" ...` later. Reject "null" + require numeric.
    if [ -z "$PR_NUMBER" ] || [ "$PR_NUMBER" = "null" ] || ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
        echo "❌ No PR found for branch: $BRANCH" >&2
        exit 1
    fi
else
    # Accept either a bare PR number or a full PR URL.
    if [[ "$1" =~ ^https?://github\.com/[^/]+/[^/]+/pull/([0-9]+)/?$ ]]; then
        PR_NUMBER="${BASH_REMATCH[1]}"
    else
        PR_NUMBER="$1"
    fi
    if [ -z "$PR_NUMBER" ] || ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
        echo "❌ Invalid PR number: '$1'" >&2
        echo "   Expected a numeric PR id or a GitHub PR URL." >&2
        exit 1
    fi
fi

echo "🔁 Bootstrapping a Claude review on PR #$PR_NUMBER (fallback — claude is normally push-triggered)..."
gh pr comment "$PR_NUMBER" --body "@claude review once"

# Fallback (Q2) — uncomment + comment-out the line above if "@claude review once"
# does NOT trigger a code-review run through the action path:
# REPO_OWNER=$(gh repo view --json owner -q '.owner.login')
# REPO_NAME=$(gh repo view --json name -q '.name')
# gh pr comment "$PR_NUMBER" --body "@claude /code-review:code-review $REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER"
