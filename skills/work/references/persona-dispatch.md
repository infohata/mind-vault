# Persona dispatch and worktree setup

Rules for routing plan Execution Sequence items to the right persona, and for provisioning parallel worktrees when the plan calls for them. Load on demand at `/work` steps 2 and 3.

## Canonical persona ↔ subagent_type map

Each persona registers as a recognized Claude Code subagent under a namespaced `name:` (the `mv-` prefix avoids collisions with marketplace plugin agents in the shared registry). Dispatch with `Agent(subagent_type: "<id>")`; the backing profile file keeps its `AGENT_*.md` name (Claude dispatches on the frontmatter `name:`, not the filename — see [`docs/guides/AGENT_PORTABILITY.md`](../../../docs/guides/AGENT_PORTABILITY.md)).

| Persona | `subagent_type` | Profile file |
| --- | --- | --- |
| Systems Architect | `mv-architect` | `agents/AGENT_architect.md` |
| Staff Backend Engineer | `mv-backend` | `agents/AGENT_backend.md` |
| Staff Client-Side Engineer | `mv-frontend` | `agents/AGENT_frontend.md` |
| SRE / Infrastructure Lead | `mv-devops` | `agents/AGENT_devops.md` |
| QA / Surgical TDD Enforcer | `mv-test-engineer` | `agents/AGENT_test-engineer.md` |
| Curator (pre-commit review) | `mv-curator` | `agents/AGENT_curator.md` |
| External Intelligence Scout | `mv-researcher` | `agents/AGENT_researcher.md` |
| Technical Writer / Clarifier | `mv-documentation` | `agents/AGENT_documentation.md` |

Conceptual prose elsewhere may still call a persona by its display name (`AGENT_backend`); the dispatchable string an executor passes is always the `mv-` id above.

## Persona dispatch matrix

The default matrix lives in `SKILL.md`. This file documents the edges, overrides, and the parallel-worktree flow.

### Ambiguous domains

Some plan items span multiple personas. Resolve by the **primary artifact touched**, not by the item's stated intent.

| Plan item example | Primary artifact | Subagent type |
| --- | --- | --- |
| "Add admin widget for billing summary" | Template + Alpine view logic | `mv-frontend` |
| "Add `billing_summary` API endpoint the widget consumes" | DRF viewset | `mv-backend` |
| "Dockerise the new Celery queue" | `docker-compose.yml` + entrypoint | `mv-devops` |
| "Add integration test for the new endpoint" | `test_*.py` | `mv-test-engineer` |
| "Refactor permission layer across auth+billing+kb apps" | Spans 3 apps, shared base class | `mv-architect` (author mode) |

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

## Stack resolution

A stack-agnostic persona's `## Stack adapter` points at "the active backend/frontend
skill" rather than a concrete framework (see [`agents/SKILL_CONTRACT.md`](../../../agents/SKILL_CONTRACT.md)).
Resolving *which* skill that is happens here, once per `/work` session, in this order —
first hit wins:

1. **`.claude/dispatch.md` `stack:` pin** (explicit, per-repo, highest authority).
2. **`AGENTS.md` `stack:` pin** (repo root convention).
3. **Auto-detect signals** (the table below).
4. **Ask the user once**, then record the answer as a `stack:` pin so it never re-asks.

### `stack:` pin convention

In `.claude/dispatch.md` (or `AGENTS.md`), backend and frontend resolve independently —
a repo may pair, e.g., a Laravel backend with a JS-tool frontend:

```yaml
stack:
  backend: django            # → skills/django/
  frontend: django-frontend  # → skills/django-frontend/
```

A single value (`stack: django`) is shorthand for `backend: django` with the frontend
left to auto-detect.

### Auto-detect signal table

**Precedence rule (A2): backend and frontend are detected separately.** A backend marker
resolves *only* the backend stack; `package.json` resolves *only* the frontend stack and
NEVER the backend — so a Laravel repo shipping a Vite/Tailwind `package.json` is not
misdetected as a Node backend.

| Stack | Backend signal (resolves backend only) | Frontend signal (resolves frontend only) |
| --- | --- | --- |
| django | `manage.py`, `settings.py` | Django templates + `django-cotton` / `templates/cotton/` |
| laravel | `composer.json` + `artisan` | `resources/views/*.blade.php` |
| node | a server entry file (`server.js` / `app.js`) — NOT `package.json`, which stays frontend-only (A2); pin a Node *backend* via `dispatch.md` if the entry file is absent/ambiguous | `package.json` (frontend tooling) |

If backend and frontend signals point at different stacks (Laravel backend + JS
frontend), that is valid — resolve each independently. If signals are absent or
ambiguous, fall through to step 4 (ask once). Per the fail-open contract, an adapter
whose stack never resolves enforces craft-only and **announces** the gap — it does not
silently skip the stack rule.

No executable detector ships in Phase 1 — these signals are read by the dispatcher /
agent directly. A `tools/detect-stack.sh` is deferred until a real third stack justifies
it.

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
- **Documentation-only work.** `mv-documentation` handles it; the work skill barely orchestrates.
- **Exploratory prototyping with no plan.** If there's no plan, there's nothing to dispatch. Drop to direct work or route to `/plan`.
