#!/bin/bash
# Find bugbot comments on a PR
# Usage: ./tools/find_bugbot_comments.sh [PR_NUMBER]
#        ./tools/find_bugbot_comments.sh  # Uses current branch's PR

set -e

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get PR number
if [ -z "$1" ]; then
    # Get PR from current branch
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

# Get repository owner and name
REPO_OWNER=$(gh repo view --json owner -q '.owner.login')
REPO_NAME=$(gh repo view --json name -q '.name')

if [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ]; then
    echo "❌ Could not determine repository owner/name"
    exit 1
fi

echo "📋 Fetching bugbot comments for PR #$PR_NUMBER..."
echo ""

# Check for clean-signal PR review ("no new issues"). Bugbot posts this as a
# PR review (state=COMMENTED) rather than an issue comment, with a BUGBOT_REVIEW
# marker in the body. We surface the latest one so the /bugbot-loop can fast-path
# to hand-back instead of burning 20 idle polls.
CLEAN_SIGNAL=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER/reviews?per_page=100" 2>/dev/null | python3 -c "
import json, sys
try:
    # per_page=100 (the GitHub API max) avoids any --paginate / --slurp
    # ambiguity across gh CLI versions. A PR with >100 bugbot reviews is
    # already a sign to bail out, not to read further pages.
    reviews = json.load(sys.stdin)
    if not isinstance(reviews, list):
        # gh api can return an error object (e.g. {'message': 'Not Found'}) as
        # a dict — iterating that yields string keys and breaks .get() below.
        sys.exit(0)
    clean = [r for r in reviews
             if r.get('user', {}).get('login') == 'cursor[bot]'
             and '<!-- BUGBOT_REVIEW -->' in (r.get('body') or '')
             and 'found no new issues' in (r.get('body') or '')]
    if clean:
        latest = max(clean, key=lambda r: r.get('submitted_at', ''))
        print(f\"{latest.get('id', '')}|{latest.get('submitted_at', '')}|{latest.get('commit_id', '')}|{latest.get('html_url', '')}\")
except Exception:
    sys.exit(0)
" 2>/dev/null || true)

if [ -n "$CLEAN_SIGNAL" ]; then
    IFS='|' read -r CS_ID CS_TIME CS_SHA CS_URL <<< "$CLEAN_SIGNAL"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ CLEAN SIGNAL: Bugbot reviewed and found no new issues${NC}"
    echo -e "${BLUE}   Review id:${NC}  $CS_ID"
    echo -e "${BLUE}   Submitted:${NC}  $CS_TIME"
    echo -e "${BLUE}   Commit:${NC}     $CS_SHA"
    echo -e "${BLUE}   Link:${NC}       $CS_URL"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    # Machine-readable marker for the /bugbot-loop skill to grep:
    echo "BUGBOT_CLEAN_SIGNAL=$CS_ID COMMIT=$CS_SHA AT=$CS_TIME"
    echo ""
fi

# Fetch PR review comments (inline findings) using GitHub API
COMMENTS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER/comments" 2>/dev/null)

if [ -z "$COMMENTS" ] || [ "$COMMENTS" = "[]" ]; then
    echo "✅ No inline code review comments found on PR #$PR_NUMBER"
    exit 0
fi

# Filter for bugbot comments (cursor[bot])
BUGBOT_COMMENTS=$(echo "$COMMENTS" | python3 -c "
import json
import sys

comments = json.load(sys.stdin)
bugbot_comments = [c for c in comments if c.get('user', {}).get('login') == 'cursor[bot]']

if not bugbot_comments:
    sys.exit(1)

print(json.dumps(bugbot_comments))
" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$BUGBOT_COMMENTS" ]; then
    echo "✅ No bugbot comments found on PR #$PR_NUMBER"
    exit 0
fi

# Count comments
COMMENT_COUNT=$(echo "$BUGBOT_COMMENTS" | python3 -c "
import json
import sys
comments = json.load(sys.stdin)
print(len(comments))
")

echo "🐛 Found $COMMENT_COUNT bugbot comment(s):"
echo ""

# Display comments
echo "$BUGBOT_COMMENTS" | python3 -c "
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
    print(f'{severity_color}[{i}/{len(comments)}] Severity: {severity}\033[0m')
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

echo ""
echo "💡 Tip: Use 'gh pr view $PR_NUMBER' to see the PR, or visit:"
echo "   https://github.com/$REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER"
