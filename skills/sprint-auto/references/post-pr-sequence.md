# sprint-auto — post-PR state machine

Full state machine for the sprint-auto loop: pre-batch (S(-1)), per-IDEA (S0–S11), batch integration phase (S11.5–S11.13), batch compound (S12–S15). Normative expansion of `SKILL.md` §1–§4. Keep this diagrammatic — implementation detail lives in the referenced docs. This file and `SKILL.md` share a single state numbering; if they disagree, treat it as a defect in this file (the SKILL is the source of behaviour; this file is the source of structure).

## The state machine — pre-batch (S(-1))

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ S(-1) Integration bootstrap (the ONLY docker stack of the batch)             │
│        - git worktree add ../<project>-auto-integration-<batch-iso>         │
│          -b integration/sprint-auto-<batch-iso> origin/main                  │
│        - tools/sprint-auto-bootstrap.sh integration-runner 30                │
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
│      - cd $SPRINT_AUTO_INTEGRATION_WORKTREE && git checkout auto/<slug>     │
│      - docker compose up -d --force-recreate web celery (refresh code)      │
│      - run targeted tests                                                    │
│      │                                                                       │
│      ├── verification failed, no PR ────────────────────────────→ S9        │
│      ├── /work crashed (rare in v3.1: stack lives elsewhere) ───→ S9*       │
│      ↓ PR opened                                                             │
│ S3  /bugbot-loop — deliverables pass                                         │
│      Phase 0 SKIPS (env var detected); fix-verification routes to           │
│      integration worktree (no DB reset within bugbot session)                │
│      │                                                                       │
│      ├── BUGBOT_CLEAN_SIGNAL ───────────────────────────────────→ S5        │
│      ├── bugbot budget exhausted ───────────────────────────────→ S5        │
│      ↓ handback with T2/T3 findings                                          │
│ S4  escalation — deliverables pass (≤20 attempts, own budget)                │
│      │                                                                       │
│      ├── attempt < 20 ───────────────────────────── retry S3                 │
│      ↓ clean OR cap hit                                                      │
│ S5  /wrap --scope=idea-only — pre-merge IDEA-local docs                      │
│      KEEP: frontmatter flip + downstream-docs scan                           │
│      DEFER: devlog + ideas-index → S11.7 batch wrap                          │
│      ↓                                                                       │
│ S6  /bugbot-loop — docs pass (Phase 0 SKIPS)                                 │
│      │                                                                       │
│      ├── BUGBOT_CLEAN_SIGNAL ───────────────────────────────────→ S9        │
│      ├── bugbot budget exhausted ───────────────────────────────→ S9        │
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
│ S11.10 Bugbot-loop on integration branch via [INTEGRATION] draft PR          │
│        (cap 20 — elephants; deliverables-class review of integrated state)   │
│        - gh pr create --draft --title "[INTEGRATION] sprint-auto-<iso>"     │
│        - /bugbot-loop <draft-pr-number>                                      │
│      ↓                                                                       │
│ S11.11 Forward-sync integration into each auto/<slug>                        │
│        - foreach slug: git checkout auto/<slug> && git merge --no-ff        │
│          integration/sprint-auto-<batch-iso> && git push origin auto/<slug> │
│        - feature-branch tip moves; integration branch stays put             │
│        - NO force-push; RULE_git-safety compliant                           │
│      ↓                                                                       │
│ S11.12 Per-PR PR re-bugbot + verification (cap 5 each)                       │
│        - foreach slug: route to integration worktree, checkout auto/<slug>, │
│          reset DB, run targeted tests, /bugbot-loop                          │
│      ↓                                                                       │
│ S11.13 Integration teardown                                                   │
│        - docker compose down (NOT -v; volumes preserved for inspection)      │
│        - gh pr close <integration-draft-pr> with auto-close comment          │
│        - worktree filesystem stays; branch lingers locally                   │
│        - human's /wrap NNN for last-of-batch IDEA does final cleanup         │
└──────────────────────────────────────────────────────────────────────────────┘
```

## The state machine — batch (S12–S15)

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ S12 foreach consolidated compound candidate: /compound (autonomous mode)     │
│      → opens mind-vault PR on compound/YYYY-MM-DD-<slug>                     │
│      ↓                                                                       │
│ S13 /bugbot-loop on each mind-vault PR                                       │
│      │                                                                       │
│      ├── clean OR budget exhausted ─────────────────────────────→ next S12  │
│      ↓ handback                                                              │
│ S14 escalation — mind-vault compound PR (≤5 attempts, own budget)            │
│      │                                                                       │
│      ├── attempt < 5 ───────────────────────────── retry S13                 │
│      ↓ clean OR cap hit                                                      │
│     (update compound PR body with bugbot summary; proceed to next candidate) │
│      ↓                                                                       │
│ S15 batch summary + HITL handoff                                             │
│      → docs/archive/auto-run-<ISO-timestamp>-summary.md (primary tree)       │
│        includes Integration check section (merge results, test results,      │
│        bugbot results, forward-sync results, re-bugbot results)              │
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
| S11.10 | bugbot (integration via [INTEGRATION] draft PR) | **20** attempts | Elephants — N-times-larger review surface; deliverables-class |
| S11.12 | re-bugbot per-PR PR after forward-sync | **5** attempts | Small surface — wrap + resolutions only on already-clean PR |
| S14 | mind-vault compound PR | **5** attempts | Documentation by nature; same logic as docs pass |

Each cap is **independent**. A single IDEA may use up to 30 attempts (20 deliverables + 5 docs + 5 re-bugbot). The integration phase adds another 50 (10 union + 10 full + 20 bugbot + 5 × N re-bugbots — last is per IDEA). A batch of N IDEAs plus M compound PRs has theoretical maximum `N × 30 + 50 + M × 5` attempts; real runs consume a small fraction.

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
| S3 bugbot budget exhausted | (not failure) → S5 | Deliverables pass ends with `deliverables_bugbot_outcome: budget_exceeded`; docs pass still runs |
| S4 cap hit on deliverables | (not failure) → S5 | Ship-non-clean for deliverables; docs pass still runs |
| S6 bugbot budget exhausted | (not failure) → S9 | Docs pass ends with `docs_bugbot_outcome: budget_exceeded` |
| S7 cap hit on docs | (not failure) → S9 | Ship-non-clean for docs |

**Why S10 (log finalization) always runs:** the log IS the diagnostic artefact. Skipping it would silently drop the failure from the paper trail.

**Why S9 (harvest) runs on failure paths:** plan-rejection, verification-failure, and bootstrap-failure patterns are themselves valuable compound signals.

**Why no per-IDEA teardown skip path in v3.1:** under v1, S2 work-crash would skip S8 to preserve the broken stack as diagnostic. In v3.1, S8 is already N/A — there's no per-IDEA stack. The integration stack is shared, so a /work crash needs explicit force-recreate before next IDEA can run, not preservation.

## Integration phase failure modes

| Where | Re-entry / next | What changes |
|---|---|---|
| S(-1) bootstrap fails | ABORT BATCH | No per-IDEA work proceeds; record `integration_outcome: bootstrap_failed` in S15 summary |
| S11.5 reset fails | jump to S15 | Skip integration phase entirely; per-PR PRs ship with their per-IDEA bugbot states intact (no integration validation) |
| S11.6 per-merge resolution fails | continue with next branch | Failed branch's per-PR PR doesn't get S11.11 forward-sync; merges to main on its own merits with cosmetic conflicts intact. Log `merge_results: [{slug, outcome: failed, reason}]` |
| S11.8/S11.9 cap exceeded | continue to next state | Ship integration-non-clean (flagged); reviewer decides at PR-merge time |
| S11.10 bugbot cap exceeded | continue to S11.11 | Same — integration ships flagged |
| S11.11 forward-sync per-branch fails | log, skip that branch's S11.12 | Per-PR PR doesn't get the integration's resolutions — same failure mode as S11.6 fail for that branch |
| S11.12 cap exceeded per branch | log, continue (each PR independent) | Per-PR PR ships with re-bugbot-non-clean state |
| S11.13 teardown fails | log; the human's /wrap catches leftover state | Worktree state stays; branch stays; human cleans up |

## Per-state contract

### S(-1) — Integration bootstrap

Inputs: project root, batch ISO timestamp. Outputs: a running docker stack at port offset `+30000`, the `SPRINT_AUTO_INTEGRATION_WORKTREE` env var exported, the `integration/sprint-auto-<batch-iso>` branch ready for sequential merges.

```bash
batch_iso=$(date -u +%Y-%m-%dT%H-%M-%SZ)
git worktree add "../<project>-auto-integration-${batch_iso}" \
    -b "integration/sprint-auto-${batch_iso}" origin/main
cd "../<project>-auto-integration-${batch_iso}"
tools/sprint-auto-bootstrap.sh integration-runner 30
export SPRINT_AUTO_INTEGRATION_WORKTREE="$PWD"
```

The `30` second arg becomes port offset `+30000` per the bootstrap script's offset formula (`10000 + (idea_number % 100) * 100` would give `+13000` for arg `30`; but a future patch should add explicit port-offset support — see "Implementation note" below).

**Implementation note**: `tools/sprint-auto-bootstrap.sh` currently computes `port_offset` from `idea_number` via `10000 + (idea_number % 100) * 100`. To get the integration stack at exactly `+30000`, either pass `idea_number=200` (yields `10000 + 0 * 100 = 10000` — wrong) or extend the bootstrap script to accept an explicit `--port-offset` flag. The cleanest path is the explicit flag; a follow-up commit on this branch should add it. Until then, calling with arg `30` actually gives `10000 + 30 * 100 = 13000` — close enough to dodge default-port collisions but not at the documented `+30000`. **Treat this as a known issue resolved by a follow-up tooling commit.**

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
git checkout "auto/<slug>"
docker compose up -d --force-recreate web celery  # refresh mounted code
# Run targeted tests as listed in the plan's Verification section
docker compose exec -T web pytest <targeted paths>
```

If verification passes, /work opens a PR. If it fails, re-enter at S9.

### S3 — /bugbot-loop (deliverables pass, Phase 0 SKIPS)

Inputs: PR number. Outputs: one of `{clean, handback-with-findings, budget-exceeded}`.

`/bugbot-loop`'s Phase 0 detects `SPRINT_AUTO_INTEGRATION_WORKTREE` and skips its own worktree-stack bootstrap entirely (no `.env`, no `docker compose up` in per-IDEA worktree). When fix-verification needs a runtime, Phase 2 routes test commands to `$SPRINT_AUTO_INTEGRATION_WORKTREE`. No DB reset within the bugbot session — fix commits don't typically migrate; reset cost would explode.

### S4 — escalation resolution (deliverables pass)

See [`escalation-policy.md`](escalation-policy.md). Cap **20**. Per-attempt verification routes to integration worktree as in S2/S3.

### S5 — /wrap --scope=idea-only

Inputs: PR number, IDEA slug.

Work performed (narrowed from full /wrap):

1. **IDEA frontmatter flip** — `status: in-progress` → `status: complete`, `completed: <today>` (per pre-merge convention; `/wrap` skill detects pre-merge mode automatically).
2. **Downstream docs scan** — for each path the PR touched, grep for references in `README.md`, `docs/guides/`, `docs/reference/`, `CLAUDE.md`, `AGENTS.md`; update any that now point at renamed/removed/changed symbols. PER-IDEA ONLY — does not touch DEVELOPMENT_LOG or ideas-index.

**Skipped at this stage** (deferred to S11.7 batch wrap):

- DEVELOPMENT_LOG entry append
- ideas-index entry move

### S6 — /bugbot-loop (docs pass, Phase 0 SKIPS)

Identical contract to S3, on the PR with S5's commit(s) on top. Same Phase 0 skip rule.

### S7 — escalation resolution (docs pass)

Cap **5**. Independent budget from S4.

### S8 — per-IDEA teardown — N/A IN v3.1

No per-IDEA stack to tear down. The auto-run log records `docker_teardown: skipped_v3_no_per_idea_stack`. The integration stack stays up for the next IDEA.

### S9 — compound-candidate harvest

Same as v1 — queue only, actual `/compound` in S12. Categories:

- **Recurrence**: same bugbot finding category appeared in ≥2 IDEAs this batch (on either pass, including S11.10 integration bugbot)
- **Novel escape**: T3 finding sprint-auto resolved for the first time
- **Infrastructure gap**: bootstrap script gap discovered during S(-1) or per-IDEA verification
- **Docs-drift pattern**: S5 downstream-docs scan finding repeated across IDEAs
- **Integration-state pattern**: NEW v3.1 — patterns surfaced only by the integration phase (S11.6 conflict-resolution patterns, S11.8/S11.9 cross-IDEA test failures, S11.10 integrated-state bugbot findings)
- **Generic noise**: stays local

### S10 — finalise per-IDEA log

Fields written (see [`../assets/auto-run-log-template.md`](../assets/auto-run-log-template.md)):

- `outcome`, `pr_url`
- `deliverables_bugbot_outcome` ∈ `clean | unresolved | budget_exceeded | skipped_no_pr`
- `deliverables_escalation_attempts`: list (cap 20)
- `docs_bugbot_outcome` ∈ `clean | unresolved | budget_exceeded | skipped_no_pr | skipped_failure_pre_pr`
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

### S11.10 — bugbot via [INTEGRATION] draft PR

```bash
gh pr create \
    --base main \
    --head integration/sprint-auto-<batch-iso> \
    --draft \
    --title "[INTEGRATION] sprint-auto-<batch-iso>" \
    --body "Auto-generated integration validation. NOT FOR MERGE."
# capture the PR number
/bugbot-loop <draft-pr-number>
```

Cap **20** attempts. Same escalation discipline as S4.

### S11.11 — forward-sync

Per `RULE_git-safety`: forward-sync = merging integration branch INTO each `auto/<slug>`. The feature branch tip moves; the integration branch stays put. No force-push. PR auto-updates on push.

### S11.12 — per-PR PR re-bugbot + verification

Per per-PR PR: `cd $SPRINT_AUTO_INTEGRATION_WORKTREE && git checkout auto/<slug>` (now post-forward-sync state), reset DB, run targeted tests, `/bugbot-loop`. Cap **5**.

### S11.13 — integration teardown

```bash
cd "$SPRINT_AUTO_INTEGRATION_WORKTREE"
docker compose down  # NOT -v
gh pr close <draft-pr-number> \
    --comment "auto-closed by sprint-auto teardown; integration validation complete. See auto-run summary."
```

### S12 — batch /compound (autonomous)

Unchanged from v1. Compound candidates from per-IDEA S9 + integration-phase candidates surfaced during S11.6/S11.8/S11.9/S11.10.

### S13 — /bugbot-loop (mind-vault compound PR)

Unchanged from v1. Cap **5**.

### S14 — escalation (mind-vault compound PR)

Cap **5**. Update mind-vault PR body with bugbot summary at end.

### S15 — batch summary + HITL handoff

Writes `docs/archive/auto-run-<ISO-timestamp>-summary.md`. Includes the **Integration check** section listing S11.6/S11.7/S11.8/S11.9/S11.10/S11.11/S11.12 outcomes. See [`../assets/auto-run-log-template.md`](../assets/auto-run-log-template.md).

## State transitions that abort the entire batch

Per `SKILL.md`'s "Abort-the-batch triggers":

- **S(-1) bootstrap failure** — without integration worktree, no verification can run. Hard abort.
- Docker daemon becomes unreachable between IDEAs.
- Disk free drops under 5 GB.
- Per-batch budget exhausted.
- Two consecutive IDEAs fail S0 with the same error class (environmental degradation).
- Mind-vault repo unreachable during S12 AND no more candidates would succeed anyway.

On abort, jump directly to S15 with whatever partial state exists. Do NOT retroactively tear down the integration worktree — the human reviewer needs it as the diagnostic artefact (it's the only stack with state).

---

**Last Updated**: 2026-04-27 (v3.1 — added S(-1) integration bootstrap, S1.5 DB reset, S11.5–S11.13 integration phase; S0 narrowed to code-surface-only; S2/S3/S6 verification routes to integration worktree via `SPRINT_AUTO_INTEGRATION_WORKTREE` env var; S5 narrowed to `--scope=idea-only`; S8 marked N/A in v3.1; failure-path invariant updated — now re-enters at S9 instead of S8 since there's no per-IDEA stack to tear down; integration-phase failure-mode table added; canonical port-offset implementation note flagged for follow-up tooling commit.)

**Previous**: 2026-04-22 (structural reconciliation: S0–S15 state numbering shared with SKILL.md; two-pass bugbot-loop inserted; canonical failure-path invariant; escalation caps 20/5/5).
