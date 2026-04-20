#!/bin/bash
# Find bugbot activity on a PR — inline comments, top-level PR comments, and reviews.
# Used by the /bugbot-loop skill (mind-vault) as well as human inspection.
#
# Output contract:
#   - Prints a single `BUGBOT_CLEAN_SIGNAL=<id> COMMIT=<sha> AT=<iso-timestamp>` line
#     on its own when bugbot's most recent review on the PR is a "found no new issues"
#     clean-signal. The loop's Phase 4 decision tree greps for this line.
#   - Prints formatted inline findings (existing behaviour, unchanged).
#   - Prints any top-level PR comments from bugbot (umbrella summaries, retrigger
#     acknowledgements, etc.) so the loop can detect truly-new activity by id.
#   - Never early-exits before all three endpoints have been polled — a clean-signal
#     review and fresh inline findings can coexist for the same commit if bugbot was
#     re-triggered after a prior clean.
#
# Usage: ./tools/find_bugbot_comments.sh [PR_NUMBER]
#        ./tools/find_bugbot_comments.sh   # Uses current branch's PR

set -e

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Resolve PR number from arg or current branch
if [ -z "$1" ]; then
    BRANCH=$(git branch --show-current)
    if [ -z "$BRANCH" ]; then
        echo "❌ Could not determine current branch"
        exit 1
    fi

    PR_NUMBER=$(gh pr list --head "$BRANCH" --json number -q '.[0].number' 2>/dev/null)

    if [ -z "$PR_NUMBER" ]; then
        echo "❌ No PR found for branch: $BRANCH"
        echo "   Create a PR first or specify PR number: $0 <PR_NUMBER>"
        exit 1
    fi

    echo "🔍 Found PR #$PR_NUMBER for branch: $BRANCH"
else
    PR_NUMBER="$1"
fi

# Repo identifier
REPO_OWNER=$(gh repo view --json owner -q '.owner.login')
REPO_NAME=$(gh repo view --json name -q '.name')

if [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ]; then
    echo "❌ Could not determine repository owner/name"
    exit 1
fi

echo "📋 Fetching bugbot activity for PR #$PR_NUMBER..."
echo ""

# Fetch all three endpoints up-front (each defaults to [] on failure so the python
# passes never receive empty stdin). `per_page=100` is GitHub's max-per-page — avoids
# the default-30 cap that would silently drop the most recent review / comment on a
# long-iteration PR and defeat the exact clean-signal fast-path this helper exists
# to serve. Single-page only (no --paginate) — bugbot review history is bounded.
INLINE_COMMENTS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER/comments?per_page=100" 2>/dev/null || echo "[]")
ISSUE_COMMENTS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/issues/$PR_NUMBER/comments?per_page=100" 2>/dev/null || echo "[]")
REVIEWS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER/reviews?per_page=100" 2>/dev/null || echo "[]")

# ------------------------------------------------------------------------------
# Pass 1 — Reviews: clean-signal detection (and any review-level bugbot summary)
# ------------------------------------------------------------------------------
CLEAN_SIGNAL_LINE=$(echo "$REVIEWS" | python3 -c "
import json, sys
try:
    reviews = json.load(sys.stdin)
except Exception:
    sys.exit(0)
bugbot = [r for r in reviews if (r.get('user') or {}).get('login') == 'cursor[bot]']
# Newest first
bugbot.sort(key=lambda r: r.get('submitted_at') or '', reverse=True)
# Find the most recent review matching the clean-signal marker.
# Bugbot's clean review body contains 'found no new issues' (sometimes wrapped
# in the <!-- BUGBOT_REVIEW --> HTML-comment marker).
for r in bugbot:
    body = r.get('body') or ''
    if 'found no new issues' in body:
        rid = r.get('id')
        commit = r.get('commit_id') or ''
        at = r.get('submitted_at') or ''
        print(f'BUGBOT_CLEAN_SIGNAL={rid} COMMIT={commit} AT={at}')
        break
" 2>/dev/null || true)

if [ -n "$CLEAN_SIGNAL_LINE" ]; then
    # Machine-readable marker for /bugbot-loop Phase 4: MUST be plain text, no ANSI
    # escapes. Phase 4 greps `^BUGBOT_CLEAN_SIGNAL=` and parses `COMMIT=<sha>` for
    # the fast-path hand-back. Wrapping this in color codes prefixes the line with
    # `\033[0;32m`, breaks the anchor, and suffixes `AT=<ts>` with `\033[0m` — the
    # exact failure mode this script exists to prevent.
    echo "$CLEAN_SIGNAL_LINE"
    echo -e "${GREEN}✅ Bugbot reviewed the PR head and found no new issues.${NC}"
    echo ""
fi

# Any other bugbot reviews with substantive bodies (umbrella summaries, partial clean,
# older clean signals for prior SHAs). Surface them so the loop can see non-clean
# review history — useful when bugbot is iterating across pushes.
OTHER_REVIEWS=$(echo "$REVIEWS" | python3 -c "
import json, sys
try:
    reviews = json.load(sys.stdin)
except Exception:
    sys.exit(0)
bugbot = [r for r in reviews if (r.get('user') or {}).get('login') == 'cursor[bot]']
bugbot.sort(key=lambda r: r.get('submitted_at') or '', reverse=True)
shown = 0
for r in bugbot:
    body = (r.get('body') or '').strip()
    if not body or 'found no new issues' in body:
        # Skip empties and the clean-signal review already surfaced above.
        continue
    rid = r.get('id')
    commit = (r.get('commit_id') or '')[:8]
    at = r.get('submitted_at') or ''
    # First line of body as a summary
    summary = body.splitlines()[0][:200] if body else ''
    print(f'  review {rid} commit={commit} at={at}')
    print(f'    summary: {summary}')
    shown += 1
    if shown >= 5:
        # Cap the history we surface to the loop
        break
" 2>/dev/null || true)

if [ -n "$OTHER_REVIEWS" ]; then
    echo -e "${BLUE}🗂  Recent bugbot reviews (non-clean / prior SHAs):${NC}"
    echo "$OTHER_REVIEWS"
    echo ""
fi

# ------------------------------------------------------------------------------
# Pass 2 — Inline review comments (findings on specific code lines)
# ------------------------------------------------------------------------------
BUGBOT_INLINE=$(echo "$INLINE_COMMENTS" | python3 -c "
import json, sys
try:
    comments = json.load(sys.stdin)
except Exception:
    sys.exit(0)
bugbot = [c for c in comments if (c.get('user') or {}).get('login') == 'cursor[bot]']
if bugbot:
    print(json.dumps(bugbot))
" 2>/dev/null || true)

if [ -n "$BUGBOT_INLINE" ]; then
    INLINE_COUNT=$(echo "$BUGBOT_INLINE" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
    echo -e "${RED}🐛 Found $INLINE_COUNT bugbot inline finding(s):${NC}"
    echo ""

    echo "$BUGBOT_INLINE" | python3 -c "
import json
import sys
import re

comments = json.load(sys.stdin)

# Sort by severity (High > Medium > Low) then by file path
def get_severity(body):
    if '**High Severity**' in body or '❌' in body:
        return 0
    elif '**Medium Severity**' in body or '⚠️' in body:
        return 1
    elif '**Low Severity**' in body:
        return 2
    else:
        return 3

comments.sort(key=lambda c: (get_severity(c.get('body', '')), c.get('path', ''), c.get('line') or 0))

for i, comment in enumerate(comments, 1):
    path = comment.get('path', 'unknown')
    line = comment.get('line', '?')
    body = comment.get('body', '')
    url = comment.get('html_url', '')
    cid = comment.get('id', '')

    # Extract severity
    severity = 'Info'
    severity_color = ''
    if '**High Severity**' in body or '❌' in body:
        severity = 'HIGH'
        severity_color = '\033[0;31m'  # Red
    elif '**Medium Severity**' in body or '⚠️' in body:
        severity = 'MEDIUM'
        severity_color = '\033[1;33m'  # Yellow
    elif '**Low Severity**' in body:
        severity = 'LOW'
        severity_color = '\033[0;32m'  # Green

    # Extract title (first line after ###)
    title_match = re.search(r'### (.+?)\n', body)
    title = title_match.group(1) if title_match else 'Bugbot Comment'

    # Extract description (between <!-- DESCRIPTION START --> and <!-- DESCRIPTION END -->)
    desc_match = re.search(r'<!-- DESCRIPTION START -->\n(.*?)\n<!-- DESCRIPTION END -->', body, re.DOTALL)
    description = desc_match.group(1).strip() if desc_match else ''

    # Extract locations
    locations_match = re.search(r'<!-- LOCATIONS START\n(.*?)\nLOCATIONS END -->', body, re.DOTALL)
    locations = locations_match.group(1).strip() if locations_match else ''

    separator = '━' * 80
    print(f'{severity_color}{separator}\033[0m')
    print(f'{severity_color}[{i}/{len(comments)}] Severity: {severity} (comment id {cid})\033[0m')
    print(f'\033[0;34m**File:**\033[0m {path}:{line}')
    print(f'\033[0;34m**Title:**\033[0m {title}')

    if description:
        print(f'\033[0;34m**Description:**\033[0m')
        print(f'{description}')
        print('')

    if locations:
        print(f'\033[0;34m**Locations:**\033[0m')
        for loc in locations.split('\n'):
            if loc.strip():
                print(f'  - {loc.strip()}')
        print('')

    print(f'\033[0;34m**Link:**\033[0m {url}')
    print('')
"
fi

# ------------------------------------------------------------------------------
# Pass 3 — Top-level PR comments (retriggers, umbrella summaries, legacy format)
# ------------------------------------------------------------------------------
BUGBOT_ISSUE=$(echo "$ISSUE_COMMENTS" | python3 -c "
import json, sys
try:
    comments = json.load(sys.stdin)
except Exception:
    sys.exit(0)
bugbot = [c for c in comments if (c.get('user') or {}).get('login') == 'cursor[bot]']
if bugbot:
    print(json.dumps(bugbot))
" 2>/dev/null || true)

if [ -n "$BUGBOT_ISSUE" ]; then
    ISSUE_COUNT=$(echo "$BUGBOT_ISSUE" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
    echo -e "${BLUE}💬 Bugbot top-level PR comments ($ISSUE_COUNT):${NC}"
    echo ""
    echo "$BUGBOT_ISSUE" | python3 -c "
import json, sys
comments = json.load(sys.stdin)
comments.sort(key=lambda c: c.get('created_at') or '', reverse=True)
for c in comments[:5]:  # Cap at 5 most recent
    cid = c.get('id', '')
    at = c.get('created_at') or ''
    body = (c.get('body') or '').strip()
    first = body.splitlines()[0][:200] if body else ''
    print(f'  comment {cid} at {at}')
    print(f'    {first}')
    print('')
"
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
if [ -z "$CLEAN_SIGNAL_LINE" ] && [ -z "$BUGBOT_INLINE" ] && [ -z "$BUGBOT_ISSUE" ] && [ -z "$OTHER_REVIEWS" ]; then
    echo "⏳ No bugbot activity yet for PR #$PR_NUMBER."
    echo "   Trigger a review with: ./tools/bugbot_retrigger.sh $PR_NUMBER"
    exit 0
fi

echo ""
echo "💡 PR: https://github.com/$REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER"
