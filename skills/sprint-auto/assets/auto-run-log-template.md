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

# Docs-pass bugbot (state S6+S7; runs after /wrap --scope=idea-only commits docs to the same branch)
docs_bugbot_outcome: clean             # clean | unresolved | budget_exceeded | skipped_no_pr | skipped_failure_pre_pr
docs_escalation_attempts: 0            # integer 0-5; cap is 5 per escalation-policy.md

# v3.1 fields — verification routing + DB reset at IDEA entry
verification_location: ~/projects/<project>-auto-integration-<batch-iso>   # MUST be the integration worktree path (flag if otherwise)
db_reset_at_idea_entry: ok             # ok | failed
sprint_auto_integration_worktree: ~/projects/<project>-auto-integration-<batch-iso>

# v3.1 — re-bugbot pass after S11.11 forward-sync (state S11.12)
# Only present for IDEAs that reached integration phase; absent if pre-integration failure
re_bugbot_outcome: clean               # clean | unresolved | budget_exceeded | skipped_no_forward_sync
re_bugbot_attempts: 0                  # integer 0-5; cap is 5 per escalation-policy.md

compound_candidates_queued:
  - type: recurrence
    category: "missing context-processor null-guard"
    notes: "same category surfaced in IDEA-050 earlier in batch"
docker_teardown: skipped_v3_no_per_idea_stack  # v3.1 always | v1 also: stopped | skipped_bootstrap_failure | skipped_work_crash
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
- 23:11:30Z — S8 N/A in v3.1 (no per-IDEA stack); integration stack stays up for next IDEA
- 23:11:45Z — compound candidates harvested (1 recurrence; state S9)
# v3.1 only — re-bugbot pass timeline events appear after the integration phase (state S11.12)
# logged once the per-IDEA archive dir gets the post-batch update; the per-IDEA log itself is
# updated again post-S11.12 with the re-bugbot outcome.

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
| — | — | (no escalation needed — clean on first bugbot pass after /wrap --scope=idea-only) | — |

## Re-bugbot escalation attempts (cap: 5) — v3.1 only

(Populated post-S11.12. Empty if IDEA pre-integration failure or forward-sync skipped.)

| # | SHA | Approach | Bugbot outcome |
|---|---|---|---|
| — | — | (no re-bugbot escalation needed — clean on first pass after S11.11 forward-sync) | — |

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
batch_budget_minutes: 1380          # len(ideas) * 300 default + 180 integration = 1380; --budget-minutes overrides
ideas_attempted: 4
ideas_bugbot_clean: 1
ideas_bugbot_unresolved: 1
ideas_failed_pre_pr: 2
batch_aborted: false
compound_prs_opened: 2
compound_prs_bugbot_clean: 1
compound_prs_bugbot_unresolved: 1

# v3.1 integration phase (states S(-1) + S11.5–S11.13)
integration_branch: integration/sprint-auto-2026-04-20T22-14-03Z
integration_worktree_path: ~/projects/<project>-auto-integration-2026-04-20T22-14-03Z
integration_draft_pr_url: https://github.com/<owner>/<repo>/pull/<int-pr>   # auto-closed at S11.13
integration_outcome: clean          # clean | with_flags | bootstrap_failed | aborted
union_test_outcome: clean           # clean | unresolved | cap_exceeded
full_suite_outcome: clean           # clean | unresolved | cap_exceeded
integration_bugbot_outcome: clean   # clean | unresolved | budget_exceeded
integration_bugbot_attempts: 3      # integer 0-20; cap is 20 (elephants — deliverables-class)
integration_teardown: stopped_clean # stopped_clean | teardown_failed
---

# sprint-auto batch — 2026-04-20 overnight run

Invocation: `/sprint-auto IDEA-050 IDEA-051 IDEA-052 IDEA-053`

## IDEA results (project PRs)

Escalation column shows `deliverables/docs/re-bugbot` attempts against caps `20/5/5`. Re-bugbot only present if forward-sync (S11.11) ran for this IDEA; otherwise `—`.

| IDEA | Slug | Outcome | PR | Deliverables bugbot | Docs bugbot | Re-bugbot | Escalation (D/d/r) | Worktree |
|---|---|---|---|---|---|---|---|---|
| 050 | sync-retry-backoff | ✅ PR open | #123 | clean | clean | clean | 0/0/0 | `../<project>-auto-sync-retry-backoff` (code-surface only; nothing to tear down) |
| 051 | modal-dismiss-focus | ⚠️ PR open, bugbot unresolved | #124 | 2 T3 remaining | clean | clean | 20/0/0 (deliverables cap hit) | `../<project>-auto-modal-dismiss-focus` (code-surface only) |
| 052 | alpine-event-bus | ⚠️ plan REJECTED | — | skipped (no PR) | skipped (no PR) | — | — | `../<project>-auto-alpine-event-bus` (code-surface only) |
| 053 | cache-invalidation | ❌ verification fail | — | skipped (no PR) | skipped (no PR) | — | — | `../<project>-auto-cache-invalidation` (code-surface only) |

## Integration check — v3.1 only (states S11.5–S11.13)

Validates the integrated state of all `auto/<slug>` PRs that reached integration phase. Single docker stack at port offset `+30000` on the integration worktree. See `references/integration-stage.md` for full mechanics.

### Sequential merge results (S11.6)

| Branch | Outcome | Conflict files (if any) | Resolution SHA |
|---|---|---|---|
| `auto/sync-retry-backoff` | ✅ clean | — | — |
| `auto/modal-dismiss-focus` | ⚠️ resolved | `web/templates/chat.html`, `web/locale/en/django.po` | `r1a2b3c` |

### Tests on integrated state (S11.8 + S11.9)

- **Union of per-IDEA target tests** (S11.8): ✅ 414 passed (cap 10; 0 escalation attempts)
- **Full suite** (S11.9): ✅ 1247 passed (cap 10; 0 escalation attempts)

### Bugbot via [INTEGRATION] draft PR (S11.10)

- **Draft PR**: [#1234](https://github.com/.../pull/1234) (auto-closed at S11.13 without merge)
- **Outcome**: ✅ clean (3 attempts; cap 20)
- **Findings**: 2 T2 fixed on integration branch, 1 T2 fixed on integration branch, 0 T3 unresolved

### Forward-sync into per-PR PRs (S11.11)

| auto/<slug> branch | Forward-sync outcome | Merge SHA |
|---|---|---|
| `auto/sync-retry-backoff` | ✅ ok | `f7e8d9a` |
| `auto/modal-dismiss-focus` | ✅ ok | `b1c2d3e` |

### Re-bugbot per-PR PRs (S11.12)

(See per-IDEA `re_bugbot_outcome` and `re_bugbot_attempts` fields above for detail.)

| IDEA | Re-bugbot outcome | Attempts |
|---|---|---|
| 050 | ✅ clean | 0 |
| 051 | ✅ clean | 0 |

## Compound (mind-vault PRs)

Escalation cap for mind-vault compound PRs is 5 (same as docs pass — compound PRs are documentation by nature).

| Destination | PR | Bugbot | Escalation | Branch |
|---|---|---|---|---|
| `skills/bugbot/references/null-guard-patterns.md` (new) | https://github.com/.../pull/78 | clean | 0/5 | `compound/2026-04-20-null-guard-patterns` |
| `AGENT_architect.md` pass-2 addendum | https://github.com/.../pull/79 | 1 T3 remaining | 5/5 (cap hit) | `compound/2026-04-20-architect-pass-2-hoisting` |

## ⚠️ Co-dependent PRs — read before merging anything

This batch ran **forward-sync (S11.11)**, which means **every per-PR PR carries the entire batch's content** post-integration. Three things to know:

1. **The first merge brings the whole batch into main.** Whichever PR you merge first absorbs all other batch IDEAs via the integration commits. There is no "merge IDEA-050 only, defer IDEA-051" option from this point — that decision had to happen pre-batch (or the agent would have to `git revert` the unwanted IDEAs on the integration branch + re-forward-sync, which sprint-auto does not auto-do post-cap).
2. **Subsequent PRs' diffs collapse to zero after the first merge.** GitHub will report the second / third / Nth PR as having no diff against main — that's correct, not weird. Close them with a comment like "absorbed by #<first-merged-PR>"; there's nothing to merge.
3. **Pre-first-merge, all PRs show similarly-large diffs against OLD main.** GitHub diffs against the current base, which is still pre-batch. The size-label values for N PRs in the batch will all be ~the same combined-additions number; that's a UI artifact of co-dependence, not duplicated work.

If you want to ship only some IDEAs from this batch, **stop here** and either:
- (a) `gh pr close` the unwanted PRs FIRST, then re-run sprint-auto with just the wanted IDEAs (cleanest);
- (b) ask the agent to `git revert` the unwanted IDEAs on the integration branch + re-forward-sync (more surgical, more risk);
- (c) accept the atomic-batch outcome and merge any one PR (the simple case).

## Morning checklist

1. Review + merge (or request changes) on project PRs #123, #124. **Per the co-dependent-PRs note above, merge ONE PR; the others will auto-collapse to zero diff.** IDEA-051 has an unresolved T3 finding on deliverables (cap hit at 20 attempts) — check the auto-run log's deliverables-pass table to see what sprint-auto tried.
2. Review + merge (or close) mind-vault PRs #78, #79. PR #79 has an unresolved bugbot finding (cap hit at 5); decide merge-anyway / fix-forward / close.
3. Read the per-IDEA log for IDEA-052 — architect's rejection is usually a plan-revision signal.
4. Read the per-IDEA log for IDEA-053 — check which test failed; decide fix-forward / plan revision.
5. **v3.1**: Read the [INTEGRATION] PR's bugbot review (auto-closed; URL above) for any integration-state-only findings the morning reviewer should weigh.
6. For each PR merged: run `/wrap NNN` to finalise. v3.1's `/wrap NNN` post-merge:
   - Per-IDEA worktree teardown: just `git worktree remove` + `git branch -d` (no docker — there's no per-IDEA stack)
   - **Last-of-batch IDEA additionally**: `cd $integration_worktree && docker compose down -v && cd - && git worktree remove $integration_worktree && git branch -d integration/sprint-auto-<batch-iso>`
   The frontmatter flip + downstream docs scan already ran at S5; the devlog batch entry + ideas-index batch update already ran at S11.7 on the integration branch and propagated to each per-PR via S11.11 forward-sync.

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

**Last Updated**: 2026-04-29 (added "⚠️ Co-dependent PRs — read before merging anything" section above the morning checklist, explaining the three forward-sync consequences (first-merge atomicity, subsequent diffs collapse to zero, pre-first-merge UI all-large diffs) and the three options for shipping a subset of the batch. Morning checklist line 1 updated to call out "merge ONE PR; the others will auto-collapse to zero diff." Compounded from teisutis 2026-04-29 batch reviewer experience.)

**Previous**: 2026-04-27 (v3.1 — added Integration check section in batch summary covering S11.5–S11.13: sequential merge results, union/full test outcomes, [INTEGRATION] draft PR bugbot, forward-sync, re-bugbot per-PR. Per-IDEA log gains `verification_location`, `db_reset_at_idea_entry`, `sprint_auto_integration_worktree`, `re_bugbot_outcome`, `re_bugbot_attempts` fields. `docker_teardown` field default is now `skipped_v3_no_per_idea_stack`. Re-bugbot escalation table added per IDEA. Morning checklist updated for last-of-batch integration cleanup chore.)

**Previous**: 2026-04-22 (split deliverables_bugbot_outcome / docs_bugbot_outcome, split escalation_attempts lists with per-pass caps 20/5, new timeline includes S5 /wrap-docs + S6 docs bugbot-pass events, batch table shows both passes side-by-side)
