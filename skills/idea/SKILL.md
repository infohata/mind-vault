---
name: idea
description: Create a new atomic IDEA-NNN-<slug>.md file in docs/ideas/ with structured frontmatter (status, priority, supersedes, depends_on, related), or update an existing idea by slug. Maintains docs/ideas/README.md index. First stage of the mind-vault sprint workflow.
---

# idea

First stage of the five-stage sprint workflow (`idea → brainstorm/plan → work → review → compound`). Captures a new idea as an atomic, per-file markdown artifact with structured YAML frontmatter, or updates an existing one. Keeps `docs/ideas/README.md` as a lightweight index grouped by priority.

This skill does not brainstorm or plan. It captures. Ambiguity and requirements work belongs in `/plan` (aliased `/brainstorm`), which is the next stage.

## When to use

**TRIGGER when:**

- user says "new idea", "let's capture an idea", "add IDEA-...", "note this idea down", "log a backlog item"
- user wants to update an existing idea's status, priority, or body (e.g. "mark IDEA-042 complete", "bump IDEA-088 to high priority", "add IDEA-110 as related to IDEA-111")
- agent proactively surfaces an improvement candidate during another workflow (e.g. after `/compound` identifies a project-specific learning worth tracking)

**SKIP when:**

- the user wants to plan or brainstorm an existing idea — route to `/plan <slug>` instead
- the idea is clearly a one-off trivial fix that does not warrant a backlog entry — just do the work
- the project has no `docs/ideas/` tree yet AND a legacy monolithic backlog file exists (`IDEAS.md`, `BACKLOG.md`, `ROADMAP.md`) — route to `/ingest-backlog` first to establish the per-idea layout

## Pattern

### 1. Creating a new idea

Auto-increment, two-phase capture.

**Phase A — establish the record.**

1. Determine the next IDEA number by scanning **all three IDEA-file locations** — `docs/ideas/IDEA-*.md`, `docs/execution/IDEA-*.md`, and `docs/archive/*/IDEA-*.md` — for the greatest existing three-digit number, and adding 1. Default to `001` if no files exist. Users can override with an explicit number argument (`/idea 200` → forces `IDEA-200`). Scanning only `docs/ideas/` would collide with any IDEA currently in `in-progress` (execution/) or `superseded` / `rejected` (archive/) state, per [`RULE_ideas-location-status`](../../rules/RULE_ideas-location-status.md).
2. Ask the user for **title**, **priority** (high / medium / low), and an optional **depends_on** / **related** list referencing existing IDEA ids.
3. Use the platform's blocking question tool when available (`AskUserQuestion` in Claude Code, `request_user_input` in Codex) for the priority choice. Ask one question at a time.
4. Derive the slug from the title: lowercase, kebab-case, strip stopwords (`a`, `the`, `for`, `into`), truncate to ~40 chars. Confirm with the user if the slug is ambiguous.

Reference command for the number scan (agent may adapt to project specifics):

```bash
ls docs/ideas/IDEA-*.md docs/execution/IDEA-*.md docs/archive/*/IDEA-*.md 2>/dev/null \
  | sed 's/.*IDEA-\([0-9]\+\).*/\1/' \
  | sort -n | tail -1
```

**Phase B — emit the file.**

1. Read [`assets/idea-template.md`](assets/idea-template.md) and substitute the frontmatter fields. Fill `status: idea`, `created: YYYY-MM-DD` (today), `completed: null`.
2. Write to `<project>/docs/ideas/IDEA-NNN-<slug>.md` per [`RULE_ideas-location-status`](../../rules/RULE_ideas-location-status.md) — `status: idea` always starts in `docs/ideas/`. Create the directory if missing.
3. Append an index line to `<project>/docs/ideas/README.md` under the matching priority heading. Create the index file with the standard skeleton if missing (see [Index maintenance](#3-index-maintenance)).
4. Print the created path + the index line for user verification.

### 2. Updating an existing idea

When invoked with a slug argument that matches an existing file (`/idea sprint-workflow`), load the file for interactive update. The file may live in `docs/ideas/`, `docs/execution/`, or `docs/archive/*/` per [`RULE_ideas-location-status`](../../rules/RULE_ideas-location-status.md) — glob across all three when resolving.

1. Glob `docs/ideas/IDEA-*-<slug>.md`, `docs/execution/IDEA-*-<slug>.md`, and `docs/archive/*/IDEA-*-<slug>.md` — the user rarely types the IDEA number and may not know which tree the file is in.
2. Offer the user a field-level edit menu. Common updates: status change (triggers a `git mv` per step 2a below; auto-stamps `completed: YYYY-MM-DD` when flipping to `complete`; asks before any other transition), priority bump (moves the index line into the new section; no file move unless status also changes), relationship edits on `related` / `depends_on` / `supersedes` (merge + de-dupe), and body edits (open the file for the user; do not auto-rewrite prose).
3. Re-emit the file with updated frontmatter. Preserve the prose body unless the user asked to edit it.
4. Re-sync the index: if priority, title, or status changed, update the index line in place or move it between sections.

**2a. Status transitions must move the file.** Per `RULE_ideas-location-status`, location is authoritative. Any status change goes through `git mv` in the same commit as the frontmatter update:

| Transition | From → To |
| --- | --- |
| `idea` → `in-progress` | `git mv docs/ideas/IDEA-NNN-<slug>.md docs/execution/IDEA-NNN-<slug>.md` (typically triggered by `/plan`, not directly here) |
| `in-progress` → `complete` | `git mv docs/execution/IDEA-NNN-<slug>.md docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md` (create archive dir if missing; typically triggered by `/work` after merge) |
| `idea` or `in-progress` → `superseded` / `rejected` | `git mv <source> docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md` — set `superseded_by` if known |
| Reverse (archive → active) | Refuse by default. Require explicit `--resurrect` flag. Undoes the archive commit carefully; reviewed by human. |

`YYYY-MM` on the archive dir uses the transition month, not the creation month.

See [`references/update-semantics.md`](references/update-semantics.md) for the full rules about which fields are safe to auto-change, which require confirmation, and how to detect conflicting updates when multiple fields change at once.

### 3. Index maintenance

`<project>/docs/ideas/README.md` is the single-file index regardless of where individual IDEA files physically live. Links resolve into `docs/ideas/` (same dir), `../execution/`, or `../archive/<dir>/` per [`RULE_ideas-location-status`](../../rules/RULE_ideas-location-status.md).

Standard skeleton:

```markdown
# <Project> Ideas Index

_Location = status convention: see RULE_ideas-location-status. Generated by `/idea`._

## 🚧 In Progress

- [IDEA-042](../execution/IDEA-042-test-suite-defragilization.md) ⏳ — Test Suite Defragilization

## 💡 High Priority (backlog)

- [IDEA-088](IDEA-088-content-aware-attachment-indexing.md) — Content-aware attachment indexing

## 💡 Medium Priority (backlog)

- [IDEA-112](IDEA-112-split-ideas-md-into-per-idea-files.md) — Split IDEAS.md into per-idea files

## 💡 Low Priority (backlog)

_(none)_

## 🗃 Superseded / Rejected (archive)

- [IDEA-109](../archive/2026-04-idea-109-replace-stt-browser-native/IDEA-109-replace-google-cloud-stt-browser-native.md) [superseded] — Replace Google Cloud STT
- [IDEA-017](../archive/2026-04-idea-017-remote-staging/IDEA-017-remote-staging-environment-setup.md) [rejected] — Remote Staging Environment Setup

## ✅ References — Implemented

- IDEA-088 (2026-04-15) — Content-aware attachment indexing (Phases 1–3) · [Archive](../archive/2026-04-idea-088-content-indexing-phase3/)
- IDEA-107 (2026-04-09) — Event List Dashboard-Style Bucket Tabs · [Archive](../archive/2026-04-idea-107-event-list-buckets/)
```

Grouping rules:

- **In Progress** lists files in `docs/execution/IDEA-*.md` (any priority — what's being worked on now, not what might be worked on).
- **Priority groupings** (High / Medium / Low) list files in `docs/ideas/IDEA-*.md` — pure backlog.
- **Superseded / Rejected** lists files in `docs/archive/*/IDEA-*.md` with `status: superseded | rejected`.
- **References — Implemented** is footer lines for completed ideas, pointing into the archive dir (not the migrated file). Forward-only: don't link to the idea file inside the archive dir — the archive dir's own README.md is the canonical landing for a completed idea's full story.

Rebuild the index from scratch if it gets out of sync: scan all three directories, read each file's frontmatter, regenerate grouped by location.

### 4. Auto-incrementing IDEA-NNN

- Scan **all three IDEA-file locations** together: `<project>/docs/ideas/IDEA-*.md`, `<project>/docs/execution/IDEA-*.md`, and `<project>/docs/archive/*/IDEA-*.md`. Zero-padded three-digit numbers preferred (`IDEA-042` not `IDEA-42`). Scanning only `docs/ideas/` would miss IDEAs currently in `in-progress` / `superseded` / `rejected` state and produce a collision on the next increment.
- Take max + 1. If no files exist, start at `IDEA-001`.
- User override: `/idea 200 "Title here"` forces the number. Warn and ask if the number already exists **in any of the three locations**.
- Do **not** attempt to find "gaps" in the numbering. Numbers are append-only; holes from deleted ideas stay as holes.

✅ DO: `IDEA-001`, `IDEA-042`, `IDEA-112` (zero-padded to 3 digits).
❌ DON'T: `IDEA-1`, `IDEA-42`, `IDEA-0042` (inconsistent width).

## When NOT to use these patterns

- **Mind-vault itself is not a target project.** The sprint workflow runs against projects that consume mind-vault (teisutis, future projects). Inside mind-vault, ideas about mind-vault's own evolution live in `mind-vault/docs/ideas/` — the skill treats mind-vault as just another project when explicitly invoked there (e.g. for dogfooding).
- **One-off trivial work.** A typo fix does not need an IDEA entry. The skill refuses to create IDEA-NNN for work that should just be done.
- **Legacy monolithic backlog still present.** If the project has `docs/execution/IDEAS.md` or similar with no `docs/ideas/` tree yet, route the user to `/ingest-backlog` first. Don't split the source of truth mid-adoption.
- **Cross-project ideas.** An idea that applies to every project (e.g. "add a new reviewer persona") does not go in any one project's `docs/ideas/`. It goes in mind-vault through `/compound` promotion, not here.

## References

- [assets/idea-template.md](assets/idea-template.md) — the verbatim template written to disk
- [references/update-semantics.md](references/update-semantics.md) — detailed rules for editing an existing IDEA file
- [rules/RULE_ideas-location-status.md](../../rules/RULE_ideas-location-status.md) — location-by-status routing contract, including the `git mv` semantics for status transitions
- [docs/SPRINT_WORKFLOW.md](../../docs/SPRINT_WORKFLOW.md) — full sprint-workflow explainer with authoritative schemas
- [skills/plan/SKILL.md](../plan/SKILL.md) — next stage; consumes the IDEA file and triggers `idea` → `in-progress` move
- [skills/work/SKILL.md](../work/SKILL.md) — triggers the `in-progress` → `complete` move on PR merge
- [skills/ingest-backlog/SKILL.md](../ingest-backlog/SKILL.md) — brownfield-takeover helper when the project has a legacy monolithic backlog
- Origin: shape lifted from **teisutis IDEA-112** (split `docs/execution/IDEAS.md` into per-idea files) — the meta-idea that surfaced when teisutis's monolithic backlog past 1500 lines started producing painful edit PRs. PR1 execution validated the three-location split.

---

**Last Updated**: 2026-04-20 (status transitions now trigger `git mv` per RULE_ideas-location-status)
