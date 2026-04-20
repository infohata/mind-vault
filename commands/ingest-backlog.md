---
description: Brownfield-takeover helper — atomise a monolithic backlog document (IDEAS.md / BACKLOG.md / ROADMAP.md / TODO.md / FEATURES.md) into per-idea docs/ideas/IDEA-NNN-<slug>.md files; regenerate the index; default dry-run
agent: general
---

# ingest-backlog

Invoke the `ingest-backlog` skill to bootstrap a brownfield project for the mind-vault sprint workflow. One-pass, forward-only migration from a legacy monolithic backlog document to per-idea files under `docs/ideas/`.

Behaviour:

1. Locate the legacy source file (auto-detect common names/paths, or explicit path argument).
2. Parse entries using the recognised formats (teisutis-style H4 `#### IDEA-NNN:`, H3 variant, GitHub issue export, kanban task-list). Unknown formats surface a warning; contribute new shapes in `skills/ingest-backlog/references/legacy-formats.md`.
3. Classify entries: Active, Completed, Superseded.
4. **Default: dry-run.** Print the proposed file tree, per-entry frontmatter derivations, warnings, and proposed index — do NOT write.
5. With `--write`: require clean git working tree, emit one `docs/ideas/IDEA-NNN-<slug>.md` per Active/Superseded entry, regenerate `docs/ideas/README.md` grouped by priority, leave Completed entries as footer lines. Rewrite the source file as a short stub pointing at the new layout.
6. Idempotent on re-run: skip identical existing files, refuse on divergent, surface conflicts.

Forward-only: completed ideas never migrate into per-idea files — they stay as index footer lines so existing execution archives remain the canonical location.

Usage:

```text
/ingest-backlog                                  # dry-run against auto-detected file
/ingest-backlog docs/execution/IDEAS.md          # dry-run against explicit path
/ingest-backlog --write                          # destructive write after review
/ingest-backlog docs/BACKLOG.md --write          # destructive with explicit path
```

Does not commit — the user reviews the diff and commits by hand. Does not push.

See `skills/ingest-backlog/SKILL.md` for full pattern; `skills/ingest-backlog/references/legacy-formats.md` for format recognition.
