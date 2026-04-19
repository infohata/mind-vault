---
name: work
description: Execute a plan produced by /plan — reads docs/plans/YYYY-MM-DD-<slug>-plan.md, enforces RULE_parallel-worktree-docker and RULE_git-safety, dispatches to AGENT_backend/frontend/devops/test-engineer, checks off plan items as commits land. Third stage of the mind-vault sprint workflow.
---

# work

Third stage of the five-stage sprint workflow (`idea → brainstorm/plan → work → review → compound`). Executes a plan against the target project's codebase — spawns worktrees when the plan flags parallelism, dispatches to implementation personas, commits feature-by-feature, and tracks progress against the plan's Execution Sequence.

This skill is intentionally thin. It does not re-decide anything the plan already decided. It orchestrates; the personas implement; the rules guardrail. If the plan is wrong, stop and route back to `/plan` — don't paper over planning gaps at execution time.

## When to use

**TRIGGER when:**

- user says "work the plan", "execute the plan", "implement plan X", "start working on Y", "ship the plan at <path>"
- a `/plan` invocation just completed and the natural next step is execution
- a plan file exists at `<project>/docs/plans/*-plan.md` with `status: ready` and the user wants to proceed

**SKIP when:**

- there is no plan file and the work is bounded enough to not need one — just do the fix
- the plan is still `status: draft` — route to `/plan` to finalise (architect review, open-questions resolution) first
- the plan has clear structural flaws (missing file paths, unresolved architect findings) — route back to `/plan`
- the user wants to review or critique existing code — route to `/bugbot-loop`

## Pattern

### 1. Load and validate the plan

1. Resolve the plan path from the argument (explicit path, slug, or most recent plan file). Read the whole file.
2. Check frontmatter: `status: ready` required. If `draft`, refuse and route to `/plan` for finalisation.
3. Read the plan's Execution Sequence — this is the ordered list of work items the skill will dispatch.
4. Read the plan's Verification section — the skill will run these commands/checks after execution completes.
5. If the plan lists dependencies (open questions, prerequisite merges), verify they're resolved before starting.

### 2. Branch and worktree setup

Honour `RULE_git-safety` and `RULE_parallel-worktree-docker` at all times.

- **Current branch check.** If the user is on `main` or `production`, refuse to commit. Create a feature branch: `git checkout -b <type>/<slug> origin/<base>` where `<type>` is `feat | fix | docs | refactor | chore` and `<slug>` matches the plan's slug.
- **Parallelism detection.** If the plan explicitly flags parallel work streams (multiple non-overlapping execution units), consult [`references/persona-dispatch.md`](references/persona-dispatch.md) for the worktree setup procedure. Otherwise execute serially on a single branch.
- **Pre-existing worktrees.** Probe `git worktree list --porcelain` for the target branch before checking out. If found, attach instead of re-checking-out in the primary tree.
- **Clean-tree gate.** `git status --porcelain` must be empty before starting, or the skill prompts the user to stash / commit / discard first.

### 3. Dispatch to personas

Walk the plan's Execution Sequence. For each step, pick the right persona via the dispatch matrix in [`references/persona-dispatch.md`](references/persona-dispatch.md).

Default matrix (projects can override in their own `AGENTS.md`):

| Plan-item domain | Persona |
| --- | --- |
| Models, views, signals, DRF, Channels, Celery, ORM | `AGENT_backend` |
| Templates, Alpine, HTMX, Bulma, static assets, JS | `AGENT_frontend` |
| Docker, compose, nginx, systemd, CI/CD, env config | `AGENT_devops` |
| Test authoring, fixture design, coverage gates | `AGENT_test-engineer` |
| Multi-domain or cross-cutting refactor | `AGENT_architect` (as author now, not reviewer — plan already reviewed) |
| Documentation-only updates (README, CHANGELOG) | `AGENT_documentation` |

Pass the persona the **plan path + the specific item index** — never inline the item's prose into the dispatch prompt (per the "pass paths not content to subagents" convention). The persona reads the plan file itself.

### 4. Commit rhythm

Commit per logical unit, not per file. One commit per completed Execution Sequence item is the default; multi-file changes that implement a single item stay in one commit.

- **Commit-message format** (project convention lives in `RULE_git-safety`):

  ```text
  type(scope): brief description (≤72 chars)

  Optional body explaining why, wrapped at 72.
  ```

- **Never `--no-verify`, never plain `--force`.** `--force-with-lease` is allowed on feature branches the agent owns.
- **After each commit**, update the plan file in place: mark the completed item with ✅ and the commit SHA short. Keeps the plan a living progress document.

### 5. Verification and handoff

After all Execution Sequence items land:

1. Run the commands listed in the plan's Verification section. Capture output.
2. If verification passes, open a PR: `gh pr create --title "<type>(<scope>): <plan.slug>" --body <plan-derived-body>`. Include the plan path in the PR body so the reviewer has the full context.
3. Mark the plan `status: shipped` in frontmatter.
4. Print the PR URL and suggest the next stage: `/bugbot-loop <pr-url>`.

If verification fails:

1. Do NOT open a PR. Do NOT mark the plan shipped.
2. Document the failure in the plan's Open Questions section (append, don't overwrite).
3. Route to the user for a decision: fix in place, roll back the latest commit, or return to `/plan` for a revised approach.

## Interaction rules

- **Don't re-decide what the plan already decided.** If the plan says "use Redis for the queue", use Redis. If the right answer is Postgres instead, that's a plan revision — route back to `/plan`.
- **Respect `RULE_i18n-workflow`.** When the work touches translatable strings, the backend persona must not hand-edit `.po` files. The map-first workflow stays intact.
- **Status updates at each commit**, not batched at the end. Keeps the plan's progress authoritative even if the session is interrupted.
- **Ask before destructive git operations.** `git reset --hard`, branch deletion, force-push to a branch with an open PR — all require user confirmation unless the plan explicitly authorises them.

## When NOT to use these patterns

- **Plan is `status: draft`.** Route to `/plan` to finalise first.
- **Plan's architect review is 🔴 REJECTED.** Do not execute a rejected plan. Revise.
- **Plan lacks an Execution Sequence.** Without ordered concrete steps, the skill has nothing to dispatch. Return to `/plan` and demand specificity.
- **Fresh bug report with no plan.** Small bugs: just fix. Larger ones: `/idea` then `/plan` first.
- **The plan says "run these migrations in production"** — production touches are explicit HITL moments per `RULE_git-safety`. The skill prepares the change; the human ships it.

## References

- [references/persona-dispatch.md](references/persona-dispatch.md) — per-domain persona routing, worktree setup for parallel work streams, override conventions
- [docs/SPRINT_WORKFLOW.md](../../docs/SPRINT_WORKFLOW.md) — full sprint-workflow explainer
- [skills/plan/SKILL.md](../plan/SKILL.md) — previous stage; produces the plan this skill executes
- [skills/compound/SKILL.md](../compound/SKILL.md) — final stage; compound what was learned after review clears
- [rules/RULE_git-safety.md](../../rules/RULE_git-safety.md) — branching and commit contract
- [rules/RULE_parallel-worktree-docker.md](../../rules/RULE_parallel-worktree-docker.md) — worktree + docker isolation contract for parallel execution
- [rules/RULE_i18n-workflow.md](../../rules/RULE_i18n-workflow.md) — translation-map workflow enforced during execution
- [agents/AGENT_backend.md](../../agents/AGENT_backend.md), [AGENT_frontend.md](../../agents/AGENT_frontend.md), [AGENT_devops.md](../../agents/AGENT_devops.md), [AGENT_test-engineer.md](../../agents/AGENT_test-engineer.md) — implementation personas dispatched by this skill

---

**Last Updated**: 2026-04-19
