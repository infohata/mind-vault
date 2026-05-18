# mind-vault — `docs/`

Inside-the-vault documentation. The project overview lives in the [root README](../README.md); this directory holds onboarding, the sprint-workflow explainer, the skill spec, host integration notes, and the historical archive.

## Top-level guides

- **[ONBOARDING.md](ONBOARDING.md)** — 30-minute tour for new contributors / new hosts. The starting point.
- **[SPRINT_WORKFLOW.md](SPRINT_WORKFLOW.md)** — the five-stage compound loop in detail: frontmatter schemas, routing tables, right-sizing, stage handoffs.
- **[SKILL_SPECIFICATION.md](SKILL_SPECIFICATION.md)** — Anthropic Agent Skills reference (frontmatter, naming regex, directory layout, validation rules). Pair with [skill-writer](../skills/skill-writer/SKILL.md) for mind-vault's authoring enforcement.
- **[CURSOR_SETUP.md](CURSOR_SETUP.md)** — Cursor 2.4+ integration notes (symlink caveat, per-skill workaround).

## Working directories

- **[ideas/](ideas/)** — open IDEA backlog (`IDEA-NNN-<slug>.md` per item, indexed by [ideas/README.md](ideas/README.md)). Managed by `/idea` and `/ideate`.
- **[plans/](plans/)** — durable technical plans emitted by `/plan` for IDEAs without an archive dir yet.
- **[artefacts/](artefacts/)** — externally-retrieved artefacts (research, validation logs) imported via `/artefact-retrieval`. Taxonomy in [artefacts/taxonomy.md](artefacts/taxonomy.md).
- **[archive/](archive/)** — shipped IDEAs (`YYYY-MM-idea-NNN-<slug>/`), archived research, historical session notes.
- **[troubleshooting/](troubleshooting/)** — host-specific gotchas (WSL, etc.).

## Tooling

[`tools/validate-skills.sh`](../tools/validate-skills.sh) — name/frontmatter/structure linter for skills:

```bash
./tools/validate-skills.sh <skill-name>   # single
./tools/validate-skills.sh --all          # entire skills/ tree
```

Checks regex-valid name, directory ↔ frontmatter `name` match, description length, presence of required sections, and common smells (TODO / FIXME). See [SKILL_SPECIFICATION.md](SKILL_SPECIFICATION.md) for the underlying spec.

## Authoring conventions

- **New skills / rule refactors** → [skills/skill-writer/SKILL.md](../skills/skill-writer/SKILL.md) (mind-vault's authoring enforcement: frontmatter, length budget, references/assets layout, trigger quality).
- **Project-wide conventions** (naming, structure, git workflow) → [AGENTS.md](../AGENTS.md) at repo root.
- **Always-on behavioural rules** → [rules/](../rules/) at repo root (auto-loaded into every session).

---

**Last Updated**: 2026-05-18
