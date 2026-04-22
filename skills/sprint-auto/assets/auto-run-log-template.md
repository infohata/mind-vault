# Auto-run logs — two shapes

Two files get written per batch: one per-IDEA log (lives inside the IDEA's archive dir), and one batch summary (lives in the primary tree's `docs/archive/`). The per-IDEA log is the morning-review unit of work; the batch summary is the at-a-glance index.

---

## Per-IDEA log

Path: `<project>/docs/archive/YYYY-MM-idea-NNN-<slug>/auto-run-YYYY-MM-DD.md`

Written inside the worktree (which is where the archive dir lives for this run), committed to the `auto/<slug>` branch, so the PR carries the log into review automatically.

```markdown
---
idea: IDEA-NNN
slug: <slug>
run_started: 2026-04-20T22:14:03Z
run_finished: 2026-04-20T23:51:40Z
outcome: success          # success | bugbot_clean | bugbot_unresolved | plan_rejected | verification_failed | bootstrap_failed | budget_exceeded | aborted
pr_url: https://github.com/<owner>/<repo>/pull/<n>   # null if no PR opened
worktree_path: ~/projects/<project>-auto-<slug>
branch: auto/<slug>
port_offset: +15000

# Deliverables-pass bugbot (state S3+S4 in post-pr-sequence.md)
deliverables_bugbot_outcome: clean     # clean | unresolved | budget_exceeded | skipped_no_pr
deliverables_escalation_attempts: 1    # integer 0-20; cap is 20 per escalation-policy.md

# Docs-pass bugbot (state S6+S7; runs after /wrap-docs commits docs to the same branch)
docs_bugbot_outcome: clean             # clean | unresolved | budget_exceeded | skipped_no_pr | skipped_failure_pre_pr
docs_escalation_attempts: 0            # integer 0-5; cap is 5 per escalation-policy.md

compound_candidates_queued:
  - type: recurrence
    category: "missing context-processor null-guard"
    notes: "same category surfaced in IDEA-050 earlier in batch"
docker_teardown: stopped               # stopped | skipped_bootstrap_failure | skipped_work_crash
---

# sprint-auto run — IDEA-NNN <slug>

**Outcome**: ✅ PR opened at <pr_url> · bugbot: deliverables clean (1 attempt) / docs clean (0 attempts)

## Summary

<one paragraph — what shipped, bugbot outcome on each pass, how many escalation cycles per pass>

## Timeline

- 22:14:03Z — Worktree bootstrap started (tools/sprint-auto-bootstrap.sh)
- 22:14:47Z — Stack up (44s)
- 22:14:50Z — /plan invoked
- 22:18:12Z — Plan drafted, architect review started
- 22:21:05Z — Architect: ARCHITECTURALLY SOUND
- 22:21:10Z — /work invoked
- 22:48:33Z — Verification passed
- 22:51:40Z — PR opened at <pr_url>
- 22:51:45Z — /bugbot-loop invoked (deliverables pass, state S3)
- 22:58:12Z — bugbot posted review, 1 T2 finding
- 22:58:45Z — Deliverables escalation attempt 1 (sha jkl0123) — added null-check
- 23:02:00Z — bugbot re-triggered; BUGBOT_CLEAN_SIGNAL on deliverables pass
- 23:02:10Z — /wrap-docs started (state S5) — devlog entry + downstream docs scan
- 23:04:30Z — docs commit pushed (sha mno4567)
- 23:04:35Z — /bugbot-loop invoked (docs pass, state S6)
- 23:11:20Z — BUGBOT_CLEAN_SIGNAL on docs pass
- 23:11:30Z — docker compose down (containers stopped, volumes kept; state S8)
- 23:11:45Z — compound candidates harvested (1 recurrence; state S9)

## Commits (on auto/<slug>)

- `abc1234` — feat(ui): ...
- `def5678` — test(ui): ...
- `ghi9abc` — docs(archive): IDEA-NNN mark in-progress
- `jkl0123` — fix(ui): escalation attempt 1 — null-guard context-processor (bugbot #M)
- `mno4567` — docs(archive): IDEA-NNN pre-merge documentation sweep

## Deliverables-pass escalation attempts (cap: 20)

(see [`references/escalation-policy.md`](../../skills/sprint-auto/references/escalation-policy.md))

| # | SHA | Approach | Bugbot outcome |
|---|---|---|---|
| 1 | jkl0123 | null-guard in context-processor | clean |

## Docs-pass escalation attempts (cap: 5)

| # | SHA | Approach | Bugbot outcome |
|---|---|---|---|
| — | — | (no escalation needed — clean on first bugbot pass after /wrap-docs) | — |

## Diagnostic excerpt

<only populated on failure — last ~50 lines of relevant output:
  - plan_rejected → the architect's verdict section
  - verification_failed → tail of pytest / build output
  - bootstrap_failed → tail of tools/sprint-auto-bootstrap.sh stderr
  - bugbot_unresolved → final attempt's diff + bugbot's remaining finding
  - budget_exceeded → last activity before timeout>

## Cleanup

```bash
# Sprint-auto already stopped the containers; remaining chore after merge:
/wrap NNN     # flips frontmatter to complete, removes volumes, removes worktree
```

Manual cleanup (if not running `/wrap`):

```bash
cd ~/projects/<project>-auto-<slug>
docker compose down -v          # -v removes volumes
cd -
git worktree remove ~/projects/<project>-auto-<slug>
git branch -D auto/<slug>        # only after PR merged or explicitly abandoned
```
```

## Batch summary

Path: `<project>/docs/archive/auto-run-<ISO-timestamp>-summary.md`

Written to the **primary checkout**, not a worktree. Committed on a throwaway branch or left uncommitted (batch runs shouldn't muddy main's history automatically — the human decides whether to commit the summary).

```markdown
---
batch_started: 2026-04-20T22:14:03Z
batch_finished: 2026-04-21T05:17:55Z
invocation: "/sprint-auto IDEA-050 IDEA-051 IDEA-052 IDEA-053"
batch_budget_minutes: 1200          # len(ideas) * 300 default; --budget-minutes overrides
ideas_attempted: 4
ideas_bugbot_clean: 1
ideas_bugbot_unresolved: 1
ideas_failed_pre_pr: 2
batch_aborted: false
compound_prs_opened: 2
compound_prs_bugbot_clean: 1
compound_prs_bugbot_unresolved: 1
---

# sprint-auto batch — 2026-04-20 overnight run

Invocation: `/sprint-auto IDEA-050 IDEA-051 IDEA-052 IDEA-053`

## IDEA results (project PRs)

Escalation column shows `deliverables/docs` attempts against caps `20/5`.

| IDEA | Slug | Outcome | PR | Deliverables bugbot | Docs bugbot | Escalation (D/d) | Worktree |
|---|---|---|---|---|---|---|---|
| 050 | sync-retry-backoff | ✅ PR open | #123 | clean | clean | 0/0 | `../<project>-auto-sync-retry-backoff` (stack down) |
| 051 | modal-dismiss-focus | ⚠️ PR open, bugbot unresolved | #124 | 2 T3 remaining | clean | 20/0 (deliverables cap hit) | `../<project>-auto-modal-dismiss-focus` (stack down) |
| 052 | alpine-event-bus | ⚠️ plan REJECTED | — | skipped (no PR) | skipped (no PR) | — | `../<project>-auto-alpine-event-bus` (stack down) |
| 053 | cache-invalidation | ❌ verification fail | — | skipped (no PR) | skipped (no PR) | — | `../<project>-auto-cache-invalidation` (stack down) |

## Compound (mind-vault PRs)

Escalation cap for mind-vault compound PRs is 5 (same as docs pass — compound PRs are documentation by nature).

| Destination | PR | Bugbot | Escalation | Branch |
|---|---|---|---|---|
| `skills/bugbot/references/null-guard-patterns.md` (new) | https://github.com/.../pull/78 | clean | 0/5 | `compound/2026-04-20-null-guard-patterns` |
| `AGENT_architect.md` pass-2 addendum | https://github.com/.../pull/79 | 1 T3 remaining | 5/5 (cap hit) | `compound/2026-04-20-architect-pass-2-hoisting` |

## Morning checklist

1. Review + merge (or request changes) on project PRs #123, #124. IDEA-051 has an unresolved T3 finding on deliverables (cap hit at 20 attempts) — check the auto-run log's deliverables-pass table to see what sprint-auto tried.
2. Review + merge (or close) mind-vault PRs #78, #79. PR #79 has an unresolved bugbot finding (cap hit at 5); decide merge-anyway / fix-forward / close.
3. Read the per-IDEA log for IDEA-052 — architect's rejection is usually a plan-revision signal.
4. Read the per-IDEA log for IDEA-053 — check which test failed; decide fix-forward / plan revision.
5. For each PR merged: run `/wrap NNN` to finalise (frontmatter flip to complete, volumes removed, worktree removed). The pre-merge docs work (devlog entry + downstream docs scan) already ran at each IDEA's state S5, so `/wrap NNN` post-merge is cleanup + frontmatter tail.

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
```

---

**Last Updated**: 2026-04-22 (split deliverables_bugbot_outcome / docs_bugbot_outcome, split escalation_attempts lists with per-pass caps 20/5, new timeline includes S5 /wrap-docs + S6 docs bugbot-pass events, batch table shows both passes side-by-side)
