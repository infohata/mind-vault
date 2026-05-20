---
name: review-loop
description: Drive a bounded-autonomy review-fix-rerun loop against one or more pluggable review engines (Cursor Bugbot, GitHub Copilot, future N-engines) on a PR. Triages findings into Tier 1 / 2 / 3, batches per-cycle fixes into single commits, retriggers engines with spacing discipline, and hands back to the user with a structured report. Engine-agnostic core; per-engine specifics live in references/engine-<name>.md per the adapter contract.
---

Drive a review-fix-rerun cycle on the given PR using one or more review engines. The orchestrator is engine-agnostic — all engine-specific work routes through adapters described in `references/engine-adapter-contract.md`.

**Inputs**:
- `PR_NUMBER` (optional; defaults to PR for current branch).
- `ENGINES` (one or more of: `bugbot`, `copilot`; defaults to all engines whose adapter is present + retrigger tool is reachable).

This skill is invoked from three command surfaces:
- `commands/review-loop.md` — direct multi-engine entry (`ENGINES=bugbot,copilot` or any subset).
- `commands/bugbot-loop.md` — thin wrapper, `ENGINES=bugbot`.
- `commands/copilot-loop.md` — thin wrapper, `ENGINES=copilot`.

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

For each `<engine>` in `ENGINES`, invoke `./tools/find_<engine>_comments.sh [PR_NUMBER]` and parse the output per the contract in [`references/engine-adapter-contract.md`](references/engine-adapter-contract.md). Parse by **anchor-based grep on `^<ENGINE>_<MARKER>=` lines** — NOT positional order — because the actual `find_*_comments.sh` scripts may emit markers in varying orders (e.g. `*_CLEAN_SIGNAL` and `*_CHECKRUN` lines often appear before `*_LATEST_REVIEW`).

The script can emit these markers (each on its own line):

- `<ENGINE>_LATEST_REVIEW=<id> COMMIT=<sha> AT=<ts> CLEAN=<bool>` — the most-recent review id (the staleness anchor). Mandatory when any review exists for the PR.
- `<ENGINE>_CLEAN_SIGNAL=<id> COMMIT=<sha> AT=<ts>` — present iff the most-recent review is classified clean (body-text match OR check-run synthesis — see the engine adapter's § Clean-signal parsing for details and false-positive caveats).
- `<ENGINE>_CHECKRUN=<id> ...` — informational, present when a check-run for this engine exists on `last_push_sha`.
- Zero or more inline findings, each tagged `(comment id <cid>, review <rid>)`.

**Always count active findings explicitly before claiming CLEAN** — the `<ENGINE>_CLEAN_SIGNAL` line is input to Phase 4's decision tree, not an authoritative verdict. The new-findings branch precedes the clean-signal branch precisely so that synthesized false-positive CLEAN signals can be overridden by actual findings.

**Meta-risk when reviewing this skill**: review-loop's docs contain literal mentions of `"found no new issues"`, `BUGBOT_CLEAN_SIGNAL`, `COPILOT_CLEAN_SIGNAL`, etc. Bugbot or Copilot reviewing a diff that adds/modifies this skill's text may quote those strings into their review body — which could re-trigger the body-text matcher's "found no new issues" check, producing a CLEAN signal whose source is the diff content, not the engine's actual verdict. When dogfooding this skill on its own changes, count active findings explicitly and be skeptical of CLEAN signals whose review body quotes the diff.

### Dual-signal enumeration — mandatory output shape every cycle

For each engine, present both signals explicitly in the cycle summary, even when one is absent. The two GitHub resources (`/reviews` for the clean signal, `/comments` for inline findings) are **independent and can coexist for the same commit** — an engine may post an overall "found no new issues" review AND one or more inline LOW-severity hints on the same push. Inline comments from prior reviews also persist in `/comments` until a reviewer manually clicks "Resolve conversation", so a stale-by-fix finding can linger alongside a fresh clean signal. Required shape per engine:

```text
[<engine>] /reviews  : ✅ CLEAN signal <review-id> @ <sha> OR ❌ no signal for current head
[<engine>] /comments : <N> active finding(s) [list with ids + L# ranges]
```

Then apply Phase 4's decision tree. **Never collapse the two signals into a single "is the PR clean?" conclusion at Phase 1 output time.** Phase 4's tree handles the collapse correctly (new-findings branch precedes clean-signal branch), but only if Phase 1's output surfaces both resources independently per engine. Context-rot during `ScheduleWakeup` sleeps tends to re-merge signals; the explicit dual presentation is what survives compaction.

### Staleness rule — primary, by `pull_request_review_id`

A finding is active iff its `review <rid>` matches the engine's `<ENGINE>_LATEST_REVIEW` id. Findings whose `rid` is older are stale persistent threads — GitHub keeps them visible in `/comments` until a human clicks "Resolve conversation", but the engine is no longer flagging them on the current code.

**Line-number drift is NOT a new-finding signal.** GitHub line-anchored comments track code position across commits — the same `comment id` reappears at different line numbers as the file changes around it. Identify findings by `comment id`, never by `file:line`.

### Zero engine activity for `last_push_sha`

If for any engine in `ENGINES` no review or finding exists for the current `last_push_sha`:

- Invoke `./tools/<engine>_retrigger.sh [PR_NUMBER]` once for that engine.
- Record any trigger-output id the script emits (a GitHub comment id for bugbot; reviewer-assignment doesn't produce a comment id for Copilot — in that case leave `last_seen_<engine>_signal_id` unchanged and rely on `<ENGINE>_LATEST_REVIEW` advancement to detect the eventual response). The shared field name is **`last_seen_<engine>_signal_id`**, engine-defined: for comment-based engines it's a comment id; for reviewer-assignment engines it stays unset until the first review posts.
- Do NOT proceed to Phase 2/3 this cycle for that engine — there's nothing to fix yet.
- **Then enter Phase 4** to poll for the eventual review. The trigger is in flight; Phase 4's wake-loop is what catches the response.
- **Guardrail**: only post the trigger when zero activity exists for the current push SHA. Don't re-trigger on every invocation; engines are rate-limited and each review is billed.

**Under multi-engine mode** the per-engine zero-activity branch above does NOT permit fixing findings from engines that DO have activity while a sibling engine is still pending — that violates the dual-engine sync rule (see [`references/dual-engine-sync.md`](references/dual-engine-sync.md)). Instead, the orchestrator waits for the slowest engine to produce a verdict for `last_push_sha` (findings OR clean-signal) before batching fixes from all engines and pushing. The escape hatches in `dual-engine-sync.md` § Trade-off escape hatch govern when to break sync (engine stalled past N× normal latency, service-errored consecutively, etc.) — those, not "this engine has findings now", are the only valid reasons to push mid-cycle while another engine is pending.

### Triage tier classification

For each active finding (across all engines), classify into a tier:

- **Tier 1 — Auto-fix**: matches a codified pattern in the engine's adapter (see `references/engine-<engine>.md` § Common Patterns), touches ≤1 file, targeted test exists.
- **Tier 2 — Approve-then-fix**: actionable but uncodified, OR touches shared helper/mixin.
- **Tier 3 — Escalate**: cross-file, architectural, conflicts with project convention, OR engine self-withdrew.

For every Tier 1 and Tier 2 finding, write a one-sentence justification: *why is this actually a bug?* If the explanation is hand-wavy or just paraphrases the bot → drop to Tier 3.

### Scratch-file persistence

Persist to `~/.claude/memory/projects/<project-slug>/review-loop-pr-<N>.md` (engine-agnostic filename) so the next wake cycle can reload state without re-reading summaries. **Supersedes the older per-engine `bugbot-pr-<N>.md` / `copilot-pr-<N>.md` paths** that pre-shared-core `AGENT_bugbot.md` / `AGENT_copilot.md` referenced. When migrating a project from the old wrappers, drop the per-engine scratch files; the shared file holds all engines' state. The scratch file must checkpoint every piece of state that a hard bound depends on, after every mutation:

- `commits_this_session` (int, /20)
- `active_work_minutes` (int, /180; best-effort)
- `idle_polls` (int, /20)
- `engines` (comma-separated list of active engines for this session)
- `last_push_sha`
- `no_progress_map` — under multi-engine mode, namespaced per engine: `{ bugbot: {<category>: <count>}, copilot: {<category>: <count>} }`

Per-engine state slots (replicate the pattern for each engine in `engines`):

- `last_seen_<engine>_review` — `<id> @ <sha> CLEAN=<bool>`
- `last_seen_<engine>_signal_id` — engine-defined: comment id for comment-based engines (bugbot); unset for reviewer-assignment engines (Copilot) until the first review posts. Tracked so Phase 4's "new findings since" comparison doesn't misread the loop's own trigger as a finding.
- `last_<engine>_retrigger_at` — ISO-8601 timestamp
- `pending_<engine>_retrigger` — bool, default false

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

**Phase 3 is unchanged in v3.1**: at the end of each cycle, all successfully-applied fixes still batch into ONE commit, push once, retrigger engines once each per the spacing rule. The v3.1 routing only affects WHERE the test runs, NOT WHEN the commit happens.

## Phase 3: Commit + push + per-engine retrigger

**Skip condition**: if zero fixes were applied (all findings Tier 3, or all reverted on test failure), skip Phase 3 AND Phase 4 — hand back immediately with Tier 3 escalations surfaced.

If at least one fix was applied:

1. **One commit per cycle**, not per finding.
   - Format: `fix(scope): address review N (PR #M)` — under multi-engine mode the body lists all findings closed across engines.
2. `git push origin HEAD`.
3. **Retrigger** — for each `<engine>` in `ENGINES` iterated **alphabetically** (deterministic order so behaviour is reproducible regardless of how the caller orders `ENGINES`, matching [`references/dual-engine-sync.md`](references/dual-engine-sync.md) § Retrigger discipline), conditional on the **per-engine** spacing rule:
   - If `last_<engine>_retrigger_at` is unset OR ≥5 min ago: fire `./tools/<engine>_retrigger.sh [PR_NUMBER]`. Update `last_<engine>_retrigger_at` to the post-time. Clear `pending_<engine>_retrigger` if set.
   - Else (last retrigger <5 min ago): do NOT fire now. Set `pending_<engine>_retrigger=true`. The defer for the slow engine does NOT block other engines firing this cycle — each engine is independent.
   - After processing all engines, if any deferred: `ScheduleWakeup(delaySeconds=300, prompt="/review-loop <PR_NUMBER> <ENGINES>")` (or the single-engine wrapper command if invoked via `/bugbot-loop` / `/copilot-loop`). Phase 4's pending-retrigger branch will fire the deferred scripts on the next wake. **The `prompt` arg is mandatory** — without it the harness wake fires but does not re-enter the loop, orphaning the deferred retrigger.

   **Spacing rationale**: engine queues stack — rapid same-engine retriggers don't preempt a pending review, they stack behind it. Field-observed: 4 bugbot retriggers in 10 min stretched per-review latency from ~1-10 min to ~16 min. The rule is **per-engine** — under multi-engine mode firing bugbot + copilot back-to-back is fine (different queues); firing bugbot twice in <5 min is not.

4. Increment `commits_this_session`. If ≥ 20 → before stopping, flush any pending retriggers whose spacing has elapsed (same rule as Phase 4 guard flush), then stop and hand back.

## Phase 4: Wait + wake

The wake-loop in this phase IS a watcher in the [`skills/work/references/WATCHER_HYGIENE.md`](../work/references/WATCHER_HYGIENE.md) sense: orchestrator-armed, supersede-able, never wall-clock-timeout-bound. Apply that reference's discipline.

1. `ScheduleWakeup(delaySeconds=180, prompt="/review-loop <PR_NUMBER> <ENGINES>")` for the first poll on **any** Phase 4 entry — either after a fresh fix-cycle in Phase 3 OR after a Phase 1 zero-activity trigger-only branch (which has no Phase 3 commit but still needs polling to catch the engine's response). Subsequent polls use a linear 270s cadence (cache-warm under the 300s prompt-cache TTL). **The `prompt` arg is mandatory** on every `ScheduleWakeup` in this skill — it's what re-enters the loop. **The `<ENGINES>` placeholder MUST be replaced with the literal comma-separated engine list from the scratch file's `engines` field**, NOT left as a literal placeholder string. A bare `/review-loop <PR>` wake (no engines) would default to all-available engines per `commands/review-loop.md`, diverging from a session that was intentionally invoked with a subset (e.g. `bugbot` only).
2. On wake: re-fetch each engine's state via `./tools/find_<engine>_comments.sh`.
3. **Decision tree — evaluate in order**. The first two branches are absolute hard-bound guards; the third handles deferred retriggers; the rest handle the standard happy-path branches. **All branches must flush pending retriggers before terminating** when applicable — see inline rule on each guard.
   - **Guard: active-work minutes ≥ 180** → before handing back, for each engine, if `pending_<engine>_retrigger=true` and `last_<engine>_retrigger_at` is ≥5 min ago (or unset), fire that engine's retrigger script, update its `last_<engine>_retrigger_at`, clear `pending_<engine>_retrigger`. If `pending_<engine>_retrigger=true` but still inside the spacing window (rare given budget exhaustion implies long elapsed time), surface "PENDING `<ENGINE>` RETRIGGER NOT FIRED — push orphaned at `<last_push_sha>`; run `./tools/<engine>_retrigger.sh <PR>` manually after 5 min from `last_<engine>_retrigger_at`" prominently in the hand-back report. Then hand back.
   - **Guard: no-progress detector trips** — same finding category flagged 2× across cycles where a commit *attempted* that category (success-or-revert both count), namespaced per engine → apply the same pending-retrigger flush rule as the active-work guard above, then hand back.
   - **Pending retrigger from prior defer** — iterate through ALL engines in `ENGINES`, processing each independently:
     - For each engine with `pending_<engine>_retrigger=true` AND `last_<engine>_retrigger_at` ≥5 min ago: fire that engine's retrigger script, update its `last_<engine>_retrigger_at`, clear its `pending_<engine>_retrigger`.
     - For each engine with `pending_<engine>_retrigger=true` AND `last_<engine>_retrigger_at` <5 min ago: leave `pending_<engine>_retrigger=true`. Record the shortest remaining spacing window across all still-pending engines as `min_remaining_wait`.
     - After iterating: if any engine remains pending, `ScheduleWakeup(delaySeconds=min_remaining_wait, prompt="/review-loop <PR_NUMBER> <ENGINES>")` to re-wake when the soonest window elapses, then return without falling through. Otherwise (all pending retriggers fired this wake), continue evaluation (fired retriggers don't immediately produce findings; fall through for *this* wake's verdict).
     - **Why this matters under multi-engine mode**: previous-spec returned immediately when any one engine was still inside its spacing window, skipping the fire-eligible defers for other engines in the same wake. Iterating processes each engine independently so an eligible bugbot retrigger isn't held up by a still-spacing-blocked copilot retrigger.
   - **New findings since `last_seen_<engine>_signal_id` (for any engine)** → reset idle-poll counter to 0, update the per-engine `last_seen_<engine>_signal_id` to the newest finding's id, reload triage state, return to Phase 1. (Compare against `last_seen_<engine>_signal_id`, not `last_push_sha` — see in-line rationale in references/engine-adapter-contract.md.) **This branch must precede the clean-signal branch** because `/reviews` and `/comments` are independent API resources — both can coexist for the same commit if the engine is re-triggered and produces new findings after a prior clean review.
   - **All-engines CLEAN — `<ENGINE>_CLEAN_SIGNAL` present for every engine in `ENGINES` AND its `COMMIT` matches `last_push_sha` (or race-caveat heuristic applies)** → PR clean for current head per all engines → hand back immediately with the clean summary. Do not wait out the idle-poll bound.

     **Race-condition caveat**: clean signal `COMMIT` is the trigger-anchor SHA, not the reviewed SHA. Review takes time (1-10 min for bugbot, ~30s for copilot); during that window a docs / comment / no-content commit may land on the branch. The signal's `COMMIT` reflects trigger-time, not what the engine's scanner inspected. So strict `COMMIT === last_push_sha` may fail even when the verdict factually applies. Apply timestamp tiebreaker: if the review's `AT` is later than the latest commit's push timestamp, treat clean as applying to current HEAD. Practical safer-default: if intervening commits since the signal's `COMMIT` are docs-only / comments-only / no source changes, skip the re-trigger and accept the clean signal.

   - **Some-engines CLEAN, others still working** → increment `idle_polls` (the still-working engine counts toward the idle budget), `ScheduleWakeup(delaySeconds=270, prompt="/review-loop <PR_NUMBER> <ENGINES>")` to keep polling for the working engines. If on a subsequent wake `idle_polls ≥ 20` without the working engines progressing, hand back with the asymmetric-clearance template per [`references/dual-engine-sync.md`](references/dual-engine-sync.md). Skipping the idle-poll increment + wake here would block the `max_idle_polls` backstop and leave the loop hanging indefinitely on a hung engine.
   - **No clean signal, no new findings (across all engines), idle_polls < 20** → increment `idle_polls`, `ScheduleWakeup(delaySeconds=270, prompt="/review-loop <PR_NUMBER> <ENGINES>")`.
   - **No clean signal, no new findings, idle_polls ≥ 20** → escalate: an engine may be hung. Apply pending-retrigger flush rule, then hand back.

## Hand-back report

Always end with:

1. **Engines summary** — per engine: cycles run, findings auto-fixed, findings approved, findings escalated, findings skipped, final verdict (CLEAN / HUNG / ERRORED / STILL_FINDING).
2. **Asymmetric clearance** — if some engines CLEAN and others not, surface prominently. See [`references/dual-engine-sync.md`](references/dual-engine-sync.md) for the message templates.
3. **Pending retriggers NOT fired** (if any) — surface with the exact manual command to run after spacing elapses.
4. **Tier 3 escalations** with reasoning (need human decision).
5. **Suggested broader regression command** for pre-merge.
6. **PR URL**.

Do not merge. Do not push to main. The loop hands the PR back to the user for final review and merge.

Under sprint-auto v3.1, the "user" the loop hands back to is sprint-auto itself (the orchestrator), which uses the Tier-3 list to drive its escalation cycle. The hand-back semantics are unchanged.

## References

- [`references/engine-adapter-contract.md`](references/engine-adapter-contract.md) — what an engine adapter must implement.
- [`references/engine-bugbot.md`](references/engine-bugbot.md) — Cursor Bugbot adapter.
- [`references/engine-copilot.md`](references/engine-copilot.md) — GitHub Copilot adapter.
- [`references/dual-engine-sync.md`](references/dual-engine-sync.md) — multi-engine synchronisation contract.
- [`agents/AGENT_bugbot.md`](../../agents/AGENT_bugbot.md) — bugbot-specific bounded-autonomy policy (codified Tier 1 patterns).
- `RULE_git-safety` — feature-branch sandbox, never-merge-to-protected discipline.
- `RULE_self-sweep-before-push` — pyflakes self-sweep between Phase 2 and Phase 3.
