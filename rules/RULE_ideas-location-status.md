# RULE_ideas-location-status

## Location encodes status for per-idea files

One hard rule: **the directory an IDEA file lives in is authoritative about its status**. Frontmatter and filesystem location must agree — if they diverge, location wins (a human can see the tree; the YAML is only visible when the file is opened).

```text
docs/ideas/IDEA-NNN-<slug>.md                         → status: idea          (backlog)
docs/execution/IDEA-NNN-<slug>.md                     → status: in-progress   (active work)
docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md
                                                      → status: complete
                                                      | status: superseded
                                                      | status: rejected
```

The file's **slug is stable across its whole lifecycle**. Only its directory changes. Cross-references keep resolving via grep on the slug, and git history follows the file through `git mv` without breaking blame.

## Why the split (not all under `docs/ideas/`)

A single pool mixes three audiences:

- **Backlog curators** want a clean list of candidates — they don't want `status: in-progress` or `status: complete` noise.
- **Executors in flight** want the live plan and artefacts co-located with the idea (`DEVELOPMENT_LOG.md`, research notes, session artefacts, screenshots) — `docs/execution/` is where that context already lives.
- **Historians** want execution history immutable in `docs/archive/YYYY-MM-<dir>/` alongside the plan and any PR handoffs, which is where teisutis (and similar projects) already put completed epics.

Splitting by status removes the tax of filtering a mixed pool and matches where the other artefacts of each lifecycle stage already want to be.

## Transition mechanics

Every status transition is **a `git mv` plus a frontmatter update**, done in the same commit. The skills own these moves — humans should not hand-move files.

### `idea` → `in-progress`

Owned by `/plan` (when a plan gets drafted) or `/work` (when execution starts without a separate plan — small scopes).

```bash
git mv docs/ideas/IDEA-NNN-<slug>.md docs/execution/IDEA-NNN-<slug>.md
# + update frontmatter: status: in-progress
```

The IDEA file now lives alongside `docs/execution/DEVELOPMENT_LOG.md`, any plan doc, research artefacts, session notes — everything an executor will touch.

### `in-progress` → `complete` | `superseded` | `rejected`

Owned by `/work` (on completion) or `/compound` (on rejection / supersession during post-incident routing).

```bash
# The archive dir is either pre-existing (typical for completed work with
# artefacts already gathered there) or newly created:
mkdir -p docs/archive/YYYY-MM-idea-NNN-<slug>/
git mv docs/execution/IDEA-NNN-<slug>.md docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md
# + update frontmatter: status: complete | superseded | rejected
# + update frontmatter: completed: YYYY-MM-DD (when status=complete)
# + update frontmatter: superseded_by: <id> (when status=superseded and the pointer is known)
```

`YYYY-MM` is the month of completion / rejection, not the month of creation — matches the existing archive-dir convention.

### `idea` → `superseded` | `rejected` (never went in-progress)

Direct to archive, skipping execution:

```bash
mkdir -p docs/archive/YYYY-MM-idea-NNN-<slug>/
git mv docs/ideas/IDEA-NNN-<slug>.md docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md
# + update frontmatter: status + superseded_by (if known)
```

## Index maintenance — `docs/ideas/README.md`

The single index lives at `docs/ideas/README.md` regardless of where individual files physically live. Entries link *out* to `../execution/` or `../archive/<dir>/` when the file is not in the ideas directory.

Skeleton:

```markdown
# <Project> Ideas Index

_Location = status convention: see RULE_ideas-location-status._

## 🚧 In Progress

- [IDEA-042](../execution/IDEA-042-test-suite-defragilization.md) ⏳ — Test Suite Defragilization

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

Grouping rules:

- **In Progress** pulls from `docs/execution/IDEA-*.md`.
- **Priority groupings** pull from `docs/ideas/IDEA-*.md`.
- **Superseded / Rejected** pulls from `docs/archive/*/IDEA-*.md` where frontmatter says `status: superseded | rejected`.
- **References — Implemented** keeps completed footer lines (slug + completion date + archive link). Forward-only: the backlog index doesn't link to the migrated idea file itself; the archive dir is the canonical landing.

## Hard rules

1. **Never** create an IDEA file outside these three locations. No `docs/in-progress/`, no `docs/ideas/in-progress/`, no flat `docs/planning/`.
2. **Never** let frontmatter and location disagree. If you find a file in `docs/ideas/` with `status: complete`, fix one or the other — treat as an incident.
3. **Never** rename the slug during a status transition. The slug is the idea's stable identity.
4. **Always** `git mv` (not copy+delete) so blame survives.
5. **Always** update the index in the same commit as the move.

## Exceptions

- **Forward-only policy for brownfield ingests.** When `/ingest-backlog` runs against a legacy monolithic backlog file, already-completed entries are NOT back-migrated into archive dirs as new files. They stay as footer lines in the index. The canonical location for each completed idea's history is the execution archive dir that already exists. Creating a new idea file retroactively in each archive dir is pure data migration with no gain.
- **Ideas without IDEA-NNN numbers.** Some brownfield legacy entries never got a number (e.g. "Test Coverage Visualization"). Those stay as footer-only lines in the index under a "Rejected — footer only" section; no file is created.

## Relationship to other rules

- [`RULE_git-safety.md`](RULE_git-safety.md) — status-transition commits live on feature branches; never edit files in `docs/archive/` directly on `main`.
- [`skills/idea/SKILL.md`](../skills/idea/SKILL.md) — owns `idea` status; moves to `in-progress` on plan creation handoff.
- [`skills/plan/SKILL.md`](../skills/plan/SKILL.md) — triggers the `idea` → `in-progress` move.
- [`skills/work/SKILL.md`](../skills/work/SKILL.md) — triggers the `in-progress` → `complete` move on PR merge.
- [`skills/compound/SKILL.md`](../skills/compound/SKILL.md) — triggers moves to `superseded` / `rejected` when post-incident routing determines an idea is no longer pursuable.
- [`skills/ingest-backlog/SKILL.md`](../skills/ingest-backlog/SKILL.md) — emits files to the three destinations per this rule during brownfield takeover.

---

**Last Updated**: 2026-04-20 (captured from teisutis IDEA-112 PR1 — the first brownfield ingest that validated the three-location split against a real 1700-line monolithic backlog)
