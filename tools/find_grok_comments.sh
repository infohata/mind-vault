#!/bin/bash
# find_grok_comments.sh — Grok Build review adapter (auto-trigger / comment-anchored).
#
# Category: auto-trigger / comment-anchored (same family as claude).
# Identity: sticky issue comment from github-actions[bot] containing
#   <!-- grok-code-review -->
# Review-state: synthesized from Actions runs of grok-code-review.yml
# Clean: prose-only surface → model-judge (IDEA-022 carve-out); adapter surfaces
#   the sticky body + GROK_VERDICT_SET_PROVEN.
#
# Simpler than find_claude_comments.sh: no inline-review path (Grok posts one
# sticky issue comment), marker-anchored identity, fewer calibration arms.
#
# Markers (contract: skills/review-loop/references/engine-adapter-contract.md):
#   GROK_NOT_INSTALLED=true
#   GROK_DRAFT_NOOP=true
#   GROK_CHECKRUN=<id> COMMIT=<sha> STATUS=... CONCLUSION=... AT=... RUNS=<n> WINDOW_START=...
#   GROK_VERDICT_SET_PROVEN=<true|false>
#   GROK_LATEST_REVIEW=<comment-id> COMMIT=<sha> AT=<iso8601>
#   GROK_REVIEW_SILENT=true   (success job, no sticky after settle)
#   + verbatim sticky body for the model-judge
#
# Usage: ./tools/find_grok_comments.sh <PR_NUMBER>
# Invoke with CWD = the project under review (gh resolves repo from CWD).

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <PR_NUMBER>" >&2
    exit 1
fi
PR_NUMBER="$1"
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "❌ Invalid PR number: '$PR_NUMBER'" >&2
    exit 1
fi

REPO_FULL=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
if [ -z "$REPO_FULL" ]; then
    echo "❌ Could not determine repository owner/name" >&2
    exit 1
fi
REPO_OWNER="${REPO_FULL%%/*}"
REPO_NAME="${REPO_FULL#*/}"

GROK_WORKFLOW_FILE="grok-code-review.yml"
GROK_MARKER='<!-- grok-code-review -->'
GROK_REVIEW_SETTLE_SECONDS="${GROK_REVIEW_SETTLE_SECONDS:-600}"

# ── Reachability probe ──────────────────────────────────────────────────────
WORKFLOWS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/actions/workflows?per_page=100" 2>/dev/null || echo '{"workflows":[]}')
ACTION_INSTALLED=$(echo "$WORKFLOWS" | GROK_WORKFLOW_FILE="$GROK_WORKFLOW_FILE" python3 -c "
import json, os, sys
try:
    data = json.load(sys.stdin)
except Exception:
    print('false'); sys.exit(0)
wf = data.get('workflows', []) if isinstance(data, dict) else []
target = os.environ.get('GROK_WORKFLOW_FILE', '')
hit = any((w.get('path') or '').endswith('/' + target) or (w.get('path') or '') == target for w in wf)
print('true' if hit else 'false')
" 2>/dev/null || echo "false")

if [ "$ACTION_INSTALLED" != "true" ]; then
    echo "GROK_NOT_INSTALLED=true"
    echo -e "${YELLOW}⚠️  grok-code-review action not installed on $REPO_OWNER/$REPO_NAME (no $GROK_WORKFLOW_FILE workflow).${NC}"
    echo "   Add .github/workflows/grok-code-review.yml + secret XAI_API_KEY (see docs/GROK_BUILD.md)."
    echo "   The /review-loop default set self-excludes grok here; an explicit 'grok' degrades loudly."
    exit 0
fi

# ── Draft-PR no-op ──────────────────────────────────────────────────────────
PR_IS_DRAFT=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER" -q '.draft' 2>/dev/null || echo "")
if [ "$PR_IS_DRAFT" = "true" ]; then
    echo "GROK_DRAFT_NOOP=true"
    echo -e "${YELLOW}⚠️  PR #$PR_NUMBER is a DRAFT — Grok workflow skips drafts (job if: / resolve step). Not a clean verdict.${NC}"
    echo "   Mark ready ('gh pr ready $PR_NUMBER'); /review-loop pre-flight normally un-drafts before Phase 1."
    exit 0
fi

echo "📋 Fetching Grok review activity for PR #$PR_NUMBER..."
echo ""

PR_HEAD_SHA=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER" -q '.head.sha' 2>/dev/null || echo "")
ISSUE_COMMENTS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/issues/$PR_NUMBER/comments?per_page=100" 2>/dev/null || echo '[]')
WORKFLOW_RUNS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/actions/workflows/$GROK_WORKFLOW_FILE/runs?per_page=50" 2>/dev/null || echo '{"workflow_runs":[]}')

# Synthesize GROK_CHECKRUN from Actions runs for the head SHA (or latest run).
GROK_CHECKRUN_LINE=$(echo "$WORKFLOW_RUNS" | PR_HEAD_SHA="$PR_HEAD_SHA" python3 -c "
import json, os, sys
from datetime import datetime, timezone
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
runs = data.get('workflow_runs') or []
head = os.environ.get('PR_HEAD_SHA') or ''
# Prefer runs whose head_sha matches PR head; else newest overall.
matched = [r for r in runs if (r.get('head_sha') or '') == head] if head else []
pool = matched if matched else runs
if not pool:
    sys.exit(0)
# Newest by run_started_at / created_at
def key(r):
    return r.get('run_started_at') or r.get('updated_at') or r.get('created_at') or ''
pool.sort(key=key, reverse=True)
r = pool[0]
status = r.get('status') or 'queued'
conclusion = r.get('conclusion') or ''
# Map GitHub Actions status → contract STATUS
if status in ('queued', 'waiting', 'requested', 'pending'):
    out_status = 'queued'
elif status in ('in_progress',):
    out_status = 'in_progress'
elif status == 'completed':
    out_status = 'completed'
else:
    out_status = status
rid = r.get('id') or 0
sha = r.get('head_sha') or head or ''
at = r.get('updated_at') or r.get('run_started_at') or ''
window = min((x.get('run_started_at') or x.get('created_at') or '') for x in pool) if pool else at
print(f'GROK_CHECKRUN={rid} COMMIT={sha} STATUS={out_status} CONCLUSION={conclusion or \"none\"} AT={at} RUNS={len(pool)} WINDOW_START={window}')
" 2>/dev/null || true)

# Sticky comment: github-actions[bot] + marker (BOTH-AND — shared login is noisy).
STICKY_JSON=$(echo "$ISSUE_COMMENTS" | GROK_MARKER="$GROK_MARKER" python3 -c "
import json, os, sys
try:
    comments = json.load(sys.stdin)
except Exception:
    print('null'); sys.exit(0)
if not isinstance(comments, list):
    print('null'); sys.exit(0)
marker = os.environ.get('GROK_MARKER', '')
# Prefer newest matching sticky
hits = []
for c in comments:
    body = c.get('body') or ''
    login = ((c.get('user') or {}).get('login') or '')
    if marker in body and login in ('github-actions[bot]', 'grok[bot]', 'xai[bot]'):
        hits.append(c)
if not hits:
    # Marker alone (workflow may post under a renamed actor in future)
    hits = [c for c in comments if marker in (c.get('body') or '')]
if not hits:
    print('null'); sys.exit(0)
hits.sort(key=lambda c: c.get('updated_at') or c.get('created_at') or '', reverse=True)
c = hits[0]
print(json.dumps({
    'id': c.get('id'),
    'body': c.get('body') or '',
    'created_at': c.get('created_at') or '',
    'updated_at': c.get('updated_at') or c.get('created_at') or '',
    'html_url': c.get('html_url') or '',
    'login': ((c.get('user') or {}).get('login') or ''),
}))
" 2>/dev/null || echo 'null')

GROK_VERDICT_SET_PROVEN=false
LATEST_ANCHOR_ID=""
LATEST_ANCHOR_AT=""
STICKY_BODY=""

if [ "$STICKY_JSON" != "null" ] && [ -n "$STICKY_JSON" ]; then
    LATEST_ANCHOR_ID=$(echo "$STICKY_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id') or '')" 2>/dev/null || true)
    LATEST_ANCHOR_AT=$(echo "$STICKY_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('updated_at') or d.get('created_at') or '')" 2>/dev/null || true)
    STICKY_BODY=$(echo "$STICKY_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('body') or '')" 2>/dev/null || true)
    if [ -n "$LATEST_ANCHOR_ID" ] && [ -n "$STICKY_BODY" ]; then
        GROK_VERDICT_SET_PROVEN=true
    fi
fi

# Comment-anchored settle: DONE only when sticky present (or genuine empty after settle on success).
if [ -n "${GROK_CHECKRUN_LINE:-}" ]; then
    cr_status=$(echo "$GROK_CHECKRUN_LINE" | grep -oE 'STATUS=[^ ]+' | cut -d= -f2 || true)
    cr_conclusion=$(echo "$GROK_CHECKRUN_LINE" | grep -oE 'CONCLUSION=[^ ]+' | cut -d= -f2 || true)
    cr_at=$(echo "$GROK_CHECKRUN_LINE" | grep -oE 'AT=[^ ]+' | cut -d= -f2 || true)

    if [ "$cr_status" = "completed" ] && [ -z "$LATEST_ANCHOR_ID" ]; then
        # Review-pending: completed job but no sticky yet — hold RUNNING unless settle elapsed on success.
        AGE_OK=$(CR_AT="$cr_at" SETTLE="$GROK_REVIEW_SETTLE_SECONDS" python3 -c "
import os, sys
from datetime import datetime, timezone
at = os.environ.get('CR_AT') or ''
settle = int(os.environ.get('SETTLE') or '600')
if not at:
    print('false'); sys.exit(0)
try:
    # GitHub timestamps are Zulu
    ts = datetime.fromisoformat(at.replace('Z', '+00:00'))
except Exception:
    print('false'); sys.exit(0)
age = (datetime.now(timezone.utc) - ts).total_seconds()
print('true' if age >= settle else 'false')
" 2>/dev/null || echo "false")
        if [ "$cr_conclusion" = "success" ] && [ "$AGE_OK" = "true" ]; then
            # Genuine empty / failed-to-post after settle — surface SILENT, not false CLEAN.
            echo "GROK_REVIEW_SILENT=true"
            echo -e "${YELLOW}⚠️  Grok Actions job completed success but no sticky <!-- grok-code-review --> comment after ${GROK_REVIEW_SETTLE_SECONDS}s settle — SILENT, not clean.${NC}"
        else
            GROK_CHECKRUN_LINE=$(echo "$GROK_CHECKRUN_LINE" | sed 's/STATUS=completed/STATUS=in_progress/')
            echo "GROK_REVIEW_PENDING=true"
        fi
    fi
    echo "$GROK_CHECKRUN_LINE"
fi

echo "GROK_VERDICT_SET_PROVEN=${GROK_VERDICT_SET_PROVEN}"

if [ -n "$LATEST_ANCHOR_ID" ]; then
    echo "GROK_LATEST_REVIEW=${LATEST_ANCHOR_ID} COMMIT=${PR_HEAD_SHA} AT=${LATEST_ANCHOR_AT}"
fi

# Surface sticky body for model-judge (prose-only engine).
if [ -n "$STICKY_BODY" ]; then
    echo ""
    echo "── GROK sticky review (comment id ${LATEST_ANCHOR_ID}, review ${LATEST_ANCHOR_ID}) ──"
    echo "**File:** (summary sticky)"
    echo "**Title:** Grok Code Review"
    echo "**Description:**"
    echo "$STICKY_BODY"
    STICKY_URL=$(echo "$STICKY_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('html_url') or '')" 2>/dev/null || true)
    if [ -n "$STICKY_URL" ]; then
        echo "**Link:** $STICKY_URL"
    fi
    echo ""
fi

if [ -z "${GROK_CHECKRUN_LINE:-}" ] && [ -z "$LATEST_ANCHOR_ID" ]; then
    echo -e "${YELLOW}No Grok activity yet for PR #$PR_NUMBER (no Actions runs, no sticky).${NC}"
    echo "   Bootstrap with: ./tools/grok_retrigger.sh $PR_NUMBER"
fi

echo ""
echo "💡 PR: https://github.com/$REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER"
exit 0
