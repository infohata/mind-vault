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
run_finished: 2026-04-20T22:51:40Z
outcome: success          # success | plan_rejected | verification_failed | bootstrap_failed | budget_exceeded | aborted
pr_url: https://github.com/<owner>/<repo>/pull/<n>   # null if no PR opened
worktree_path: ~/projects/<project>-auto-<slug>
branch: auto/<slug>
port_offset: +15000
---

# sprint-auto run — IDEA-NNN <slug>

**Outcome**: ✅ PR opened at <pr_url>

## Summary

<one paragraph — what shipped, or why it didn't>

## Timeline

- 22:14:03Z — Worktree bootstrap started (tools/sprint-auto-bootstrap.sh)
- 22:14:47Z — Stack up (44s)
- 22:14:50Z — /plan invoked
- 22:18:12Z — Plan drafted, architect review started
- 22:21:05Z — Architect: ARCHITECTURALLY SOUND
- 22:21:10Z — /work invoked
- 22:48:33Z — Verification passed
- 22:51:40Z — PR opened at <pr_url>

## Commits (on auto/<slug>)

- `abc1234` — feat(ui): ...
- `def5678` — test(ui): ...
- `ghi9abc` — docs(archive): IDEA-NNN mark in-progress

## Diagnostic excerpt

<only populated on failure — last ~50 lines of relevant output:
  - plan_rejected → the architect's verdict section
  - verification_failed → tail of pytest / build output
  - bootstrap_failed → tail of tools/sprint-auto-bootstrap.sh stderr
  - budget_exceeded → last activity before timeout>

## Cleanup

```bash
# Once you've reviewed + merged (or abandoned):
cd ~/projects/<project>-auto-<slug>
docker compose down -v          # -v removes volumes; drop -v to keep DB state for inspection
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
batch_finished: 2026-04-21T02:17:55Z
invocation: "/sprint-auto IDEA-050 IDEA-051 IDEA-052 IDEA-053"
batch_budget_minutes: 240
ideas_attempted: 4
ideas_succeeded: 2
ideas_failed: 2
batch_aborted: false
---

# sprint-auto batch — 2026-04-20 overnight run

Invocation: `/sprint-auto IDEA-050 IDEA-051 IDEA-052 IDEA-053`

## Results

| IDEA | Slug | Outcome | PR | Worktree |
|---|---|---|---|---|
| 050 | sync-retry-backoff | ✅ PR open | #123 | `../<project>-auto-sync-retry-backoff` |
| 051 | modal-dismiss-focus | ✅ PR open | #124 | `../<project>-auto-modal-dismiss-focus` |
| 052 | alpine-event-bus | ⚠️ plan REJECTED | — | `../<project>-auto-alpine-event-bus` |
| 053 | cache-invalidation | ❌ verification fail | — | `../<project>-auto-cache-invalidation` |

## Morning checklist

1. Review + merge (or request changes) on #123, #124.
2. Read the per-IDEA log for IDEA-052 — architect's rejection is usually a plan-revision signal, not a "this can't be done" signal.
3. Read the per-IDEA log for IDEA-053 — check which test failed; decide whether to fix-forward on the same worktree branch or route back through `/plan`.
4. Once done with each worktree, run the cleanup block from its auto-run log.

## Per-IDEA logs

- [IDEA-050 log](YYYY-MM-idea-050-sync-retry-backoff/auto-run-2026-04-20.md)
- [IDEA-051 log](YYYY-MM-idea-051-modal-dismiss-focus/auto-run-2026-04-20.md)
- [IDEA-052 log](YYYY-MM-idea-052-alpine-event-bus/auto-run-2026-04-20.md)
- [IDEA-053 log](YYYY-MM-idea-053-cache-invalidation/auto-run-2026-04-20.md)

## Environment snapshot

- Host: <hostname>
- Docker: `<docker version one-liner>`
- Git HEAD (primary): `<sha>` (`<message>`)
- Disk free at start: <GB>
- Disk free at end: <GB>
```

---

**Last Updated**: 2026-04-20 (initial)
