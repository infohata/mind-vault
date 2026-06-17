---
stage: plan
slug: monitor-accelerated-review-loop-wait
created: 2026-06-17
source: ./IDEA-021-monitor-accelerated-review-loop-wait.md
status: ready
project: mind-vault
---

# Monitor-accelerated review-loop Phase 4 wait

## Context

`/review-loop` Phase 4 ("Wait + wake") drives the review-fix-rerun loop's polling. Today it re-invokes the agent via `ScheduleWakeup` on a fixed cadence (180s first poll, then 270s linear). That cadence is blind: it polls whether or not anything changed, and each wake is a full agent re-invocation (context re-read, cache-busting once past the 300s prompt-cache TTL). The Monitor tool — which natively advertises "PR monitoring" as a use case and ships a `gh api ... since=` poll idiom — lets us react to engine events as they land instead. This plan adds a Monitor as a pure accelerator over the existing `ScheduleWakeup` spine, leaving the Phase 4 decision logic untouched.

## Problem Frame

- **Latency.** Up to ~270s elapses between an engine posting a verdict (or a new finding) and the loop noticing it. On a multi-cycle review this compounds across every wait.
- **Waste.** Every wake re-reads the full conversation context even when no engine state changed. At sprint-auto invocation rates (≈18 review cycles per overnight batch) the idle-poll cost is real.
- **Blind spot, not a correctness bug.** The loop is correct today — it just sits dark between polls rather than reacting to events. So the fix must be strictly additive: it cannot weaken the disconnect/compaction resilience the `ScheduleWakeup` spine provides.

## Requirements Trace

- **R1.** On each Phase 4 entry, arm a bounded, **read-only** Monitor that polls the engine adapters and emits exactly one event the moment the loop could make progress, then exits. (IDEA Proposal §1.)
- **R2.** The Monitor must emit on **every** terminal/actionable condition, never go silent on a failure: (a) all engines `DONE` for the tracked head SHA, (b) head SHA changed out-of-band, (c) an engine check-run errored/failed. (IDEA Proposal §1; Monitor "coverage — silence is not success" caveat.)
- **R3.** Keep `ScheduleWakeup` as the resilient backstop, lengthened from 270s to **1200s (20 min)**; whichever of Monitor-event / ScheduleWakeup fires first re-enters unchanged Phase 4 logic. Correctness never depends on the Monitor. (IDEA Proposal §2.)
- **R4.** `max_idle_polls` **20 → 10** (Hard bounds + Phase 4 idle backstop). (IDEA coupled bound change.)
- **R5.** The Monitor is **strictly read-only** — only `find_<engine>_comments.sh` / `gh api` reads, never any `*_retrigger.sh`. Retriggers stay exclusively agent-driven (Phase 1 zero-activity + Phase 3 post-push). (IDEA Hard invariants.)
- **R6.** The Monitor is **explicitly torn down** (`TaskStop`) when the agent re-engages and re-armed fresh each Phase 4 entry — no zombie poller across cycles. (IDEA Hard invariants; WATCHER_HYGIENE Hard Rules 1+2.)
- **R7.** The Phase 4 decision tree, triage tiers, retrigger discipline, and multi-engine sync contract are unchanged. (IDEA Non-goals.)
- **R8.** GitHub API rate-budget stays bounded under concurrent cycles: one **aggregate** Monitor per Phase 4 entry (not N per-engine), polled ≥30s, bounded by per-entry re-arm + mandatory TaskStop so pollers never accumulate (WATCHER_HYGIENE Failure Mode A). (Architect F5.)

## Scope Boundaries

**In scope:**

- `skills/review-loop/SKILL.md` — Phase 4 step 1 (arm Monitor + lengthen backstop), Hard bounds (`max_idle_polls`), and the idle-backstop line in the decision tree.
- New `skills/review-loop/references/MONITOR_ACCELERATION.md` — the Monitor poll-script recipe, trigger conditions, read-only + teardown invariants, and the accelerator-over-spine contract (references-first, per the body-budget convention).
- `skills/review-loop/references/multi-engine-sync.md` — **(F1, must-fix)** line 18 hardcodes the asymmetric-clearance budget as `max_idle_polls × 270s`; both factors change under this plan (20→10, 270→1200). De-number it to reference the Hard-bounds constant + new cadence by name (so the next cadence change touches one site), rather than re-stating literals. Also add the pointer noting the Monitor's "all engines DONE" trigger is this sync gate's event form.
- CHANGELOG + `.claude-plugin/plugin.json` version bump (handled at `/wrap`, noted here for traceability).

**Out of scope:**

- The `commands/review-loop.md` thin wrapper (no behavioural change to the entry contract).
- Per-engine adapter scripts (`find_*`, `*_retrigger.sh`) — the Monitor reuses them as-is; no signature change.
- sprint-auto's own `run_in_background` review watchers — they already follow WATCHER_HYGIENE; this plan does not refactor them (a possible follow-on).

**Explicit non-goals:**

- Replacing `ScheduleWakeup` outright (a pure-Monitor loop dies with the session on hard disconnect — rejected in brainstorming; user runs review-loop from mixed/sometimes-local contexts).
- Making the Monitor triage, fix, or retrigger anything — it only signals "make progress now."
- Changing the CLEAN/STILL_FINDING verdict logic, which stays the agent's sole authority on re-entry.

## Context & Research

### Existing code and patterns to reuse

- `skills/review-loop/SKILL.md` Phase 4 (lines ~175-197) — the wait/wake loop being amended; `ScheduleWakeup(delaySeconds=180…270, prompt="/<reentry_command> <PR> <ENGINES>")` is the spine to keep.
- `skills/review-loop/SKILL.md` § Hard bounds — `max_idle_polls = 20` lives here and is referenced again in the Phase 4 decision tree's idle backstop; both must change to 10 in lockstep.
- `tools/find_<engine>_comments.sh` — the read-only adapters the Monitor script calls; their marker contract (`<ENGINE>_CHECKRUN=… STATUS=…`, `<ENGINE>_LATEST_REVIEW=…`) is what the poll script greps to compute per-engine state. Documented in `references/engine-adapter-contract.md`.
- `skills/work/references/WATCHER_HYGIENE.md` — **load-bearing.** Hard Rule 1 (explicit stop on supersede), Rule 2 (explicit stop when reason-to-poll resolves), Rule 4 (`cd` inside the loop body — the `find_*` scripts auto-detect repo via `git rev-parse --show-toplevel`), Rule 5 (avoid self-matching `pgrep -f` — N/A here since we poll `gh api`, not the process table). Phase 4 already declares itself a watcher "in the WATCHER_HYGIENE sense" — this plan makes the Monitor obey it concretely.
- `references/multi-engine-sync.md` — the "wait for slowest engine per SHA" contract; the Monitor's "all engines DONE" trigger is exactly its event encoding.

### Institutional learnings

- `mind-vault` memory — review-loop `reentry_command` must be channel-matched (`mv:review-loop` on plugin channel); the Monitor's emitted event re-enters via the same `ScheduleWakeup` prompt path, so no new channel concern, but the plan must not duplicate the re-entry token in two places.
- Monitor tool contract (this session) — `persistent: true` for session-length; bounded `timeout_ms` (max 3600000) otherwise; "monitors producing too many events are auto-stopped" → the poll script must be selective (emit once, then exit), and "silence is not success" → cover failure states (R2).

### External references

- Monitor tool schema — poll-loop idiom (`since=$last`, `|| true` on transient curl/gh failure, 30s+ cadence for remote APIs, `--line-buffered` on any filter stage). The recipe in `MONITOR_ACCELERATION.md` will follow it.

## Key Technical Decisions

- **Accelerator over an unchanged spine.** Monitor + long `ScheduleWakeup`, not Monitor-only. Preserves every disconnect/compaction guarantee; the Monitor is pure latency/cost upside that can fail without breaking correctness. (Settled in brainstorming, resilience answer = "mixed / sometimes local".)
- **Single-purpose, sync-aware trigger.** The poll script emits on the exact condition Phase 4 waits for — all engines `DONE` for the head SHA — plus the two safety events (SHA-change, engine-error). It does NOT try to detect mid-flight per-finding deltas: in sync mode findings only matter once the slowest engine finishes, so "wake when slowest is done" is both the simplest and the correct trigger. Keeps the sync logic from being duplicated/divergent between script and decision tree — the script's job is only "worth looking now"; the agent remains the authority.
- **Bounded Monitor, explicit teardown is the GC.** Use a bounded `timeout_ms` (e.g. 1200000, matching the backstop) rather than `persistent: true`, AND `TaskStop` on re-engage. Per WATCHER_HYGIENE, explicit-stop is the real GC mechanism; the timeout is just belt-and-suspenders. (Note: WATCHER_HYGIENE Hard Rule 3 forbids wall-clock timeouts on *test-running* watchers because they kill long suites — a review-poll Monitor is not gating a long compute job, so a backstop timeout is acceptable here; the plan calls this distinction out explicitly so a reader doesn't think Rule 3 is being violated.)
- **`cd` pinned inside the poll loop.** The `find_*` scripts resolve the repo from cwd; per WATCHER_HYGIENE Rule 4 the script `cd`s to the repo root at the top of each iteration so it survives subshell boundaries / worktree cwd moves.
- **References-first body discipline.** The Monitor recipe (script template, ~40-60 lines) lands in a new `references/MONITOR_ACCELERATION.md`; SKILL.md Phase 4 gains only a few lines pointing at it. Keeps the SKILL.md body under budget (matches IDEA-002/007 debloat precedent). Write the reference **loop-agnostic** (engine/orchestrator-neutral) so sprint-auto's S3/S6/S11.10/S13 review watchers can later adopt it by citation, not rewrite (nice-to-have, architect PASS 1).
- **Frozen arm-time SHA for the sha-change trigger (F3, must-fix).** The Monitor's sha-change condition is `live $(git rev-parse HEAD) != ARM_SHA`, where `ARM_SHA` is frozen into the script at arm time — NOT a comparison of two live reads (which move together and never diverge). This mirrors SKILL.md Phase 4 step 3's frozen-baseline discipline (`scratch last_push_sha` vs live HEAD) exactly, so the two cannot drift.
- **TaskStop is the GC, and it runs first on every wake (F3, must-fix).** Unconditional `TaskStop` of the current Monitor is the **mandatory first action of every Phase 4 wake**, ordered *before* the re-fetch, regardless of whether a Monitor event or the ScheduleWakeup backstop woke the agent. The emit-once-then-exit contract is belt; explicit TaskStop is the real GC (WATCHER_HYGIENE Hard Rule 2 — exit-condition self-clean is bug-prone). Re-arm fresh only if the decision tree keeps the loop in Phase 4.
- **A vanished Monitor is a silent no-op, never a signal (F3, must-fix).** If the Monitor is killed, errors, times out, or is auto-stopped by the platform (the "too many events → auto-stopped" caveat), its absence carries NO meaning — the long ScheduleWakeup remains the sole correctness path and the agent recomputes verdicts from the adapters on wake. The loop must never infer "all-done" from a missing/silent Monitor.
- **Engine-error trigger is a strict subset of the escape-hatch table (F4, should-fix).** The Monitor's "engine-error" emit fires only on `STATUS=completed` with a terminal-error `CONCLUSION` that the existing escape-hatch logic recognizes — explicitly NOT on a clean-but-findings `CONCLUSION=success` (SKILL.md line 64: `CONCLUSION` is a run outcome, never a verdict). The Monitor signals "worth looking"; the agent's escape-hatch logic in `multi-engine-sync.md` decides. Keeps the trigger consistent with, and a subset of, that table — no verdict semantics in the watcher.
- **HUNG-detection latency on the Monitor-dead path (F2, should-fix).** With the Monitor absent, the wedged-check-run HUNG detector trips at `idle_polls ≥ 10 × 1200s ≈ 3.3h` (vs ~90 min today). 3.3h is within `max_active_work_minutes = 240` (4h), so the idle-poll HUNG detector still trips before the active-work guard — documented so the two interacting bounds are a decision, not an accident. Acceptable for an overnight sprint-auto batch; the Monitor makes this the rare path anyway.

## Open Questions

- **Q1. Does an emitted Monitor event re-invoke the agent the same way a `ScheduleWakeup` prompt does, including reconstructing the Phase 4 re-entry with the engine list? — RESOLVED (default accepted).**
  - **Resolution:** Treat the Monitor event as a notification that wakes the agent; on wake the agent reads the scratch file (which already holds `engines`, `last_push_sha`, `reentry_command`) and runs Phase 4 exactly as a ScheduleWakeup wake would. The Monitor's stdout line carries a short reason tag (`all-done` / `sha-changed` / `engine-error`) for the log, not control data.
  - **Trade-off:** If a Monitor event does NOT survive context compaction the way a ScheduleWakeup prompt does, the long ScheduleWakeup still fires as backstop — so worst case we lose the acceleration on that one cycle, never correctness. Acceptable; confirm empirically in the dogfood.

- **Q2. Should the Monitor also be armed on a Phase 1 zero-activity (trigger-only) cycle, or only on Phase 4 entry after the engines are in flight? — RESOLVED (default accepted).**
  - **Resolution:** Arm it on any Phase 4 entry (both the post-Phase-3 push and the Phase-1 zero-activity short-circuit both flow into Phase 4) — the trigger conditions are identical regardless of how we got there.
  - **Trade-off:** Slightly earlier arming on the bootstrap path; no downside since the script is read-only and self-exits.

- **Q3. One Monitor watching all engines, or one per engine? — RESOLVED: one aggregate, mirroring the already-aggregate ScheduleWakeup.**
  - **Resolution:** One Monitor whose script loops over the engine list and computes the aggregate "all DONE" condition. This is the same shape the spine already uses: `ScheduleWakeup` fires a **single** wake carrying the full `<ENGINES>` list (SKILL.md:179, 182), and the agent re-fetches every engine and runs the decision tree across the whole set on each wake — there is no per-engine ScheduleWakeup today. So the single-aggregate Monitor is **symmetric with the existing single-aggregate wake**, not a new asymmetry; both wake paths cover all engines in one re-invocation, gated by the slowest (multi-engine sync). Also avoids N parallel pollers double-hitting the GitHub API (R8).
  - **Trade-off:** A per-engine Monitor would give finer-grained "engine X just finished" events, but the loop can't act on a single engine in sync mode anyway, so it'd be wasted wakes — and it would *break* the symmetry with the aggregate spine. Both wake mechanisms stay aggregate by design.

## Execution Sequence

1. **Author `skills/review-loop/references/MONITOR_ACCELERATION.md`** — the recipe (loop-agnostic framing): the accelerator-over-spine contract; the poll-script template (loops over `engines`, `cd`s to repo root each iteration per WATCHER_HYGIENE Rule 4, runs `find_<engine>_comments.sh`, greps `STATUS=`/`CHECKRUN`, computes aggregate all-`DONE`, compares live HEAD against the **frozen `ARM_SHA`** for sha-change, emits one tagged line [`all-done` / `sha-changed` / `engine-error`] + exits, `|| true` on transient gh failure, `--line-buffered`); the read-only invariant (R5 — no `*_retrigger.sh`); the TaskStop-first-on-every-wake GC discipline + vanished-Monitor-is-a-no-op rule (F3) citing WATCHER_HYGIENE Hard Rule 2; the engine-error-as-escape-hatch-subset definition (F4, never off `CONCLUSION`); the timeout-vs-test-watcher distinction scoped narrowly to read-only API pollers; the single-aggregate-Monitor + API-budget note (R8, Q3).
2. **Amend `skills/review-loop/SKILL.md` § Hard bounds** — `max_idle_polls = 20` → `10` with a one-line rationale (20-min backstop makes 10 polls ≈ 3.3h wall-clock, within the 240-min active-work guard; Monitor ends most waits on an event).
3. **Amend `skills/review-loop/SKILL.md` Phase 4 step 1** — change the backstop cadence 270s → 1200s; add: (a) "arm a bounded read-only Monitor (see MONITOR_ACCELERATION.md)" — armed **after** the scratch-file bootstrap write so it reads the frozen SHA + engine list from scratch (the Phase-1 zero-activity path mandates that write at SKILL.md line 97; ordering matters); (b) "`TaskStop` the current Monitor as the **first action** of every wake, before re-fetch, unconditional on trigger source." Keep the mandatory `prompt=` ScheduleWakeup form as the spine. Update the decision-tree idle-backstop line (SKILL.md line 193) that references `max_idle_polls`/`270s` to `10`/`1200s`.
4. **Amend `skills/review-loop/references/multi-engine-sync.md` line 18 (F1)** — replace the `max_idle_polls × 270s` literal with a by-name reference to the Hard-bounds constant + the new cadence (de-numbered); add the Monitor-trigger-is-the-sync-gate-event-form pointer.
5. **Add the References entry** for `MONITOR_ACCELERATION.md` in SKILL.md § References.
6. **Self-sweep** (markdownlint on the touched/added `.md`; no code, so no pyflakes) per `RULE_self-sweep-before-push`.
7. **Architect reviewer pass** (this plan, pre-execution) — DONE 2026-06-17 (🟡 → all must/should findings folded in below). Re-review not required for the doc-only fold.
8. Version bump (CHANGELOG `## v5.1.x` section + `plugin.json`) deferred to `/wrap`.

## Verification

- `grep -rn "270" skills/review-loop/` → **recursive** (F1: the constant leaked into `multi-engine-sync.md:18`, which a SKILL.md-only grep misses); zero stray `270` cadence references remain across the whole skill dir (the 300s prompt-cache-TTL mention is fine).
- `grep -rn "max_idle_polls" skills/review-loop/` → every numeric occurrence reads `10` (SKILL.md Hard bounds + decision-tree backstop); `multi-engine-sync.md:18` references the bound by name, not a literal `20`.
- `grep -rn "1200" skills/review-loop/SKILL.md` → backstop is 1200s; the initial 180s first-poll is preserved.
- `skills/review-loop/references/MONITOR_ACCELERATION.md` exists, is linked from SKILL.md § References, and its script template calls only `find_*_comments.sh` / `gh api` (no `*_retrigger.sh` — `grep -L retrigger` / `grep -c retrigger` confirms absence).
- The Monitor script template compares live HEAD against a frozen `ARM_SHA` (F3), not two live reads; TaskStop-first is documented as the wake's opening step.
- `tools/validate-skills` (or the repo's skill validator) passes on `review-loop`.
- markdownlint clean on all touched `.md` files.
- **Behavioural dogfood (hand-back, not in-loop):** run `/review-loop` on a live PR and confirm (a) the Monitor arms and emits an `all-done` event that re-enters Phase 4 faster than 270s, (b) the long ScheduleWakeup still fires if the Monitor is killed, (c) no `*_retrigger.sh` is ever invoked by the watcher. Resolves Q1 empirically.

---

**Status:** ready — architect-reviewed 2026-06-17 (🟡 REQUIRES ABSTRACTION → 2 must-fix + 3 should-fix folded in). Awaiting user approval before `/work`.
