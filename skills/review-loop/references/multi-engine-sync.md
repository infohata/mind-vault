# Multi-engine synchronisation contract

When `|ENGINES| > 1` in the review-loop invocation, the orchestrator at [`SKILL.md`](../SKILL.md) MUST sync each cycle to avoid double-pushes that invalidate each engine's pending review. Each cycle waits for the slowest engine to reach `DONE` (check-run `completed`) for `last_push_sha`, then batches findings from all engines into ONE fix commit + pushes once + retriggers all engines once each.

The rationale: each push invalidates pending reviews of the prior SHA — without sync, bugbot's pending review of SHA-A becomes stale the moment a copilot-triggered fix lands on SHA-B, forcing bugbot to re-scan from scratch (and vice-versa).

## Trade-off escape hatch — proceed with subset of engines when others stall

Hard "wait for slowest" risks blocking the loop indefinitely if one engine hangs. The orchestrator MUST trip out of strict sync under these conditions:

| Trip | Trigger | Action |
|---|---|---|
| Engine `<X>` stalled | Engine-specific stall condition per the engine's adapter doc § Failure modes (e.g. bugbot `CHECKRUN STATUS=in_progress` >15 min — see [`engine-bugbot.md`](engine-bugbot.md); copilot variants in [`engine-copilot.md`](engine-copilot.md)) | Proceed with other engines' findings if any; retrigger `<X>` post-push. |
| Copilot service-errored 2× consecutive | Copilot review body literally `"Copilot encountered an error..."` on two consecutive HEAD SHAs | Proceed with other engines' findings if any; do NOT retry Copilot in this cycle. |
| Copilot service-errored 3× consecutive | Third consecutive error | Hand back to user — durable service issue, can't resolve from the loop. |
| One engine DONE+clean + another still RUNNING | one engine `DONE` with zero active findings for `last_push_sha` + other engine's check-run still `queued`/`in_progress` past idle-poll threshold | Wait up to `max_idle_polls × 270s`; if the RUNNING engine never reaches `DONE`, hand back with the cleared engine's CLEAN status documented prominently. |

## Sync state — scratch-file fields per engine

Replicate per engine in the loop's scratch file:

```yaml
engines: bugbot,copilot
bugbot_review_state:  NOT_TRIGGERED|TRIGGERED|RUNNING|DONE
copilot_review_state: NOT_TRIGGERED|TRIGGERED|RUNNING|DONE
last_seen_bugbot_review:  <id> @ <sha>
last_seen_copilot_review: <id> @ <sha>
last_seen_bugbot_signal_id:  <id>
last_seen_copilot_signal_id: <id>
no_progress_map:
  bugbot:  { <category>: <count> }
  copilot: { <category>: <count> }
```

Each engine's `<engine>_review_state` is tracked independently — under dual-engine mode one engine can be `DONE` while the other is still `RUNNING`. The orchestrator waits for the slowest to reach `DONE` before reading any verdict (the Phase 4 sync gate).

## Retrigger discipline — different per engine, fired in deterministic order

Phase 3 fires after the batch commit. For each engine in `ENGINES` (deterministic order: alphabetical so behaviour is reproducible):

- For `bugbot`: `./tools/bugbot_retrigger.sh <PR>` (posts a `bugbot run` comment).
- For `copilot`: `./tools/copilot_retrigger.sh <PR>` (`gh pr edit <PR> --add-reviewer @copilot`; Copilot self-removes from `requested_reviewers` post-review so bare `--add` is the canonical retrigger — see [`engine-copilot.md`](engine-copilot.md) § Tool invocations for the still-pending fallback case).

Both retriggers happen post-push and fire once each, back-to-back (different queues, no interval). The orchestrator never retriggers while an engine's check-run is RUNNING, so there is nothing to space out.

## Hand-back when only one engine cleared

A non-trivial fraction of multi-engine runs end with one engine CLEAN and another in a degraded state. The hand-back report MUST distinguish the cases:

- **`bugbot: CLEAN at <sha>` AND `copilot: errored / hung / unavailable`** — the PR has ONE engine's verdict. Surface this prominently:

  ```
  ⚠️  ASYMMETRIC CLEARANCE: bugbot CLEAN at <sha>, copilot errored (3× consecutive service errors).
      Merge decision is yours: (a) merge on bugbot's verdict alone, (b) retry copilot from GitHub UI before merging, or (c) wait for Copilot service recovery.
  ```

- **`copilot: CLEAN at <sha>` AND `bugbot: hung`** — mirror message.
- **`both: CLEAN at <sha>`** — merge-ready summary; no asymmetric-clearance warning.
- **`both: still finding things`** — loop continues; no hand-back yet.

The user always decides; the loop never auto-merges and never escalates an asymmetric clearance into a silent CLEAN.

## Why this contract exists in one file

The dual-engine sync rule previously lived in BOTH per-engine command wrappers, in near-duplicate form. Refactoring it into one canonical reference (this file) was the motivating example for IDEA-005's existence — every cycle of PR #129 that touched the sync rule had to be mirrored across two files. The orchestrator now reads this file once, regardless of which engine entry-point invoked it.

## Adding a third engine

If a new engine (e.g. CodeRabbit) is added per the adapter contract, this file needs no structural changes — only:

1. Add the new engine's stall/error conditions to the trade-off escape-hatch table.
2. Add the new engine's `last_seen_<x>_*` slots to the scratch-file schema (the orchestrator already handles arbitrary `ENGINES` lists; the doc just needs the example fields).
3. Add the new engine's asymmetric-clearance hand-back template.

The sync protocol itself (wait-for-slowest with escape hatches, batch fixes, retrigger all) generalises to N engines without modification.
