# RULE_ideas-location-status

## Two locations, one move

An IDEA file lives in one of exactly two places across its whole life:

```text
docs/ideas/IDEA-NNN-<slug>.md                         → status: idea          (backlog, not started)
docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md
                                                      → status: in-progress
                                                      | status: complete
                                                      | status: superseded
                                                      | status: rejected
```

Only one move happens: **from `docs/ideas/` to `docs/archive/<dir>/` at the moment work starts** (`/plan` fires, or `/work` on small scopes that skip plan). After that, every status flip is a frontmatter edit — `in-progress → complete` is `completed: YYYY-MM-DD` in YAML, nothing on the filesystem.

`YYYY-MM` in the archive dir name = the month execution **started**. It doesn't change on completion. Stable identifier.

## Why not split in-progress out into its own tree

An earlier version of this rule had `docs/execution/IDEA-NNN-<slug>.md` as a mid-life location between `docs/ideas/` and `docs/archive/`. Dropped, because:

1. **Reference-link stability.** Every cross-reference written during active work (the plan doc linking to the IDEA, a research artefact linking to the plan, a `DEVELOPMENT_LOG` entry linking to session notes) has to resolve to the file's post-completion path, or every reference gets rewritten on merge. Making the start-of-work location = the end-of-life location means zero rewrites.
2. **Artefacts already want to be co-located.** Plans, research notes, session prompts, screenshots, PR-handoff docs — these all end up inside `docs/archive/YYYY-MM-idea-NNN-<slug>/` eventually. Landing the IDEA file there on day one gives active work a single dir to write into. The alternative forces cross-tree references during exactly the phase those references are being written.
3. **It matches what teisutis was already doing.** Archive dirs like `2026-04-idea-042/`, `2026-04-idea-088-content-indexing-phase2/` were created and populated while those ideas were in-progress, not retroactively. The convention was fighting the practice.

The word "archive" is a slight misnomer in this model — it's really "this idea's own directory, from first plan through shipping and beyond." But keeping the name keeps existing archive dirs compatible and the directory's purpose is clear in context.

## Lifecycle

```text
┌─────────────────────────────────────────────────────────────┐
│ docs/ideas/IDEA-NNN-<slug>.md                               │
│   status: idea                                              │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        │  /plan or /work fires →
                        │  mkdir docs/archive/YYYY-MM-idea-NNN-<slug>/
                        │  git mv IDEA file into it
                        │  update frontmatter: status: in-progress
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ docs/archive/YYYY-MM-idea-NNN-<slug>/                       │
│   ├── IDEA-NNN-<slug>.md                                    │
│   │     status: in-progress                                 │
│   ├── YYYY-MM-DD-<slug>-plan.md       (when /plan fires)    │
│   ├── research-*.md                   (during work)         │
│   ├── session-notes/                  (during work)         │
│   └── README.md                       (on completion)       │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        │  PR merges → just frontmatter edits:
                        │    status: complete
                        │    completed: YYYY-MM-DD
                        │
                        │  or (rejected path) → frontmatter edits:
                        │    status: superseded | rejected
                        │    superseded_by: NNN  (if known)
                        │
                        ▼
                 Same directory, same path. No file move.
```

## Transition mechanics

Only one filesystem transition exists:

```bash
# At /plan time (or /work time if plan is skipped):
mkdir -p docs/archive/YYYY-MM-idea-NNN-<slug>/
git mv docs/ideas/IDEA-NNN-<slug>.md \
       docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md
# Update frontmatter: status: in-progress
# Update docs/ideas/README.md: move entry from priority section to In-Progress section
# All in one commit.
```

Every subsequent status change is a **frontmatter edit only**, plus an index-line update:

```yaml
# On merge
status: complete
completed: 2026-04-22
```

```yaml
# On rejection during /compound
status: rejected
# optionally superseded_by: 123
```

No `git mv` on the second transition. That's the whole point.

### Never-started ideas that get rejected

An IDEA in `docs/ideas/` that never becomes work (superseded by a better idea, or explicitly rejected) still moves to archive — it's leaving the backlog:

```bash
mkdir -p docs/archive/YYYY-MM-idea-NNN-<slug>/
git mv docs/ideas/IDEA-NNN-<slug>.md \
       docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md
# Update frontmatter: status: superseded | rejected
# + superseded_by: NNN (if known)
```

`YYYY-MM` in this case = month of rejection. Same move, same commit.

## Chronological logs — `DEVELOPMENT_LOG`

Project-wide chronological engineering logs (`DEVELOPMENT_LOG.md`, release notes) follow a **per-month file** convention inside `docs/archive/`:

```text
docs/archive/2026-01-DEVELOPMENT_LOG.md    # frozen
docs/archive/2026-02-DEVELOPMENT_LOG.md    # frozen
docs/archive/2026-03-DEVELOPMENT_LOG.md    # frozen
docs/archive/2026-04-DEVELOPMENT_LOG.md    # current month — being written to now
```

- New entries on 2026-04-22 go into `docs/archive/2026-04-DEVELOPMENT_LOG.md`.
- First new entry on 2026-05-01 creates `docs/archive/2026-05-DEVELOPMENT_LOG.md` and starts writing there. No rollover ritual — the new month means a new file, that's it.
- No "active" copy in `docs/execution/`. There is no `docs/execution/` in this model.
- Per-file size bounded to ~one month of entries (typically 1000-2000 lines). Grep across months when you need full-project history: `grep -l IDEA-042 docs/archive/*-DEVELOPMENT_LOG.md`.

Why the monthly split matters: merged, the log would be five-thousand-plus lines and only growing. Per-month files are each individually tractable, grep-friendly, and naturally bounded by a cut point everyone already understands.

## `docs/execution/` does not exist in this model

The dir was in an earlier draft of this rule. It's gone. Two dirs:

- `docs/ideas/` — backlog
- `docs/archive/` — everything else (active-idea dirs, completed-idea dirs, monthly logs, historical epic dirs)

Projects adopting this rule retire any existing `docs/execution/` directory during takeover — move its current contents to appropriate archive locations (per-IDEA archive dirs for in-progress work, monthly-log files for chronological logs) and `rmdir`. See the teisutis IDEA-112 takeover for the worked example.

## Index maintenance — `docs/ideas/README.md`

The single index lives at `docs/ideas/README.md` regardless of where individual IDEA files live. Entries link *out* to `../archive/<dir>/` when the file has left the backlog.

Skeleton:

```markdown
# <Project> Ideas Index

_Two locations per RULE_ideas-location-status: `docs/ideas/` = backlog;
`docs/archive/YYYY-MM-idea-NNN-<slug>/` = everything that's left backlog,
differentiated by frontmatter `status:`._

## 🚧 In Progress

- [IDEA-042](../archive/2026-04-idea-042/IDEA-042-test-suite-defragilization.md) ⏳ — Test Suite Defragilization

## 💡 High Priority (backlog)

- [IDEA-080](IDEA-080-phased-django-reversion-rollout.md) — Phased django-reversion rollout

## 💡 Medium Priority (backlog)

- [IDEA-112](IDEA-112-split-ideas-md-per-idea-files.md) — Split IDEAS.md into per-idea files

## 💡 Low Priority (backlog)

_(none)_

## 🗃 Superseded / Rejected (archive)

- [IDEA-109](../archive/2026-04-idea-109-replace-stt-browser-native/IDEA-109-replace-google-cloud-stt-browser-native.md) [superseded] — Replace Google Cloud STT
- [IDEA-017](../archive/2026-04-idea-017-remote-staging/IDEA-017-remote-staging-environment-setup.md) [rejected] — Remote Staging Environment Setup

## ✅ References — Implemented

### IDEA-NNN: Title ✅ COMPLETE
**Status**: ✅ **COMPLETE** · **Completed**: YYYY-MM-DD · **See**: [Archive](../archive/YYYY-MM-idea-NNN-<slug>/)
One-line summary.
```

Grouping rules (all read frontmatter; location is filtered by status):

- **🚧 In Progress** — `docs/archive/*/IDEA-*.md` where `status: in-progress`.
- **💡 Priority groupings** — `docs/ideas/IDEA-*.md` (status: idea, grouped by priority).
- **🗃 Superseded / Rejected** — `docs/archive/*/IDEA-*.md` where `status: superseded | rejected`.
- **✅ References — Implemented** — `docs/archive/*/IDEA-*.md` where `status: complete`. Footer lines pointing at the archive dir, not the IDEA file itself (archive dir's own README is the canonical landing for a completed idea's full story).

Rebuild the index from scratch when out of sync: scan both dirs, read each file's frontmatter, regenerate.

## Hard rules

1. **Never** create an IDEA file outside `docs/ideas/` or `docs/archive/YYYY-MM-idea-NNN-<slug>/`. No `docs/execution/`, no `docs/in-progress/`, no flat `docs/planning/`.
2. **Never** let frontmatter and location disagree. If you find `docs/ideas/*.md` with `status: complete`, fix it — treat as an incident.
3. **Never** rename the slug during a status transition. The slug is the idea's stable identity.
4. **Always** `git mv` (not copy+delete) so blame survives.
5. **Always** update `docs/ideas/README.md` in the same commit as the move.
6. **Never** move the archive dir once created. `YYYY-MM` is stamped at creation time and stays. The dir holds its history.

## Exceptions

- **Forward-only policy for brownfield ingests.** When `/ingest-backlog` runs against a legacy monolithic backlog file, already-completed entries are NOT back-migrated into archive dirs as new files. They stay as footer lines in the index. Each completed idea's canonical history is its pre-existing execution archive dir. Creating a new idea file retroactively is pure data migration with no gain.
- **Ideas without IDEA-NNN numbers.** Some brownfield legacy entries never got a number (e.g. "Test Coverage Visualization"). Those stay as footer-only lines in the index under a "Rejected — footer only" section; no file is created.

## Relationship to other rules

- [`RULE_git-safety.md`](RULE_git-safety.md) — single-move commits live on feature branches; `git mv` respects blame.
- [`skills/idea/SKILL.md`](../skills/idea/SKILL.md) — owns creation in `docs/ideas/`; globs both dirs when auto-incrementing IDEA numbers.
- [`skills/plan/SKILL.md`](../skills/plan/SKILL.md) — triggers the single `idea` → archive move; emits the plan file INTO the new archive dir (not a separate `docs/plans/` tree).
- [`skills/work/SKILL.md`](../skills/work/SKILL.md) — on PR merge, updates frontmatter only by default (`status: complete`, `completed: <date>`). Triggers the `idea` → archive fallback move when `/plan` was bypassed and the source file is still in `docs/ideas/` (small-scope `/idea` → `/work` shortcut).
- [`skills/compound/SKILL.md`](../skills/compound/SKILL.md) — may trigger `idea` → archive move directly when post-incident routing classifies an idea as superseded or rejected before any execution started.
- [`skills/ingest-backlog/SKILL.md`](../skills/ingest-backlog/SKILL.md) — emits files to both dirs per this rule during brownfield takeover; retires any existing `docs/execution/` tree as part of the write step.

---

**Last Updated**: 2026-04-20
