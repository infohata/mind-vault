#!/bin/bash
# Bootstrap / re-trigger a Grok Code Review on a PR by posting "grok review".
# Usage: ./tools/grok_retrigger.sh [PR_NUMBER]
#        ./tools/grok_retrigger.sh  # Uses current branch's PR
#
# The push auto-run (`.github/workflows/grok-code-review.yml` on `synchronize`)
# re-runs on every non-draft same-repo push. This explicit comment is still
# required for:
#   1. Zero-activity bootstrap (workflow not yet settled / just installed).
#   2. Retrigger without Actions:write on a PAT — `issue_comment` with the
#      literal body `grok review` (author_association OWNER/MEMBER/COLLABORATOR).
#
# The body is hard-coded so agent hosts can pre-approve this script without
# risk of arbitrary comment injection. Idempotent: posting twice queues another
# review; concurrency cancel-in-progress collapses overlapping runs.

set -eo pipefail

if [ -z "$1" ]; then
    BRANCH=$(git branch --show-current)
    if [ -z "$BRANCH" ]; then
        echo "❌ Could not determine current branch" >&2
        exit 1
    fi
    PR_NUMBER=$(gh pr list --head "$BRANCH" --json number -q '.[0].number' 2>/dev/null)
    if [ -z "$PR_NUMBER" ] || [ "$PR_NUMBER" = "null" ] || ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
        echo "❌ No PR found for branch: $BRANCH" >&2
        exit 1
    fi
else
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

echo "🔁 Bootstrapping a Grok review on PR #$PR_NUMBER..."
gh pr comment "$PR_NUMBER" --body "grok review"
