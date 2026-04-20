---
description: First stage of the sprint workflow — create a new atomic IDEA-NNN-<slug>.md file or update an existing idea by slug; maintains docs/ideas/README.md index
agent: general
---

# idea

Invoke the `idea` skill to create or update an atomic IDEA file in the target project's `docs/ideas/` tree, and sync the `docs/ideas/README.md` index. Frontmatter shape lifted from teisutis IDEA-112.

Behaviour by argument:

1. **No argument** — prompt the user for a title, auto-assign the next `IDEA-NNN`, derive a slug, ask for priority (high/medium/low), write the file.
2. **Slug argument matching an existing file** (`/idea sprint-workflow`) — load the existing `IDEA-NNN-<slug>.md` for interactive field-level update (status, priority, relationships, body edit).
3. **Number argument** (`/idea 200`) — force IDEA-200 if not already taken.
4. **Title with no slug** (`/idea "Add payment gateway"`) — treat as case 1 with the title pre-filled.

Always:

- Auto-stamp `completed: YYYY-MM-DD` when status flips to `complete`; never touch `created:` after initial write.
- Zero-pad the IDEA number to three digits (`IDEA-042`, not `IDEA-42`).
- Sync `docs/ideas/README.md` at the end — rebuild if out of sync.
- Refuse to create if a legacy monolithic `IDEAS.md` / `BACKLOG.md` / `ROADMAP.md` exists without a `docs/ideas/` tree — route to `/ingest-backlog` first.

See `skills/idea/SKILL.md` for full pattern; `docs/SPRINT_WORKFLOW.md` for the authoritative frontmatter schema.
