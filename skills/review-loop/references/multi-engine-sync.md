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
| Claude stalled | Claude's Actions job `STATUS=in_progress` (RUNNING) past observed latency on `last_push_sha` — see [`engine-claude.md`](engine-claude.md) § Failure modes | Proceed with other engines' findings if any. **Don't retrigger while it's RUNNING.** Once a fix push lands, Phase 3's explicit `claude_retrigger.sh` is what gets the fresh verdict — the `synchronize` auto-run skip-no-ops after claude's first review (see [`engine-claude.md`](engine-claude.md) § A7). Surface in hand-back if it never recovers. |
| Claude action not installed | `CLAUDE_NOT_INSTALLED=true` (no `claude-code-review.yml` workflow on the repo) | In a multi-engine run, claude self-excludes from the **default** set; proceed with the other engines. On an **explicit** `...,claude` run, surface loudly in hand-back ("run `/install-github-app`"), never HUNG. |
| One engine DONE+clean + another still RUNNING | one engine `DONE` with zero active findings for `last_push_sha` + another engine's check-run/Actions job still `queued`/`in_progress` past idle-poll threshold | Wait up to `max_idle_polls × 270s`; if the RUNNING engine never reaches `DONE`, hand back with the cleared engine(s)' CLEAN status documented prominently. |

## Sync state — scratch-file fields per engine

Replicate per engine in the loop's scratch file:

```yaml
engines: bugbot,claude,copilot
bugbot_review_state:  NOT_TRIGGERED|TRIGGERED|RUNNING|DONE
claude_review_state:  NOT_TRIGGERED|TRIGGERED|RUNNING|DONE
copilot_review_state: NOT_TRIGGERED|TRIGGERED|RUNNING|DONE
last_seen_bugbot_review:  <id> @ <sha>
last_seen_claude_review:  <id> @ <sha>   # claude anchor = synthesized summary-comment id (or newest head-SHA inline comment id)
last_seen_copilot_review: <id> @ <sha>
last_seen_bugbot_signal_id:  <id>
last_seen_claude_signal_id:  <id>
last_seen_copilot_signal_id: <id>
no_progress_map:
  bugbot:  { <category>: <count> }
  claude:  { <category>: <count> }
  copilot: { <category>: <count> }
```

Each engine's `<engine>_review_state` is tracked independently — under multi-engine mode one engine can be `DONE` while another is still `RUNNING`. The orchestrator waits for the slowest to reach `DONE` before reading any verdict (the Phase 4 sync gate). For `claude`, `<engine>_review_state` is synthesized from its **Actions job** status (no native check-run — see [`engine-claude.md`](engine-claude.md)), but the orchestrator reads it through the same RUNNING/DONE state machine.

## Retrigger discipline — different per engine, fired in deterministic order

Phase 3 fires after the batch commit. For each engine in `ENGINES` (deterministic order: alphabetical so behaviour is reproducible — `bugbot` → `claude` → `copilot`):

- For `bugbot`: `./tools/bugbot_retrigger.sh <PR>` (posts a `bugbot run` comment).
- For `claude`: `./tools/claude_retrigger.sh <PR>` (posts `@claude review once`). **This DOES fire in Phase 3.** The batch commit's push fires the `synchronize` auto-run, but the `code-review` plugin **skip-no-ops it once claude has already reviewed the PR** — which, by Phase 3, it always has (the loop only reaches Phase 3 after acting on findings). So the explicit retrigger is the *only* path to a fresh verdict on the fix, and there is **no double-run race**: the auto-run skips, leaving the explicit `@claude review` as the sole review for the head SHA. `claude_retrigger.sh` also covers the zero-activity bootstrap. Corrected via the PR #169 self-dogfood — see [`engine-claude.md`](engine-claude.md) § A7.
- For `copilot`: `./tools/copilot_retrigger.sh <PR>` (`gh pr edit <PR> --add-reviewer @copilot`; Copilot self-removes from `requested_reviewers` post-review so bare `--add` is the canonical retrigger — see [`engine-copilot.md`](engine-copilot.md) § Tool invocations for the still-pending fallback case).

All three retriggers happen post-push and fire once each, back-to-back (different queues, no interval): bugbot/copilot via their check-run / reviewer-request mechanisms, claude via the explicit `@claude review` (its `synchronize` auto-run skip-no-ops after the first review, so the explicit request is the real one for the new SHA). The orchestrator never retriggers while an engine's check-run/Actions job is RUNNING, so there is nothing to space out.

## Hand-back when only one engine cleared

A non-trivial fraction of multi-engine runs end with a subset of engines CLEAN and the rest in a degraded state. The hand-back report MUST distinguish the cases. The rule generalises to N engines: enumerate which engines cleared (with `<sha>`) and which are degraded (with the degradation cause), and surface any partial clearance prominently.

- **Some engines CLEAN, ≥1 degraded** — the PR has a *partial* verdict. Surface it prominently, listing every engine's state. Example (3-engine run):

  ```
  ⚠️  ASYMMETRIC CLEARANCE (2 of 3 engines cleared):
      ✅ bugbot CLEAN at <sha>
      ✅ claude  CLEAN at <sha>
      ❌ copilot errored (3× consecutive service errors)
      Merge decision is yours: (a) merge on the cleared engines' verdicts alone,
      (b) retry copilot from the GitHub UI before merging, or (c) wait for Copilot recovery.
  ```

  A claude-specific degradation row reads e.g. `❌ claude NOT INSTALLED (run /install-github-app)` or `❌ claude hung (Actions job in_progress past latency)`. The principle is identical regardless of which engine(s) cleared — name each engine, its verdict or its degradation cause, and leave the merge decision to the user.

- **All engines CLEAN at `<sha>`** — merge-ready summary; no asymmetric-clearance warning.
- **≥1 engine still finding things** — loop continues; no hand-back yet.

The user always decides; the loop never auto-merges and never escalates an asymmetric clearance into a silent CLEAN.

## Why this contract exists in one file

The multi-engine sync rule previously lived in BOTH per-engine command wrappers, in near-duplicate form. Refactoring it into one canonical reference (this file) was the motivating example for IDEA-005's existence — every cycle of PR #129 that touched the sync rule had to be mirrored across two files. The orchestrator now reads this file once, regardless of which engine entry-point invoked it.

## Adding the Nth engine

If a new engine (e.g. CodeRabbit) is added per the adapter contract, this file needs no structural changes — only the example fields and the four touchpoints (`claude` was added this way as the third engine; the steps are identical for the next):

1. Add the new engine's stall/error conditions to the trade-off escape-hatch table — including any `<ENGINE>_NOT_INSTALLED` self-exclusion row for default-set engines gated on a reachability probe.
2. Add the new engine's `<engine>_review_state` + `last_seen_<x>_*` slots to the scratch-file schema (the orchestrator already handles arbitrary `ENGINES` lists; the doc just needs the example fields).
3. Slot the new engine into the **alphabetical** retrigger order. If it's a **push-triggered** engine (auto-runs on `synchronize`), check whether its auto-run de-dupes after the first review — if so, Phase 3 must still fire its explicit `*_retrigger.sh` for a fresh post-fix verdict (the auto-run skip-no-ops), exactly as `claude`'s slot documents.
4. Extend the asymmetric-clearance hand-back to cover the new engine count (the template already generalises — just add the engine's CLEAN/degradation row vocabulary).

The sync protocol itself (wait-for-slowest with escape hatches, batch fixes, retrigger all *check-run-category* engines) generalises to N engines without modification.
