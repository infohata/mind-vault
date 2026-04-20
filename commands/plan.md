---
description: Second stage of the sprint workflow — turn an IDEA file or rough description into a durable plan emitted into the idea's archive dir at docs/archive/YYYY-MM-idea-NNN-<slug>/YYYY-MM-DD-<slug>-plan.md; interactively brainstorms when input is thin; invokes AGENT_architect as reviewer; triggers the single idea → archive move per RULE_ideas-location-status
agent: general
---

Invoke the `plan` skill to produce a technical plan for an IDEA file, a rough feature description, or a deepening pass on an existing plan. The skill merges CE's brainstorm + plan into a single stage: when the input is thin (sparse IDEA body, < 30-word description), a brainstorm front-end fires before the plan is drafted.

Behaviour:

1. Resolve the input: IDEA file path, IDEA slug, plan-file path for deepening, raw description, or nothing (ask the user).
2. If thin input, run the interactive brainstorm bootstrap (one-question-at-a-time, single-select preferred, platform blocking tools where available).
3. Research existing repo patterns, institutional learnings (`docs/solutions/`, mind-vault skills/rules), and external references before structuring.
4. Draft the plan using the canonical CE-inspired structure: Context → Problem Frame → Requirements Trace → Scope → Key Decisions → Open Questions → Execution Sequence → Verification.
5. Invoke `AGENT_architect` as a reviewer pass (4-pass structural architecture review) for medium+ plans. Integrate findings.
6. Trigger the single `idea → archive` move per `RULE_ideas-location-status` — `mkdir -p <project>/docs/archive/YYYY-MM-idea-NNN-<slug>/` + `git mv` the source IDEA file into it + flip frontmatter to `status: in-progress` + update `docs/ideas/README.md` (entry into 🚧 In Progress).
7. Write the plan alongside the moved IDEA file at `<project>/docs/archive/YYYY-MM-idea-NNN-<slug>/YYYY-MM-DD-<slug>-plan.md` with stage-handoff frontmatter (`stage: plan`, `source: ./IDEA-NNN-<slug>.md`, `status: draft|ready|shipped`).
8. Print the path and suggest `/work <plan-path>` as the next command.

Right-sized: trivial work skips the skill entirely; small work gets a compact plan; medium+ gets the full structure with architect review.

`/brainstorm` is an alias for this command — both invoke the same skill.

See `skills/plan/SKILL.md` for full pattern; `docs/SPRINT_WORKFLOW.md` for the stage-handoff schema.
