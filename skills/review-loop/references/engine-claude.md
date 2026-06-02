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
- **Identity — CONFIRMED `claude[bot]`** for posted reviews (findings-bearing run, downstream non-draft PR, 2026-06-03). When the action actually POSTS a review — inline findings **and** a top-level **"Code review" summary comment** — the author login is **`claude[bot]`**.
  - ⚠️ **The PR #167 dogfood "confirmed `github-actions[bot]`" was WRONG** — it calibrated on a CLEAN run that posted *no claude content*, mistaking the workflow's PR-size-check / `github-actions[bot]` comment for claude's review. Never calibrate identity off a run that posted nothing. `find_claude_comments.sh`'s `CLAUDE_LOGINS` includes `claude[bot]` (plus `github-actions[bot]` / `claude-code-action[bot]` as harmless over-coverage), so detection was robust either way — but the doc was wrong.
  - **Inline review comments → login-only** (login ∈ `CLAUDE_LOGINS`). Review output by construction; the safe direction (over-count → keep polling, never a false clean).
  - **Summary issue comment → BOTH-AND** (login AND body signature). A findings-bearing run **does** post a "Code review" summary (e.g. "N issues found … No bugs detected" / "No bugs or security issues found"), so this arm is **live, not dead backup** — and the body signature stops a stray bot "no issues" comment faking a clean.

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

### ⚠️ DRAFT PRs get NO posted review — the action runs but posts nothing

**On a draft PR, the Actions run fires (`synchronize` fires on draft pushes) and concludes `success`, but claude POSTS NOTHING** — no inline findings, no summary. So a draft PR reads as **SILENT / false-clean-vector**, *not* clean. Confirmed by an A/B on one commit (downstream, 2026-06-03): the same tree read SILENT while draft and posted a full review (summary + 2 inline findings) the instant the PR was marked **ready for review**. This — not `#1087` — was the actual cause of every "ran but posted nothing" result during the engine's bring-up; the `#1087` post-session-capture bug is a *separate*, rarer failure.

✅ **DO** ensure the PR is **ready-for-review (not draft)** before trusting a claude verdict; the workflow already lists `ready_for_review` in its trigger types, so un-drafting auto-fires a real review.

❌ **DON'T** read a draft PR's silence as a finding about the code — it's the draft no-op.

**Adapter belt-and-suspenders:** `find_claude_comments.sh` now probes `gh ... pulls/<PR> .draft` up-front and, on a draft PR, emits **`CLAUDE_DRAFT_NOOP=true`** + exits early (instead of fetching runs → eventually SILENT). So even if `/review-loop`'s pre-flight un-draft is skipped or fails, the loop sees a clear "no claude verdict until ready (un-draft the PR)" signal, never a misattributed SILENT/HUNG/clean. In normal flow the pre-flight un-drafts before Phase 1, so this never fires.

**✅ Use the draft no-op as a deliberate lever — the recommended sprint cadence.** claude is the only **push-triggered** engine (bugbot/copilot are on-demand inside the review-loop), so a non-draft PR auto-runs — and bills — a claude review on **every** `/work` commit push. Keep the PR in **draft during `/work`** to suppress that, iterate freely, and **flip to ready-for-review after `/wrap`** — that single un-draft fires one intentional claude review on the finalized state, which the `/review-loop` then drives alongside bugbot/copilot. Net: one billed review per cohesive change instead of one per WIP push, and no SILENT-on-WIP noise. (If you *want* a mid-`/work` claude pass, momentarily mark ready or trigger bugbot/copilot, which don't need the un-draft.)

## § Review-state + clean detection

**Review-state is synthesized from the Actions job, not a check-run.** `find_claude_comments.sh` filters `claude-code-review.yml` runs to the head SHA, picks the latest by `run_started_at`, and maps `queued`/`in_progress` → **RUNNING**, `completed` → **DONE**. The Actions `CONCLUSION` is **green whether claude found 0 or 5 issues** — it is a RUNNING/DONE signal only, NEVER a verdict.

**Clean requires a POSITIVE posted signal — never zero-inline alone (A6 / LAYER 2).**

```text
clean    ⟺  claude POSTED a clean summary (body contains case-insensitive
            substring "no issues found")  AND  zero inline findings
findings ⟺  inline comments posted on the head SHA
SILENT   ⟸  run `success` (DONE) but NOTHING posted after settle
            → NOT clean (held RUNNING; see § Failure modes)
```

**Why not "zero inline = clean" (the original A6 belt-and-suspenders, reversed by verified research).** A claude run can report `success` having posted **nothing** — action issue [#1087](https://github.com/anthropics/claude-code-action/issues/1087): the plugin buffers inline comments for a post-session step whose result-capture grabs a `TodoWrite` response instead of the review → empty → no comment. "success + silent" is **indistinguishable from genuinely-clean** ([#1054](https://github.com/anthropics/claude-code-action/issues/1054)) by run status, so zero-inline is a **false-CLEAN vector**, not a clean signal. Clean now demands a posted clean summary; the **fixed workflow** ([`../assets/claude-code-review.yml`](../assets/claude-code-review.yml) — `classify_inline_comments:false` + `claude_args` post-during-run + a prompt that forces a posted summary *even when clean*) is what makes a genuinely-clean run actually post that summary. The substring (not the full sentence) follows the copilot lesson (`find_copilot_comments.sh:182-189`).

The legacy `CLAUDE_CLEAN_SIGNAL` line is corroboration only; the orchestrator derives clean structurally (DONE + zero active findings) — which is correct ONLY because the adapter holds a no-verdict run RUNNING (so DONE is reached only with a posted clean summary or posted findings).

✅ **DO** read clean off a POSTED clean summary + zero inline findings.

❌ **DON'T** read clean off zero-inline alone, nor off the Actions `CONCLUSION`. Both pass on a #1087 silent drop → false CLEAN.

## § Staleness rule

Keyed on **comment ids** (synthesized anchor), not a review id. `CLAUDE_LATEST_REVIEW` = the summary-comment id, or the newest head-SHA inline comment id when no summary exists. Each inline finding carries `(comment id <cid>, review <rid>)`; whether the inline comments share a single `pull_request_review_id` is **unconfirmed** (Q1, § first-run calibration) — the anchor keys on the comment id either way, so the rule is safe regardless. When `<rid>` is null/absent the orchestrator tolerates an empty review token for comment-anchored engines.

## § Race-condition caveats

**The settle valve releases on comment PRESENCE, not Actions conclusion (A3 — load-bearing).** This is the divergence from copilot's `CONCLUSION=success` settle gate. claude's Actions job flips to `completed` *before* its summary/inline comments post — a poll in that gap sees DONE + zero findings → false CLEAN.

So a `completed` Actions run with **no readable verdict** (no posted findings AND no clean summary) is held at `STATUS=in_progress` (RUNNING) so the orchestrator's "DONE + zero findings = CLEAN" can't fire on it. The settle window (`CLAUDE_REVIEW_SETTLE_SECONDS`, default **180**) only picks the marker — it never releases a no-verdict run to DONE:

- **within window** → `CLAUDE_REVIEW_PENDING` (comments may still be landing — race).
- **window elapsed** → `CLAUDE_REVIEW_SILENT` (nothing came → **NOT clean**: #1087 drop / read-only perms / un-fixed workflow). Stays RUNNING; the loop hands it back as uncertain (re-trigger / verify perms), never auto-clean.

**Settle window is 180s, not copilot's 600 (calibrated PR #167).** claude-code-action posts its inline comments *synchronously within the job* — the post step runs **before** the run reports `completed`, so comments (if any) already exist at completed-time. The window only covers GitHub API read-consistency after that in-job post, not copilot's minutes-long async-review lag.

✅ **DO** treat `CLAUDE_REVIEW_SILENT` as uncertain/needs-retrigger — never clean.

❌ **DON'T** copy copilot's `CONCLUSION=success` settle gate, and DON'T release a no-verdict run to DONE on settle-elapse (the original "zero-inline arm" — that's the #1087 false-CLEAN). claude concludes `success` even WITH findings, so conclusion is never consulted.

Settle age is computed in Python `datetime` (cross-platform), never `date -d`.

## § Failure modes

| Symptom | Detection | Orchestrator action |
|---|---|---|
| claude action not installed | `CLAUDE_NOT_INSTALLED=true` (no `claude-code-review.yml` workflow on the repo) | Self-exclude from the **default** set (bare `/review-loop`); on an **explicit** `claude` run, degrade **loudly** — hand back with "run `/install-github-app`", never HUNG, never silent. |
| **Draft PR (no review posted)** | `CLAUDE_DRAFT_NOOP=true` — the PR `.draft` is `true` (adapter early-exits) | Not a verdict — the draft no-op. `/review-loop` pre-flight should have un-drafted (`gh pr ready`); if this still fires, un-draft and re-poll. NEVER read as clean/SILENT/HUNG. |
| claude stalled | Actions job `STATUS=in_progress` (RUNNING) past observed latency on `last_push_sha` | Proceed with other engines' findings if any; do NOT explicitly retrigger (push-triggered — the next fix push re-runs it). Surface in hand-back if it doesn't recover within the idle-poll budget. |
| Actions job unreadable | `actions: read` blocked for the user's `gh` auth — `WORKFLOW_RUNS` empty, no `CLAUDE_CHECKRUN` (Q3) | Degrade to summary-comment-only state (lose the RUNNING signal) with a logged warning. Do NOT hard-fail the loop. |
| **Silent run (success + nothing posted)** | `CLAUDE_REVIEW_SILENT=...` — run `completed`/`success` but NO findings and NO clean summary after settle (held RUNNING) | **NOT clean.** Hand back as uncertain: re-trigger once, and verify the workflow has the reliability fixes + `pull-requests: write` (LAYER 1/2). Most likely the #1087 buffer-drop, a read-only-perms posting block, or an un-fixed/old workflow — never read as a clean pass. Don't wait for the full idle-timeout; the SILENT marker is the terminal signal. |

**Robust-mode alternative (record-only).** #1087 is an *open* upstream bug — the workflow fixes *mitigate* (post-during-run) but don't *guarantee* (the model can still end on a `TodoWrite` before posting). For guaranteed reliability, Anthropic's **managed Code Review GitHub App** (`@claude review`, Team/Enterprise) writes findings to **check-run annotations** independent of the comment buffer — but it's paid (~$15–25/review), research-preview, and unavailable under Zero Data Retention. If a project hits persistent SILENT despite the fixes, the managed App is the escalation path (a different adapter — it *does* post a named check-run, unlike this action path). Tracked in IDEA-012.
| Review-pending race | Actions job `completed` but no head-SHA summary/inline comment yet | Downgraded to RUNNING + `CLAUDE_REVIEW_PENDING` (§ Race-condition caveats). Keep waiting; never a premature CLEAN. |

## § Common patterns (codified Tier 1)

The codified Tier-1 catalogue is shared across engines — see [`common-review-findings.md`](common-review-findings.md). No claude-specific deltas at present; claude's behavioural quirks live in § Review-state + clean detection and § Race-condition caveats above. (claude's severity stamp + comment-body markers are unconfirmed — see § first-run calibration; codify deltas here once a findings-bearing review lands.)

## § Review-state gate

claude exposes its review-state as `CLAUDE_CHECKRUN ... STATUS=<status>` **synthesized from the Actions job** (there is no native check-run — see the trap banner at the top). `queued`/`in_progress` = **RUNNING**, `completed` = **DONE**; `CONCLUSION` is never a verdict.

**Clean for claude**: Actions job DONE AND (summary-comment body contains "no issues found" OR zero active head-SHA inline findings matching `CLAUDE_LATEST_REVIEW`). The review-pending guard (§ Race-condition caveats) holds the loop in RUNNING until a head-SHA comment posts, so the DONE-before-comments gap cannot fire a false CLEAN. The orchestrator retriggers only from the zero-activity bootstrap (push-triggered otherwise) and never while RUNNING, so no inter-retrigger interval exists.

## § calibration update — findings-bearing + clean runs (downstream non-draft, 2026-06-03)

Two runs on the SAME commit, non-draft, settled the open questions:

- **Findings-bearing run → POSTS a full review.** ~9-minute run; posted inline findings + a top-level **"Code review" summary** ("N issues found … No bugs detected") under **`claude[bot]`**. So claude **does** post findings reliably on a ready-for-review PR — the long-pending findings-path question is answered YES.
- **Clean run → SILENT (still).** After the findings were fixed, the re-review on the clean tree finished in **~1 minute** and posted **nothing** — no inline, no summary — well past settle → `CLAUDE_REVIEW_SILENT`. **The LAYER-2 forced-summary prompt does NOT fire on a clean run**: the action short-circuits ("nothing to flag") and exits without posting the "no issues found" summary it was instructed to post. So the mitigation works for *findings* but not for *clean*.

**Net engine capability (action + `code-review` plugin):** posts **findings** reliably; never posts a **positive clean verdict** — a clean PR reads SILENT (correctly held non-clean by the detection, so SAFE, but never a green "claude says clean"). Consequence for the loop: claude contributes findings; it cannot be the source of a CLEAN signal. **For a reliable clean verdict, the managed Claude Code Review App** (named check-run, verdict independent of the comment buffer) **remains the robust-mode answer** — IDEA-012 stays open on this.

## § first-run calibration — status after the PR #167 dogfood (2026-06-02, SUPERSEDED by the block above on identity + posting)

Calibrated against claude-code-action run `26834423838` (model `claude-sonnet-4-6`), a **clean** run (logged "No buffered inline comments").

**✅ CONFIRMED:**
- **Q1 (identity)** — ⚠️ SUPERSEDED. The dogfood concluded `github-actions[bot]`, but that run posted no claude content; a later findings-bearing run (non-draft) proved the posting identity is **`claude[bot]`**. `CLAUDE_LOGINS` covers both, so detection held. See § Identity for the correction. Inline detection is login-only; summary stays BOTH-AND.
- **Q3 (`actions: read`)** — the local `gh` auth reads `actions/workflows/claude-code-review.yml/runs` fine; `CLAUDE_CHECKRUN` synthesizes correctly. No workflow change needed.
- **Posting model** — the action posts ONLY buffered inline comments (synchronously, in-job); there is **no summary comment**. Clean = **zero head-SHA inline comments** (the A6 zero-inline arm). The summary-substring arm is dead backup. Settle window cut to 180s (in-job synchronous posting).

**⚠️ The PR #167 calibration run's "clean" was MISLEADING (corrected after the downstream validation).** That run executed with a `pull-requests: read` workflow — read-only **cannot post review comments**. It happened to be clean (nothing to flag), so the missing post capability didn't show. **Read-only does not mean "claude reviews fine and posts nothing"; it means a findings-bearing run would have found issues and SILENTLY FAILED TO POST them → a false CLEAN.** The fix is `pull-requests: write` + `issues: write` (see § Identity + onboarding reference). Never calibrate "clean" off a read-only run.

**✅ Findings-bearing validation (downstream, write perms):** a complex code PR ran the 3-engine loop with the write-perm workflow. Claude validated past the action's anti-tampering guard, ran with posting rights, and returned a genuine clean on the (already-fixed) diff — confirming the run no longer ERRORs under write perms. (A run that ERRORs vs one that genuinely-cleans is the distinction read-only obscured.)

**⏳ STILL PENDING a findings-bearing review that actually posts:**
- **Q1 (shared review id)** — whether inline findings share a `pull_request_review_id` is still unobserved (no run has posted a finding yet). The anchor keys on comment id either way, so safe; confirm when claude first posts.
- **`CLAUDE_BODY_SIGNATURES` wording** — only matters for the (currently-dead) summary arm now that inline is login-only; lock it if/when a summary comment ever appears.
- **Q2 (`@claude review once` via the action path)** — not exercised: the action auto-ran on push, so the fallback retrigger was never needed. Confirm the fallback works if a future PR's auto-run fails to fire; else use the commented `@claude /code-review:code-review …` fallback in `claude_retrigger.sh`.
