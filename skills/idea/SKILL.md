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

1. Determine the next IDEA number by scanning **both IDEA-file locations** — `docs/ideas/IDEA-*.md` and `docs/archive/*/IDEA-*.md` — for the greatest existing three-digit number, and adding 1. Default to `001` if no files exist. Users can override with an explicit number argument (`/idea 200` → forces `IDEA-200`). Scanning only `docs/ideas/` would collide with any IDEA currently in `in-progress`, `complete`, `superseded`, or `rejected` state, all of which live in the archive tree per [`RULE_ideas-location-status`](references/IDEAS_LOCATION_STATUS.md).
2. Ask the user for **title**, **priority** (high / medium / low), and an optional **depends_on** / **related** list referencing existing IDEA ids.
3. Use the platform's blocking question tool when available (`AskUserQuestion` in Claude Code, `request_user_input` in Codex) for the priority choice. Ask one question at a time.
4. Derive the slug from the title: lowercase, kebab-case, strip stopwords (`a`, `the`, `for`, `into`), truncate to ~40 chars. Confirm with the user if the slug is ambiguous.
5. **Evaluate sprint-auto eligibility** and set the two gate fields with explicit reasoning. Default both to `false` at capture — the question isn't "can we eventually automate this?" but "can sprint-auto run this **tonight, unattended, with no human in the loop**?" A `/plan` pass later can upgrade `false → true` once the unknowns are resolved. Rubric:

   | Gate | Ask yourself | Default at capture |
   | --- | --- | --- |
   | `auto_safe` | Are there **judgment calls** (path naming, middleware scope, algorithm choice, UX decisions) that sprint-auto would have to make blindly? **Migrations + reversibility known?** **Test coverage path clear?** If any `no` / `unknown` — leave `false`. | `false` unless obviously additive + reversible + no design unknowns |
   | `sensitive_paths_cleared` | Does the scope touch **auth / permission / schema / infra (nginx, docker-compose) / secrets / payment paths**? Broad regex matches like `*auth*`, `*billing*`, `*core*` bias toward `false` even when the actual change is benign — the gate exists so a human eyeballs it. | `false` unless the files touched are entirely outside those zones |

   Write a 1-2 sentence reason for each, naming the specific blocker (or the specific reason it's safe) — never leave the reason empty. The reason is what a future sprint-auto reviewer reads when deciding whether to flip the gate during `/plan`.

Reference command for the number scan (agent may adapt to project specifics):

```bash
ls docs/ideas/IDEA-*.md docs/archive/*/IDEA-*.md 2>/dev/null \
  | sed 's/.*IDEA-\([0-9]\+\).*/\1/' \
  | sort -n | tail -1
```

**Phase B — emit the file.**

1. Read [`assets/idea-template.md`](assets/idea-template.md) and substitute the frontmatter fields. Fill `status: idea`, `created: YYYY-MM-DD` (today), `completed: null`.
2. Write to `<project>/docs/ideas/IDEA-NNN-<slug>.md` per [`RULE_ideas-location-status`](references/IDEAS_LOCATION_STATUS.md) — `status: idea` always starts in `docs/ideas/`. Create the directory if missing.
3. Append an index line to `<project>/docs/ideas/README.md` under the matching priority heading. Create the index file with the standard skeleton if missing (see [Index maintenance](#3-index-maintenance)).
4. Print the created path + the index line for user verification.

### 2. Updating an existing idea

When invoked with a slug argument that matches an existing file (`/idea sprint-workflow`), load the file for interactive update. The file may live in `docs/ideas/` (backlog) or `docs/archive/<dir>/` (any non-backlog status) per [`RULE_ideas-location-status`](references/IDEAS_LOCATION_STATUS.md) — glob both when resolving.

1. Glob `docs/ideas/IDEA-*-<slug>.md` and `docs/archive/*/IDEA-*-<slug>.md` — the user rarely types the IDEA number and may not know whether the idea is still in backlog.
2. Offer the user a field-level edit menu. Common updates: **status change** (one-move transition per step 2a; most status flips are frontmatter-only since the idea already lives in its permanent dir), **priority bump** (moves the index line into the new section; no file move), **relationship edits** on `related` / `depends_on` / `supersedes` (merge + de-dupe), and **body edits** (open the file for the user; do not auto-rewrite prose).
3. Re-emit the file with updated frontmatter. Preserve the prose body unless the user asked to edit it.
4. Re-sync `docs/ideas/README.md`: if priority, title, or status changed, update the index line in place or move it between sections.

**2a. Status transitions.** Per `RULE_ideas-location-status`, **only one filesystem move exists across the whole lifecycle** — the `idea → <anything-else>` move. Everything after is frontmatter-only:

| Transition | Action |
| --- | --- |
| `idea` → `in-progress` | `mkdir docs/archive/YYYY-MM-idea-NNN-<slug>/` + `git mv docs/ideas/IDEA-NNN-<slug>.md <dir>/IDEA-NNN-<slug>.md` + `status: in-progress`. Usually triggered by `/plan`, not directly. |
| `idea` → `superseded` \| `rejected` | Same move (fresh archive dir, `YYYY-MM` = rejection month) + `status: superseded \| rejected` + `superseded_by: NNN` if known. |
| `in-progress` → `complete` \| `superseded` \| `rejected` | **Frontmatter-only.** File stays in its archive dir. Triggered by `/work` (on merge) or `/compound` (on rejection). |
| Reverse (`complete`/`superseded` → active) | Refuse by default. Require explicit `--resurrect` flag; reviewed by human; may involve `git mv` back to `docs/ideas/` and creating a new IDEA number for the resumed work. |

`YYYY-MM` in the archive dir name = the month the first move happened. Doesn't change on later status flips.

See [`references/update-semantics.md`](references/update-semantics.md) for the full rules about which fields are safe to auto-change, which require confirmation, and how to detect conflicting updates when multiple fields change at once.

### 3. Index maintenance

`<project>/docs/ideas/README.md` is the single-file index regardless of where individual IDEA files physically live. Links resolve into `docs/ideas/` (same dir) or `../archive/<dir>/` per [`RULE_ideas-location-status`](references/IDEAS_LOCATION_STATUS.md).

Standard skeleton:

```markdown
# <Project> Ideas Index

_Two locations per RULE_ideas-location-status: `docs/ideas/` = backlog;
`docs/archive/YYYY-MM-idea-NNN-<slug>/` = everything else. Generated by `/idea`._

## 🚧 In Progress

- [IDEA-042](../archive/2026-04-idea-042/IDEA-042-test-suite-defragilization.md) ⏳ — Test Suite Defragilization

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

Grouping rules — all read frontmatter `status:`, filter by directory:

- **🚧 In Progress** — `docs/archive/*/IDEA-*.md` where `status: in-progress`.
- **💡 Priority groupings** (High / Medium / Low) — `docs/ideas/IDEA-*.md` (status: idea).
- **🗃 Superseded / Rejected** — `docs/archive/*/IDEA-*.md` where `status: superseded | rejected`.
- **✅ References — Implemented** — `docs/archive/*/IDEA-*.md` where `status: complete`. Footer lines pointing at the archive dir (not the IDEA file) — the archive dir's own README is the canonical landing for a completed idea's full story.

Rebuild the index from scratch if it gets out of sync: scan both dirs, read each file's frontmatter, regenerate.

### 4. Auto-incrementing IDEA-NNN

- Scan **both IDEA-file locations** together: `<project>/docs/ideas/IDEA-*.md` and `<project>/docs/archive/*/IDEA-*.md`. Zero-padded three-digit numbers preferred (`IDEA-042` not `IDEA-42`). Scanning only `docs/ideas/` would miss IDEAs in any non-backlog state (`in-progress`, `complete`, `superseded`, `rejected`) — all live in the archive tree per [`RULE_ideas-location-status`](references/IDEAS_LOCATION_STATUS.md) — and produce a collision on the next increment.
- **Each project's numbering is independent.** Scan ONLY the target project's `docs/ideas/` + `docs/archive/`. Never carry a number from another project's stream (e.g. agent working a `project-x` compound branch checked into mind-vault must NOT pick "next after IDEA-166" — IDEA-166 lives in `project-x`, mind-vault has its own sequence starting at IDEA-001). The branch name (`compound/2026-05-DD-idea-NNN-...`) often references the originating project's IDEA — that is NOT the target project's next number. The scan-from-disk rule is what defines the next number; conversation context referencing other projects' IDEAs is irrelevant.
- Take max + 1. If no files exist, start at `IDEA-001`.
- User override: `/idea 200 "Title here"` forces the number. Warn and ask if the number already exists **in either location**.
- Do **not** attempt to find "gaps" in the numbering. Numbers are append-only; holes from deleted ideas stay as holes.

✅ DO: `IDEA-001`, `IDEA-042`, `IDEA-112` (zero-padded to 3 digits).
❌ DON'T: `IDEA-1`, `IDEA-42`, `IDEA-0042` (inconsistent width).

## When NOT to use these patterns

- **Mind-vault itself is not a target project.** The sprint workflow runs against projects that consume mind-vault. Inside mind-vault, ideas about mind-vault's own evolution live in `mind-vault/docs/ideas/` — the skill treats mind-vault as just another project when explicitly invoked there (e.g. for dogfooding).
- **One-off trivial work.** A typo fix does not need an IDEA entry. The skill refuses to create IDEA-NNN for work that should just be done.
- **Legacy monolithic backlog still present.** If the project has `docs/execution/IDEAS.md` or similar with no `docs/ideas/` tree yet, route the user to `/ingest-backlog` first. Don't split the source of truth mid-adoption.
- **Cross-project ideas.** An idea that applies to every project (e.g. "add a new reviewer persona") does not go in any one project's `docs/ideas/`. It goes in mind-vault through `/compound` promotion, not here.

## References

- [assets/idea-template.md](assets/idea-template.md) — the verbatim template written to disk
- [references/update-semantics.md](references/update-semantics.md) — detailed rules for editing an existing IDEA file
- [skills/idea/references/IDEAS_LOCATION_STATUS.md](references/IDEAS_LOCATION_STATUS.md) — location-by-status routing contract, including the `git mv` semantics for status transitions
- [docs/guides/SPRINT_WORKFLOW.md](../../docs/guides/SPRINT_WORKFLOW.md) — full sprint-workflow explainer with authoritative schemas
- [skills/plan/SKILL.md](../plan/SKILL.md) — next stage; consumes the IDEA file and triggers `idea` → `in-progress` move
- [skills/work/SKILL.md](../work/SKILL.md) — triggers the `in-progress` → `complete` move on PR merge
- [skills/ingest-backlog/SKILL.md](../ingest-backlog/SKILL.md) — brownfield-takeover helper when the project has a legacy monolithic backlog
