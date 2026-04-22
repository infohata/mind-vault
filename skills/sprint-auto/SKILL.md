---
name: sprint-auto
description: Unattended overnight orchestrator — run a curated list of opt-in IDEAs through /plan → /work → /bugbot-loop → escalation-resolution → pre-merge docker teardown → /compound (mind-vault, each itself bugbot-looped) in isolated per-IDEA git worktrees with independent docker-compose stacks. Enforces belt-and-suspenders safety gates (auto_safe frontmatter + explicit arg allowlist), resolves T2/T3 bugbot escalations autonomously with rollback-able commits, halts only at the HITL merge boundary per RULE_git-safety. Wraps the full sprint workflow for VPS / overnight execution.
---

# sprint-auto

Autonomous wrapper around the full sprint workflow (`/plan → /work → /bugbot-loop → /compound`) for unattended overnight execution on a VPS. Takes a curated list of IDEAs that the human has pre-cleared as low-risk, runs each one end-to-end — planning, work, bugbot review, escalation resolution, docker teardown, and mind-vault compounding (each compound PR itself bugbot-looped) — in its own git worktree with its own docker-compose project. Stops at the one HITL boundary that matters: merge to a protected branch.

This skill is **not** a substitute for human review — it is a throughput multiplier for ideas where the human has already decided "no harm trying". The human still reviews every PR before merging. The skill's job is to close the gap between "I have 10 low-risk IDEAs in the backlog" and "I have 10 PRs, each already drained through bugbot and with cross-project learnings promoted to mind-vault, waiting on my desk in the morning".

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

For each IDEA in the list, in argument order, sequentially. The full state machine is in [`references/post-pr-sequence.md`](references/post-pr-sequence.md); the summary below gives the nine steps.

1. **Worktree bootstrap.** Follow [`references/worktree-lifecycle.md`](references/worktree-lifecycle.md):
   - `git worktree add ../<project>-auto-<slug> -b auto/<slug> origin/main`
   - `cd` into the worktree
   - Run `tools/sprint-auto-bootstrap.sh` (project-local, sets up `.env` with sentinels, writes compose override with port offset, brings up stack, runs post-up init). If the script exits non-zero, record failure and skip to next IDEA — do not proceed with a half-initialised stack.
   - Append start entry to `docs/archive/<dir>/auto-run-YYYY-MM-DD.md` (see [`assets/auto-run-log-template.md`](assets/auto-run-log-template.md)).

2. **Plan the idea.** Invoke the `plan` skill against the IDEA slug. Because step 1 of [`references/safety-gates.md`](references/safety-gates.md) guaranteed the IDEA body is thick, the thin-input bootstrap will skip and planning runs non-interactively. The architect review pass runs; if the verdict is `REJECTED`, record failure and jump to step 6 (pre-merge wrap) — the stack came up at step 1 so there are containers to stop. If `REQUIRES ABSTRACTION`, the plan author already incorporated findings — proceed.

3. **Work the plan.** Invoke the `work` skill against the emitted plan. Per `RULE_git-safety`, the worktree is on `auto/<slug>` (not main), so commits flow freely. `/work` dispatches personas, commits per plan item, runs verification, and opens the PR on success. If `/work` returns without opening a PR (verification failed, plan infeasible), record failure and jump to step 6 (pre-merge wrap) — there's still a worktree to tear down.

4. **Bugbot-loop the PR.** Invoke `/bugbot-loop <PR>` on the PR `/work` just opened. Bugbot-loop has its own bounds (180 min active, 20 idle polls, 20 commits) and will autonomously handle Tier-1 findings, hand back Tier 2/3 to the caller. Under sprint-auto the "caller" is this skill, not the human — so bugbot-loop's hand-back is never the end of the line. See [`references/escalation-policy.md`](references/escalation-policy.md) for the full contract. Three outcomes:
   - **Clean** (bugbot posted `BUGBOT_CLEAN_SIGNAL` for current head) → proceed to step 6.
   - **Hand-back with Tier 2/3 findings** → proceed to step 5.
   - **Bugbot budget exhausted without resolution** (180-min active, 20 idle polls) → accept current state, proceed to step 6 with `bugbot_outcome: budget_exceeded` in the auto-run log.

5. **Escalation resolution — autonomous.** Under sprint-auto, Tier 2 findings are auto-approved (the whole run is pre-authorized by the `auto_safe` frontmatter plus explicit-arg allowlist), and Tier 3 findings are attempted rather than escalated to a human. Maximum thinking effort per attempt. Each attempt is a **fresh commit** so the state is rollback-able: if the next attempt needs a different angle, `git revert <previous-attempt-sha>` before trying again — do not pile broken fixes on top of each other. Cap: **3 attempt cycles per IDEA**. After the cap, accept the non-clean state and proceed to step 6 — a PR with known unresolved findings is still a valid PR for human review; do not block the pipeline on perfection. Log the escalation attempt history (SHAs, approaches, outcomes) into the per-IDEA auto-run log for morning review.

6. **Pre-merge wrap — docker teardown.** Stop the worktree's docker stack now that bugbot is satisfied (or the 3-attempt cap is reached). Keep the **worktree filesystem** (`git worktree list` still shows it, reviewer can `cd` in for post-hoc investigation), but stop the containers so they're not burning host CPU / holding ports while the human sleeps:
   ```bash
   cd ~/projects/<project>-auto-<slug>
   docker compose down       # drops containers; keeps volumes by default
   ```
   Use `down` (not `down -v`) to preserve DB / MinIO state in case the reviewer wants to inspect. Full teardown (`-v` + `git worktree remove` + branch delete) is still the human's morning chore via `/wrap <NNN>`.

7. **Capture per-IDEA compound candidates.** Harvest learnings from the IDEA's run — bugbot findings that exposed patterns, escalation attempts that revealed new recipes, infrastructure gaps (e.g. missing project-local tooling) discovered during bootstrap. Do **not** invoke `/compound` yet — queue candidates into a per-batch list for consolidation. Per-batch aggregation makes cross-IDEA patterns visible; per-IDEA compound would miss them.

8. **Finalise the per-IDEA auto-run log** with outcome (`success | bugbot_clean | bugbot_unresolved | budget_exceeded | bootstrap_failed | plan_rejected | verification_failed`), PR URL, bugbot-loop summary (cycles, findings auto-fixed, escalation attempts), teardown status, and compound candidates queued. Commit + push (the log is on the `auto/<slug>` branch so it rides into the PR).

9. **Move to next IDEA.** The worktree stays on disk; its docker stack is down. Next IDEA's worktree gets a fresh stack on the next port offset.

### 3. Batch-level compound + mind-vault bugbot-loop

When all IDEAs have been processed (or the batch aborted mid-way):

1. **Consolidate compound candidates** harvested from every per-IDEA step 7. Across-IDEA patterns get de-duplicated here: if three IDEAs independently surfaced the same bugbot finding category, it's a stronger compound candidate than any single instance.

2. **Invoke `/compound` per candidate — autonomous mode.** The compound skill's Shape-C narrative probe normally asks up to three questions before routing; under sprint-auto those answers come from the compound candidate's own metadata (the IDEA's scope, the finding's category, whether the pattern appeared in more than one project's codebase). The invocation of `/sprint-auto` by the user is the *transitive* confirmation that compound's "Never silently promote to mind-vault" interaction rule requires — sprint-auto is not silent; it publishes its compound candidates in the auto-run log before promoting, and the morning reviewer can reject any mind-vault PR they disagree with.

3. **Each mind-vault PR → its own `/bugbot-loop` session.** Once `/compound` produces a PR on `compound/YYYY-MM-DD-<slug>` in the mind-vault repo, invoke `/bugbot-loop <mind-vault-PR>` with the same escalation policy from step 5 above. Cap: 3 attempt cycles. If bugbot doesn't clear, the PR still stands — it's the human reviewer's decision whether the remaining finding blocks merge. Same bug, same teardown discipline: after bugbot outcome, update the compound-PR body with the bugbot summary so the reviewer sees the state at a glance.

4. **Write `docs/archive/auto-run-<ISO-timestamp>-summary.md`** in the primary tree. See [`assets/auto-run-log-template.md`](assets/auto-run-log-template.md) for shape — one-paragraph per IDEA, per-IDEA bugbot outcome, teardown status, and a new **Compound section** listing each mind-vault PR produced, its bugbot outcome, and its URL.

5. Print the summary block to stdout:

   ```text
   sprint-auto batch complete — 2026-04-20T23:47:12Z

   IDEAs (project PRs):
   ✅ IDEA-050 sync-retry-backoff     → https://github.com/.../pull/123  (bugbot: clean)
   ✅ IDEA-051 modal-dismiss-focus    → https://github.com/.../pull/124  (bugbot: 2 T3 unresolved, reviewer to decide)
   ⚠️  IDEA-052 alpine-event-bus      → plan REJECTED (architect); see worktree
   ❌ IDEA-053 cache-invalidation     → verification failed (test_cache.py); see worktree

   Compound (mind-vault PRs):
   ✅ RULE_htmx-partial-boundary-check  → https://github.com/.../pull/78   (bugbot: clean)
   ⚠️  skill:curator pass-3 addendum     → https://github.com/.../pull/79   (bugbot: 1 T3 unresolved)

   Docker stacks: stopped (containers down, volumes retained). Worktrees preserved.
   Batch summary: docs/archive/auto-run-2026-04-20T23-47-12Z-summary.md
   ```

6. **Worktree preservation discipline.** Containers are stopped at step 6 of each IDEA's loop (or step 6 here for partial failures that never reached per-IDEA teardown). Worktree filesystems **remain** — they are the diagnostic artefact the human reviews against; removing them would erase state. Full teardown (`docker compose down -v`, `git worktree remove`, `git branch -D`) is still the human's chore via `/wrap <NNN>` post-merge.

### 4. Post-merge reminders (still human)

The batch summary's closing section must list `/wrap NNN` for each merged IDEA — the **post-merge** sweep (frontmatter flip `status: in-progress → complete`, `completed: <date>`, index rewrite, devlog entry, `-v` docker teardown, downstream docs scan) still needs merge to have happened first, which is the HITL gate:

```markdown
## Next steps (post-merge)

For each IDEA whose PR you merge, run `/wrap NNN` from the primary tree —
it flips the frontmatter, updates the devlog + index, removes the worktree
docker volumes, removes the worktree itself, and sweeps downstream docs.
Sprint-auto already stopped the containers; /wrap finishes the job.

- `/wrap 050` → finalises IDEA-050 (worktree `../<project>-auto-sync-retry-backoff`)
- `/wrap 051` → finalises IDEA-051 (worktree `../<project>-auto-modal-dismiss-focus`)
```

No `/compound` reminder here — compound ran in step 3 above. The mind-vault PRs are already in front of the reviewer. If the reviewer disagrees with anything compound promoted, they can close the mind-vault PR without merging — no project-local state depends on it.

## Interaction rules

- **Belt-and-suspenders opt-in.** Frontmatter `auto_safe: true` AND explicit arg allowlist. Never scan-mode in v1; curation is the whole point.
- **No merges, ever.** The skill stops at PR creation (project PRs AND mind-vault compound PRs). `gh pr merge`, `git push` to protected branches, anything that crosses the HITL gate — forbidden. Re-read `RULE_git-safety` if tempted.
- **Rollback-able commits only for escalation resolution.** During step 5 bugbot-escalation work, the skill MAY commit multiple attempts, each revertable via `git revert`. It MAY NOT force-push, rewrite history, or amend commits produced by `/work` — those are part of the PR's review history. If a bugbot fix attempt goes wrong, the correct move is `git revert <bad-sha>` + a fresh attempt commit, not `git reset`.
- **Sequential in v1.** Parallel IDEA execution on a VPS invites host contention (CPU, disk, RAM, parallel pip installs) and makes failure-log attribution harder. Add concurrency later if the overnight throughput demands it.
- **Respect the architect.** If the plan-time architect review comes back `REJECTED`, that IDEA is done for this batch. The plan is wrong; do not fall into "well the agent thought it was safe" — trust the review.
- **Non-clean bugbot is OK to ship-for-review.** After 3 escalation attempt cycles, an IDEA with unresolved Tier 2/3 findings still produces a valid PR. The morning reviewer decides whether the remaining findings block merge. Do not block the pipeline on perfection; transparency in the auto-run log is the contract.
- **Compound transitive confirmation.** `/compound`'s "Never silently promote to mind-vault" rule is satisfied by sprint-auto's own invocation: the user launched sprint-auto knowing compound runs at end-of-batch, and every mind-vault PR produced lands in the summary for review. Sprint-auto IS the confirmation.
- **Abort-the-batch triggers** (not just skip-the-IDEA): docker daemon lost, disk full, the bootstrap script exits with a class of error flagged unrecoverable (see [`references/safety-gates.md`](references/safety-gates.md)), token/minute budget blown at batch scope, mind-vault repo becomes unreachable during step 3.
- **Priority is queue order, not a safety gate.** `priority: high` / `medium` / `low` affects the order in which the human schedules ideas — it does not imply "how dangerous to automate". `auto_safe: true` is the authoritative safety signal. A High-priority idea tagged `auto_safe: true` by the human runs without special ceremony; a Low-priority idea without `auto_safe` stays out of every batch. Don't stack redundant gates.

## When NOT to use these patterns

- **Single IDEA with supervision available.** Use `/plan` + `/work` directly — less ceremony.
- **Any IDEA without `auto_safe: true`.** Tag it first via `/idea <slug>` update, with an explicit `auto_safe_reason` in frontmatter explaining why the human cleared it. Don't bypass the gate.
- **IDEAs touching sensitive paths.** See [`references/safety-gates.md`](references/safety-gates.md) for the default-deny list (migrations that drop tables, anything under `.env*`, `docker-compose.yml` base file, CI/CD pipelines, auth middleware). Override only via explicit `sensitive_paths_cleared: true` in the IDEA frontmatter.
- **First run on a new project.** Run one IDEA manually through `/plan` and `/work` first, confirm the bootstrap script works end-to-end, then trust the batch runner.

## References

- [references/safety-gates.md](references/safety-gates.md) — opt-in criteria, automatic disqualifiers, halt conditions
- [references/worktree-lifecycle.md](references/worktree-lifecycle.md) — project-bootstrap-script contract, port offset strategy, teardown policy
- [references/post-pr-sequence.md](references/post-pr-sequence.md) — the nine-step state machine after `/work` opens a PR: bugbot-loop → escalation → teardown → compound candidates
- [references/escalation-policy.md](references/escalation-policy.md) — how T2/T3 (and theoretical T4+) bugbot findings get resolved autonomously: rollback discipline, attempt cap, when non-clean ship
- [assets/auto-run-log-template.md](assets/auto-run-log-template.md) — per-IDEA and batch-summary log shape (includes bugbot + compound fields)
- [rules/RULE_parallel-worktree-docker.md](../../rules/RULE_parallel-worktree-docker.md) — underlying worktree + docker isolation contract
- [rules/RULE_git-safety.md](../../rules/RULE_git-safety.md) — the HITL boundary the skill must never cross
- [rules/RULE_ideas-location-status.md](../../rules/RULE_ideas-location-status.md) — how IDEA files migrate; `/plan` does the move inside the worktree
- [commands/bugbot-loop.md](../../commands/bugbot-loop.md) — stage 4, invoked per PR produced (both project and mind-vault compound PRs)
- [skills/plan/SKILL.md](../plan/SKILL.md) — stage 2, invoked per IDEA
- [skills/work/SKILL.md](../work/SKILL.md) — stage 3, invoked per plan
- [skills/compound/SKILL.md](../compound/SKILL.md) — stage 5, invoked at batch end for cross-project learnings; each mind-vault PR it produces is itself bugbot-looped
- [skills/wrap/SKILL.md](../wrap/SKILL.md) — post-merge documentation sweep; sprint-auto already stopped containers in step 6, `/wrap` finishes with `-v` + worktree removal + frontmatter flip (still human, still post-merge)
- [docs/SPRINT_WORKFLOW.md](../../docs/SPRINT_WORKFLOW.md) — the sprint workflow this skill wraps

---

**Last Updated**: 2026-04-22 (added full post-`/work` autonomy: /bugbot-loop drives review, T2/T3 escalations resolved with rollback-able commits capped at 3 attempts, docker stack teardown after bugbot clears, /compound promotes learnings to mind-vault with each compound PR itself bugbot-looped. HITL merge gate unchanged.)
