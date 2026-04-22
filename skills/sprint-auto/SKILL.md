---
name: sprint-auto
description: Unattended overnight orchestrator — run a curated list of opt-in IDEAs through /plan → /work → /bugbot-loop (deliverables) → escalation → /wrap-docs → /bugbot-loop (docs) → escalation → pre-merge docker teardown → /compound (mind-vault, each itself bugbot-looped) in isolated per-IDEA git worktrees with independent docker-compose stacks. Enforces belt-and-suspenders safety gates (auto_safe frontmatter + explicit arg allowlist), resolves T2/T3 bugbot escalations autonomously with rollback-able commits (caps per pass — 20 deliverables, 5 docs, 5 mind-vault compound, each independent), halts only at the HITL merge boundary per RULE_git-safety. Wraps the full sprint workflow for VPS / overnight execution.
---

# sprint-auto

Autonomous wrapper around the full sprint workflow (`/plan → /work → /bugbot-loop → /wrap → /bugbot-loop → /compound`) for unattended overnight execution on a VPS. Takes a curated list of IDEAs that the human has pre-cleared as low-risk, runs each one end-to-end — planning, work, bugbot review of deliverables, escalation resolution, pre-merge documentation sweep, bugbot review of docs, docker teardown, and mind-vault compounding (each compound PR itself bugbot-looped) — in its own git worktree with its own docker-compose project. Stops at the one HITL boundary that matters: merge to a protected branch.

This skill is **not** a substitute for human review — it is a throughput multiplier for ideas where the human has already decided "no harm trying". The human still reviews every PR before merging. The skill's job is to close the gap between "I have 10 low-risk IDEAs in the backlog" and "I have 10 PRs, each already drained through bugbot on both deliverables and docs, with cross-project learnings promoted to mind-vault, waiting on my desk in the morning".

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
7. **Budget sanity.** If the caller passed `--budget-minutes=N` or `--budget-tokens=N`, record it. Per-IDEA default timeout: **300 minutes** of wall clock (accommodates two bugbot passes with generous escalation budgets — 20 deliverables attempts × ~10 min + 5 docs attempts × ~5 min + bugbot-loop's own activity). Per-batch default: `len(ideas) * 300` minutes. For overnight runs, this is a soft ceiling; individual IDEAs that clean-signal early return budget to the pool.

### 2. Per-IDEA execution loop

For each IDEA in the list, in argument order, sequentially. The full state machine is in [`references/post-pr-sequence.md`](references/post-pr-sequence.md); it spans states **S0–S11** per IDEA. Each step heading below tags the state it covers (e.g. `(S3)`). The one mapping wrinkle: steps 4a and 6a are inline escalation branches covering states S4 and S7 respectively, which is why step 7 has no body — it keeps steps 8–11 aligned with states S8–S11.

**Canonical failure-path invariant** (applies throughout this loop): every failure path re-enters the happy path at **step 8 (pre-merge teardown)**, then flows through **step 9 (harvest) → step 10 (log) → step 11 (next IDEA)**. Step 8 is a no-op when there is nothing running to tear down (bootstrap failure); step 9 may queue fewer candidates; step 10 is **always** written — the log IS the diagnostic artefact.

1. **Worktree bootstrap (S0).** Follow [`references/worktree-lifecycle.md`](references/worktree-lifecycle.md):
   - `git worktree add ../<project>-auto-<slug> -b auto/<slug> origin/main`
   - `cd` into the worktree
   - Run `tools/sprint-auto-bootstrap.sh` (project-local, sets up `.env` with sentinels, writes compose override with port offset, brings up stack, runs post-up init). If the script exits non-zero, re-enter at step 8 with `outcome: bootstrap_failed` — step 8 will be a no-op because there is no complete stack to stop, but steps 9 + 10 still run.
   - Append start entry to `docs/archive/<dir>/auto-run-YYYY-MM-DD.md` (see [`assets/auto-run-log-template.md`](assets/auto-run-log-template.md)).

2. **Plan the idea (S1).** Invoke the `plan` skill against the IDEA slug. Because step 1 of [`references/safety-gates.md`](references/safety-gates.md) guaranteed the IDEA body is thick, the thin-input bootstrap will skip and planning runs non-interactively. The architect review pass runs; if the verdict is `REJECTED`, re-enter at step 8 with `outcome: plan_rejected` — the stack came up at step 1, so teardown runs normally. If `REQUIRES ABSTRACTION`, the plan author already incorporated findings — proceed.

3. **Work the plan (S2).** Invoke the `work` skill against the emitted plan. Per `RULE_git-safety`, the worktree is on `auto/<slug>` (not main), so commits flow freely. `/work` dispatches personas, commits per plan item, runs verification, and opens the PR on success. If `/work` returns without opening a PR (verification failed, plan infeasible), re-enter at step 8 with `outcome: verification_failed`. Edge case: if `/work` crashed and left docker state inconsistent, re-enter at step 9 instead (skip step 8) with `docker_teardown: skipped_work_crash` — preserving the broken stack is part of the diagnostic.

4. **Bugbot-loop the PR — deliverables pass (S3).** Invoke `/bugbot-loop <PR>` on the PR `/work` just opened. Bugbot-loop has its own bounds (180 min active, 20 idle polls, 20 commits) and autonomously handles Tier-1 findings, handing Tier 2/3 back to the caller. Under sprint-auto the "caller" is this skill, not the human — so bugbot-loop's hand-back is never the end of the line. See [`references/escalation-policy.md`](references/escalation-policy.md). Three outcomes:
   - **Clean** (BUGBOT_CLEAN_SIGNAL for current head) → proceed to step 5 (/wrap-docs).
   - **Hand-back with Tier 2/3 findings** → proceed to step 4a (escalation).
   - **Bugbot budget exhausted** → proceed to step 5 with `deliverables_bugbot_outcome: budget_exceeded` in the log; docs pass still runs.

   **4a. Escalation resolution — deliverables pass (S4).** Tier 2 auto-approved (pre-authorized by the `auto_safe` frontmatter + explicit-arg allowlist), Tier 3 attempted (not handed back). Maximum thinking effort per attempt. Each attempt is a **fresh commit**; if it needs a different angle, `git revert <previous-attempt-sha>` before trying again — do not pile broken fixes on top of each other. Cap: **20 attempt cycles on this pass** (deliverables bugs have long tails — bugbot may re-flag a T2 multiple times before the right angle lands; being stingy here converts would-be resolutions into shipped-non-clean). After the cap, ship-non-clean for deliverables and proceed to step 5 — the docs pass still runs; a PR with known unresolved deliverables findings is still a valid PR for human review. Log every attempt's SHA + approach + outcome into the auto-run log. Return to step 4 after each attempt to let bugbot re-evaluate (step 4 is the bugbot-loop invocation; step 3 is `/work`, which must not be re-run).

5. **/wrap-docs — pre-merge documentation commit (S5).** Now that deliverables are bugbot-clean (or the deliverables 20-attempt cap is reached), invoke the documentation-sweep phase of the wrap discipline: add a DEVELOPMENT_LOG entry for this IDEA's changes, scan for downstream docs (README, guides, reference files) that reference paths/flags/patterns the PR changed, update what's broken. Commit to the same `auto/<slug>` branch so the docs land in the open PR and bugbot can review them alongside the code.

   **Important scope:** this is the **documentation-only** subset of `/wrap`. Do NOT flip the IDEA's frontmatter to `status: complete` (the PR has not merged — pre-merge flip would lie in the paper trail). Do NOT run the post-merge worktree-teardown chores (`-v` volume removal, `git worktree remove`, branch delete) — those are the human's job post-merge. The invocation shape is "apply /wrap's documentation discipline pre-merge on the open PR's branch", not a full /wrap run.

   If there's genuinely no documentation work (the IDEA changed zero paths referenced in docs, added no new features worth a devlog entry), emit a trivial commit like `docs(archive): IDEA-NNN no-op pre-merge docs check` with a one-line rationale in the log body. The trivial commit keeps the state machine uniform — step 6 runs regardless.

6. **Bugbot-loop the PR — docs pass (S6).** Invoke `/bugbot-loop <PR>` a second time, now on the PR with the docs commit(s) on top. Same three outcomes as step 3:
   - **Clean** → proceed to step 8 (teardown).
   - **Hand-back with Tier 2/3 findings** → proceed to step 6a (docs escalation).
   - **Bugbot budget exhausted** → proceed to step 8 with `docs_bugbot_outcome: budget_exceeded` in the log.

   **6a. Escalation resolution — docs pass (S7).** Same contract as step 4a: fresh commits, `git revert` between attempts, cap of **5 cycles on this pass** (documentation findings are mostly stylistic or reference-drift — they converge fast or they don't; 5 is generous enough to try substantially different angles without wasting budget on genuinely ambiguous editorial calls). Independent budget from the deliverables-pass cap — up to 25 attempts total per IDEA across both passes. After the cap, ship-non-clean for docs and proceed to step 8. Return to step 6 after each attempt.

7. *(Reserved — state S7 (docs-pass escalation) is documented as sub-step 6a above. This slot is left empty to keep steps 8–11 aligned with states S8–S11 respectively. For the full state-to-step mapping see [`references/post-pr-sequence.md`](references/post-pr-sequence.md).)*

8. **Pre-merge teardown — docker stack down (S8).** Stop the worktree's docker stack now that both bugbot passes are done (clean, capped, or budget-exceeded — same destination). Keep the **worktree filesystem** (`git worktree list` still shows it; the reviewer can `cd` in for post-hoc investigation) and the **docker volumes** (state preserved for inspection), but stop the running containers:
   ```bash
   cd ~/projects/<project>-auto-<slug>
   docker compose down       # drops containers; keeps volumes by default
   ```
   Use `down` (not `down -v`) to preserve DB / MinIO / ES state. Full teardown (`-v` + `git worktree remove` + branch delete) is still the human's morning chore via `/wrap <NNN>` post-merge.

   **No-op cases:** if step 1 failed (bootstrap never completed), there is no complete stack; step 8 exits cleanly without error, and the log records `docker_teardown: skipped_bootstrap_failure`. If step 3 detected a `/work` crash with inconsistent stack state, step 8 is skipped entirely to preserve the diagnostic; the log records `docker_teardown: skipped_work_crash`.

9. **Capture per-IDEA compound candidates (S9).** Harvest learnings from the IDEA's run — bugbot findings (from either pass) that exposed patterns, escalation attempts that revealed new recipes, infrastructure gaps (e.g. missing project-local tooling) discovered during bootstrap, downstream-docs drift patterns discovered during step 5's sweep. Do **not** invoke `/compound` yet — queue candidates into a per-batch list for consolidation at step 12. Per-batch aggregation makes cross-IDEA patterns visible; per-IDEA compound would miss them. On failure paths, harvest still runs but may queue fewer candidates — plan-rejection patterns and verification-failure patterns are themselves valuable compound signals (architect blind-spot, test-env fragility).

10. **Finalise the per-IDEA auto-run log (S10).** Fields written:
    - `outcome` ∈ `success | bugbot_clean | bugbot_unresolved | budget_exceeded | bootstrap_failed | plan_rejected | verification_failed | aborted` (reflects the whole IDEA run; `bugbot_unresolved` means *at least one* pass ended with unresolved findings; `aborted` means the batch was aborted while this IDEA was mid-run)
    - `pr_url` (null if no PR opened)
    - `deliverables_bugbot_outcome` ∈ `clean | unresolved | budget_exceeded | skipped_no_pr`
    - `deliverables_escalation_attempts` (0–20)
    - `docs_bugbot_outcome` ∈ `clean | unresolved | budget_exceeded | skipped_no_pr | skipped_failure_pre_pr`
    - `docs_escalation_attempts` (0–5)
    - `docker_teardown` ∈ `stopped | skipped_bootstrap_failure | skipped_work_crash`
    - `compound_candidates_queued` — list with types + notes
    - Attempt tables for both passes (SHAs, approaches, bugbot outcomes)

    Commit + push; the log rides into the PR on the `auto/<slug>` branch.

11. **Move to next IDEA (S11).** The worktree stays on disk; its docker stack is down. Next IDEA's worktree gets a fresh stack on the next port offset.

### 3. Batch-level compound + mind-vault bugbot-loop (S12–S15)

When all IDEAs have been processed (or the batch aborted mid-way):

1. **Consolidate compound candidates (S12 prep)** harvested from every per-IDEA step 9. Cross-IDEA patterns get de-duplicated here: if three IDEAs independently surfaced the same bugbot finding category (on either pass), it's a stronger compound candidate than any single instance.

2. **Invoke `/compound` per candidate — autonomous mode (S12).** The compound skill's Shape-C narrative probe normally asks up to three questions before routing; under sprint-auto those answers come from the compound candidate's own metadata (the IDEA's scope, the finding's category, whether the pattern appeared in more than one project's codebase). The invocation of `/sprint-auto` by the user is the *transitive* confirmation that compound's "Never silently promote to mind-vault" interaction rule requires — sprint-auto is not silent; it publishes its compound candidates in the auto-run log before promoting, and the morning reviewer can reject any mind-vault PR they disagree with.

3. **Each mind-vault PR → its own `/bugbot-loop` session (S13 + S14).** Once `/compound` produces a PR on `compound/YYYY-MM-DD-<slug>` in the mind-vault repo, invoke `/bugbot-loop <mind-vault-PR>` with the same escalation policy from steps 4a/6a above. Cap: **5 attempt cycles** (single-pass here — mind-vault compound PRs are documentation by nature, so the deliverables/docs split collapses into one pass, and the docs-pass 5-attempt budget applies). If bugbot doesn't clear, the PR still stands — it's the human reviewer's decision whether the remaining finding blocks merge. After bugbot outcome, update the compound-PR body with the bugbot summary so the reviewer sees the state at a glance.

4. **Write `docs/archive/auto-run-<ISO-timestamp>-summary.md` (S15 artefact)** in the primary tree. See [`assets/auto-run-log-template.md`](assets/auto-run-log-template.md) for shape — one-paragraph per IDEA, per-IDEA bugbot outcomes (deliverables + docs split), teardown status, and a **Compound section** listing each mind-vault PR produced, its bugbot outcome, and its URL.

5. **Print the summary block to stdout (S15):**

   ```text
   sprint-auto batch complete — 2026-04-20T23:47:12Z

   IDEAs (project PRs):
   ✅ IDEA-050 sync-retry-backoff     → https://github.com/.../pull/123  (bugbot: deliverables clean / docs clean)
   ✅ IDEA-051 modal-dismiss-focus    → https://github.com/.../pull/124  (bugbot: deliverables 2 T3 unresolved / docs clean; reviewer to decide)
   ⚠️  IDEA-052 alpine-event-bus      → plan REJECTED (architect); see worktree
   ❌ IDEA-053 cache-invalidation     → verification failed (test_cache.py); see worktree

   Compound (mind-vault PRs):
   ✅ RULE_htmx-partial-boundary-check  → https://github.com/.../pull/78   (bugbot: clean)
   ⚠️  skill:curator pass-3 addendum     → https://github.com/.../pull/79   (bugbot: 1 T3 unresolved)

   Docker stacks: stopped (containers down, volumes retained). Worktrees preserved.
   Batch summary: docs/archive/auto-run-2026-04-20T23-47-12Z-summary.md
   ```

6. **Worktree preservation discipline.** Containers are stopped at step 8 of each IDEA's loop. Worktree filesystems **remain** — they are the diagnostic artefact the human reviews against; removing them would erase state. Full teardown (`docker compose down -v`, `git worktree remove`, `git branch -D`) is still the human's chore via `/wrap <NNN>` post-merge.

### 4. Post-merge reminders (still human)

The batch summary's closing section must list `/wrap NNN` for each merged IDEA — the **post-merge** sweep (frontmatter flip `status: in-progress → complete`, `completed: <date>`, index rewrite, `-v` docker teardown, worktree removal) still needs merge to have happened first, which is the HITL gate. Note: the pre-merge docs work (devlog entry + downstream docs scan) already ran at step 5, so `/wrap NNN` post-merge is the cleanup + frontmatter tail, not the full devlog write:

```markdown
## Next steps (post-merge)

For each IDEA whose PR you merge, run `/wrap NNN` from the primary tree —
it flips the frontmatter to `status: complete`, re-sorts the ideas index,
removes the worktree docker volumes, removes the worktree itself, and
sweeps for any downstream docs drift introduced during review. The devlog
entry is already in place (sprint-auto's step 5 wrote it pre-merge).

- `/wrap 050` → finalises IDEA-050 (worktree `../<project>-auto-sync-retry-backoff`)
- `/wrap 051` → finalises IDEA-051 (worktree `../<project>-auto-modal-dismiss-focus`)
```

No `/compound` reminder here — compound ran in section 3 above. The mind-vault PRs are already in front of the reviewer. If the reviewer disagrees with anything compound promoted, they can close the mind-vault PR without merging — no project-local state depends on it.

## Interaction rules

- **Belt-and-suspenders opt-in.** Frontmatter `auto_safe: true` AND explicit arg allowlist. Never scan-mode in v1; curation is the whole point.
- **No merges, ever.** The skill stops at PR creation (project PRs AND mind-vault compound PRs). `gh pr merge`, `git push` to protected branches, anything that crosses the HITL gate — forbidden. Re-read `RULE_git-safety` if tempted.
- **Rollback-able commits only for escalation resolution.** During the step-4a and step-6a bugbot-escalation work, the skill MAY commit multiple attempts, each revertable via `git revert`. It MAY NOT force-push, rewrite history, or amend commits produced by `/work` (deliverables pass) or by the documentation sweep (docs pass) — those are part of the PR's review history. If a fix attempt goes wrong, the correct move is `git revert <bad-sha>` + a fresh attempt commit, not `git reset`.
- **Two-pass bugbot-loop contract.** Every successful-through-PR IDEA run receives **two** bugbot-loop invocations: one on deliverables (step 4 / S3) and one on docs (step 6 / S6). Each has its own independent escalation budget — 20 attempts for deliverables (step 4a / S4), 5 attempts for docs (step 6a / S7). Skipping the docs pass is never correct on the happy path — if step 5 produced no docs changes, step 6 still runs and should clean-signal immediately against the (trivially-committed) docs state.
- **Sequential in v1.** Parallel IDEA execution on a VPS invites host contention (CPU, disk, RAM, parallel pip installs) and makes failure-log attribution harder. Add concurrency later if the overnight throughput demands it.
- **Respect the architect.** If the plan-time architect review comes back `REJECTED`, that IDEA is done for this batch. The plan is wrong; do not fall into "well the agent thought it was safe" — trust the review.
- **Non-clean bugbot is OK to ship-for-review.** After the per-pass cap is hit (20 on deliverables, 5 on docs, 5 on mind-vault compound PRs), an IDEA with unresolved Tier 2/3 findings still produces a valid PR. The morning reviewer decides whether the remaining findings block merge. Do not block the pipeline on perfection; transparency in the auto-run log (attempt SHAs, approaches, outcomes) is the contract.
- **Compound transitive confirmation.** `/compound`'s "Never silently promote to mind-vault" rule is satisfied by sprint-auto's own invocation: the user launched sprint-auto knowing compound runs at end-of-batch, and every mind-vault PR produced lands in the summary for review. Sprint-auto IS the confirmation.
- **Abort-the-batch triggers** (not just skip-the-IDEA): docker daemon lost, disk full, the bootstrap script exits with a class of error flagged unrecoverable (see [`references/safety-gates.md`](references/safety-gates.md)), token/minute budget blown at batch scope, mind-vault repo becomes unreachable during section 3.
- **Priority is queue order, not a safety gate.** `priority: high` / `medium` / `low` affects the order in which the human schedules ideas — it does not imply "how dangerous to automate". `auto_safe: true` is the authoritative safety signal. A High-priority idea tagged `auto_safe: true` by the human runs without special ceremony; a Low-priority idea without `auto_safe` stays out of every batch. Don't stack redundant gates.

## When NOT to use these patterns

- **Single IDEA with supervision available.** Use `/plan` + `/work` directly — less ceremony.
- **Any IDEA without `auto_safe: true`.** Tag it first via `/idea <slug>` update, with an explicit `auto_safe_reason` in frontmatter explaining why the human cleared it. Don't bypass the gate.
- **IDEAs touching sensitive paths.** See [`references/safety-gates.md`](references/safety-gates.md) for the default-deny list (migrations that drop tables, anything under `.env*`, `docker-compose.yml` base file, CI/CD pipelines, auth middleware). Override only via explicit `sensitive_paths_cleared: true` in the IDEA frontmatter.
- **First run on a new project.** Run one IDEA manually through `/plan` and `/work` first, confirm the bootstrap script works end-to-end, then trust the batch runner.

## References

- [references/safety-gates.md](references/safety-gates.md) — opt-in criteria, automatic disqualifiers, halt conditions
- [references/worktree-lifecycle.md](references/worktree-lifecycle.md) — project-bootstrap-script contract, port offset strategy, teardown policy
- [references/post-pr-sequence.md](references/post-pr-sequence.md) — the S0–S15 state machine: bootstrap → plan → work → deliverables bugbot + escalation → /wrap-docs → docs bugbot + escalation → teardown → harvest → log → (batch) compound + mind-vault bugbot
- [references/escalation-policy.md](references/escalation-policy.md) — how T2/T3 (and theoretical T4+) bugbot findings get resolved autonomously: rollback discipline, per-pass attempt caps (20 deliverables / 5 docs / 5 mind-vault compound), when non-clean ship
- [assets/auto-run-log-template.md](assets/auto-run-log-template.md) — per-IDEA and batch-summary log shape (includes split deliverables + docs bugbot fields, compound fields)
- [rules/RULE_parallel-worktree-docker.md](../../rules/RULE_parallel-worktree-docker.md) — underlying worktree + docker isolation contract
- [rules/RULE_git-safety.md](../../rules/RULE_git-safety.md) — the HITL boundary the skill must never cross
- [rules/RULE_ideas-location-status.md](../../rules/RULE_ideas-location-status.md) — how IDEA files migrate; `/plan` does the move inside the worktree
- [commands/bugbot-loop.md](../../commands/bugbot-loop.md) — invoked twice per IDEA (deliverables + docs) and once per mind-vault compound PR
- [skills/plan/SKILL.md](../plan/SKILL.md) — invoked per IDEA (step 2)
- [skills/work/SKILL.md](../work/SKILL.md) — invoked per plan (step 3)
- [skills/wrap/SKILL.md](../wrap/SKILL.md) — step 5 invokes its documentation-sweep discipline pre-merge; the full /wrap (frontmatter flip + `-v` teardown + worktree remove) still runs post-merge as the human's chore
- [skills/compound/SKILL.md](../compound/SKILL.md) — invoked at batch end (section 3) for cross-project learnings; each mind-vault PR it produces is itself bugbot-looped
- [docs/SPRINT_WORKFLOW.md](../../docs/SPRINT_WORKFLOW.md) — the sprint workflow this skill wraps

---

**Last Updated**: 2026-04-22 (structural reconciliation pass: S0–S11 per-IDEA + S12–S15 batch state machine, canonical failure-path invariant (re-enter at step 8, harvest + log always run), two-pass bugbot-loop inserted — deliverables pass after /work, docs pass after /wrap-docs. Escalation caps bumped from a placeholder 3 to calibrated per-pass numbers: 20 deliverables / 5 docs / 5 mind-vault compound, each independent — reflects real tail-length of T2/T3 resolution work.)
