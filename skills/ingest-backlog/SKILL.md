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

Walk the detected entries and classify:

- **Active** (default destination: per-idea file). `status: idea | in-progress`. Entry body preserved verbatim; frontmatter derived from parsed fields.
- **Completed** (default destination: index footer line only, no file). `status: complete`. Keep the entry's title + IDEA id + optional completion date; do not migrate prose.
- **Superseded** (default destination: per-idea file with `status: superseded`, `superseded_by: <id>` if determinable). If the supersession link is unclear, fall back to Active and surface a warning.

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
2. `mkdir -p <project>/docs/ideas/`.
3. For each Active and Superseded entry:
   - Emit `<project>/docs/ideas/IDEA-NNN-<slug>.md` using [`assets/idea-template.md`](assets/idea-template.md).
   - Frontmatter derived from parsed fields; body transplanted from the source entry with minor normalisation (strip legacy emoji status prefixes, keep prose).
4. Write `<project>/docs/ideas/README.md` with the standard skeleton — one line per Active/Superseded idea grouped by priority, Completed entries as footer lines.
5. Rewrite the source monolithic file as a short stub pointing at `docs/ideas/README.md`:

   ```markdown
   # IDEAS.md

   This file was split into per-idea files under [`docs/ideas/`](../ideas/).
   See [`docs/ideas/README.md`](../ideas/README.md) for the index.

   _Original content preserved in git history — see commit that landed the split._
   ```

6. Print a summary: files created, index entries, any warnings. **Do not commit.** The user reviews the diff and commits by hand.

### 6. Forward-only policy (load-bearing)

Completed entries never get migrated into per-idea files, even if they have substantial body content. Rationale from teisutis IDEA-112:

- Completed ideas live in existing execution archive directories (`docs/archive/YYYY-MM-idea-NNN-<slug>/`) when they have rich history. That's the canonical location.
- Migrating a completed idea's body into a new file duplicates state and creates two sources of truth.
- The index's footer line + optional archive-directory link is enough for discoverability via grep.

If the user disagrees on a specific entry, they can hand-create the file post-ingest. Don't expand this skill's scope to handle it.

### 7. Slug derivation

- Lowercase the title, strip `IDEA-NNN:` prefix.
- Kebab-case on word boundaries.
- Strip stopwords (`a`, `the`, `for`, `into`, `of`, `on`, `in`).
- Truncate to ~40 chars at a word boundary.
- De-duplicate: if two entries would collide, append `-N` suffix to later ones.

### 8. Idempotency on re-run

If `<project>/docs/ideas/IDEA-NNN-<slug>.md` already exists (e.g. re-running after a partial previous ingest), the skill:

- Compares the existing file's frontmatter against the proposed one.
- **If identical or existing is a superset:** skip the file, report "already present" in the summary.
- **If divergent:** refuse to overwrite, report the conflict, and route the user to resolve manually. Do not silently stomp.

This makes re-runs safe when the legacy file has been edited since a prior ingest.

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
- [docs/SPRINT_WORKFLOW.md](../../docs/SPRINT_WORKFLOW.md) — authoritative IDEA frontmatter schema
- [skills/idea/SKILL.md](../idea/SKILL.md) — the skill that consumes the per-idea format this one produces
- Origin: teisutis IDEA-112 (Split `docs/execution/IDEAS.md` into per-idea files). This skill is the execution vehicle for that idea.

---

**Last Updated**: 2026-04-19
