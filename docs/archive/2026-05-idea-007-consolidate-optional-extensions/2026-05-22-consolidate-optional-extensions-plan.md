---
stage: plan
slug: consolidate-optional-extensions
created: 2026-05-22
source: ./IDEA-007-consolidate-optional-extensions-into-references.md
status: shipped
project: mind-vault
---

# Plan — Consolidate `Optional extensions` into `## References`

## Context

Three feature-dense skills carry **two** parallel index blocks listing the same `references/*.md` files: a top-of-file `**Optional extensions** (load on demand):` and a bottom-of-file `## References` section. The skill-writer spec (PR #134) codifies one canonical body section per skill, so the duplicate index now violates the rule it just established. Every line of `SKILL.md` is loaded into context on every activation — the duplicate index doubles the token cost for the same information.

Scope: SMALL — three SKILL.md files, mechanical merge per file, < 30 min per file, no design unknowns. Architect review skipped per right-sizing.

## Scope Boundaries

**In-scope:**

- `skills/deployment/SKILL.md` (line 25: 9 entries, ~11 lines)
- `skills/django/SKILL.md` (line 23: 10 entries, ~13 lines)
- `skills/django-frontend/SKILL.md` (line 28: 18 entries, ~20 lines)

**Out-of-scope:**

- Reference file content edits (`references/*.md` themselves stay untouched).
- SKILL.md body changes outside the index blocks (no rewording of `## Pattern`, hazards, etc.).
- Renaming the canonical section (it stays `## References`).
- Other skills that don't carry the `Optional extensions` pattern (audit confirmed only these three).
- Adopting a new top-of-file index convention (`## Further reading` etc.) — the spec names exactly one section.

**Non-goals:**

- Polishing the descriptions in `## References` beyond what's needed to absorb the entries from `Optional extensions`. If both blocks already have an entry pointing at the same file with different descriptions, keep the longer/more-recent one; don't author fresh wording.

## Requirements Trace

- **R1** — `## References` is the only canonical index block; `Optional extensions` is removed entirely from all three SKILL.md files. (IDEA-007 Proposal §1, §2; skill-writer SKILL.md body §"Body structure" item 5.)
- **R2** — No entry that previously appeared in `Optional extensions` is lost — every reference still discoverable in the merged `## References`. (IDEA-007 Proposal §1; per-file diff verification.)
- **R3** — In-body inline mentions of references (e.g. inside `## Critical hazards`) link to `references/<NAME>.md` at point of mention, not via the deleted top block. (IDEA-007 Proposal §3.)
- **R4** — Each file's line count drops by approximately the size of its `Optional extensions` block minus any entries genuinely added to `## References` (most should already be mirrored).

## Context & Research

- **Precedent**: PR #134 already removed our newly-added bullet from `django-frontend`'s `Optional extensions` and codified the single-block rule in `skills/skill-writer/SKILL.md`. The same skill's body §"Body structure" item 5 names these three files as the historical violators to consolidate.
- **Audit confirmed during /plan**: `grep -l "Optional extensions" skills/*/SKILL.md` returns exactly the three offenders — no other skills are affected.
- **Prior debloat**: IDEA-002 (PR #107/#109/#110) extracted body content into `references/*.md` and trimmed ~748L across the same three skills. This is the index-level continuation.

## Key Technical Decisions

- **Dedup rule when both blocks list the same reference**: prefer the entry as it currently appears in `## References` (bottom block) since it's the spec-canonical home. If the `Optional extensions` entry has a longer / more-recent description, swap that description into the bottom-block entry; the `Optional extensions` line is then deleted. No new bullets are authored — only descriptions migrated.
- **Merge order in `## References`**: append-only at end of existing `## References`. Don't re-sort; preserves git-blame for historical entries.
- **One commit per file**: keeps the merge audit-able per skill. Three commits, identical pattern, easy to revert one without disturbing the others. (Aligns with `RULE_rename-before-drop` § "One commit per logical step" — even though this isn't a rename, the same per-step bisectability discipline applies.)
- **Don't touch `Pairs with:` lines, `Compatibility:` lines, or any other top-matter** — the `Optional extensions` block sits between those and `## When to use`. Surgical edit only.

## Open Questions

None at draft time. All entries are mechanical; no judgment calls expected. If during execution a `Optional extensions` entry turns out NOT to be mirrored in `## References` (genuine new content), promote it verbatim to the bottom block before deleting the top.

## Execution Sequence

For each of the three files, repeat the same per-file pattern:

### Step 1: `skills/django/SKILL.md` (smallest dedup surface, do first as canary) ✅ 67e9997

1. Read both blocks (top `Optional extensions` at L23, bottom `## References` at L572).
2. Build a diff: which top-block entries are absent from the bottom block?
3. For absent entries: insert them into `## References` (append at end). For mirrored entries: if top-block description is richer, update bottom-block description.
4. Delete the `Optional extensions` block (header + entries + trailing blank line). Preserve the `Pairs with:` line directly above.
5. Verify line count drops by ~10-13 lines.
6. Commit: `chore(skills): django — consolidate Optional extensions into ## References (IDEA-007)`.

### Step 2: `skills/deployment/SKILL.md` ✅ 3395484 (+ 42c2f75 README terminology fix)

Same pattern. Top block at L25 (9 entries), bottom at L460. Commit:  `chore(skills): deployment — consolidate Optional extensions into ## References (IDEA-007)`.

### Step 3: `skills/django-frontend/SKILL.md` ✅ 3d81557

Same pattern. Top block at L28 (18 entries — largest), bottom at L591. The bottom block already includes some entries not in the top block (`App-shell layout`, `Alpine.store coordinators`, `Active-state tracking`, `Template comment syntax`, `SCSS vendor-import` — these are referenced inline from `## Critical hazards` and `## Pattern`). Most of the top block IS mirrored in the bottom block already (PR #134 audit visible in conversation), so the merge is mostly dedup-and-delete, light promotion of any unique descriptions. Commit: `chore(skills): django-frontend — consolidate Optional extensions into ## References (IDEA-007)`.

### Step 4: Cross-check

After all three commits, grep `skills/*/SKILL.md` for `Optional extensions` — should return zero matches. Grep `## References` — exactly one per offender SKILL.md.

### Step 5: Wrap the IDEA

Per the /wrap skill, flip IDEA-007 frontmatter `status: in-progress → complete`, append a paragraph to the archive dir's README (or create one if absent) summarising the trim achieved per file, log a devlog entry. The /wrap skill handles the housekeeping.

## Verification

- `! grep -l "Optional extensions" skills/*/SKILL.md` returns success (zero offenders).
- `wc -l skills/{deployment,django,django-frontend}/SKILL.md` shows a net trim of ~40-60 lines summed across the three files.
- Visual diff on each file: bottom `## References` section now contains every entry the top block listed, no duplicates, no orphaned link-text.
- Dual-engine review-loop on the resulting PR: bugbot + copilot both CLEAN on HEAD. No new findings expected — markdown-only edits with mechanical pattern.

## Risks

Minimal:

- **Risk**: A consumer (CLAUDE.md, agent prompt, external doc) hard-codes the `Optional extensions` heading and breaks. Mitigation: `grep -rn "Optional extensions"` outside `skills/` to confirm zero external references. Likely already true.
- **Risk**: An entry in the top block that's NOT mirrored in the bottom block gets silently dropped. Mitigation: per-file build-the-diff step before deletion (Execution Step 1.2 / 2.2 / 3.2).

## Next command

`/work docs/archive/2026-05-idea-007-consolidate-optional-extensions/2026-05-22-consolidate-optional-extensions-plan.md`
