---
name: sprint-auto
description: Unattended overnight orchestrator — runs a curated list of opt-in IDEAs through /plan → /work → /bugbot-loop (deliverables) → /wrap (idea-only) → /bugbot-loop (docs) → integration phase (merge + batch wrap + tests + bugbot via [INTEGRATION] draft PR + forward-sync + re-bugbot) → /compound (mind-vault, bugbot-looped). Single integration-worktree docker stack at port offset +30000 is the only stack of the batch; per-IDEA worktrees are pure code surfaces with verification routed via SPRINT_AUTO_INTEGRATION_WORKTREE env var. Full DB reset between IDEAs guarantees per-PR PRs are independently deliverable. Enforces auto_safe frontmatter + explicit arg allowlist; resolves T2/T3 bugbot escalations autonomously (caps 20/5/10/10/20/5/5 across stages, each independent); halts only at the HITL merge boundary per RULE_git-safety.
---

# sprint-auto

Autonomous wrapper around the full sprint workflow (`/plan → /work → /bugbot-loop → /wrap → /bugbot-loop → integration phase → /compound`) for unattended overnight execution on a VPS. Takes a curated list of IDEAs that the human has pre-cleared as low-risk and runs each one through the per-IDEA loop, then runs all of them through a batch-level integration phase that resolves cross-PR conflicts on a disposable integration branch, validates the integrated state with union + full-suite tests + bugbot, and propagates the integration's resolutions back to each per-PR PR via forward-sync — so when the human reviews each PR in the morning, every PR merges cleanly to main with no conflict surprises.

The skill stops at the one HITL boundary that matters: merge to a protected branch.

This skill is **not** a substitute for human review — it is a throughput multiplier for ideas where the human has already decided "no harm trying". The human still reviews every PR before merging. The skill's job is to close the gap between "I have 10 low-risk IDEAs in the backlog" and "I have 10 PRs, each already drained through bugbot on both deliverables and docs, integration-validated against the others in the batch, with cross-project learnings promoted to mind-vault, waiting on my desk in the morning".

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

### 1. Preflight + integration bootstrap — gate the batch and bring up the only stack

Run once, before any per-IDEA work. If **any** check fails, abort with an actionable message; do not partially-run the batch.

1. **Primary-tree cleanliness.** `git status --porcelain` in the primary checkout must be empty. Dirty tree → abort.
2. **Branch.** Primary tree must be on `main` (or a non-protected branch the user explicitly authorised in the invocation). Never create auto worktrees off an unknown checkout state.
3. **Fetch.** `git fetch origin` so worktrees branch off the freshest `origin/main`.
4. **Docker daemon reachable.** `docker compose version` exits 0.
5. **Bootstrap script present.** Probe for `tools/sprint-auto-bootstrap.sh` in the project root (see [`references/worktree-lifecycle.md`](references/worktree-lifecycle.md)). If missing, warn and fall back to the generic recipe from `RULE_parallel-worktree-docker`; the user may prefer to add a script rather than run the generic path unattended.
6. **IDEA gate — every one.** For each arg, resolve the IDEA file (glob both `docs/ideas/` and `docs/archive/*/`) and verify the safety gates in [`references/safety-gates.md`](references/safety-gates.md). Any failure → abort the batch before starting, list the offenders. Belt-and-suspenders: `auto_safe: true` in frontmatter AND explicit arg presence, not either/or.
7. **Budget sanity.** If the caller passed `--budget-minutes=N` or `--budget-tokens=N`, record it. Per-IDEA default timeout: **300 minutes** wall clock. Per-batch default: `len(ideas) * 300` minutes plus an additional **180 minutes** for the integration phase (S11.5–S11.13).
8. **Integration bootstrap (S(-1)).** This is the **only** docker stack the batch will use:
   ```bash
   batch_iso=$(date -u +%Y-%m-%dT%H-%M-%SZ)
   git worktree add "../<project>-auto-integration-${batch_iso}" \
       -b "integration/sprint-auto-${batch_iso}" origin/main
   cd "../<project>-auto-integration-${batch_iso}"
   tools/sprint-auto-bootstrap.sh integration-runner 0 --port-offset 30000
   export SPRINT_AUTO_INTEGRATION_WORKTREE="$PWD"
   ```
   The `tools/sprint-auto-bootstrap.sh` invocation creates `.env` from the template (sentinel-replaced credentials), emits the docker-compose override at the explicit `--port-offset 30000` (the legacy idea-number-derived formula caps at `+19900`, so the explicit flag is required), brings up the stack, runs project-local `post_up_init` if defined. Failure here = abort the batch (no per-IDEA work proceeds; record `integration_outcome: bootstrap_failed`). See [`references/integration-stage.md`](references/integration-stage.md) for full mechanics.

### 2. Per-IDEA execution loop (S0–S11)

For each IDEA in the list, in argument order, sequentially. The full state machine is in [`references/post-pr-sequence.md`](references/post-pr-sequence.md). Each step heading below tags the state it covers.

**Canonical failure-path invariant** (applies throughout this loop): every failure path re-enters the happy path at **step 9 (harvest)**, then flows through **step 10 (log) → step 11 (next IDEA)**. **Step 8 (per-IDEA teardown) is a no-op in v3.1** — there is no per-IDEA stack to tear down.

1. **Worktree bootstrap — code-surface only (S0).** Per-IDEA worktrees in v3.1 are pure code surfaces. NO `.env`, NO `docker compose up`, NO post-up init.
   ```bash
   git worktree add "../<project>-auto-<slug>" -b "auto/<slug>" origin/main
   cd "../<project>-auto-<slug>"
   ```
   That's the entire bootstrap. The agent edits files here, commits, pushes; tests and verification run elsewhere (the integration worktree, via the env var). If the worktree-add itself fails, re-enter at step 9 with `outcome: bootstrap_failed`.

   Append a start entry to `docs/archive/<dir>/auto-run-YYYY-MM-DD.md` (see [`assets/auto-run-log-template.md`](assets/auto-run-log-template.md)).

2. **Plan the idea (S1).** Invoke the `plan` skill against the IDEA slug. Because step 6 of [`references/safety-gates.md`](references/safety-gates.md) guaranteed the IDEA body is thick, the thin-input bootstrap will skip and planning runs non-interactively. Architect-review pass runs; if `REJECTED`, re-enter at step 9 with `outcome: plan_rejected`. If `REQUIRES ABSTRACTION`, the plan author already incorporated findings — proceed.

3. **Reset DB on integration worktree (entry to S2).** Before invoking `/work`, sprint-auto resets the integration worktree's DB to a main-equivalent baseline. This is what makes per-PR PRs **independently deliverable**: each IDEA's tests run against a DB equivalent to what the morning reviewer's `main` will look like before they merge it.
   ```bash
   cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
   docker compose down -v
   docker compose up -d --wait
   # post_up_init from tools/sprint-auto-hooks.sh: migrate, seed, etc.
   ```
   Reset wall-clock: ~5 min depending on seed size.

4. **Work the plan (S2).** Invoke the `work` skill against the emitted plan. The work skill detects `SPRINT_AUTO_INTEGRATION_WORKTREE` is set and routes its verification step there — see [`references/integration-stage.md`](references/integration-stage.md) and [`../work/SKILL.md`](../work/SKILL.md). Per `RULE_git-safety`, the per-IDEA worktree is on `auto/<slug>` (not main), so commits flow freely. `/work` dispatches personas, commits per plan item, runs verification on the integration worktree (`git fetch origin auto/<slug>` + `git checkout --detach origin/auto/<slug>` there + `docker compose up -d --force-recreate web celery` + targeted tests; **`--detach` is required** because the per-IDEA worktree already has `auto/<slug>` checked out, and git refuses cross-worktree branch checkouts), and opens the PR on success. If verification fails or `/work` returns without opening a PR, re-enter at step 9 with `outcome: verification_failed`.

5. **Bugbot-loop the PR — deliverables pass (S3).** Invoke `/bugbot-loop <PR>` on the PR `/work` just opened. With `SPRINT_AUTO_INTEGRATION_WORKTREE` set, bugbot-loop's Phase 0 skips entirely — per-IDEA worktrees never get `.env` or docker. Fix-verification routes to the integration worktree as in step 4 (no DB reset within the bugbot session — fix commits don't typically migrate; reset cost would explode). Three outcomes (per [`references/escalation-policy.md`](references/escalation-policy.md)):
   - **Clean** → step 6.
   - **Hand-back with Tier 2/3 findings** → step 5a (escalation).
   - **Bugbot budget exhausted** → step 6 with `deliverables_bugbot_outcome: budget_exceeded`.

   **5a. Escalation resolution — deliverables pass (S4).** Tier 2 auto-approved (pre-authorized by `auto_safe` frontmatter + explicit-arg allowlist), Tier 3 attempted (not handed back). Maximum thinking effort per attempt. Each attempt is a **fresh commit**; if it needs a different angle, `git revert <previous-attempt-sha>` before trying again. Cap: **20 attempt cycles**. Verification routes to integration worktree per step 4. Return to step 5 after each attempt.

6. **/wrap (pre-merge, idea-only scope) — S5.** Invoke `/wrap --scope=idea-only <NNN>` — narrows wrap to the IDEA-local subset:
   - IDEA frontmatter flip (`status: in-progress` → `status: complete` + `completed: <today>`)
   - Downstream docs scan (per IDEA's own touched paths)

   **Skipped at this stage** (deferred to batch wrap on integration branch at S11.7):
   - DEVELOPMENT_LOG entry append
   - ideas-index move

   This eliminates the structural N-way line-conflict that every parallel `/wrap` produces today (every IDEA appending to the same lines of `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md` and `docs/ideas/README.md` → guaranteed conflicts at merge time). See [`../wrap/SKILL.md`](../wrap/SKILL.md) for the `--scope=idea-only` mode.

7. **Bugbot-loop the PR — docs pass (S6).** Invoke `/bugbot-loop <PR>` again, on the PR with the docs commit(s) on top. Same Phase-0-skip rule. Three outcomes as in step 5.
   - **Clean** → step 9 (skip step 8; no per-IDEA stack to tear down).
   - **Hand-back with Tier 2/3 findings** → step 7a (docs escalation).
   - **Bugbot budget exhausted** → step 9 with `docs_bugbot_outcome: budget_exceeded`.

   **7a. Escalation resolution — docs pass (S7).** Same contract as step 5a, **cap of 5 cycles**. Independent budget from S4. After cap, ship-non-clean for docs and proceed to step 9.

8. **Per-IDEA teardown — N/A in v3.1 (S8).** Was: `docker compose down` on per-IDEA stack. In v3.1, no per-IDEA stack exists. The integration worktree's stack stays up for the next IDEA's S2 reset. Step kept in the doc as a no-op marker for backward-compat with v1's state numbers; the auto-run log records `docker_teardown: skipped_v3_no_per_idea_stack`.

9. **Capture per-IDEA compound candidates (S9).** Harvest learnings from the IDEA's run — bugbot findings (from either pass) that exposed patterns, escalation attempts that revealed new recipes, infrastructure gaps discovered during bootstrap, downstream-docs drift patterns from step 6's sweep. Do **not** invoke `/compound` yet — queue candidates into a per-batch list for consolidation at step 12. On failure paths, harvest still runs but may queue fewer candidates — plan-rejection patterns and verification-failure patterns are themselves valuable compound signals.

10. **Finalise the per-IDEA auto-run log (S10).** Fields written (see [`assets/auto-run-log-template.md`](assets/auto-run-log-template.md)). Always written, including failure paths. Commit + push to `auto/<slug>`; the log rides into the PR.

11. **Move to next IDEA (S11).** The per-IDEA worktree stays on disk (still useful for code-surface inspection if needed). The integration worktree's stack stays up. The next IDEA's step 3 will reset DB and start fresh.

### 3. Integration phase (S11.5–S11.13) — batch validation

After all per-IDEA loops complete, the integration phase runs once. Full mechanics in [`references/integration-stage.md`](references/integration-stage.md); summary here:

1. **Final pre-merge DB reset (S11.5).** `cd $SPRINT_AUTO_INTEGRATION_WORKTREE && docker compose down -v && docker compose up -d --wait && migrate + seed`. Same baseline as per-IDEA resets but for the integration test run.

2. **Sequential merge (S11.6).** `git checkout integration/sprint-auto-<batch-iso>`. For each `auto/<slug>` in batch-arg order: `git merge --no-ff auto/<slug>`. On conflict: resolve on integration branch using [`references/integration-conflict-resolutions.md`](references/integration-conflict-resolutions.md), commit the resolution. Continue. Track which branches needed resolution.

3. **Batch wrap on integration branch (S11.7).** Compose ONE devlog commit + ONE ideas-index commit covering all N IDEAs. This is the work that per-IDEA `/wrap --scope=idea-only` (step 6) deferred. Eliminates the N-way wrap-stage conflicts at the source.

4. **Integration tests — union (S11.8).** Read each merged-in IDEA's plan-doc Verification section, union test paths, run pytest on the integration stack. Migrate up if migrations were merged. Failure → fix on integration branch, cap **10 attempts**.

5. **Full test suite (S11.9).** Sprint-end gate. Full pytest on the integrated state. Same fix discipline, cap **10 attempts**.

6. **Bugbot-loop on integration branch via `[INTEGRATION]` draft PR (S11.10).** Cursor Bugbot is PR-anchored, so:
   ```bash
   gh pr create --base main --head integration/sprint-auto-<batch-iso> \
       --draft --title "[INTEGRATION] sprint-auto-<batch-iso>" \
       --body "Auto-generated integration validation. NOT FOR MERGE. Auto-closed at sprint-auto teardown."
   ```
   Then `/bugbot-loop` against the draft PR's number. **Cap 20 attempts** — integration branches are elephants (N-times-larger review surface than any per-PR PR; T2/T3 findings have proportionally longer tails). Symmetric with the S4 deliverables-pass cap because integration is deliverables-class review of the integrated state, not docs-class.

7. **Forward-sync (S11.11).** For each `auto/<slug>`: **run inside the per-IDEA worktree** (where `auto/<slug>` is the active checkout — avoids the cross-worktree branch-collision that would happen if attempted in the integration worktree). The integration worktree must `git push origin integration/sprint-auto-<batch-iso>` first so per-IDEA worktrees can fetch. Then per per-IDEA worktree: `cd $HOME/projects/<project>-auto-<slug> && git fetch origin && git merge --no-ff origin/integration/sprint-auto-<batch-iso> && git push origin auto/<slug>`. Forward-sync is RULE_git-safety-compliant (feature branch tip moves; no force-push; no review threads invalidated). Each per-PR PR auto-updates; bugbot fires automatically against the new head.

8. **Per-PR PR re-bugbot + verification (S11.12).** For each per-PR PR: `cd $SPRINT_AUTO_INTEGRATION_WORKTREE && git fetch origin auto/<slug> && git checkout --detach origin/auto/<slug>` (now post-forward-sync state; `--detach` because the per-IDEA worktree still has the branch ref claimed), reset DB, run targeted tests, invoke `/bugbot-loop`. Cap **5 attempts** each. Most clean-signal immediately because the new commits are wrap + resolutions, not deliverables work.

9. **Integration teardown (S11.13).** `docker compose down` (NOT `down -v`; volumes preserved for inspection). Worktree filesystem stays. Close `[INTEGRATION]` draft PR with comment `auto-closed by sprint-auto teardown; integration validation complete.` and `gh pr close <N>`. The integration branch lingers locally; cleaned up by the human's `/wrap NNN` post-merge teardown for the **last-of-batch** IDEA (extend `/wrap` to detect last-of-batch and `git branch -d integration/sprint-auto-<batch-iso>`).

**Failure mode summary** (full table in [`references/integration-stage.md`](references/integration-stage.md)):
- S(-1) bootstrap fails → abort batch; no per-IDEA work proceeds
- S11.6 merge resolution fails → log + continue to next branch in sequence
- S11.8/S11.9 tests cap-exceeded → ship integration-non-clean (flagged in summary)
- S11.10 bugbot cap-exceeded → ship integration-non-clean (flagged)
- S11.11 forward-sync per-branch fail → log + skip that branch's S11.12
- S11.12 cap-exceeded per branch → log + continue (each PR independent)

### 4. Batch-level compound + mind-vault bugbot-loop (S12–S15)

When the integration phase completes (clean or with flags):

1. **Consolidate compound candidates (S12 prep)** harvested from every per-IDEA step 9. Cross-IDEA patterns get de-duplicated here: if three IDEAs independently surfaced the same bugbot finding category, it's a stronger compound candidate than any single instance.

2. **Invoke `/compound` per candidate — autonomous mode (S12).** The compound skill's Shape-C narrative probe normally asks up to three questions before routing; under sprint-auto those answers come from the compound candidate's own metadata. The user's invocation of `/sprint-auto` is the *transitive* confirmation that compound's "Never silently promote to mind-vault" interaction rule requires.

3. **Each mind-vault PR → its own `/bugbot-loop` session (S13 + S14).** Once `/compound` produces a PR on `compound/YYYY-MM-DD-<slug>` in the mind-vault repo, invoke `/bugbot-loop <mind-vault-PR>` with the same escalation policy as steps 5a/7a. Cap **5 attempt cycles** (single-pass — mind-vault compound PRs are documentation by nature).

4. **Write `docs/archive/auto-run-<ISO-timestamp>-summary.md` (S15 artefact)** in the primary tree. See [`assets/auto-run-log-template.md`](assets/auto-run-log-template.md). Includes a new **Integration check** section listing the integration phase's outcomes (merge results, test results, bugbot results, forward-sync results, re-bugbot results) and a **Compound section** listing each mind-vault PR and its bugbot outcome.

5. **Print the summary block to stdout (S15):**

   ```text
   sprint-auto batch complete — 2026-04-20T23:47:12Z

   IDEAs (project PRs):
   ✅ IDEA-050 sync-retry-backoff     → https://github.com/.../pull/123  (bugbot: deliverables clean / docs clean / re-bugbot clean)
   ✅ IDEA-051 modal-dismiss-focus    → https://github.com/.../pull/124  (bugbot: deliverables 2 T3 unresolved / docs clean / re-bugbot clean)
   ⚠️  IDEA-052 alpine-event-bus      → plan REJECTED (architect); see worktree
   ❌ IDEA-053 cache-invalidation     → verification failed (test_cache.py); see worktree

   Integration check:
   ✅ Sequential merge: 2 clean, 0 conflicts
   ✅ Union tests: 414 passed
   ✅ Full suite: 1247 passed
   ⚠️  Integration bugbot: 1 T3 unresolved at cap; see [INTEGRATION] PR
   ✅ Forward-sync: 2 branches updated
   ✅ Re-bugbot per-PR: clean on both

   Compound (mind-vault PRs):
   ✅ RULE_htmx-partial-boundary-check  → https://github.com/.../pull/78   (bugbot: clean)
   ⚠️  skill:curator pass-3 addendum     → https://github.com/.../pull/79   (bugbot: 1 T3 unresolved)

   Docker stacks: 1 stopped (integration; volumes retained). Per-IDEA worktrees preserved (code-surface only).
   Integration branch: integration/sprint-auto-2026-04-20T23-47-12Z (cleaned up by /wrap on last-of-batch merge).
   Batch summary: docs/archive/auto-run-2026-04-20T23-47-12Z-summary.md
   ```

6. **Worktree preservation discipline.** Containers on the integration stack are stopped at S11.13. Per-IDEA worktree filesystems stay (code-surface only; never had stacks). The integration worktree filesystem stays. Full teardown of the integration worktree is the human's chore via `/wrap NNN` post-merge for the last-of-batch IDEA.

### 5. Post-merge reminders (still human)

The batch summary's closing section lists `/wrap NNN` for each merged IDEA — but note its scope has narrowed. Everything except the destructive teardown already ran during the batch (frontmatter flip + downstream docs scan at S5; devlog + index batch-wrap at S11.7 — all on the relevant branches, landing with the merge). The post-merge `/wrap NNN` invocation now runs **only Step 5 of `/wrap`**: `docker compose down -v` (a no-op for per-IDEA worktrees since no stack), `git worktree remove ../<slug>`, `git branch -d auto/<slug>`. Plus, for the last-of-batch IDEA, the additional integration-worktree cleanup:

```markdown
## Next steps (post-merge)

For each IDEA whose PR you merge, run `/wrap NNN` from the primary tree —
it auto-detects post-merge mode and runs only the destructive teardown:
- `git worktree remove ../<project>-auto-<slug>` (per-IDEA worktree cleanup)
- `git branch -d auto/<slug>` (per-IDEA branch cleanup)
- For the LAST-OF-BATCH IDEA additionally:
  - `cd $integration_worktree && docker compose down -v` (drops volumes)
  - `git worktree remove $integration_worktree`
  - `git branch -d integration/sprint-auto-<batch-iso>`

The frontmatter flip + downstream docs scan already landed at S5; the
devlog batch entry + ideas-index batch update already landed at S11.7
on the integration branch and propagated to each per-PR via S11.11
forward-sync.
```

No `/compound` reminder here — compound ran in section 4 above.

## Interaction rules

- **Belt-and-suspenders opt-in.** Frontmatter `auto_safe: true` AND explicit arg allowlist. Never scan-mode in v1; curation is the whole point.
- **No merges, ever.** The skill stops at PR creation (project PRs, the `[INTEGRATION]` draft PR, and mind-vault compound PRs). `gh pr merge`, `git push` to protected branches, anything that crosses the HITL gate — forbidden. The `[INTEGRATION]` draft PR specifically is **closed without merging** at S11.13.
- **Single docker stack contract.** v3.1 brings up exactly ONE docker stack per batch — the integration worktree's, at port offset `+30000`. Per-IDEA worktrees are pure code surfaces (no `.env`, no `docker compose up`). The verification routing via `SPRINT_AUTO_INTEGRATION_WORKTREE` env var is what makes this work; if any per-IDEA worktree somehow ends up with a `.env` or running stack, treat it as a defect.
- **Verification-routing env var.** Sprint-auto exports `SPRINT_AUTO_INTEGRATION_WORKTREE=<path>` at S(-1). `/work`, `/bugbot-loop`, and any test-runner shelled out from the per-IDEA loop must honor this var and route their docker/test commands to that path. See [`references/integration-stage.md`](references/integration-stage.md) for the contract.
- **DB reset cadence: per-IDEA, NOT per-bugbot-commit.** A single reset at the entry to each IDEA's S2 (~5 min) gives main-equivalent baseline. Resets within a bugbot session would multiply wall-clock 10× without quality gain — fix commits don't typically migrate.
- **Rollback-able commits only for escalation resolution.** During step-5a, step-7a, S11.8/S11.9 fix attempts, S11.10 bugbot escalation, and S11.12 re-bugbot, the skill MAY commit multiple attempts, each revertable via `git revert`. It MAY NOT force-push, rewrite history, or amend commits produced by `/work` or by `/wrap`'s docs sweep — those are part of the PR's review history. If a fix attempt goes wrong, the correct move is `git revert <bad-sha>` + a fresh attempt commit.
- **Two-pass bugbot-loop per IDEA + integration bugbot + per-PR re-bugbot.** Every successful-through-PR IDEA run receives **two** per-PR bugbot-loop invocations (deliverables S3, docs S6) plus a **third** post-forward-sync re-bugbot (S11.12). Plus the batch gets one integration-state bugbot (S11.10). Each has its own independent escalation budget — 20 deliverables / 5 docs / 5 re-bugbot per IDEA, plus 20 integration. Skipping any of these passes is never correct on the happy path.
- **Bugbot-loop invocations are MANDATORY; ship-non-clean is a fallback, not an upfront opt-out.** The skill's S3, S6, S11.10, and S11.12 contracts are "invoke `/bugbot-loop`, work the escalation cycle, ship-non-clean only after the per-pass cap is reached." They are NOT "decide upfront not to invoke and call it ship-non-clean." The auto-run log must record the attempt outcome for each pass, NOT `deferred to morning review` — the latter is a tell that no attempt was made.
- **Sequential in v1.** Parallel IDEA execution invites host contention, and v3.1's single-stack architecture inherently serialises through the integration worktree's DB. Add concurrency later only if v3.1 calibration shows headroom.
- **Respect the architect.** If the plan-time architect review comes back `REJECTED`, that IDEA is done for this batch. Trust the review.
- **Non-clean bugbot is OK to ship-for-review — *after* the attempt was made.** After the per-pass cap is hit OR `/bugbot-loop` returned an exhaust-budget signal, an IDEA with unresolved Tier 2/3 findings still produces a valid PR. The morning reviewer decides. Do not block the pipeline on perfection; transparency in the auto-run log (attempt SHAs, approaches, outcomes) is the contract.
- **Compound transitive confirmation.** `/compound`'s "Never silently promote to mind-vault" rule is satisfied by sprint-auto's own invocation: the user launched sprint-auto knowing compound runs at end-of-batch, and every mind-vault PR produced lands in the summary for review.
- **Abort-the-batch triggers**: docker daemon lost, disk full, the bootstrap script exits with a class of error flagged unrecoverable, token/minute budget blown at batch scope, mind-vault repo becomes unreachable during section 4. **NEW in v3.1**: integration worktree bootstrap (S(-1)) failure is a hard abort — without the integration stack, no verification can run.
- **Priority is queue order, not a safety gate.** `priority: high` / `medium` / `low` affects the order in which the human schedules ideas — it does not imply "how dangerous to automate". `auto_safe: true` is the authoritative safety signal.
- **`[INTEGRATION]` draft PR is auto-closed, never merged.** S11.10 opens it; S11.13 closes it (without merge) with an audit-trail comment. The closed PR's URL goes into the auto-run summary so the morning reviewer can read bugbot's integration-state findings without recreating state. Treat any code path that would `gh pr merge` the integration draft PR as a defect.
- **Forward-sync gives the reviewer atomic-batch merging — name the time-save in the summary, document the escape hatch for the rare deferral case.** After S11.11, every per-PR PR carries the entire batch's content. On the happy path (merge the whole batch) this is a *time-saver*: one merge ships N IDEAs; the other PRs auto-collapse to zero diff and close with a one-liner. The auto-run summary should celebrate this, not warn about it. The friction case is escalation — the reviewer wants to defer one IDEA from the batch — and that's where the summary needs to enumerate the three escape hatches (close-and-rerun / surgical revert / accept atomic). **The summary template's "Atomic-batch merging" section names the time-save AND the escape hatches** (see `assets/auto-run-log-template.md`); `references/integration-stage.md` § Forward-sync carries the full trade-off discussion. No hard rules — the architecture is correct as-is; we're optimising the morning-reviewer surface. *(Compounded 2026-04-29 from teisutis batch where the reviewer merged PR #397, asked "PR #398's diff looked weird" — exactly because it collapsed to zero — and then noted "atomic-batch is actually saving me time, only escalation is the issue." Reframed to match.)*

## When NOT to use these patterns

- **Single IDEA with supervision available.** Use `/plan` + `/work` directly — less ceremony.
- **Any IDEA without `auto_safe: true`.** Tag it first via `/idea <slug>` update, with an explicit `auto_safe_reason` in frontmatter explaining why the human cleared it.
- **IDEAs touching sensitive paths.** See [`references/safety-gates.md`](references/safety-gates.md) for the default-deny list. Override only via explicit `sensitive_paths_cleared: true` in the IDEA frontmatter.
- **First run on a new project under v3.1 mechanics.** First run signals are listed in `IDEA_integration_branch.md` § First-batch monitoring. Run any sprint-auto batch as if it's a real batch — there are no low-stakes nights — but pay extra attention to the listed signals.

## References

- [references/safety-gates.md](references/safety-gates.md) — opt-in criteria, automatic disqualifiers, halt conditions
- [references/worktree-lifecycle.md](references/worktree-lifecycle.md) — per-IDEA code-surface mode + integration-worktree-as-runtime model
- [references/post-pr-sequence.md](references/post-pr-sequence.md) — the S(-1) → S0–S15 state machine including the integration phase
- [references/integration-stage.md](references/integration-stage.md) — **NEW** integration phase mechanics: env var, sequential merge, batch wrap, [INTEGRATION] draft PR, forward-sync, teardown
- [references/integration-conflict-resolutions.md](references/integration-conflict-resolutions.md) — **NEW** algorithm catalogue for S11.6 conflict resolution (devlog, index, .po, HTML, JS, Python, settings, tests)
- [references/escalation-policy.md](references/escalation-policy.md) — T2/T3 resolution rules + per-pass attempt caps (20 deliverables / 5 docs / 10 union / 10 full / 20 integration / 5 re-bugbot / 5 mind-vault compound)
- [assets/auto-run-log-template.md](assets/auto-run-log-template.md) — per-IDEA + batch-summary log shape (now includes Integration check section)
- [rules/RULE_parallel-worktree-docker.md](../../rules/RULE_parallel-worktree-docker.md) — underlying worktree + docker isolation contract
- [rules/RULE_git-safety.md](../../rules/RULE_git-safety.md) — the HITL boundary the skill must never cross
- [rules/RULE_ideas-location-status.md](../../rules/RULE_ideas-location-status.md) — how IDEA files migrate; `/plan` does the move inside the worktree
- [commands/bugbot-loop.md](../../commands/bugbot-loop.md) — invoked four times per IDEA happy path (deliverables, docs, re-bugbot) + once on integration ([INTEGRATION] draft PR) + once per mind-vault compound PR; honors `SPRINT_AUTO_INTEGRATION_WORKTREE`
- [skills/plan/SKILL.md](../plan/SKILL.md) — invoked per IDEA (step 2)
- [skills/work/SKILL.md](../work/SKILL.md) — invoked per plan (step 4); honors `SPRINT_AUTO_INTEGRATION_WORKTREE` for verification routing
- [skills/wrap/SKILL.md](../wrap/SKILL.md) — invoked per IDEA at step 6 (`--scope=idea-only` mode); destructive teardown is post-merge human chore (extended for last-of-batch integration cleanup)
- [skills/compound/SKILL.md](../compound/SKILL.md) — invoked at batch end (section 4) for cross-project learnings; each mind-vault PR is itself bugbot-looped
- [docs/SPRINT_WORKFLOW.md](../../docs/SPRINT_WORKFLOW.md) — the sprint workflow this skill wraps

---

**Last Updated**: 2026-04-29 (interaction rule + 3-place doc update reframed: forward-sync makes per-PR PRs atomic-batch-mergeable — that's a TIME-SAVER on the happy path (one merge ships N IDEAs; others auto-collapse to zero and close with a one-liner). The friction is only when the reviewer wants to defer ONE IDEA from the batch — escalation case — for which we enumerate three escape hatches (close-and-rerun / surgical revert / accept atomic). Auto-run template's "Atomic-batch merging" section celebrates the time-save AND lists the escape hatches. Compounded from teisutis 2026-04-29 batch where the reviewer merged PR #397, asked "PR #398's diff looked weird" (because it had collapsed to zero — a feature, not a bug), and then articulated "atomic-batch is actually saving me time, only escalation is the issue." Reframed to match.)

**Previous**: 2026-04-27 v3.1 (test-triage worktree architecture — single docker stack on integration worktree at port offset `+30000`; per-IDEA worktrees are code surfaces routed via `SPRINT_AUTO_INTEGRATION_WORKTREE` env var; full DB reset between IDEAs guarantees independently deliverable PRs; new integration phase S(-1) + S11.5–S11.13 with sequential merge, batch wrap on integration branch, union + full suite tests, bugbot via `[INTEGRATION]` draft PR, forward-sync propagation, per-PR re-bugbot; per-IDEA `/wrap` narrowed to `--scope=idea-only` to defer devlog + index writes to S11.7 batch wrap; eliminates the wrap-stage line-conflict that every parallel sprint-auto batch produced silently. See PR #76 for the design doc and the resolved decision history.)

**Previous**: 2026-04-26 (tightened the bugbot-loop rule pair: shipping non-clean is a fallback after attempt, not an upfront opt-out; auto-run log signal `deferred to morning review` is a tell that no attempt was made).

**Previous**: 2026-04-22 (structural reconciliation: S0–S15 state numbering shared with `references/post-pr-sequence.md`; two-pass bugbot-loop inserted; canonical failure-path invariant; escalation caps 20/5/5).
