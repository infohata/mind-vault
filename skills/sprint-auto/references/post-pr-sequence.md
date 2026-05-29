# sprint-auto — post-PR state machine

Full state machine for the sprint-auto loop: pre-batch (S(-1)), per-IDEA (S0–S11), batch integration phase (S11.5–S11.13), batch compound (S12–S15). Normative expansion of `SKILL.md` §1–§4. Keep this diagrammatic — implementation detail lives in the referenced docs. This file and `SKILL.md` share a single state numbering; if they disagree, treat it as a defect in this file (the SKILL is the source of behaviour; this file is the source of structure).

> **v3.1 vs v3.2 split.** The top-level state-machine diagrams reflect **v3.2 current** (integration branch is the merge gate; [INTEGRATION] PR is non-draft; per-IDEA PRs target the integration branch; S11.11 forward-sync + S11.12 re-review deleted). The detailed prose sections below (`### S11.10 — review via [INTEGRATION] draft PR`, `### S11.11 — forward-sync`, `### S11.12 — per-PR PR re-review + verification`) still describe **v3.1 historical behavior** and are retained as historical reference for compound provenance. **For current behavior, follow the diagrams + `SKILL.md`; ignore the v3.1 prose sections.** A future debloat pass should either remove the v3.1 prose entirely or rewrite each section in v3.2 form.

## The state machine — pre-batch (S(-1))

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ S(-1) Integration bootstrap (the ONLY docker stack of the batch)             │
│        - git worktree add ../<project>-auto-integration-<batch-iso>         │
│          -b integration/sprint-auto-<batch-iso> origin/main                  │
│        - tools/sprint-auto-bootstrap.sh integration-runner 0 \              │
│              --port-offset 30000                                             │
│          (port offset +30000; sentinel .env; full stack up; post_up_init)    │
│        - export SPRINT_AUTO_INTEGRATION_WORKTREE=<path>                      │
│      │                                                                       │
│      ├── bootstrap failed ───────────────────→ ABORT BATCH (no per-IDEA)    │
│      ↓                                                                       │
│       [enter per-IDEA loop]                                                  │
└──────────────────────────────────────────────────────────────────────────────┘
```

## The state machine — per IDEA (S0–S11)

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ S0  bootstrap — code-surface worktree only (NO docker, NO .env)              │
│      - git worktree add ../<project>-auto-<slug> -b auto/<slug> origin/main │
│      │                                                                       │
│      ├── bootstrap failed ──────────────────────────────────────→ S9        │
│      ↓                                                                       │
│ S1  /plan                                                                    │
│      │                                                                       │
│      ├── architect REJECTED ────────────────────────────────────→ S9        │
│      ↓ ok                                                                    │
│ S1.5 DB reset on integration worktree (~5 min):                              │
│      - cd $SPRINT_AUTO_INTEGRATION_WORKTREE                                  │
│      - docker compose down -v && docker compose up -d --wait                 │
│      - migrate + seed (post_up_init from hooks)                              │
│      ↓                                                                       │
│ S2  /work — verification routes to integration worktree                      │
│      - cd $SPRINT_AUTO_INTEGRATION_WORKTREE && git fetch origin auto/<slug> │
│        && git checkout --detach origin/auto/<slug> (--detach: per-IDEA      │
│        worktree already has the branch checked out; cross-worktree branch   │
│        collision otherwise)                                                  │
│      - docker compose up -d --force-recreate web celery (refresh code)      │
│      - run targeted tests                                                    │
│      │                                                                       │
│      ├── verification failed, no PR ────────────────────────────→ S9        │
│      ├── /work crashed (rare in v3.1: stack lives elsewhere) ───→ S9*       │
│      ↓ PR opened                                                             │
│ S3  /<engine>-loop — deliverables pass                                         │
│      Phase 0 SKIPS (env var detected); fix-verification routes to           │
│      integration worktree (no DB reset within review session)                │
│      │                                                                       │
│      ├── ${ENGINE}_CLEAN_SIGNAL ───────────────────────────────────→ S5        │
│      ├── review budget exhausted ───────────────────────────────→ S5        │
│      ↓ handback with T2/T3 findings                                          │
│ S4  escalation — deliverables pass (≤20 attempts, own budget)                │
│      │                                                                       │
│      ├── attempt < 20 ───────────────────────────── retry S3                 │
│      ↓ clean OR cap hit                                                      │
│ S5  /wrap --scope=idea-only — pre-merge IDEA-local docs                      │
│      KEEP: frontmatter flip + downstream-docs scan                           │
│      DEFER: devlog + ideas-index → S11.7 batch wrap                          │
│      ↓                                                                       │
│ S6  /<engine>-loop — docs pass (Phase 0 SKIPS)                                 │
│      │                                                                       │
│      ├── ${ENGINE}_CLEAN_SIGNAL ───────────────────────────────────→ S9        │
│      ├── review budget exhausted ───────────────────────────────→ S9        │
│      ↓ handback with T2/T3 findings                                          │
│ S7  escalation — docs pass (≤5 attempts, own budget, independent of S4)      │
│      │                                                                       │
│      ├── attempt < 5 ───────────────────────────── retry S6                  │
│      ↓ clean OR cap hit                                                      │
│ S8  per-IDEA teardown — N/A IN v3.1                                          │
│      No per-IDEA stack exists to tear down; integration stack stays up       │
│      for next IDEA's S1.5 reset. Logged as docker_teardown:                  │
│      skipped_v3_no_per_idea_stack.                                           │
│      ↓                                                                       │
│ S9  compound-candidate harvest (queue only; actual /compound in S12)         │
│      ↓                                                                       │
│ S10 finalise per-IDEA log + push (always written, even on failure paths)     │
│      ↓                                                                       │
│ S11 move to next IDEA (or fall through to integration phase if last)         │
└──────────────────────────────────────────────────────────────────────────────┘
```

## The state machine — integration phase (S11.5–S11.13)

After all per-IDEA loops complete:

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ S11.5 Final pre-merge DB reset on integration worktree                       │
│       - cd $SPRINT_AUTO_INTEGRATION_WORKTREE                                 │
│       - docker compose down -v && docker compose up -d --wait + migrate+seed │
│      ↓                                                                       │
│ S11.6 Sequential merge: each auto/<slug> into integration/sprint-auto-<iso> │
│       - git checkout integration/sprint-auto-<batch-iso>                     │
│       - foreach slug in batch_arg_order:                                     │
│           git merge --no-ff auto/<slug>                                      │
│           on conflict: resolve per integration-conflict-resolutions.md       │
│      ↓                                                                       │
│ S11.7 Batch wrap on integration branch:                                      │
│       - ONE devlog commit covering all N IDEAs (chronological/numerical)    │
│       - ONE ideas-index commit moving all N entries to References-Implemented│
│      ↓                                                                       │
│ S11.8 Union of per-IDEA target tests (cap 10 attempts on failure)            │
│       - read each merged-in IDEA's plan-doc Verification section             │
│       - union test paths, run pytest on integration stack                    │
│      ↓                                                                       │
│ S11.9 Full test suite (sprint-end gate, cap 10 attempts on failure)          │
│      ↓                                                                       │
│ S11.10 Review-loop on integration branch via [INTEGRATION] non-draft PR     │
│        — THE MERGE GATE (v3.2 redesign; cap 20 — elephants;                 │
│        deliverables-class review of integrated state)                       │
│        - gh pr create (non-draft) --title "[INTEGRATION] sprint-auto-<iso>" │
│        - /<engine>-loop <pr-number>                                         │
│      ↓                                                                       │
│ ~~S11.11 Forward-sync~~ DELETED in v3.2 — per-IDEA PRs target the           │
│        integration branch directly (not parent), so forward-sync from       │
│        integration back to per-IDEA branches is no longer needed.            │
│ ~~S11.12 Per-PR re-review~~ DELETED in v3.2 — no forward-sync means         │
│        per-IDEA branch tips don't change post-S11.10, so re-running the     │
│        review on them adds zero signal.                                      │
│      ↓                                                                       │
│ S11.13 Integration teardown (post-batch, NOT post-merge)                    │
│        - docker compose down (NOT -v; volumes preserved for inspection)      │
│        - [INTEGRATION] PR LEFT OPEN as the merge gate — the human merges    │
│          it; per-IDEA PRs auto-close as merged ancestors                    │
│        - worktree filesystem stays; branch lingers locally                   │
│        - human's /wrap --integration <batch-iso> does final cleanup          │
└──────────────────────────────────────────────────────────────────────────────┘
```

## The state machine — batch (S12–S15)

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ S12 foreach consolidated compound candidate: /compound (autonomous mode)     │
│      → opens mind-vault PR on compound/YYYY-MM-DD-<slug>                     │
│      ↓                                                                       │
│ S13 /<engine>-loop on each mind-vault PR                                       │
│      │                                                                       │
│      ├── clean OR budget exhausted ─────────────────────────────→ next S12  │
│      ↓ handback                                                              │
│ S14 escalation — mind-vault compound PR (≤5 attempts, own budget)            │
│      │                                                                       │
│      ├── attempt < 5 ───────────────────────────── retry S13                 │
│      ↓ clean OR cap hit                                                      │
│     (update compound PR body with review summary; proceed to next candidate) │
│      ↓                                                                       │
│ S15 batch summary + HITL handoff                                             │
│      → docs/archive/auto-run-<ISO-timestamp>-summary.md (primary tree)       │
│        includes Integration check section (merge results, test results,      │
│        review results)                                                       │
│      → stdout summary block                                                  │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Escalation caps at a glance

| State | Pass | Cap | Rationale |
|---|---|---|---|
| S4 | deliverables (project PR) | **20** attempts | Real code bugs; long T2/T3 tail |
| S7 | docs (project PR) | **5** attempts | Stylistic/reference-drift; converges fast or not at all |
| S11.8 | union tests (integration) | **10** attempts | Cross-cutting failures have shorter tails than per-IDEA |
| S11.9 | full suite (integration) | **10** attempts | Same |
| S11.10 | review (integration via non-draft [INTEGRATION] PR) | **20** attempts | Elephants — N-times-larger review surface; deliverables-class |
| S14 | mind-vault compound PR | **5** attempts | Documentation by nature; same logic as docs pass |

Each cap is **independent**. A single IDEA may use up to **25 attempts** (20 deliverables + 5 docs). The integration phase adds **40 fixed** attempts (10 union + 10 full + 20 review). So a batch of N IDEAs plus M compound PRs has theoretical maximum `N × 25 + 40 + M × 5` attempts; real runs consume a small fraction. (v3.2 deleted the per-IDEA re-review pass S11.12 and its 5-attempt cap — per-IDEA branch tips don't change after S6, so re-running adds zero signal.)

See [`escalation-policy.md`](escalation-policy.md) for the rollback discipline and ship-non-clean contract that surrounds these caps.

## The canonical failure-path invariant

**Every per-IDEA failure path re-enters the happy path at S9 (harvest), then flows through S10 → S11.** S8 is N/A in v3.1 (no per-IDEA stack to tear down).

Concretely:

| Where failure occurs | Re-entry point | What changes |
|---|---|---|
| S0 worktree-add failed | S9 → S10 → S11 | S9 may queue infra-gap candidates; S10 outcome: `bootstrap_failed`, `docker_teardown: skipped_v3_no_per_idea_stack` |
| S1 architect REJECTED | S9 → S10 → S11 | S9 may queue architect blind-spot candidates; S10 outcome: `plan_rejected` |
| S1.5 DB reset failed | S9 → S10 → S11 (skip rest of IDEA) | S10 outcome: `db_reset_failed`; the integration worktree's stack may need manual recovery before next IDEA — surface as abort-the-batch trigger candidate |
| S2 /work failed, no PR | S9 → S10 → S11 | S9 may queue test-env fragility candidates; S10 outcome: `verification_failed` |
| S2 /work crashed (rare in v3.1) | S9 → S10 → S11 | The integration stack is shared; preserving it would taint the next IDEA. Force-recreate the integration stack (`docker compose down -v && up -d`) before next IDEA. S10 outcome: `verification_failed`, note the recovery in the log. |
| S3 review budget exhausted | (not failure) → S5 | Deliverables pass ends with `deliverables_review_outcome: budget_exceeded`; docs pass still runs |
| S4 cap hit on deliverables | (not failure) → S5 | Ship-non-clean for deliverables; docs pass still runs |
| S6 review budget exhausted | (not failure) → S9 | Docs pass ends with `docs_review_outcome: budget_exceeded` |
| S7 cap hit on docs | (not failure) → S9 | Ship-non-clean for docs |

**Why S10 (log finalization) always runs:** the log IS the diagnostic artefact. Skipping it would silently drop the failure from the paper trail.

**Why S9 (harvest) runs on failure paths:** plan-rejection, verification-failure, and bootstrap-failure patterns are themselves valuable compound signals.

**Why no per-IDEA teardown skip path in v3.1:** under v1, S2 work-crash would skip S8 to preserve the broken stack as diagnostic. In v3.1, S8 is already N/A — there's no per-IDEA stack. The integration stack is shared, so a /work crash needs explicit force-recreate before next IDEA can run, not preservation.

## Integration phase failure modes

| Where | Re-entry / next | What changes |
|---|---|---|
| S(-1) bootstrap fails | ABORT BATCH | No per-IDEA work proceeds; record `integration_outcome: bootstrap_failed` in S15 summary |
| S11.5 reset fails | jump to S15 | Skip integration phase entirely; per-PR PRs ship with their per-IDEA review states intact (no integration validation) |
| S11.6 per-merge resolution fails | continue with next branch | Failed branch's commits aren't reflected on the integration branch; its per-IDEA PR still ships (reviewed at its IDEA-isolated diff against integration). Log `merge_results: [{slug, outcome: failed, reason}]` |
| S11.8/S11.9 cap exceeded | continue to next state | Ship integration-non-clean (flagged); reviewer decides at PR-merge time |
| S11.10 review cap exceeded | continue to S11.13 | Integration ships flagged; the non-draft [INTEGRATION] PR is left OPEN for the human to merge or hold |
| S11.13 teardown fails | log; the human's `/wrap --integration` catches leftover state | Worktree state stays; branch stays; human cleans up |

## Per-state contract

### S(-1) — Integration bootstrap

Inputs: project root, batch ISO timestamp. Outputs: a running docker stack at port offset `+30000`, the `SPRINT_AUTO_INTEGRATION_WORKTREE` env var exported, the `integration/sprint-auto-<batch-iso>` branch ready for sequential merges.

```bash
batch_iso=$(date -u +%Y-%m-%dT%H-%M-%SZ)
git worktree add "../<project>-auto-integration-${batch_iso}" \
    -b "integration/sprint-auto-${batch_iso}" origin/main
cd "../<project>-auto-integration-${batch_iso}"
tools/sprint-auto-bootstrap.sh integration-runner 0 --port-offset 30000
export SPRINT_AUTO_INTEGRATION_WORKTREE="$PWD"
```

The `--port-offset 30000` flag (added to `tools/sprint-auto-bootstrap.sh` in this branch) explicitly sets the integration stack at `+30000`. The legacy idea-number-derived formula (`10000 + (idea_number % 100) * 100`) caps at `+19900`, so the explicit flag is required for the v3.1 integration phase. The script enforces a safety ceiling at `+39851` (the recommended bound from `IDEA_integration_branch.md` § Port-offset math, keeping max remapped port `9300+offset` ≤ `49151`).

The `0` second arg is a placeholder `idea_number` (the integration runner isn't a per-IDEA worktree — it's the batch-level runtime — but the script's signature still expects an idea_number). When `--port-offset` is set, the idea_number's only role is in input validation; its computed offset is overridden.

Maps to `SKILL.md` §1 step 8.

### S0 — Per-IDEA worktree bootstrap (code-surface only)

```bash
git worktree add "../<project>-auto-<slug>" -b "auto/<slug>" origin/main
cd "../<project>-auto-<slug>"
```

That's it. NO `tools/sprint-auto-bootstrap.sh` invocation, NO `.env` creation, NO `docker compose up`. The worktree is a code surface; verification commands shell out to the integration worktree via `SPRINT_AUTO_INTEGRATION_WORKTREE`.

If `git worktree add` fails (slug collision, branch exists, etc.), re-enter at S9.

### S1 — /plan

Unchanged from v1. Markdown read/write; no runtime dependency.

### S1.5 — DB reset on integration worktree (entry to S2)

```bash
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
docker compose down -v
docker compose up -d --wait
# Source tools/sprint-auto-hooks.sh and call post_up_init (migrate + seed)
```

Wall-clock: ~5 min depending on seed size. This is the per-IDEA reset that makes per-PR PRs independently deliverable.

### S2 — /work (verification routes to integration worktree)

`/work` skill detects `SPRINT_AUTO_INTEGRATION_WORKTREE` is set and routes its verification step:

```bash
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
git fetch origin "auto/<slug>"
git checkout --detach "origin/auto/<slug>"   # --detach: per-IDEA worktree
                                              # already has the branch ref;
                                              # claiming it twice errors out
docker compose up -d --force-recreate web celery  # refresh mounted code
# Run targeted tests as listed in the plan's Verification section
docker compose exec -T web pytest <targeted paths>
```

If verification passes, /work opens a PR. If it fails, re-enter at S9.

### S3 — /<engine>-loop (deliverables pass, Phase 0 SKIPS)

Inputs: PR number. Outputs: one of `{clean, handback-with-findings, budget-exceeded}`.

`/<engine>-loop`'s Phase 0 detects `SPRINT_AUTO_INTEGRATION_WORKTREE` and skips its own worktree-stack bootstrap entirely (no `.env`, no `docker compose up` in per-IDEA worktree). When fix-verification needs a runtime, Phase 2 routes test commands to `$SPRINT_AUTO_INTEGRATION_WORKTREE`. No DB reset within the review session — fix commits don't typically migrate; reset cost would explode.

### S4 — escalation resolution (deliverables pass)

See [`escalation-policy.md`](escalation-policy.md). Cap **20**. Per-attempt verification routes to integration worktree as in S2/S3.

### S5 — /wrap --scope=idea-only

Inputs: PR number, IDEA slug.

Work performed (narrowed from full /wrap):

1. **IDEA frontmatter flip** — `status: in-progress` → `status: complete`, `completed: <today>` (per pre-merge convention; `/wrap` skill detects pre-merge mode automatically).
2. **Downstream docs scan** — for each path the PR touched, grep for references in `README.md`, `docs/guides/`, `docs/reference/`, `CLAUDE.md`, `AGENTS.md`; update any that now point at renamed/removed/changed symbols. PER-IDEA ONLY — does not touch DEVELOPMENT_LOG or ideas-index.
3. **Eval-gate checklist emission (conditional)** — fires when the IDEA's frontmatter has `auto_safe_with_eval_gate: true`. `/wrap` Step 7 copies the manual-evaluation template from `<mind-vault>/skills/wrap/assets/manual-evaluation-template.md` to `docs/archive/<YYYY-MM-idea-NNN-slug>/<today>-manual-evaluation.md`, fills mechanical placeholders (IDEA number, plan-doc filename, PR number, date), commits to `auto/<slug>`. The plan author's "Manual evaluation scenarios" section (if present) seeds the per-scenario blocks; otherwise the skeleton lands and the integration-PR reviewer fills scenarios from the per-IDEA diff. See [`../../wrap/SKILL.md`](../../wrap/SKILL.md) § Step 7 for emission mechanics. The S6 docs-pass review covers the checklist alongside the rest of the wrap commits.

**Skipped at this stage** (deferred to S11.7 batch wrap):

- DEVELOPMENT_LOG entry append
- ideas-index entry move

### S6 — /<engine>-loop (docs pass, Phase 0 SKIPS)

Identical contract to S3, on the PR with S5's commit(s) on top. Same Phase 0 skip rule.

### S7 — escalation resolution (docs pass)

Cap **5**. Independent budget from S4.

### S8 — per-IDEA teardown — N/A IN v3.1

No per-IDEA stack to tear down. The auto-run log records `docker_teardown: skipped_v3_no_per_idea_stack`. The integration stack stays up for the next IDEA.

### S9 — compound-candidate harvest

Same as v1 — queue only, actual `/compound` in S12. Categories:

- **Recurrence**: same review finding category appeared in ≥2 IDEAs this batch (on either pass, including S11.10 integration review)
- **Novel escape**: T3 finding sprint-auto resolved for the first time
- **Infrastructure gap**: bootstrap script gap discovered during S(-1) or per-IDEA verification
- **Docs-drift pattern**: S5 downstream-docs scan finding repeated across IDEAs
- **Integration-state pattern**: NEW v3.1 — patterns surfaced only by the integration phase (S11.6 conflict-resolution patterns, S11.8/S11.9 cross-IDEA test failures, S11.10 integrated-state review findings)
- **Generic noise**: stays local

### S10 — finalise per-IDEA log

Fields written (see [`../assets/auto-run-log-template.md`](../assets/auto-run-log-template.md)):

- `outcome`, `pr_url`
- `deliverables_review_outcome` ∈ `clean | unresolved | budget_exceeded | skipped_no_pr`
- `deliverables_escalation_attempts`: list (cap 20)
- `docs_review_outcome` ∈ `clean | unresolved | budget_exceeded | skipped_no_pr | skipped_failure_pre_pr`
- `docs_escalation_attempts`: list (cap 5)
- `db_reset_at_idea_entry` ∈ `ok | failed`
- `verification_location` (must be the integration worktree path; flag if otherwise)
- `docker_teardown` ∈ `skipped_v3_no_per_idea_stack` (always, in v3.1)
- `compound_candidates_queued`

### S11 — move to next IDEA

Per-IDEA worktree stays on disk (code-surface only — no docker state to clean). Integration worktree's stack stays up. Next IDEA's S1.5 resets DB.

### S11.5 — final pre-merge DB reset

Same mechanism as S1.5; runs once before sequential merge.

### S11.6 — sequential merge

```bash
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
git checkout integration/sprint-auto-<batch-iso>
for slug in $batch_slugs_in_arg_order; do
    git merge --no-ff "auto/$slug" -m "merge: integrate auto/$slug" \
        || resolve_per_catalogue_then_commit "auto/$slug"
done
```

Resolution algorithm catalogue: [`integration-conflict-resolutions.md`](integration-conflict-resolutions.md). Track per-branch outcome: `clean | resolved | failed`.

### S11.7 — batch wrap on integration branch

Two commits on integration branch:

1. `wrap-batch: devlog for sprint-auto-<batch-iso>` — composes ONE devlog section at top of `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md` covering all N IDEAs in chronological/numerical order
2. `wrap-batch: ideas-index for sprint-auto-<batch-iso>` — moves all N entries in `docs/ideas/README.md` from priority sections to References — Implemented

### S11.8 — union of per-IDEA target tests

Cap **10** attempts on failure. Reads each IDEA's plan-doc Verification section.

### S11.9 — full test suite

Cap **10** attempts on failure. Sprint-end gate.

### S11.10 — review via [INTEGRATION] draft PR

```bash
gh pr create \
    --base main \
    --head integration/sprint-auto-<batch-iso> \
    --draft \
    --title "[INTEGRATION] sprint-auto-<batch-iso>" \
    --body "Auto-generated integration validation. NOT FOR MERGE."
# capture the PR number
/<engine>-loop <draft-pr-number>
```

Cap **20** attempts. Same escalation discipline as S4.

**Eval-checklist aggregation in PR body**: when the batch contains any IDEA with `auto_safe_with_eval_gate: true`, the PR body additionally lists each emitted checklist's URL under a `## Per-IDEA evaluation checklists` section. The aggregation glob is `find docs/archive/<batch-IDEA-dirs>/ -maxdepth 1 -name '*-manual-evaluation.md'`. See [`integration-stage.md`](integration-stage.md) § The `[INTEGRATION]` PR for the full body template + bash composition.

### S11.11 — forward-sync

Per `RULE_git-safety`: forward-sync = merging integration branch INTO each `auto/<slug>`. The feature branch tip moves; the integration branch stays put. No force-push. PR auto-updates on push.

**Run inside the per-IDEA worktree, not the integration worktree.** Reason: `auto/<slug>` is already checked out in `<project>-auto-<slug>/`, and git refuses to claim the same branch ref in two worktrees. The integration worktree pushes its branch first; per-IDEA worktrees fetch and merge from there:

```bash
# integration worktree → push its branch
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
git push origin "integration/sprint-auto-<batch-iso>"

# per-IDEA worktrees → merge in their own checkouts
for slug in $batch_slugs; do
    cd "$HOME/projects/<project>-auto-${slug}"
    git fetch origin "integration/sprint-auto-<batch-iso>"
    git merge --no-ff "origin/integration/sprint-auto-<batch-iso>"
    git push origin "auto/${slug}"
done
```

### S11.12 — per-PR PR re-review + verification

Per per-PR PR: `cd $SPRINT_AUTO_INTEGRATION_WORKTREE && git fetch origin auto/<slug> && git checkout --detach origin/auto/<slug>` (post-forward-sync state; `--detach` because the per-IDEA worktree still claims the branch ref), reset DB, run targeted tests, `/<engine>-loop`. Cap **5**.

### S11.13 — integration teardown

```bash
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
docker compose down  # NOT -v
gh pr close <draft-pr-number> \
    --comment "auto-closed by sprint-auto teardown; integration validation complete. See auto-run summary."
```

### S12 — batch /compound (autonomous)

Unchanged from v1. Compound candidates from per-IDEA S9 + integration-phase candidates surfaced during S11.6/S11.8/S11.9/S11.10.

### S13 — /<engine>-loop (mind-vault compound PR)

Unchanged from v1. Cap **5**.

### S14 — escalation (mind-vault compound PR)

Cap **5**. Update mind-vault PR body with review summary at end.

### S15 — batch summary + HITL handoff

Writes `docs/archive/auto-run-<ISO-timestamp>-summary.md`. Includes the **Integration check** section listing S11.6/S11.7/S11.8/S11.9/S11.10 outcomes. See [`../assets/auto-run-log-template.md`](../assets/auto-run-log-template.md).

## State transitions that abort the entire batch

Per `SKILL.md`'s "Abort-the-batch triggers":

- **S(-1) bootstrap failure** — without integration worktree, no verification can run. Hard abort.
- Docker daemon becomes unreachable between IDEAs.
- Disk free drops under 5 GB.
- Per-batch budget exhausted.
- Two consecutive IDEAs fail S0 with the same error class (environmental degradation).
- Mind-vault repo unreachable during S12 AND no more candidates would succeed anyway.

On abort, jump directly to S15 with whatever partial state exists. Do NOT retroactively tear down the integration worktree — the human reviewer needs it as the diagnostic artefact (it's the only stack with state).
