---
name: sprint-auto
description: Unattended overnight orchestrator — run a curated list of opt-in IDEAs through /plan → /work → PR creation in isolated per-IDEA git worktrees with independent docker-compose stacks. Enforces belt-and-suspenders safety gates (auto_safe frontmatter + explicit arg allowlist), halts at the HITL merge boundary per RULE_git-safety, preserves worktrees on failure for morning review. Wraps the sprint workflow for VPS / overnight execution.
---

# sprint-auto

Autonomous wrapper around the sprint workflow's middle stages (`/plan → /work → PR`) for unattended overnight execution on a VPS. Takes a curated list of IDEAs that the human has pre-cleared as low-risk, runs each one in its own git worktree with its own docker-compose project, and stops at the one HITL boundary that matters: merge to a protected branch.

This skill is **not** a substitute for human review — it is a throughput multiplier for ideas where the human has already decided "no harm trying". The human still reviews every PR before merging. The skill's job is to close the gap between "I have 10 low-risk IDEAs in the backlog" and "I have 10 PRs waiting on my desk in the morning".

## When to use

**TRIGGER when:**

- user says "run these IDEAs overnight", "sprint-auto IDEA-NNN ...", "set claude on autopilot for these", "full auto on these ideas"
- user is setting up a VPS / screen session / background run and wants multiple IDEAs executed unattended
- a curated list of IDEAs is ready: each marked `auto_safe: true` in frontmatter, each with a thick enough body to survive `/plan` without thin-input bootstrap

**SKIP when:**

- any IDEA in the list lacks `auto_safe: true` → refuse the batch, surface the offender, ask the human to tag or drop it
- the user wants interactive development → route to `/plan` or `/work` directly
- the user wants to discover candidates → route to `/ideate`
- the user has a single IDEA and plans to supervise → just run `/plan <slug>` and `/work` manually; the ceremony isn't worth it for one

## Pattern

### 1. Preflight — gate the whole batch before touching anything

Run once, before any per-IDEA work. If **any** check fails, abort with an actionable message; do not partially-run the batch.

1. **Primary-tree cleanliness.** `git status --porcelain` in the primary checkout must be empty. Dirty tree → abort.
2. **Branch.** Primary tree must be on `main` (or a non-protected branch the user explicitly authorised in the invocation). Never create auto worktrees off an unknown checkout state.
3. **Fetch.** `git fetch origin` so worktrees branch off the freshest `origin/main`.
4. **Docker daemon reachable.** `docker compose version` exits 0. (The skill will bring up a stack per IDEA — no point starting if the daemon is down.)
5. **Bootstrap script present.** Probe for `tools/sprint-auto-bootstrap.sh` in the project root (see [`references/worktree-lifecycle.md`](references/worktree-lifecycle.md)). If missing, warn and fall back to the generic recipe from `RULE_parallel-worktree-docker`; the user may prefer to add a script rather than run the generic path unattended.
6. **IDEA gate — every one.** For each arg, resolve the IDEA file (glob both `docs/ideas/` and `docs/archive/*/`) and verify the safety gates in [`references/safety-gates.md`](references/safety-gates.md). Any failure → abort the batch before starting, list the offenders. Belt-and-suspenders: `auto_safe: true` in frontmatter AND explicit arg presence, not either/or.
7. **Budget sanity.** If the caller passed `--budget-minutes=N` or `--budget-tokens=N`, record it. Per-IDEA default timeout: 60 minutes of wall clock. Per-batch default: `len(ideas) * 60` minutes.

### 2. Per-IDEA execution loop

For each IDEA in the list, in argument order, sequentially:

1. **Worktree bootstrap.** Follow [`references/worktree-lifecycle.md`](references/worktree-lifecycle.md):
   - `git worktree add ../<project>-auto-<slug> -b auto/<slug> origin/main`
   - `cd` into the worktree
   - Run `tools/sprint-auto-bootstrap.sh` (project-local, sets up `.env` with sentinels, writes compose override with port offset, brings up stack, runs post-up init). If the script exits non-zero, record failure and skip to next IDEA — do not proceed with a half-initialised stack.
   - Append start entry to `docs/archive/<dir>/auto-run-YYYY-MM-DD.md` (see [`assets/auto-run-log-template.md`](assets/auto-run-log-template.md)).

2. **Plan the idea.** Invoke the `plan` skill against the IDEA slug. Because step 1 of [`references/safety-gates.md`](references/safety-gates.md) guaranteed the IDEA body is thick, the thin-input bootstrap will skip and planning runs non-interactively. The architect review pass runs; if the verdict is `REJECTED`, record failure and skip to next IDEA. If `REQUIRES ABSTRACTION`, the plan author already incorporated findings — proceed.

3. **Work the plan.** Invoke the `work` skill against the emitted plan. Per `RULE_git-safety`, the worktree is on `auto/<slug>` (not main), so commits flow freely. `/work` dispatches personas, commits per plan item, runs verification, and opens the PR on success.

4. **Capture outcome.**
   - Success: PR URL recorded in the auto-run log + a per-batch summary at `docs/archive/auto-run-<timestamp>-summary.md` in the primary tree.
   - Verification fail: log the failure, route-back note ("plan/open-questions section has diagnostic"), leave worktree and branch intact for morning inspection. **Do not force-merge, do not rollback, do not retry** — the human decides.
   - Unrecoverable error (docker down, disk full, exception inside a persona call): log, abort the remaining batch, surface the class of failure; subsequent IDEAs are not a good bet if the environment is degraded.

5. **Move to next IDEA.** No teardown of the previous worktree; each stack stays up until the human reviews in the morning. Parallel stacks are fine per `RULE_parallel-worktree-docker` because the bootstrap script allocated non-colliding ports.

### 3. Batch-level handoff

When the loop ends (all IDEAs processed, or batch aborted mid-way):

1. Write `docs/archive/auto-run-<ISO-timestamp>-summary.md` in the primary tree. See [`assets/auto-run-log-template.md`](assets/auto-run-log-template.md) for shape — one-paragraph per IDEA, with PR URL or failure reason, plus links to the per-IDEA auto-run logs.
2. Print a single summary block to stdout:

   ```text
   sprint-auto batch complete — 2026-04-20T23:47:12Z

   ✅ IDEA-050 sync-retry-backoff     → https://github.com/.../pull/123
   ✅ IDEA-051 modal-dismiss-focus    → https://github.com/.../pull/124
   ⚠️  IDEA-052 alpine-event-bus      → plan REJECTED (architect); see worktree
   ❌ IDEA-053 cache-invalidation     → verification failed (test_cache.py); see worktree

   Worktrees preserved — review + teardown at your convenience.
   Batch summary: docs/archive/auto-run-2026-04-20T23-47-12Z-summary.md
   ```

3. Do **not** delete worktrees. Do **not** teardown docker stacks. Leave everything for the human. Teardown belongs in a separate skill / manual cleanup — mixing it into the autopilot risks erasing diagnostics.

## Interaction rules

- **Belt-and-suspenders opt-in.** Frontmatter `auto_safe: true` AND explicit arg allowlist. Never scan-mode in v1; curation is the whole point.
- **No merges, ever.** The skill stops at PR creation. `gh pr merge`, `git push` to protected branches, anything that crosses the HITL gate — forbidden. Re-read `RULE_git-safety` if tempted.
- **No destructive recovery.** On failure, the skill logs and moves on. It does not `git reset --hard`, does not delete the branch, does not force-push. The failing worktree is a diagnostic artefact.
- **Sequential in v1.** Parallel IDEA execution on a VPS invites host contention (CPU, disk, RAM, parallel pip installs) and makes failure-log attribution harder. Add concurrency later if the overnight throughput demands it.
- **Respect the architect.** If the plan-time architect review comes back `REJECTED`, that IDEA is done for this batch. The plan is wrong; do not fall into "well the agent thought it was safe" — trust the review.
- **Abort-the-batch triggers** (not just skip-the-IDEA): docker daemon lost, disk full, the bootstrap script exits with a class of error flagged unrecoverable (see [`references/safety-gates.md`](references/safety-gates.md)), token/minute budget blown at batch scope.

## When NOT to use these patterns

- **Single IDEA with supervision available.** Use `/plan` + `/work` directly — less ceremony.
- **Any IDEA without `auto_safe: true`.** Tag it first via `/idea <slug>` update, with an explicit `auto_safe_reason` in frontmatter explaining why the human cleared it. Don't bypass the gate.
- **Priority: high IDEAs.** High-priority work deserves human attention during execution. The skill refuses `priority: high` even with `auto_safe: true` (if the user really means it, they can explicitly override via `--include-high`, not the default path).
- **IDEAs touching sensitive paths.** See [`references/safety-gates.md`](references/safety-gates.md) for the default-deny list (migrations that drop tables, anything under `.env*`, `docker-compose.yml` base file, CI/CD pipelines, auth middleware). Override only via explicit `sensitive_paths_cleared: true` in the IDEA frontmatter.
- **First run on a new project.** Run one IDEA manually through `/plan` and `/work` first, confirm the bootstrap script works end-to-end, then trust the batch runner.

## References

- [references/safety-gates.md](references/safety-gates.md) — opt-in criteria, automatic disqualifiers, halt conditions
- [references/worktree-lifecycle.md](references/worktree-lifecycle.md) — project-bootstrap-script contract, port offset strategy, teardown policy
- [assets/auto-run-log-template.md](assets/auto-run-log-template.md) — per-IDEA and batch-summary log shape
- [rules/RULE_parallel-worktree-docker.md](../../rules/RULE_parallel-worktree-docker.md) — underlying worktree + docker isolation contract
- [rules/RULE_git-safety.md](../../rules/RULE_git-safety.md) — the HITL boundary the skill must never cross
- [rules/RULE_ideas-location-status.md](../../rules/RULE_ideas-location-status.md) — how IDEA files migrate; `/plan` does the move inside the worktree
- [skills/plan/SKILL.md](../plan/SKILL.md) — stage 2, invoked per IDEA
- [skills/work/SKILL.md](../work/SKILL.md) — stage 3, invoked per plan
- [docs/SPRINT_WORKFLOW.md](../../docs/SPRINT_WORKFLOW.md) — the sprint workflow this skill wraps

---

**Last Updated**: 2026-04-20 (initial — overnight unattended wrapper around /plan → /work → PR)
