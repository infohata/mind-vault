---
id: 021
title: Monitor-accelerated review-loop Phase 4 wait
status: complete          # idea | in-progress | complete | superseded
priority: medium   # high | medium | low
supersedes: []       # list of IDEA ids this replaces, or []
superseded_by: null
depends_on: []       # list of IDEA ids required before starting, or []
related: [005, 012]             # list of IDEA ids that share context, or []
created: 2026-06-17
completed: 2026-06-17
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false                                     # true | false
auto_safe_reason: "Modifies the core review-loop orchestrator's wait phase with judgment calls (monitor trigger conditions, sync-gate encoding, teardown lifecycle). Needs a human to validate the accelerator never alters the decision tree."
sensitive_paths_cleared: false         # true | false
sensitive_paths_cleared_reason: "Touches skills/review-loop, which every review run and all of sprint-auto depend on — high blast radius orchestration even though no auth/schema/secret paths are involved. A human should eyeball the Phase 4 change."
---

# IDEA-021: Monitor-accelerated review-loop Phase 4 wait

**Status**: ✅ Complete (2026-06-17)
**Priority**: Medium

**Problem** (or opportunity): `/review-loop` Phase 4 waits for engine verdicts via blind fixed-cadence `ScheduleWakeup` polling (180s first poll, then a 270s linear cadence). Two costs: (1) **latency** — up to ~270s between an engine posting a verdict/finding and the loop noticing it; (2) **waste** — every wake is a full context re-read (cache-busting once past the 300s prompt-cache TTL) even when nothing changed. The loop sits blind between polls instead of reacting to events as they land.

**Proposal** (or idea): Keep `ScheduleWakeup` as the **resilient spine** and add a `Monitor` as a pure **accelerator**. The Phase 4 decision logic (re-fetch → recompute per-engine state → decision tree) does **not change** — only what re-invokes the agent during the wait does.

On each Phase 4 entry, arm **both**:

1. A **bounded, read-only** `Monitor` whose poll script (every ~30s) runs the existing `find_<engine>_comments.sh` adapters and **exits the moment the loop could make progress**, emitting one event on any of:
   - all engines reach `DONE` for the tracked head SHA (the multi-engine sync condition — exactly the gate Phase 4 waits on),
   - the head SHA changed out-of-band (user/other-process pushed a fix → re-enter Phase 1 for the new SHA),
   - an engine check-run **errored/failed** (coverage caveat — never go silent on a crash).
2. A **long** `ScheduleWakeup` backstop — **1200s (20 min)** instead of the current 270s — that resumes the loop if the Monitor dies (disconnect, hard process death, monitor timeout) or never fires.

Whichever fires first re-invokes the agent into the unchanged Phase 4 logic. Correctness never depends on the Monitor — if it's gone, the long ScheduleWakeup still drives the loop, preserving every disconnect/compaction guarantee the loop has today.

Coupled bound change: with a 20-min backstop, `max_idle_polls` **20 → 10** (10 idle polls ≈ 3.3h wall-clock; 20 would be absurd, and the Monitor means most waits end on a real event rather than a poll anyway).

**Hard invariants** (the design's safety rails):

- The Monitor is **strictly read-only** — only `find_*_comments.sh` / `gh api` reads, **never** a `*_retrigger.sh`. Retriggers stay exclusively in the agent's hands (Phase 1 zero-activity bootstrap + Phase 3 post-push), so billed reviews are never fired by the watcher.
- The Monitor is **bounded per Phase 4 entry** and torn down (`TaskStop`) when the agent re-engages — re-armed fresh each entry with current scratch values (head SHA, engine list, last-seen ids) baked into the script. No zombie poller across cycles.
- The Monitor is the authority on *nothing* — it only says "worth looking now." The agent re-running the decision tree remains the sole authority on the sync gate and CLEAN/STILL_FINDING verdict.

**Why now**:
- Just dogfooded `/review-loop 206` and felt the fixed-cadence latency directly; the `Monitor` tool natively names "PR monitoring" as a `persistent`/bounded use case with a ready-made `gh api ... since=` poll idiom.
- Inspired by Fable 5 using monitors to actively hunt review comments as they arrived — this ports that "active hunt" feel onto the existing resilient spine without giving up disconnect safety.

**Non-goals**:
- Replacing `ScheduleWakeup` outright (a pure-Monitor loop dies with the session on a hard disconnect — rejected; user runs review-loop from mixed/sometimes-local contexts).
- Changing the Phase 4 decision tree, the triage tiers, the retrigger discipline, or the multi-engine sync contract.
- Making the Monitor smart enough to fix or triage — it only signals "make progress now."

**Related**: [IDEA-005](../archive/2026-05-idea-005-review-loop-shared-core/IDEA-005-review-loop-shared-core.md) (review-loop shared-core orchestrator this amends) · [IDEA-012](../archive/2026-06-idea-012-claude-code-review-engine/IDEA-012-claude-code-review-engine.md) (multi-engine sync + per-engine adapters the Monitor script reuses).
