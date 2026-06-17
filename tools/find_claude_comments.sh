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
# A6 / LAYER-2 — CLEAN IS A MODEL JUDGMENT, never zero-inline alone (IDEA-022).
#   A claude run can report `success` having posted NOTHING (action issue #1087 — the
#   buffered-comment result-capture grabs a TodoWrite response instead of the review),
#   which is indistinguishable from a genuinely-clean run by run status. So "completed
#   + zero inline" is a FALSE-CLEAN vector, never a clean signal — a no-verdict run is
#   held RUNNING (A3 below) and never reaches the judge. When material IS posted, the
#   adapter does NOT classify it: it surfaces every verdict body + inline finding, and
#   the /review-loop model-judge decides clean/blocking/non-blocking (engine-claude.md
#   § Verdict judge). The regex classifier (CLEAN/FINDING patterns) was REMOVED — it
#   false-FINDING'd clean prose and false-CLEAN'd marker-less prose findings.
#
# A3 / LAYER-2 — RACE + SILENT GUARD (load-bearing). A `completed` run with NO readable
#   verdict (nothing posted) is held as STATUS=in_progress (RUNNING) so the
#   orchestrator's "DONE + zero findings = CLEAN" can't fire on it.
#   CONCLUSION is never consulted (claude concludes `success` regardless of findings).
#   The settle window (CLAUDE_REVIEW_SETTLE_SECONDS, default 180) only picks the marker:
#   within → CLAUDE_REVIEW_PENDING (comments may still land); elapsed → CLAUDE_REVIEW_SILENT
#   (didn't → NOT clean: #1087 / read-only perms / un-fixed workflow; re-trigger or verify,
#   never auto-clean). Settle age in Python `datetime` (cross-platform), never `date -d`.
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
# Output contract (engine-adapter-contract.md) — IDEA-022: this script SURFACES
# review material; it computes NO clean/findings verdict (that is the /review-loop
# model-judge's call, engine-claude.md § Verdict judge). Markers:
#   - CLAUDE_CHECKRUN=<run-id> COMMIT=<sha> STATUS=<queued|in_progress|completed> CONCLUSION=<...> AT=<iso8601> RUNS=<n> WINDOW_START=<iso8601>
#     (synthesized from the Actions runs; STATUS RUNNING vs DONE aggregated across all
#      head-SHA runs; CONCLUSION never a verdict)
#   - CLAUDE_VERDICT_SET_PROVEN=<true|false> (structural fail-closed: the judge may
#     return CLEAN only when the whole head-SHA verdict set was provably seen)
#   - CLAUDE_HEAD_VERDICTS=<n> CLAUDE_VERDICT_IDS=<id,...|none> (in-window verdict enumeration)
#   - CLAUDE_LATEST_REVIEW=<anchor-id> COMMIT=<sha> AT=<iso8601>
#     (anchor = summary-comment id, or newest head-SHA inline comment id if no summary;
#      NO CLEAN= token — the adapter computes no verdict)
#   - verdict-body MATERIAL blocks (every in-window summary body, verbatim) + inline
#     finding blocks, each carrying the mandatory `(comment id <cid>, review <rid|summary>)` token
#   - CLAUDE_NOT_INSTALLED=true (reachability) / CLAUDE_DRAFT_NOOP=true (draft PR — no
#     review posted; un-draft for a verdict) / CLAUDE_REVIEW_PENDING=... (race guard)
#   - CLAUDE_REVIEW_SILENT=... (run `success` but posted nothing after settle — NOT
#     clean; #1087 / read-only perms / un-fixed workflow. Held RUNNING, never judged.)
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

# ── Test seam (IDEA-022) ──────────────────────────────────────────────────────
# When CLAUDE_FIXTURE_DIR is set, read captured GitHub API payloads from files
# instead of calling `gh api`, so tests/test_claude_material_surfacing.sh runs
# deterministically offline. The production path (var unset) is unchanged — every
# fetch below falls through to its original `gh` call. Fixture files (all
# optional, each defaulting to its empty shape): workflows.json, pr.json
# ({"draft":bool,"head":{"sha":...}}), inline_comments.json, issue_comments.json,
# workflow_runs.json. Invoke tests with a numeric PR arg so PR resolution never
# calls `gh pr list`.
gh_payload() {
    # $1 = fixture filename, $2 = empty-shape default; remaining args = the `gh`
    # argv for the production fetch. Both paths default to $2 on any failure so
    # the python passes never receive empty stdin.
    local fname="$1" default="$2"; shift 2
    if [ -n "${CLAUDE_FIXTURE_DIR:-}" ]; then
        cat "$CLAUDE_FIXTURE_DIR/$fname" 2>/dev/null || printf '%s' "$default"
    else
        gh "$@" 2>/dev/null || printf '%s' "$default"
    fi
}

# Repo identifier
if [ -n "${CLAUDE_FIXTURE_DIR:-}" ]; then
    REPO_OWNER=testowner
    REPO_NAME=testrepo
else
    REPO_OWNER=$(gh repo view --json owner -q '.owner.login')
    REPO_NAME=$(gh repo view --json name -q '.name')
fi

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
WORKFLOWS=$(gh_payload workflows.json '{"workflows":[]}' api "repos/$REPO_OWNER/$REPO_NAME/actions/workflows?per_page=100")
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

# ── Draft-PR no-op guard (LAYER 0) ──────────────────────────────────────────
# On a DRAFT PR the action's run fires + concludes `success` but claude POSTS
# NOTHING (no summary, no inline) — confirmed A/B 2026-06-03: the same tree read
# SILENT while draft and posted a full review the instant it was marked ready. So a
# draft PR would otherwise read SILENT / false-clean-vector — NOT a code verdict, just
# the draft no-op. /review-loop's pre-flight un-drafts the PR before Phase 1 (see
# SKILL.md § Pre-flight); this is the belt-and-suspenders net for a skipped/failed
# un-draft: emit CLAUDE_DRAFT_NOOP + exit 0 so the loop reports "no claude verdict until
# ready" (un-draft the PR), never SILENT/HUNG/clean.
if [ -n "${CLAUDE_FIXTURE_DIR:-}" ]; then
    PR_IS_DRAFT=$(gh_payload pr.json '{}' api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('draft', False)).lower())" 2>/dev/null || echo "")
else
    PR_IS_DRAFT=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER" -q '.draft' 2>/dev/null || echo "")
fi
if [ "$PR_IS_DRAFT" = "true" ]; then
    echo "CLAUDE_DRAFT_NOOP=true"
    echo -e "${YELLOW}⚠️  PR #$PR_NUMBER is a DRAFT — claude's action runs but posts NO review on drafts (no summary, no inline). This is the draft no-op, NOT a clean or SILENT verdict.${NC}"
    echo "   Mark ready-for-review ('gh pr ready $PR_NUMBER') to get a real claude review; /review-loop's pre-flight normally does this automatically before Phase 1."
    exit 0
fi

echo "📋 Fetching claude review activity for PR #$PR_NUMBER..."
echo ""

# Head SHA — anchors both the Actions-run filter and the head-SHA-aware finding
# precheck. Degrade gracefully to empty if the fetch fails.
if [ -n "${CLAUDE_FIXTURE_DIR:-}" ]; then
    PR_HEAD_SHA=$(gh_payload pr.json '{}' api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER" | python3 -c "import json,sys; d=json.load(sys.stdin); print((d.get('head') or {}).get('sha',''))" 2>/dev/null || echo "")
else
    PR_HEAD_SHA=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER" -q '.head.sha' 2>/dev/null || echo "")
fi

# Fetch comment + run endpoints up-front (each defaults to []/empty-shape on
# failure so the python passes never receive empty stdin). per_page=100 avoids
# the default-30 cap dropping the most recent comment on a long-iteration PR.
INLINE_COMMENTS=$(gh_payload inline_comments.json '[]' api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER/comments?per_page=100")
ISSUE_COMMENTS=$(gh_payload issue_comments.json '[]' api "repos/$REPO_OWNER/$REPO_NAME/issues/$PR_NUMBER/comments?per_page=100")

# Actions runs for the claude-code-review workflow (A7/R2). If `actions: read`
# is unreadable for the user's gh auth we degrade to summary-comment-only state
# (lose the RUNNING signal) — Q3, resolved at dogfood. Empty-shape default keeps
# the python pass honest.
WORKFLOW_RUNS=$(gh_payload workflow_runs.json '{"workflow_runs":[]}' api "repos/$REPO_OWNER/$REPO_NAME/actions/workflows/$CLAUDE_WORKFLOW_FILE/runs?per_page=100")

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
# POSTING MODEL — the BARE (read-only / un-fixed) action posts only buffered inline
#   comments and NO summary, AND can drop even those (#1087). The PR-#167 dogfood run
#   logged "No buffered inline comments" and was READ as clean via the old zero-inline
#   arm — but that was only safe because the run genuinely had nothing AND we later
#   learned (LAYER 2) it could equally have been a silent #1087 drop. ⚠️ SUPERSEDED:
#   the zero-inline arm is NO LONGER a clean signal (see the A6/LAYER-2 header). The
#   FIXED workflow (assets/) forces a posted clean summary, so:
#     • CLEAN = a POSTED clean summary ("no issues found") + zero inline.
#     • success + nothing posted after settle = CLAUDE_REVIEW_SILENT (NOT clean).
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
# CLEAN SUBSTRING (A6) — now THE clean signal (LAYER 2): with the fixed workflow a
#   genuinely-clean run posts a summary containing it. Wording NOW CONFIRMED downstream
#   (see the SUMMARY CALIBRATION block below): the clean family is "no issues found" /
#   "no bugs found" — matched by CLAUDE_CLEAN_PATTERNS, not a single literal.
#
# STILL UNCALIBRATED (no finding observed yet — this run was clean):
#   • CLAUDE_BODY_SIGNATURES exact wording (only matters for the summary arm now).
#   • Whether inline findings share a pull_request_review_id (Q1) — anchor keys on
#     comment id either way, so safe; confirm when claude first posts a finding
#     (step 10 tri-engine on a rougher diff, or a deliberate probe).
# ==============================================================================
# Single source of truth — exported once, read by every python pass via env.
#
# ⚠️ IDEA-022 — the CLEAN / FINDING-MARKER bullets below describe the REMOVED regex
#    classifier; clean/blocking/non-blocking is now the model-judge's call. The LOGIN /
#    HEADING-SIGNATURE / NO-OP calibration here is STILL LIVE (it selects which comments
#    are claude's, feeding the material surfacer). Read the clean/marker bullets as
#    historical "what claude's prose looks like" — judge input, not regex to match.
#
# ── SUMMARY CALIBRATION — CONFIRMED on a downstream PR (2026-06-03, the first
#    high-volume findings-bearing claude review observed in the wild — 13 summary
#    bodies). This SUPERSEDES several PR-#167 guesses with real data; see
#    engine-claude.md § calibration update — findings live in the SUMMARY BODY. ──
#  • SUMMARY LOGIN = `claude[bot]` (NOT `github-actions[bot]` — that login is the
#    PR-size bot). The action posts its review SUMMARY as a `claude[bot]` ISSUE
#    comment; inline comments (when any) come via GITHUB_TOKEN as github-actions[bot].
#    Both logins stay in the set so either surface is recognized.
#  • SUMMARY HEADING = literal `## Code review`. The old signature `code-review`
#    (hyphen) did NOT match "Code review" (space) → claude's whole summary was
#    UNRECOGNIZED → its body findings were invisible (the C1 gap). Fixed: `code[ -]?review`.
#  • CLEAN IS WHOLE-REVIEW, NOT SUBSTRING-ANYWHERE. claude clears sections
#    independently: a review can say "Bugs: No issues found." in one section AND list
#    "Docstrings missing" / "violations" in another. A bare `'no issues found' in body`
#    test FALSE-CLEANS that mixed review. Clean now requires a positive clean phrase
#    AND the ABSENCE of any finding marker (CLAUDE_FINDING_MARKERS).
#  • CLEAN PHRASING VARIES — "No issues found." AND "No bugs found." both seen on the
#    genuinely-clean final verdict. Match the family, not one literal.
#  • NO-OP BODIES ("Skipped — draft", "Skipped — already posted review") match the
#    signature but are NOT verdicts. CLAUDE_NOOP_PATTERNS filters them out before
#    a verdict is read (else a draft/duplicate no-op masquerades as a real summary).
export CLAUDE_LOGINS='github-actions[bot] claude[bot] claude-code-action[bot]'
export CLAUDE_BODY_SIGNATURES='claude code review|generated by claude|reviewed by claude|code[ -]?review'
# ── IDEA-022: NO PROSE CLASSIFIER ────────────────────────────────────────────
# CLAUDE_CLEAN_PATTERNS / CLAUDE_FINDING_MARKERS / CLAUDE_CLEAN_SUBSTRING were
# REMOVED. Regex cannot reliably classify claude's model-generated prose — it
# false-FINDING'd on unrecognized clean phrasing (the IDEA-021 dogfood) and
# false-CLEAN'd on marker-less prose findings (the architect hole). The
# clean/blocking/non-blocking decision is now the /review-loop model-judge
# (engine-claude.md § Verdict judge). This script is reduced to SURFACING the
# review material the judge reads: RUNNING/DONE, the in-window verdict-body
# enumeration (verbatim, UNclassified), inline findings, and the structural
# CLAUDE_VERDICT_SET_PROVEN fail-closed gate. CLAUDE_NOOP_PATTERNS (below) and
# the SILENT/draft guards STAY — they are structural "did claude post a real
# review at all" gates that run BEFORE material ever reaches the judge.
#
# Signature-matching bodies that are claude NO-OPs, never verdicts. Anchored to the
# skip-preamble SHAPE — the "## Code review" heading immediately followed by skip prose —
# matched with re.MULTILINE so `^` is a line start. claude phrases the skip BOTH ways:
# past-tense "Skipped — draft status" / "Skipped: already reviewed this PR" (seen on an external project)
# AND gerund "Skipping review: already posted a code review comment" (mind-vault #169) —
# so the verb arm is `skipp(ed|ing)`. Anchoring (vs a bare search-anywhere) is deliberate:
# PR #169 self-dogfood flagged that a loose `already (posted|reviewed)` arm would
# false-no-op a REAL findings body whose prose merely says "already reviewed in PR #X but
# regressed" → findings silently dropped (the unsafe direction). The heading-anchored
# skip shape covers every observed no-op without that risk.
export CLAUDE_NOOP_PATTERNS='^##\s+code[ -]?review\s*\n+\s*skipp(ed|ing)'

# ------------------------------------------------------------------------------
# Pass 1 — Review-state from the Actions job (A7/R2): synthesize CLAUDE_CHECKRUN
# ------------------------------------------------------------------------------
# Filter runs to the head SHA. Metadata (id/AT) comes from the LATEST run by
# `run_started_at`, but STATUS aggregates across ALL head-SHA runs — completed
# only when every run completed (dual-verdict rule: auto-run + retrigger can both
# review one SHA; an in-flight earlier run must hold the engine RUNNING). The
# Actions conclusion is emitted for forensics ONLY — never a verdict (it is
# green with or without findings).
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
# Latest by run_started_at (A7 dedup of metadata). Fall back to created_at then id.
runs.sort(key=lambda r: (r.get('run_started_at') or r.get('created_at') or '', r.get('id') or 0), reverse=True)
latest = runs[0]
rid = latest.get('id') or ''
sha = latest.get('head_sha') or ''
conclusion = latest.get('conclusion') or ''
# Dual-verdict rule (engine-claude.md § dual substantive verdicts): the engine is
# DONE only when ALL head-SHA runs are completed — the skip-no-op is install-
# dependent, so a push auto-run AND an explicit retrigger can both run full
# reviews of one SHA. STATUS aggregates across runs: any queued/in_progress run
# holds the whole engine in that state, regardless of which run started latest.
incomplete = [r for r in runs if (r.get('status') or '') != 'completed']
status = (incomplete[0].get('status') or 'in_progress') if incomplete else 'completed'
# AT anchors the settle valve — prefer updated_at (when it completed) then run_started_at.
at = latest.get('updated_at') or latest.get('run_started_at') or latest.get('created_at') or ''
# WINDOW_START = earliest head-SHA run start: scopes the all-verdicts pass below
# to summaries posted for THIS SHA (issue comments carry no commit id).
# Empty timestamps are EXCLUDED from min() — one run with a blank
# run_started_at would otherwise poison the window to '' and silently
# disable Pass 2b (bugbot 3399604441).
starts = [s for s in ((r.get('run_started_at') or r.get('created_at') or '') for r in runs) if s]
window = min(starts) if starts else ''
print(f'CLAUDE_CHECKRUN={rid} COMMIT={sha} STATUS={status} CONCLUSION={conclusion} AT={at} RUNS={len(runs)} WINDOW_START={window}')
" 2>/dev/null || true)

# ------------------------------------------------------------------------------
# Pass 2 — claude-authored head-SHA inline comments + summary comment
# ------------------------------------------------------------------------------
# Identity (calibrated PR #167): INLINE = login-only (github-actions[bot]; the
# safe direction — see the CALIBRATED block above); SUMMARY = BOTH-AND (login AND
# body signature, so a stray github-actions[bot] "no issues" issue comment can't
# fake a claude summary). Inline findings are the staleness corpus + material; the
# summary comment is the newest-verdict anchor + presence signal. Emit (IDEA-022 —
# presence/anchor only; NO clean/findings classification):
#   - CLAUDE_HEAD_INLINE_COUNT  — # of claude inline comments ON the head SHA
#   - CLAUDE_SUMMARY_JSON / SUMMARY_ID — newest non-no-op summary (presence + anchor + body material)
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

# Summary comment (top-level issue comment) — the verdict surface (C1, calibrated
# downstream). claude posts its review as a `claude[bot]` issue comment headed
# `## Code review`; that body carries BOTH the clean signal AND any non-line-anchorable
# findings (CLAUDE.md convention violations, cross-file security notes). This pass:
#   1. selects the NEWEST non-no-op claude-authored summary (skips "Skipped — draft/
#      already posted" no-ops, which match the signature but aren't verdicts),
#   2. classifies it clean (positive phrase AND zero finding markers — whole-review,
#      not substring-anywhere) vs findings-bearing,
#   3. emits the selected comment's JSON (CLAUDE_SUMMARY_JSON) so a findings-bearing
#      body can be SURFACED as a finding downstream (the C1 fix — previously a
#      non-clean summary was silently dropped, making claude's convention review
#      invisible to the loop).
CLAUDE_SUMMARY_JSON=$(echo "$ISSUE_COMMENTS" | python3 -c "
import json, os, re, sys
try:
    comments = json.load(sys.stdin)
except Exception:
    sys.exit(0)
logins = set(os.environ.get('CLAUDE_LOGINS', '').split())
sig_re = re.compile(os.environ.get('CLAUDE_BODY_SIGNATURES', 'a^'), re.IGNORECASE)
noop_re = re.compile(os.environ.get('CLAUDE_NOOP_PATTERNS', 'a^'), re.IGNORECASE | re.MULTILINE)
def is_claude_summary(c):
    login = (c.get('user') or {}).get('login') or ''
    body = c.get('body') or ''
    # Signature AND login (BOTH-AND — a stray bot 'no issues' issue comment must not
    # fake a claude summary). No-op bodies (draft/already-posted skips) are excluded
    # so a no-op never masquerades as a verdict.
    return login in logins and bool(sig_re.search(body)) and not noop_re.search(body)
claude = [c for c in comments if is_claude_summary(c)]
if not claude:
    sys.exit(0)
# Newest verdict-bearing summary wins.
claude.sort(key=lambda c: c.get('created_at') or '', reverse=True)
print(json.dumps(claude[0]))
" 2>/dev/null || true)

# Presence + anchor of the NEWEST non-no-op summary. The adapter does NOT classify
# it clean/findings (IDEA-022 — that is the model-judge's call); this line is the
# staleness anchor + the RUNNING/DONE gate's "a verdict was posted" signal. The body
# itself is surfaced verbatim as material in the verdict-body render below.
CLAUDE_SUMMARY_LINE=$(echo "${CLAUDE_SUMMARY_JSON:-}" | python3 -c "
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    c = json.loads(raw)
except Exception:
    sys.exit(0)
cid = c.get('id') or ''
at = c.get('created_at') or ''
print(f'CLAUDE_SUMMARY_ID={cid} AT={at}')
" 2>/dev/null || true)

# Derive presence/anchor scalars (bash side; `|| true` on every grep -oE because
# empty captures would make grep exit 1 under -eo pipefail). No CLEAN/FINDINGS
# scalars — the adapter computes no verdict; SUMMARY_ID presence is the readable-
# verdict signal the settle gate keys on.
SUMMARY_ID=$(echo "$CLAUDE_SUMMARY_LINE" | grep -oE 'CLAUDE_SUMMARY_ID=[^ ]+' | cut -d= -f2 || true)
SUMMARY_AT=$(echo "$CLAUDE_SUMMARY_LINE" | grep -oE 'AT=[^ ]+' | cut -d= -f2 || true)

# ------------------------------------------------------------------------------
# Pass 2b — ENUMERATE every head-SHA verdict body as raw material (IDEA-022). The
# dual-verdict rule (engine-claude.md § dual substantive verdicts) is now applied by
# the model-judge, NOT by regex here: the adapter surfaces EVERY substantive non-no-op
# summary inside the head-SHA window (created_at >= earliest head-SHA run start —
# issue comments carry no commit id, so the run window is the SHA scope) verbatim, so
# the judge sees a masked earlier verdict alongside any newer clean roll and applies
# the masking rule itself. The adapter classifies NONE of them. Emits:
#   CLAUDE_HEAD_VERDICTS=<n> — substantive summaries in the window
#   CLAUDE_VERDICT_IDS=<id,id,...|none> — their comment ids (oldest-first)
#   + a second JSON line = the full verdict objects, for the verbatim material render.
# No window (runs fetch failed / blank timestamps) → pass emits nothing → the
# verdict set is UNPROVEN (CLAUDE_VERDICT_SET_PROVEN=false below), which structurally
# forbids the judge returning CLEAN (it can't rule out a masked earlier verdict).
WINDOW_START=$(echo "${CLAUDE_CHECKRUN_LINE:-}" | grep -oE 'WINDOW_START=[^ ]+' | cut -d= -f2 || true)
CLAUDE_VERDICTS_OUT=$(echo "$ISSUE_COMMENTS" | WINDOW_START="$WINDOW_START" python3 -c "
import json, os, re, sys
window = os.environ.get('WINDOW_START', '')
if not window:
    sys.exit(0)
try:
    comments = json.load(sys.stdin)
except Exception:
    sys.exit(0)
logins = set(os.environ.get('CLAUDE_LOGINS', '').split())
sig_re = re.compile(os.environ.get('CLAUDE_BODY_SIGNATURES', 'a^'), re.IGNORECASE)
noop_re = re.compile(os.environ.get('CLAUDE_NOOP_PATTERNS', 'a^'), re.IGNORECASE | re.MULTILINE)
def in_window(c):
    # ISO-8601 UTC Z strings compare lexicographically.
    return (c.get('created_at') or '') >= window
def is_claude_summary(c):
    login = (c.get('user') or {}).get('login') or ''
    body = c.get('body') or ''
    return login in logins and bool(sig_re.search(body)) and not noop_re.search(body)
verdicts = [c for c in comments if is_claude_summary(c) and in_window(c)]
# Oldest-first so the material render reads chronologically (earlier verdict before
# a newer clean one — the judge applies the masking rule over the whole sequence).
verdicts.sort(key=lambda c: c.get('created_at') or '')
ids = ','.join(str(c.get('id') or '') for c in verdicts) if verdicts else 'none'
print(f'CLAUDE_HEAD_VERDICTS={len(verdicts)} CLAUDE_VERDICT_IDS={ids}')
if verdicts:
    print(json.dumps(verdicts))
" 2>/dev/null || true)
CLAUDE_VERDICTS_LINE=$(printf '%s\n' "${CLAUDE_VERDICTS_OUT:-}" | grep '^CLAUDE_HEAD_VERDICTS=' || true)
CLAUDE_VERDICTS_JSON=$(printf '%s\n' "${CLAUDE_VERDICTS_OUT:-}" | grep '^\[' || true)
CLAUDE_HEAD_VERDICTS_N=$(echo "${CLAUDE_VERDICTS_LINE:-}" | grep -oE 'CLAUDE_HEAD_VERDICTS=[^ ]+' | cut -d= -f2 || true)
# Fail-closed verdict-set proof (structural, kept from the dual-verdict work): the
# judge may return CLEAN only when Pass 2b actually ran AND counted >= 1 in-window
# verdict. No window / empty verdict set = the adapter CANNOT prove it saw the whole
# head-SHA verdict set (paginated-out / blank run timestamps) — so the judge is
# forbidden CLEAN (engine-claude.md § Verdict judge, proven-set fail-closed).
# (bugbot 3399604441: blank timestamps → WINDOW_START='' → pass skipped → UNPROVEN.
# Run-list gaps are NOT defended here — same-SHA runs are expected to co-appear in the
# API response for a fresh push; a paginated-out earlier run would narrow the window
# undetected.)
CLAUDE_VERDICT_SET_PROVEN=false
if [ -n "${CLAUDE_VERDICTS_LINE:-}" ] && [ "${CLAUDE_HEAD_VERDICTS_N:-0}" -ge 1 ] 2>/dev/null; then
    CLAUDE_VERDICT_SET_PROVEN=true
fi

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

# Is there a READABLE VERDICT for the head SHA? (LAYER 2 — action issue #1087.)
# A claude run can report `success` having posted NOTHING: the plugin buffers inline
# comments for a post-session step whose result-capture can grab a TodoWrite response
# instead of the review → empty → no comment, run still `success`. That "success +
# silent" state is INDISTINGUISHABLE from a genuinely-clean run by run status alone, so
# we must NOT release a no-verdict run to DONE — it would let the orchestrator read a
# #1087-dropped run as the absence of findings. A verdict is readable ONLY when claude
# POSTED material the judge can read (IDEA-022 — the adapter no longer classifies it):
#   - inline findings (HEAD_INLINE_COUNT > 0), OR
#   - a posted non-no-op summary comment (SUMMARY_ID non-empty).
# Either is "material exists for the judge" — window-independent (so an unprovable
# verdict set still counts as readable; the proven-set gate handles its safety, not the
# settle valve). Anything else — nothing posted at all — is SILENT/uncertain: held
# RUNNING, surfaced, NEVER auto-cleaned, and never handed to the judge (nothing to read).
VERDICT_READABLE=false
if [ "$HEAD_INLINE_COUNT" -gt 0 ] 2>/dev/null || [ -n "${SUMMARY_ID:-}" ]; then
    VERDICT_READABLE=true
fi

# ------------------------------------------------------------------------------
# Review-state gate + race guard (A3) + LAYER-2 silent guard — load-bearing
# ------------------------------------------------------------------------------
if [ -n "$CLAUDE_CHECKRUN_LINE" ]; then
    cr_status=$(echo "$CLAUDE_CHECKRUN_LINE" | grep -oE 'STATUS=[^ ]+' | cut -d= -f2 || true)
    cr_id=$(echo "$CLAUDE_CHECKRUN_LINE" | grep -oE 'CLAUDE_CHECKRUN=[^ ]+' | cut -d= -f2 || true)
    cr_sha=$(echo "$CLAUDE_CHECKRUN_LINE" | grep -oE 'COMMIT=[^ ]+' | cut -d= -f2 || true)
    cr_at=$(echo "$CLAUDE_CHECKRUN_LINE" | grep -oE 'AT=[^ ]+' | cut -d= -f2 || true)

    # ── Race guard (A3) + LAYER-2 silent guard ──────────────────────────────────
    # A `completed` run with NO readable verdict is held as RUNNING (downgraded) so
    # the orchestrator's generic "DONE + zero findings = CLEAN" cannot fire on a run
    # that merely hasn't posted yet (race) OR never will (#1087 drop). The settle
    # window distinguishes the two:
    #   - within window  → CLAUDE_REVIEW_PENDING  (comments may still be landing)
    #   - window elapsed → CLAUDE_REVIEW_SILENT    (nothing came → NOT clean: #1087 /
    #                       read-only perms / un-fixed workflow). Stays RUNNING so the
    #                       loop never reads CLEAN; the loop hands SILENT back as
    #                       uncertain (re-trigger / verify perms), not as clean — see
    #                       engine-claude.md § Failure modes.
    # CONCLUSION is never consulted (claude concludes `success` regardless of findings).
    #
    # Default 180s (calibrated PR #167, NOT copilot's 600). claude-code-action posts
    # its inline comments *synchronously within the job* (the post step runs BEFORE
    # the run reports `completed`), so comments — if any — already exist at
    # completed-time; the window only covers GitHub API read-consistency after that
    # in-job post, not copilot's minutes-long async-review lag. Settle age computed in
    # Python `datetime` (cross-platform), never `date -d`.
    SETTLE=${CLAUDE_REVIEW_SETTLE_SECONDS:-180}
    CLAUDE_PENDING= ; CLAUDE_SILENT=
    if [ "$cr_status" = "completed" ] && [ "$VERDICT_READABLE" != "true" ]; then
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
        # NO conclusion gate (claude concludes `success` regardless of findings).
        # ALWAYS hold as RUNNING — a run with no readable verdict must never reach
        # DONE, else the orchestrator's "DONE + zero findings = CLEAN" false-cleans
        # an unposted / #1087-dropped run. The settle window only chooses the marker:
        # within → PENDING (comments may still land); elapsed → SILENT (didn't come →
        # NOT clean; needs re-trigger / perms-verify, never auto-clean).
        cr_status="in_progress"
        CLAUDE_CHECKRUN_LINE=$(echo "$CLAUDE_CHECKRUN_LINE" | sed 's/STATUS=completed/STATUS=in_progress/')
        if [ "$settle_state" = "elapsed" ]; then CLAUDE_SILENT=1; else CLAUDE_PENDING=1; fi
    fi

    echo "$CLAUDE_CHECKRUN_LINE"

    # CLAUDE_VERDICT_SET_PROVEN — structural fail-closed gate the model-judge reads
    # (engine-claude.md § Verdict judge): the judge may return CLEAN only when the
    # whole head-SHA verdict set was provably seen. Emitted whenever a checkrun exists,
    # for BOTH the proven (true) and unprovable (false) paths.
    echo "CLAUDE_VERDICT_SET_PROVEN=${CLAUDE_VERDICT_SET_PROVEN}"
    if [ "$cr_status" = "completed" ]; then
        # Reached ONLY with a readable verdict (inline findings and/or a posted
        # summary) — no-verdict cases are held as RUNNING (PENDING/SILENT). The
        # adapter emits NO clean/findings verdict (IDEA-022): every head-SHA inline
        # finding + every in-window summary body is surfaced verbatim below as the
        # material the /review-loop model-judge classifies (engine-claude.md
        # § Verdict judge → {CLEAN | BLOCKING | NON_BLOCKING[]}).
        echo -e "${GREEN}✅ Claude Actions run completed with posted material for PR head — verdict is the /review-loop judge's call (see surfaced material below).${NC}"
        if [ "$CLAUDE_VERDICT_SET_PROVEN" != "true" ] && [ "$HEAD_INLINE_COUNT" -eq 0 ] 2>/dev/null; then
            # Summary present but the head-SHA verdict set is UNPROVEN (no run window /
            # blank run timestamps): the judge is forbidden CLEAN here (fail-closed),
            # because a masked earlier verdict can't be ruled out. Surfaced, not cleaned.
            echo -e "${YELLOW}⚠️  Head-SHA verdict set UNPROVEN (${CLAUDE_VERDICTS_LINE:-no run window}) — judge MUST NOT return CLEAN (fail-closed). Verify the Actions run list for the head SHA.${NC}"
        fi
    elif [ -n "$CLAUDE_SILENT" ]; then
        echo "CLAUDE_REVIEW_SILENT=run-${cr_id} COMMIT=${cr_sha} SETTLE=${SETTLE}s"
        echo -e "${RED}⚠️  Claude Actions run completed but posted NO findings and NO clean summary after ${SETTLE}s — SILENT/uncertain, NOT clean (likely anthropics/claude-code-action#1087 buffer-drop, read-only perms, or an un-fixed workflow). Re-trigger or verify the workflow has the reliability fixes + pull-requests:write. See engine-claude.md § Failure modes.${NC}"
    elif [ -n "$CLAUDE_PENDING" ]; then
        echo "CLAUDE_REVIEW_PENDING=run-${cr_id} COMMIT=${cr_sha} SETTLE=${SETTLE}s"
        echo -e "${YELLOW}⏳ Claude Actions run completed but no head-SHA verdict posted yet (within ${SETTLE}s settle) — treating as RUNNING (race guard) to avoid a false CLEAN.${NC}"
    fi
    echo ""
fi

# ------------------------------------------------------------------------------
# CLAUDE_LATEST_REVIEW — staleness anchor (comment-anchored; A4 synthesized id)
# ------------------------------------------------------------------------------
# Anchor = summary-comment id if present, else newest head-SHA inline comment id
# (Q1: inline comments may share a pull_request_review_id; we anchor on comment id
# either way). Mandatory when ANY claude activity exists so the orchestrator's
# staleness rule has a reference. NO CLEAN= token (IDEA-022 — the adapter computes
# no verdict; the staleness anchor carries the id/at only, the judge reads the body).
LATEST_ANCHOR_ID="$SUMMARY_ID"
LATEST_ANCHOR_AT="$SUMMARY_AT"
if [ -z "$LATEST_ANCHOR_ID" ]; then
    LATEST_ANCHOR_ID="$INLINE_ANCHOR_ID"
    LATEST_ANCHOR_AT="$INLINE_ANCHOR_AT"
fi
if [ -n "$LATEST_ANCHOR_ID" ]; then
    echo "CLAUDE_LATEST_REVIEW=${LATEST_ANCHOR_ID} COMMIT=${PR_HEAD_SHA} AT=${LATEST_ANCHOR_AT}"
    # In-window verdict enumeration (Pass 2b): the count + ids of every substantive
    # head-SHA verdict, so the judge applies the masking rule over the whole set (not
    # just the anchor). The verdict BODIES are surfaced verbatim as material below.
    if [ -n "${CLAUDE_VERDICTS_LINE:-}" ]; then
        echo "$CLAUDE_VERDICTS_LINE"
    fi
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
# Verdict-body MATERIAL (IDEA-022) — surface EVERY in-window head-SHA summary body
# VERBATIM, unclassified. claude posts convention / cross-file findings it can't
# line-anchor in the `## Code review` summary BODY, AND posts clean recaps, AND
# (install-dependent) can post two disagreeing verdicts on one SHA. The adapter no
# longer decides which is a finding — it hands ALL of them to the /review-loop
# model-judge, which applies the masking rule and emits {CLEAN|BLOCKING|NON_BLOCKING[]}
# (engine-claude.md § Verdict judge). Each block carries the mandatory contract token
#   (comment id <cid>, review summary)
# so the orchestrator's staleness filter matches it against CLAUDE_LATEST_REVIEW.
# Oldest-first (Pass 2b sort) so the judge reads the verdict sequence chronologically.
# ------------------------------------------------------------------------------
# Fall back to the newest non-no-op summary (window-independent) when the in-window
# enumeration is empty — i.e. the verdict set is UNPROVEN (no run window). The judge
# still needs the body to assess BLOCKING; the proven-set gate independently forbids
# CLEAN, so surfacing the body here is safe and strictly more informative.
CLAUDE_MATERIAL_JSON="${CLAUDE_VERDICTS_JSON:-}"
if [ -z "$CLAUDE_MATERIAL_JSON" ] && [ -n "${CLAUDE_SUMMARY_JSON:-}" ]; then
    CLAUDE_MATERIAL_JSON=$(printf '%s' "$CLAUDE_SUMMARY_JSON" | python3 -c "import json,sys; print(json.dumps([json.load(sys.stdin)]))" 2>/dev/null || true)
fi
if [ -n "${CLAUDE_MATERIAL_JSON:-}" ]; then
    echo -e "${BLUE}📝 Claude review material — ${CLAUDE_HEAD_VERDICTS_N:-1} head-SHA summary verdict(s), verbatim for the /review-loop judge (UNclassified — clean/blocking/non-blocking is the judge's call):${NC}"
    echo ""
    echo "$CLAUDE_MATERIAL_JSON" | python3 -c "
import json, re, sys
try:
    verdicts = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
n = len(verdicts)
for i, c in enumerate(verdicts, 1):
    body = c.get('body', '') or ''
    cid = c.get('id', '')
    url = c.get('html_url', '')
    at = c.get('created_at', '') or ''
    # Title = first non-'Code review' heading, else first heading, else a default.
    # Render-only convenience; NOT a classification. (No double quotes in this -c
    # block — they break the bash-wrapped python.)
    headings = re.findall(r'^#{1,6}\s+(.+)$', body, re.MULTILINE)
    finding_headings = [h.strip() for h in headings if not re.match(r'code[ -]?review\b', h.strip(), re.I)]
    title = (finding_headings or [h.strip() for h in headings] or ['Claude review summary'])[0]
    separator = '━' * 80
    print(f'\033[0;34m{separator}\033[0m')
    # Mandatory contract token — verbatim '(comment id <cid>, review summary)'.
    print(f'\033[0;34m[verdict {i}/{n}] (comment id {cid}, review summary) @ {at}\033[0m')
    print('\033[0;34m**File:**\033[0m (summary body — not line-anchored)')
    print(f'\033[0;34m**Title:**\033[0m {title}')
    print('\033[0;34m**Body (verbatim — judge reads this):**\033[0m')
    print(body.strip())
    print('')
    print(f'\033[0;34m**Link:**\033[0m {url}')
    print('')
"
fi

# ------------------------------------------------------------------------------
# Summary comment surface (top-level) — informational, by id. NO verdict banner:
# clean/blocking/non-blocking is the judge's call (IDEA-022), not the adapter's.
# ------------------------------------------------------------------------------
if [ -n "$CLAUDE_SUMMARY_LINE" ]; then
    echo "$CLAUDE_SUMMARY_LINE"
    echo -e "${BLUE}💬 Claude summary comment present (id $SUMMARY_ID) — body surfaced above as material; verdict is the /review-loop judge's call.${NC}"
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
