---
description: Semi-autonomous Cursor Bugbot code-review loop with bounded-autonomy policy (Option B+)
agent: general
---

# /bugbot-loop

Drive a Cursor Bugbot review-fix-rerun cycle on the current PR (or specified PR number).

**Inputs**: optional `PR_NUMBER`. Default: PR for current branch.

## Behaviour

This command is a single-engine wrapper around the shared review-loop skill. It is equivalent to:

```
/review-loop <PR_NUMBER> bugbot
```

The full behaviour spec lives in:

- [`skills/review-loop/SKILL.md`](../skills/review-loop/SKILL.md) — Phase 0/1/2/3/4 orchestrator, hard bounds, decision tree.
- [`skills/review-loop/references/engine-bugbot.md`](../skills/review-loop/references/engine-bugbot.md) — Bugbot-specific identity, tools, clean-signal parsing, race-condition caveats, failure modes, codified Tier 1 patterns.
- [`agents/AGENT_bugbot.md`](../agents/AGENT_bugbot.md) — Common Bugbot Patterns §1-8 (Tier 1 auto-fix catalogue).

## Hard bounds

- `max_commits_per_session = 20`
- `max_active_work_minutes = 180` (excludes ScheduleWakeup sleep time)
- `max_idle_polls = 20`
- ≥5 min between bugbot retriggers (per-engine spacing)
- Feature branch only — never main (per `RULE_git-safety`)
- Batch fixes per cycle into one commit, not one-per-finding

## When to use this command vs `/review-loop`

- **`/bugbot-loop`** — single-engine bugbot run. Use when you only care about bugbot's verdict OR when Copilot is unavailable/disabled on the repo.
- **`/review-loop <PR> bugbot,copilot`** — dual-engine sync mode. Use when both engines are configured and you want both verdicts before merging. Findings from both engines batch into the same fix commits per cycle — see [`references/dual-engine-sync.md`](../skills/review-loop/references/dual-engine-sync.md).

## Hand-back

The loop hands back with:

- Cycles run, findings auto-fixed, findings approved, findings escalated, findings skipped.
- Tier 3 escalations with reasoning (need human decision).
- Pending bugbot retrigger NOT fired (if budget exhaustion prevented it) — with the exact manual command to run after spacing elapses.
- Suggested broader regression command for pre-merge.
- PR URL.

The loop never merges. Final review and merge are always the user's responsibility.
