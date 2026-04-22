# sprint-auto — post-PR state machine

Full state machine for the sprint-auto loop, per-IDEA (S0–S11) and batch-level (S12–S15). Normative expansion of `SKILL.md` §2 + §3. Keep this diagrammatic — implementation detail lives in the referenced skills. This file and `SKILL.md` share a single state numbering; if they disagree, treat it as a defect in this file (the SKILL is the source of behaviour; this file is the source of structure).

## The state machine — per IDEA (S0–S11)

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ S0  bootstrap (worktree + stack up)                                          │
│      │                                                                       │
│      ├── bootstrap failed ──────────────────────────────────────→ S8*       │
│      ↓                                                                       │
│ S1  /plan                                                                    │
│      │                                                                       │
│      ├── architect REJECTED ────────────────────────────────────→ S8        │
│      ↓ ok                                                                    │
│ S2  /work                                                                    │
│      │                                                                       │
│      ├── verification failed, no PR ────────────────────────────→ S8        │
│      ├── /work crashed, inconsistent docker state ──────────────→ S9**      │
│      ↓ PR opened                                                             │
│ S3  /bugbot-loop — deliverables pass                                         │
│      │                                                                       │
│      ├── BUGBOT_CLEAN_SIGNAL ───────────────────────────────────→ S5        │
│      ├── bugbot budget exhausted ───────────────────────────────→ S5        │
│      ↓ handback with T2/T3 findings                                          │
│ S4  escalation — deliverables pass (≤20 attempts, own budget)                │
│      │                                                                       │
│      ├── attempt < 20 ───────────────────────────── retry S3                 │
│      ↓ clean OR cap hit                                                      │
│ S5  /wrap-docs — pre-merge documentation commit to same branch               │
│      (devlog entry + downstream docs scan; NOT frontmatter flip,             │
│       NOT worktree teardown — those stay post-merge)                         │
│      ↓                                                                       │
│ S6  /bugbot-loop — docs pass                                                 │
│      │                                                                       │
│      ├── BUGBOT_CLEAN_SIGNAL ───────────────────────────────────→ S8        │
│      ├── bugbot budget exhausted ───────────────────────────────→ S8        │
│      ↓ handback with T2/T3 findings                                          │
│ S7  escalation — docs pass (≤5 attempts, own budget, independent of S4)      │
│      │                                                                       │
│      ├── attempt < 5 ───────────────────────────── retry S6                  │
│      ↓ clean OR cap hit                                                      │
│ S8  pre-merge teardown (docker compose down, no -v)                          │
│      │  * no-op if S0 failed (nothing running to tear down)                  │
│      │  * skipped entirely if S2 crashed with inconsistent stack (**)        │
│      ↓                                                                       │
│ S9  compound-candidate harvest (queue only; actual /compound in S12)         │
│      ↓                                                                       │
│ S10 finalise per-IDEA log + push (always written, even on failure paths)     │
│      ↓                                                                       │
│ S11 move to next IDEA (or fall through to S12 if last)                       │
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
│      → stdout summary block                                                  │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Escalation caps at a glance

| State | Pass | Cap | Rationale |
|---|---|---|---|
| S4 | deliverables (project PR) | **20** attempts | Real code bugs; the tail is long — bugbot may re-flag a T2 five or six times before the right angle is found. Stingy here converts would-be resolutions into shipped-non-clean, and the whole point of sprint-auto is overnight time to burn. |
| S7 | docs (project PR) | **5** attempts | Documentation findings are mostly stylistic or reference-drift — they converge fast or they don't. 5 is generous enough to try substantially different angles without wasting a budget on a genuinely ambiguous editorial call. |
| S14 | mind-vault compound PR | **5** attempts | Mind-vault compound PRs are documentation by nature (skills, rules, references), so the docs-pass logic applies. Same 5-attempt budget. |

Each cap is **independent** of the others. A single IDEA may legitimately use up to 25 escalation attempts total (20 deliverables + 5 docs), each tracked separately in the per-IDEA log. A batch of N IDEAs plus M compound PRs has a theoretical maximum of `N × 25 + M × 5` attempts, but real runs consume a small fraction of that — most IDEAs clean-signal on the first pass of each bugbot invocation.

See [`escalation-policy.md`](escalation-policy.md) for the rollback discipline and ship-non-clean contract that surrounds these caps.

## The canonical failure-path invariant

**Every per-IDEA failure path re-enters the happy path at S8, then flows through S9 → S10 → S11.** There is exactly one exception (S2 work-crash with inconsistent docker state), documented below.

Concretely:

| Where failure occurs | Re-entry point | What changes |
|---|---|---|
| S0 bootstrap failed | S8 (no-op) → S9 → S10 → S11 | S8 is no-op (nothing running); S9 may queue infra-gap candidates; S10 outcome: `bootstrap_failed`, `docker_teardown: skipped_bootstrap_failure` |
| S1 architect REJECTED | S8 → S9 → S10 → S11 | S8 runs normally (stack came up at S0); S9 may queue architect blind-spot candidates; S10 outcome: `plan_rejected` |
| S2 /work failed, no PR | S8 → S9 → S10 → S11 | S8 runs normally; S9 may queue test-env fragility candidates; S10 outcome: `verification_failed` |
| S2 /work crashed, inconsistent docker | **S9** → S10 → S11 (skips S8) | Preserving the broken stack IS the diagnostic; S10 outcome: `verification_failed`, `docker_teardown: skipped_work_crash` |
| S3 bugbot budget exhausted | (not a failure) → S5 | Deliverables pass ends with `deliverables_bugbot_outcome: budget_exceeded`; docs pass still runs |
| S4 cap hit on deliverables | (not a failure) → S5 | Ship-non-clean for deliverables; `deliverables_bugbot_outcome: unresolved`; docs pass still runs |
| S6 bugbot budget exhausted | (not a failure) → S8 | Docs pass ends with `docs_bugbot_outcome: budget_exceeded`; teardown runs normally |
| S7 cap hit on docs | (not a failure) → S8 | Ship-non-clean for docs; `docs_bugbot_outcome: unresolved`; teardown runs normally |

**Why S10 (log finalization) always runs:** the log IS the diagnostic artefact the morning reviewer needs. Skipping it would silently drop the failure from the paper trail. A rejected or failed IDEA with a rich per-IDEA log is strictly more useful than a successful-but-silent drop.

**Why S9 (harvest) runs on failure paths:** plan-rejection, verification-failure, and bootstrap-failure patterns are themselves valuable compound signals (architect blind-spot, test-env fragility, missing project-local tooling). Harvest runs, queues what it can, and moves on.

**Why the S2-crash exception skips S8:** if `/work` left docker in an inconsistent state (a container OOM'd mid-migration, a volume got corrupted, a build hung and was ctrl-C'd), running `docker compose down` on top of that state erases the diagnostic. The broken stack is more useful to the morning reviewer than a cleanly-stopped mystery. The reviewer does the teardown manually after inspection.

## Per-state contract

### S3 — /bugbot-loop invocation (deliverables pass)

Inputs: PR number. Outputs: one of `{clean, handback-with-findings, budget-exceeded}`.

- Delegate fully to `/bugbot-loop` — sprint-auto does NOT reach into bugbot-loop's internal counters or modify its state file at `~/.claude/memory/projects/<project>/bugbot-pr-<N>.md`.
- `/bugbot-loop` handles its own Tier-1 autonomous fixes and its own ScheduleWakeup cadence.
- Sprint-auto only re-enters when `/bugbot-loop` prints its handback report.

### S4 — escalation resolution (deliverables pass)

See [`escalation-policy.md`](escalation-policy.md) for full rules. Abbreviated contract:

- Findings delivered by `/bugbot-loop`'s handback are classified by bugbot-loop as T2 / T3 / noise.
- Under sprint-auto, T2 is auto-approved and T3 is attempted (not escalated).
- Each attempt = one fresh commit. If the attempt didn't help (bugbot re-flags on retry) or made things worse, `git revert <bad-sha>` before the next attempt.
- Attempt counter is per-pass (deliverables gets its own budget), capped at **20**. After the 20th attempt's bugbot result, proceed regardless to S5.
- Log every attempt's SHA + approach + outcome into the auto-run log's `deliverables_escalation_attempts` table.

### S5 — /wrap-docs (pre-merge documentation commit)

Inputs: PR number, IDEA slug, set of paths the PR's diff touches.

Work performed (documentation-only subset of `/wrap`):

1. **DEVELOPMENT_LOG entry** — append an entry to `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md` (current month's file; create it if rolling over per `RULE_ideas-location-status`) describing what the PR ships, bugbot-pass outcomes so far, any noteworthy escalation attempts. Entry-shape follows the existing monthly log's convention.
2. **Downstream docs scan** — for each path the PR touched, grep for references in `README.md`, `docs/guides/`, `docs/reference/`, `CLAUDE.md`, `AGENTS.md`; update any that now point at renamed/removed/changed symbols.
3. **IDEA-file coherence** — if the PR's work materially completes or narrows the IDEA's scope, note it in the IDEA file body (NOT the frontmatter — frontmatter `status` stays `in-progress` pre-merge).

**Explicitly NOT done at S5:**

- No frontmatter flip to `status: complete` (the PR has not merged; lying in the paper trail is worse than the gap).
- No `-v` volume removal, no `git worktree remove`, no `git branch -D` — all post-merge human chores.

Commit message shape: `docs(archive): IDEA-NNN pre-merge documentation sweep` (or similar — the per-project commit-message convention wins if stricter).

**Trivial-commit case:** if the sweep finds no work to do (no paths referenced in docs changed, no devlog-worthy feature), emit `docs(archive): IDEA-NNN no-op pre-merge docs check` with a one-line rationale; S6 still runs.

Maps to `SKILL.md` §2 step 5.

### S6 — /bugbot-loop invocation (docs pass)

Identical contract to S3, but invoked on the PR with S5's commit(s) on top. Same three outcomes: clean, handback-with-findings, budget-exceeded. Bugbot here typically catches: broken links, devlog entries that contradict the PR's code changes, references to renamed symbols, dead anchors, stale table-of-contents entries.

### S7 — escalation resolution (docs pass)

Identical contract to S4, but with an **independent 5-attempt budget** from S4. An IDEA may use up to 25 escalation attempts total (20 deliverables + 5 docs), each tracked separately in the log.

### S8 — pre-merge teardown (docker stack down)

```bash
cd ~/projects/<project>-auto-<slug>
docker compose down
# no -v: keep volumes so the reviewer can inspect DB/MinIO/ES state if needed
# no worktree remove: the reviewer needs the filesystem
```

Skip S8 **if and only if**:
- S2 detected a `/work` crash with inconsistent stack state (preserving the broken stack IS the diagnostic).

Execute S8 as a no-op (exits cleanly, logs `docker_teardown: skipped_bootstrap_failure`) **if**:
- S0 failed (nothing to tear down).

Otherwise always perform S8 — regardless of whether S3 / S6 cleared, budget-exhausted, or cap-hit. Teardown is orthogonal to bugbot outcome.

Maps to `SKILL.md` §2 step 8.

### S9 — compound-candidate harvest

Not an invocation of `/compound` — just a queue update. Candidates are collected into a batch-level list for S12 aggregation. Per-IDEA compounding would miss cross-IDEA patterns.

Classify candidates into:

- **Recurrence**: the same bugbot finding category appeared in ≥2 IDEAs this batch (on either pass) → strong mind-vault promotion signal (updating `AGENT_bugbot` patterns or a project rule).
- **Novel escape**: a T3 finding sprint-auto resolved for the first time → candidate for bugbot-agent patterns catalogue.
- **Infrastructure gap**: something the bootstrap script didn't provide but we needed (see teisutis IDEA-061 run which surfaced the missing `sprint-auto-hooks.sh`) → candidate for project-local adoption checklist or a mind-vault reference update.
- **Docs-drift pattern**: the S5 downstream-docs scan consistently finds the same class of stale reference across IDEAs → candidate for a doc-layout rule or a `/wrap`-skill extension.
- **Generic noise**: one-off project-specific fixes → stay local, do not promote.

Only the first four categories queue for S12. Maps to `SKILL.md` §2 step 9.

### S10 — finalise per-IDEA log

Fields written (see [`../assets/auto-run-log-template.md`](../assets/auto-run-log-template.md)):

- `outcome` ∈ `success | bugbot_clean | bugbot_unresolved | budget_exceeded | bootstrap_failed | plan_rejected | verification_failed | aborted`
- `pr_url` (null if no PR opened)
- `deliverables_bugbot_outcome` ∈ `clean | unresolved | budget_exceeded | skipped_no_pr`
- `deliverables_escalation_attempts`: list of `{ attempt: 1..20, sha, approach, outcome }`
- `docs_bugbot_outcome` ∈ `clean | unresolved | budget_exceeded | skipped_no_pr | skipped_failure_pre_pr`
- `docs_escalation_attempts`: list of `{ attempt: 1..5, sha, approach, outcome }`
- `docker_teardown` ∈ `stopped | skipped_bootstrap_failure | skipped_work_crash`
- `compound_candidates_queued`: list of candidate types, pointing at the S12 batch aggregation

S10 is always written, including for all failure-path outcomes — `bootstrap_failed`, `plan_rejected`, `verification_failed`. On those paths, `deliverables_bugbot_outcome` and `docs_bugbot_outcome` are both `skipped_no_pr` (no PR was opened, so no bugbot pass ran) or `skipped_failure_pre_pr` (bootstrap failed before worktree existed).

### S12 — batch /compound (autonomous)

Inputs: consolidated candidate list from all per-IDEA S9 steps. For each candidate:

1. Call `/compound` with the candidate's essence and classification.
2. Compound's Shape-C router, under sprint-auto, does NOT stop to ask narrative-probe questions — it reads the candidate's classification from S9 and routes accordingly.
3. Compound emits the mind-vault PR on `compound/YYYY-MM-DD-<slug>`.
4. Sprint-auto proceeds to S13 on the newly-opened PR.

If mind-vault becomes unreachable (fetch / push fails, GitHub API errors), halt S12 + S13 + S14: record candidates that didn't promote into the batch summary so the human can hand-promote them later, then proceed to S15.

### S13 — /bugbot-loop (mind-vault compound PR)

Identical contract to S3, but on the mind-vault repo. Mind-vault compound PRs are documentation by nature — there's no deliverables/docs split to make, so the two-pass structure collapses into this single pass.

### S14 — escalation (mind-vault compound PR)

Same contract as S4/S7: fresh commits, revert-before-retry, **5-attempt cap**, ship-non-clean if cap hit. After S14 resolves (clean, budget, or cap), update the mind-vault compound PR's body with the final bugbot summary before moving to the next candidate.

**Hard-skip extra rule at S14 (from escalation-policy.md):** if bugbot's finding on a compound PR says "this pattern doesn't belong in mind-vault", revert and close the compound PR. That IS the human-level feedback, delivered through bugbot; don't iterate.

### S15 — batch summary + HITL handoff

Writes `docs/archive/auto-run-<ISO-timestamp>-summary.md` in the primary tree and prints the stdout summary block. Contents defined in [`../assets/auto-run-log-template.md`](../assets/auto-run-log-template.md). From here control returns to the human — sprint-auto does not cross the HITL merge gate for either project PRs or mind-vault PRs.

## State transitions that abort the entire batch

Per `SKILL.md`'s "Abort-the-batch triggers" interaction rule:

- Docker daemon becomes unreachable between IDEAs.
- Disk free drops under 5 GB (subsequent worktrees would fail bootstrap anyway).
- Per-batch budget exhausted.
- Two consecutive IDEAs fail S0 with the same error class (environmental degradation).
- Mind-vault repo unreachable during S12 AND no more candidates would succeed anyway.

On abort, jump directly to S15 with whatever partial state exists. Do NOT retroactively tear down worktrees already preserved — the human reviewer needs them as diagnostic artefacts.

---

**Last Updated**: 2026-04-22 (structural reconciliation: S0–S15 state numbering shared with SKILL.md; two-pass bugbot-loop inserted (S3+S4 deliverables, S6+S7 docs), S5 = /wrap-docs pre-merge between them; canonical failure-path invariant — every failure re-enters at S8, S9 + S10 always run, one exception for S2 work-crash skipping S8 to preserve diagnostic; batch states S12–S15 split out for clarity; escalation caps bumped to 20/5/5 — deliverables/docs/mind-vault — each independent)
