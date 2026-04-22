# sprint-auto — post-PR state machine

Full state machine for the per-IDEA loop, starting the moment `/work` opens the PR. Normative expansion of `SKILL.md` §2 steps 4-9 and §3. Keep this diagrammatic — implementation detail lives in the referenced skills.

## The nine states

```text
┌────────────────────────────────────────────────────────────────────────────┐
│ S0  worktree + stack up                                                    │
│      ↓                                                                     │
│ S1  /plan                  ─┬─ architect REJECTED → jump to S5           │
│      ↓ ok                   │                                              │
│ S2  /work                  ─┼─ verification failed, no PR → jump to S5   │
│      ↓ PR opened            │                                              │
│ S3  /bugbot-loop PR        ─┼─ BUGBOT_CLEAN_SIGNAL         ─→  S5          │
│      ↓ handback with T2/T3  │                                              │
│      │  (bugbot's own       │                                              │
│      │   T1 already fixed   │                                              │
│      │   autonomously)      │                                              │
│      ↓                       │                                              │
│ S4  escalation resolution  ─┼─ attempts < 3 & not clean  ─→ retry S3     │
│      (max 3 attempt cycles) │                                              │
│      ↓ clean OR cap hit     │                                              │
│ S5  pre-merge wrap          │   docker compose down (no -v)                │
│      (teardown containers)  │   keep worktree for reviewer                 │
│      ↓                       │                                              │
│ S6  compound-candidate      │   (queue only; actual /compound in S9)       │
│      harvest                │                                              │
│      ↓                       │                                              │
│ S7  finalise per-IDEA log   │   outcome + PR + bugbot + teardown           │
│      + push                 │   commit onto auto/<slug>                    │
│      ↓                       │                                              │
│ S8  move to next IDEA       │                                              │
│                              │   ... all IDEAs processed ...               │
│                              │                                              │
│ S9  batch /compound         │   foreach candidate: /compound autonomous   │
│      + mind-vault bugbot    │   each mind-vault PR → /bugbot-loop         │
│      ↓                                                                     │
│ S10 batch summary + handoff to human (HITL merge)                          │
└────────────────────────────────────────────────────────────────────────────┘
```

This order (teardown S5 → harvest S6 → log S7) matches `SKILL.md` §2 steps 6 → 7 → 8. The clean-bugbot path (S3 → S5) still flows through S6 for harvest; compound-candidate collection is cheap and always runs regardless of bugbot outcome, because infrastructure-gap candidates (bootstrap-script gaps, missing hooks, test-env fragility) surface even on "clean" runs.

**Failure paths rejoin the happy path at S5.** The "jump to S5" arrows from S1 REJECTED / S2 work-failed are re-entry points, not short-circuits: once at S5, the IDEA flows through S5 → S6 → S7 → S8 normally. Per-IDEA logs (S7) are always written — including failure outcomes (`plan_rejected`, `verification_failed`, `bootstrap_failed`) — because the log IS the diagnostic artefact. Harvest (S6) runs too; on failure it may queue fewer candidates, but plan-rejection patterns or verification-failure patterns are themselves valuable compound signals.

## Per-state contract

### S3 — `/bugbot-loop` invocation

Inputs: PR number. Outputs: one of `{clean, handback-with-findings, budget-exceeded}`.

- Delegate fully to `/bugbot-loop` — sprint-auto does NOT reach into bugbot-loop's internal counters or modify its state file at `~/.claude/memory/projects/<project>/bugbot-pr-<N>.md`.
- `/bugbot-loop` handles its own Tier-1 autonomous fixes and its own ScheduleWakeup cadence.
- Sprint-auto only re-enters when `/bugbot-loop` prints its handback report.

### S4 — escalation resolution (the sprint-auto-specific step)

See [`escalation-policy.md`](escalation-policy.md) for full rules. Abbreviated contract:

- Findings delivered by `/bugbot-loop`'s handback are classified by bugbot-loop as T2 / T3 / noise.
- Under sprint-auto, T2 is auto-approved and T3 is attempted (not escalated).
- Each attempt = one fresh commit. If the attempt didn't help (bugbot re-flags on retry) or made things worse, `git revert <bad-sha>` before the next attempt.
- Attempt counter is per-IDEA, capped at 3. After the third attempt's bugbot result, proceed regardless to S5 (teardown).
- Log every attempt's SHA + approach + outcome into the auto-run log.

### S5 — pre-merge wrap (docker teardown)

```bash
cd ~/projects/<project>-auto-<slug>
docker compose down
# no -v: keep volumes so the reviewer can inspect DB/MinIO/ES state if needed
# no worktree remove: the reviewer needs the filesystem
```

Skip S5 if:
- The worktree bootstrap failed at S0 (no stack to stop; diagnostic already maximal).
- `/work` itself crashed before opening a PR and left an inconsistent docker state — in that case, do NOT down the stack; the stack state IS part of the diagnostic.

Always perform S5 if the stack is running at a consistent post-bootstrap state, regardless of bugbot-loop outcome.

Maps to `SKILL.md` §2 step 6.

### S6 — compound-candidate harvest

Not an invocation of `/compound` — just a queue update. Candidates are collected into a batch-level list for S9 aggregation. Per-IDEA compounding would miss cross-IDEA patterns.

Classify candidates into:

- **Recurrence**: the same bugbot finding category appeared in ≥2 IDEAs this batch → strong mind-vault promotion signal (updating `AGENT_bugbot` patterns or a project rule).
- **Novel escape**: a T3 finding sprint-auto resolved for the first time → candidate for bugbot-agent patterns catalogue.
- **Infrastructure gap**: something the bootstrap script didn't provide but we needed (see teisutis IDEA-061 run which surfaced the missing `sprint-auto-hooks.sh`) → candidate for project-local adoption checklist or a mind-vault reference update.
- **Generic noise**: one-off project-specific fixes → stay local, do not promote.

Only the first three categories queue for S9. Maps to `SKILL.md` §2 step 7.

### S7 — finalise per-IDEA log

Fields updated (see [`../assets/auto-run-log-template.md`](../assets/auto-run-log-template.md)):

- `outcome`: `success | bugbot_clean | bugbot_unresolved | budget_exceeded | bootstrap_failed | plan_rejected | verification_failed`
- `bugbot_summary`: `{ cycles, t1_autofixed, t2_resolved_by_sprint_auto, t3_resolved, t3_unresolved_with_last_attempt_sha }`
- `escalation_attempts`: list of `{ attempt: 1|2|3, sha, approach, outcome }`
- `docker_teardown`: `stopped | skipped_bootstrap_failure | skipped_work_crash`
- `compound_candidates_queued`: list of candidate types, pointing at the S9 batch aggregation

### S9 — batch `/compound`

Inputs: consolidated candidate list. For each candidate:

1. Call `/compound` with the candidate's essence and classification.
2. Compound's Shape-C router, under sprint-auto, does NOT stop to ask narrative-probe questions — it reads the candidate's classification from S6 and routes accordingly.
3. Compound emits the mind-vault PR on `compound/YYYY-MM-DD-<slug>`.
4. Sprint-auto invokes `/bugbot-loop <mind-vault-PR>` on the newly-opened PR, following the same S3-S4 logic.
5. Update the compound PR's body with the final bugbot outcome before moving to the next candidate.

If mind-vault becomes unreachable (fetch / push fails, GitHub API errors), halt S9: record candidates that didn't promote into the batch summary so the human can hand-promote them later, then proceed to S10.

## State transitions that re-enter at S5 (not skip states)

Failure paths don't skip later states — they re-enter the happy-path at S5 (teardown), then flow through S6 (harvest) and S7 (log finalize) like every other IDEA. The only thing that changes is the `outcome:` field written at S7 and what's queueable at S6:

- **S0 bootstrap failed** → S6 (harvest limited — no stack means no bugbot data; infrastructure-gap candidates still possible) → S7 (outcome: `bootstrap_failed`, `docker_teardown: skipped_bootstrap_failure`) → S8. Skips S5 because there's no complete stack to tear down.
- **S1 architect REJECTED** → S5 (teardown) → S6 (harvest — plan-rejection patterns are valuable compound signals; the IDEA may have exposed an architect blind-spot or template gap) → S7 (outcome: `plan_rejected`) → S8.
- **S2 /work failed without opening PR** → S5 (teardown) → S6 (harvest — verification failures are also valuable; the test that failed may reveal a test-env gap or fragile pattern) → S7 (outcome: `verification_failed`) → S8.

Rationale for always writing the log (S7) on failure: the log IS the diagnostic artefact the morning reviewer needs. Skipping S7 would silently drop the failure from the paper trail. A rejected or failed IDEA with a rich per-IDEA log is strictly more useful than a successful-but-silent drop.

## State transitions that abort the entire batch

Per `SKILL.md`'s "Abort-the-batch triggers" interaction rule:

- Docker daemon becomes unreachable between IDEAs.
- Disk free drops under 5 GB (subsequent worktrees would fail bootstrap anyway).
- Per-batch budget exhausted.
- Two consecutive IDEAs fail S0 with the same error class (environmental degradation).
- Mind-vault repo unreachable during S9 AND no more candidates would succeed anyway.

On abort, jump directly to S10 with whatever partial state exists. Do NOT retroactively tear down worktrees already preserved.

---

**Last Updated**: 2026-04-22 (initial — codifies the nine-state machine post-`/work` for sprint-auto; state labels aligned to SKILL.md §2 step order: S5 = teardown, S6 = harvest, reflecting that teardown runs before harvest to ensure harvest works against the final, stable repo state; failure paths re-enter at S5 rather than short-circuiting to S8 so S6/S7 always run — the per-IDEA log is the diagnostic artefact and must always be written, including for plan-rejected / verification-failed / bootstrap-failed outcomes)
