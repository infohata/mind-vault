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

- `./tools/find_claude_comments.sh <PR_NUMBER>` — probes engine reachability (below), then **surfaces review material** (IDEA-022 — it computes no clean/findings verdict; the § Verdict judge does): `CLAUDE_CHECKRUN=... STATUS=<queued|in_progress|completed> RUNS=<n> WINDOW_START=<iso>` from the **Actions job** (aggregated across all head-SHA runs), `CLAUDE_VERDICT_SET_PROVEN=<bool>` (structural fail-closed gate), `CLAUDE_HEAD_VERDICTS=<n> CLAUDE_VERDICT_IDS=<...>` (in-window verdict enumeration), `CLAUDE_LATEST_REVIEW=...` anchored on the summary-comment id (or newest head-SHA inline comment id if no summary), **verdict-body MATERIAL blocks** — every in-window summary body verbatim, each carrying `(comment id <cid>, review summary)`, UNclassified — and inline finding blocks each carrying `(comment id <cid>, review <rid>)`. May also emit `CLAUDE_NOT_INSTALLED=true` (reachability), `CLAUDE_DRAFT_NOOP=true` (draft PR — no review), `CLAUDE_REVIEW_PENDING=...` / `CLAUDE_REVIEW_SILENT=...` (race / silent guards). No `CLAUDE_CLEAN_SIGNAL`, no `CLAUDE_HAS_FINDINGS`, no `CLEAN=` token — those were the removed prose classifier.
- `./tools/claude_retrigger.sh <PR_NUMBER>` — **fallback only.** Posts the hard-coded `@claude review once` comment. Pre-approvable in `~/.claude/settings.json`. See § Push-triggered model below — Phase 3 does NOT call this after a fix push.

**Reachability probe (A2 / R4).** `find_claude_comments.sh` probes `gh api .../actions/workflows` for `claude-code-review.yml` by filename. If the workflow is absent it emits `CLAUDE_NOT_INSTALLED=true` and exits 0, so the orchestrator's default-engine resolution can **self-exclude** claude rather than poll an un-provisioned engine to HUNG.

✅ **DO** let claude self-exclude from the *default* set on repos where the action isn't installed.

❌ **DON'T** treat `CLAUDE_NOT_INSTALLED=true` on an *explicit* `/review-loop <PR> claude` as a silent skip — it degrades **loudly**: hand back with a clear "claude action not installed (run `/install-github-app`)" message. Loud-not-silent is the contract.

## § Push-triggered for the FIRST review; EXPLICIT retrigger for every review after (A7 — CORRECTED, PR #169 self-dogfood)

The `claude-code-review.yml` action auto-runs on every push (`synchronize`), **but the `code-review` plugin skips the auto-run once claude has already posted a review on the PR** — it posts a `## Code review\n\nSkipping review — Claude has already posted a code review comment` no-op instead of a fresh review. So the push is the retrigger **only for the first review**:

- The **push auto-run produces a real review ONLY the first time** claude sees the ready PR (any push before claude has commented). 
- Every **subsequent push auto-SKIPS** → no fresh verdict (a "Skipping review …" no-op, caught by `CLAUDE_NOOP_PATTERNS`). Verified PR #169: pushes `06b3a3b` + `16e6dd4` both skip-no-op'd after the first review on `7399749`. ⚠️ **NOT universal** — a second downstream project's install **never skipped**: every push auto-run produced a full substantive review even after multiple prior reviews, so push + explicit retrigger yields **two substantive verdicts per SHA that can DISAGREE**. See § calibration update — dual substantive verdicts (below) for the masking hazard and the adapter rule.
- An **explicit `@claude review`** (`claude_retrigger.sh`) **overrides the skip and forces a fresh review.** Verified PR #169: the explicit retrigger produced a full 3-minute review where the two prior pushes had skipped. Note the explicit path posts in the **@-mention / task format** ("Claude finished @user's task … ### Code Review …") — a different shape than the auto "## Code review" summary; the catch-everything classifier (§ Review-state + clean detection) handles both.

✅ **DO** let the **FIRST** claude review come from the push / un-draft auto-run (no explicit retrigger needed before claude has commented).

✅ **DO** fire `claude_retrigger.sh` after a Phase-3 fix push **once claude has already reviewed the PR** — the push auto-run will skip, so the explicit `@claude review` is the only thing that gets a fresh verdict on the fix. **This REVERSES the prior "the push IS the retrigger, don't double-fire" guidance, which was wrong for the 2nd+ review** (the feared double-run race doesn't occur: the auto-run skips, so the explicit retrigger is the sole review).

❌ **DON'T** expect a fix push alone to re-review after claude's first comment — it skip-no-ops, and the loop will read the stale prior verdict (or a no-op) until you explicitly retrigger.

⚠️ **Double-run friction (fix-push + explicit retrigger on the SAME head SHA).** A Phase-3 fix push fires a `synchronize` auto-run *and* you then fire `claude_retrigger.sh` — **two Actions runs for one head SHA**: the auto-run skip-no-ops (claude already reviewed the PR), the explicit run produces the real verdict. Because the adapter derives `STATUS` from the *latest run by `run_started_at`*, it can report `in_progress`/`RUNNING` off whichever run started later — sometimes the skip-no-op run — **while the real verdict (a `CLAUDE_LATEST_REVIEW` summary for the head SHA, with substantive prose) is already posted.** Observed repeatedly in a multi-engine sprint-auto loop: the orchestrator polled an `in_progress` claude run for several extra cycles after the verdict was readable. Mitigation: when a `CLAUDE_LATEST_REVIEW` summary/inline set exists **for the current head SHA with substantive verdict prose** (not the in-progress checklist comment — see § Race-condition caveats), treat claude as DONE for that SHA even if the latest Actions run still shows `in_progress`; the lingering run is the skip-no-op twin. (Distinct from the no-verdict-held-RUNNING case below, which is correct — there the run is held *because* no verdict is readable.)

The retrigger script also covers the **zero-activity bootstrap**: no Actions run at all for the head SHA (fresh PR / just-installed workflow).

**Dedup.** `find_claude_comments.sh` always selects the **latest Actions run by `run_started_at`** + the newest summary comment for the head SHA, so any auto-run / fallback overlap collapses to one authoritative signal. ⚠️ **Latest-wins is only safe when at most one substantive verdict exists per SHA** — on installs where the auto-run doesn't skip (see § calibration update — dual substantive verdicts), the newest summary can be a clean verdict that MASKS an earlier findings-bearing verdict on the same SHA. Orchestrators must enumerate **every** substantive verdict for the head SHA, not trust the adapter's latest-only line.

### ⚠️ DRAFT PRs get NO posted review — the action runs but posts nothing

**On a draft PR, the Actions run fires (`synchronize` fires on draft pushes) and concludes `success`, but claude POSTS NOTHING** — no inline findings, no summary. So a draft PR reads as **SILENT / false-clean-vector**, *not* clean. Confirmed by an A/B on one commit (downstream, 2026-06-03): the same tree read SILENT while draft and posted a full review (summary + 2 inline findings) the instant the PR was marked **ready for review**. This — not `#1087` — was the actual cause of every "ran but posted nothing" result during the engine's bring-up; the `#1087` post-session-capture bug is a *separate*, rarer failure.

✅ **DO** ensure the PR is **ready-for-review (not draft)** before trusting a claude verdict; the workflow already lists `ready_for_review` in its trigger types, so un-drafting auto-fires a real review.

❌ **DON'T** read a draft PR's silence as a finding about the code — it's the draft no-op.

**Adapter belt-and-suspenders:** `find_claude_comments.sh` now probes `gh ... pulls/<PR> .draft` up-front and, on a draft PR, emits **`CLAUDE_DRAFT_NOOP=true`** + exits early (instead of fetching runs → eventually SILENT). So even if `/review-loop`'s pre-flight un-draft is skipped or fails, the loop sees a clear "no claude verdict until ready (un-draft the PR)" signal, never a misattributed SILENT/HUNG/clean. In normal flow the pre-flight un-drafts before Phase 1, so this never fires.

**✅ Use the draft no-op as a deliberate lever — the recommended sprint cadence.** claude is the only **push-triggered** engine (bugbot/copilot are on-demand inside the review-loop), so a non-draft PR auto-runs — and bills — a claude review on **every** `/work` commit push. Keep the PR in **draft during `/work`** to suppress that, iterate freely, and **flip to ready-for-review after `/wrap`** — that single un-draft fires one intentional claude review on the finalized state, which the `/review-loop` then drives alongside bugbot/copilot. Net: one billed review per cohesive change instead of one per WIP push, and no SILENT-on-WIP noise. (If you *want* a mid-`/work` claude pass, momentarily mark ready or trigger bugbot/copilot, which don't need the un-draft.)

## § Review-state + clean detection

**Review-state is synthesized from the Actions job, not a check-run.** `find_claude_comments.sh` filters `claude-code-review.yml` runs to the head SHA, picks the latest by `run_started_at`, and maps `queued`/`in_progress` → **RUNNING**, `completed` → **DONE**. The Actions `CONCLUSION` is **green whether claude found 0 or 5 issues** — it is a RUNNING/DONE signal only, NEVER a verdict. This RUNNING/DONE state, the SILENT-≠-clean hold, and the settle valve are all **structural** (machine-derived in the adapter, unchanged by IDEA-022).

**Clean/blocking/non-blocking is a MODEL JUDGMENT, not a regex (IDEA-022).** The adapter no longer classifies claude's prose with `CLAUDE_CLEAN_PATTERNS` / `CLAUDE_FINDING_MARKERS` — that string-matcher false-FINDING'd on unrecognized clean phrasing (the dogfood) and risked false-CLEAN on marker-less prose findings (the architect's hole); both are inevitable when regex parses free-form model output. The adapter is reduced to **surfacing review material** (RUNNING/DONE, the in-window verdict-body enumeration, inline findings, `CLAUDE_VERDICT_SET_PROVEN`); the `/review-loop` orchestrator **judges that material with a model** and emits a tiered verdict. The full judge contract is **§ Verdict judge** below.

**`SILENT` (success + nothing posted) is still NOT clean — and it is structural, not a judgment.** A claude run can report `success` having posted **nothing** — action issue [#1087](https://github.com/anthropics/claude-code-action/issues/1087): the plugin buffers inline comments for a post-session step whose result-capture grabs a `TodoWrite` response instead of the review → empty → no comment. "success + silent" is **indistinguishable from genuinely-clean** ([#1054](https://github.com/anthropics/claude-code-action/issues/1054)) by run status, so the adapter holds a no-verdict `completed` run at **RUNNING** (§ Race-condition caveats) and emits `CLAUDE_REVIEW_SILENT` when the settle window elapses. The judge is only ever handed **posted, non-no-op material**; a SILENT run never reaches it (there is nothing to read), so the false-CLEAN-on-silence vector is closed structurally, upstream of the judge.

✅ **DO** route the clean/blocking/non-blocking decision to the § Verdict judge, reading the posted material the adapter surfaces.

❌ **DON'T** read clean off zero-inline alone, off the Actions `CONCLUSION`, or off any leftover prose-substring — and never judge a SILENT run (it posted nothing to judge; it is held RUNNING).

## § Verdict judge — the model-judge contract (IDEA-022; owns clean/blocking/non-blocking)

> Carve-out, typed to cause (not engine name). The core rule "**clean is structural, never prose**" ([`../SKILL.md`](../SKILL.md) § Phase 1) holds for every engine with a **structured verdict surface** (bugbot/copilot post severity-tagged structured findings — a machine reads them). claude has **no structured surface**: its verdict *is* prose (§ Identity — no severity JSON, no named check-run). For a **prose-only verdict surface**, the prose IS the structural signal, and a model reading it is the classification. This carve-out is licensed by *absence of a structured surface* and applies to **any future prose-only engine**, not to claude by name.

### Structural-vs-semantic split

| Layer | Who decides | Surface |
| --- | --- | --- |
| RUNNING / DONE (all head-SHA runs completed?) | **adapter** (machine) | `CLAUDE_CHECKRUN ... STATUS=` aggregated across runs |
| Was a real review posted (vs draft/skip no-op, vs SILENT)? | **adapter** (machine) | `CLAUDE_NOOP_PATTERNS` filter, `CLAUDE_DRAFT_NOOP`, `CLAUDE_REVIEW_SILENT` — a no-op/SILENT run never reaches the judge |
| Was the whole head-SHA verdict set seen (vs paginated-out)? | **adapter** (machine, fail-closed) | `CLAUDE_VERDICT_SET_PROVEN` |
| Which substantive bodies + inline findings exist for the head SHA | **adapter** (machine) | `CLAUDE_HEAD_VERDICTS=<n>` + each verdict body verbatim + inline blocks `(comment id …, review …)` |
| **clean vs blocking vs non-blocking** | **the model-judge** (orchestrator-inline) | the tiered verdict below |

The adapter surfaces material; it computes **no** clean/findings verdict. Only the last row is the judge's — and only because the surface is prose.

### The judge prompt (orchestrator-inline)

When `claude` ∈ `ENGINES` and its adapter run is **DONE with a readable verdict** (not RUNNING/PENDING/SILENT/NOOP/DRAFT), the `/review-loop` agent reads the surfaced material — **every** in-window verdict body verbatim + every head-SHA inline finding + `CLAUDE_VERDICT_SET_PROVEN` — and judges:

> You are the review-loop's verdict judge for the claude engine. You are handed the full review material claude posted for the current head SHA: every substantive summary-comment body (verbatim), every head-SHA inline finding, and the structural facts (`CLAUDE_HEAD_VERDICTS`, `CLAUDE_VERDICT_SET_PROVEN`, unresolved inline-thread ids). Classify the review into exactly one tiered verdict:
>
> - **`CLEAN`** — claude found nothing that should change before merge. A genuinely-clean review (it may still *name* what it checked, e.g. "the privilege-escalation guard looks correct").
> - **`BLOCKING`** — one or more findings that must be addressed before merge. Bugs, security issues, correctness problems, convention violations claude flags as required.
> - **`NON_BLOCKING[<item>, …]`** — claude is content to merge but raised observations worth recording (e.g. "works, but you might later extract X"). Each item is `{title, why, where}`.
>
> A single review can be `BLOCKING` *and* carry `NON_BLOCKING` items — return `BLOCKING` with the non-blocking items listed alongside; blocking dominates for convergence. `CLEAN` and `NON_BLOCKING[]` both let the loop converge; only `BLOCKING` keeps it iterating.
>
> **The false-CLEAN direction is the dangerous one (IDEA-018 philosophy).** When uncertain whether an item is blocking, classify it **blocking**. Never return `CLEAN` past an unresolved concern. A "ready to merge, but one concern: …" body is **not** `CLEAN` — the concern is at least `NON_BLOCKING`, and if it names a correctness/security/convention defect it is `BLOCKING`.
>
> **Masking rule (verbatim — transcribed from § dual substantive verdicts).** Enumerate **every** substantive head-SHA body. Any unaddressed findings-bearing body keeps the verdict **`BLOCKING`** even if a newer same-SHA body reads clean — findings are addressed by fixes, never by a luckier newer roll. A clean verdict never overrides an earlier findings verdict on the same SHA.
>
> **Proven-set fail-closed (structural, non-overridable).** If `CLAUDE_VERDICT_SET_PROVEN` is not `true`, you **cannot** return `CLEAN` — the adapter could not prove it saw the whole verdict set (paginated-out / blank run timestamps / no run window), so a clean read can't rule out a masked earlier verdict. Return `BLOCKING` (re-poll / re-trigger) until the set is proven.
>
> When you return `CLEAN` over a posted summary body, **record which body id you cleared and the one-line reason** — a clean verdict over substantive prose must be auditable.

### Backstop — stated honestly (architect C1; no "guarded two ways" overclaim)

The never-false-CLEAN bias has **two different anchors depending on finding shape**, because claude's *common* finding shape is **summary-body-only with zero inline threads** (§ calibration update — findings live in the SUMMARY BODY; the ~30-docstring real case):

- **Inline-thread findings** → the structural anchor holds: an unresolved head-SHA inline thread ⇒ the judge must not return `CLEAN` (machine-countable).
- **Summary-body-only findings** → there is **no inline-thread anchor** (the signal *is* prose). The guard here is the **judge instruction** (false-CLEAN-dangerous) **plus** the structural **proven-verdict-set requirement** (`CLAUDE_VERDICT_SET_PROVEN` fail-closed). The judge may return `CLEAN` only over a verdict set the adapter proved whole.

So: structural where a structural signal exists (inline threads, proven-set, masking enumeration); judge-instruction where the signal is irreducibly prose. Not "guarded two ways" everywhere — guarded by whatever anchor the finding shape affords.

### Fixture taxonomy (drives the tests — § Verification / `tests/`)

The judge contract is gated **asymmetrically** (architect C2 — moving classification to a model loses the deterministic CI gate, so restore it only on the dangerous direction):

- **Hard-gated (false-CLEAN direction; the structurally-detectable part runs in bash CI):**
  - **summary-body-only blocking finding** (the `:176` ~30-docstring shape) — the adapter MUST surface the body verbatim so the judge sees the concern.
  - **dual-verdict masking** (newer clean body masks an earlier findings-bearing body on the same SHA) — the adapter MUST enumerate **both** bodies (`CLAUDE_HEAD_VERDICTS=2`), so a masked verdict can never be invisible to the judge.
  - **unprovable verdict set** — `CLAUDE_VERDICT_SET_PROVEN=false` MUST hold, structurally forbidding a `CLEAN` judgment.
  - **marker-less prose finding** ("ready to merge; one concern: no auth check on the new endpoint") — the adapter MUST surface the body verbatim; the *NOT-CLEAN reading* of it is the judge's (no structural signal distinguishes it from clean prose — that is exactly why it needs a model, and why this specific reading is **judge-eval / advisory**, not a bash assertion).
- **Advisory (safe boundary; model variance is a calibration signal, not a build break):** the `CLEAN`-vs-`NON_BLOCKING` boundary — e.g. the dogfood `4729548936` "all findings resolved / ready to merge" recap should read `CLEAN` (or `NON_BLOCKING`), the original false-positive gone; a pure suggestion reads `NON_BLOCKING`.

**What the bash hard-gate can and cannot assert** (architect C1, honest): bash deterministically gates that **the dangerous material is always surfaced to the judge** (verbatim bodies, full verdict enumeration) **and the structural fail-closed holds** (`CLAUDE_VERDICT_SET_PROVEN`, masking enumeration). The semantic NOT-CLEAN *reading* of pure prose is the model's job — covered by the judge instruction + the advisory eval, not a deterministic bash assertion. The machine guarantees the judge can't be starved of the concern; the model guarantees it reads the concern correctly.

## § Staleness rule

Keyed on **comment ids** (synthesized anchor), not a review id. `CLAUDE_LATEST_REVIEW` = the summary-comment id, or the newest head-SHA inline comment id when no summary exists. Each inline finding carries `(comment id <cid>, review <rid>)`; whether the inline comments share a single `pull_request_review_id` is **unconfirmed** (Q1, § residual open questions) — the anchor keys on the comment id either way, so the rule is safe regardless. When `<rid>` is null/absent the orchestrator tolerates an empty review token for comment-anchored engines.

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
| claude stalled | Actions job `STATUS=in_progress` (RUNNING) past observed latency on `last_push_sha` — **but claude's normal latency is long (up to ~17 min on a large PR); confirm genuinely wedged, not merely slow — see § slow-not-hung** | Proceed with other engines' findings if any; do NOT explicitly retrigger (push-triggered — the next fix push re-runs it). **Before treating it as stalled, run the § slow-not-hung checks (step-progress + verdict re-fetch).** Surface in hand-back if it doesn't recover within the idle-poll budget. |
| Actions job unreadable | `actions: read` blocked for the user's `gh` auth — `WORKFLOW_RUNS` empty, no `CLAUDE_CHECKRUN` (Q3) | Degrade to summary-comment-only state (lose the RUNNING signal) with a logged warning. Do NOT hard-fail the loop. |
| **Silent run (success + nothing posted)** | `CLAUDE_REVIEW_SILENT=...` — run `completed`/`success` but NO findings and NO clean summary after settle (held RUNNING) | **NOT clean.** Hand back as uncertain: re-trigger once, and verify the workflow has the reliability fixes + `pull-requests: write` (LAYER 1/2). Most likely the #1087 buffer-drop, a read-only-perms posting block, or an un-fixed/old workflow — never read as a clean pass. Don't wait for the full idle-timeout; the SILENT marker is the terminal signal. **Anchor: a *first* un-draft/initial auto-run came back SILENT (#1087) and a single explicit `claude_retrigger.sh` then produced a full verdict — the retrigger recovery works on the first review too, not only after a fix push. Its first response may be the in-progress checklist (§ Race-condition caveats), so wait for the checklist to resolve / a substantive verdict to post before judging.** |

**Robust-mode alternative (record-only).** #1087 is an *open* upstream bug — the workflow fixes *mitigate* (post-during-run) but don't *guarantee* (the model can still end on a `TodoWrite` before posting). For guaranteed reliability, Anthropic's **managed Code Review GitHub App** (`@claude review`, Team/Enterprise) writes findings to **check-run annotations** independent of the comment buffer — but it's paid (~$15–25/review), research-preview, and unavailable under Zero Data Retention. If a project hits persistent SILENT despite the fixes, the managed App is the escalation path (a different adapter — it *does* post a named check-run, unlike this action path). Tracked in IDEA-012.
| Review-pending race | Actions job `completed` but no head-SHA summary/inline comment yet | Downgraded to RUNNING + `CLAUDE_REVIEW_PENDING` (§ Race-condition caveats). Keep waiting; never a premature CLEAN. |

## § Actions billing wall — jobs fail at startup, NOT a code/engine problem

On a **private repo** GitHub-hosted Actions minutes are metered. When the account exhausts its included minutes (or a payment fails / the spending limit sits at $0), **every** workflow — claude-review included — stops at **job startup**: the run is `conclusion=failure`, `STATUS=completed`, `runner=""`, `steps: []`, finishes in ~2 s, and `gh run view --log-failed` returns "log not found". The real reason is in the check-run **annotation**: *"The job was not started because recent account payments have failed or your spending limit needs to be increased."* (`gh api repos/{O}/{R}/check-runs/{id}/annotations`).

**Distinguish from a real engine failure**: a genuine claude failure runs its steps (logs exist, duration ≫ seconds). A billing wall produces **no steps + sub-2s duration across UNRELATED workflows at the same instant** (e.g. claude-review AND a trivial lint/size check both fail in the same second). That signature = **account billing, not the engine**.

Orchestrator action: **surface to the user** (Settings → Billing & plans — raise the Actions spending limit or fix the payment method), **do NOT retrigger** (the rerun also fails to start, burning the loop's budget on a wall it can't clear), and **never read it as a claude verdict**. Only the Actions-based engine (claude) is affected — app-based engines (bugbot/copilot) keep working, so a multi-engine loop can still make partial progress. Anchor: a heavy multi-PR review day exhausted a private repo's monthly minutes mid-afternoon; reruns succeeded the moment the spending limit was raised.

## § slow-not-hung — don't escape-hatch a long claude run on elapsed time alone

claude's review legitimately runs **much longer than bugbot/copilot** — observed up to **~17 min** on a large multi-file PR (vs the ~1–9 min seen on small diffs). The multi-engine stall escape-hatch ([`multi-engine-sync.md`](multi-engine-sync.md) § Trade-off escape hatch) must therefore **not** fire on elapsed wall-time alone — that's how a still-working run gets abandoned one beat before it posts.

Field near-miss (the source of this note): a ~17-min run was treated as hung and superseded by a fix push; it then posted real findings essentially immediately after — the supersede had thrown them away, and a human surfaced the missed findings by hand. Two findings were lost to the loop.

Before tripping the escape-hatch on claude:

1. **Confirm genuinely wedged, not just slow.** Read the Actions job's *step progress*, not just elapsed time: `gh run view <run-id>` (or `--json jobs`). A job advancing through steps is working; a job parked on one step well past its normal duration is wedged. *No step movement* is the wedged signal — elapsed-since-start is not.
2. **Re-fetch for a late-posted verdict FIRST.** Re-run `find_claude_comments.sh` immediately before superseding — claude posts its summary/inline comments synchronously near the **end** of the job (§ Settle window), so a run that was verdict-less five minutes ago may have just posted. A supersede that skips this re-check is the exact shape of the near-miss.
3. **Raise the stall ceiling for claude specifically.** Whatever per-engine stall threshold the loop carries, claude's must sit comfortably above its ~17-min observed worst case — a ceiling tuned to copilot/bugbot's minutes mis-classifies a healthy claude run as hung.

This pairs with the RUNNING-state machine (§ Review-state gate): a `completed` Actions run with no readable verdict is held at RUNNING precisely so the loop can't read a no-verdict run as CLEAN — and the same discipline says **don't read a still-RUNNING run as hung** until step-progress proves it. (It also pairs with the C1 calibration: even once it posts, claude's findings often live only in the summary BODY, so a too-early supersede skips them twice over — never fetched, never surfaced.)

## § Common patterns (codified Tier 1)

The codified Tier-1 catalogue is shared across engines — see [`common-review-findings.md`](common-review-findings.md). No claude-specific deltas at present; claude's behavioural quirks live in § Review-state + clean detection and § Race-condition caveats above. (claude's comment-body finding markers are now calibrated — see § calibration update — findings live in the SUMMARY BODY; the severity stamp on a summary-body finding is a heuristic, re-triaged by the loop.)

## § Review-state gate

claude exposes its review-state as `CLAUDE_CHECKRUN ... STATUS=<status>` **synthesized from the Actions job** (there is no native check-run — see the trap banner at the top). `queued`/`in_progress` = **RUNNING**, `completed` = **DONE**; `CONCLUSION` is never a verdict.

**Clean for claude**: Actions job DONE (all head-SHA runs `completed`) AND the **§ Verdict judge** returns `CLEAN` or `NON_BLOCKING[]` over the surfaced material (IDEA-022 — clean is a model judgment for this prose-only surface, not a regex). The review-pending guard (§ Race-condition caveats) holds the loop in RUNNING until a head-SHA comment posts, so the DONE-before-comments gap cannot fire a false CLEAN; a SILENT run is held RUNNING and never reaches the judge. The orchestrator retriggers only from the zero-activity bootstrap (push-triggered otherwise) and never while RUNNING, so no inter-retrigger interval exists.

> **⚠️ IDEA-022 supersession (regex mechanism → judge input).** The calibration blocks below were written to tune the **regex classifier** (`CLAUDE_CLEAN_PATTERNS` / `CLAUDE_FINDING_MARKERS` / `is_clean`), which IDEA-022 **removed** — the clean/blocking/non-blocking decision is now the **§ Verdict judge** (a model reading the prose). The *classification mechanism* these blocks describe is gone. Their *behavioural observations* — findings often live only in the summary BODY; clean is whole-review not substring; two substantive verdicts on one SHA can disagree; no-op/skip bodies aren't verdicts; clean now usually posts on both paths — are **exactly the material the judge reasons over**, so they remain load-bearing as judge input. Read them as "what claude's prose looks like in the wild," not "what regex to match."

## § calibration update — findings-bearing + clean runs (downstream non-draft, 2026-06-03)

Two runs on the SAME commit, non-draft, settled the open questions:

- **Findings-bearing run → POSTS a full review.** ~9-minute run; posted inline findings + a top-level **"Code review" summary** ("N issues found … No bugs detected") under **`claude[bot]`**. So claude **does** post findings reliably on a ready-for-review PR — the long-pending findings-path question is answered YES.
- **Clean run → SILENT (still).** After the findings were fixed, the re-review on the clean tree finished in **~1 minute** and posted **nothing** — no inline, no summary — well past settle → `CLAUDE_REVIEW_SILENT`. **The LAYER-2 forced-summary prompt does NOT fire on a clean run**: the action short-circuits ("nothing to flag") and exits without posting the "no issues found" summary it was instructed to post. So the mitigation works for *findings* but not for *clean*.

**Net engine capability (action + `code-review` plugin):** posts **findings** reliably. ⚠️ **The "never posts a positive clean verdict — a clean PR reads SILENT" claim below is OUTDATED as of 2026-06-08 — see § COUNTER-OBSERVATION** (clean verdicts now post on both trigger paths; likely an upstream fix). The historical claim, preserved for context: a clean PR read SILENT (correctly held non-clean by the detection, so SAFE, but never a green "claude says clean"), so claude contributed findings only, never a CLEAN signal. That was the basis for IDEA-012 keeping the **managed Claude Code Review App** (named check-run, verdict independent of the comment buffer) as the robust-mode answer — still the most reliable, but the action path now does usually post clean.

## § calibration update — findings live in the SUMMARY BODY (downstream, 2026-06-03)

The first *high-volume* findings-bearing run (13 `claude[bot]` summary comments across a long iteration) exposed that the prior "findings = inline comments + a short summary" model **undercounts where claude puts findings**. CALIBRATED against the real bodies; the adapter (`find_claude_comments.sh`) was fixed to match (the **C1** fix). Corrections (the last two added by the PR #169 self-dogfood — running this engine on the PR that ships C1):

- **Findings often post ONLY in the summary BODY, not inline.** claude's convention findings (CLAUDE.md docstring violations) and cross-file findings it can't line-anchor (privilege-escalation spanning a form + a view) are written as a structured report **inside the `claude[bot]` "## Code review" issue-comment body** — `### Bugs / Security`, `#### 1. …`, `### CLAUDE.md compliance / Docstrings missing …` — with **zero inline comments**. The old adapter only read the summary body for the clean substring, never surfaced its findings → claude's convention review was **invisible to the loop** (the user surfaced ~6 URL + ~30 docstring findings by hand). Fix: the adapter now surfaces a findings-bearing summary body as a finding block carrying `(comment id <cid>, review summary)`.
- **The summary heading is literally `## Code review` (space), which the old `code-review` (hyphen) signature did NOT match** → the whole summary was unrecognized. Signature widened to `code[ -]?review`.
- **Clean is WHOLE-REVIEW, not substring-anywhere.** claude clears sections independently: a single review says **"Bugs: No issues found."** in one section AND lists **"Docstrings missing"** in another. A bare `'no issues found' in body` test **false-cleans** that mixed review (the dangerous direction). Clean requires a positive clean phrase (`no issues/bugs/problems found`) AND the **absence of any finding marker** (structural, not security-keyword: a genuinely-clean review NAMES the concepts it checked, e.g. *"the privilege-escalation guard looks correct"*, so `privilege`/`escalation` as markers false-positive on clean prose). Re-validated against all 13 downstream bodies (2026-06-03): **3 NOOP, 9 FINDINGS** (incl. every mixed clean-bugs-but-dirty-compliance review), **1 CLEAN** (the final whole-review verdict) — **zero false-cleans** (the PR body's "2 NOOP / 10" was an off-by-one miscount; all three `Skipped` bodies are genuine no-ops).
- **No-op skip bodies must be filtered — ANCHORED.** claude posts `## Code review\n\nSkipped — …draft status` and `## Code review\n\nSkipped: …already reviewed this PR` issue comments that match the signature but are **not verdicts**. Anchored to the heading-then-`Skipped` shape (`^##\s+code[ -]?review\s*\n+\s*skipped`, `re.MULTILINE`) — **not** a bare search-anywhere — so a real findings body whose *prose* merely says "already reviewed in PR #N but regressed" is not false-filtered (PR #169 self-dogfood caught the old unanchored `already (posted|reviewed)` arm dropping exactly that — claude's finding body literally contained "already reviewed").
- **Surface is CATCH-EVERYTHING, marker-INDEPENDENT (PR #169 self-dogfood).** Review format is **non-deterministic** — count-line ("One issue found.") + ``### `file` `` headers in one run, `#### 1.` numbered + `### Bugs` sections in another, future runs may differ again. So the adapter does **not** require a matched marker to surface findings: a posted, non-no-op summary is **either provably-clean OR surfaced-as-findings** (`findings = posted ∧ ¬clean`). Markers now only gate the *clean* determination + severity. An unseen future finding shape therefore can never read SILENT. (The dogfood: claude posted "One issue found." under ``### `file` `` while reviewing this adapter; the marker-only logic read SILENT and dropped it — the inversion + anchored no-op are the fix.)

This does **not** change the findings-side capability: claude posts findings reliably; the C1 fix only stops claude's *findings* — when they exist and live in the body — from being silently dropped. (The "never a positive clean verdict / clean reads SILENT" half of this is **outdated as of 2026-06-08** — see § COUNTER-OBSERVATION; clean verdicts now post on both paths.)

## § COUNTER-OBSERVATION — clean trees DO post a positive clean verdict, on BOTH paths (PR #190 + #192, 2026-06-08)

Two independent, reproducible data points **against** the "clean always reads SILENT" claim above — now confirmed on **both** trigger paths, so the §158 SILENT-on-clean behaviour is no longer the whole story:

- **Observation 1 — explicit-retrigger path (PR #190).** First claude run fired on `ready_for_review` over a tree with one real (bugbot-found) finding → claude went **SILENT** (run `completed`, posted nothing — the expected #1087 / short-circuit behaviour). The finding was fixed, pushed, and claude was **explicitly retriggered via `claude_retrigger.sh`** (`@claude review` / `claude.yml`). On the clean post-fix tree it posted a **positive whole-review clean summary** — `find_claude_comments.sh` read `CLAUDE_SUMMARY_ID=… CLEAN=true FINDINGS=false`, loop terminated structurally **CLEAN** off claude.
- **Observation 2 — push / auto-run path (PR #192).** On the *first* claude review of a clean tree (the PR-open auto-run on `claude-code-review.yml`, **no retrigger**), claude **again posted a positive clean summary** → `CLEAN=true FINDINGS=false`, structurally CLEAN. This is the path §158 said short-circuits to SILENT on clean — and here it did not.
- **What this changes.** The **push-vs-retrigger asymmetry hypothesis is WEAKENED** — claude posted a positive clean verdict on *both* paths within the same day. The §158 "clean run → SILENT (still)" + §Net-capability "never posts a positive clean verdict" claims are at minimum **no longer reliably true**; the most likely explanation is **upstream improvement to the action's clean-path posting** (a `code-review`-plugin or `claude-code-action` update between the §158 calibration and 2026-06-08), not a path-specific quirk. Still possible: SILENT-on-clean recurs intermittently (the #1087 buffer-drop is an *open* upstream bug), so this is "clean verdicts now usually post" — NOT "SILENT-on-clean is impossible."
- **Loop consequence (unchanged for safety).** Detection is structural (clean = DONE + posted clean summary + zero finding markers), so a posted clean verdict reads CLEAN correctly and any residual SILENT run still reads NOT-clean. The adapter needs no change to be *safe*. What changes is *reliance*: claude **can now usually be a CLEAN source** (both paths observed). Treat a clean claude verdict as a real signal; but because SILENT-on-clean can still recur (open #1087), do **not** hard-depend on claude being the *sole* clean gate — keep a second engine (bugbot) when a definitive clean matters. Promote further (drop the "usually") only if SILENT-on-clean goes unseen across a longer run of clean PRs.

## § calibration update — clean summary CAN coexist with inline-only findings; progress comments are not verdicts (downstream, 2026-06-11)

Two adapter blind spots observed in one loop run on a downstream project, both in the *summary-trusting* direction (the dangerous one):

- **A clean-prose summary does NOT imply zero findings.** One run posted **3 inline finding comments** (each as its **own separate review object**, seconds apart) and then, ~10s later, a summary whose prose read clean → the adapter emitted `CLEAN=true FINDINGS=false` while 3 active inline findings sat on the head SHA. This is the **inverse** of the §164 calibration (findings only-in-summary-body): findings can also be **only-inline with a clean-reading summary**. Consequence for orchestrators and the adapter: **never derive the findings count from the summary body** — enumerate `/pulls/<n>/comments` for the head SHA's review ids independently, every cycle, and require zero active inline findings *in addition to* a clean summary. (The structural-clean rule in the core skill already demands this; the trap is an adapter summary line that *looks* like it did the enumeration.)
- **In-flight progress comments match the verdict signature.** The action edits a `## Code review` issue comment *while working* — task checklist with unchecked `- [ ]` items ("Post findings" unchecked) + a "View job run" link. On the explicit-retrigger path this progress comment exists **while the prior push's check-run reads `completed`** (the retrigger run is a *different* workflow run, often under `claude.yml`, not the `claude-code-review.yml` check-run the adapter watches), so the adapter read it as a findings-bearing verdict (`CLEAN=false FINDINGS=true`) mid-run. Markers for not-a-verdict: unchecked checklist items, absence of any findings/clean section, "Claude finished" header missing. Treat such a body as RUNNING regardless of any check-run state the adapter resolved.
- **Q1 (below) is now answered**: inline findings do **not** share one `pull_request_review_id` — each inline comment posted as its own single-comment review. The comment-id staleness anchor (§ Staleness) handles this correctly; review-id-based grouping would have read "3 reviews" as 3 separate passes.

## § residual open questions (post-downstream calibration)

The §131 + §140 downstream blocks supersede the PR #167 first-run calibration — identity (`github-actions[bot]` → **`claude[bot]`**), the dead "zero-inline-only, no summary" posting model, and `CLAUDE_BODY_SIGNATURES` wording are all now confirmed. Two items survive it:

- **Never calibrate "clean" off a read-only (`pull-requests: read`) run.** The PR #167 run read clean only because it had nothing to flag; read-only silently **cannot post**, so a *findings-bearing* read-only run would fail to post → false CLEAN. Fix is `pull-requests: write` + `issues: write` (§ Identity + onboarding reference).
- **Still open:** **Q2** — the `claude_retrigger.sh` `@claude review once` fallback is now exercised (2026-06-11 downstream: the comment trigger fired a fresh review that posted a full verdict) — confirmed working. **Q1** — ANSWERED 2026-06-11 (see the calibration block above): inline findings post as separate single-comment reviews, no shared review id; the comment-id anchor keys correctly either way.

## § calibration update — dual substantive verdicts on one SHA; the skip-no-op is install-dependent (second downstream, 2026-06-11)

A second downstream project falsified the §48 "subsequent pushes auto-skip" model on its install, and the failure it produced is the most dangerous shape yet observed — a **false CLEAN hand-back**:

- **The auto-run does NOT reliably skip.** On this install, every push's `synchronize` auto-run produced a **full substantive review** even after claude had reviewed the PR multiple times. With Phase 3's explicit retrigger also firing, each fix push yielded **two complete, independent reviews of the same head SHA**.
- **Two substantive verdicts on one SHA can DISAGREE.** Observed concretely: the push auto-run posted a findings-bearing review (multiple real correctness findings), then the explicit-retrigger run posted `No issues found` on the **same commit** minutes later. Engine nondeterminism — same diff, opposite verdicts. The newest-summary-wins dedup picked the clean one, the loop reported CLEAN, and the findings were only caught because the human read the PR thread.
- **Adapter/orchestrator rule (supersedes latest-only reading):** treat the engine as DONE only when **all** Actions runs for the head SHA are `completed` AND no claude comment is in the WIP-checklist state; then read **every** substantive claude verdict posted for that SHA. Any findings-bearing verdict with unaddressed findings keeps the engine **STILL_FINDING**, even when a newer verdict on the same SHA reads clean. A clean verdict never overrides an earlier findings verdict — findings are addressed by fixes, not by a luckier second roll.
- **Epistemics of disagreement:** a findings-bearing verdict is strong evidence (specific, checkable claims — verify each against source); a clean verdict is weak evidence (absence-of-findings on one sample). When verdicts disagree, the findings verdict wins by default.
- **Why installs differ** is unresolved — candidate variables: `claude-code-action` / `code-review`-plugin version skew between repos, workflow-config differences (the skipping install vs the non-skipping install were set up weeks apart). Until root-caused, treat skip-no-op as an **optimization some installs have**, never as a correctness assumption: the Phase-3 explicit retrigger stays (it's the only guaranteed fresh verdict), and the dual-verdict reading rule above makes the double-run harmless.
- **Adapter implementation** (`find_claude_comments.sh`, IDEA-022 — material-surfacing, not classification): Pass 1 aggregates `STATUS` across **all** head-SHA Actions runs (completed only when every run completed; metadata from the latest) and emits `RUNS=` + `WINDOW_START=` (earliest head-SHA run start). Pass 2b **enumerates** every substantive non-no-op summary with `created_at >= WINDOW_START` (issue comments carry no commit id — the run window IS the SHA scope) and emits `CLAUDE_HEAD_VERDICTS=` / `CLAUDE_VERDICT_IDS=`, plus each verdict body **verbatim** as a `(comment id …, review summary)` material block (oldest-first) — it does **not** classify them findings/clean. The **§ Verdict judge** applies the masking rule over that surfaced set (any unaddressed findings-bearing body keeps the verdict BLOCKING even if a newer same-SHA body reads clean). The structural fail-closed stays in the adapter: `CLAUDE_VERDICT_SET_PROVEN=false` whenever the verdict set is unproven (no run window, blank run timestamps), and the judge is forbidden CLEAN under it. (Pre-IDEA-022 this was a regex `CLAUDE_HAS_FINDINGS` classification + clean-signal suppression — removed; the judge subsumes it.)

## § calibration update — the @-mention TASK SHAPE is a full verdict surface the summary signature missed (mind-vault PR #221 self-dogfood, 2026-07-15)

The §49 note that the explicit retrigger "posts in the @-mention / task format" undersold the consequence: on mind-vault's own install, that shape was **invisible to the adapter for 4 consecutive cycles** while it carried the PR's only outstanding blocking finding.

- **The dual-stream reality.** A retriggered cycle produces TWO parallel claude streams: the push's `claude-code-review.yml` auto-run posts (or skip-no-ops) the `## Code review` summary shape, while the explicit `@claude review` comment is answered by **`claude.yml`** (the @-mention handler) in the **task shape** — `**Claude finished @<user>'s task in <t>**` header, a *model-generated* heading below it (`### Review complete` observed; `### Code Review` seen elsewhere), findings in the body, posted as `claude[bot]`.
- **The leak.** The summary filter is BOTH-AND (login AND `CLAUDE_BODY_SIGNATURES`). The task-shape body contained no "code review" phrase, so it failed the signature → excluded from the summary anchor AND from the Pass 2b head-SHA verdict enumeration. Observed sequence on PR #221: cycles 1–2 the coexisting auto-run summary said "No issues found" → judge read CLEAN while the task shape flagged a real `A && B || C` bug; cycles 3–4 no summary posted at all → `CLAUDE_HEAD_VERDICTS=0` → UNPROVEN → the loop declared claude SILENT and handed back. The finding was flagged four times and surfaced zero times; a human caught it in the PR thread.
- **The fix (structural, not heading-matched):** `claude finished` — the ACTION-generated stable header — is now part of `CLAUDE_BODY_SIGNATURES`. Never key the task shape on its model-generated heading (it varies run to run). Regression fixture: `tests/fixtures/claude/task-shape-retrigger/` (clean summary + task-shape finding on one SHA must enumerate `CLAUDE_HEAD_VERDICTS=2`).
- **Interaction with § progress comments (2026-06-11):** the WIP checklist comment ALSO carries the "Claude finished" header only when done — while working it lacks that header and has unchecked `- [ ]` items. The not-a-verdict markers there are unchanged; a completed task-shape body (header present, boxes checked) is a verdict, a WIP one is RUNNING.
- **Window caveat.** Pass 2b's SHA window is derived from `claude-code-review.yml` runs only. A task-shape response on a PR whose head SHA never ran that workflow (mention-only usage) has no window → UNPROVEN → the fallback surfaces the newest summary as material and the judge is forbidden CLEAN — fail-closed, acceptable. Widening the window source to `claude.yml` runs is deliberately NOT done (that workflow answers arbitrary @-mentions, not just reviews).
