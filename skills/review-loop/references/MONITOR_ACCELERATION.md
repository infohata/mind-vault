# Monitor-accelerated wait — bolt-on accelerator over the ScheduleWakeup spine

The review-loop's Phase 4 wait is driven by a `ScheduleWakeup` re-invocation spine: it survives context compaction and a dropped session, and it is what makes the loop correct. This reference adds a **`Monitor` as a pure accelerator** on top of that spine — it cuts the latency between an engine event and the agent noticing it (from the fixed poll cadence down to ~one poll interval) and avoids burning a full context re-read on every blind wake.

**The accelerator never owns correctness.** If the Monitor is killed, errors, times out, or is auto-stopped by the platform, its absence carries no meaning — the long `ScheduleWakeup` backstop still re-enters Phase 4 and the agent recomputes every engine's state from the adapters. The Monitor is upside that is allowed to fail.

This pattern is written loop-agnostic: any orchestrator that waits on external state via a `ScheduleWakeup` (or equivalent) spine — review-loop here, and sprint-auto's S3/S6/S11.10/S13 review watchers as a future adopter — can arm the same bounded, read-only, emit-once Monitor by citing this file.

## The contract

1. **Read-only.** The poll script calls only `find_<engine>_comments.sh` / `gh api` reads. It MUST NOT invoke any `*_retrigger.sh` — retriggers stay exclusively agent-driven (Phase 1 zero-activity bootstrap + Phase 3 post-push), so billed reviews are never fired by the watcher.
2. **Emit-once, then exit.** The script emits exactly one tagged stdout line the moment the loop could make progress, then exits. One event per Phase 4 entry — not a stream (a chatty Monitor gets auto-stopped by the platform, "too many events").
3. **Aggregate, not per-engine.** One Monitor watches the whole engine set and emits on the aggregate condition. This mirrors the spine: `ScheduleWakeup` already fires a *single* wake carrying the full `<ENGINES>` list (`SKILL.md` Phase 4 step 1), and the agent re-fetches every engine per wake. A per-engine Monitor would emit "engine X finished" events the loop can't act on under multi-engine sync (it waits for the slowest) — wasted wakes, and a needless break from the aggregate-wake symmetry. Also avoids N pollers double-hitting the GitHub API.
4. **The agent is the only authority.** The Monitor signals "worth looking now." Every verdict (CLEAN / STILL_FINDING / HUNG), every triage decision, and the sync gate itself are recomputed by the agent on wake via the unchanged Phase 4 decision tree. The Monitor encodes none of them.

## Trigger conditions — the three events that end the wait

The script emits on the first of these to become true, then exits:

- **`all-done`** — every engine's check-run is `STATUS=completed` for the tracked head SHA. This is exactly the multi-engine sync gate ("wait for the slowest engine") in event form — see [`multi-engine-sync.md`](multi-engine-sync.md).
- **`sha-changed`** — live `git rev-parse HEAD` has diverged from the **frozen arm-time SHA** (an out-of-band push by the user or another process). Compared against the SHA frozen into the script at arm time, NOT two live reads (which move together and never diverge) — this mirrors `SKILL.md` Phase 4 step 3's frozen-baseline new-push detection (`scratch last_push_sha` vs live HEAD) so the two cannot drift.
- **`engine-error`** — an engine reached a **terminal-error** check-run conclusion that the escape-hatch table in [`multi-engine-sync.md`](multi-engine-sync.md) acts on. This is a strict subset of, and must stay consistent with, that table. It is explicitly **NOT** triggered by `CONCLUSION=success` — an engine concludes `success` even when it posted inline findings (`SKILL.md` § "clean is structural": `CONCLUSION` is a run outcome, never a verdict). Firing on success-with-findings would wake the agent into a no-op and risk the auto-stop caveat.

## Poll-script template

Armed with the frozen scratch values substituted in. Follows the Monitor idioms: ≥30s cadence for a remote API, `|| true` on transient failure, `cd` pinned inside the loop ([`../../work/references/WATCHER_HYGIENE.md`](../../work/references/WATCHER_HYGIENE.md) Hard Rule 4 — the `find_*` scripts auto-detect the repo from cwd).

```bash
#!/usr/bin/env bash
# review-loop Phase 4 accelerator — READ-ONLY. Emits ONE event, then exits.
# Substituted at arm time from the scratch file; all values FROZEN for this entry.
set -uo pipefail

REPO_ROOT="__REPO_ROOT__"      # repo toplevel, frozen at arm time
PR="__PR_NUMBER__"
ARM_SHA="__ARM_SHA__"          # scratch `last_push_sha` at arm time — the frozen baseline
ENGINES="__ENGINES__"          # comma-separated, from scratch `engines`
POLL_INTERVAL=30               # ≥30s — remote API, rate-limit-friendly

while true; do
  cd "$REPO_ROOT" || { sleep "$POLL_INTERVAL"; continue; }   # Rule 4: cd INSIDE the loop

  # (sha-changed) live HEAD diverged from the frozen arm-time baseline
  live_sha=$(git rev-parse HEAD 2>/dev/null || echo "$ARM_SHA")
  if [ "$live_sha" != "$ARM_SHA" ]; then
    echo "sha-changed: HEAD now $live_sha (armed at $ARM_SHA)"; exit 0
  fi

  all_done=1
  IFS=',' read -ra ENG <<< "$ENGINES"
  for e in "${ENG[@]}"; do
    out=$(./tools/find_${e}_comments.sh "$PR" 2>/dev/null || true)   # read-only; tolerate transient failure
    line=$(printf '%s\n' "$out" | grep -E "^$(printf '%s' "$e" | tr a-z A-Z)_CHECKRUN=" | head -1)
    status=$(printf '%s' "$line" | sed -n 's/.* STATUS=\([^ ]*\).*/\1/p')
    concl=$(printf '%s'  "$line" | sed -n 's/.* CONCLUSION=\([^ ]*\).*/\1/p')

    # (engine-error) terminal-error conclusions the escape-hatch table acts on —
    # NEVER `success` (success-with-findings is the normal all-done path).
    # Keep this set aligned with multi-engine-sync.md's escape-hatch table.
    case "$concl" in
      failure|cancelled|timed_out|action_required)
        echo "engine-error: $e CONCLUSION=$concl"; exit 0 ;;
    esac

    [ "$status" = "completed" ] || all_done=0
  done

  # (all-done) every engine completed for the tracked head SHA — the sync gate, met
  if [ "$all_done" -eq 1 ]; then
    echo "all-done: every engine completed for $ARM_SHA"; exit 0
  fi

  sleep "$POLL_INTERVAL"
done
```

Arm it via `Monitor` with a bounded `timeout_ms` matched to the backstop (e.g. `1200000`), NOT `persistent: true` — see § Lifecycle. `description` should name the PR (`"PR #<N> review engines"`), per the Monitor "specific description" guidance.

## Lifecycle — arm, GC, and the vanished-Monitor rule

- **Arm after the scratch bootstrap write.** The script reads its frozen `ARM_SHA` and engine list from the scratch file's `last_push_sha` / `engines`. On the Phase 1 zero-activity path the scratch bootstrap write is mandatory *before* Phase 4 (`SKILL.md` Phase 1 § "Zero engine activity"); arm the Monitor only **after** that write, never before, or it freezes stale values.
- **`TaskStop` is the GC, and it runs first on every wake.** Unconditionally `TaskStop` the current Monitor as the **first action of every Phase 4 wake** — before the re-fetch, regardless of whether a Monitor event or the `ScheduleWakeup` backstop woke the agent. The emit-once-then-exit contract is the belt; the explicit stop is the real garbage collection ([`../../work/references/WATCHER_HYGIENE.md`](../../work/references/WATCHER_HYGIENE.md) Hard Rule 2 — exit-condition self-clean is bug-prone; a future edit that breaks the exit condition would otherwise leave a zombie poller, Failure Mode D). Re-arm a fresh Monitor only if the decision tree keeps the loop in Phase 4.
- **A vanished Monitor is a silent no-op — never a signal.** If the Monitor is killed, errors out, hits its timeout, or is auto-stopped by the platform, its absence means nothing. The agent must never infer `all-done` (or any state) from a missing or silent Monitor — the long `ScheduleWakeup` backstop remains the sole correctness path and the agent recomputes state from the adapters on its next wake.

## Why a bounded `timeout_ms` here does NOT violate WATCHER_HYGIENE Hard Rule 3

[`WATCHER_HYGIENE.md`](../../work/references/WATCHER_HYGIENE.md) Hard Rule 3 forbids wall-clock timeouts on watcher loops — but that rule is scoped to **test-running watchers**, where a timeout small enough to garbage-collect is small enough to kill a legitimately-long (30+ min) test suite (its provenance is a 5h45m test shell). A read-only PR poller gates **no long compute job**: its emit-once-and-exit contract means a bounded `timeout_ms` only ever kills a *stuck* poller, which is the desired GC, not collateral damage. So here the timeout is acceptable as belt-and-suspenders behind the primary explicit-`TaskStop` GC. This carve-out is narrow: it applies to read-only API pollers only, never to test/build watchers.

## Scaling — GitHub API budget

One aggregate Monitor per Phase 4 entry, polled at ≥30s, bounded by per-entry re-arm + mandatory `TaskStop` (above), keeps poller count to one-per-active-loop. This is what bounds API consumption under sprint-auto's concurrent review cycles — without the per-entry re-arm + explicit stop, watchers accumulate and double-poll ([`WATCHER_HYGIENE.md`](../../work/references/WATCHER_HYGIENE.md) Failure Mode A). The aggregate (not per-engine) choice keeps it at one `find_*` sweep per interval rather than N.
