---
description: Semi-autonomous GitHub Copilot code-review loop with bounded-autonomy policy (Option B+)
agent: general
---

# /copilot-loop

Drive a GitHub Copilot review-fix-rerun cycle on the current PR (or specified PR number).

**Inputs**: optional `PR_NUMBER`. Default: PR for current branch.

## Behaviour

This command is a single-engine wrapper around the shared review-loop skill. It is equivalent to:

```
/review-loop <PR_NUMBER> copilot
```

The full behaviour spec lives in:

- [`skills/review-loop/SKILL.md`](../skills/review-loop/SKILL.md) — Phase 0/1/2/3/4 orchestrator, hard bounds, decision tree.
- [`skills/review-loop/references/engine-copilot.md`](../skills/review-loop/references/engine-copilot.md) — Copilot-specific identity (dual user.login), tools, clean-signal parsing (TBD), race-condition caveats, service-error failure modes, first-run calibration notes.

## Hard bounds

- `max_commits_per_session = 20`
- `max_active_work_minutes = 180` (excludes ScheduleWakeup sleep time)
- `max_idle_polls = 20`
- ≥5 min between copilot retriggers (per-engine spacing)
- Feature branch only — never main (per `RULE_git-safety`)
- Batch fixes per cycle into one commit, not one-per-finding

## Copilot-specific quirks

- **Retrigger requires `remove+add`** — bare `gh pr edit --add-reviewer @copilot` against an already-requested reviewer is a no-op. The `tools/copilot_retrigger.sh` script encapsulates the working sequence.
- **Service-error failure mode** — Copilot can post reviews with body literally `"Copilot encountered an error..."` and zero findings. 2× consecutive → stop retriggering this cycle; 3× → hand back as durable service issue.
- **Clean-signal phrasing** — still TBD pending empirical observation (2026-05-18 calibration never observed a clean review).

See [`skills/review-loop/references/engine-copilot.md`](../skills/review-loop/references/engine-copilot.md) for the full set.

## When to use this command vs `/review-loop`

- **`/copilot-loop`** — single-engine Copilot run. Use when you only care about Copilot's verdict OR when Bugbot is unavailable/disabled on the repo.
- **`/review-loop <PR> bugbot,copilot`** — dual-engine sync mode. Use when both engines are configured and you want both verdicts before merging. Findings from both engines batch into the same fix commits per cycle — see [`references/dual-engine-sync.md`](../skills/review-loop/references/dual-engine-sync.md).

## Hand-back

The loop hands back with:

- Cycles run, findings auto-fixed, findings approved, findings escalated, findings skipped.
- Tier 3 escalations with reasoning (need human decision).
- Pending copilot retrigger NOT fired (if budget exhaustion prevented it) — with the exact manual command to run after spacing elapses.
- Suggested broader regression command for pre-merge.
- PR URL.

The loop never merges. Final review and merge are always the user's responsibility.
