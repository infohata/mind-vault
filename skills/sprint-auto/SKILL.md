---
name: sprint-auto
description: Unattended overnight orchestrator — runs a curated list of opt-in IDEAs through /plan → /work → /wrap (idea-only) → review-loop (single pass over the wrapped PR) → integration phase (sequential merge + batch wrap + tests + integration review) → /compound (mind-vault, review-looped). Review-engine selector (`SPRINT_AUTO_REVIEW_ENGINE`) dispatches a single `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE` call carrying one or all configured engines (Cursor Bugbot, GitHub Copilot, Claude Code Review, future N) — concurrent multi-engine sync when >1; default `none` skips external review and relies on AGENT_curator. Per-IDEA PRs target the integration branch (v3.2 — integration-as-merge-gate); the [INTEGRATION] PR is the SINGLE PR that targets the parent (main / sprint-*) and is what the human reviews + merges. Eliminates forward-sync and per-PR re-review — per-IDEA PRs stay IDEA-isolated, integration PR carries the integrated state + compatibility patches as visible commits. Single integration-worktree docker stack at port offset +30000 is the only stack of the batch; per-IDEA worktrees are pure code surfaces with verification routed via SPRINT_AUTO_INTEGRATION_WORKTREE env var. Full DB reset between IDEAs guarantees per-IDEA PRs are independently deliverable when reviewed in isolation. Two opt-in modes: auto_safe: true (autonomous through merge gate) and auto_safe_with_eval_gate: true (autonomous through merge gate + emit a manual-evaluation checklist for the human to walk before merging — for IDEAs whose visual / a11y / interaction residue cannot be covered by render-and-assert tests). Enforces frontmatter opt-in + explicit arg allowlist; resolves T2/T3 review-loop escalations autonomously (caps 20/10/10/20/5 across stages — single per-IDEA review / union / full / integration / compound, each an independent `/review-loop` session whose budget spans all configured engines); halts only at the HITL merge boundary per RULE_git-safety.
---

# sprint-auto

Autonomous wrapper around the full sprint workflow (`/plan → /work → /wrap → review-loop → integration phase → /compound`, where the `review-loop` pass is one `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE` call carrying the configured engine(s) over the wrapped PR — single-review cadence, IDEA-015 — or is skipped when engine is `none`) for unattended overnight execution on a VPS. Takes a curated list of IDEAs that the human has pre-cleared as low-risk and runs each one through the per-IDEA loop, then runs all of them through a batch-level integration phase: a long-lived integration branch is the **base ref** for every per-IDEA PR. Per-IDEA PRs target integration; the integration phase merges them sequentially, lands compatibility / conflict-resolution patches as visible commits, validates the integrated state with union + full-suite tests + the configured review loop, and opens a single non-draft `[INTEGRATION]` PR that targets the parent (main / sprint-\*). When the human merges that one PR, every per-IDEA PR auto-closes as a merged ancestor.

The skill stops at the one HITL boundary that matters: merge to a protected branch.

This skill is **not** a substitute for human review — it is a throughput multiplier for ideas where the human has already decided "no harm trying". The human still reviews. The skill's job is to close the gap between "I have 10 low-risk IDEAs in the backlog" and "I have 10 IDEA-isolated per-PR PRs (each drained through the configured review engine in one post-wrap review pass) plus one integration PR (drained through the same engine on the integrated state) waiting on my desk, with cross-project learnings already promoted to mind-vault as their own review-looped PRs".

**v3.2 (current) vs v3.1**: v3.1 had per-IDEA PRs target the parent (main / sprint-\*), then forward-synced the integration's content back into each per-IDEA PR after S11.10. The result was N PRs all carrying the entire batch's diff — atomic-batch-merging at the cost of "N identical PRs" UX confusion. v3.2 inverts the routing: integration is the base ref, per-IDEA PRs stay IDEA-isolated for review, integration PR is the single merge gate. Forward-sync (S11.11) and per-PR re-review (S11.12) are deleted — they only existed to compensate for the v3.1 routing.

## When to use

**TRIGGER when:**

- user says "run these IDEAs overnight", "sprint-auto IDEA-NNN ...", "set claude on autopilot for these", "full auto on these ideas"
- user is setting up a VPS / screen session / background run and wants multiple IDEAs executed unattended
- a curated list of IDEAs is ready: each marked `auto_safe: true` OR `auto_safe_with_eval_gate: true` in frontmatter (see [`references/safety-gates.md`](references/safety-gates.md) § Mode A / Mode B for the distinction), each with a thick enough body to survive `/plan` without thin-input bootstrap

**SKIP when:**

- any IDEA in the list lacks both `auto_safe: true` and `auto_safe_with_eval_gate: true` → refuse the batch, surface the offender, ask the human to tag or drop it
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

6. **IDEA gate — every one.** For each arg, resolve the IDEA file (glob both `docs/ideas/` and `docs/archive/*/`) and verify the safety gates in [`references/safety-gates.md`](references/safety-gates.md). Any failure → abort the batch before starting, list the offenders. Belt-and-suspenders: (`auto_safe: true` OR `auto_safe_with_eval_gate: true`) in frontmatter AND explicit arg presence, not either/or. Both opt-in modes route through the same per-IDEA loop; the only divergence is at S5 (`/wrap --scope=idea-only` Step 7 emits a manual-evaluation checklist when `auto_safe_with_eval_gate: true`) and at S11.10 (the integration PR's body aggregates each emitted checklist's URL — see [`references/integration-stage.md`](references/integration-stage.md) § Per-IDEA evaluation checklists).

7. **Budget sanity.** If the caller passed `--budget-minutes=N` or `--budget-tokens=N`, record it. Per-IDEA default timeout: **300 minutes** wall clock. Per-batch default: `len(ideas) * 300` minutes plus an additional **180 minutes** for the integration phase (S11.5–S11.13).
   7.5. **Review-engine resolution.** Read the project's review-engine declaration and export it as `SPRINT_AUTO_REVIEW_ENGINE`. Resolution order:

   1. Explicit `--review-engine=<value>` arg passed to sprint-auto.
   2. `review_engine:` key in `.mind-vault.yml` at the repo root.
   3. `review_engine:` key in the project's `CLAUDE.md` frontmatter (if present).
   4. Fallback: `none` (curator-only).
      Accepted values: `none`, or any **non-empty CSV subset** of `{bugbot, copilot, claude}` — e.g. `bugbot`, `claude`, `bugbot,copilot`, `bugbot,copilot,claude` (or list form `[bugbot, copilot]` / `[bugbot, copilot, claude]` in YAML — coerce to CSV at export time). Validate by splitting the CSV and checking every token is in `{bugbot, copilot, claude}` (equivalently: each token has a matching `tools/<engine>_*.sh` pair); **reject unknown names** (`=bogus`, `=bugbot,foo`) with an actionable error naming the offending token, and reject the empty string. `none` is the only non-engine accepted value. Export `SPRINT_AUTO_REVIEW_ENGINE=<resolved-csv-or-none>` so downstream stages can dispatch. Log the resolution explicitly: `review_engine: <value> (source: <arg|.mind-vault.yml|CLAUDE.md|default>)`. (`claude` self-excludes at the `/review-loop` layer on repos without the action installed — see [`../review-loop/references/engine-claude.md`](../review-loop/references/engine-claude.md); sprint-auto passes it through, the loop handles reachability.)

8. **Integration bootstrap (S(-1)).** This is the **only** docker stack the batch will use **and** the integration branch is published immediately so per-IDEA PRs in S2 can target it:

   ```bash
   batch_iso=$(date -u +%Y-%m-%dT%H-%M-%SZ)
   git worktree add "../<project>-auto-integration-${batch_iso}" \
       -b "integration/sprint-auto-${batch_iso}" origin/main
   cd "../<project>-auto-integration-${batch_iso}"
   git push -u origin "integration/sprint-auto-${batch_iso}"   # v3.2: publish before S2
   tools/sprint-auto-bootstrap.sh integration-runner 0 --port-offset 30000
   export SPRINT_AUTO_INTEGRATION_WORKTREE="$PWD"
   export SPRINT_AUTO_INTEGRATION_BRANCH="integration/sprint-auto-${batch_iso}"
   ```

   The `tools/sprint-auto-bootstrap.sh` invocation creates `.env` from the template (sentinel-replaced credentials), emits the docker-compose override at the explicit `--port-offset 30000` (the legacy idea-number-derived formula caps at `+19900`, so the explicit flag is required), brings up the stack, runs project-local `post_up_init` if defined. Failure of the worktree+push or the bootstrap = abort the batch (no per-IDEA work proceeds; record `integration_outcome: bootstrap_failed`). See [`references/integration-stage.md`](references/integration-stage.md) for full mechanics.

   **Why push at S(-1)** (v3.2 change from v3.1, where push happened at S11.10): per-IDEA `/work` invocations in S2 open PRs with `--base $SPRINT_AUTO_INTEGRATION_BRANCH`. GitHub requires the base ref to exist on `origin` at PR-creation time, so the integration branch must be pushed first. The push is just the branch ref — no PR is opened until S11.10.

9. **Playwright availability probe (non-fatal).** After the integration stack is up, probe whether Playwright is installed in the `web` service. The probe outcome flips the IDEA-level `requires_playwright` gate; it is **never** a batch-level abort.

   ```bash
   if docker compose exec -T web playwright --version >/dev/null 2>&1; then
       export SPRINT_AUTO_PLAYWRIGHT_AVAILABLE=1
   else
       export SPRINT_AUTO_PLAYWRIGHT_AVAILABLE=0
       echo "[preflight] Playwright not installed in integration stack." \
            "IDEAs with 'requires_playwright: true' will gate to manual-eval-only mode" \
            "(plan author writes manual-eval-checklist rows; Playwright tests are deferred)." \
            "Run tools/setup_playwright.sh and rebuild the image to enable." | tee -a "$BATCH_LOG"
   fi
   ```

   Persist `SPRINT_AUTO_PLAYWRIGHT_AVAILABLE` to the batch state file so per-IDEA `/plan` and `/work` invocations read the same value across worktree boundaries (env vars don't survive subshells). The IDEA-level gate (`requires_playwright` frontmatter flag) is described in [`references/safety-gates.md`](references/safety-gates.md) § Playwright-availability gate. Three branches:

   - **Probe = present, IDEA has `requires_playwright: true`** → plan author writes Playwright tests; eval-checklist pre-fills covered rows from the plan's `playwright_test_coverage` block.
   - **Probe = absent, IDEA has `requires_playwright: true`** → plan author writes ONLY the manual-eval-checklist rows for Playwright-relevant scenarios; the frontmatter flag stays as a backref so a later "set up Playwright" IDEA can backfill tests.
   - **IDEA has no `requires_playwright`** → IDEA proceeds independent of probe outcome.

   Bootstrap circularity is solved by manual-eval fallback: the first project-side "set up Playwright" IDEA's `requires_playwright` is `false` (it provisions the gate's "present" state but doesn't depend on it); after it merges, downstream IDEAs' probes flip to "present" and the gate begins authoring tests. No IDEA is ever blocked on infra readiness.

### 2. Per-IDEA execution loop (S0–S11)

For each IDEA in the list, in argument order, sequentially. The full state machine is in [`references/post-pr-sequence.md`](references/post-pr-sequence.md). Each step heading below tags the state it covers.

**Canonical failure-path invariant** (applies throughout this loop): every failure path re-enters the happy path at **step 9 (harvest)**, then flows through **step 10 (log) → step 11 (next IDEA)**. **Step 8 (per-IDEA teardown) is a no-op in v3.1** — there is no per-IDEA stack to tear down.

01. **Worktree bootstrap — code-surface only (S0).** Per-IDEA worktrees in v3.1 are pure code surfaces. NO `.env`, NO `docker compose up`, NO post-up init.

    ```bash
    git worktree add "../<project>-auto-<slug>" -b "auto/<slug>" origin/main
    cd "../<project>-auto-<slug>"
    ```

    That's the entire bootstrap. The agent edits files here, commits, pushes; tests and verification run elsewhere (the integration worktree, via the env var). If the worktree-add itself fails, re-enter at step 9 with `outcome: bootstrap_failed`.

    Append a start entry to `docs/archive/<dir>/auto-run-YYYY-MM-DD.md` (see [`assets/auto-run-log-template.md`](assets/auto-run-log-template.md)).

02. **Plan the idea (S1).** Invoke the `plan` skill against the IDEA slug. Because step 6 of [`references/safety-gates.md`](references/safety-gates.md) guaranteed the IDEA body is thick, the thin-input bootstrap will skip and planning runs non-interactively. Architect-review pass runs; if `REJECTED`, re-enter at step 9 with `outcome: plan_rejected`. If `REQUIRES ABSTRACTION`, the plan author already incorporated findings — proceed.

03. **Reset DB on integration worktree (entry to S2).** Before invoking `/work`, sprint-auto resets the integration worktree's DB to a main-equivalent baseline. This is what makes per-PR PRs **independently deliverable**: each IDEA's tests run against a DB equivalent to what the morning reviewer's `main` will look like before they merge it.

    ```bash
    cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
    docker compose down -v
    docker compose up -d --wait
    # post_up_init from tools/sprint-auto-hooks.sh: migrate, seed, etc.
    ```

    Reset wall-clock: ~5 min depending on seed size.

04. **Work the plan (S2).** Invoke the `work` skill against the emitted plan. The work skill detects `SPRINT_AUTO_INTEGRATION_WORKTREE` is set and routes its verification step there — see [`references/integration-stage.md`](references/integration-stage.md) and [`../work/SKILL.md`](../work/SKILL.md). Per `RULE_git-safety`, the per-IDEA worktree is on `auto/<slug>` (not main), so commits flow freely. `/work` dispatches personas, commits per plan item, runs verification on the integration worktree (`git fetch origin auto/<slug>` + `git checkout --detach origin/auto/<slug>` there + `docker compose up -d --force-recreate web celery` + targeted tests; **`--detach` is required** because the per-IDEA worktree already has `auto/<slug>` checked out, and git refuses cross-worktree branch checkouts), and opens the PR on success.

    **v3.2 PR base routing**: when `SPRINT_AUTO_INTEGRATION_BRANCH` is set, `/work` passes `--base "$SPRINT_AUTO_INTEGRATION_BRANCH"` to `gh pr create` instead of the parent (`main` / `sprint-*`). The PR's diff is naturally IDEA-isolated against integration (which starts as a copy of `origin/main` at S(-1) and only accumulates merge commits as later IDEAs land). Each per-IDEA PR remains independently reviewable for the morning reviewer. If verification fails or `/work` returns without opening a PR, re-enter at step 9 with `outcome: verification_failed`.

    **Per-IDEA PRs ride DRAFT until the review pass (claude-cost lever).** `/work` opens each per-IDEA PR as draft; sprint-auto pushes many commits per IDEA across many IDEAs unattended, and the Claude engine is push-triggered — a non-draft PR would auto-run + bill a claude review on *every* commit overnight. Draft suppresses that. S6's single `/review-loop` pre-flight un-drafts the PR (`gh pr ready`) so claude reviews the finalized per-IDEA state once, then re-drafts is unnecessary (the PR auto-closes when the \[INTEGRATION\] PR merges). Net: one claude review per IDEA's review pass instead of one per WIP commit. (The single `[INTEGRATION]` PR is opened **non-draft** at S11.10 — it's the human merge gate and wants its review.) When `SPRINT_AUTO_REVIEW_ENGINE` excludes claude, the draft state is harmless (bugbot/copilot are on-demand regardless).

    **Playwright defence-in-depth at S2**: if the IDEA's plan contains a `playwright_test_coverage` block (i.e. the plan author wrote Playwright tests), `/work`'s verification step re-probes `docker compose exec -T web playwright --version` against the integration stack. If the probe now fails (infra was uninstalled between S(-1) and now, or the image was rebuilt without Playwright), S2 logs `playwright_unavailable: true` to the auto-run log, skips the Playwright tests for that IDEA only, and continues with non-Playwright tests. The IDEA still ships; the manual-eval rows the plan would have pre-filled stay un-pre-filled. The integration PR's body surfaces this in S11.10's per-IDEA evaluation summary.

05. **/wrap (pre-merge, idea-only scope) — S5.** Invoke `/wrap --scope=idea-only <NNN>` **before** the review (wrap-before-review: the single review then sees the PR at docs-finalized state) — narrows wrap to the IDEA-local subset:

    - IDEA frontmatter flip (`status: in-progress` → `status: complete` + `completed: <today>`)
    - Downstream docs scan (per IDEA's own touched paths)

    **Skipped at this stage** (deferred to batch wrap on integration branch at S11.7):

    - DEVELOPMENT_LOG entry append
    - ideas-index move

    This eliminates the structural N-way line-conflict that every parallel `/wrap` produces today (every IDEA appending to the same lines of `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md` and `docs/ideas/README.md` → guaranteed conflicts at merge time). See [`../wrap/SKILL.md`](../wrap/SKILL.md) for the `--scope=idea-only` mode.

06. **Review-loop the wrapped PR — single pass (S6).** Invoke `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE` (single call, all configured engines) **once**, over the wrapped PR — it reviews code AND finalized docs together (the loop's Phase-1 triage is finding-class-agnostic, so one pass absorbs both). This is the single-review cadence (IDEA-015): wrap-then-review, no separate deliverables/docs passes. With `SPRINT_AUTO_INTEGRATION_WORKTREE` set, the loop's Phase 0 skips entirely — per-IDEA worktrees never get `.env` or docker. Fix-verification routes to the integration worktree as in step 4 (no DB reset within the review session — fix commits don't typically migrate; reset cost would explode). Three outcomes (per [`references/escalation-policy.md`](references/escalation-policy.md)):

    - **Clean** → step 9 (skip step 7/8; no per-IDEA stack to tear down).
    - **Hand-back with Tier 2/3 findings** → step 6a (escalation).
    - **Review-loop budget exhausted** → step 9 with `review_outcome: budget_exceeded`.

    **6a. Escalation resolution (S6).** Tier 2 auto-approved (pre-authorized by `auto_safe` frontmatter + explicit-arg allowlist), Tier 3 attempted (not handed back). Maximum thinking effort per attempt. Each attempt is a **fresh commit**; if it needs a different angle, `git revert <previous-attempt-sha>` before trying again. Cap: **20 attempt cycles** — sized for the code long tail (migration/model/test triads, type-refactor propagation run 4–6 attempts); doc findings that won't converge are caught by `/review-loop`'s own `no_progress_map`, not a tighter cap. Verification routes to integration worktree per step 4. Return to step 6 after each attempt.

07. **(retired — S7).** The separate docs-review pass and its independent 5-cycle budget are retired under the IDEA-015 single-review cadence (the one S6 pass over the wrapped PR covers code + docs). Step number kept as a no-op marker for backward-compat with the v1–v3.2 state numbers (same convention as step 8 below); the auto-run log records `docs_review: folded_into_single_review_s6`.

08. **Per-IDEA teardown — N/A in v3.1 (S8).** Was: `docker compose down` on per-IDEA stack. In v3.1, no per-IDEA stack exists. The integration worktree's stack stays up for the next IDEA's S2 reset. Step kept in the doc as a no-op marker for backward-compat with v1's state numbers; the auto-run log records `docker_teardown: skipped_v3_no_per_idea_stack`.

09. **Capture per-IDEA compound candidates (S9).** Harvest learnings from the IDEA's run — review findings (from the single S6 pass) that exposed patterns, escalation attempts that revealed new recipes, infrastructure gaps discovered during bootstrap, downstream-docs drift patterns from S5's sweep. Do **not** invoke `/compound` yet — queue candidates into a per-batch list for consolidation at step 12. On failure paths, harvest still runs but may queue fewer candidates — plan-rejection patterns and verification-failure patterns are themselves valuable compound signals.

10. **Finalise the per-IDEA auto-run log (S10).** Fields written (see [`assets/auto-run-log-template.md`](assets/auto-run-log-template.md)). Always written, including failure paths. Commit + push to `auto/<slug>`; the log rides into the PR.

11. **Move to next IDEA (S11).** The per-IDEA worktree stays on disk (still useful for code-surface inspection if needed). The integration worktree's stack stays up. The next IDEA's step 3 will reset DB and start fresh.

### 3. Integration phase (S11.5–S11.13) — batch validation

After all per-IDEA loops complete, the integration phase runs once. Full mechanics in [`references/integration-stage.md`](references/integration-stage.md); summary here:

1. **Final pre-merge DB reset (S11.5).** `cd $SPRINT_AUTO_INTEGRATION_WORKTREE && docker compose down -v && docker compose up -d --wait && migrate + seed`. Same baseline as per-IDEA resets but for the integration test run.

2. **Sequential merge (S11.6).** `git checkout integration/sprint-auto-<batch-iso>`. For each `auto/<slug>` in batch-arg order: `git merge --no-ff auto/<slug>`. On conflict: resolve on integration branch using [`references/integration-conflict-resolutions.md`](references/integration-conflict-resolutions.md), commit the resolution. Continue. Track which branches needed resolution.

3. **Batch wrap on integration branch (S11.7).** Compose ONE devlog commit + ONE ideas-index commit covering all N IDEAs. This is the work that per-IDEA `/wrap --scope=idea-only` (S5) deferred. Eliminates the N-way wrap-stage conflicts at the source. **Also maintain the Decisions Recap section** at the top of `docs/ideas/README.md` if the cohort is large (~10+ IDEAs sharing context) — see [`../wrap/SKILL.md`](../wrap/SKILL.md) § "Decisions Recap section". Each IDEA's wrap row + any newly-locked cross-cutting decision is rolled into the same batch-wrap commit.

4. **Integration tests — union (S11.8).** Read each merged-in IDEA's plan-doc Verification section, union test paths, run pytest on the integration stack. Migrate up if migrations were merged. Failure → fix on integration branch, cap **10 attempts**.

5. **Full test suite (S11.9).** Sprint-end gate. Full pytest on the integrated state. Same fix discipline, cap **10 attempts**.

6. **Review-loop on integration branch via `[INTEGRATION]` PR — the merge gate (S11.10).** Review bots are PR-anchored (Cursor Bugbot, GitHub Copilot, and the Claude `code-review` action all operate on PRs, not branches), so:

   ```bash
   gh pr create --base main --head integration/sprint-auto-<batch-iso> \
       --title "[INTEGRATION] sprint-auto-<batch-iso>" \
       --body "Integration of $N per-IDEA PRs (links below). Merging this PR ships
   the entire batch. Per-IDEA PRs auto-close as merged ancestors."
   ```

   The PR is **non-draft** (v3.2 change from v3.1 — it's the actual merge gate, not a validation harness). Then run `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE` against the PR's number. **Cap 20 attempts for the session** (one multi-engine session, shared across configured engines) — integration branches are elephants (N-times-larger review surface than any per-PR PR; T2/T3 findings have proportionally longer tails). Symmetric with the S6a per-IDEA review cap (20) — both are sized for the code long tail.

7. **Integration teardown (S11.13 — was S11.13 in v3.1; S11.11 + S11.12 are deleted in v3.2).** `docker compose down` (NOT `down -v`; volumes preserved for inspection). Worktree filesystem stays. **The `[INTEGRATION]` PR is left OPEN — it's the merge gate, not auto-closed.** The integration branch + worktree are cleaned up by the human's post-merge `/land --integration <batch-iso>` (not per-IDEA), which detects the integration-PR-merge case and `git branch -d integration/sprint-auto-<batch-iso>` + `git worktree remove` the integration worktree.

**v3.2 — what's deleted vs v3.1**:

- ~~S11.11 forward-sync~~ **deleted**: per-IDEA PRs don't need the integrated state propagated back, because their reviewer reviews them at their natural IDEA-isolated diff against integration. The integrated state lives on integration, reviewed via the \[INTEGRATION\] PR.
- ~~S11.12 per-PR re-review~~ **deleted**: per-IDEA PRs haven't had any commits added since the S6 single review pass (which ran over the wrapped PR), so it already covered the current head. Re-running adds zero signal at non-trivial cost.
- ~~"atomic-batch merging" forward-sync property~~ **superseded**: in v3.2 the integration PR is itself atomic-batch — merging it ships every per-IDEA at once. Same property, different mechanism.

**Failure mode summary** (full table in [`references/integration-stage.md`](references/integration-stage.md)):

- S(-1) bootstrap fails (worktree create OR integration-branch push OR docker bootstrap) → abort batch; no per-IDEA work proceeds
- S11.6 merge resolution fails → log + continue to next branch in sequence
- S11.8/S11.9 tests cap-exceeded → ship integration-non-clean (flagged in summary)
- S11.10 review cap-exceeded → ship integration-non-clean (flagged); PR still left open as merge gate

### 4. Batch-level compound + mind-vault review-loop (S12–S15)

When the integration phase completes (clean or with flags):

1. **Consolidate compound candidates (S12 prep)** harvested from every per-IDEA step 9. Cross-IDEA patterns get de-duplicated here: if three IDEAs independently surfaced the same review finding category, it's a stronger compound candidate than any single instance.

2. **Invoke `/compound` per candidate — autonomous mode (S12).** The compound skill's Shape-C narrative probe normally asks up to three questions before routing; under sprint-auto those answers come from the compound candidate's own metadata. The user's invocation of `/sprint-auto` is the *transitive* confirmation that compound's "Never silently promote to mind-vault" interaction rule requires.

3. **Each mind-vault PR → its own review-loop session (S13 + S14).** Once `/compound` produces a PR on `compound/YYYY-MM-DD-<slug>` in the mind-vault repo, invoke `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE` on the mind-vault PR with the same escalation policy as the S6a per-IDEA review pass. Cap **5 attempt cycles** for the session (single-pass — mind-vault compound PRs are documentation by nature).

4. **Write `docs/archive/auto-run-<ISO-timestamp>-summary.md` (S15 artefact)** in the primary tree. See [`assets/auto-run-log-template.md`](assets/auto-run-log-template.md). Includes a new **Integration check** section listing the integration phase's outcomes (merge results, test results, review-loop results per engine) and a **Compound section** listing each mind-vault PR and its review outcome.

5. **Print the summary block to stdout (S15):**

   ```text
   sprint-auto batch complete — 2026-04-20T23:47:12Z

   Per-IDEA PRs (target: integration/sprint-auto-2026-04-20T23-47-12Z, IDEA-isolated diffs):
   ✅ IDEA-050 sync-retry-backoff     → https://github.com/.../pull/123  (review: clean)
   ✅ IDEA-051 modal-dismiss-focus    → https://github.com/.../pull/124  (review: 2 T3 unresolved)
   ⚠️  IDEA-052 alpine-event-bus      → plan REJECTED (architect); see worktree
   ❌ IDEA-053 cache-invalidation     → verification failed (test_cache.py); see worktree

   Integration check (target: main, MERGE GATE):
   ✅ Sequential merge: 2 clean, 0 conflicts
   ✅ Union tests: 414 passed
   ✅ Full suite: 1247 passed
   ⚠️  Integration review: 1 T3 unresolved at cap; see [INTEGRATION] PR
   👉 [INTEGRATION] PR — MERGE THIS to ship the batch:
        https://github.com/.../pull/125

   Compound (mind-vault PRs):
   ✅ RULE_htmx-partial-boundary-check  → https://github.com/.../pull/78   (review: clean)
   ⚠️  skill:curator pass-3 addendum     → https://github.com/.../pull/79   (review: 1 T3 unresolved)

   Docker stacks: 1 stopped (integration; volumes retained). Per-IDEA worktrees preserved (code-surface only).
   Integration branch: integration/sprint-auto-2026-04-20T23-47-12Z (open PR; cleaned up by /land --integration post-merge).
   Batch summary: docs/archive/auto-run-2026-04-20T23-47-12Z-summary.md
   ```

6. **Worktree preservation discipline.** Containers on the integration stack are stopped at S11.13. Per-IDEA worktree filesystems stay (code-surface only; never had stacks). The integration worktree filesystem stays. Full teardown of the integration worktree is the human's chore via `/land --integration sprint-auto-<batch-iso>` post-merge of the `[INTEGRATION]` PR (see § 5 + `skills/land/SKILL.md` § `--integration` mode).

### 5. Post-merge reminders (still human) — v3.2 model

The batch's merge surface is **one PR** — the `[INTEGRATION]` PR (S11.10). Merging it lands every per-IDEA `auto/<slug>` in one shot via the merge commits already on integration. GitHub auto-closes each per-IDEA PR as a merged ancestor (their head SHAs are reachable from the merged integration commit). Everything except the destructive worktree+branch teardown already ran during the batch:

- Per-IDEA frontmatter flip + downstream docs scan: S5 (`/wrap --scope=idea-only`)
- Devlog batch entry + ideas-index batch update: S11.7 (single commit on integration)

The post-merge `/land` invocation runs only the destructive teardown. With v3.2's integration-as-merge-gate, the natural shape is **one** `/land --integration` call against the integration ref:

```markdown
## Next steps (post-merge of the [INTEGRATION] PR)

Run `/land --integration sprint-auto-<batch-iso>` from the primary tree —
it auto-detects post-merge mode and runs:
- For each per-IDEA `auto/<slug>` from the batch manifest:
  - `git worktree remove ../<project>-auto-<slug>`
  - `git branch -d auto/<slug>`
- For the integration worktree:
  - `cd $integration_worktree && docker compose down -v` (drops volumes)
  - `git worktree remove $integration_worktree`
  - `git branch -d integration/sprint-auto-<batch-iso>`

If you merged any per-IDEA PR independently (atypical — splits the
batch), for each IDEA you merged run `/wrap NNN` (finalizes docs) then
`/land NNN` (tears down that IDEA's worktree + branch), and finally
`/land --integration` for the residual integration cleanup.

The frontmatter flip + downstream docs scan already landed at S5; the
devlog batch entry + ideas-index batch update already landed at S11.7
on the integration branch and merged to parent via the integration PR.
```

No `/compound` reminder here — compound ran in section 4 above.

## Interaction rules

- **Belt-and-suspenders opt-in.** Frontmatter declares one of two modes — `auto_safe: true` (autonomous-through-merge-gate) OR `auto_safe_with_eval_gate: true` (autonomous-through-merge-gate + eval-checklist emission for the human to walk before merging) — AND the IDEA's slug appears in the explicit arg allowlist. Never scan-mode in v1; curation is the whole point. The two modes are orthogonal opt-in signals — see [`references/safety-gates.md`](references/safety-gates.md) § Mode A / Mode B for the authoring contract.
- **Eval-gate is the unblock for UX-overhaul / a11y / interaction-heavy IDEAs.** When an IDEA's *implementation* is mechanical (component scaffolding + JS API + render-and-assert tests) but ships behaviour that needs human eyes on visual / focus / screen-reader / animation residue, opt-in via `auto_safe_with_eval_gate: true` instead of leaving the IDEA out of sprint-auto entirely. Sprint-auto runs the IDEA end-to-end without pausing; `/wrap` S5 emits a structured checklist to the IDEA's archive dir (see [`../wrap/SKILL.md`](../wrap/SKILL.md) § Step 7); S11.10 aggregates every emitted checklist's URL into the integration PR's body. The morning reviewer's existing PR-merge gate is now also the manual-walk gate — same review surface, structured in.
- **No merges, ever.** The skill stops at PR creation (project PRs, the non-draft `[INTEGRATION]` PR, and mind-vault compound PRs). `gh pr merge`, `git push` to protected branches, anything that crosses the HITL gate — forbidden. The `[INTEGRATION]` PR specifically is left **OPEN as the human merge gate** at S11.13 — never `gh pr close`d by the skill (v3.2; aligns with lines 171/281).
- **Single docker stack contract.** v3.1 brings up exactly ONE docker stack per batch — the integration worktree's, at port offset `+30000`. Per-IDEA worktrees are pure code surfaces (no `.env`, no `docker compose up`). The verification routing via `SPRINT_AUTO_INTEGRATION_WORKTREE` env var is what makes this work; if any per-IDEA worktree somehow ends up with a `.env` or running stack, treat it as a defect.
- **Verification-routing env var.** Sprint-auto exports `SPRINT_AUTO_INTEGRATION_WORKTREE=<path>` at S(-1). `/work`, the configured `/review-loop` session, and any test-runner shelled out from the per-IDEA loop must honor this var and route their docker/test commands to that path. See [`references/integration-stage.md`](references/integration-stage.md) for the contract.
- **DB reset cadence: per-IDEA, NOT per-review-commit.** A single reset at the entry to each IDEA's S2 (~5 min) gives main-equivalent baseline. Resets within a review session would multiply wall-clock 10× without quality gain — fix commits don't typically migrate.
- **Rollback-able commits only for escalation resolution.** During the S6a per-IDEA review escalation, S11.8/S11.9 fix attempts, and S11.10 integration review escalation, the skill MAY commit multiple attempts, each revertable via `git revert`. It MAY NOT force-push, rewrite history, or amend commits produced by `/work` or by `/wrap`'s docs sweep — those are part of the PR's review history. If a fix attempt goes wrong, the correct move is `git revert <bad-sha>` + a fresh attempt commit.
- **Single review-loop per IDEA + integration review.** Every successful-through-PR IDEA run receives **one** per-PR review-loop invocation (the S6 single pass over the wrapped PR — wrap-before-review, IDEA-015); the batch gets one integration-state review (S11.10). The per-IDEA pass has one independent **escalation-attempt** budget — 20 per IDEA, plus 20 integration (sprint-auto re-entries to resolve T2/T3 findings; see the budget rule below). When `SPRINT_AUTO_REVIEW_ENGINE` lists multiple engines, one multi-engine session runs, so that budget is shared across engines — "20" is 20 escalation attempts for the single review pass, not 20-per-engine. Skipping the review pass is never correct on the happy path. (v3.2 deletes v3.1's per-PR re-review S11.12 — the per-IDEA PR's head doesn't change after S6, so re-running adds no signal.)
- **Review-engine selector — project-configurable, default `none`. One `/review-loop` call carries all configured engines.** Sprint-auto's S6 / S11.10 / S13 / S14 review passes each dispatch a **single** `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE` invocation, passing the whole resolved engine list. `SPRINT_AUTO_REVIEW_ENGINE` is exported during preflight from the project's `review_engine` declaration in `CLAUDE.md` or `.mind-vault.yml`:
  - `SPRINT_AUTO_REVIEW_ENGINE=bugbot` → `/review-loop <PR> bugbot` (single-engine).
  - `SPRINT_AUTO_REVIEW_ENGINE=copilot` → `/review-loop <PR> copilot` (single-engine).
  - `SPRINT_AUTO_REVIEW_ENGINE=claude` → `/review-loop <PR> claude` (single-engine; the `claude-code-action@v1` + `code-review` plugin — push-triggered, comment-anchored. Self-excludes if its action isn't installed on the repo — see [`../review-loop/references/engine-claude.md`](../review-loop/references/engine-claude.md)).
  - `SPRINT_AUTO_REVIEW_ENGINE=bugbot,copilot,claude` (or list form `review_engine: [bugbot, copilot, claude]` in YAML; any non-empty subset works) → `/review-loop <PR> bugbot,copilot,claude` — review-loop's **concurrent multi-engine sync** (wait for the slowest engine per push SHA, batch all engines' findings into one fix commit, retrigger all check-run engines; claude re-runs on the push). A "clean" verdict requires every engine to clear. Generalises to N engines with no change here.
  - `SPRINT_AUTO_REVIEW_ENGINE=none` (default) → **skip the external review pass entirely**. Auto-run log records `review_pass: skipped (engine=none)` for the pass; the per-IDEA PR's `AGENT_curator` pre-commit pass is the only review gate. Surface the skip prominently in the morning summary so the human reviewer knows external-bot coverage was not in play. Treat curator-only as a weaker gate — known to miss edge cases the external bots catch. Wherever this skill describes invoking "the review loop", read it as "invoke `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE`, or skip when engine is `none`".
- **Escalation budget is shared across engines, not multiplied — and is distinct from the loop's internal session bounds.** Sprint-auto's per-pass caps (20 per-IDEA review / 10 union / 10 full / 20 integration / 5 compound) count **escalation attempts** — sprint-auto re-entries to resolve T2/T3 findings, tallied as `review_escalation_attempts` (see [`references/escalation-policy.md`](references/escalation-policy.md)). With one multi-engine `/review-loop` session for the per-IDEA pass (vs the old two sequential single-engine loops), that cap is a single shared budget, NOT 20-per-engine. This is **separate** from `/review-loop`'s own internal `max_commits_per_session` / `max_idle_polls` bounds, which govern fix commits *within* a single session, not sprint-auto's escalation re-entries. Per-engine clearance is tracked inside the loop (asymmetric-clearance hand-back); the escalation budget is shared.
- **Review-loop invocations are MANDATORY (when an engine is configured); ship-non-clean is a fallback, not an upfront opt-out.** When `SPRINT_AUTO_REVIEW_ENGINE` is not `none`, the skill's S6 and S11.10 contracts are "invoke `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE`, work the escalation cycle, ship-non-clean only after the session cap is reached." They are NOT "decide upfront not to invoke and call it ship-non-clean." The auto-run log must record the attempt outcome per pass (per-engine verdicts within), NOT `deferred to morning review` — the latter is a tell that no attempt was made. (When `SPRINT_AUTO_REVIEW_ENGINE=none`, the pass is logged as `review_pass: skipped (engine=none)` per the selector rule.)
- **Sequential in v1.** Parallel IDEA execution invites host contention, and v3.1's single-stack architecture inherently serialises through the integration worktree's DB. Add concurrency later only if v3.1 calibration shows headroom.
- **Respect the architect.** If the plan-time architect review comes back `REJECTED`, that IDEA is done for this batch. Trust the review.
- **Non-clean review is OK to ship-for-review — *after* the attempt was made.** After the per-pass session cap is hit OR the review-loop returned an exhaust-budget signal, an IDEA with unresolved Tier 2/3 findings still produces a valid PR. The morning reviewer decides. Do not block the pipeline on perfection; transparency in the auto-run log (attempt SHAs, approaches, outcomes, per-engine verdicts within the session when both are configured) is the contract.
- **Compound transitive confirmation.** `/compound`'s "Never silently promote to mind-vault" rule is satisfied by sprint-auto's own invocation: the user launched sprint-auto knowing compound runs at end-of-batch, and every mind-vault PR produced lands in the summary for review.
- **Abort-the-batch triggers**: docker daemon lost, disk full, the bootstrap script exits with a class of error flagged unrecoverable, token/minute budget blown at batch scope, mind-vault repo becomes unreachable during section 4. **NEW in v3.1**: integration worktree bootstrap (S(-1)) failure is a hard abort — without the integration stack, no verification can run.
- **Priority is queue order, not a safety gate.** `priority: high` / `medium` / `low` affects the order in which the human schedules ideas — it does not imply "how dangerous to automate". `auto_safe: true` is the authoritative safety signal.
- **`[INTEGRATION]` PR is THE merge gate — non-draft, human-merged.** S11.10 opens it as a non-draft PR targeting parent (`main` / `sprint-*`). S11.13 leaves it OPEN (no auto-close). The human reviews the integration PR's combined diff (per-IDEA diffs + compatibility / conflict-resolution patches as visible commits) and merges it. Per-IDEA PRs auto-close as merged ancestors. (v3.2 change from v3.1, which had the integration PR as `--draft` and auto-closed at S11.13.) Treat any code path that would `gh pr close` the integration PR before human merge as a defect.
- **Per-IDEA PRs target integration, NOT parent — keeps each PR's diff IDEA-isolated.** Reviewer inspects per-IDEA PRs at their natural single-IDEA scope (against the integration base, which starts as a copy of `origin/main`). The integrated state lives on the integration PR; the morning reviewer reads the review-loop findings on both surfaces — IDEA-isolated findings on per-IDEA PRs, integration-state findings on the integration PR. The merge is a single click on the integration PR. *(v3.2 redesign — superseded v3.1's "forward-sync gives the reviewer atomic-batch merging" model. v3.1's mechanism: forward-sync the integrated state into every per-IDEA PR, so any single merge shipped the batch. v3.2's mechanism: integration is the base ref + the merge gate; the property drops out for free without "N identical PRs" UX confusion. Compounded 2026-05-01 from a sprint/ux-overhaul batch where the reviewer noted "now we have 3 identical PRs", confirming v3.1's forward-sync trade-off was reviewer-hostile in the morning-review surface.)*

## When NOT to use these patterns

- **Single IDEA with supervision available.** Use `/plan` + `/work` directly — less ceremony.
- **Any IDEA without `auto_safe: true`.** Tag it first via `/idea <slug>` update, with an explicit `auto_safe_reason` in frontmatter explaining why the human cleared it.
- **IDEAs touching sensitive paths.** See [`references/safety-gates.md`](references/safety-gates.md) for the default-deny list. Override only via explicit `sensitive_paths_cleared: true` in the IDEA frontmatter.
- **First run on a new project (v3.2 mechanics).** First-run signals are listed in `IDEA_integration_branch.md` § First-batch monitoring (a v3.1-era design doc — see its top-of-file supersession banner; the monitoring signals themselves still apply). Run any sprint-auto batch as if it's a real batch — there are no low-stakes nights — but pay extra attention to the listed signals.

## References

- [references/safety-gates.md](references/safety-gates.md) — opt-in criteria, automatic disqualifiers, halt conditions
- [references/worktree-lifecycle.md](references/worktree-lifecycle.md) — per-IDEA code-surface mode + integration-worktree-as-runtime model
- [references/post-pr-sequence.md](references/post-pr-sequence.md) — the S(-1) → S0–S15 state machine including the integration phase
- [references/integration-stage.md](references/integration-stage.md) — integration phase mechanics: env var, sequential merge, batch wrap, non-draft \[INTEGRATION\] PR (the merge gate), `/land --integration` teardown
- [references/integration-conflict-resolutions.md](references/integration-conflict-resolutions.md) — **NEW** algorithm catalogue for S11.6 conflict resolution (devlog, index, .po, HTML, JS, Python, settings, tests)
- [references/escalation-policy.md](references/escalation-policy.md) — T2/T3 resolution rules + per-pass attempt caps (20 per-IDEA review / 10 union / 10 full / 20 integration / 5 mind-vault compound)
- [assets/auto-run-log-template.md](assets/auto-run-log-template.md) — per-IDEA + batch-summary log shape (now includes Integration check section)
- [skills/sprint-auto/references/PARALLEL_WORKTREE_DOCKER.md](references/PARALLEL_WORKTREE_DOCKER.md) — underlying worktree + docker isolation contract
- [rules/RULE_git-safety.md](../../rules/RULE_git-safety.md) — the HITL boundary the skill must never cross
- [skills/idea/references/IDEAS_LOCATION_STATUS.md](../idea/references/IDEAS_LOCATION_STATUS.md) — how IDEA files migrate; `/plan` does the move inside the worktree
- [skills/review-loop/SKILL.md](../review-loop/SKILL.md) — the unified review loop, invoked as `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE` (single call carries one or all configured engines). Called once per IDEA happy path (the single S6 review over the wrapped PR) + once on the \[INTEGRATION\] PR (S11.10, the merge gate) + once per mind-vault compound PR; honors `SPRINT_AUTO_INTEGRATION_WORKTREE` and `SPRINT_AUTO_INTEGRATION_BRANCH`
- [skills/plan/SKILL.md](../plan/SKILL.md) — invoked per IDEA (step 2)
- [skills/work/SKILL.md](../work/SKILL.md) — invoked per plan (step 4); honors `SPRINT_AUTO_INTEGRATION_WORKTREE` for verification routing
- [skills/wrap/SKILL.md](../wrap/SKILL.md) — invoked per IDEA at S5 (`--scope=idea-only` mode); docs finalization only — never merges or tears down (IDEA-015 split)
- [skills/land/SKILL.md](../land/SKILL.md) — owns the destructive teardown (IDEA-015 split); `--integration <batch-iso>` mode runs the post-merge batch teardown from the integration ref (v3.2: human merges the integration PR, then `/land --integration` removes the integration + per-IDEA worktrees/branches)
- [skills/compound/SKILL.md](../compound/SKILL.md) — invoked at batch end (section 4) for cross-project learnings; each mind-vault PR is itself review-looped
- [docs/guides/SPRINT_WORKFLOW.md](../../docs/guides/SPRINT_WORKFLOW.md) — the sprint workflow this skill wraps
- [assets/setup_playwright.sh.template](assets/setup_playwright.sh.template) — bootstrap script projects copy to provision Playwright (the S(-1) probe + per-IDEA `requires_playwright` gate are documented inline above + in `references/safety-gates.md`)
- [skills/work/references/WATCHER_HYGIENE.md](../work/references/WATCHER_HYGIENE.md) — orchestrator-trash-collection discipline for `run_in_background` watchers across S6/S11.10/S13 review loops
- [skills/django-frontend/references/VISUAL_BASELINE_BUMPS.md](../django-frontend/references/VISUAL_BASELINE_BUMPS.md) — AI-never-auto-`--update-snapshots` discipline for Direction-1 IDEAs that ship Playwright visual baselines
