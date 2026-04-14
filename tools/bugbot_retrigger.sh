#!/bin/bash
# Post "bugbot run" on a PR to re-trigger Cursor Bugbot review.
# Usage: ./tools/bugbot_retrigger.sh [PR_NUMBER]
#        ./tools/bugbot_retrigger.sh  # Uses current branch's PR
#
# The body is hard-coded to "bugbot run" so Claude Code can pre-approve
# this script in ~/.claude/settings.json without risk of arbitrary
# comment injection. Any other PR comment should go through `gh pr comment`
# directly (which prompts for approval).

set -e

if [ -z "$1" ]; then
    BRANCH=$(git branch --show-current)
    if [ -z "$BRANCH" ]; then
        echo "❌ Could not determine current branch" >&2
        exit 1
    fi
    PR_NUMBER=$(gh pr list --head "$BRANCH" --json number -q '.[0].number' 2>/dev/null)
    if [ -z "$PR_NUMBER" ]; then
        echo "❌ No PR found for branch: $BRANCH" >&2
        exit 1
    fi
else
    PR_NUMBER="$1"
fi

echo "🔁 Re-triggering bugbot on PR #$PR_NUMBER..."
gh pr comment "$PR_NUMBER" -b "bugbot run"
