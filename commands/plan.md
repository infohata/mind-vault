---
description: Second stage of the sprint workflow — turn an IDEA file or rough description into a durable plan at docs/plans/YYYY-MM-DD-<slug>-plan.md; interactively brainstorms when input is thin; invokes AGENT_architect as reviewer
agent: general
---

Invoke the `plan` skill to produce a technical plan for an IDEA file, a rough feature description, or a deepening pass on an existing plan. The skill merges CE's brainstorm + plan into a single stage: when the input is thin (sparse IDEA body, < 30-word description), a brainstorm front-end fires before the plan is drafted.

Behaviour:

1. Resolve the input: IDEA file path, IDEA slug, plan-file path for deepening, raw description, or nothing (ask the user).
2. If thin input, run the interactive brainstorm bootstrap (one-question-at-a-time, single-select preferred, platform blocking tools where available).
3. Research existing repo patterns, institutional learnings (`docs/solutions/`, mind-vault skills/rules), and external references before structuring.
4. Draft the plan using the canonical CE-inspired structure: Context → Problem Frame → Requirements Trace → Scope → Key Decisions → Open Questions → Execution Sequence → Verification.
5. Invoke `AGENT_architect` as a reviewer pass (4-pass structural architecture review) for medium+ plans. Integrate findings.
6. Write to `<project>/docs/plans/YYYY-MM-DD-<slug>-plan.md` with stage-handoff frontmatter (`stage: plan`, `source:`, `status: draft|ready|shipped`).
7. Print the path and suggest `/work <plan-path>` as the next command.

Right-sized: trivial work skips the skill entirely; small work gets a compact plan; medium+ gets the full structure with architect review.

`/brainstorm` is an alias for this command — both invoke the same skill.

See `skills/plan/SKILL.md` for full pattern; `docs/SPRINT_WORKFLOW.md` for the stage-handoff schema.
