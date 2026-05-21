---
description: Semi-autonomous Cursor Bugbot code-review loop with bounded-autonomy policy (Option B+)
agent: general
---

# /bugbot-loop

> **Deprecated (v4.2, upcoming).** Prefer `/review-loop <PR> bugbot` directly. This thin wrapper will be removed in a future release; dropping it trims the always-loaded command surface and reduces initial token toll.

Single-engine wrapper around the shared review-loop skill. Equivalent to:

```
/review-loop <PR_NUMBER> bugbot
```

**Inputs**: optional `PR_NUMBER`. Default: PR for current branch.

**Behaviour**: see [`skills/review-loop/SKILL.md`](../skills/review-loop/SKILL.md).
**Bugbot specifics** (identity, tools, clean-signal parsing, race caveats, failure modes, Tier 1 catalogue): see [`skills/review-loop/references/engine-bugbot.md`](../skills/review-loop/references/engine-bugbot.md).

For dual-engine sync mode (run bugbot + copilot concurrently with cycle-level synchronisation), invoke [`/review-loop`](review-loop.md) with `bugbot,copilot` instead.
