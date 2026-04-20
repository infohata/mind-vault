---
description: Third stage of the sprint workflow — execute a plan by dispatching to implementation personas; enforces RULE_git-safety + RULE_parallel-worktree-docker; commits per plan item
agent: general
---

# work

Invoke the `work` skill to execute a plan produced by `/plan`. Thin orchestrator — delegates actual implementation to personas (backend / frontend / devops / test-engineer / architect as author / documentation) and commits feature-by-feature.

Behaviour:

1. Resolve the plan path from the argument, slug, or most recent plan file; require `status: ready` (refuse `status: draft`).
2. Enforce clean working tree; create or attach to a feature branch per `RULE_git-safety`. Refuse `main` / `production`.
3. If the plan flags parallel work streams, consult `rules/RULE_parallel-worktree-docker.md` for worktree + docker-compose override setup.
4. Walk the plan's Execution Sequence; dispatch each item to the matching persona via `skills/work/references/persona-dispatch.md`. Pass paths, not content, to subagents.
5. Commit per logical unit. After each commit, mark the plan item ✅ with the short SHA in the plan file.
6. Run the plan's Verification section after all items land. If passes, open a PR (never merges). If fails, document in the plan's Open Questions and route back to the user.
7. Print the PR URL and suggest `/bugbot-loop <pr-url>` as the review stage.

Does not re-decide what the plan decided. If execution reveals the plan is wrong, stop and route back to `/plan` for a revision.

See `skills/work/SKILL.md` for full pattern.
