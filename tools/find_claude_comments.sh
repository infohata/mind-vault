#!/bin/bash
# Find Claude Code Review activity on a PR — synthesizes the engine-adapter
# contract markers from the `claude-code-action@v1` running the `code-review`
# plugin via the `.github/workflows/claude-code-review.yml` workflow.
# Used by the /review-loop skill (mind-vault) as well as human inspection.
#
# ⚠️ TRAP — action + `code-review` plugin ≠ Anthropic's MANAGED Code Review App.
# We run `anthropics/claude-code-action@v1` (OAuth/subscription-billed) on a
# self-hosted workflow, NOT the managed "Claude Code Review" GitHub App. The
# managed App posts a dedicated `Claude Code Review` CHECK-RUN with severity
# JSON; the action posts NOTHING of the sort. So unlike copilot/bugbot, claude
# has NO pollable named check-run — the only RUNNING/DONE surface is the
# GitHub *Actions* job status of the `claude-code-review` workflow run. Anything
# you read at code.claude.com/docs about machine-readable check-runs describes
# the managed App and DOES NOT APPLY here. See engine-claude.md § Identity.
#
# ── Divergences from find_copilot_comments.sh (architect findings A2/A3/A6/A8) ──
#
# A7/R2 — STATE FROM THE ACTIONS JOB, not a check-run. CLAUDE_CHECKRUN is
#   SYNTHESIZED from `gh api .../actions/workflows/claude-code-review.yml/runs`
#   filtered to the head SHA, picking the LATEST run by `run_started_at` (dedup:
#   the `synchronize` auto-run and any `@claude review once` fallback collapse to
#   one authoritative signal). queued/in_progress → RUNNING; completed → DONE.
#   The Actions CONCLUSION is GREEN whether claude found 0 or 5 issues — it is a
#   RUNNING/DONE signal only, NEVER a verdict.
#
# A6 — CLEAN = SUBSTRING **OR** ZERO-INLINE. clean iff the claude summary comment
#   body contains the case-insensitive substring "no issues found" OR there are
#   zero claude-authored inline comments on the head SHA (after settle). Substring
#   (not the full sentence) per the copilot two-phrasing lesson
#   (find_copilot_comments.sh:182-189 — copilot already burned two wordings). The
#   zero-inline OR-arm covers action issue #1087 (empty result, no summary comment)
#   and any future clean-string drift.
#
# A3 — SETTLE VALVE RELEASES ON COMMENT PRESENCE, NOT CONCLUSION (load-bearing).
#   copilot trusts a review-less `completed` check-run only when CONCLUSION=success.
#   That rule is POISON for claude: claude's Actions conclusion is success EVEN WITH
#   findings, so a conclusion gate would ALWAYS release and ship lagged findings as
#   a false CLEAN. Here: a `completed` Actions run whose head-SHA summary/inline
#   comments have NOT posted is downgraded to STATUS=in_progress (RUNNING) and emits
#   CLAUDE_REVIEW_PENDING. The CLAUDE_REVIEW_SETTLE_SECONDS (default 180) valve, when
#   it elapses on the genuine no-comment-at-all case (#1087), resolves to CLEAN via
#   the ZERO-INLINE arm — it must NEVER bypass a findings-pending state via conclusion.
#   Settle age computed in Python `datetime` (cross-platform), never `date -d`.
#
# A8 — CONSERVATIVE BOTH-AND IDENTITY FILTER. claude's comment author login is
#   UNCONFIRMED until the dogfood — the filter requires BOTH (a) the comment author
#   login matching a claude-action identity AND (b) the code-review plugin's
#   comment-body signature, NEVER either alone, so an over-loose filter fails toward
#   "no clean detected" (keeps polling — safe), never a false CLEAN. See # CALIBRATE
#   markers below for the exact login + body signature to lock on the first run.
#
# A2 — REACHABILITY PROBE. This script reports whether the action is installed by
#   probing `gh api .../actions/workflows` for `claude-code-review.yml`. If absent it
#   emits CLAUDE_NOT_INSTALLED=true and exits 0 so the orchestrator's default
#   resolution can self-exclude claude (degrade loudly) rather than hang to HUNG.
#
# Output contract (engine-adapter-contract.md):
#   - CLAUDE_CHECKRUN=<run-id> COMMIT=<sha> STATUS=<queued|in_progress|completed> CONCLUSION=<...> AT=<iso8601>
#     (synthesized from the Actions run; STATUS RUNNING vs DONE; CONCLUSION never a verdict)
#   - CLAUDE_LATEST_REVIEW=<anchor-id> COMMIT=<sha> AT=<iso8601> [CLEAN=<bool>]
#     (anchor = summary-comment id, or newest head-SHA inline comment id if no summary)
#   - CLAUDE_CLEAN_SIGNAL=... (legacy / non-authoritative — orchestrator derives clean structurally)
#   - inline finding blocks each carrying the mandatory `(comment id <cid>, review <rid>)` token
#   - CLAUDE_NOT_INSTALLED=true (reachability) / CLAUDE_REVIEW_PENDING=... (race guard)
#   Exit 0 on success.
#
# Usage: ./tools/find_claude_comments.sh [PR_NUMBER]
#        ./tools/find_claude_comments.sh   # Uses current branch's PR

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

# ------------------------------------------------------------------------------
# Reachability probe (A2 / R4) — is the claude-code-review action installed?
# ------------------------------------------------------------------------------
# The /review-loop default-engine resolution gates claude into the DEFAULT set
# only where the action's workflow exists on the target repo. If it's absent we
# emit CLAUDE_NOT_INSTALLED=true and exit 0 so a bare `/review-loop` self-excludes
# claude (degrade loudly) instead of polling an un-provisioned engine to HUNG.
# An explicit `/review-loop <PR> claude` still calls this and gets the same loud
# marker — the orchestrator hands it back, never silent.
#
# Probe by workflow FILENAME, not display name — the file path is stable; the
# `name:` field is author-editable. The managed App (if anyone ever switches to
# it) would NOT add this workflow file, so this also correctly reports "not the
# action path" in that case.
CLAUDE_WORKFLOW_FILE="claude-code-review.yml"
WORKFLOWS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/actions/workflows?per_page=100" 2>/dev/null || echo '{"workflows":[]}')
ACTION_INSTALLED=$(echo "$WORKFLOWS" | CLAUDE_WORKFLOW_FILE="$CLAUDE_WORKFLOW_FILE" python3 -c "
import json, os, sys
try:
    data = json.load(sys.stdin)
except Exception:
    print('false'); sys.exit(0)
wf = data.get('workflows', []) if isinstance(data, dict) else []
target = os.environ.get('CLAUDE_WORKFLOW_FILE', '')
# Match on the workflow file's basename (.path ends with /<file>).
hit = any((w.get('path') or '').endswith('/' + target) or (w.get('path') or '') == target for w in wf)
print('true' if hit else 'false')
" 2>/dev/null || echo "false")

if [ "$ACTION_INSTALLED" != "true" ]; then
    echo "CLAUDE_NOT_INSTALLED=true"
    echo -e "${YELLOW}⚠️  claude-code-review action not installed on $REPO_OWNER/$REPO_NAME (no $CLAUDE_WORKFLOW_FILE workflow).${NC}"
    echo "   Install with: /install-github-app (then set CLAUDE_CODE_OAUTH_TOKEN secret)."
    echo "   The /review-loop default set self-excludes claude here; an explicit 'claude' degrades loudly."
    exit 0
fi

echo "📋 Fetching claude review activity for PR #$PR_NUMBER..."
echo ""

# Head SHA — anchors both the Actions-run filter and the head-SHA-aware finding
# precheck. Degrade gracefully to empty if the fetch fails.
PR_HEAD_SHA=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER" -q '.head.sha' 2>/dev/null || echo "")

# Fetch comment + run endpoints up-front (each defaults to []/empty-shape on
# failure so the python passes never receive empty stdin). per_page=100 avoids
# the default-30 cap dropping the most recent comment on a long-iteration PR.
INLINE_COMMENTS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER/comments?per_page=100" 2>/dev/null || echo "[]")
ISSUE_COMMENTS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/issues/$PR_NUMBER/comments?per_page=100" 2>/dev/null || echo "[]")

# Actions runs for the claude-code-review workflow (A7/R2). If `actions: read`
# is unreadable for the user's gh auth we degrade to summary-comment-only state
# (lose the RUNNING signal) — Q3, resolved at dogfood. Empty-shape default keeps
# the python pass honest.
WORKFLOW_RUNS=$(gh api "repos/$REPO_OWNER/$REPO_NAME/actions/workflows/$CLAUDE_WORKFLOW_FILE/runs?per_page=100" 2>/dev/null || echo '{"workflow_runs":[]}')

# ==============================================================================
# CALIBRATED — dogfood step 9 on PR #167 (claude-code-action run 26834423838,
# 2026-06-02, model claude-sonnet-4-6). Confirmed against the live run log:
# ------------------------------------------------------------------------------
# IDENTITY (Q1) — CONFIRMED `github-actions[bot]`. The action posts inline
#   comments via the workflow `GITHUB_TOKEN` (log: post-buffered-inline-comments.ts
#   with GITHUB_TOKEN env), so the author login is the shared `github-actions[bot]`,
#   NOT a `claude[bot]` app identity. (Extra app-style logins kept as harmless
#   future-proofing in case the action switches to an app token.)
#
# POSTING MODEL — CONFIRMED the action posts ONLY *buffered inline review comments*
#   (one post-step). There is NO top-level summary comment in the action+plugin
#   flow (that's a managed-App behavior). So:
#     • CLEAN signal = ZERO claude inline comments on the head SHA (the A6
#       zero-inline arm is THE clean signal here; the summary-substring arm is
#       dead backup that this action never exercises).
#     • This run logged "No buffered inline comments" → genuinely CLEAN.
#
# INLINE FILTER — CALIBRATION REFINES A8. A8 prescribed BOTH-AND (login AND body
#   signature) to stop a loose login from over-claiming. But for INLINE review
#   comments that asymmetry is DANGEROUS: a body-signature that doesn't match
#   claude's real comment body would filter a genuine finding OUT → zero-inline →
#   FALSE CLEAN (the one direction we must never fail). On this repo, NOTHING ELSE
#   posts inline *review* comments as `github-actions[bot]` (inline review comments
#   are review output by construction), so login-membership ALONE is both correct
#   and the safe direction for inline (errs toward over-counting → keep polling,
#   never a false clean). Inline detection is therefore LOGIN-ONLY. If a second
#   bot ever posts inline review comments via the Actions token, reintroduce a
#   body-signature AND-clause here.
#
# SUMMARY FILTER — keeps BOTH-AND (login AND body signature). The action posts no
#   summary today, but IF one ever appears, a stray `github-actions[bot]` issue
#   comment containing "no issues" must NOT be mistaken for a claude clean signal
#   — so summary clean-detection still requires the body signature. (Here the
#   false-positive direction is the dangerous one, so BOTH-AND is correct.)
#
# CLEAN SUBSTRING (A6) — unverified in the wild (no summary ever posted); retained
#   as harmless backup for the summary arm. The zero-inline arm is authoritative.
#
# STILL UNCALIBRATED (no finding observed yet — this run was clean):
#   • CLAUDE_BODY_SIGNATURES exact wording (only matters for the summary arm now).
#   • Whether inline findings share a pull_request_review_id (Q1) — anchor keys on
#     comment id either way, so safe; confirm when claude first posts a finding
#     (step 10 tri-engine on a rougher diff, or a deliberate probe).
# ==============================================================================
# Single source of truth — exported once, read by every python pass via env.
export CLAUDE_LOGINS='github-actions[bot] claude[bot] claude-code-action[bot]'
export CLAUDE_BODY_SIGNATURES='claude code review|generated by claude|reviewed by claude|code-review'
export CLAUDE_CLEAN_SUBSTRING='no issues found'

# ------------------------------------------------------------------------------
# Pass 1 — Review-state from the Actions job (A7/R2): synthesize CLAUDE_CHECKRUN
# ------------------------------------------------------------------------------
# Filter runs to the head SHA, pick the LATEST by `run_started_at` (dedup of the
# synchronize auto-run + any fallback retrigger). Map queued/in_progress→RUNNING,
# completed→DONE. The Actions conclusion is emitted for forensics ONLY — never a
# verdict (it is green with or without findings).
CLAUDE_CHECKRUN_LINE=$(echo "$WORKFLOW_RUNS" | PR_HEAD_SHA="$PR_HEAD_SHA" python3 -c "
import json, os, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
runs = data.get('workflow_runs', []) if isinstance(data, dict) else []
head = os.environ.get('PR_HEAD_SHA', '')
# Filter to the head SHA when known; if head is unknown (PR fetch failed),
# fall back to the newest run overall so we still emit a RUNNING/DONE signal.
if head:
    runs = [r for r in runs if (r.get('head_sha') or '') == head]
if not runs:
    sys.exit(0)
# Latest by run_started_at (A7 dedup). Fall back to created_at then id.
runs.sort(key=lambda r: (r.get('run_started_at') or r.get('created_at') or '', r.get('id') or 0), reverse=True)
latest = runs[0]
rid = latest.get('id') or ''
sha = latest.get('head_sha') or ''
status = latest.get('status') or ''      # queued | in_progress | completed
conclusion = latest.get('conclusion') or ''
# AT anchors the settle valve — prefer updated_at (when it completed) then run_started_at.
at = latest.get('updated_at') or latest.get('run_started_at') or latest.get('created_at') or ''
print(f'CLAUDE_CHECKRUN={rid} COMMIT={sha} STATUS={status} CONCLUSION={conclusion} AT={at}')
" 2>/dev/null || true)

# ------------------------------------------------------------------------------
# Pass 2 — claude-authored head-SHA inline comments + summary comment
# ------------------------------------------------------------------------------
# Identity (calibrated PR #167): INLINE = login-only (github-actions[bot]; the
# safe direction — see the CALIBRATED block above); SUMMARY = BOTH-AND (login AND
# body signature, so a stray github-actions[bot] "no issues" issue comment can't
# fake a clean). Inline findings are the staleness corpus + the zero-inline clean
# signal; the summary comment (if the action ever posts one) carries the substring. Emit:
#   - CLAUDE_HEAD_INLINE_COUNT  — # of claude inline comments ON the head SHA
#   - CLAUDE_SUMMARY_PRESENT / CLAUDE_SUMMARY_CLEAN — for the clean OR-arm + race guard
#   - CLAUDE_ANCHOR_ID / CLAUDE_ANCHOR_AT — the LATEST_REVIEW anchor
#   - CLAUDE_INLINE_JSON — claude inline comments (head SHA) for the finding render
CLAUDE_INLINE_JSON=$(echo "$INLINE_COMMENTS" | PR_HEAD_SHA="$PR_HEAD_SHA" python3 -c "
import json, os, sys
try:
    comments = json.load(sys.stdin)
except Exception:
    sys.exit(0)
head = os.environ.get('PR_HEAD_SHA', '')
logins = set(os.environ.get('CLAUDE_LOGINS', '').split())
def is_claude(c):
    # LOGIN-ONLY for inline review comments (calibrated on PR #167, refines A8).
    # Inline review comments are review output by construction; nothing else posts
    # them as github-actions[bot] on this repo. Requiring a body-signature here
    # would risk filtering a real finding OUT → false CLEAN (the one unsafe
    # direction). Login-membership errs toward over-counting → keep polling, never
    # a false clean. (Re-add a body-signature AND-clause iff a 2nd bot ever posts
    # inline review comments via the Actions token.)
    login = (c.get('user') or {}).get('login') or ''
    return login in logins
# Inline review-comments carry original_commit_id / commit_id; restrict to the
# head SHA so stale prior-SHA threads (GitHub keeps them visible until resolve)
# don't masquerade as active findings.
def on_head(c):
    if not head:
        return True
    return (c.get('commit_id') or '') == head or (c.get('original_commit_id') or '') == head
claude = [c for c in comments if is_claude(c) and on_head(c)]
if claude:
    print(json.dumps(claude))
" 2>/dev/null || true)

# Summary comment (top-level issue comment) — clean-substring OR-arm + race guard.
CLAUDE_SUMMARY_LINE=$(echo "$ISSUE_COMMENTS" | python3 -c "
import json, os, re, sys
try:
    comments = json.load(sys.stdin)
except Exception:
    sys.exit(0)
logins = set(os.environ.get('CLAUDE_LOGINS', '').split())
sig_re = re.compile(os.environ.get('CLAUDE_BODY_SIGNATURES', 'a^'), re.IGNORECASE)
clean_sub = os.environ.get('CLAUDE_CLEAN_SUBSTRING', '').lower()
def is_claude(c):
    login = (c.get('user') or {}).get('login') or ''
    body = c.get('body') or ''
    return login in logins and bool(sig_re.search(body))
claude = [c for c in comments if is_claude(c)]
if not claude:
    sys.exit(0)
# Newest first.
claude.sort(key=lambda c: c.get('created_at') or '', reverse=True)
latest = claude[0]
cid = latest.get('id') or ''
at = latest.get('created_at') or ''
body_l = (latest.get('body') or '').lower()
is_clean = 'true' if (clean_sub and clean_sub in body_l) else 'false'
print(f'CLAUDE_SUMMARY_ID={cid} AT={at} CLEAN={is_clean}')
" 2>/dev/null || true)

# Derive presence/clean/anchor scalars from the two passes (bash side; `|| true`
# on every grep -oE because empty captures would make grep exit 1 under -eo pipefail).
SUMMARY_ID=$(echo "$CLAUDE_SUMMARY_LINE" | grep -oE 'CLAUDE_SUMMARY_ID=[^ ]+' | cut -d= -f2 || true)
SUMMARY_AT=$(echo "$CLAUDE_SUMMARY_LINE" | grep -oE 'AT=[^ ]+' | cut -d= -f2 || true)
SUMMARY_CLEAN=$(echo "$CLAUDE_SUMMARY_LINE" | grep -oE 'CLEAN=[^ ]+' | cut -d= -f2 || true)

if [ -n "$CLAUDE_INLINE_JSON" ]; then
    HEAD_INLINE_COUNT=$(echo "$CLAUDE_INLINE_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
else
    HEAD_INLINE_COUNT=0
fi

# Newest head-SHA inline comment id — the LATEST_REVIEW anchor fallback when no
# summary comment exists (Q1: inline comments may or may not share a
# pull_request_review_id; we key the anchor on the comment id either way).
INLINE_ANCHOR_LINE=$(echo "${CLAUDE_INLINE_JSON:-[]}" | python3 -c "
import json, sys
try:
    comments = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not comments:
    sys.exit(0)
comments.sort(key=lambda c: c.get('created_at') or '', reverse=True)
top = comments[0]
cid = top.get('id') or ''
at = top.get('created_at') or ''
# review id may be shared across inline comments (Q1) — surface it if present.
rid = top.get('pull_request_review_id') or ''
print(f'CLAUDE_INLINE_ANCHOR={cid} AT={at} REVIEW={rid}')
" 2>/dev/null || true)
INLINE_ANCHOR_ID=$(echo "$INLINE_ANCHOR_LINE" | grep -oE 'CLAUDE_INLINE_ANCHOR=[^ ]+' | cut -d= -f2 || true)
INLINE_ANCHOR_AT=$(echo "$INLINE_ANCHOR_LINE" | grep -oE 'AT=[^ ]+' | cut -d= -f2 || true)

# A head-SHA claude comment (summary OR inline) has posted iff either is present.
# This is the A3 race-guard gate: comment PRESENCE, not Actions conclusion.
COMMENT_POSTED=false
if [ -n "$SUMMARY_ID" ] || [ "$HEAD_INLINE_COUNT" -gt 0 ] 2>/dev/null; then
    COMMENT_POSTED=true
fi

# ------------------------------------------------------------------------------
# Review-state gate + review-pending race guard (A3) — the load-bearing divergence
# ------------------------------------------------------------------------------
if [ -n "$CLAUDE_CHECKRUN_LINE" ]; then
    cr_status=$(echo "$CLAUDE_CHECKRUN_LINE" | grep -oE 'STATUS=[^ ]+' | cut -d= -f2 || true)
    cr_id=$(echo "$CLAUDE_CHECKRUN_LINE" | grep -oE 'CLAUDE_CHECKRUN=[^ ]+' | cut -d= -f2 || true)
    cr_sha=$(echo "$CLAUDE_CHECKRUN_LINE" | grep -oE 'COMMIT=[^ ]+' | cut -d= -f2 || true)
    cr_at=$(echo "$CLAUDE_CHECKRUN_LINE" | grep -oE 'AT=[^ ]+' | cut -d= -f2 || true)

    # ── Review-pending race guard (A3 — releases on COMMENT PRESENCE) ───────────
    # The Actions job flips to `completed` BEFORE claude's summary/inline comments
    # post (and #1087: sometimes no comment ever posts). A poll in that gap sees
    # DONE + zero findings → false CLEAN. So a `completed` run whose head-SHA
    # comments have NOT posted is downgraded to in_progress (RUNNING) — the loop
    # keeps waiting.
    #
    # CRITICAL vs copilot: copilot's valve releases a review-less `completed` run
    # ONLY on CONCLUSION=success. claude's Actions CONCLUSION is success EVEN WITH
    # findings — a conclusion gate would ALWAYS release and ship lagged findings as
    # a false CLEAN. So the valve here keys on the SETTLE WINDOW alone (not the
    # conclusion). When it elapses on the genuine no-comment-at-all case (#1087) it
    # releases to DONE, and the clean verdict is reached via the ZERO-INLINE arm
    # (HEAD_INLINE_COUNT==0 + no summary). It NEVER bypasses a findings-pending
    # state, because if comments HAD posted, COMMENT_POSTED=true and we never enter
    # the downgrade branch at all.
    #
    # Default 180s (calibrated PR #167, NOT copilot's 600). claude-code-action posts
    # its buffered inline comments *synchronously within the job* (the
    # post-buffered-inline-comments step runs BEFORE the run reports `completed`),
    # so comments — if any — already exist at completed-time; the settle only needs
    # to cover GitHub API read-consistency after that in-job post, not copilot's
    # minutes-long async-review lag. 180s is a generous margin for that.
    SETTLE=${CLAUDE_REVIEW_SETTLE_SECONDS:-180}
    CLAUDE_DOWNGRADED=
    if [ "$cr_status" = "completed" ] && [ "$COMMENT_POSTED" != "true" ]; then
        # Settle decision in Python `datetime` (cross-platform; never `date -d`).
        # Emits "elapsed" iff cr_at parsed AND (now - cr_at) >= SETTLE; "pending"
        # otherwise — a parse failure lands on "pending" (default safe = keep waiting).
        settle_state=$(SETTLE="$SETTLE" CR_AT="$cr_at" python3 -c "
import os
from datetime import datetime, timezone
try:
    settle = int(os.environ.get('SETTLE', '180'))  # match bash default (calibrated PR #167); was '600' (copilot's window) — a refactor that ran this snippet standalone would silently use the wrong window
    # Normalize trailing Z → +00:00 so fromisoformat works on Python < 3.11 too.
    dt = datetime.fromisoformat(os.environ.get('CR_AT', '').replace('Z', '+00:00'))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    age = (datetime.now(timezone.utc) - dt).total_seconds()
    print('elapsed' if age >= settle else 'pending')
except Exception:
    print('pending')
" 2>/dev/null || echo "pending")
        # NOTE (A3): NO conclusion gate here. The valve releases purely on the
        # settle window. The only way past this branch with comments-present is
        # COMMENT_POSTED=true (checked above), so an elapsed valve can only release
        # the genuine #1087 no-comment case → clean via zero-inline.
        if [ "$settle_state" != "elapsed" ]; then
            cr_status="in_progress"
            CLAUDE_CHECKRUN_LINE=$(echo "$CLAUDE_CHECKRUN_LINE" | sed 's/STATUS=completed/STATUS=in_progress/')
            CLAUDE_DOWNGRADED=1
        fi
    fi

    echo "$CLAUDE_CHECKRUN_LINE"

    if [ "$cr_status" = "completed" ]; then
        echo -e "${GREEN}✅ Claude Actions run completed for PR head (RUNNING/DONE signal only — conclusion is never a verdict).${NC}"
        # Structural clean (A6): summary substring OR zero head-SHA inline comments.
        # The orchestrator derives clean structurally; the legacy CLAUDE_CLEAN_SIGNAL
        # below is corroboration only.
        if [ "$SUMMARY_CLEAN" = "true" ] || [ "$HEAD_INLINE_COUNT" -eq 0 ] 2>/dev/null; then
            anchor_id="$SUMMARY_ID"
            anchor_at="$SUMMARY_AT"
            [ -z "$anchor_id" ] && anchor_id="$INLINE_ANCHOR_ID" && anchor_at="$INLINE_ANCHOR_AT"
            [ -z "$anchor_id" ] && anchor_id="checkrun-${cr_id}" && anchor_at="$cr_at"
            echo "CLAUDE_CLEAN_SIGNAL=${anchor_id} COMMIT=${cr_sha} AT=${anchor_at}"
        fi
    elif [ -n "$CLAUDE_DOWNGRADED" ]; then
        echo "CLAUDE_REVIEW_PENDING=run-${cr_id} COMMIT=${cr_sha} SETTLE=${SETTLE}s"
        echo -e "${YELLOW}⏳ Claude Actions run completed but no head-SHA summary/inline comment posted yet — treating as RUNNING (review-pending race guard, A3) to avoid a false CLEAN.${NC}"
    fi
    echo ""
fi

# ------------------------------------------------------------------------------
# CLAUDE_LATEST_REVIEW — staleness anchor (comment-anchored; A4 synthesized id)
# ------------------------------------------------------------------------------
# Anchor = summary-comment id if present, else newest head-SHA inline comment id
# (Q1: inline comments may share a pull_request_review_id; we anchor on comment id
# either way). Mandatory when ANY claude activity exists so the orchestrator's
# staleness rule has a reference. CLEAN= is legacy/ignored by the orchestrator.
LATEST_ANCHOR_ID="$SUMMARY_ID"
LATEST_ANCHOR_AT="$SUMMARY_AT"
LATEST_CLEAN="$SUMMARY_CLEAN"
if [ -z "$LATEST_ANCHOR_ID" ]; then
    LATEST_ANCHOR_ID="$INLINE_ANCHOR_ID"
    LATEST_ANCHOR_AT="$INLINE_ANCHOR_AT"
    # No summary → clean derives from the zero-inline arm structurally; report
    # CLEAN=false here when inline findings exist, true when none (legacy hint only).
    if [ "$HEAD_INLINE_COUNT" -eq 0 ] 2>/dev/null; then LATEST_CLEAN=true; else LATEST_CLEAN=false; fi
fi
if [ -n "$LATEST_ANCHOR_ID" ]; then
    echo "CLAUDE_LATEST_REVIEW=${LATEST_ANCHOR_ID} COMMIT=${PR_HEAD_SHA} AT=${LATEST_ANCHOR_AT} CLEAN=${LATEST_CLEAN:-false}"
    echo ""
fi

# ------------------------------------------------------------------------------
# Inline findings (head SHA) — each block carries the mandatory token
#   (comment id <cid>, review <rid>)
# ------------------------------------------------------------------------------
if [ -n "$CLAUDE_INLINE_JSON" ] && [ "$HEAD_INLINE_COUNT" -gt 0 ] 2>/dev/null; then
    echo -e "${RED}🐛 Found $HEAD_INLINE_COUNT claude inline finding(s) on the head SHA:${NC}"
    echo ""
    echo "$CLAUDE_INLINE_JSON" | python3 -c "
import json, re, sys
comments = json.load(sys.stdin)

# Severity heuristic — the code-review plugin's severity stamp is UNCONFIRMED.
# CALIBRATE (Q1/dogfood): lock the real markers once a findings-bearing review
# lands. Until then accept the common spellings + fall back to INFO.
def get_severity(body):
    b = (body or '').lower()
    if 'critical' in b:
        return 0, 'CRITICAL', '\033[0;31m'
    if 'high' in b or '❌' in body:
        return 1, 'HIGH', '\033[0;31m'
    if 'medium' in b or '⚠️' in body:
        return 2, 'MEDIUM', '\033[1;33m'
    if 'low' in b:
        return 3, 'LOW', '\033[0;32m'
    return 4, 'INFO', ''

comments.sort(key=lambda c: (get_severity(c.get('body', ''))[0], c.get('path', ''), c.get('line') or 0))

for i, comment in enumerate(comments, 1):
    path = comment.get('path', 'unknown')
    line = comment.get('line', '?')
    body = comment.get('body', '') or ''
    url = comment.get('html_url', '')
    cid = comment.get('id', '')
    # Q1: inline comments MAY share a pull_request_review_id. Surface it as <rid>;
    # the orchestrator's staleness filter compares it against CLAUDE_LATEST_REVIEW.
    # When null/absent (comment-anchored, no shared review) coalesce to '' — the
    # orchestrator tolerates an empty review token on comment-anchored engines.
    rev_id = comment.get('pull_request_review_id') or ''
    _, severity, severity_color = get_severity(body)

    # Title = first markdown heading, else first non-empty line.
    title = ''
    m = re.search(r'^#{1,6}\s+(.+)$', body, re.MULTILINE)
    if m:
        title = m.group(1).strip()
    else:
        for ln in body.splitlines():
            if ln.strip():
                title = ln.strip()[:200]
                break
    if not title:
        title = 'Claude Comment'

    separator = '━' * 80
    print(f'{severity_color}{separator}\033[0m')
    # Mandatory contract token — verbatim '(comment id <cid>, review <rid>)'.
    print(f'{severity_color}[{i}/{len(comments)}] Severity: {severity} (comment id {cid}, review {rev_id})\033[0m')
    print(f'\033[0;34m**File:**\033[0m {path}:{line}')
    print(f'\033[0;34m**Title:**\033[0m {title}')
    print(f'\033[0;34m**Description:**\033[0m')
    print(body.strip())
    print('')
    print(f'\033[0;34m**Link:**\033[0m {url}')
    print('')
"
fi

# ------------------------------------------------------------------------------
# Summary comment surface (top-level) — informational, by id
# ------------------------------------------------------------------------------
if [ -n "$CLAUDE_SUMMARY_LINE" ]; then
    echo "$CLAUDE_SUMMARY_LINE"
    if [ "$SUMMARY_CLEAN" = "true" ]; then
        echo -e "${GREEN}✅ Claude summary comment contains the clean substring.${NC}"
    else
        echo -e "${BLUE}💬 Claude summary comment present (id $SUMMARY_ID) — see body for verdict.${NC}"
    fi
    echo ""
fi

# ------------------------------------------------------------------------------
# Summary / no-activity
# ------------------------------------------------------------------------------
if [ -z "$CLAUDE_CHECKRUN_LINE" ] && [ -z "$CLAUDE_SUMMARY_LINE" ] && [ -z "$CLAUDE_INLINE_JSON" ] && [ -z "$LATEST_ANCHOR_ID" ]; then
    echo "⏳ No claude activity yet for PR #$PR_NUMBER (no Actions run for the head SHA, no comments)."
    echo "   claude is push-triggered (the action auto-runs on every push). If the auto-run"
    echo "   didn't fire, bootstrap with the fallback: ./tools/claude_retrigger.sh $PR_NUMBER"
    exit 0
fi

echo ""
echo "💡 PR: https://github.com/$REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER"
