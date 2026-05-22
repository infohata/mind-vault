# Persona dispatch and worktree setup

Rules for routing plan Execution Sequence items to the right persona, and for provisioning parallel worktrees when the plan calls for them. Load on demand at `/work` steps 2 and 3.

## Persona dispatch matrix

The default matrix lives in `SKILL.md`. This file documents the edges, overrides, and the parallel-worktree flow.

### Ambiguous domains

Some plan items span multiple personas. Resolve by the **primary artifact touched**, not by the item's stated intent.

| Plan item example | Primary artifact | Persona |
| --- | --- | --- |
| "Add admin widget for billing summary" | Template + Alpine view logic | `AGENT_frontend` |
| "Add `billing_summary` API endpoint the widget consumes" | DRF viewset | `AGENT_backend` |
| "Dockerise the new Celery queue" | `docker-compose.yml` + entrypoint | `AGENT_devops` |
| "Add integration test for the new endpoint" | `test_*.py` | `AGENT_test-engineer` |
| "Refactor permission layer across auth+billing+kb apps" | Spans 3 apps, shared base class | `AGENT_architect` (author mode) |

If a single item genuinely touches two domains, split it into two items first — the plan is expressing two logical units and should have been split at plan time.

### Project-specific overrides

Projects can override the default matrix in their own `AGENTS.md` or a `.claude/dispatch.md` file. The work skill checks for these in order:

1. `<project>/.claude/dispatch.md` — project-specific dispatch overrides
2. `<project>/AGENTS.md` — project root agent conventions
3. The default matrix above.

Overrides replace specific rows, not the whole matrix. A project that adds a `data-engineer` persona for ETL work overrides only the Celery / data-migration rows.

### When no persona fits

If none of the available personas match the item, that's a signal the plan is either:

- Too granular ("Fix the typo on line 42" should just be done, not dispatched).
- Too architectural (should have gone through architect review at plan time).
- Missing infrastructure (the project needs a new persona added to mind-vault).

Stop and ask the user rather than force-fitting.

## Parallel worktree setup

When the plan flags parallel work streams — typically in the Execution Sequence's Phase structure — multiple work streams can proceed concurrently. Follow `RULE_parallel-worktree-docker` literally.

### When to go parallel

- The plan explicitly names two or more execution phases that do not share file paths.
- The first phase has been merged (or is open PR awaiting review) and the second phase can start without blocking.
- No more than 2–3 parallel streams at once — coordination cost dominates beyond that.

### Worktree bootstrap recipe (short form)

From the primary checkout, for each new parallel stream:

```bash
# 1. Create the worktree off the base branch.
git worktree add ../<project>-<track> -b <type>/<slug> <base-branch>

# 2. Inside the worktree, bootstrap the env with sentinel values.
cd ../<project>-<track>
cp .env.template .env
# Replace secrets with test-safe sentinels. Never copy real secrets.

# 3. Write docker-compose.override.yml for host port + subnet remapping.
#    Use +10000 port offset; pick a non-overlapping /16 subnet.

# 4. Bring up the stack.
docker compose up -d

# 5. Run project-specific post-up bootstrap (MinIO buckets, ES indices, seed data).
```

Full rules — including the `!override` gotcha on port lists, subnet overlap errors, and the pip-cache problem when adding deps — live in [`../../sprint-auto/references/PARALLEL_WORKTREE_DOCKER.md`](../../sprint-auto/references/PARALLEL_WORKTREE_DOCKER.md).

### Starting the agent inside the worktree

Per the rule's prime directive: **start the agent from the worktree directory**, not from the primary checkout reaching in via absolute paths. This dictates the working-directory scope for permission prompts and is the single biggest productivity lever in parallel-stream work.

For the work skill: when dispatching a persona into a worktree, pass the worktree path and expect the persona's session to be rooted there.

## Commit-to-plan sync protocol

After each persona completes an Execution Sequence item:

1. Capture the commit SHA: `git rev-parse --short HEAD`.
2. Read the plan file.
3. Locate the matching item in Execution Sequence.
4. Replace the item's leading bullet or number with `✅` and append `— <short-sha>` to the end of the line (preceded by a space).
5. Write the plan back.
6. Do NOT commit the plan update separately. Stage it; it'll be included with the next implementation commit, or the final wrap-up commit.

Keeps the plan a living progress document without polluting commit history with one-line plan bumps.

## Handling mid-flight plan revisions

If the persona, during implementation, hits a reason the plan's decision is wrong:

1. Stop the dispatch.
2. Report the conflict to the user with the persona's finding.
3. Route the user to `/plan` for a revision — not a silent deviation.

Silent plan deviation is the pattern that makes execution expensive to review later. The plan is the reviewable artifact; if the code diverges, the plan must be updated to match before work continues.

## What NOT to route through this skill

- **Pure refactors without feature content.** If the plan is "extract `EventRenderer` into its own module, no behaviour change", architect is the author; backend is not needed.
- **Documentation-only work.** `AGENT_documentation` handles it; the work skill barely orchestrates.
- **Exploratory prototyping with no plan.** If there's no plan, there's nothing to dispatch. Drop to direct work or route to `/plan`.
