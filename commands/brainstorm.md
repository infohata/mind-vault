---
description: Alias for /plan — brainstorming is the interactive front-end of the plan skill when input is thin; both commands invoke the same skill
agent: general
---

Alias for `/plan`. The brainstorming semantics — one-question-at-a-time interactive requirements capture — are the thin-input bootstrap mode of the plan skill, not a separate stage.

Use whichever command reads better in context:

- `/brainstorm` when starting from a vague idea or exploring "what should we build" before naming a plan.
- `/plan` when starting from a filled-out IDEA file or a clear specification and ready to structure the approach.

Either way, the same skill handles it: thin input triggers the bootstrap; substantive input goes straight to plan drafting.

See `skills/plan/SKILL.md` for full pattern. See `skills/plan/references/thin-input-bootstrap.md` for the brainstorm-mode interaction rules.
