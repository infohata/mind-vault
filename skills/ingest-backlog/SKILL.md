---
name: ingest-backlog
description: Brownfield-takeover helper that atomises a monolithic backlog document (IDEAS.md, BACKLOG.md, ROADMAP.md, TODO.md, FEATURES.md, or similar) into per-idea `docs/ideas/IDEA-NNN-<slug>.md` files with structured YAML frontmatter, then regenerates a lightweight index. One-pass, forward-only, defaults to dry-run. Bootstraps a project for the mind-vault sprint workflow.
---

# ingest-backlog

One-time bootstrap helper. A brownfield project that already has a monolithic idea/backlog markdown document cannot cleanly adopt the sprint workflow's per-idea convention until every entry has its own file. This skill does that migration mechanically: scan the legacy document, emit one file per entry, regenerate a lightweight index, and leave completed entries as footer lines (forward-only policy).

This is not part of the sprint loop. Run it once per brownfield project, review the diff, commit.

## When to use

**TRIGGER when:**

- user says "ingest the backlog", "split IDEAS.md", "atomise the idea list", "convert BACKLOG.md into per-idea files", "bootstrap docs/ideas/"
- a project adopting the sprint workflow has a legacy monolithic backlog file and no existing `docs/ideas/` tree
- `/idea` refuses to create because it detected a legacy file — this skill is the routed follow-up

**SKIP when:**

- `docs/ideas/` already has files AND a legacy monolithic file also exists — mixed state. Abort and ask the user which source of truth wins before touching either.
- the legacy file is under 100 lines with fewer than ~5 entries — just ask the user to split it by hand; the skill is over-engineered for that.
- the user wants to capture a new idea — route to `/idea`.
- the user wants to plan an existing idea — route to `/plan`.

## Pattern

### 1. Locate the source file

Scan in this order; stop at the first hit. Ask the user for an explicit path if multiple candidates exist or nothing is found.

Search paths (relative to project root):

- `IDEAS.md`, `BACKLOG.md`, `ROADMAP.md`, `TODO.md`, `FEATURES.md`
- `docs/IDEAS.md`, `docs/BACKLOG.md`, ...
- `docs/execution/IDEAS.md`, `docs/execution/BACKLOG.md`, ...
- `docs/planning/IDEAS.md`, `docs/planning/BACKLOG.md`, ...

If the user supplies an explicit path, honour it regardless of filename. The skill is agnostic about where the source lives.

### 2. Detect the format

Parse the source, identifying one of the recognised shapes in [`references/legacy-formats.md`](references/legacy-formats.md). The canonical shape (teisutis-style) uses H4 entries:

```markdown
#### IDEA-NNN: Title
**Status**: 💡 Idea | 🔄 In Progress | ✅ COMPLETE
**Priority**: High | Medium | Low
**Depends on**: IDEA-XXX
**Related**: IDEA-YYY, IDEA-ZZZ
**Problem**: ...
```

Variants handled:

- H3 entries (`### IDEA-NNN: Title`).
- Completed-section promotion: in teisutis, completed ideas sit under `## Completed` / `## References — Implemented` using H3 headings with `✅ COMPLETE` suffix. These stay as footer lines in the regenerated index — they are NOT migrated into files.
- Numbering gaps: IDs are parsed as-is; holes are preserved.
- Missing fields: default to `status: idea`, `priority: medium`, empty relationship lists. Surface a warning per-entry.
- Prose-only entries without `**Status**:` markers: skill parses the heading + body, infers `status: idea`, surfaces in the dry-run summary for user review.

See [`references/legacy-formats.md`](references/legacy-formats.md) for the full recognition rules, field-inference heuristics, and de-duplication handling when the same IDEA id appears twice.

### 3. Classify entries

Walk the detected entries and classify per [`RULE_ideas-location-status`](../../rules/RULE_ideas-location-status.md). Two dirs, not three:

- **`status: idea`** → file lands in `docs/ideas/IDEA-NNN-<slug>.md`.
- **`status: in-progress`** → file lands in `docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md`. `YYYY-MM` = month execution started (inferred from the brownfield source or current month when undated). The IDEA lives inside the archive dir from the moment it left backlog; artefacts (plans, research, screenshots) get co-located there as work proceeds.
- **`status: superseded`** (with determinable pointer) → file lands in `docs/archive/YYYY-MM-idea-NNN-<slug>/`. If the supersession link is unclear, fall back to `status: idea` and surface a warning.
- **`status: rejected`** (from a `## ❌ Rejected` section or equivalent) → file lands in `docs/archive/YYYY-MM-idea-NNN-<slug>/`. Entries without an IDEA-NNN number stay as footer-only lines in the index (no file).
- **`status: complete`** → footer-line only in the index. **Forward-only**: no file created. Already-complete entries have an existing execution archive dir as their canonical home; a new stub file is pure data migration with no gain.

A brownfield source will typically have `🔄 Partially done` / `✅ Implemented` markers on entries whose H4 body is stale — the entry is actually complete. Per the stale-H4 heuristic in [`references/legacy-formats.md`](references/legacy-formats.md), reclassify to `complete` and drop the H4 body.

### 4. Dry-run preview (default mode)

Without `--write`, the skill emits a preview, never writes:

- Total entries found; count per classification (active / completed / superseded).
- Per-entry: proposed filename, derived slug, detected frontmatter fields, warnings (missing fields, inferred values, duplicate ids).
- Proposed index structure.
- Files that WOULD be written and WOULD be modified.

Print to stdout, exit cleanly. The user reviews, then re-invokes with `--write`.

### 5. Destructive write mode (`--write` flag)

Only when explicitly passed `--write`:

1. Require clean git working tree (`git status --porcelain` empty). Refuse with error otherwise.
2. `mkdir -p <project>/docs/ideas/`. Archive dirs are created on demand per entry.
3. For each entry, route to its destination per step 3's classification and [`RULE_ideas-location-status`](../../rules/RULE_ideas-location-status.md):
   - `status: idea` → `<project>/docs/ideas/IDEA-NNN-<slug>.md`.
   - `status: in-progress | superseded | rejected` → `<project>/docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md`. Create the archive dir. `YYYY-MM` = best-effort from the source's dates (execution start for in-progress, supersession/rejection date otherwise), falling back to the current month when undated.
   - `status: complete` → no file. Footer-line only in the index.
   - Each emitted file uses [`assets/idea-template.md`](assets/idea-template.md). Frontmatter derived from parsed fields; body transplanted from the source entry with minor normalisation (strip legacy emoji status prefixes, strip the bold-label fields now living in YAML, keep prose).
4. Write `<project>/docs/ideas/README.md` as the single index regardless of where individual files live. Skeleton per `RULE_ideas-location-status` — one In-Progress section (links into `../archive/<dir>/`), three priority sections (ideas in-place), a Superseded/Rejected section (archive files), a footer-only Rejected section (entries without IDEA-NNN), and a References — Implemented section preserving the legacy completed footer lines.
5. Rewrite the source monolithic file as a short stub pointing at `docs/ideas/README.md`. **The stub's relative links must be computed from the source file's directory to `<project>/docs/ideas/`, not hardcoded.** Step 1 supports source files at the repo root (`IDEAS.md`), under `docs/` (`docs/IDEAS.md`), or deeper (`docs/execution/IDEAS.md`, `docs/planning/IDEAS.md`); a hardcoded `../ideas/` path would break in most of those locations.

### 5a. Retire `docs/execution/` during the same write

If the source file was in `docs/execution/` AND that's the only remaining content in the dir (typical — `DEVELOPMENT_LOG.md` and any lingering agent-workflow docs are also retired during brownfield takeover per `RULE_ideas-location-status`), include the cleanup in the same write:

- Move `docs/execution/DEVELOPMENT_LOG.md` → `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md` (current month) via `git mv`. Subsequent log entries get written directly to the archive file.
- Move any other pre-sprint-workflow workflow docs (e.g. `agent_delegation_architecture.md`) to an appropriately-dated archive subdir — they're superseded by the sprint workflow adoption.
- Delete the stub created in step 5 if it was in `docs/execution/` — the entire dir is about to go — OR keep the stub as a breadcrumb for external bookmarks. Ask the user which.
- `rmdir docs/execution/` when empty.

Surface the cleanup plan in the dry-run so the user can approve before `--write`.

   Derivation rule (applied per-invocation):

   - `<SOURCE_DIR>` = directory containing the legacy source file, relative to repo root.
   - `<IDEAS_REL>` = relative path from `<SOURCE_DIR>` to `<project>/docs/ideas/`. Compute with `os.path.relpath(docs/ideas, SOURCE_DIR)` or equivalent.
   - `<INDEX_REL>` = `<IDEAS_REL>/README.md`.

   Worked examples:

   | Source file | `<IDEAS_REL>` | `<INDEX_REL>` |
   | --- | --- | --- |
   | `IDEAS.md` (repo root) | `docs/ideas/` | `docs/ideas/README.md` |
   | `docs/IDEAS.md` | `ideas/` | `ideas/README.md` |
   | `docs/execution/IDEAS.md` | `../ideas/` | `../ideas/README.md` |
   | `docs/planning/BACKLOG.md` | `../ideas/` | `../ideas/README.md` |

   Stub template (substitute `<IDEAS_REL>` + `<INDEX_REL>` + `<ORIGINAL_FILENAME>`):

   ```markdown
   # <ORIGINAL_FILENAME>

   This file was split into per-idea files under [`docs/ideas/`](<IDEAS_REL>).
   See [`docs/ideas/README.md`](<INDEX_REL>) for the index.

   _Original content preserved in git history — see commit that landed the split._
   ```

6. Print a summary: files created, index entries, any warnings. **Do not commit.** The user reviews the diff and commits by hand.

### 6. Forward-only policy (load-bearing)

Completed entries never get migrated into per-idea files, even if they have substantial body content. Rationale from teisutis IDEA-112:

- Completed ideas live in existing execution archive directories (`docs/archive/YYYY-MM-idea-NNN-<slug>/`) when they have rich history. That's the canonical location.
- Migrating a completed idea's body into a new file duplicates state and creates two sources of truth.
- The index's footer line + optional archive-directory link is enough for discoverability via grep.

If the user disagrees on a specific entry, they can hand-create the file post-ingest. Don't expand this skill's scope to handle it.

**Note**: superseded and rejected entries DO get files (in the archive tree), because they lack an existing archive dir. The forward-only carve-out is only for `status: complete`.

### 7. Slug derivation

- Lowercase the title, strip `IDEA-NNN:` prefix.
- Kebab-case on word boundaries.
- Strip stopwords (`a`, `the`, `for`, `into`, `of`, `on`, `in`).
- Truncate to ~40 chars at a word boundary.
- De-duplicate: if two entries would collide, append `-N` suffix to later ones.

### 8. Idempotency on re-run

A re-run after a partial previous ingest must check **both destination trees**, since step 5 can route an entry into either `docs/ideas/` (backlog) or `docs/archive/YYYY-MM-idea-NNN-<slug>/` (in-progress / superseded / rejected) per the classification in step 3. Checking only `docs/ideas/` would miss already-written archive-tree files and risk duplicate creation for non-backlog entries on the second pass.

For each proposed entry:

1. Glob both `<project>/docs/ideas/IDEA-NNN-<slug>.md` and `<project>/docs/archive/*/IDEA-NNN-<slug>.md`. Expect at most one hit if the prior run completed partially.
2. If a file is found:
   - Compare the existing file's frontmatter against the proposed one.
   - **If identical or existing is a superset:** skip the file, report "already present (at `<found-path>`)" in the summary.
   - **If divergent:** refuse to overwrite, report the conflict including the found path, and route the user to resolve manually. Do not silently stomp.
3. If no file is found, proceed with the normal step 5 write.

This makes re-runs safe when the legacy file has been edited since a prior ingest, and prevents duplicate-file creation for entries already promoted into the archive tree.

## Invocation

```text
/ingest-backlog                                  # dry-run against auto-detected file
/ingest-backlog docs/execution/IDEAS.md          # dry-run against explicit path
/ingest-backlog --write                          # destructive write after review
/ingest-backlog docs/BACKLOG.md --write          # destructive with explicit path
```

All modes end with a summary and next-step suggestions.

## When NOT to use these patterns

- **No legacy file exists.** Route to `/idea` for each new entry.
- **Mixed state — `docs/ideas/` already populated AND a monolithic file exists.** Refuse until the user decides which wins.
- **Small backlogs (< 5 entries).** Hand-split is faster and cleaner than running the skill.
- **Highly structured external backlogs (Jira, Linear export).** The skill targets markdown; structured JSON/CSV imports need a different tool.

## When running against teisutis specifically

Teisutis IDEA-112 is the first real consumer. Validation gate for this skill's v1:

- **Dry-run against teisutis `docs/execution/IDEAS.md` must complete cleanly** before merging this skill into mind-vault.
- Expected output: ~30+ active IDEA files proposed, ~50+ completed IDEAs as footer lines.
- Known edge cases in teisutis: IDEA-088 has `Phase 1 ✅ / Phase 2 ✅ / Phase 3 ✅` multi-phase completion — treat as one entry with `status: complete`. IDEA-042 has `Status: 🔄 Partially done` — treat as `status: in-progress`.
- Do **not** run `--write` against teisutis from mind-vault's `ce-inspired-evolution` branch. That execution happens in a teisutis worktree *after* this PR merges.

## References

- [assets/idea-template.md](assets/idea-template.md) — per-idea file template; same schema as `skills/idea/assets/idea-template.md`
- [references/legacy-formats.md](references/legacy-formats.md) — format recognition rules, variant handling, field inference heuristics
- [rules/RULE_ideas-location-status.md](../../rules/RULE_ideas-location-status.md) — location-by-status routing contract honoured by step 3 and step 5
- [docs/SPRINT_WORKFLOW.md](../../docs/SPRINT_WORKFLOW.md) — authoritative IDEA frontmatter schema
- [skills/idea/SKILL.md](../idea/SKILL.md) — the skill that consumes the per-idea format this one produces
- Origin: teisutis IDEA-112 (Split `docs/execution/IDEAS.md` into per-idea files). This skill is the execution vehicle for that idea. First end-to-end brownfield ingest validated the three-location split — see teisutis PR TBD.

---

**Last Updated**: 2026-04-20
