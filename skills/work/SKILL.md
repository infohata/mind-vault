---
name: work
description: Execute a plan produced by /plan — reads the plan at docs/archive/YYYY-MM-idea-NNN-<slug>/YYYY-MM-DD-<slug>-plan.md, enforces RULE_parallel-worktree-docker and RULE_git-safety, dispatches per the persona dispatch matrix, checks off plan items as commits land. Third stage of the mind-vault sprint workflow.
---

# work

Third stage of the five-stage sprint workflow (`idea → brainstorm/plan → work → review → compound`). Executes a plan against the target project's codebase — spawns worktrees when the plan flags parallelism, dispatches to implementation personas, commits feature-by-feature, and tracks progress against the plan's Execution Sequence.

This skill is intentionally thin. It does not re-decide anything the plan already decided. It orchestrates; the personas implement; the rules guardrail. If the plan is wrong, stop and route back to `/plan` — don't paper over planning gaps at execution time.

## When to use

**TRIGGER when:**

- user says "work the plan", "execute the plan", "implement plan X", "start working on Y", "ship the plan at <path>"
- a `/plan` invocation just completed and the natural next step is execution
- a plan file exists at `<project>/docs/archive/*-<slug>/*-<slug>-plan.md` with `status: ready` and the user wants to proceed

**SKIP when:**

- there is no plan file and the work is bounded enough to not need one — just do the fix
- the plan is still `status: draft` — route to `/plan` to finalise (architect review, open-questions resolution) first
- the plan has clear structural flaws (missing file paths, unresolved architect findings) — route back to `/plan`
- the user wants to review or critique existing code — route to `/<engine>-loop`

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

Default matrix (projects can override in their own `AGENTS.md`). The right column is the dispatchable `subagent_type` — pass it verbatim to `Agent(subagent_type: …)`; the profile file backing each id is mapped in [`references/persona-dispatch.md`](references/persona-dispatch.md):

| Plan-item domain | Subagent type |
| --- | --- |
| Models, views, signals, DRF, Channels, Celery, ORM | `mv-backend` |
| Templates, Alpine, HTMX, Bulma, static assets, JS | `mv-frontend` |
| Docker, compose, nginx, systemd, CI/CD, env config | `mv-devops` |
| Test authoring, fixture design, coverage gates | `mv-test-engineer` |
| Multi-domain or cross-cutting refactor | `mv-architect` (as author now, not reviewer — plan already reviewed) |
| Documentation-only updates (README, CHANGELOG) | `mv-documentation` |

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

1. Run the commands listed in the plan's Verification section. Capture output. **Verification routing — see § "Sprint-auto v3.1 verification routing" below for the env-var-driven mode.**
2. If verification passes, open a PR: `gh pr create --title "<type>(<scope>): <plan.slug>" --body <plan-derived-body>`. Include the plan path in the PR body so the reviewer has the full context.
3. Mark the plan `status: shipped` in frontmatter.
4. Print the PR URL and suggest the next-stage chain: `/<engine>-loop <pr-url>` → `/wrap NNN`.

The full canonical chain after `/work` opens the PR:

```text
/work        → opens PR, plan: shipped, code committed
/<engine>-loop → clears review findings, retriggers until clean
/wrap NNN    → docs commits ride the same PR (frontmatter flip,
               ideas-index, devlog, archive README, downstream scan).
               If PR base is non-protected, wrap also squash-merges.
               If PR base is protected, wrap hands back the PR URL
               for human merge.
```

The single-IDEA chain mirrors what sprint-auto already does at the multi-IDEA scale: code → review → docs → integration merge as ONE shipping moment. Don't split it into two operator turns when the merge target is non-protected per [`RULE_git-safety`](../../rules/RULE_git-safety.md).

If verification fails:

1. Do NOT open a PR. Do NOT mark the plan shipped.
2. Document the failure in the plan's Open Questions section (append, don't overwrite).
3. Route to the user for a decision: fix in place, roll back the latest commit, or return to `/plan` for a revised approach.

### 5a. Sprint-auto v3.1 verification routing

Under sprint-auto v3.1, per-IDEA worktrees are pure code surfaces — no `.env`, no docker stack. The integration worktree's stack (at port offset `+30000`) is the only docker stack of the batch, and all verification routes there.

Detect by checking `SPRINT_AUTO_INTEGRATION_WORKTREE`:

```bash
if [[ -n "${SPRINT_AUTO_INTEGRATION_WORKTREE:-}" ]]; then
    # v3.1 sprint-auto mode — route verification commands to the integration worktree
    integration_wt="$SPRINT_AUTO_INTEGRATION_WORKTREE"
    feature_branch=$(git branch --show-current)  # e.g. auto/<slug>

    # Switch the integration worktree to the per-IDEA branch's tip and refresh
    # code. IMPORTANT: use `--detach` because `auto/<slug>` is already checked
    # out in the per-IDEA worktree — git refuses to check out the same branch
    # in two worktrees ("'auto/<slug>' is already checked out at '<path>'").
    # `--detach origin/auto/<slug>` reads the commits without claiming the
    # branch ref, which is exactly right: we don't commit in the integration
    # worktree (commits happen in the per-IDEA worktree). docker compose
    # up -d --force-recreate refreshes Python services with the mounted source
    # from this commit; stateful services (db, redis, minio, elasticsearch)
    # keep their state from the per-IDEA DB reset that sprint-auto ran at
    # S1.5 (entry to S2).
    pushd "$integration_wt" >/dev/null
    git fetch origin "$feature_branch"
    git checkout --detach "origin/$feature_branch"
    docker compose up -d --force-recreate web celery
    # Run plan's Verification commands here (pytest, etc.) inside the
    # integration worktree's stack.
    docker compose exec -T web pytest <unioned paths from plan>
    popd >/dev/null
else
    # Standalone mode — run verification in the current worktree (default).
    # Existing behaviour: pytest / make test / project-equivalent against
    # the worktree's own stack (RULE_parallel-worktree-docker contract).
    pytest <paths>  # or make test, etc.
fi
```

When `SPRINT_AUTO_INTEGRATION_WORKTREE` is set:
- The agent never runs `docker compose` against the per-IDEA worktree (there's no `.env`, no override file — would fail).
- The agent never creates a `.env` in the per-IDEA worktree (the env-var contract guarantees verification happens elsewhere).
- The DB state on the integration worktree is the **main-equivalent baseline** for this IDEA (sprint-auto reset it at S1.5 before invoking `/work`); the verification runs against that baseline.
- Within an IDEA's session (this `/work` invocation + subsequent review-loop fix-cycles), the DB state is preserved between commands. Sprint-auto only resets between IDEAs.

The full env-var contract is in [`../sprint-auto/references/integration-stage.md`](../sprint-auto/references/integration-stage.md). If verification commands are documented elsewhere (project Makefile, `tools/test.sh`), the same routing applies — `cd $SPRINT_AUTO_INTEGRATION_WORKTREE` first, then run.

### 6. Frontmatter flip — `/wrap` is the canonical owner; this section is the fallback

**Primary path: `/wrap` does the frontmatter flip pre-merge.** `/wrap NNN` runs after `/<engine>-loop` clears, before merge — it flips IDEA frontmatter `in-progress → complete`, updates the ideas index, appends the devlog entry, scans downstream docs, and (when target is non-protected) squash-merges atomically. The `/work` skill does NOT duplicate that work in the normal flow — it hands off to `/wrap`.

**Fallback in this section fires only when `/wrap` was bypassed** — the user merged the PR directly without invoking `/wrap`, or a hotfix landed without ceremony. In that case, the next `/work` invocation that touches a merged-but-unflipped IDEA runs the steps below as a cleanup pass on a separate `chore/complete-idea-NNN` branch. The `/wrap` skill itself also has a "post-merge fallback" mode that does the same thing with full docs sweep — prefer `/wrap NNN` post-merge over the pared-down version below.

Per [`RULE_ideas-location-status`](../idea/references/IDEAS_LOCATION_STATUS.md), the IDEA file normally already lives in its permanent home (`docs/archive/YYYY-MM-idea-NNN-<slug>/`, placed there by `/plan` step 6 when the user went through `/plan` first). On merge, **no file moves** in that case. Just frontmatter edits:

```yaml
# docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md
status: complete
completed: 2026-04-22
```

```yaml
# docs/archive/YYYY-MM-idea-NNN-<slug>/YYYY-MM-DD-<slug>-plan.md
status: shipped
```

Plus `docs/ideas/README.md`:

- Remove the In-Progress entry.
- Add a footer line under "References — Implemented" pointing at `../archive/<dir>/` (the dir itself, not the IDEA file — the dir's README is the canonical landing for a completed idea's full story).

That's it. No `git mv` cascade, no archive-dir creation (it already exists), no cross-tree routing. The single filesystem move per idea happened at `/plan` time.

**Fallback: idea bypassed `/plan` entirely.** If the user went straight from `/idea` to `/work` without a `/plan` invocation (small scope, simple fix), the source file is still in `docs/ideas/` at merge time. `/work` is the fallback owner of the `idea → archive` move per `RULE_ideas-location-status`. Before the frontmatter flip above, run the same move `/plan` step 6 would have done:

```bash
mkdir -p <project>/docs/archive/YYYY-MM-idea-NNN-<slug>/
git mv <project>/docs/ideas/IDEA-NNN-<slug>.md \
       <project>/docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md
# + update docs/ideas/README.md: remove from priority section,
#   add footer line under "References — Implemented"
```

`YYYY-MM` = merge month (since work happened without a separate plan-time stamp). Then apply the frontmatter flip above — on the now-archive path.

Detection: glob `<project>/docs/ideas/IDEA-*-<slug>.md` before the frontmatter flip. If a match exists, run the fallback move first. If not, the file is already in archive and the frontmatter flip is all that's needed.

Commit message: `docs(archive): IDEA-NNN <slug> — mark complete (merged in PR #xxx)`. If the fallback move ran, the commit combines both the move and the frontmatter flip; commit message prefix becomes `feat(archive)` instead of `docs(archive)` to signal the filesystem change.

This commit lands on a cleanup branch after the primary PR merges (typically `chore/complete-idea-NNN`) since the status-flip commit references the merged PR number. The human can also roll the completion-flip into the same commit that updates `DEVELOPMENT_LOG` for that merge.

### 6a. Write the completion summary into the archive dir README

**Owned by `/wrap`** — same canonical-vs-fallback split as Section 6. `/wrap` writes the archive-dir README during its pre-merge pass; this section is the fallback for IDEAs that merged without a wrap.

When run as a fallback, append a short summary to `docs/archive/YYYY-MM-idea-NNN-<slug>/README.md` (create if missing) covering:

- What shipped (one-paragraph)
- PR number(s)
- Notable deviations from the plan
- Follow-up work that got punted to new IDEAs

This is the canonical landing page for anyone discovering the idea via grep/index after completion. Keep it short; details live in the plan doc and the DEVELOPMENT_LOG entry.

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
- [skills/idea/references/IDEAS_LOCATION_STATUS.md](../idea/references/IDEAS_LOCATION_STATUS.md) — location-by-status contract driving step 6's archive move on merge
- [docs/guides/SPRINT_WORKFLOW.md](../../docs/guides/SPRINT_WORKFLOW.md) — full sprint-workflow explainer
- [skills/plan/SKILL.md](../plan/SKILL.md) — previous stage; produces the plan this skill executes
- [skills/compound/SKILL.md](../compound/SKILL.md) — final stage; compound what was learned after review clears
- [rules/RULE_git-safety.md](../../rules/RULE_git-safety.md) — branching and commit contract
- [skills/sprint-auto/references/PARALLEL_WORKTREE_DOCKER.md](../sprint-auto/references/PARALLEL_WORKTREE_DOCKER.md) — worktree + docker isolation contract for parallel execution
- [skills/django/references/I18N_WORKFLOW.md](../django/references/I18N_WORKFLOW.md) — translation-map workflow enforced during execution
- [references/WATCHER_HYGIENE.md](references/WATCHER_HYGIENE.md) — load when arming `run_in_background` watchers (test runs, log tails, polling); orchestrator-trash-collection discipline + self-match avoidance
- [references/AUDIT_NEWLY_REACHABLE_CODE.md](references/AUDIT_NEWLY_REACHABLE_CODE.md) — load when the fix being applied REMOVES a short-circuit (empty-state guard, early return, missing call, async resolution, type-gate relaxation); audit newly-reachable downstream code for latent issues before committing
- [agents/AGENT_backend.md](../../agents/AGENT_backend.md), [AGENT_frontend.md](../../agents/AGENT_frontend.md), [AGENT_devops.md](../../agents/AGENT_devops.md), [AGENT_test-engineer.md](../../agents/AGENT_test-engineer.md) — implementation personas dispatched by this skill
