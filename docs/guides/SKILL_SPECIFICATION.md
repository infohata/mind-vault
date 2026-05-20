# Agent Skills Specification

**Purpose**: Reference spec for creating Agent Skills compatible with Claude Code, OpenCode, and other skill-aware hosts\
**Date**: 2026-04-17\
**Status**: Ready\
**Applies To**: mind-vault skill authoring, cross-host skill portability\
**Source**: Anthropic Agent Skills (`docs.claude.com`), OpenCode (`opencode.ai/docs/skills/`)\
**Enforcement rules**: See `skills/skill-writer/SKILL.md` for the operational rules applied in this repository

______________________________________________________________________

## Executive Summary

Agent Skills are **markdown files with YAML frontmatter** that agents load on demand to apply domain-specific knowledge. The canonical format is a `SKILL.md` file inside a skill-named directory, with optional `references/`, `assets/`, and `scripts/` subdirectories for content that loads only when needed.

**The five things that matter:**

1. **File layout**: `skills/<name>/SKILL.md` — directory name matches frontmatter `name`.
2. **Frontmatter**: `name` + `description` mandatory; description acts as the probabilistic trigger.
3. **Progressive disclosure**: keep `SKILL.md` under ~500 lines; spill detail into `references/` + `assets/`.
4. **Body structure**: Overview → When to use → Pattern → When NOT to use → References.
5. **Host-agnostic content**: no Claude-Code-only or OpenCode-only tricks in the pattern body.

______________________________________________________________________

## 1. File Structure & Discovery

### Canonical layout

```text
skills/
└── <skill-slug>/
    ├── SKILL.md              # Required, uppercase
    ├── references/           # Deep-dive docs, loaded on demand
    │   └── *.md
    ├── assets/               # Templates / snippets the agent emits verbatim
    │   └── *.{py,sh,yml,…}
    └── scripts/              # Executable helpers the agent runs
        └── *.sh
```

### Discovery locations (varies by host)

| Host        | Paths searched                                                                                                               |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Claude Code | `~/.claude/skills/<name>/SKILL.md`, `.claude/skills/<name>/SKILL.md` (project-local)                                         |
| OpenCode    | `~/.opencode/skills/<name>/SKILL.md`, `.opencode/skills/<name>/SKILL.md`, `/usr/local/share/opencode/skills/<name>/SKILL.md` |
| Cursor      | `~/.cursor/skills/<name>/` (plugin-specific paths vary)                                                                      |

**For mind-vault**: the canonical source is `~/projects/mind-vault/skills/<name>/`. Per-host discovery folders symlink into it (`~/.claude/skills`, `~/.config/opencode/skills`, etc.).

______________________________________________________________________

## 2. Frontmatter Contract

**Required minimum:**

```yaml
---
name: <kebab-case-slug>
description: <one-line trigger, noun-dense, under 200 chars>
---
```

**Optional (for larger or versioned skills):**

```yaml
license: MIT
allowed_tools:           # If set, restricts which tools the skill may invoke
  - Read
  - Grep
  - Bash
metadata:
  author: mind-vault
  version: "1.0"
  replaces:
    - <older-skill-name>
```

If `allowed_tools` is omitted, the skill inherits the parent agent's full tool set. Strict hosts (OpenCode) ignore unrecognised frontmatter keys rather than rejecting them — extras like `metadata` are safe.

### Naming rules

Format: `^[a-z0-9]+(-[a-z0-9]+)*$` (enforced by OpenCode, recommended by Claude Code).

- Lowercase alphanumeric + single hyphens.
- No leading / trailing hyphens.
- No consecutive hyphens.
- Directory name MUST match the `name` frontmatter value.

✅ `django`, `django-frontend`, `surgical-tdd`, `skill-writer`
❌ `Django-Frontend` (uppercase), `django__frontend` (underscore), `-django` (leading hyphen)

### Description — the probabilistic trigger

The description is the only text the host agent inspects when deciding whether to load the skill. Vague descriptions = skill never fires, or fires on the wrong turns.

- **Length**: 20–1024 characters (OpenCode hard limit), target ≤200 characters.
- **Style**: noun-dense, names the concrete stack, specific verbs.
- **No newlines** in the description string.

✅ **Good**:

> *Apply cross-project Django backend conventions — BaseModel abstractions, DRF viewsets, ORM optimisation, multi-tenancy boundaries, generic-FK patterns, permission probes, and translation workflow — before hitting templates.*

❌ **Bad**:

> *Django stuff*\
> *Helps with code*\
> *Enforce robust anchor store bounding box triggers.*

______________________________________________________________________

## 3. TRIGGER / SKIP Blocks

For skills that fire frequently or misfire often, include an explicit decision block at the top of `## When to use`:

```text
TRIGGER when: <conditions that should activate the skill>
SKIP: <opposite / non-applicable conditions>
```

Load-bearing — it gives the host agent a crisp decision rule instead of vibes. See `skills/skill-writer/SKILL.md` for exemplars.

______________________________________________________________________

## 4. Progressive Disclosure

Every line of `SKILL.md` is loaded into the agent's context on every activation. A 1000-line skill spends context budget the downstream task could have used.

**Target: `SKILL.md` under 500 lines. Hard stop ~800.**

When content grows past budget:

1. Move long code examples into `references/<TOPIC>.md` — linked from SKILL.md, loaded only on demand.
2. Move large templates into `assets/<name>.<ext>` — the agent reads these via tool when needed.
3. Keep the `SKILL.md` body focused on **decisions, contracts, and pointers**.

Example: `skills/django/SKILL.md` runs ~450 lines and links to 9 reference files (`MULTI_TENANT.md`, `ASYNC_WEBSOCKET.md`, `CELERY.md`, `LOGGING.md`, `I18N.md`, `TESTING.md`, `DEVELOPMENT_WORKFLOW.md`, and two combination docs).

______________________________________________________________________

## 5. Body Structure

Canonical section order (enforced by `skills/skill-writer/SKILL.md`):

1. `# <title>` + one-paragraph **Overview** (what it covers, what it does not).
2. `## When to use` — scoping rules, with TRIGGER/SKIP block if applicable.
3. `## Pattern` — the actual conventions, named or numbered subsections.
4. `## When NOT to use these patterns` — counter-cases that prevent over-application.
5. `## References` — links to `./references/*.md`, external docs, related skills.
6. Trailing `**Last Updated**: YYYY-MM-DD` line.

### DO / DON'T matrices

Every non-trivial convention should include an explicit counter-example:

```text
✅ DO: Use `select_related("author")` on list views that access `article.author.name`.
❌ DON'T: Access `.author.name` in a loop without `select_related` — N+1 query storm.
```

This bounds the agent's guessing space. Without the negative, agents revert to mean (idiomatic but wrong).

______________________________________________________________________

## 6. Host Compatibility

| Aspect        | Claude Code                                   | OpenCode                                           | Cursor               |
| ------------- | --------------------------------------------- | -------------------------------------------------- | -------------------- |
| Loading       | Session start (descriptions in system prompt) | On-demand via `skill` tool                         | Plugin-dependent     |
| Naming        | Flexible                                      | Strict `^[a-z0-9]+(-[a-z0-9]+)*$`                  | Varies               |
| Frontmatter   | Accepts extras (`metadata`, `license`)        | Only `name` + `description` parsed; extras ignored | Varies               |
| References    | Agent reads via tool                          | Agent reads via tool                               | Agent reads via tool |
| Allowed-tools | Honoured if present                           | Honoured if present                                | Varies               |

**Cross-host rule**: write for OpenCode's strict rules (most restrictive), and your skill will be compatible everywhere. Extra frontmatter is ignored by strict hosts, not rejected — so `metadata` / `allowed_tools` blocks are safe to include.

______________________________________________________________________

## 7. Cross-Project Portability

A skill in `mind-vault` is consumed by multiple projects. Concrete project names in the pattern body are **leaks**:

- **Don't** assert "Project X uses Y" as a universal rule — it's wrong for every other project.
- **Do** generalise ("Projects with constraint X should Y") or visually fence as an example:
  > *Example (Django project): the translation map lives at `tools/translation_maps/*.py`.*
- **Never hard-code paths from a consuming project** in `References`. `docs/artefacts/by-agent/…` paths do not exist from the agent's perspective when invoked from a sibling project.

______________________________________________________________________

## 8. Validation Checklist

Before merging a new or refactored skill:

- [ ] Directory: `skills/<name>/SKILL.md` (uppercase filename).
- [ ] Frontmatter `name` matches the directory name.
- [ ] Frontmatter `description` is 20–200 chars, noun-dense, no newlines.
- [ ] Name format: `^[a-z0-9]+(-[a-z0-9]+)*$`.
- [ ] `SKILL.md` < 500 lines (or heavy content extracted to `references/`).
- [ ] TRIGGER/SKIP block present if the skill fires often.
- [ ] Canonical body sections in order (Overview → When to use → Pattern → When NOT to use → References).
- [ ] DO/DON'T matrices on non-trivial conventions.
- [ ] No host-specific tricks in the body (cross-host portable).
- [ ] No concrete project names asserted as universal rules.
- [ ] Trailing `**Last Updated**: YYYY-MM-DD` line.
- [ ] Passes markdown lint (`mdformat --check` for mind-vault, `markdownlint-cli2` for doc-heavy repos).

______________________________________________________________________

## 9. Migration from Older Formats

If migrating from legacy flat-file skills (`skills/<name>.md`) or project-specific variants:

1. Create `skills/<name>/` directory.
2. Move `<name>.md` to `skills/<name>/SKILL.md`.
3. Ensure frontmatter has `name` + `description`.
4. Rename to canonical kebab-case if needed.
5. If > 500 lines, extract deep content to `references/`.
6. Add `TRIGGER/SKIP` block.
7. Bump or introduce `metadata.version`; add `metadata.replaces` pointing to old names so hosts recognise the lineage.
8. Verify the canonical body structure and add DO/DON'T matrices where missing.

______________________________________________________________________

## References

- **Anthropic Agent Skills documentation** — `docs.claude.com` (official SKILL.md spec).
- **OpenCode skills docs** — `opencode.ai/docs/skills/` (strict loading & validation rules).
- `skills/skill-writer/SKILL.md` — enforcement rules for mind-vault skill authoring.
- `skills/django/SKILL.md` — reference example of a feature-dense skill with 9 `references/` files.
- `skills/artefact-retrieval/SKILL.md` — reference example of a lean, self-contained skill.
- `skills/deployment/SKILL.md` — reference example of a skill split into SKILL + `references/` + `scripts/`.

**Last Updated**: 2026-04-17
