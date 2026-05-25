#!/bin/bash
# Find GitHub Copilot review activity on a PR — inline comments, top-level PR
# comments, and reviews.
# Used by the /review-loop skill (mind-vault) as well as human inspection.
#
# Bot user.login dual identity — confirmed empirically on mind-vault PR
# #118 (2026-05-17 cycle 2): GitHub Copilot's PR-review bot exposes
# DIFFERENT user.login values across endpoints:
#   - /pulls/<N>/reviews          → 'copilot-pull-request-reviewer[bot]'
#   - /pulls/<N>/comments         → 'Copilot'
#   - /pulls/<N>/requested_reviewers → 'Copilot'
# This is GitHub-side, not a script bug — the bracket-bot form on /reviews
# and the bare 'Copilot' on /comments are the actual API responses. The
# filter below matches both spellings to catch every endpoint's authored
# entries. The check-run app-slug filter ('copilot' substring match) is
# still best-guess — calibrate when the first check-run-bearing PR runs
# through. If a future Copilot product change adds a third spelling,
# extend the tuple below + skills/review-loop/references/engine-copilot.md.
#
# Output contract:
#   - Prints a single `COPILOT_CLEAN_SIGNAL=<id> COMMIT=<sha> AT=<iso-timestamp>` line
#     on its own when copilot's most recent review on the PR is a clean-signal
#     ("found no new issues" OR "generated no new comments" — both phrasings observed
#     in the wild as of 2026-05-22). The loop's Phase 4 decision tree greps for
#     this line.
#     The signal source is /pulls/<N>/reviews PRIMARILY, with a /commits/<sha>/check-runs
#     fallback (added 2026-05-06): copilot can post the clean signal as a GitHub Check
#     instead of a review-body — the script synthesizes COPILOT_CLEAN_SIGNAL from a
#     successful check-run when /reviews has no clean-signal review for HEAD.
#   - Prints formatted inline findings (existing behaviour, unchanged).
#   - Prints any top-level PR comments from copilot (umbrella summaries, retrigger
#     acknowledgements, etc.) so the loop can detect truly-new activity by id.
#   - Never early-exits before all four endpoints have been polled — a clean-signal
#     review and fresh inline findings can coexist for the same commit if copilot was
#     re-triggered after a prior clean.
#
# Usage: ./tools/find_copilot_comments.sh [PR_NUMBER]
#        ./tools/find_copilot_comments.sh   # Uses current branch's PR

set -eo pipefail

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

    # `gh pr list -q .[0].number` returns the literal string "null" when no
    # PR exists (not empty), so the bare -z guard misses that case and later
    # `gh api .../pulls/null/...` calls fail mysteriously. Reject both empty
    # and "null" + require a numeric PR id.
    if [ -z "$PR_NUMBER" ] || [ "$PR_NUMBER" = "null" ] || ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
        echo "❌ No PR found for branch: $BRANCH"
        echo "   Create a PR first or specify PR number: $0 <PR_NUMBER>"
        exit 1
    fi

    echo "🔍 Found PR #$PR_NUMBER for branch: $BRANCH"
else
    # Accept either a bare PR number (e.g. "118") or a full PR URL
    # (e.g. "https://github.com/owner/repo/pull/118"). Anything else
    # would silently fail in `gh api .../pulls/$PR_NUMBER/...` calls
    # downstream; validate numeric here.
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

# Repo identifier
REPO_OWNER=$(gh repo view --json owner -q '.owner.login')
REPO_NAME=$(gh repo view --json name -q '.name')

if [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ]; then
    echo "❌ Could not determine repository owner/name"
    exit 1
fi

echo "📋 Fetching copilot activity for PR #$PR_NUMBER..."
echo ""

# Fetch all four endpoints up-front (each defaults to [] / empty-shape on failure so
# the python passes never receive empty stdin). `per_page=100` is GitHub's max-per-page
# — avoids the default-30 cap that would silently drop the most recent review / comment
# on a long-iteration PR and defeat the exact clean-signal fast-path this helper exists
# to serve. Single-page only (no --paginate) — copilot review history is bounded.
INLINE_COMMENTS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER/comments?per_page=100" 2>/dev/null || echo "[]")
ISSUE_COMMENTS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/issues/$PR_NUMBER/comments?per_page=100" 2>/dev/null || echo "[]")
REVIEWS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER/reviews?per_page=100" 2>/dev/null || echo "[]")

# /check-runs API — added 2026-05-06 after PR #429 spent ~35 min polling /reviews
# for a clean signal that copilot had posted as a successful GitHub Check.
# Copilot's clean signal can land in EITHER:
#   - /pulls/<N>/reviews with a clean-body matching one of CLEAN_PHRASES
#     ("found no new issues" / "generated no new comments") — original signal source
#   - /commits/<sha>/check-runs with conclusion=success on the Copilot app's check-run
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
# Copilot, and sort by submitted_at — but each answers a different question
# and emits a different marker:
#
#   1. CLEAN_SIGNAL_LINE   — "is copilot saying HEAD is clean right now?"
#                            Emits COPILOT_CLEAN_SIGNAL only on positive match.
#                            Empty otherwise. Drives /review-loop's Phase 4
#                            fast-path hand-back.
#
#   2. LATEST_REVIEW_LINE  — "what is the most recent copilot review, regardless
#                            of clean state?" Emits COPILOT_LATEST_REVIEW
#                            unconditionally with a CLEAN=true|false flag.
#                            Drives the active/stale finding filter from PR #81.
#
#   3. OTHER_REVIEWS       — "what non-clean reviews against earlier SHAs are
#                            still in history?" Emits a small human-readable
#                            list (capped at 5).
#
# Copilot PR #81 review (3156265252, LOW) flagged the duplication as a
# maintenance smell — same filter + sort + field-extract in three places.
# Kept three blocks intentionally:
#
#   - Each block answers ONE question and is independently readable (~15 lines
#     vs ~40 for a consolidated emit-three-markers block).
#   - The line-by-line stdout shape (independently empty-able markers in their
#     existing order) IS a contract — `/review-loop` Phase 4 greps the
#     `^COPILOT_CLEAN_SIGNAL=` anchor; consolidating risks reordering or
#     emitting empty placeholders that subtly change consumer behaviour.
#   - Three python3 spawns is ~150ms total — invisible at the loop's 270s
#     polling cadence. Performance is not the load-bearing argument here.
#
# Drift risk: if Copilot becomes a different bot login or the API field
# names change, all THREE blocks need updating. Worth consolidating IF a fourth
# marker is added or the maintenance pain actually shows up.
# ------------------------------------------------------------------------------
CLEAN_SIGNAL_LINE=$(echo "$REVIEWS" | python3 -c "
import json, sys
try:
    reviews = json.load(sys.stdin)
except Exception:
    sys.exit(0)
copilot = [r for r in reviews if (r.get('user') or {}).get('login') in ('Copilot', 'copilot-pull-request-reviewer[bot]')]
# Newest first
copilot.sort(key=lambda r: r.get('submitted_at') or '', reverse=True)
# The output contract (file header, lines 5-8) says the marker fires iff copilot's
# MOST RECENT review is a clean-signal. Check the newest review only — never skip
# past a newer non-clean review to find an older clean one. The 'Recent reviews'
# pass below separately surfaces non-clean history.
#
# Two body-text phrasings observed in the wild as of 2026-05-22:
#   * 'found no new issues' — classic Copilot wording.
#   * 'generated no new comments' — newer wording, surfaced on PR #474 (teisutis)
#     when the final review was effectively clean but the body started with
#     '## Pull request overview\n\nCopilot reviewed N out of N changed files
#     in this pull request and generated no new comments.' The legacy matcher
#     missed it; review-loop had to fetch the body manually to confirm CLEAN.
# Match either phrasing. Compare case-insensitively so a future Copilot
# template tweak (e.g. sentence-case 'Generated no new comments') doesn't
# silently break clean detection — CLEAN_PHRASES stays lowercase, body
# is lower-cased at compare time.
CLEAN_PHRASES = ('found no new issues', 'generated no new comments')
def _is_clean_body(body):
    body_l = (body or '').lower()
    return any(p in body_l for p in CLEAN_PHRASES)
if copilot:
    r = copilot[0]
    body = r.get('body') or ''
    if _is_clean_body(body):
        rid = r.get('id')
        commit = r.get('commit_id') or ''
        at = r.get('submitted_at') or ''
        print(f'COPILOT_CLEAN_SIGNAL={rid} COMMIT={commit} AT={at}')
" 2>/dev/null || true)

if [ -n "$CLEAN_SIGNAL_LINE" ]; then
    # Machine-readable marker for /review-loop Phase 4: MUST be plain text, no ANSI
    # escapes. Phase 4 greps `^COPILOT_CLEAN_SIGNAL=` and parses `COMMIT=<sha>` for
    # the fast-path hand-back. Wrapping this in color codes prefixes the line with
    # `\033[0;32m`, breaks the anchor, and suffixes `AT=<ts>` with `\033[0m` — the
    # exact failure mode this script exists to prevent.
    echo "$CLEAN_SIGNAL_LINE"
    echo -e "${GREEN}✅ Copilot's most recent review on the PR head is a clean-signal (no new findings).${NC}"
    echo ""
fi

# ------------------------------------------------------------------------------
# Pass 1.5 — Check Runs API: copilot's clean signal can also land here
# ------------------------------------------------------------------------------
# Surfaced 2026-05-06: copilot posted a successful check-run
# for the PR head while /reviews stayed empty for that commit. The loop wasted
# ~35 min polling /reviews + /comments for a clean signal that lived on
# /commits/<sha>/check-runs. Make the script tolerant: emit COPILOT_CHECKRUN
# unconditionally (informational), and SYNTHESIZE COPILOT_CLEAN_SIGNAL when the
# check-run reports success and /reviews didn't already produce a clean signal
# for HEAD. Downstream consumers (/review-loop Phase 4) only need to grep
# COPILOT_CLEAN_SIGNAL — the synthesis preserves the existing contract.
#
# App identification — match by Copilot-specific markers ONLY. Earlier
# revisions broadened the filter to include `'github' in owner_login`, which
# is far too permissive (GitHub Actions, Dependabot, and other first-party
# bots are all GitHub-owned and would have synthesized a false
# COPILOT_CLEAN_SIGNAL). The filter now requires 'copilot' in slug / owner /
# name, OR an exact match to the canonical `github-copilot` slug.
COPILOT_CHECKRUN_LINE=$(echo "$CHECK_RUNS" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
runs = data.get('check_runs', []) if isinstance(data, dict) else []

def is_copilot(run):
    app = run.get('app') or {}
    slug = (app.get('slug') or '').lower()
    owner_login = ((app.get('owner') or {}).get('login') or '').lower()
    name = (run.get('name') or '').lower()
    # Require a Copilot-specific marker — the generic 'github' owner-login
    # match was too broad (GitHub Actions, Dependabot, etc. are also
    # GitHub-owned and would synthesize a false COPILOT_CLEAN_SIGNAL).
    # The slug and run-name probes carry the actual Copilot identity.
    return ('copilot' in slug
            or 'copilot' in owner_login
            or 'copilot' in name
            or slug == 'github-copilot')

copilot = [r for r in runs if is_copilot(r)]
if not copilot:
    sys.exit(0)
# Newest first by completed_at, fall back to started_at.
copilot.sort(key=lambda r: (r.get('completed_at') or r.get('started_at') or ''), reverse=True)
latest = copilot[0]
status = latest.get('status', '')
conclusion = latest.get('conclusion', '')
rid = latest.get('id') or ''
sha = latest.get('head_sha') or ''
at = latest.get('completed_at') or latest.get('started_at') or ''
print(f'COPILOT_CHECKRUN={rid} COMMIT={sha} STATUS={status} CONCLUSION={conclusion} AT={at}')
" 2>/dev/null || true)

if [ -n "$COPILOT_CHECKRUN_LINE" ]; then
    echo "$COPILOT_CHECKRUN_LINE"
    # Synthesize COPILOT_CLEAN_SIGNAL from a successful check-run when /reviews
    # didn't produce one for HEAD. The downstream /review-loop Phase 4 only
    # greps COPILOT_CLEAN_SIGNAL; this preserves the existing consumer contract.
    # In-progress Copilot check-runs emit `STATUS=` / `CONCLUSION=` with
    # empty values. `grep -oE 'FIELD=[^ ]+'` (requiring ≥1 non-space char
    # after `=`) returns 1 in that case. With `set -eo pipefail` (enabled
    # at top of file) the grep's exit propagates through the pipe and
    # aborts the script. Append `|| true` to each pipeline so empty
    # fields fall through to the `!= success` branch (no synthesis)
    # rather than abort.
    cr_status=$(echo "$COPILOT_CHECKRUN_LINE" | grep -oE 'STATUS=[^ ]+' | cut -d= -f2 || true)
    cr_conclusion=$(echo "$COPILOT_CHECKRUN_LINE" | grep -oE 'CONCLUSION=[^ ]+' | cut -d= -f2 || true)
    if [ "$cr_status" = "completed" ] && [ "$cr_conclusion" = "success" ]; then
        echo -e "${GREEN}✅ Copilot check-run reports success for PR head.${NC}"
        if [ -z "$CLEAN_SIGNAL_LINE" ]; then
            cr_id=$(echo "$COPILOT_CHECKRUN_LINE" | grep -oE 'COPILOT_CHECKRUN=[^ ]+' | cut -d= -f2 || true)
            cr_sha=$(echo "$COPILOT_CHECKRUN_LINE" | grep -oE 'COMMIT=[^ ]+' | cut -d= -f2 || true)
            cr_at=$(echo "$COPILOT_CHECKRUN_LINE" | grep -oE 'AT=[^ ]+' | cut -d= -f2 || true)
            echo "COPILOT_CLEAN_SIGNAL=checkrun-${cr_id} COMMIT=${cr_sha} AT=${cr_at}"
            CLEAN_SIGNAL_LINE="checkrun-${cr_id}"  # mark non-empty for the summary check below
        fi
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
# burns cycles. Surface the latest copilot review id (whether clean or not) so the
# loop can compare each comment's `pull_request_review_id` field against it and
# treat anything-but-the-latest as stale persistent threads, not active findings.
LATEST_REVIEW_LINE=$(echo "$REVIEWS" | python3 -c "
import json, sys
try:
    reviews = json.load(sys.stdin)
except Exception:
    sys.exit(0)
copilot = [r for r in reviews if (r.get('user') or {}).get('login') in ('Copilot', 'copilot-pull-request-reviewer[bot]')]
if not copilot:
    sys.exit(0)
copilot.sort(key=lambda r: r.get('submitted_at') or '', reverse=True)
latest = copilot[0]
rid = latest.get('id')
commit = latest.get('commit_id') or ''
at = latest.get('submitted_at') or ''
body = (latest.get('body') or '').strip()
# Match either of the two known clean-body phrasings — see Pass 1 comment block
# for the full rationale and the PR #474 (teisutis) reference that surfaced
# the 'generated no new comments' variant.
CLEAN_PHRASES = ('found no new issues', 'generated no new comments')
body_l = body.lower()
clean = 'true' if any(p in body_l for p in CLEAN_PHRASES) else 'false'
print(f'COPILOT_LATEST_REVIEW={rid} COMMIT={commit} AT={at} CLEAN={clean}')
" 2>/dev/null || true)

if [ -n "$LATEST_REVIEW_LINE" ]; then
    # Same plain-text contract as COPILOT_CLEAN_SIGNAL — no ANSI codes.
    echo "$LATEST_REVIEW_LINE"
    echo ""
fi

# Any other copilot reviews with substantive bodies (umbrella summaries, partial clean,
# older clean signals for prior SHAs). Surface them so the loop can see non-clean
# review history — useful when copilot is iterating across pushes.
OTHER_REVIEWS=$(echo "$REVIEWS" | python3 -c "
import json, sys
try:
    reviews = json.load(sys.stdin)
except Exception:
    sys.exit(0)
copilot = [r for r in reviews if (r.get('user') or {}).get('login') in ('Copilot', 'copilot-pull-request-reviewer[bot]')]
copilot.sort(key=lambda r: r.get('submitted_at') or '', reverse=True)
shown = 0
CLEAN_PHRASES = ('found no new issues', 'generated no new comments')
def _is_clean_body(body):
    body_l = (body or '').lower()
    return any(p in body_l for p in CLEAN_PHRASES)
for r in copilot:
    body = (r.get('body') or '').strip()
    if not body or _is_clean_body(body):
        # Skip empties and any clean-signal review (newest one already surfaced
        # above; older ones are stale clean signals for prior SHAs).
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
    echo -e "${BLUE}🗂  Recent copilot reviews (non-clean / prior SHAs):${NC}"
    echo "$OTHER_REVIEWS"
    echo ""
fi

# ------------------------------------------------------------------------------
# Pass 2 — Inline review comments (findings on specific code lines)
# ------------------------------------------------------------------------------
COPILOT_INLINE=$(echo "$INLINE_COMMENTS" | python3 -c "
import json, sys
try:
    comments = json.load(sys.stdin)
except Exception:
    sys.exit(0)
copilot = [c for c in comments if (c.get('user') or {}).get('login') in ('Copilot', 'copilot-pull-request-reviewer[bot]')]
if copilot:
    print(json.dumps(copilot))
" 2>/dev/null || true)

if [ -n "$COPILOT_INLINE" ]; then
    INLINE_COUNT=$(echo "$COPILOT_INLINE" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
    echo -e "${RED}🐛 Found $INLINE_COUNT copilot inline finding(s):${NC}"
    echo ""

    echo "$COPILOT_INLINE" | python3 -c "
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
    # The pull_request_review_id field ties a comment to a specific copilot review.
    # /review-loop Phase 1 compares this against the COPILOT_LATEST_REVIEW marker
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
    title = title_match.group(1) if title_match else 'Copilot Comment'

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
COPILOT_ISSUE=$(echo "$ISSUE_COMMENTS" | python3 -c "
import json, sys
try:
    comments = json.load(sys.stdin)
except Exception:
    sys.exit(0)
copilot = [c for c in comments if (c.get('user') or {}).get('login') in ('Copilot', 'copilot-pull-request-reviewer[bot]')]
if copilot:
    print(json.dumps(copilot))
" 2>/dev/null || true)

if [ -n "$COPILOT_ISSUE" ]; then
    ISSUE_COUNT=$(echo "$COPILOT_ISSUE" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
    echo -e "${BLUE}💬 Copilot top-level PR comments ($ISSUE_COUNT):${NC}"
    echo ""
    echo "$COPILOT_ISSUE" | python3 -c "
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
if [ -z "$CLEAN_SIGNAL_LINE" ] && [ -z "$LATEST_REVIEW_LINE" ] && [ -z "$COPILOT_INLINE" ] && [ -z "$COPILOT_ISSUE" ] && [ -z "$OTHER_REVIEWS" ] && [ -z "$COPILOT_CHECKRUN_LINE" ]; then
    echo "⏳ No copilot activity yet for PR #$PR_NUMBER."
    echo "   Trigger a review with: ./tools/copilot_retrigger.sh $PR_NUMBER"
    exit 0
fi

echo ""
echo "💡 PR: https://github.com/$REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER"
