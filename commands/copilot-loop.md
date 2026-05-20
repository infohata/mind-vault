---
description: Semi-autonomous GitHub Copilot code-review loop with bounded-autonomy policy (Option B+)
agent: general
---

# /copilot-loop

Single-engine wrapper around the shared review-loop skill. Equivalent to:

```
/review-loop <PR_NUMBER> copilot
```

**Inputs**: optional `PR_NUMBER`. Default: PR for current branch.

**Behaviour**: see [`skills/review-loop/SKILL.md`](../skills/review-loop/SKILL.md).
**Copilot specifics** (dual user.login, `remove+add` retrigger quirk, service-error failure modes, clean-signal TBD, first-run calibration): see [`skills/review-loop/references/engine-copilot.md`](../skills/review-loop/references/engine-copilot.md).

For dual-engine sync mode (run bugbot + copilot concurrently with cycle-level synchronisation), invoke [`/review-loop`](review-loop.md) with `bugbot,copilot` instead.
