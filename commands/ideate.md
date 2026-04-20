---
description: Zeroth (optional) stage of the sprint workflow — discover high-impact improvement candidates through divergent ideation + adversarial filter; user picks which to capture as atomic IDEA files via the /idea schema
agent: general
---

# ideate

Invoke the `ideate` skill to surface a set of candidate improvements for a given scope, filter them adversarially, and let the user pick which to promote into real IDEA files. Optional entry point above `/idea`.

When to use:

- Between sprints when the backlog is thin.
- Starting on a new project area and needing a landscape of candidate work.
- After `AGENT_curator`'s sprint-end promotion sweep surfaces multiple compound candidates and you want to triage them as a batch.

Use `/idea` instead when you already have one specific idea in mind — no need to ideate when you already know.

Behaviour:

1. Establish scope interactively (project / area / timeline / candidate budget / constraints).
2. Divergent scan: generate candidates across relevant axes (bugs, tech debt, features, refactors, tooling, docs, observability, process).
3. Adversarial filter: YAGNI probe, cost-vs-value, prior-art check, sharpness, dependency awareness, ownership, cost-of-being-wrong. Drop 30–50% of candidates.
4. Present the ranked survivors as a menu with priority / effort / rationale.
5. User picks which to capture; skill emits `IDEA-NNN-<slug>.md` files via the shared `/idea` template and updates `docs/ideas/README.md` index.
6. Hand off with suggested next command (`/plan <slug>` for the highest-priority captured idea).

See `skills/ideate/SKILL.md` for full pattern; `skills/ideate/references/divergent-scan.md` for per-axis generation prompts; `skills/ideate/references/adversarial-filter.md` for the critique rules.
