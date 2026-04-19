# IDEA file update semantics

Rules governing `/idea <slug>` when updating an existing `docs/ideas/IDEA-NNN-<slug>.md` file. Load this file on demand when the user triggers an update, not on skill activation.

## Safe auto-changes (no confirmation needed)

These updates are applied directly and reported back to the user:

| Field | Trigger | Auto-rule |
| --- | --- | --- |
| `completed` | `status` changes from anything → `complete` | Set `completed: YYYY-MM-DD` (today). |
| `completed` | `status` changes from `complete` → anything else | Set `completed: null`. Warn the user (unusual transition — ask for confirmation). |
| index line priority | `priority` field changes | Move the line in `docs/ideas/README.md` to the matching priority section. |
| index line text | `title` field changes | Update the index line's link text. |
| `supersedes` / `depends_on` / `related` lists | user asks to add an id | Merge into the existing list; de-duplicate; sort numerically. |

## Changes requiring explicit confirmation

These are reversible structural changes that the user should affirm before the skill writes them:

- **`status: superseded`** → always asks "set `superseded_by:` to which IDEA id?" before applying.
- **`id:` field change** → refuse unless the user explicitly renumbers (e.g. renumbering after a merge conflict). Renumbering requires renaming the file too.
- **Deleting a field** (setting `priority: null`, clearing `created:`) → refuse. These fields are required.
- **Batch updates that touch > 3 fields at once** → summarise the proposed change set and ask for confirmation before writing.

## Body (prose) edits

The skill does not auto-rewrite the prose body. When the user asks to edit the body:

1. Open the file for the user's editor (print the path and stop), OR
2. Accept specific instructions like "append a new **Phase 4** section with body X" and apply them surgically.

Never:

- Rewrite the user's original prose to match a new template version.
- Delete sections the user hand-wrote.
- Re-order sections.

## Conflict detection

If the file's on-disk state appears to have been hand-edited since the last `/idea` invocation (e.g. the frontmatter is malformed, or there's a prose section with a heading the template doesn't produce), **stop and report**. Do not silently normalise.

- Print a diff of what changed vs. what the template expects.
- Ask the user to resolve manually or confirm overwrite.

## Timestamp discipline

- `created:` is **immutable** once set. Never edit it.
- `completed:` is auto-managed on status transitions to/from `complete`. Do not set it manually unless the user explicitly asks.
- No other timestamp fields are added to the frontmatter (no `updated:`, `modified:`). Filesystem mtime + git history are the authority for "when was this last touched".

## Relationship lists (`supersedes`, `superseded_by`, `depends_on`, `related`)

These are referential — they point at other IDEA ids. The skill does not enforce referential integrity (the target IDEA file may not exist yet, or may have been deleted). It does:

- Validate that the id format matches `IDEA-NNN` (integer, no prefix/suffix in the list).
- Warn if the referenced id does not exist in `docs/ideas/`.
- Never silently delete an entry because the target is missing.

Bi-directional relationships are **not automatically mirrored**. If IDEA-112 is set `supersedes: [091, 109]`, the skill does **not** automatically set `superseded_by: 112` on IDEAs 091 and 109. Ask the user whether to update the other end; if yes, do it in a second pass.

## Re-indexing

After any update that changes `status`, `priority`, or `title`:

1. Re-read the per-idea file's frontmatter.
2. Locate the corresponding line in `docs/ideas/README.md`.
3. Update in place; move across sections if needed.
4. If the index is malformed (missing section headings, duplicate entries), regenerate it from scratch by scanning all `docs/ideas/IDEA-*.md`.

---

**Last Updated**: 2026-04-19
