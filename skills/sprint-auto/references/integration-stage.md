# sprint-auto — integration stage

The batch-level integration phase (states **S(-1)** + **S11.5–S11.13**) introduced in v3.1 of `IDEA_integration_branch.md`. This doc is the normative reference for: the integration worktree's lifecycle, the env-var-driven verification routing, the `[INTEGRATION]` draft PR mechanic, the sequential-merge protocol, the propagate-back forward-sync, and the teardown contract.

If this doc disagrees with `SKILL.md`, treat the discrepancy as a defect in this doc — `SKILL.md` is the source of behaviour.

## Why this stage exists

Before v3.1: every parallel `auto/<slug>` PR's tests passed in isolation, every per-PR bugbot cleared in isolation, but two structural classes of conflict surfaced **only at human merge time**:

1. **Surface conflicts** — two PRs that edit the same file regions (the teisutis 2026-04-26 batch's chat.html + 8 .po files = 12-conflict case)
2. **Wrap-stage conflicts** — every parallel `/wrap` commits to the same lines of `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md` and `docs/ideas/README.md`. Every batch ≥2 IDEAs guarantees N-way line-conflicts, silently taxing every batch

The integration stage closes both. Surface conflicts are surfaced and resolved on the integration branch before the human sees them. Wrap-stage conflicts are eliminated at the source: per-IDEA `/wrap` narrows to frontmatter + downstream-docs only; devlog + index writes move to a **single** batch-wrap commit on the integration branch.

## The integration worktree — naming, location, lifecycle

```text
<project>/                                        ← primary checkout (untouched)
<project>-staging/                                ← human's existing staging worktree (untouched)
<project>-auto-<slug-A>/                          ← per-IDEA worktree (code-surface only, no docker)
<project>-auto-<slug-B>/                          ← per-IDEA worktree (code-surface only, no docker)
…
<project>-auto-integration-<batch-iso>/           ← NEW: the only docker stack of the batch
```

**Naming rules**:
- `<batch-iso>` = the same ISO-8601 timestamp used in `auto-run-<ISO>-summary.md`. Mirrors the existing batch-summary filename so a reviewer can grep one timestamp and find everything related.
- The branch in this worktree is `integration/sprint-auto-<batch-iso>`. Distinct from the human's `staging` branch (which is human-owned, long-lived, on `main`).
- Port offset: `+30000` (see `IDEA_integration_branch.md` § Port-offset math for the full constraint analysis — `+70000` was an early arithmetic error before the 16-bit limit was caught).

**Lifecycle**:
- Created at **S(-1)** (before any per-IDEA work). Bootstrapped via `tools/sprint-auto-bootstrap.sh` with no special flags (this is the canonical mode — full `.env` + docker stack + post-up init).
- Stays up the entire batch. All per-IDEA verification (S2/S3/S6) routes here; all integration-phase work (S11.5–S11.13) happens here.
- Containers stopped (NOT `down -v`) at S11.13. Volumes preserved for inspection. Worktree filesystem stays.
- Branch + worktree cleaned up by the human's `/wrap NNN` post-merge teardown for the **last-of-batch** IDEA (see `skills/wrap/SKILL.md` § Step 5 last-of-batch detection).

If the integration worktree's bootstrap at S(-1) fails: abort the batch. No per-IDEA work proceeds. Record `integration_outcome: bootstrap_failed` in the batch summary; the human investigates the worktree directly.

## Verification routing — `SPRINT_AUTO_INTEGRATION_WORKTREE`

Sprint-auto exports the env var at S(-1):

```bash
export SPRINT_AUTO_INTEGRATION_WORKTREE="$HOME/projects/<project>-auto-integration-<batch-iso>"
```

Three skills detect it and reroute their verification step:

### `/work` (S2)

Default behaviour: run `pytest` against the current worktree's stack. Sprint-auto override: `cd $SPRINT_AUTO_INTEGRATION_WORKTREE && git fetch origin auto/<slug> && git checkout --detach origin/auto/<slug> && docker compose up -d --force-recreate web celery && pytest <targeted paths>`. The `--detach` is required: `auto/<slug>` is already checked out in the per-IDEA worktree, and git refuses to claim the same branch ref in two worktrees. Detaching reads the commits without claiming the ref — exactly what verification needs (no commits happen in the integration worktree).

The `--force-recreate web celery` refreshes the Python services with the per-IDEA branch's mounted code. Stateful services (db, redis, minio, elasticsearch) keep their state from the IDEA-entry reset — no need to recreate them.

### `/bugbot-loop` (S3, S6)

Default behaviour: Phase 0 brings up the current worktree's stack (`.env` template-rewrite + `docker compose up`). Sprint-auto override: **skip Phase 0 entirely**. Per-IDEA worktrees are code-surface-only and have no `.env`. Bugbot's review is remote (Cursor Bugbot reads the PR diff over the GitHub API); bugbot-loop's local role is reading findings + committing fixes — neither needs a runtime in the per-IDEA worktree.

When a fix's verification needs a runtime (e.g. running a targeted test to confirm the fix works): bugbot-loop's Phase 2 routes the test command to `$SPRINT_AUTO_INTEGRATION_WORKTREE` (same routing as `/work`).

### Per-IDEA DB reset cadence

At the **entry to S2 for each IDEA**, sprint-auto runs:

```bash
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
docker compose down -v
docker compose up -d --wait
# Then post-up init from tools/sprint-auto-hooks.sh: migrate, seed, etc.
```

This is the **main-equivalent baseline** for that IDEA's tests + bugbot session. Reset is **per-IDEA, NOT per-bugbot-commit** — within an IDEA's bugbot session, fix commits don't typically migrate, so the DB state is consistent for the duration.

Resetting between bugbot commits would multiply wall-clock 10× without any quality gain. Resetting between IDEAs is what makes per-PR PRs **independently deliverable**: each IDEA's tests run against a DB equivalent to what the morning reviewer's `main` will look like before they merge it.

Wall-clock cost per reset: `down -v` (~5 s) + `up -d --wait` (~30–60 s, depending on healthcheck cadence) + migrate + seed (~1–4 min depending on project size). Budget ~5 min per IDEA reset; for a 6-IDEA batch, total reset wall-clock ~30 min.

## Sequential merge protocol (S11.6)

```bash
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
git checkout integration/sprint-auto-<batch-iso>
# Already at origin/main from S(-1).

for slug in $batch_slugs_in_arg_order; do
    if git merge --no-ff "auto/$slug" -m "merge: integrate auto/$slug"; then
        log_merge_clean "auto/$slug"
    else
        # Conflicts staged. Resolve per references/integration-conflict-resolutions.md.
        resolve_conflicts_for_branch "auto/$slug"
        # The resolution is committed AS PART OF the merge commit — do not
        # `git merge --abort`. The point is to PRESERVE the integrated state.
        git add <resolved-files>
        git commit --no-edit  # uses git's default "Merge branch ..." with conflicts noted
        log_merge_resolved "auto/$slug" --files <resolved-file-list>
    fi
done
```

**Why `--no-ff`**: preserves per-IDEA history. The post-batch git log shows distinct merge commits for each IDEA, so forensic questions like "was the conflict introduced by IDEA-124's commit X or its later commit Y?" stay answerable by `git log --first-parent integration/sprint-auto-<batch-iso>`.

**Why NOT `git merge --abort` on conflict**: v1 of the plan flirted with `--abort + open per-PR PRs anyway with warning`. v3.1's user redirect: resolve on the integration branch, validate, propagate back. So the resolution lands as part of the merge commit (or as a follow-up commit if multi-step), and the integration branch reflects the **complete integrated state**.

**Why NOT `git merge -X ours/theirs`**: silent data loss. Conflicts on translation files are typically "include both contributions" (each IDEA added independent translation keys near each other); `-X ours` would silently drop one IDEA's keys.

**Conflict-resolution algorithm catalogue**: see [`integration-conflict-resolutions.md`](integration-conflict-resolutions.md). Most are mechanical (devlog chronological concat, index alphabetical re-sort, .po include-both); HTML/JS occasionally need human-style judgement, in which case the agent applies the most plausible "include both" resolution and flags the resolution commit for extra scrutiny in S11.10's bugbot pass.

## Batch wrap on the integration branch (S11.7)

Composes the work that per-IDEA `/wrap --scope=idea-only` (S5) deferred:

1. **Devlog batch entry** — read each merged-in IDEA's frontmatter + plan-doc + commits; compose ONE devlog section at the top of `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md` covering all N IDEAs. Format: each IDEA gets its own subsection in chronological IDEA-number order. Single commit `wrap-batch: devlog for sprint-auto-<batch-iso>`.

2. **Ideas-index batch update** — read each merged-in IDEA's title; one commit moving all N entries from their priority sections in `docs/ideas/README.md` to References — Implemented. Single commit `wrap-batch: ideas-index for sprint-auto-<batch-iso>`.

The two commits are separate (devlog + index) for two reasons:
- Reviewer cognitive load: `git show <devlog-sha>` shows one concern
- Bisectability: if S11.10 bugbot flags an issue with the devlog composition specifically, reverting the devlog commit doesn't disturb the index move

## Tests on the integrated state (S11.8 + S11.9)

### S11.8 — Union of per-IDEA target tests

Read each merged-in IDEA's plan-doc Verification section; collect all `pytest` paths; deduplicate; run as one pytest invocation:

```bash
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
docker compose exec -T web pytest <unioned paths>
```

Failure → fix on integration branch (cap **10 attempts**, fresh commits + revert between attempts per `escalation-policy.md`). If cap exceeded → log `integration_union_outcome: cap_exceeded`, proceed to S11.9. The integration is shippable with known-flagged unioned-test failures (the reviewer decides at PR-merge time per the existing ship-non-clean policy).

### S11.9 — Full test suite

```bash
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
docker compose exec -T web pytest
```

Same fix discipline, cap **10 attempts**. Sprint-end gate: catches integration-state failures the union misses (cross-app coupling, subtle dependencies that no IDEA's plan listed but the integrated state surfaces).

### Migrations

Before either test step: `docker compose exec -T web python manage.py migrate --noinput` (or project-equivalent), in case any merged-in IDEA included migrations.

If any IDEA's migration **drops** a column/table that another IDEA's code still references, surfacing this is exactly what S11.8/S11.9 are for. Cap-exceeded here is a strong signal that the human reviewer should NOT merge those two IDEAs in the same window.

## Bugbot on the integration branch (S11.10)

### The `[INTEGRATION]` draft PR mechanic

Cursor Bugbot is anchored to PR URLs. The integration branch is never going to merge to `main`, but bugbot still needs a PR-shaped target. Solution:

```bash
gh pr create \
    --base main \
    --head integration/sprint-auto-<batch-iso> \
    --draft \
    --title "[INTEGRATION] sprint-auto-<batch-iso>" \
    --body "$(cat <<EOF
Auto-generated integration validation PR. **NOT FOR MERGE.**

This PR exists solely so Cursor Bugbot has an anchor for its review of the integrated batch state. It will be auto-closed (without merging) at sprint-auto's S11.13 teardown step.

Batch slugs: <slug-A>, <slug-B>, …
Per-PR PRs: #<A>, #<B>, …
Auto-run summary: <path>
EOF
)"
```

Then run `/bugbot-loop` against the draft PR's number. Cap **20 attempts** — integration branches are elephants (N-times-larger review surface than any per-PR PR). Symmetric with the S4 deliverables-pass cap because integration is deliverables-class review of the integrated state, not docs-class.

### Findings on the integration branch

Two cases:

1. **Finding is integration-state-specific** (only surfaces because of the cross-IDEA combination): fix on the integration branch directly. The fix rides into the forward-sync at S11.11 onto every per-PR branch; the morning reviewer sees it as part of each PR's diff.

2. **Finding is per-PR-specific that bugbot missed during the deliverables/docs passes**: still fix on the integration branch (don't try to back-port to a single per-PR branch — that would re-open a class of pre-integration coordination problems). The forward-sync handles propagation.

### Closing the draft PR

At S11.13, post a comment to the draft PR:

```text
auto-closed by sprint-auto teardown; integration validation complete.
See auto-run summary at <path-to-summary>.
```

Then `gh pr close <N>`. The PR closes without merging; the comment is the audit trail of what the integration validation did. The closed PR's URL goes into the auto-run summary so the human can read bugbot's integration-state findings without recreating state.

## Forward-sync (S11.11) — propagate back to per-PR PRs

After S11.10 clears (or caps), each `auto/<slug>` branch needs the integration's resolutions and batch-wrap commits propagated back, so each per-PR PR merges cleanly to main.

**Run the merge inside the per-IDEA worktree, NOT the integration worktree.** Reason: `auto/<slug>` is already checked out in `<project>-auto-<slug>/`, and git refuses to claim the same branch ref in two worktrees. The integration worktree pushes the integration branch first; per-IDEA worktrees fetch + merge from there.

```bash
# Step 1 — integration worktree pushes its branch so per-IDEA worktrees can fetch.
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
git push origin "integration/sprint-auto-<batch-iso>"

# Step 2 — for each per-IDEA branch, run merge inside its OWN worktree.
for slug in $batch_slugs; do
    cd "$HOME/projects/<project>-auto-${slug}"  # the per-IDEA worktree (auto/<slug> is checked out here)
    git fetch origin "integration/sprint-auto-<batch-iso>"
    git merge --no-ff "origin/integration/sprint-auto-<batch-iso>" \
        -m "merge: forward-sync from integration/sprint-auto-<batch-iso>"
    git push origin "auto/$slug"
done
```

**Forward-sync, not force-push**: the feature-branch tip moves; `integration/sprint-auto-<batch-iso>` stays put. Per `RULE_git-safety` this is "merging `main`-equivalent state into a feature branch" — agent-allowed without force-push. No review threads invalidated.

**Cosmetic acknowledged trade**: each per-PR PR's diff against main now contains commits from every other PR in the batch (transitively, via the merge commit). The morning reviewer's mental model becomes: "this PR represents the post-batch state if the batch is merged in any order." When the reviewer merges PR-A, PR-B's diff against main shrinks (PR-A is now common ancestor); bugbot re-fires automatically; eventually all merge. Weirdness has bounded duration (until the batch is fully merged).

## Re-bugbot per-PR PRs (S11.12)

After forward-sync, each per-PR PR's head is a new SHA. GitHub auto-fires Cursor Bugbot when the head moves; sprint-auto invokes `/bugbot-loop <per-PR PR>` to drive the review-fix-rerun cycle.

Verification routes to the integration worktree as in S2/S3 — `cd $SPRINT_AUTO_INTEGRATION_WORKTREE && git fetch origin auto/<slug> && git checkout --detach origin/auto/<slug>` (post-forward-sync state; `--detach` because the per-IDEA worktree still claims the branch ref), reset DB, run targeted tests one final time. Cap **5 attempts** per PR. Most clean-signal immediately because the new commits are wrap + resolutions, not deliverables work.

## Integration teardown (S11.13)

```bash
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
docker compose down  # NOT -v: preserve volumes for inspection
gh pr close <integration-draft-pr-number> \
    --comment "auto-closed by sprint-auto teardown; integration validation complete. See auto-run summary at <path>."
```

What stays:
- Worktree filesystem at `~/projects/<project>-auto-integration-<batch-iso>/`
- Volumes (db, minio, redis, ES — whatever the project uses) on the docker daemon
- Branch `integration/sprint-auto-<batch-iso>` locally + on origin

What's gone:
- Running containers
- The `[INTEGRATION]` draft PR (closed, not merged)

The worktree + branch + volumes are cleaned up by the **human's `/wrap NNN` for the LAST-OF-BATCH IDEA**. See `skills/wrap/SKILL.md` § Step 5 last-of-batch detection: when the wrap detects this IDEA was part of a sprint-auto batch AND no other `auto/<batch-mate-slug>` worktrees still exist locally (i.e. the human has merged + wrapped them all), additionally tear down the integration worktree:

```bash
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
docker compose down -v
cd -
git worktree remove "$SPRINT_AUTO_INTEGRATION_WORKTREE"
git branch -d "integration/sprint-auto-<batch-iso>"
git push origin --delete "integration/sprint-auto-<batch-iso>"  # optional; remote cleanup
```

## State-by-state contract summary

| State | Purpose | Failure mode |
|---|---|---|
| S(-1) | Bootstrap integration worktree | Bootstrap fails → abort batch entirely |
| S11.5 | Final pre-merge DB reset | Reset fails → log + skip integration phase, jump to S15 |
| S11.6 | Sequential merge of all auto/* into integration | Per-merge resolution fails after best effort → log + continue with what merged |
| S11.7 | Batch wrap (devlog + index) | Compose fails → log + use the per-IDEA-frontmatter as the truth source for partial composition |
| S11.8 | Union of per-IDEA target tests | Cap exceeded → log, ship integration-non-clean |
| S11.9 | Full test suite | Cap exceeded → log, ship integration-non-clean |
| S11.10 | Bugbot via [INTEGRATION] draft PR | Cap exceeded → log, ship with unresolved findings flagged |
| S11.11 | Forward-sync into each auto/<slug> | Per-branch sync fails → log + skip that branch's S11.12 |
| S11.12 | Re-bugbot per-PR PRs | Cap exceeded per branch → log + continue (each PR is independent) |
| S11.13 | Teardown integration stack + draft PR | Failure → log; the worktree's `/wrap` cleanup will catch any leftover state |

## Auto-run log fields

The per-batch summary at `docs/archive/auto-run-<ISO>-summary.md` gains an Integration check section (see `assets/auto-run-log-template.md` for the template). Key fields:

- `integration_branch`: `integration/sprint-auto-<batch-iso>`
- `integration_worktree_path`
- `integration_draft_pr_url` (the auto-closed [INTEGRATION] PR)
- `merge_results`: list of `{ slug, outcome ∈ clean | resolved | failed, conflict_files, resolution_sha }`
- `union_test_outcome` ∈ `clean | unresolved | cap_exceeded`
- `full_suite_outcome` ∈ `clean | unresolved | cap_exceeded`
- `integration_bugbot_outcome` ∈ `clean | unresolved | budget_exceeded`
- `integration_bugbot_attempts` (0–20)
- `forward_sync_results`: list of `{ slug, outcome ∈ ok | failed }`
- `re_bugbot_results`: list of `{ slug, outcome, attempts (0–5) }`
- `teardown` ∈ `stopped_clean | teardown_failed`

## Why the integration phase is in `sprint-auto`, not its own `/integrate` skill

Three reasons:

1. The integration step has no meaning outside sprint-auto's batch context. It needs `auto/<slug>` branches with `auto_safe` provenance, isolated worktrees with bootstrap-script-validated environments, and a known port-offset scheme. None of those preconditions exist for a manual "I have N feature branches, integrate them" use case.
2. Promoting to `/integrate` would invite future use without sprint-auto's preconditions — manually-typed branch names, no `auto_safe` gate, host-port collision with a primary stack. We'd either re-implement the gates inside `/integrate` or ship a less-safe public surface.
3. Splitting `/integrate` later (if usage demand surfaces) is a cheap refactor — extract S11.5–S11.13 logic + parameterise the branch-discovery step. Not pre-emptive worth.

---

**Last Updated**: 2026-04-27 (initial — implements `IDEA_integration_branch.md` v3.1)
