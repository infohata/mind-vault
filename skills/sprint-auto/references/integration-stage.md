# sprint-auto — integration stage

The batch-level integration phase (states **S(-1)** + **S11.5–S11.13**) introduced in v3.1 of `IDEA_integration_branch.md` and redesigned in v3.2 to make the integration branch the **merge gate** rather than a validation harness. This doc is the normative reference for: the integration worktree's lifecycle, the env-var-driven verification routing, the `[INTEGRATION]` PR (non-draft, the merge gate, in v3.2), the sequential-merge protocol, and the teardown contract.

**v3.2 vs v3.1**: in v3.1 the integration branch was a disposable validation harness — `[INTEGRATION]` PR was draft + auto-closed; per-IDEA PRs targeted parent (main / sprint-*); after S11.10 cleared, S11.11 forward-synced the integrated state into every per-IDEA PR; S11.12 re-reviewed each per-IDEA PR. In v3.2 the integration branch IS the merge gate — `[INTEGRATION]` PR is non-draft + the human merges it; per-IDEA PRs target the integration branch (kept IDEA-isolated for review); S11.11 + S11.12 deleted (no propagation needed; the integrated state lives only on integration). v3.2 was compounded after a sprint/ux-overhaul cohort surfaced "now we have 3 identical PRs" UX confusion from v3.1's forward-sync mechanism.

If this doc disagrees with `SKILL.md`, treat the discrepancy as a defect in this doc — `SKILL.md` is the source of behaviour.

## Why this stage exists

Before v3.1: every parallel `auto/<slug>` PR's tests passed in isolation, every per-PR review cleared in isolation, but two structural classes of conflict surfaced **only at human merge time**:

1. **Surface conflicts** — two PRs that edit the same file regions (e.g. chat.html + 8 .po files = 12-conflict case)
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
- **v3.2: integration branch published to `origin` immediately at S(-1)** (`git push -u origin integration/sprint-auto-<batch-iso>`) so per-IDEA `/work` invocations in S2 can open PRs with `--base integration/sprint-auto-<batch-iso>`. GitHub requires the base ref to exist on the remote at PR-creation time. (v3.1 deferred this push to S11.10 because the branch was only used as a review anchor at that point.)
- Stays up the entire batch. All per-IDEA verification (S2/S3/S6) routes here; all integration-phase work (S11.5–S11.13) happens here.
- Containers stopped (NOT `down -v`) at S11.13. Volumes preserved for inspection. Worktree filesystem stays. **The `[INTEGRATION]` PR is left OPEN at teardown** (v3.2) — it's the merge gate, not auto-closed.
- Branch + worktree + remote ref cleaned up by the human's post-merge `/wrap --integration <batch-iso>` after merging the integration PR (see `skills/wrap/SKILL.md` § `--integration` mode). The teardown removes the integration worktree, deletes the local + remote integration branch, and removes each per-IDEA worktree + branch (whose PRs auto-closed when the integration PR merged).

If the integration worktree's bootstrap at S(-1) fails (worktree create OR `git push` of integration branch OR `tools/sprint-auto-bootstrap.sh`): abort the batch. No per-IDEA work proceeds. Record `integration_outcome: bootstrap_failed` in the batch summary; the human investigates the worktree directly.

## Verification routing — `SPRINT_AUTO_INTEGRATION_WORKTREE`

Sprint-auto exports the env var at S(-1):

```bash
export SPRINT_AUTO_INTEGRATION_WORKTREE="$HOME/projects/<project>-auto-integration-<batch-iso>"
```

Three skills detect it and reroute their verification step:

### `/work` (S2)

Default behaviour: run `pytest` against the current worktree's stack. Sprint-auto override: `cd $SPRINT_AUTO_INTEGRATION_WORKTREE && git fetch origin auto/<slug> && git checkout --detach origin/auto/<slug> && docker compose up -d --force-recreate web celery && pytest <targeted paths>`. The `--detach` is required: `auto/<slug>` is already checked out in the per-IDEA worktree, and git refuses to claim the same branch ref in two worktrees. Detaching reads the commits without claiming the ref — exactly what verification needs (no commits happen in the integration worktree).

The `--force-recreate web celery` refreshes the Python services with the per-IDEA branch's mounted code. Stateful services (db, redis, minio, elasticsearch) keep their state from the IDEA-entry reset — no need to recreate them.

### `/<engine>-loop` (S3, S6)

Default behaviour: Phase 0 brings up the current worktree's stack (`.env` template-rewrite + `docker compose up`). Sprint-auto override: **skip Phase 0 entirely**. Per-IDEA worktrees are code-surface-only and have no `.env`. The review is performed remotely by the configured bot (Cursor Bugbot or GitHub Copilot reading the PR diff over the GitHub API); the local review-loop's role is reading findings + committing fixes — neither needs a runtime in the per-IDEA worktree.

When a fix's verification needs a runtime (e.g. running a targeted test to confirm the fix works): review-loop's Phase 2 routes the test command to `$SPRINT_AUTO_INTEGRATION_WORKTREE` (same routing as `/work`).

### Per-IDEA DB reset cadence

At the **entry to S2 for each IDEA**, sprint-auto runs:

```bash
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
docker compose down -v
docker compose up -d --wait
# Then post-up init from tools/sprint-auto-hooks.sh: migrate, seed, etc.
```

This is the **main-equivalent baseline** for that IDEA's tests + review session. Reset is **per-IDEA, NOT per-review-commit** — within an IDEA's review session, fix commits don't typically migrate, so the DB state is consistent for the duration.

Resetting between review commits would multiply wall-clock 10× without any quality gain. Resetting between IDEAs is what makes per-PR PRs **independently deliverable**: each IDEA's tests run against a DB equivalent to what the morning reviewer's `main` will look like before they merge it.

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

**Conflict-resolution algorithm catalogue**: see [`integration-conflict-resolutions.md`](integration-conflict-resolutions.md). Most are mechanical (devlog chronological concat, index alphabetical re-sort, .po include-both); HTML/JS occasionally need human-style judgement, in which case the agent applies the most plausible "include both" resolution and flags the resolution commit for extra scrutiny in S11.10's review pass.

## Batch wrap on the integration branch (S11.7)

Composes the work that per-IDEA `/wrap --scope=idea-only` (S5) deferred:

1. **Devlog batch entry** — read each merged-in IDEA's frontmatter + plan-doc + commits; compose ONE devlog section at the top of `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md` covering all N IDEAs. Format: each IDEA gets its own subsection in chronological IDEA-number order. Single commit `wrap-batch: devlog for sprint-auto-<batch-iso>`.

2. **Ideas-index batch update** — read each merged-in IDEA's title; one commit moving all N entries from their priority sections in `docs/ideas/README.md` to References — Implemented. Single commit `wrap-batch: ideas-index for sprint-auto-<batch-iso>`.

The two commits are separate (devlog + index) for two reasons:
- Reviewer cognitive load: `git show <devlog-sha>` shows one concern
- Bisectability: if S11.10 review flags an issue with the devlog composition specifically, reverting the devlog commit doesn't disturb the index move

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

## Review-loop on the integration branch (S11.10)

### The `[INTEGRATION]` PR — non-draft, the merge gate (v3.2)

```bash
# Discover any per-IDEA eval-gate checklists for this batch.
# Wrap S5 emits these to docs/archive/<dir>/YYYY-MM-DD-manual-evaluation.md
# when the IDEA's frontmatter has auto_safe_with_eval_gate: true. See
# safety-gates.md § Mode B and skills/wrap/SKILL.md § Step 7.
eval_checklists=()
for slug in "${batch_slugs[@]}"; do
    archive_dir=$(find "docs/archive" -maxdepth 1 -type d -name "*-${slug}" | head -1)
    [[ -z "$archive_dir" ]] && continue
    while IFS= read -r checklist; do
        eval_checklists+=("$checklist")
    done < <(find "$archive_dir" -maxdepth 1 -name '*-manual-evaluation.md')
done

# Compose the eval-checklist section if any were emitted in this batch.
eval_section=""
if (( ${#eval_checklists[@]} > 0 )); then
    eval_section=$'\n\n## Per-IDEA evaluation checklists\n\n'
    eval_section+=$'The following IDEAs ship behaviours that need human eyes on visual / a11y / interaction review before merge. Walk each checklist in a real browser, tick boxes (or note deviations), then merge.\n\n'
    for c in "${eval_checklists[@]}"; do
        # Convert local path → repo URL on the integration branch:
        #   docs/archive/2026-05-idea-141-modal-primitives/2026-05-05-manual-evaluation.md
        # → https://github.com/<owner>/<repo>/blob/integration/sprint-auto-<batch-iso>/<path>
        url="https://github.com/<owner>/<repo>/blob/${SPRINT_AUTO_INTEGRATION_BRANCH}/${c}"
        # Pull the IDEA's title from its archive-dir IDEA file (best-effort).
        # `sub` + `print` (NOT `-F': ' {print $2}`) preserves the full title
        # even when it contains a colon-space (e.g. "Modal: Confirm & Error
        # Variants" — field-splitting on ': ' would truncate to "Modal").
        idea_file=$(dirname "$c")/IDEA-*.md
        title=$(awk '/^title:/ { sub(/^title:[[:space:]]*/, ""); print; exit }' $idea_file 2>/dev/null \
                 || basename "$(dirname "$c")")
        eval_section+="- [ ] [${title}](${url})"$'\n'
    done
fi

gh pr create \
    --base main \
    --head integration/sprint-auto-<batch-iso> \
    --title "[INTEGRATION] sprint-auto-<batch-iso>" \
    --body "$(cat <<EOF
Integration of $N per-IDEA PRs from sprint-auto batch <batch-iso>.

**Merging this PR ships the entire batch.** Per-IDEA PRs auto-close as merged ancestors when this merges.

Batch slugs: <slug-A>, <slug-B>, …
Per-IDEA PRs (target this branch, IDEA-isolated diffs for review):
- #<A> — IDEA-NNN <slug-A>
- #<B> — IDEA-NNN <slug-B>
- …

Compatibility / conflict-resolution patches: see commits on this branch
(authored by sprint-auto during S11.6 sequential merge + S11.7 batch wrap +
S11.8/S11.9 test fixups + S11.10 integration-review fixups, if any).

Auto-run summary: <path>${eval_section}
EOF
)"
```

If the batch contains no eval-gate IDEAs, `eval_section` stays empty and the PR body is identical to a v3.2 batch with only `auto_safe: true` IDEAs — the section is purely additive.

Then run `/<engine>-loop` against the PR's number. Cap **20 attempts** — integration branches are elephants (N-times-larger review surface than any per-PR PR). Symmetric with the S6a per-IDEA review cap (20): both are sized for the code long tail.

(v3.1 used `--draft` because the PR was solely a review anchor; v3.2 drops `--draft` because it's the actual merge gate. The PR is left OPEN at S11.13; the human merges it.)

### Findings on the integration branch (v3.2)

Two cases — both fix directly on the integration branch:

1. **Finding is integration-state-specific** (only surfaces because of the cross-IDEA combination): fix on the integration branch. The fix becomes part of the integrated diff visible on the [INTEGRATION] PR. Per-IDEA PRs are not touched (they target integration; their diff doesn't include the integrated state).

2. **Finding is per-PR-specific that review missed during the per-IDEA review pass**: also fix on the integration branch. Don't back-port to the per-IDEA branch — the per-IDEA PR's review surface is "what the IDEA introduced *before* integration", and re-opening it after S6 would require another review pass on a SHA that's no longer the per-IDEA boundary. The fix on integration is the right surface; the morning reviewer sees it on the [INTEGRATION] PR's combined diff alongside the IDEA's content.

(v3.1 had this same fix-on-integration discipline but the fix then forward-synced into per-IDEA PRs at S11.11 + re-reviewed at S11.12. v3.2 deletes both — the fix lives only on integration, and the morning reviewer reads it there as part of the merge-gate diff.)

## Integration teardown (S11.13) — v3.2

```bash
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
docker compose down  # NOT -v: preserve volumes for inspection
# The [INTEGRATION] PR is NOT closed — it's the merge gate, left OPEN
# for the human to review and merge. No `gh pr close` here.
```

What stays:
- Worktree filesystem at `~/projects/<project>-auto-integration-<batch-iso>/`
- Volumes (db, minio, redis, ES — whatever the project uses) on the docker daemon
- Branch `integration/sprint-auto-<batch-iso>` locally + on origin
- **The `[INTEGRATION]` PR — open, awaiting human merge** (v3.2 change)

What's gone:
- Running containers

The worktree + branch + volumes are cleaned up by the **human's `/wrap --integration <batch-iso>`** post-merge of the integration PR (v3.2). See `skills/wrap/SKILL.md` § `--integration` mode. The teardown:

```bash
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
docker compose down -v
cd -
git worktree remove "$SPRINT_AUTO_INTEGRATION_WORKTREE"
git branch -d "integration/sprint-auto-<batch-iso>"
git push origin --delete "integration/sprint-auto-<batch-iso>"  # remote cleanup
# Plus, for each per-IDEA branch from the batch manifest (auto-closed on merge):
for slug in $batch_slugs; do
    git worktree remove "$HOME/projects/<project>-auto-${slug}"
    git branch -d "auto/${slug}"
done
```

(v3.1 cleanup ran from the human's `/wrap NNN` of the last-of-batch IDEA and required detecting that no other `auto/*` worktrees remained. v3.2 reverses the trigger: the integration PR's merge is the natural cleanup point, and the integration ref carries the manifest of which per-IDEA branches to tear down.)

## State-by-state contract summary

| State | Purpose | Failure mode |
|---|---|---|
| S(-1) | Bootstrap integration worktree + push integration branch to origin | Worktree create OR push OR docker bootstrap fails → abort batch entirely |
| S11.5 | Final pre-merge DB reset | Reset fails → log + skip integration phase, jump to S15 |
| S11.6 | Sequential merge of all auto/* into integration | Per-merge resolution fails after best effort → log + continue with what merged |
| S11.7 | Batch wrap (devlog + index) | Compose fails → log + use the per-IDEA-frontmatter as the truth source for partial composition |
| S11.8 | Union of per-IDEA target tests | Cap exceeded → log, ship integration-non-clean |
| S11.9 | Full test suite | Cap exceeded → log, ship integration-non-clean |
| S11.10 | Review-loop via [INTEGRATION] non-draft PR (the merge gate) | Cap exceeded → log, ship with unresolved findings flagged; PR still left OPEN |
| ~~S11.11~~ | ~~Forward-sync~~ — **deleted in v3.2** (per-IDEA PRs already target integration; no propagation needed) | n/a |
| ~~S11.12~~ | ~~Re-review per-PR PRs~~ — **deleted in v3.2** (per-IDEA PR heads unchanged after S6; no new SHA to review) | n/a |
| S11.13 | Stop containers; leave [INTEGRATION] PR OPEN as merge gate | Failure → log; the human's post-merge `/wrap --integration` cleanup will catch any leftover state |

## Auto-run log fields

The per-batch summary at `docs/archive/auto-run-<ISO>-summary.md` gains an Integration check section (see `assets/auto-run-log-template.md` for the template). Key fields:

- `integration_branch`: `integration/sprint-auto-<batch-iso>`
- `integration_worktree_path`
- `integration_pr_url` (the OPEN, non-draft [INTEGRATION] PR — the merge gate; v3.2)
- `per_idea_pr_base`: `integration/sprint-auto-<batch-iso>` (v3.2 — per-IDEA PRs target integration, not parent)
- `merge_results`: list of `{ slug, outcome ∈ clean | resolved | failed, conflict_files, resolution_sha }`
- `union_test_outcome` ∈ `clean | unresolved | cap_exceeded`
- `full_suite_outcome` ∈ `clean | unresolved | cap_exceeded`
- `integration_review_outcome` ∈ `clean | unresolved | budget_exceeded`
- `integration_review_attempts` (0–20)
- `eval_gate_idea_count` (number of IDEAs in the batch with `auto_safe_with_eval_gate: true`; 0 if none)
- `eval_checklists_emitted` (count; should equal `eval_gate_idea_count` when wrap S5 fired correctly — divergence is a signal that S7 emission failed silently for some IDEA)
- ~~`forward_sync_results`~~ — removed in v3.2
- ~~`re_review_results`~~ — removed in v3.2
- `teardown` ∈ `stopped_clean | teardown_failed` (note: integration PR is NOT auto-closed; left OPEN as merge gate)

## Why the integration phase is in `sprint-auto`, not its own `/integrate` skill

Three reasons:

1. The integration step has no meaning outside sprint-auto's batch context. It needs `auto/<slug>` branches with `auto_safe` provenance, isolated worktrees with bootstrap-script-validated environments, and a known port-offset scheme. None of those preconditions exist for a manual "I have N feature branches, integrate them" use case.
2. Promoting to `/integrate` would invite future use without sprint-auto's preconditions — manually-typed branch names, no `auto_safe` gate, host-port collision with a primary stack. We'd either re-implement the gates inside `/integrate` or ship a less-safe public surface.
3. Splitting `/integrate` later (if usage demand surfaces) is a cheap refactor — extract S11.5–S11.13 logic + parameterise the branch-discovery step. Not pre-emptive worth.
