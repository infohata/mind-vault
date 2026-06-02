# engine-claude — Claude Code Review adapter (action + `code-review` plugin)

Adapter specification for the Claude review engine. The orchestrator at [`SKILL.md`](../SKILL.md) drives this engine via the tool surface; the reference surface (this file) documents quirks the agent needs when triaging findings.

## ⚠️ READ THIS FIRST — the action + `code-review` plugin is NOT the managed Claude Code Review App

This engine drives `anthropics/claude-code-action@v1` running the **`code-review` plugin** via a self-hosted `.github/workflows/claude-code-review.yml` workflow (OAuth/subscription-billed). It is **NOT** Anthropic's managed *Claude Code Review* GitHub App.

| Surface | Managed App (we do NOT use) | Action + `code-review` plugin (what we drive) |
| --- | --- | --- |
| Named check-run | ✅ `Claude Code Review` check-run | ❌ none — only the GitHub **Actions job** status |
| Machine-readable verdict | ✅ severity JSON | ❌ findings are plain inline + summary comments |
| Clean signal | severity JSON empty | summary-comment body substring OR zero head-SHA inline comments |

✅ **DO** read review-state off the **Actions job** of the `claude-code-review` workflow run, and clean off comment structure.

❌ **DON'T** look for a `Claude Code Review` check-run or severity JSON — anything you read at `code.claude.com/docs` describing those describes the *managed App* and **does not apply here**. There is no named check-run to poll; polling for one returns nothing and the loop hangs to HUNG.

## § Identity

- Vendor: Anthropic — `anthropics/claude-code-action@v1` running the `code-review` plugin.
- Install path: **do NOT rely on `/install-github-app`'s default template — it ships `pull-requests: read` / `issues: read`, which silently blocks the action from POSTING findings** (a findings-bearing run posts nothing → `find_claude_comments.sh` reads a FALSE CLEAN via the zero-inline arm). Onboard by committing **our own write-perm templates** ([`../assets/claude-code-review.yml`](../assets/claude-code-review.yml) + [`../assets/claude.yml`](../assets/claude.yml)) to the **default branch**, porting `find_claude_comments.sh` + `claude_retrigger.sh` into `tools/`, and wiring `CLAUDE_CODE_OAUTH_TOKEN`. Full procedure + the anti-tampering bootstrap catch-22 (why the perms change can only take effect from the default branch): [`engine-claude-onboarding.md`](engine-claude-onboarding.md). The drop-the-two-workflows part of `/install-github-app` is fine as a starting point — but immediately replace the perms + add the guards.
- GitHub UI surface — **comment-anchored, no named check-run**:
  - Inline findings on `/pulls/<N>/comments`.
  - A top-level summary comment on `/issues/<N>/comments`.
  - The only RUNNING/DONE surface is the **GitHub Actions job** of the `claude-code-review` workflow run (`/actions/workflows/claude-code-review.yml/runs`).
- **Identity — CONFIRMED `github-actions[bot]`** (calibrated PR #167, 2026-06-02). The action posts inline comments via the workflow `GITHUB_TOKEN`, so the author login is the shared `github-actions[bot]`, not a `claude[bot]` app. Filter split (refines A8 after the dogfood):
  - **Inline review comments → login-only.** Inline review comments are review output by construction, and nothing else posts them as `github-actions[bot]` on this repo — so login-membership alone is the discriminator. This is the *safe* direction: it errs toward over-counting (→ keep polling), never toward filtering a real finding out (→ which would be a false CLEAN via the zero-inline arm). Requiring a body-signature on inline comments would invert that safety.
  - **Summary issue comment → BOTH-AND** (login AND body signature). Here a false *positive* is the danger (a stray `github-actions[bot]` "no issues" comment faking a clean), so the body signature stays required. (The action posts no summary today — see § Review-state + clean detection — so this arm is currently dead backup.)

## § Tool invocations

- `./tools/find_claude_comments.sh <PR_NUMBER>` — probes engine reachability (below), then synthesizes the contract-shape stream: `CLAUDE_CHECKRUN=... STATUS=<queued|in_progress|completed>` from the **Actions job** (latest run by `run_started_at` for the head SHA), `CLAUDE_LATEST_REVIEW=...` anchored on the summary-comment id (or newest head-SHA inline comment id if no summary), inline finding blocks each carrying the mandatory `(comment id <cid>, review <rid>)` token, and an optional legacy `CLAUDE_CLEAN_SIGNAL=...` (non-authoritative). May also emit `CLAUDE_NOT_INSTALLED=true` (reachability) or `CLAUDE_REVIEW_PENDING=...` (race guard).
- `./tools/claude_retrigger.sh <PR_NUMBER>` — **fallback only.** Posts the hard-coded `@claude review once` comment. Pre-approvable in `~/.claude/settings.json`. See § Push-triggered model below — Phase 3 does NOT call this after a fix push.

**Reachability probe (A2 / R4).** `find_claude_comments.sh` probes `gh api .../actions/workflows` for `claude-code-review.yml` by filename. If the workflow is absent it emits `CLAUDE_NOT_INSTALLED=true` and exits 0, so the orchestrator's default-engine resolution can **self-exclude** claude rather than poll an un-provisioned engine to HUNG.

✅ **DO** let claude self-exclude from the *default* set on repos where the action isn't installed.

❌ **DON'T** treat `CLAUDE_NOT_INSTALLED=true` on an *explicit* `/review-loop <PR> claude` as a silent skip — it degrades **loudly**: hand back with a clear "claude action not installed (run `/install-github-app`)" message. Loud-not-silent is the contract.

## § Push-triggered model — claude is NOT retriggered after a fix push (A7)

claude is a **push-triggered** engine. The `claude-code-review.yml` action auto-runs on every push (`synchronize`), so **a fix push IS the retrigger**.

✅ **DO** let Phase 3's fix push trigger the next claude run implicitly; `find_claude_comments.sh` picks up the `synchronize` auto-run.

❌ **DON'T** fire `claude_retrigger.sh` after a Phase-3 fix push. The push already triggered the action; an explicit `@claude review once` on the same head SHA double-runs it and creates a "which run is authoritative" race. The retrigger script exists for ONE case only: the zero-activity bootstrap where `find_claude_comments.sh` finds **no Actions run at all** for the head SHA (the auto-run never fired — fresh PR, just-installed workflow).

**Dedup.** `find_claude_comments.sh` always selects the **latest Actions run by `run_started_at`** + the newest summary comment for the head SHA, so any auto-run / fallback overlap collapses to one authoritative signal.

## § Review-state + clean detection

**Review-state is synthesized from the Actions job, not a check-run.** `find_claude_comments.sh` filters `claude-code-review.yml` runs to the head SHA, picks the latest by `run_started_at`, and maps `queued`/`in_progress` → **RUNNING**, `completed` → **DONE**. The Actions `CONCLUSION` is **green whether claude found 0 or 5 issues** — it is a RUNNING/DONE signal only, NEVER a verdict.

**Clean is structural and belt-and-suspenders (A6):**

```text
clean  ⟺  the claude summary-comment body contains the case-insensitive
          substring "no issues found"
       OR zero claude-authored inline comments on the head SHA (after settle)
```

The substring (not the full sentence) follows the copilot lesson — copilot burned two phrasings (`find_copilot_comments.sh:182-189`). The zero-inline OR-arm covers action issue #1087 (empty result with no summary comment) and any future clean-string drift.

The legacy `CLAUDE_CLEAN_SIGNAL` line is corroboration only; the orchestrator derives clean structurally and counts active findings explicitly.

✅ **DO** read clean off the summary-comment body substring OR the zero-inline count.

❌ **DON'T** read clean off the Actions `CONCLUSION`. `CONCLUSION=success` means "the workflow ran", not "no findings" — a conclusion gate would always pass and ship findings as a false CLEAN.

## § Staleness rule

Keyed on **comment ids** (synthesized anchor), not a review id. `CLAUDE_LATEST_REVIEW` = the summary-comment id, or the newest head-SHA inline comment id when no summary exists. Each inline finding carries `(comment id <cid>, review <rid>)`; whether the inline comments share a single `pull_request_review_id` is **unconfirmed** (Q1, § first-run calibration) — the anchor keys on the comment id either way, so the rule is safe regardless. When `<rid>` is null/absent the orchestrator tolerates an empty review token for comment-anchored engines.

## § Race-condition caveats

**The settle valve releases on comment PRESENCE, not Actions conclusion (A3 — load-bearing).** This is the divergence from copilot's `CONCLUSION=success` settle gate. claude's Actions job flips to `completed` *before* its summary/inline comments post — a poll in that gap sees DONE + zero findings → false CLEAN.

So a `completed` Actions run whose head-SHA summary/inline comments have NOT posted is downgraded to `STATUS=in_progress` (RUNNING) + a `CLAUDE_REVIEW_PENDING` marker. The valve (`CLAUDE_REVIEW_SETTLE_SECONDS`, default **180**) keys on the **settle window alone** — never the conclusion.

**Settle window is 180s, not copilot's 600 (calibrated PR #167).** claude-code-action posts its buffered inline comments *synchronously within the job* — the `post-buffered-inline-comments` step runs **before** the run reports `completed`, so comments (if any) already exist at completed-time. The window only needs to cover GitHub API read-consistency after that in-job post, not copilot's minutes-long async-review lag.

✅ **DO** release the valve on comment presence, or — on the genuine no-comment-at-all case (#1087) after the window elapses — resolve CLEAN via the **zero-inline arm**.

❌ **DON'T** copy copilot's `CONCLUSION=success` settle gate here. claude concludes `success` even WITH findings, so a conclusion gate would always release and ship lagged findings as a false CLEAN. The valve can only ever release the genuine #1087 no-comment case (when comments HAD posted, `COMMENT_POSTED=true` and the downgrade branch is never entered).

Settle age is computed in Python `datetime` (cross-platform), never `date -d`.

## § Failure modes

| Symptom | Detection | Orchestrator action |
|---|---|---|
| claude action not installed | `CLAUDE_NOT_INSTALLED=true` (no `claude-code-review.yml` workflow on the repo) | Self-exclude from the **default** set (bare `/review-loop`); on an **explicit** `claude` run, degrade **loudly** — hand back with "run `/install-github-app`", never HUNG, never silent. |
| claude stalled | Actions job `STATUS=in_progress` (RUNNING) past observed latency on `last_push_sha` | Proceed with other engines' findings if any; do NOT explicitly retrigger (push-triggered — the next fix push re-runs it). Surface in hand-back if it doesn't recover within the idle-poll budget. |
| Actions job unreadable | `actions: read` blocked for the user's `gh` auth — `WORKFLOW_RUNS` empty, no `CLAUDE_CHECKRUN` (Q3) | Degrade to summary-comment-only state (lose the RUNNING signal) with a logged warning. Do NOT hard-fail the loop. |
| Review-pending race | Actions job `completed` but no head-SHA summary/inline comment yet | Downgraded to RUNNING + `CLAUDE_REVIEW_PENDING` (§ Race-condition caveats). Keep waiting; never a premature CLEAN. |

## § Common patterns (codified Tier 1)

The codified Tier-1 catalogue is shared across engines — see [`common-review-findings.md`](common-review-findings.md). No claude-specific deltas at present; claude's behavioural quirks live in § Review-state + clean detection and § Race-condition caveats above. (claude's severity stamp + comment-body markers are unconfirmed — see § first-run calibration; codify deltas here once a findings-bearing review lands.)

## § Review-state gate

claude exposes its review-state as `CLAUDE_CHECKRUN ... STATUS=<status>` **synthesized from the Actions job** (there is no native check-run — see the trap banner at the top). `queued`/`in_progress` = **RUNNING**, `completed` = **DONE**; `CONCLUSION` is never a verdict.

**Clean for claude**: Actions job DONE AND (summary-comment body contains "no issues found" OR zero active head-SHA inline findings matching `CLAUDE_LATEST_REVIEW`). The review-pending guard (§ Race-condition caveats) holds the loop in RUNNING until a head-SHA comment posts, so the DONE-before-comments gap cannot fire a false CLEAN. The orchestrator retriggers only from the zero-activity bootstrap (push-triggered otherwise) and never while RUNNING, so no inter-retrigger interval exists.

## § first-run calibration — status after the PR #167 dogfood (2026-06-02)

Calibrated against claude-code-action run `26834423838` (model `claude-sonnet-4-6`), a **clean** run (logged "No buffered inline comments").

**✅ CONFIRMED:**
- **Q1 (identity)** — author login is **`github-actions[bot]`** (posts via the workflow `GITHUB_TOKEN`). Locked in `CLAUDE_LOGINS`. Inline detection is login-only; summary stays BOTH-AND (see § Identity).
- **Q3 (`actions: read`)** — the local `gh` auth reads `actions/workflows/claude-code-review.yml/runs` fine; `CLAUDE_CHECKRUN` synthesizes correctly. No workflow change needed.
- **Posting model** — the action posts ONLY buffered inline comments (synchronously, in-job); there is **no summary comment**. Clean = **zero head-SHA inline comments** (the A6 zero-inline arm). The summary-substring arm is dead backup. Settle window cut to 180s (in-job synchronous posting).

**⚠️ The PR #167 calibration run's "clean" was MISLEADING (corrected after the downstream validation).** That run executed with a `pull-requests: read` workflow — read-only **cannot post review comments**. It happened to be clean (nothing to flag), so the missing post capability didn't show. **Read-only does not mean "claude reviews fine and posts nothing"; it means a findings-bearing run would have found issues and SILENTLY FAILED TO POST them → a false CLEAN.** The fix is `pull-requests: write` + `issues: write` (see § Identity + onboarding reference). Never calibrate "clean" off a read-only run.

**✅ Findings-bearing validation (downstream, write perms):** a complex code PR ran the 3-engine loop with the write-perm workflow. Claude validated past the action's anti-tampering guard, ran with posting rights, and returned a genuine clean on the (already-fixed) diff — confirming the run no longer ERRORs under write perms. (A run that ERRORs vs one that genuinely-cleans is the distinction read-only obscured.)

**⏳ STILL PENDING a findings-bearing review that actually posts:**
- **Q1 (shared review id)** — whether inline findings share a `pull_request_review_id` is still unobserved (no run has posted a finding yet). The anchor keys on comment id either way, so safe; confirm when claude first posts.
- **`CLAUDE_BODY_SIGNATURES` wording** — only matters for the (currently-dead) summary arm now that inline is login-only; lock it if/when a summary comment ever appears.
- **Q2 (`@claude review once` via the action path)** — not exercised: the action auto-ran on push, so the fallback retrigger was never needed. Confirm the fallback works if a future PR's auto-run fails to fire; else use the commented `@claude /code-review:code-review …` fallback in `claude_retrigger.sh`.
