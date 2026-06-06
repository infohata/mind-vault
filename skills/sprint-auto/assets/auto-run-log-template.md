# Auto-run logs — two shapes

Two files get written per batch: one per-IDEA log (lives inside the IDEA's archive dir), and one batch summary (lives in the primary tree's `docs/archive/`). The per-IDEA log is the morning-review unit of work; the batch summary is the at-a-glance index.

______________________________________________________________________

## Per-IDEA log

Path: `<project>/docs/archive/YYYY-MM-idea-NNN-<slug>/auto-run-YYYY-MM-DD.md`

Written inside the worktree (which is where the archive dir lives for this run), committed to the `auto/<slug>` branch, so the PR carries the log into review automatically.

````markdown
---
idea: IDEA-NNN
slug: <slug>
run_started: 2026-04-20T22:14:03Z
run_finished: 2026-04-20T23:51:40Z
outcome: success          # success | review_clean | review_unresolved | plan_rejected | verification_failed | bootstrap_failed | budget_exceeded | aborted
pr_url: https://github.com/<owner>/<repo>/pull/<n>   # null if no PR opened
worktree_path: ~/projects/<project>-auto-<slug>
branch: auto/<slug>
port_offset: +15000

# Single per-IDEA review (state S6+S6a; runs over the WRAPPED PR — /wrap --scope=idea-only ran first at S5)
review_outcome: clean                  # clean | unresolved | budget_exceeded | skipped_no_pr | skipped_failure_pre_pr
review_escalation_attempts: 1          # integer 0-20; cap is 20 (covers code + docs) per escalation-policy.md
docs_review: folded_into_single_review_s6   # marker: the v3.x separate docs pass was retired (IDEA-015)

# v3.1 fields — verification routing + DB reset at IDEA entry
verification_location: ~/projects/<project>-auto-integration-<batch-iso>   # MUST be the integration worktree path (flag if otherwise)
db_reset_at_idea_entry: ok             # ok | failed
sprint_auto_integration_worktree: ~/projects/<project>-auto-integration-<batch-iso>

# (v3.2 removed the per-IDEA re-review pass S11.12 — no re_review_* fields are emitted.)

compound_candidates_queued:
  - type: recurrence
    category: "missing context-processor null-guard"
    notes: "same category surfaced in IDEA-050 earlier in batch"
docker_teardown: skipped_v3_no_per_idea_stack  # v3.1 always | v1 also: stopped | skipped_bootstrap_failure | skipped_work_crash
---

# sprint-auto run — IDEA-NNN <slug>

**Outcome**: ✅ PR opened at <pr_url> · review: clean (1 attempt, single pass over wrapped PR)

## Summary

<one paragraph — what shipped, single-review outcome, how many escalation cycles>

## Timeline

- 22:14:03Z — Worktree bootstrap started (tools/sprint-auto-bootstrap.sh)
- 22:14:47Z — Stack up (44s)
- 22:14:50Z — /plan invoked
- 22:18:12Z — Plan drafted, architect review started
- 22:21:05Z — Architect: ARCHITECTURALLY SOUND
- 22:21:10Z — /work invoked
- 22:48:33Z — Verification passed
- 22:51:40Z — PR opened at <pr_url>
- 22:51:45Z — /wrap --scope=idea-only started (state S5, BEFORE review) — frontmatter flip + downstream docs scan + eval-checklist emission (if auto_safe_with_eval_gate); devlog + ideas-index deferred to S11.7 batch wrap
- 22:51:55Z — wrap commit pushed (sha mno4567)
- 22:52:00Z — /<engine>-loop invoked (single pass over the WRAPPED PR, state S6)
- 22:58:12Z — review posted, 1 T2 finding (code)
- 22:58:45Z — Escalation attempt 1 (sha jkl0123) — added null-check (state S6a)
- 23:02:00Z — review re-triggered; ${ENGINE}_CLEAN_SIGNAL (code + docs)
- 23:11:30Z — S8 N/A in v3.1 (no per-IDEA stack); integration stack stays up for next IDEA
- 23:11:45Z — compound candidates harvested (1 recurrence; state S9)

## Commits (on auto/<slug>)

- `abc1234` — feat(ui): ...
- `def5678` — test(ui): ...
- `ghi9abc` — docs(archive): IDEA-NNN mark in-progress
- `jkl0123` — fix(ui): escalation attempt 1 — null-guard context-processor (review #M)
- `mno4567` — docs(archive): IDEA-NNN pre-merge documentation sweep

## Review-pass escalation attempts (cap: 20)

Single per-IDEA review pass over the wrapped PR (S6/S6a) — covers code + docs findings. (see [`references/escalation-policy.md`](../../skills/sprint-auto/references/escalation-policy.md))

| # | SHA | Approach | Review outcome |
|---|---|---|---|
| 1 | jkl0123 | null-guard in context-processor | clean |

## Diagnostic excerpt

<only populated on failure — last ~50 lines of relevant output:
  - plan_rejected → the architect's verdict section
  - verification_failed → tail of pytest / build output
  - bootstrap_failed → tail of tools/sprint-auto-bootstrap.sh stderr
  - review_unresolved → final attempt's diff + review's remaining finding
  - budget_exceeded → last activity before timeout>

## Cleanup

```bash
# Sprint-auto already stopped the containers; remaining chore after the
# [INTEGRATION] PR merges (frontmatter was flipped at S5):
/land --integration sprint-auto-<batch-iso>   # tears down integration worktree + branch + every per-IDEA worktree/branch
````

Manual cleanup (if not running `/land`):

```bash
cd ~/projects/<project>-auto-<slug>
docker compose down -v          # -v removes volumes
cd -
git worktree remove ~/projects/<project>-auto-<slug>
git branch -D auto/<slug>        # only after PR merged or explicitly abandoned
```

````

## Batch summary

Path: `<project>/docs/archive/auto-run-<ISO-timestamp>-summary.md`

Written to the **primary checkout**, not a worktree. Committed on a throwaway branch or left uncommitted (batch runs shouldn't muddy main's history automatically — the human decides whether to commit the summary).

```markdown
---
batch_started: 2026-04-20T22:14:03Z
batch_finished: 2026-04-21T05:17:55Z
invocation: "/sprint-auto IDEA-050 IDEA-051 IDEA-052 IDEA-053"
batch_budget_minutes: 1380          # len(ideas) * 300 default + 180 integration = 1380; --budget-minutes overrides
ideas_attempted: 4
ideas_review_clean: 1
ideas_review_unresolved: 1
ideas_failed_pre_pr: 2
batch_aborted: false
compound_prs_opened: 2
compound_prs_review_clean: 1
compound_prs_review_unresolved: 1

# v3.1 integration phase (states S(-1) + S11.5–S11.13)
integration_branch: integration/sprint-auto-2026-04-20T22-14-03Z
integration_worktree_path: ~/projects/<project>-auto-integration-2026-04-20T22-14-03Z
integration_draft_pr_url: https://github.com/<owner>/<repo>/pull/<int-pr>   # auto-closed at S11.13
integration_outcome: clean          # clean | with_flags | bootstrap_failed | aborted
union_test_outcome: clean           # clean | unresolved | cap_exceeded
full_suite_outcome: clean           # clean | unresolved | cap_exceeded
integration_review_outcome: clean   # clean | unresolved | budget_exceeded
integration_review_attempts: 3      # integer 0-20; cap is 20 (elephants — deliverables-class)
integration_teardown: stopped_clean # stopped_clean | teardown_failed
---

# sprint-auto batch — 2026-04-20 overnight run

Invocation: `/sprint-auto IDEA-050 IDEA-051 IDEA-052 IDEA-053`

## IDEA results (project PRs)

Escalation column shows per-IDEA review attempts against cap `20`.

| IDEA | Slug | Outcome | PR | Review (single pass) | Escalation | Worktree |
|---|---|---|---|---|---|---|
| 050 | sync-retry-backoff | ✅ PR open | #123 | clean | 0 | `../<project>-auto-sync-retry-backoff` (code-surface only; nothing to tear down) |
| 051 | modal-dismiss-focus | ⚠️ PR open, review unresolved | #124 | 2 T3 remaining | 20 (review cap hit) | `../<project>-auto-modal-dismiss-focus` (code-surface only) |
| 052 | alpine-event-bus | ⚠️ plan REJECTED | — | skipped (no PR) | — | `../<project>-auto-alpine-event-bus` (code-surface only) |
| 053 | cache-invalidation | ❌ verification fail | — | skipped (no PR) | — | `../<project>-auto-cache-invalidation` (code-surface only) |

## Integration check (states S11.5–S11.13)

Validates the integrated state of all `auto/<slug>` PRs that reached integration phase. Single docker stack at port offset `+30000` on the integration worktree. See `references/integration-stage.md` for full mechanics.

### Sequential merge results (S11.6)

| Branch | Outcome | Conflict files (if any) | Resolution SHA |
|---|---|---|---|
| `auto/sync-retry-backoff` | ✅ clean | — | — |
| `auto/modal-dismiss-focus` | ⚠️ resolved | `web/templates/chat.html`, `web/locale/en/django.po` | `r1a2b3c` |

### Tests on integrated state (S11.8 + S11.9)

- **Union of per-IDEA target tests** (S11.8): ✅ 414 passed (cap 10; 0 escalation attempts)
- **Full suite** (S11.9): ✅ 1247 passed (cap 10; 0 escalation attempts)

### Review via [INTEGRATION] PR (S11.10)

- **[INTEGRATION] PR**: [#1234](https://github.com/.../pull/1234) (non-draft; left OPEN at S11.13 as the merge gate — the human merges it, and the per-IDEA PRs auto-close as merged ancestors)
- **Outcome**: ✅ clean (3 attempts; cap 20)
- **Findings**: 3 T2 fixed on integration branch, 0 T3 unresolved

## Compound (mind-vault PRs)

Escalation cap for mind-vault compound PRs is 5 (doc-class convergence — compound PRs are documentation by nature).

| Destination | PR | Review | Escalation | Branch |
|---|---|---|---|---|
| `skills/<owner>/references/<topic>.md` (placeholder example) | https://github.com/.../pull/78 | clean | 0/5 | `compound/2026-04-20-<topic>` |
| `AGENT_architect.md` pass-2 addendum | https://github.com/.../pull/79 | 1 T3 remaining | 5/5 (cap hit) | `compound/2026-04-20-architect-pass-2-hoisting` |

## ✅ Merging — the [INTEGRATION] PR is the single merge gate

In v3.2 the per-IDEA PRs target the **integration branch**, not the parent. **Merge the one non-draft `[INTEGRATION]` PR (#1234)** — it ships the entire batch in one click, and the per-IDEA PRs (#123, #124) auto-close as merged ancestors. There is no "pick any PR / the rest collapse" step and no forward-sync — the per-IDEA PRs stay IDEA-isolated for review; the integration PR carries the integrated state.

**If you want to ship some IDEAs but defer others** (the escalation case — rare, but real):

- **(a) Surgical revert on the integration branch (cleanest).** `git revert` the unwanted IDEA's commits on the integration branch, push, let the [INTEGRATION] PR re-review, then merge it. The deferred IDEA's per-IDEA PR stays open against integration for a later batch.
- **(b) Close-and-rerun.** `gh pr close` the [INTEGRATION] PR, then re-run sprint-auto with only the IDEAs to ship. Re-runs the integration phase + review; ~30-60 min unattended.
- **(c) Accept atomic.** Merge the [INTEGRATION] PR whole, revert the unwanted IDEA as a post-merge follow-up PR. Only acceptable if the deferred IDEA is additive + low-risk; never for high-risk deferrals.

## Morning checklist

1. Review the per-IDEA PRs #123, #124 at their IDEA-isolated diffs (against the integration base), plus the **[INTEGRATION] PR #1234** for integration-state findings. IDEA-051 has an unresolved T3 finding (review cap hit at 20 attempts) — check the auto-run log's review-escalation table.
2. **Merge the [INTEGRATION] PR (#1234)** to ship the batch (per-IDEA PRs auto-close). Review + merge (or close) mind-vault compound PRs #78, #79 — PR #79 has an unresolved review finding (cap hit at 5); decide merge-anyway / fix-forward / close.
3. Read the per-IDEA log for IDEA-052 — architect's rejection is usually a plan-revision signal.
4. Read the per-IDEA log for IDEA-053 — check which test failed; decide fix-forward / plan revision.
5. After merging the [INTEGRATION] PR: run **`/land --integration sprint-auto-<batch-iso>`** once from the primary tree — it tears down the integration worktree + branch + every per-IDEA `auto/<slug>` worktree/branch (see `skills/land/SKILL.md` § `--integration` mode). The per-IDEA frontmatter flips + downstream docs scans already ran at S5; the devlog batch entry + ideas-index batch update already ran at S11.7 on the integration branch.

## Per-IDEA logs

- [IDEA-050 log](YYYY-MM-idea-050-sync-retry-backoff/auto-run-2026-04-20.md)
- [IDEA-051 log](YYYY-MM-idea-051-modal-dismiss-focus/auto-run-2026-04-20.md)
- [IDEA-052 log](YYYY-MM-idea-052-alpine-event-bus/auto-run-2026-04-20.md)
- [IDEA-053 log](YYYY-MM-idea-053-cache-invalidation/auto-run-2026-04-20.md)

## Environment snapshot

- Host: <hostname>
- Docker: `<docker version one-liner>`
- Git HEAD (primary): `<sha>` (`<message>`)
- Git HEAD (mind-vault): `<sha>` (`<message>`)
- Disk free at start: <GB>
- Disk free at end: <GB>
````
