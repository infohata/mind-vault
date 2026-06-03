#!/bin/bash
# Bootstrap a Claude Code Review on a PR by posting "@claude review once".
# Usage: ./tools/claude_retrigger.sh [PR_NUMBER]
#        ./tools/claude_retrigger.sh  # Uses current branch's PR
#
# The push auto-run (`claude-code-review.yml` on `synchronize`) only produces a
# review the FIRST time — the `code-review` plugin SKIPS the auto-run once claude
# has already posted a review on the PR ("Skipping review — already posted …").
# So this explicit `@claude review` is REQUIRED, not fallback-only, in two cases
# (corrected PR #169 self-dogfood — see engine-claude.md § Push-triggered model):
#   1. Phase-3 retrigger after a fix push, ONCE claude has already reviewed — the
#      push will skip-no-op, so the explicit request is the only way to a fresh
#      verdict on the fix. (No double-run race: the auto-run skips.)
#   2. The zero-activity bootstrap — no Actions run at all for the head SHA (fresh
#      PR before the action settled, or a just-installed workflow).
# Before claude's first comment, the push/un-draft auto-run suffices — no need to
# call this for the very first review.
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
