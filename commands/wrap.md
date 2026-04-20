---
description: Post-merge documentation sweep — flip idea frontmatter to complete, re-sort the ideas index, append a devlog entry, scan project docs for stale references. Runs between /work (merged PR) and /compound (learnings).
agent: general
---

# /wrap

Invoke the `wrap` skill to close the paper-trail loop after a PR merges. Catches the documentation debt `/work` and `/bugbot-loop` were too focused on code to write.

Behaviour:

1. Resolve the IDEA-NNN from the argument, branch name, or most recent merged PR.
2. Flip frontmatter in the archived `IDEA-NNN-<slug>.md` → `status: complete` + `completed: <merge-date>` (per `RULE_ideas-location-status` — frontmatter-only, no file move).
3. Re-sort `docs/ideas/README.md` — remove from **🚧 In Progress**, insert at the top of **✅ References — Implemented** with a 1–3 sentence shipping summary.
4. Append a top entry to the current month's `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md` covering *what shipped*, *infrastructure fixes landed in the same PR*, and *related links*.
5. Scan project docs (`docs/guides/`, `docs/reference/`, `docs/README.md`, top-level `README.md`, `AGENTS.md`, rules) for references to deleted / renamed identifiers, new env vars, new make targets, new settings surface — patch trivial hits, flag architectural ones as follow-ups.
6. Commit on the feature branch if still open, or a fresh `docs/idea-NNN-wrap` branch if it's already merged. Never pushes to main; never merges.

Usage:

```text
/wrap                   # auto-detects most recent merged PR
/wrap 118               # force IDEA-118
/wrap IDEA-118-centralize-attachment-type-registry
```

Called automatically by `/sprint-auto` between `/bugbot-loop` and `/compound` in the unattended orchestrator — critical there because there's no human prompting after merge.

See `skills/wrap/SKILL.md` for the full five-step pattern and the downstream-docs-scan probe checklist.
