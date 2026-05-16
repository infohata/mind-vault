# Legacy backlog format recognition

Parsing rules for the monolithic-backlog shapes `/ingest-backlog` supports. Load on demand at step 2 of the skill. Grows by addition — when a new legacy shape surfaces (third brownfield takeover, etc.), add a recognition block here rather than special-casing the core skill.

## Canonical shape — H4-entry style

Detected by the presence of `#### IDEA-NNN:` headings in the source.

### Entry heading

```markdown
#### IDEA-NNN: <Title text>
```

- `NNN` is 1–4 digits. Parsed as an integer, re-zero-padded to 3 digits on emit (`42` → `042`).
- Title text is everything after `: `. Used for the slug and for the frontmatter `title` field.

### Field markers

Fields appear as bold label + colon + value, one per line, between the heading and the first body paragraph. All optional.

```markdown
**Status**: <status indicator>
**Priority**: <priority indicator>
**Depends on**: IDEA-NNN[, IDEA-NNN, ...]
**Supersedes**: IDEA-NNN[, IDEA-NNN, ...]
**Superseded by**: IDEA-NNN
**Related**: IDEA-NNN[, IDEA-NNN, ...]
**Created**: YYYY-MM-DD
**Completed**: YYYY-MM-DD
```

### Value normalisation (strip formatting)

Field values often contain inline markdown formatting, bold markers, trailing metadata, or link references. Before matching against the enum tables below:

- Strip leading/trailing whitespace.
- Strip bold markers (`**...**`) around the value: `✅ **COMPLETE** · All phases done` → `✅ COMPLETE · All phases done`.
- Strip trailing metadata after ` · ` or ` — ` or `(...)`: `High (search relevance for manuals)` → `High`.
- Keep the leading emoji — it disambiguates the canonical status/priority.
- Match the remaining first 1–3 tokens against the mapping tables.

### Status-value mapping

Many legacy backlogs use emoji-prefixed status indicators; normalise to the canonical `status:` enum:

| Legacy value | Normalised `status:` |
| --- | --- |
| `💡 Idea`, `Idea`, `New`, `Proposed` | `idea` |
| `🔄 In Progress`, `In Progress`, `Active`, `WIP`, `🔄 Partially done` | `in-progress` |
| `✅ COMPLETE`, `COMPLETE`, `Done`, `Shipped`, `Landed` | `complete` |
| `❌ Cancelled`, `Cancelled`, `Dropped`, `Rejected` | `superseded` (if pointer available) or drop |
| `Superseded`, `Replaced by X` | `superseded` |

If the value doesn't match any pattern, default to `idea` and emit a warning in the dry-run.

### Priority-value mapping

```text
| Legacy value                        | Normalised |
| ----------------------------------- | ---------- |
| High, High Priority, 🔥, P0, P1     | high       |
| Medium, Medium-High, Medium-Low, P2 | medium     |
| Low, Low Priority, P3, Nice-to-have | low        |
```

Missing priority → `medium` + warning.

### Body

Everything after the field block until the next `#### IDEA-NNN:` heading (or `### ` / `## ` heading) is the entry body. Preserve verbatim on emit — no prose rewriting.

Minor normalisation:

- Strip the redundant `**Status**:` / `**Priority**:` lines if the skill is also writing them to frontmatter (avoid double-encoding state).
- Keep everything else, including emoji, tables, code blocks, and nested headings.

## Variant — H3 entries (`### IDEA-NNN:`)

Some projects use H3 instead of H4. Detected by a document where no `#### IDEA-NNN:` entries exist but `### IDEA-NNN:` do. Field and body handling is identical.

## Variant — GitHub issues export

Exports from `gh api /issues` or similar:

```markdown
## Issue #42: Title
- **State**: open / closed
- **Labels**: priority/high, type/feature
- **Body**: <prose>
```

Mapping:

- `State: open` → `status: idea` (unless a label says `status:in-progress`).
- `State: closed` → `status: complete`.
- Labels like `priority/high`, `priority/medium`, `priority/low` → `priority:` field.
- Labels like `depends-on:#NNN` → `depends_on:` list.
- No IDEA-NNN numbering in GitHub issues — the skill assigns new sequential IDEA-NNN starting from 1, capturing the original issue number in the body's provenance.

## Variant — kanban-style (`- [ ] Title`)

Flat `BACKLOG.md` with a task-list syntax:

```markdown
## High Priority
- [ ] Add payment gateway integration
- [ ] Migrate to Python 3.12

## Medium Priority
- [x] Refactor billing module  <!-- done -->
- [ ] Improve test coverage
```

Mapping:

- Section heading (`## High Priority`) → `priority:`.
- `- [ ]` → `status: idea`.
- `- [x]` → `status: complete` (kept as footer only, not migrated).
- No IDEA-NNN → skill auto-assigns sequential numbers starting at 1.
- Title = the bullet text.
- Body = any indented continuation under the bullet, or empty.

## Field inference heuristics

When parsed fields are missing:

- **No `status:` field** → `status: idea`. Warning in dry-run summary.
- **No `priority:` field** → `priority: medium`. Warning in dry-run summary.
- **No `created:` field** → best-effort from git blame (`git log --diff-filter=A --format=%cs -- <source-file>`) on the lines where the entry was introduced. If unavailable, use today's date and mark the entry with `created_inferred: true` in a footer comment.
- **No `completed:` field but `status: complete`** → best-effort from git blame on the status-line change to `✅ COMPLETE`. Fall back to the completed-section scan date.

## De-duplication

If the source file contains two entries with the same IDEA-NNN:

- **Exact-duplicate bodies:** drop the later one, keep the earlier one, emit a warning.
- **Different bodies:** refuse and surface the conflict. The user must resolve in the source file before re-running the skill.
- **Full H4 entry in an active section + short footer line in a Completed section for the same ID:** interpret as "entry is actually complete but the active entry is stale". Classify as `status: complete`, use the footer line as the source of truth, drop the H4 body, emit a warning listing the dropped body so the user can decide whether to restore it as prose in the archive directory. This is the "IDEA shipped but someone forgot to remove the New-Ideas entry" pattern.

If two entries would slug-collide (different IDs, same title text slugified):

- Append `-N` suffix to the later one's slug (IDEA-042-add-payment-gateway, IDEA-108-add-payment-gateway-2).
- Emit a warning so the user can rename the title in the source if desired.

## Adding a new format

When a brownfield takeover surfaces a shape this file doesn't cover:

1. Add a new `## Variant — <name>` section here with the detection heuristic and mapping rules.
2. Extend the skill's parsing logic in `SKILL.md` step 2 to branch on the new detection.
3. Do NOT special-case inside the core skill body — keep the format specifics isolated in this reference file so the core remains stable.

---

**Last Updated**: 2026-04-19
