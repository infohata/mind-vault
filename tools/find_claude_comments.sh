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
# A6 / LAYER-2 — CLEAN REQUIRES A POSITIVE POSTED SIGNAL, never zero-inline alone.
#   A claude run can report `success` having posted NOTHING (action issue #1087 — the
#   buffered-comment result-capture grabs a TodoWrite response instead of the review),
#   which is indistinguishable from a genuinely-clean run by run status. So "completed
#   + zero inline" is a FALSE-CLEAN vector, NOT a clean signal. clean iff claude POSTED
#   a clean summary (case-insensitive substring "no issues found"; substring not full
#   sentence per the copilot two-phrasing lesson, find_copilot_comments.sh:182-189)
#   AND zero inline findings. The fixed workflow (assets/claude-code-review.yml —
#   classify_inline_comments:false + claude_args + a prompt forcing a posted summary
#   even when clean) is what makes a genuinely-clean run POST that summary.
#
# A3 / LAYER-2 — RACE + SILENT GUARD (load-bearing). A `completed` run with NO readable
#   verdict (no posted findings AND no clean summary) is held as STATUS=in_progress
#   (RUNNING) so the orchestrator's "DONE + zero findings = CLEAN" can't fire on it.
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
# Output contract (engine-adapter-contract.md):
#   - CLAUDE_CHECKRUN=<run-id> COMMIT=<sha> STATUS=<queued|in_progress|completed> CONCLUSION=<...> AT=<iso8601>
#     (synthesized from the Actions run; STATUS RUNNING vs DONE; CONCLUSION never a verdict)
#   - CLAUDE_LATEST_REVIEW=<anchor-id> COMMIT=<sha> AT=<iso8601> [CLEAN=<bool>]
#     (anchor = summary-comment id, or newest head-SHA inline comment id if no summary)
#   - CLAUDE_CLEAN_SIGNAL=... (legacy / non-authoritative — orchestrator derives clean structurally)
#   - inline finding blocks each carrying the mandatory `(comment id <cid>, review <rid>)` token
#   - CLAUDE_NOT_INSTALLED=true (reachability) / CLAUDE_DRAFT_NOOP=true (draft PR — no
#     review posted; un-draft for a verdict) / CLAUDE_REVIEW_PENDING=... (race guard)
#   - CLAUDE_REVIEW_SILENT=... (run `success` but posted nothing after settle — NOT
#     clean; #1087 / read-only perms / un-fixed workflow. Loop hands back as uncertain.)
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

# ── Draft-PR no-op guard (LAYER 0) ──────────────────────────────────────────
# On a DRAFT PR the action's run fires + concludes `success` but claude POSTS
# NOTHING (no summary, no inline) — confirmed A/B 2026-06-03: the same tree read
# SILENT while draft and posted a full review the instant it was marked ready. So a
# draft PR would otherwise read SILENT / false-clean-vector — NOT a code verdict, just
# the draft no-op. /review-loop's pre-flight un-drafts the PR before Phase 1 (see
# SKILL.md § Pre-flight); this is the belt-and-suspenders net for a skipped/failed
# un-draft: emit CLAUDE_DRAFT_NOOP + exit 0 so the loop reports "no claude verdict until
# ready" (un-draft the PR), never SILENT/HUNG/clean.
PR_IS_DRAFT=$(gh api "repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER" -q '.draft' 2>/dev/null || echo "")
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
# Clean = a POSITIVE clean phrase (CLAUDE_CLEAN_PATTERNS) AND zero finding markers
# (CLAUDE_FINDING_MARKERS). Both calibrated downstream. CLAUDE_CLEAN_SUBSTRING kept
# as a legacy alias (first pattern) for any external reader; the pass uses the family.
export CLAUDE_CLEAN_SUBSTRING='no issues found'
export CLAUDE_CLEAN_PATTERNS='no issues found|no bugs found|no problems found|no security issues'
# Finding markers — narrowed role. The SURFACE decision is now catch-everything
# (posted ∧ ¬provably-clean → findings; see the classify pass), so markers are NO LONGER
# the sole findings signal. They do two narrower jobs: (1) the MIXED-review guard — a body
# with a clean phrase ("Bugs: no issues found") AND a finding marker ("Docstrings missing")
# is NOT clean; (2) severity in the render. They're STRUCTURAL, not security-keyword-prose
# (a clean review NAMES the concepts it checked — "the privilege-escalation guard looks
# correct" — so privilege/escalation/security would false-positive on clean prose):
#   • numbered/sectioned headers `#### ` / `### [0-9]`; file-grouped header `### ` + backtick
#     (clean section headers are `### Bugs` / `### Security`, NO backtick);
#   • the count line `<N> issue(s)/bug(s)/… found` with a NON-"no" quantifier ("One issue
#     found.") — the clean phrase "No … found" is in CLAUDE_CLEAN_PATTERNS, no collision;
#   • report-list words `missing` / `violation` / ❌.
# Because the surface default is now "not-provably-clean → surface", a marker MISSING on a
# findings body no longer false-cleans it (it's surfaced anyway) — markers can only fail
# in the SAFE direction now. (Format is non-deterministic — PR #169 posted "One issue
# found." + "### `file`", downstream posted "#### 1." numbered; the catch-everything
# default is what makes an unseen 3rd format safe.)
export CLAUDE_FINDING_MARKERS='missing|violation|❌|#### |### [0-9]|### `|[0-9]+ (issue|bug|problem|finding)s? found|(one|two|three|four|five|six|seven|eight|nine|ten) (issue|bug|problem|finding)s? found'
# Signature-matching bodies that are claude NO-OPs, never verdicts. Anchored to the
# skip-preamble SHAPE — the "## Code review" heading immediately followed by "Skipped …"
# — matched with re.MULTILINE so `^` is a line start. This catches the observed variants
# ("Skipped — draft status", "Skipped: already reviewed this PR") WITHOUT a bare
# search-anywhere arm: PR #169 self-dogfood flagged that the old loose `already (posted|
# reviewed)` arm would false-no-op a REAL findings body whose prose merely says "already
# reviewed in PR #X but regressed" → findings silently dropped (the unsafe direction).
# The heading-anchored "Skipped" shape covers every real no-op; the loose arm is gone.
export CLAUDE_NOOP_PATTERNS='^##\s+code[ -]?review\s*\n+\s*skipped'

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

# Classify the selected summary in one pass: PROVABLY-clean (positive clean phrase AND
# no finding marker) vs surface-as-findings (everything else posted — catch-everything,
# marker-independent; see the has_findings note below). Single source of truth.
CLAUDE_SUMMARY_LINE=$(echo "${CLAUDE_SUMMARY_JSON:-}" | python3 -c "
import json, os, re, sys
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    c = json.loads(raw)
except Exception:
    sys.exit(0)
cid = c.get('id') or ''
at = c.get('created_at') or ''
body = c.get('body') or ''
clean_re = re.compile(os.environ.get('CLAUDE_CLEAN_PATTERNS', 'a^'), re.IGNORECASE)
finding_re = re.compile(os.environ.get('CLAUDE_FINDING_MARKERS', 'a^'), re.IGNORECASE)
has_clean_phrase = bool(clean_re.search(body))
has_finding_marker = bool(finding_re.search(body))
# WHOLE-REVIEW clean: a positive clean phrase AND no finding marker anywhere.
# Mixed reviews (one section clean, another flags 'missing'/'violation') → NOT clean.
is_clean = has_clean_phrase and not has_finding_marker
# CATCH-EVERYTHING surface decision (marker-INDEPENDENT): claude review format is NOT
# deterministic -- count-line + backtick-file-header here, numbered hash sections
# downstream, future runs may differ again. So findings is NOT matched-a-known-marker;
# it is posted-AND-not-provably-clean. A posted non-no-op summary is therefore ALWAYS
# either clean (provably) or surfaced-as-findings; an unrecognized future finding shape
# can never read SILENT (the unsafe direction). Markers now only gate is_clean (the
# mixed-review guard) and drive severity below. (NOTE: keep this -c block free of double
# quotes -- it runs inside a bash double-quoted python -c string.)
has_findings = not is_clean
print(f'CLAUDE_SUMMARY_ID={cid} AT={at} CLEAN={str(is_clean).lower()} FINDINGS={str(has_findings).lower()}')
" 2>/dev/null || true)

# Derive presence/clean/anchor scalars from the two passes (bash side; `|| true`
# on every grep -oE because empty captures would make grep exit 1 under -eo pipefail).
SUMMARY_ID=$(echo "$CLAUDE_SUMMARY_LINE" | grep -oE 'CLAUDE_SUMMARY_ID=[^ ]+' | cut -d= -f2 || true)
SUMMARY_AT=$(echo "$CLAUDE_SUMMARY_LINE" | grep -oE 'AT=[^ ]+' | cut -d= -f2 || true)
SUMMARY_CLEAN=$(echo "$CLAUDE_SUMMARY_LINE" | grep -oE 'CLEAN=[^ ]+' | cut -d= -f2 || true)
SUMMARY_FINDINGS=$(echo "$CLAUDE_SUMMARY_LINE" | grep -oE 'FINDINGS=[^ ]+' | cut -d= -f2 || true)

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
# silent" state is INDISTINGUISHABLE from a genuinely-clean run by run status alone,
# so we must NOT infer clean from "completed + zero inline" — that is the false-CLEAN
# vector. A verdict is readable ONLY when claude POSTED something definitive:
#   - inline findings (HEAD_INLINE_COUNT > 0)        → not clean; triage them
#   - a clean summary comment (SUMMARY_CLEAN==true)  → clean (the fixed workflow's
#                                                       prompt forces a posted "no
#                                                       issues found" summary even
#                                                       when clean — see assets/)
# A readable verdict is anything claude POSTED definitively:
#   - inline findings (HEAD_INLINE_COUNT > 0)        → not clean; triage them
#   - a findings-bearing summary (SUMMARY_FINDINGS)  → not clean; triage the body (C1 —
#                                                       convention/cross-file findings
#                                                       claude can't line-anchor)
#   - a clean summary comment (SUMMARY_CLEAN==true)  → clean
# Anything else — nothing posted, or a summary that isn't a recognized clean OR findings
# signal, with zero inline — is SILENT/uncertain: surfaced, NEVER auto-cleaned. (With the
# fixed workflow a genuinely-clean run POSTS a clean summary, so SILENT means
# #1087-drop / read-only perms / un-fixed workflow, not "clean".)
VERDICT_READABLE=false
if [ "$HEAD_INLINE_COUNT" -gt 0 ] 2>/dev/null || [ "$SUMMARY_CLEAN" = "true" ] || [ "$SUMMARY_FINDINGS" = "true" ]; then
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

    if [ "$cr_status" = "completed" ]; then
        # Reached ONLY with a readable verdict (inline findings, a findings-bearing
        # summary, or a clean summary) — no-verdict cases held as RUNNING (PENDING/SILENT).
        echo -e "${GREEN}✅ Claude Actions run completed with a posted verdict for PR head.${NC}"
        if [ "$HEAD_INLINE_COUNT" -gt 0 ] 2>/dev/null || [ "$SUMMARY_FINDINGS" = "true" ]; then
            : # findings present (inline and/or summary body) — rendered below; emit NO clean signal
        elif [ "$SUMMARY_CLEAN" = "true" ]; then
            # Posted clean summary ("no issues found") + zero inline → clean.
            # (LAYER 2: clean now requires a POSITIVE posted signal — never zero-inline alone.)
            echo "CLAUDE_CLEAN_SIGNAL=${SUMMARY_ID:-checkrun-${cr_id}} COMMIT=${cr_sha} AT=${SUMMARY_AT:-$cr_at}"
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
# staleness rule has a reference. CLEAN= is legacy/ignored by the orchestrator.
LATEST_ANCHOR_ID="$SUMMARY_ID"
LATEST_ANCHOR_AT="$SUMMARY_AT"
LATEST_CLEAN="$SUMMARY_CLEAN"
if [ -z "$LATEST_ANCHOR_ID" ]; then
    LATEST_ANCHOR_ID="$INLINE_ANCHOR_ID"
    LATEST_ANCHOR_AT="$INLINE_ANCHOR_AT"
    # No summary comment → no positive clean signal. LAYER 2: zero-inline is NOT
    # clean (could be a #1087 silent drop), so the legacy CLEAN= hint is false here
    # absent a posted clean summary. (The orchestrator ignores CLEAN= anyway — clean
    # is structural; this just stops the hint from lying.)
    LATEST_CLEAN=false
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
# Summary-body findings (C1) — claude posts convention / cross-file findings it
# can't line-anchor in the `## Code review` summary BODY, not as inline comments.
# Surface that body as a finding so the loop triages it (previously dropped → claude's
# convention review was invisible). Carries the mandatory contract token
#   (comment id <cid>, review summary)
# — `summary` is the synthetic review id for a body-anchored finding; the orchestrator's
# staleness filter matches it against CLAUDE_LATEST_REVIEW (which anchors on this same id).
# ------------------------------------------------------------------------------
if [ "$SUMMARY_FINDINGS" = "true" ] && [ -n "$CLAUDE_SUMMARY_JSON" ]; then
    echo -e "${RED}🐛 Claude summary-body finding(s) — review report posted as an issue comment (no inline anchor):${NC}"
    echo ""
    echo "$CLAUDE_SUMMARY_JSON" | python3 -c "
import json, re, sys
try:
    c = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
body = c.get('body', '') or ''
cid = c.get('id', '')
url = c.get('html_url', '')
# Severity heuristic mirrors the inline render (UNCONFIRMED stamp; common spellings).
# Bias HIGH when the body names a security failure mode; the loop re-triages anyway.
b = body.lower()
if 'critical' in b:
    severity, color = 'CRITICAL', '\033[0;31m'
elif 'privilege' in b or 'escalation' in b or '❌' in body:
    severity, color = 'HIGH', '\033[0;31m'
elif 'violation' in b or 'missing' in b or '⚠️' in body:
    severity, color = 'MEDIUM', '\033[1;33m'
else:
    severity, color = 'INFO', ''
m = re.search(r'^#{1,6}\s+(.+)$', body, re.MULTILINE)
title = m.group(1).strip() if m else 'Claude summary review'
separator = '━' * 80
print(f'{color}{separator}\033[0m')
# Mandatory contract token — verbatim '(comment id <cid>, review summary)'.
print(f'{color}Severity: {severity} (comment id {cid}, review summary)\033[0m')
print('\033[0;34m**File:**\033[0m (summary body — not line-anchored)')
print(f'\033[0;34m**Title:**\033[0m {title}')
print('\033[0;34m**Description:**\033[0m')
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
        echo -e "${GREEN}✅ Claude summary comment is whole-review clean (positive phrase, no finding markers).${NC}"
    elif [ "$SUMMARY_FINDINGS" = "true" ]; then
        echo -e "${YELLOW}💬 Claude summary comment carries findings (id $SUMMARY_ID) — rendered above.${NC}"
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
