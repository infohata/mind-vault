---
description: Post-merge documentation + cleanup sweep — flip idea frontmatter to complete, re-sort the ideas index, append a devlog entry, tear down the worktree stack if one was in use, scan project docs for stale references. Runs between /work (merged PR) and /compound (learnings).
agent: general
---

# /wrap

Invoke the `wrap` skill to close the paper-trail + cleanup loop after a PR merges. Catches the documentation debt `/work` and `/bugbot-loop` were too focused on code to write, and reclaims the docker/disk/port resources the sprint was holding.

Behaviour:

1. Resolve the IDEA-NNN from the argument, branch name, or most recent merged PR.
2. Flip frontmatter in the archived `IDEA-NNN-<slug>.md` → `status: complete` + `completed: <merge-date>` (per `RULE_ideas-location-status` — frontmatter-only, no file move).
3. Re-sort `docs/ideas/README.md` — remove from **🚧 In Progress**, insert at the top of **✅ References — Implemented** with a 1–3 sentence shipping summary.
4. Append a top entry to the current month's `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md` covering *what shipped*, *infrastructure fixes landed in the same PR*, and *related links*.
5. **Teardown** (worktree sprints only): `docker compose down -v` → `git worktree remove` → `git branch -d`. Skip on primary checkout, skip when `WRAP_KEEP_STACK=1` / `--keep-stack` is set, refuse when the worktree has uncommitted changes.
6. Scan project docs (`docs/guides/`, `docs/reference/`, `docs/README.md`, top-level `README.md`, `AGENTS.md`, rules) for references to deleted / renamed identifiers, new env vars, new make targets, new settings surface — patch trivial hits, flag architectural ones as follow-ups.
7. Commit doc changes on the feature branch if still open, or a fresh `docs/idea-NNN-wrap` branch if it's already merged. Never pushes to main; never merges.

Usage:

```text
/wrap                   # auto-detects most recent merged PR
/wrap 118               # force IDEA-118
/wrap --keep-stack      # skip teardown (Step 5) — keep worktree + docker up
/wrap IDEA-118-centralize-attachment-type-registry
```

Called automatically by `/sprint-auto` in its post-merge reminder block — critical there because there's no human prompting after merge, and sprint-auto explicitly leaves worktrees up for morning review.

See `skills/wrap/SKILL.md` for the full six-step pattern, the teardown safety gates, and the downstream-docs-scan probe checklist.
