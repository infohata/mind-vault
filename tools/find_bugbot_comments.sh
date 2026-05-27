#!/bin/bash
# Find bugbot activity on a PR — inline comments, top-level PR comments, and reviews.
# Used by the /review-loop skill (mind-vault) as well as human inspection.
#
# Output contract:
#   - Prints a single `BUGBOT_CLEAN_SIGNAL=<id> COMMIT=<sha> AT=<iso-timestamp>` line
#     on its own when bugbot's most recent review on the PR is a "found no new issues"
#     clean-signal. The loop's Phase 4 decision tree greps for this line.
#     The signal source is /pulls/<N>/reviews PRIMARILY, with a /commits/<sha>/check-runs
#     fallback (added 2026-05-06): bugbot can post the clean signal as a GitHub Check
#     instead of a review-body — the script synthesizes BUGBOT_CLEAN_SIGNAL from a
#     successful check-run when /reviews has no clean-signal review for HEAD.
#   - Prints formatted inline findings (existing behaviour, unchanged).
#   - Prints any top-level PR comments from bugbot (umbrella summaries, retrigger
#     acknowledgements, etc.) so the loop can detect truly-new activity by id.
#   - Never early-exits before all four endpoints have been polled — a clean-signal
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

# Fetch all four endpoints up-front (each defaults to [] / empty-shape on failure so
# the python passes never receive empty stdin). `per_page=100` is GitHub's max-per-page
# — avoids the default-30 cap that would silently drop the most recent review / comment
# on a long-iteration PR and defeat the exact clean-signal fast-path this helper exists
# to serve. Single-page only (no --paginate) — bugbot review history is bounded.
INLINE_COMMENTS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER/comments?per_page=100" 2>/dev/null || echo "[]")
ISSUE_COMMENTS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/issues/$PR_NUMBER/comments?per_page=100" 2>/dev/null || echo "[]")
REVIEWS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER/reviews?per_page=100" 2>/dev/null || echo "[]")

# /check-runs API — added 2026-05-06 after PR #429 spent ~35 min polling /reviews
# for a clean signal that bugbot had posted as a successful GitHub Check.
# Bugbot's clean signal can land in EITHER:
#   - /pulls/<N>/reviews with body "found no new issues" (the original signal source)
#   - /commits/<sha>/check-runs with conclusion=success on the cursor app's check-run
# This script accepts either as clean. The /check-runs path requires the PR HEAD SHA;
# we fetch it via /pulls/<N> and gracefully degrade to empty state if that fetch fails.
PR_HEAD_SHA=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER" -q '.head.sha' 2>/dev/null || echo "")
if [ -n "$PR_HEAD_SHA" ]; then
    CHECK_RUNS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/commits/$PR_HEAD_SHA/check-runs?per_page=100" 2>/dev/null || echo '{"check_runs":[]}')
else
    CHECK_RUNS='{"check_runs":[]}'
fi

# ------------------------------------------------------------------------------
# Pass 1 — Reviews: three Python sub-passes against $REVIEWS
# ------------------------------------------------------------------------------
# Three near-identical python3 blocks below all parse $REVIEWS, filter for
# cursor[bot], and sort by submitted_at — but each answers a different question
# and emits a different marker:
#
#   1. CLEAN_SIGNAL_LINE   — "is bugbot saying HEAD is clean right now?"
#                            Emits BUGBOT_CLEAN_SIGNAL only on positive match.
#                            Empty otherwise. Drives /review-loop's Phase 4
#                            fast-path hand-back.
#
#   2. LATEST_REVIEW_LINE  — "what is the most recent bugbot review, regardless
#                            of clean state?" Emits BUGBOT_LATEST_REVIEW
#                            unconditionally with a CLEAN=true|false flag.
#                            Drives the active/stale finding filter from PR #81.
#
#   3. OTHER_REVIEWS       — "what non-clean reviews against earlier SHAs are
#                            still in history?" Emits a small human-readable
#                            list (capped at 5).
#
# Bugbot PR #81 review (3156265252, LOW) flagged the duplication as a
# maintenance smell — same filter + sort + field-extract in three places.
# Kept three blocks intentionally:
#
#   - Each block answers ONE question and is independently readable (~15 lines
#     vs ~40 for a consolidated emit-three-markers block).
#   - The line-by-line stdout shape (independently empty-able markers in their
#     existing order) IS a contract — `/review-loop` Phase 4 greps the
#     `^BUGBOT_CLEAN_SIGNAL=` anchor; consolidating risks reordering or
#     emitting empty placeholders that subtly change consumer behaviour.
#   - Three python3 spawns is ~150ms total — invisible at the loop's 270s
#     polling cadence. Performance is not the load-bearing argument here.
#
# Drift risk: if cursor[bot] becomes a different bot login or the API field
# names change, all THREE blocks need updating. Worth consolidating IF a fourth
# marker is added or the maintenance pain actually shows up.
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
# The output contract (file header, lines 5-8) says the marker fires iff bugbot's
# MOST RECENT review is the 'found no new issues' clean-signal. Check the newest
# review only — never skip past a newer non-clean review to find an older clean
# one. The 'Recent reviews' pass below separately surfaces non-clean history.
if bugbot:
    r = bugbot[0]
    body = r.get('body') or ''
    if 'found no new issues' in body:
        rid = r.get('id')
        commit = r.get('commit_id') or ''
        at = r.get('submitted_at') or ''
        print(f'BUGBOT_CLEAN_SIGNAL={rid} COMMIT={commit} AT={at}')
" 2>/dev/null || true)

if [ -n "$CLEAN_SIGNAL_LINE" ]; then
    # Machine-readable marker for /review-loop Phase 4: MUST be plain text, no ANSI
    # escapes. Phase 4 greps `^BUGBOT_CLEAN_SIGNAL=` and parses `COMMIT=<sha>` for
    # the fast-path hand-back. Wrapping this in color codes prefixes the line with
    # `\033[0;32m`, breaks the anchor, and suffixes `AT=<ts>` with `\033[0m` — the
    # exact failure mode this script exists to prevent.
    echo "$CLEAN_SIGNAL_LINE"
    echo -e "${GREEN}✅ Bugbot reviewed the PR head and found no new issues.${NC}"
    echo ""
fi

# ------------------------------------------------------------------------------
# Pass 1.5 — Check Runs API: bugbot's clean signal can also land here
# ------------------------------------------------------------------------------
# Surfaced 2026-05-06: bugbot posted a successful check-run
# for the PR head while /reviews stayed empty for that commit. The loop wasted
# ~35 min polling /reviews + /comments for a clean signal that lived on
# /commits/<sha>/check-runs. Make the script tolerant: emit BUGBOT_CHECKRUN
# unconditionally (informational), and SYNTHESIZE BUGBOT_CLEAN_SIGNAL when the
# check-run reports success and /reviews didn't already produce a clean signal
# for HEAD. Downstream consumers (/review-loop Phase 4) only need to grep
# BUGBOT_CLEAN_SIGNAL — the synthesis preserves the existing contract.
#
# App identification — match by app.slug for cursor's bot. Tolerant filter so
# minor app-name changes don't break the script: matches if app.slug contains
# 'cursor' OR app.owner.login contains 'cursor' OR name contains 'bugbot'.
BUGBOT_CHECKRUN_LINE=$(echo "$CHECK_RUNS" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
runs = data.get('check_runs', []) if isinstance(data, dict) else []

def is_bugbot(run):
    app = run.get('app') or {}
    slug = (app.get('slug') or '').lower()
    owner_login = ((app.get('owner') or {}).get('login') or '').lower()
    name = (run.get('name') or '').lower()
    return ('cursor' in slug
            or 'cursor' in owner_login
            or 'bugbot' in name
            or 'bugbot' in slug)

bugbot = [r for r in runs if is_bugbot(r)]
if not bugbot:
    sys.exit(0)
# Newest first by completed_at, fall back to started_at.
bugbot.sort(key=lambda r: (r.get('completed_at') or r.get('started_at') or ''), reverse=True)
latest = bugbot[0]
status = latest.get('status', '')
conclusion = latest.get('conclusion', '')
rid = latest.get('id') or ''
sha = latest.get('head_sha') or ''
at = latest.get('completed_at') or latest.get('started_at') or ''
print(f'BUGBOT_CHECKRUN={rid} COMMIT={sha} STATUS={status} CONCLUSION={conclusion} AT={at}')
" 2>/dev/null || true)

# Did bugbot post a REVIEW (not merely a check-run) for the current head SHA, and are
# there any cursor[bot] inline findings already? Both feed the review-pending race guard.
HEAD_REVIEW_POSTED=$(echo "$REVIEWS" | PR_HEAD_SHA="$PR_HEAD_SHA" python3 -c "
import json, os, sys
try:
    reviews = json.load(sys.stdin)
except Exception:
    print('false'); sys.exit(0)
head = os.environ.get('PR_HEAD_SHA','')
bb = [r for r in reviews if (r.get('user') or {}).get('login') == 'cursor[bot]']
print('true' if any((r.get('commit_id') or '') == head for r in bb) else 'false')
" 2>/dev/null || echo "false")

BUGBOT_INLINE_PRECHECK=$(echo "$INLINE_COMMENTS" | python3 -c "
import json, sys
try:
    comments = json.load(sys.stdin)
except Exception:
    sys.exit(0)
bb = [c for c in comments if (c.get('user') or {}).get('login') == 'cursor[bot]']
if bb:
    print('yes')
" 2>/dev/null || true)

if [ -n "$BUGBOT_CHECKRUN_LINE" ]; then
    # `|| true` on each pipeline: an in_progress check-run emits empty CONCLUSION=, so
    # `grep -oE 'FIELD=[^ ]+'` exits 1 and would abort under `set -eo pipefail`.
    cr_status=$(echo "$BUGBOT_CHECKRUN_LINE" | grep -oE 'STATUS=[^ ]+' | cut -d= -f2 || true)
    cr_conclusion=$(echo "$BUGBOT_CHECKRUN_LINE" | grep -oE 'CONCLUSION=[^ ]+' | cut -d= -f2 || true)
    cr_id=$(echo "$BUGBOT_CHECKRUN_LINE" | grep -oE 'BUGBOT_CHECKRUN=[^ ]+' | cut -d= -f2 || true)
    cr_sha=$(echo "$BUGBOT_CHECKRUN_LINE" | grep -oE 'COMMIT=[^ ]+' | cut -d= -f2 || true)
    cr_at=$(echo "$BUGBOT_CHECKRUN_LINE" | grep -oE 'AT=[^ ]+' | cut -d= -f2 || true)

    # ── Review-pending race guard (engine-general; see engine-adapter-contract.md
    # § Review-state gate). A check-run can flip to completed BEFORE the engine's review /
    # inline comments post; a poll in that gap sees DONE + zero findings and the loop
    # declares a false CLEAN (observed on copilot, PR #148 — 3m42s lag). Cursor's
    # check-suite turns non-success on findings so bugbot's window is narrower, but the
    # orchestrator's structural clean ignores CONCLUSION, so the gap is still exploitable.
    # Trust a completed+success check-run as DONE only once bugbot has posted a review for
    # the head SHA; until then downgrade STATUS to in_progress (loop keeps waiting) + emit
    # BUGBOT_REVIEW_PENDING. Settle valve (BUGBOT_REVIEW_SETTLE_SECONDS, default 600)
    # covers the rare check-run-only-no-review case. Settle math in Python — `datetime`
    # is cross-platform, unlike `date -d` (GNU-only; would fail on BSD/macOS).
    SETTLE=${BUGBOT_REVIEW_SETTLE_SECONDS:-600}
    if [ "$cr_status" = "completed" ] && [ "$cr_conclusion" = "success" ] && [ "$HEAD_REVIEW_POSTED" != "true" ]; then
        settle_state=$(SETTLE="$SETTLE" CR_AT="$cr_at" python3 -c "
import os
from datetime import datetime, timezone
try:
    settle = int(os.environ.get('SETTLE', '600'))
    dt = datetime.fromisoformat(os.environ.get('CR_AT', '').replace('Z', '+00:00'))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    age = (datetime.now(timezone.utc) - dt).total_seconds()
    print('elapsed' if age >= settle else 'pending')
except Exception:
    print('pending')
" 2>/dev/null || echo "pending")
        if [ "$settle_state" != "elapsed" ]; then
            cr_status="in_progress"
            BUGBOT_CHECKRUN_LINE=$(echo "$BUGBOT_CHECKRUN_LINE" | sed 's/STATUS=completed/STATUS=in_progress/')
        fi
    fi

    echo "$BUGBOT_CHECKRUN_LINE"

    if [ "$cr_status" = "completed" ] && [ "$cr_conclusion" = "success" ]; then
        # Reached only when the review content has landed (HEAD_REVIEW_POSTED=true) or the
        # settle valve fired. Synthesize BUGBOT_CLEAN_SIGNAL only if /reviews didn't emit
        # one AND there are zero cursor[bot] inline findings — never paper over findings.
        echo -e "${GREEN}✅ Bugbot check-run reports success for PR head.${NC}"
        if [ -z "$CLEAN_SIGNAL_LINE" ] && [ -z "$BUGBOT_INLINE_PRECHECK" ]; then
            echo "BUGBOT_CLEAN_SIGNAL=checkrun-${cr_id} COMMIT=${cr_sha} AT=${cr_at}"
            CLEAN_SIGNAL_LINE="checkrun-${cr_id}"  # mark non-empty for the summary check below
        fi
    elif [ "$cr_status" = "in_progress" ] && [ "$cr_conclusion" = "success" ]; then
        echo "BUGBOT_REVIEW_PENDING=checkrun-${cr_id} COMMIT=${cr_sha} SETTLE=${SETTLE}s"
        echo -e "${YELLOW}⏳ Bugbot check-run completed but no review posted for HEAD yet — treating as RUNNING (review-pending race guard) to avoid a false CLEAN.${NC}"
    fi
    echo ""
fi

# ------------------------------------------------------------------------------
# Latest-review marker — used by the loop's Phase 1 to filter stale-vs-HEAD findings
# ------------------------------------------------------------------------------
# Inline review comments persist visually across pushes until "Resolve conversation"
# is clicked on the GitHub UI, so /comments will surface findings from EVERY prior
# review, not just the latest one. Without a way to tell which review a finding
# belongs to, the loop processes already-fixed findings as if they were active and
# burns cycles. Surface the latest bugbot review id (whether clean or not) so the
# loop can compare each comment's `pull_request_review_id` field against it and
# treat anything-but-the-latest as stale persistent threads, not active findings.
LATEST_REVIEW_LINE=$(echo "$REVIEWS" | python3 -c "
import json, sys
try:
    reviews = json.load(sys.stdin)
except Exception:
    sys.exit(0)
bugbot = [r for r in reviews if (r.get('user') or {}).get('login') == 'cursor[bot]']
if not bugbot:
    sys.exit(0)
bugbot.sort(key=lambda r: r.get('submitted_at') or '', reverse=True)
latest = bugbot[0]
rid = latest.get('id')
commit = latest.get('commit_id') or ''
at = latest.get('submitted_at') or ''
body = (latest.get('body') or '').strip()
clean = 'true' if 'found no new issues' in body else 'false'
print(f'BUGBOT_LATEST_REVIEW={rid} COMMIT={commit} AT={at} CLEAN={clean}')
" 2>/dev/null || true)

if [ -n "$LATEST_REVIEW_LINE" ]; then
    # Same plain-text contract as BUGBOT_CLEAN_SIGNAL — no ANSI codes.
    echo "$LATEST_REVIEW_LINE"
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
    # The pull_request_review_id field ties a comment to a specific bugbot review.
    # /review-loop Phase 1 compares this against the BUGBOT_LATEST_REVIEW marker
    # to distinguish active findings (latest-review) from stale persistent threads
    # (older reviews kept by GitHub UI until manually Resolve-conversation-clicked).
    # GitHub documents the field as integer-or-null. .get(key, default) returns the
    # null/None value when the key EXISTS, not the default — so use Python's "or"
    # operator to coalesce both absent-key and null-value cases (matches the pattern
    # used elsewhere in this script, e.g. latest.get on commit_id immediately above).
    rev_id = comment.get('pull_request_review_id') or ''

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
    print(f'{severity_color}[{i}/{len(comments)}] Severity: {severity} (comment id {cid}, review {rev_id})\033[0m')
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
if [ -z "$CLEAN_SIGNAL_LINE" ] && [ -z "$LATEST_REVIEW_LINE" ] && [ -z "$BUGBOT_INLINE" ] && [ -z "$BUGBOT_ISSUE" ] && [ -z "$OTHER_REVIEWS" ] && [ -z "$BUGBOT_CHECKRUN_LINE" ]; then
    echo "⏳ No bugbot activity yet for PR #$PR_NUMBER."
    echo "   Trigger a review with: ./tools/bugbot_retrigger.sh $PR_NUMBER"
    exit 0
fi

echo ""
echo "💡 PR: https://github.com/$REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER"
