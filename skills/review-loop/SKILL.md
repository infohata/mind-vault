---
name: review-loop
description: Drive a bounded-autonomy review-fix-rerun loop against one or more pluggable review engines (Cursor Bugbot, GitHub Copilot, future N-engines) on a PR. Triages findings into Tier 1 / 2 / 3, batches per-cycle fixes into single commits, retriggers engines after each push, tracks each engine through a review-state machine (NOT_TRIGGERED → TRIGGERED → RUNNING → DONE) read from its check-run status, treats an engine as clean only when DONE with zero active findings, and hands back to the user with a structured report. Engine-agnostic core; per-engine specifics live in references/engine-<name>.md per the adapter contract.
---

Drive a review-fix-rerun cycle on the given PR using one or more review engines. The orchestrator is engine-agnostic — all engine-specific work routes through adapters described in `references/engine-adapter-contract.md`.

**Inputs**:
- `PR_NUMBER` (optional; defaults to PR for current branch).
- `ENGINES` (one or more of: `bugbot`, `copilot`; defaults to all engines whose adapter is present + retrigger tool is reachable).

This skill is invoked via `commands/review-loop.md` — the single review entry point. Pass `ENGINES` as `bugbot`, `copilot`, or `bugbot,copilot` (any subset); single-engine runs are just a one-element list.

## Hard bounds (enforced by the loop)

- `max_commits_per_session = 20`
- `max_active_work_minutes = 180` (excludes ScheduleWakeup sleep time)
- `max_idle_polls = 20` (consecutive wakes with no new finding AND no new push, across all engines). **New-push detection**: Phase 4 compares the scratch file's `last_push_sha` against `git rev-parse HEAD` on each wake; if they differ (e.g. an out-of-band push by another process or the user), reset `idle_polls=0`, update scratch `last_push_sha`, and re-enter Phase 1 to fetch fresh state for the new SHA. Without this check the counter accumulates forever past a push the loop didn't initiate.
- Targeted tests only inside the loop; broader regression deferred to hand-back
- Feature branch only — never main (per `RULE_git-safety`)
- Batch fixes per cycle into one commit, not one-per-finding
- **Commits**: standard `RULE_git-safety` applies — feature branches are the agent's sandbox, so the loop commits and pushes Tier 1 fixes autonomously. Tier 2 still needs explicit per-finding *fix-direction* approval. Protected-branch guardrails remain in force: never main, never merge into a protected branch, never force-push to protected, never `--no-verify`.

## Multi-engine mode

When `|ENGINES| > 1`, see [`references/dual-engine-sync.md`](references/dual-engine-sync.md) for the synchronisation contract: wait for the slowest engine per push SHA, batch findings from all engines into one fix commit, push once, retrigger all engines, surface asymmetric clearance (one engine clean + another hung) prominently in hand-back.

## Phase 0: Worktree environment bootstrap

**Sprint-auto v3.1 mode — short-circuit**: if `SPRINT_AUTO_INTEGRATION_WORKTREE` is set in the environment, **skip Phase 0 entirely**. Per-IDEA worktrees under sprint-auto v3.1 are pure code surfaces — no `.env`, no docker compose stack. The loop's role in this mode narrows to (a) reading findings via the GitHub API and (b) committing fixes to the per-IDEA branch. When fix-verification runs in Phase 2, it routes to the integration worktree — see [`skills/sprint-auto/references/integration-stage.md`](../sprint-auto/references/integration-stage.md) for the full env-var contract.

**Standalone mode (default)**: if `SPRINT_AUTO_INTEGRATION_WORKTREE` is unset, fall through to the existing worktree-bootstrap logic below.

**Primary working tree** (NOT a worktree — `git rev-parse --git-common-dir` equals `.git`): skip Phase 0 entirely; the primary tree's `.env` and docker stack are assumed to be already provisioned by the user.

**Worktree** (`git rev-parse --git-common-dir` differs from `.git`):

1. If `.env` already exists → skip to step 3 (containers only).
2. Else (`.env` missing):
   - If `.env.template` exists:
     - Copy template → `.env`.
     - Replace any `*_API_KEY=` / `*_TOKEN=` / `*_SECRET=` values with `test-not-a-real-key`.
     - Replace `SECRET_KEY=` with `test-<random-hex>` — generate the literal value via `openssl rand -hex 16` and paste the output. (Do NOT write the literal `$(openssl ...)` form into `.env` — most dotenv loaders don't evaluate shell substitution.)
     - Scope DB/Redis URLs to the worktree's docker compose project namespace.
   - If `.env.template` missing → escalate to user; do not proceed.
3. Spin up containers: `docker compose up -d`.

This is the **only** authorised place to create `.env` — see exception clause in global `CLAUDE.md`.

## Phase 1: Triage

### Per-engine fetch

For each `<engine>` in `ENGINES`, invoke `./tools/find_<engine>_comments.sh [PR_NUMBER]` and parse the output per the contract in [`references/engine-adapter-contract.md`](references/engine-adapter-contract.md). Parse by **anchor-based grep on `^<ENGINE>_<MARKER>=` lines** — NOT positional order — because the actual `find_*_comments.sh` scripts may emit markers in varying orders (e.g. the `*_CHECKRUN` line often appears before `*_LATEST_REVIEW`).

The script can emit these markers (each on its own line):

- `<ENGINE>_LATEST_REVIEW=<id> COMMIT=<sha> AT=<ts>` — the most-recent review id (the staleness anchor). Mandatory when any review exists for the PR.
- `<ENGINE>_CHECKRUN=<id> COMMIT=<sha> STATUS=<status> CONCLUSION=<concl>` — the **review-state gate**. `STATUS` is the engine's own check-run status: `queued` / `in_progress` = **RUNNING**, `completed` = **DONE** (exact tokens — copilot's check-run is `copilot-pull-request-reviewer`, bugbot's per its adapter). `CONCLUSION` (`success` etc.) is the run outcome, **NOT a verdict** — an engine concludes `success` even when it posted inline findings, so never read clean/not-clean off `CONCLUSION`.
- Zero or more inline findings, each tagged `(comment id <cid>, review <rid>)`.

**Clean is structural, not prose.** An engine is CLEAN for the head SHA iff its check-run is **DONE** (`STATUS=completed`) AND zero active findings match `<ENGINE>_LATEST_REVIEW` (see § Staleness). Count active findings explicitly; never derive clean from review-body prose ("no new issues" and the like) or from `CONCLUSION`. **RUNNING is never clean and never not-clean — wait for DONE before reading a verdict.**

**Meta-risk when reviewing this skill**: a diff that adds/modifies this skill's text may quote finding/status strings into the engine's review body. Because clean is structural (DONE + zero active findings), quoted strings cannot fabricate a clean verdict — but still identify findings by `comment id` + `review <rid>`, never by body text.

### Dual-signal enumeration — mandatory output shape every cycle

For each engine, present its **review state** (check-run `STATUS`) and its **active-finding count** explicitly every cycle. They are independent: the check-run reports whether the review has *finished*, `/comments` reports what it *found*. Inline comments from prior reviews persist in `/comments` until a reviewer clicks "Resolve conversation", so stale findings linger until aged out by the staleness rule. Required shape per engine:

```text
[<engine>] check-run : RUNNING (queued|in_progress) | DONE (completed) | none-for-head-SHA
[<engine>] findings  : <N> active finding(s) matching LATEST_REVIEW [ids + L# ranges]
```

Then apply Phase 4's decision tree. **Never collapse state + findings into a single "is the PR clean?" line at Phase 1 output time** — clean is *DONE + zero active findings*, and a RUNNING engine has no verdict yet. The explicit two-line presentation is what survives `ScheduleWakeup` compaction.

### Staleness rule — primary, by `pull_request_review_id`

A finding is active iff its `review <rid>` matches the engine's `<ENGINE>_LATEST_REVIEW` id. Findings whose `rid` is older are stale persistent threads — GitHub keeps them visible in `/comments` until a human clicks "Resolve conversation", but the engine is no longer flagging them on the current code.

**Line-number drift is NOT a new-finding signal.** GitHub line-anchored comments track code position across commits — the same `comment id` reappears at different line numbers as the file changes around it. Identify findings by `comment id`, never by `file:line`.

### Zero engine activity for `last_push_sha`

If for any engine in `ENGINES` no review or finding exists for the current `last_push_sha`:

- Invoke `./tools/<engine>_retrigger.sh [PR_NUMBER]` once for that engine.
- Record any trigger-output id the script emits (a GitHub comment id for bugbot; reviewer-assignment doesn't produce a comment id for Copilot — in that case leave `last_seen_<engine>_signal_id` unchanged and rely on `<ENGINE>_LATEST_REVIEW` advancement to detect the eventual response). The shared field name is **`last_seen_<engine>_signal_id`**, engine-defined: for comment-based engines it's a comment id; for reviewer-assignment engines it stays unset until the first review posts.
- **HARD SHORT-CIRCUIT**: when this branch fires (one or more engines had zero activity and got triggered this cycle), **SKIP the triage tier classification step AND SKIP Phase 2 AND SKIP Phase 3 entirely. Jump directly to Phase 4** after writing the scratch-file bootstrap below. The "then enter Phase 4" wording is a control-flow directive, not a soft suggestion — Phase 2/3 must NOT execute on a trigger-only cycle, because there are no findings to triage and no fixes to commit. Going through Phase 2/3 on a trigger-only cycle risks the agent fabricating "findings" to fix or committing empty.
- **Scratch-file bootstrap is still required** on the trigger-only cycle: write `engines`, `last_push_sha`, and the per-engine `<engine>_review_state` (set to `TRIGGERED`), plus `last_seen_<engine>_signal_id` if the trigger script emitted a comment id. Without these, Phase 4's wake-loop can't construct the resume prompt's engine list and can't compare against `last_push_sha` for new-push detection — the scratch is what Phase 4 reads after compaction.
- **Guardrail**: trigger only when the engine has no check-run for the head SHA (state `NOT_TRIGGERED`). **Never** retrigger while a check-run is `RUNNING`, nor on a bare wake-poll — a retrigger happens exactly twice in a SHA's life: this zero-activity bootstrap, or Phase 3 after a fix push. Engines are rate-limited and each review is billed.

**Under multi-engine mode** the per-engine zero-activity branch above does NOT permit fixing findings from engines that are already `DONE` while a sibling engine is still `TRIGGERED`/`RUNNING` — that violates the dual-engine sync rule (see [`references/dual-engine-sync.md`](references/dual-engine-sync.md)). Instead, the orchestrator waits for the slowest engine to reach `DONE` for `last_push_sha` before batching fixes from all engines and pushing. The escape hatches in `dual-engine-sync.md` § Trade-off escape hatch govern when to break sync (engine stalled past N× normal latency, service-errored consecutively, etc.) — those, not "this engine has findings now", are the only valid reasons to push mid-cycle while another engine is still RUNNING.

### Triage tier classification

For each active finding (across all engines), classify into a tier:

- **Tier 1 — Auto-fix**: matches a codified pattern in the engine's adapter (see `references/engine-<engine>.md` § Common Patterns), touches ≤1 file, targeted test exists.
- **Tier 2 — Approve-then-fix**: actionable but uncodified, OR touches shared helper/mixin.
- **Tier 3 — Escalate**: cross-file, architectural, conflicts with project convention, OR engine self-withdrew.

For every Tier 1 and Tier 2 finding, write a one-sentence justification: *why is this actually a bug?* If the explanation is hand-wavy or just paraphrases the bot → drop to Tier 3.

### Scratch-file persistence

Persist to `~/.claude/memory/projects/<project-slug>/review-loop-pr-<N>.md` (engine-agnostic filename) so the next wake cycle can reload state without re-reading summaries. **Supersedes the older per-engine `bugbot-pr-<N>.md` / `copilot-pr-<N>.md` scratch paths** from the pre-shared-core single-engine wrappers. When migrating a project off those, drop the per-engine scratch files; the shared file holds all engines' state. The scratch file must checkpoint every piece of state that a hard bound depends on, after every mutation:

- `commits_this_session` (int, /20)
- `active_work_minutes` (int, /180; best-effort)
- `idle_polls` (int, /20)
- `engines` (comma-separated list of active engines for this session)
- `last_push_sha`
- `no_progress_map` — **always namespaced per engine** (uniform across single-engine and multi-engine modes): `{ bugbot: {<category>: <count>} }` for a bugbot-only run, `{ copilot: {<category>: <count>} }` for copilot-only, `{ bugbot: {...}, copilot: {...} }` for dual-engine. Flat (un-namespaced) maps from pre-shared-core sessions must be migrated to the per-engine shape on first wake — otherwise Phase 4's no-progress guard reads the wrong slot and never trips.

Per-engine state slots (replicate the pattern for each engine in `engines`):

- `<engine>_review_state` — `NOT_TRIGGERED` | `TRIGGERED` (fired, no check-run yet) | `RUNNING` (check-run `queued`/`in_progress`) | `DONE` (check-run `completed`), for the current `last_push_sha`.
- `last_seen_<engine>_review` — `<id> @ <sha>` (the LATEST_REVIEW last acted on; staleness anchor for new-finding detection).
- `last_seen_<engine>_signal_id` — engine-defined: comment id for comment-based engines (bugbot); unset for reviewer-assignment engines (Copilot) until the first review posts. Tracked so Phase 4's "new findings since" comparison doesn't misread the loop's own trigger as a finding.

Plus the per-cycle triage table (findings + tier + justification + outcome).

If any of these live only in conversation context, they will be summarised away across `ScheduleWakeup` boundaries and the hard bounds become unenforceable.

## Phase 2: Execute

For each Tier 1 finding (no prompt) and each Tier 2 finding (after explicit `yes` from user):

1. Apply the edit.
2. **Audit newly-reachable code** when the edit REMOVES a short-circuit. See [`skills/work/references/AUDIT_NEWLY_REACHABLE_CODE.md`](../work/references/AUDIT_NEWLY_REACHABLE_CODE.md) for the audit procedure. Fold same-file / tightly-coupled latents into the same Phase 3 commit; cross-file latents land as a follow-on commit on the same branch.
3. Run targeted test (`make test-fresh ARGS="app.tests.ClassName"` or project equivalent) — class scope only. **Verification routing — see § "Sprint-auto v3.1 verification routing" below for the env-var-driven mode.**
4. If test fails: revert edit, log to scratch file, move to next finding (do not retry-fix in the same cycle).

Tier 3 findings: skip the fix, log to the scratch file, continue. List all Tier 3 escalations in the final hand-back.

### Sprint-auto v3.1 verification routing

Under sprint-auto v3.1 (`SPRINT_AUTO_INTEGRATION_WORKTREE` is set), step 3's targeted test does NOT run in the per-IDEA worktree (which is code-surface only with no `.env` or docker stack). The **test command's location** changes — the edit-then-test contract per finding is unchanged, and Phase 3's "one commit per cycle" batching still applies.

The test routes to the integration worktree's docker stack via `pushd "$SPRINT_AUTO_INTEGRATION_WORKTREE" && docker compose exec -T web pytest <targeted path>`. The per-IDEA worktree must expose its in-progress edits to the integration worktree's containers before the test runs — the contract is project-specific (rsync-with-exclude, bind-mount, or a `tools/sprint-auto-hooks.sh` hook). Projects that can't satisfy mid-cycle routing fall back to: apply the edit, skip the targeted test, rely on the next bugbot/copilot retrigger cycle to surface regressions via review.

When `SPRINT_AUTO_INTEGRATION_WORKTREE` is unset (standalone mode), step 3 runs the targeted test against the current worktree's stack — no behaviour change.

**Phase 3 is unchanged in v3.1**: at the end of each cycle, all successfully-applied fixes still batch into ONE commit, push once, retrigger each engine once after the push. The v3.1 routing only affects WHERE the test runs, NOT WHEN the commit happens.

## Phase 3: Commit + push + per-engine retrigger

**Skip condition**: if zero fixes were applied (all findings Tier 3, or all reverted on test failure), skip Phase 3 AND Phase 4 — hand back immediately with Tier 3 escalations surfaced.

If at least one fix was applied:

1. **One commit per cycle**, not per finding.
   - Format: `fix(scope): address review N (PR #M)` — under multi-engine mode the body lists all findings closed across engines.
2. `git push origin HEAD`, then **update scratch `last_push_sha` to the new HEAD**. Phase 4's new-push detection compares against it — without this update the loop reads its *own* push as an out-of-band change next wake, resets every engine to `NOT_TRIGGERED`, and double-retriggers (wasting billed reviews).
3. **Retrigger** — for each `<engine>` in `ENGINES` (iterated **alphabetically** for reproducibility, matching [`references/dual-engine-sync.md`](references/dual-engine-sync.md) § Retrigger discipline): fire `./tools/<engine>_retrigger.sh [PR_NUMBER]` once and set `<engine>_review_state=TRIGGERED`. No interval, no defer — the push just created a new SHA, so there is no in-flight review for it to stack behind. (A retrigger is withheld in exactly one situation — Phase 4's `RUNNING` state — which Phase 3 never hits, because a fix push always supersedes any prior SHA's review.)

4. Increment `commits_this_session`. If ≥ 20 → stop and hand back.

## Phase 4: Wait + wake

The wake-loop in this phase IS a watcher in the [`skills/work/references/WATCHER_HYGIENE.md`](../work/references/WATCHER_HYGIENE.md) sense: orchestrator-armed, supersede-able, never wall-clock-timeout-bound. Apply that reference's discipline.

1. `ScheduleWakeup(delaySeconds=180, prompt="/review-loop <PR_NUMBER> <ENGINES>")` for the first poll on **any** Phase 4 entry (after a Phase 3 fix push OR a Phase 1 zero-activity trigger). Subsequent polls use a linear 270s cadence (cache-warm under the 300s prompt-cache TTL). **The `prompt` arg is mandatory** — it's what re-enters the loop — and **`<ENGINES>` MUST be the literal comma-separated engine list from the scratch file's `engines` field**, never the placeholder string (a bare `/review-loop <PR>` would default to all available engines, diverging from a subset run).
2. On wake: re-fetch each engine via `./tools/find_<engine>_comments.sh` and recompute each `<engine>_review_state` from its check-run `STATUS` — `queued`/`in_progress` → `RUNNING`; `completed` → `DONE`; no check-run for head SHA → `TRIGGERED` if a trigger already fired this SHA, else `NOT_TRIGGERED`.
3. **New-push detection (run BEFORE the decision tree)**: compare scratch's `last_push_sha` against `git rev-parse HEAD`. If they differ (out-of-band push by another process or the user), reset `idle_polls=0`, update `last_push_sha`, reset every `<engine>_review_state` to `NOT_TRIGGERED`, and re-enter Phase 1 for the new SHA. Without this the counter accumulates past a push the loop didn't initiate.

4. **Decision tree — evaluate in order:**
   - **Guard: `commits_this_session` ≥ 20 OR active-work minutes ≥ 180** → hand back.
   - **Guard: no-progress detector trips** — same finding category flagged 2× across cycles where a commit *attempted* that category (success-or-revert both count), namespaced per engine → hand back.
   - **Any engine `NOT_TRIGGERED`** → fire its retrigger (Phase 1 zero-activity path), set it `TRIGGERED`, `ScheduleWakeup(180s)`.
   - **Any engine `TRIGGERED` or `RUNNING`** (review requested but check-run not yet `completed`) → still in flight: do NOT retrigger, do NOT read a verdict. This is the multi-engine sync gate — **wait for the slowest engine to reach `DONE` before reading any verdict.** Increment `idle_polls`, `ScheduleWakeup(270s)`. `idle_polls ≥ 20` here = a check-run wedged in `queued`/`in_progress` → treat as HUNG, hand back. (This is the sole idle backstop — once every engine is `DONE` the verdict is final and the branches below terminate without further polling.)
   - **[All engines `DONE`] New findings since `last_seen_<engine>_signal_id` (any engine)** → reset `idle_polls=0`, update each engine's `last_seen_<engine>_signal_id` to its newest finding id, reload triage state, return to Phase 1 (which batch-triages every engine's active findings into one fix cycle). Compare against `last_seen_<engine>_signal_id`, not `last_push_sha` — see references/engine-adapter-contract.md.
   - **[All engines `DONE`] No new findings** → terminal hand back, no further polling:
     - **CLEAN** if every engine has zero active findings matching its `LATEST_REVIEW`. (Structural — never inferred from `CONCLUSION` or review-body prose.)
     - else surface the **residual active findings** (already-seen / Tier-3 escalations the loop chose not to fix) and hand back — the loop can't make further progress on this SHA.

## Hand-back report

Always end with:

1. **Engines summary** — per engine: cycles run, findings auto-fixed, findings approved, findings escalated, findings skipped, final verdict (CLEAN / HUNG / ERRORED / STILL_FINDING).
2. **Asymmetric clearance** — if some engines CLEAN and others not, surface prominently. See [`references/dual-engine-sync.md`](references/dual-engine-sync.md) for the message templates.
3. **Tier 3 escalations** with reasoning (need human decision).
4. **Suggested broader regression command** for pre-merge.
5. **PR URL**.

Do not merge. Do not push to main. The loop hands the PR back to the user for final review and merge.

Under sprint-auto v3.1, the "user" the loop hands back to is sprint-auto itself (the orchestrator), which uses the Tier-3 list to drive its escalation cycle. The hand-back semantics are unchanged.

## References

- [`references/engine-adapter-contract.md`](references/engine-adapter-contract.md) — what an engine adapter must implement.
- [`references/engine-bugbot.md`](references/engine-bugbot.md) — Cursor Bugbot adapter.
- [`references/engine-copilot.md`](references/engine-copilot.md) — GitHub Copilot adapter.
- [`references/dual-engine-sync.md`](references/dual-engine-sync.md) — multi-engine synchronisation contract.
- [`references/common-review-findings.md`](references/common-review-findings.md) — shared codified Tier-1 catalogue (engine-agnostic).
- `RULE_git-safety` — feature-branch sandbox, never-merge-to-protected discipline.
- `RULE_self-sweep-before-push` — pyflakes self-sweep between Phase 2 and Phase 3.
