# mind-vault — `docs/`

Inside-the-vault documentation. The project overview lives in the [root README](../README.md); this directory holds onboarding, deep-dive guides, the sprint-workflow explainer, the skill spec, host integration notes, and the historical archive.

## Guides

All guides live under [`guides/`](guides/). Start with ONBOARDING and follow links from there.

- **[guides/ONBOARDING.md](guides/ONBOARDING.md)** — 30-minute tour for new contributors / new hosts. The starting point. Now includes inline AI-concepts section + useful Claude commands toolbox + deep-dives index.
- **[guides/SPRINT_WORKFLOW.md](guides/SPRINT_WORKFLOW.md)** — the five-stage compound loop in detail: frontmatter schemas, routing tables, right-sizing, stage handoffs.
- **[guides/SKILL_SPECIFICATION.md](guides/SKILL_SPECIFICATION.md)** — Anthropic Agent Skills reference (frontmatter, naming regex, directory layout, validation rules). Pair with [skill-writer](../skills/skill-writer/SKILL.md) for mind-vault's authoring enforcement.
- **[guides/SKILL_AUTHORING_WALKTHROUGH.md](guides/SKILL_AUTHORING_WALKTHROUGH.md)** — process companion to SKILL_SPECIFICATION: when to make a skill vs rule vs command vs agent, the 500-line body budget, anti-patterns, `/compound` route.
- **[guides/GIT_WORKFLOW.md](guides/GIT_WORKFLOW.md)** — branch-per-IDEA discipline, multi-engine review, integration branches, force-push hygiene, the HITL merge gate.
- **[guides/WORKTREE_PRACTICES.md](guides/WORKTREE_PRACTICES.md)** — parallel `git worktree` workflow, port-offset discipline, `.env` isolation exception, sprint-auto's integration-worktree pattern.
- **[guides/MEMORY_MANAGEMENT.md](guides/MEMORY_MANAGEMENT.md)** — auto-memory vs `CLAUDE.md` vs project doc vs skill, rot detection, periodic pruning, verify-before-acting discipline.
- **[guides/CURSOR_SETUP.md](guides/CURSOR_SETUP.md)** — Cursor 2.4+ integration notes (symlink caveat, per-skill workaround).
- **[guides/AGENT_PORTABILITY.md](guides/AGENT_PORTABILITY.md)** — cross-harness agent-profile compatibility: the CC-canonical schema, what travels unchanged to Cursor, and fork recipes for OpenCode + Antigravity.

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

Checks regex-valid name, directory ↔ frontmatter `name` match, description length, presence of required sections, and common smells (TODO / FIXME). See [guides/SKILL_SPECIFICATION.md](guides/SKILL_SPECIFICATION.md) for the underlying spec.

## Authoring conventions

- **New skills / rule refactors** → [skills/skill-writer/SKILL.md](../skills/skill-writer/SKILL.md) (mind-vault's authoring enforcement: frontmatter, length budget, references/assets layout, trigger quality).
- **Project-wide conventions** (naming, structure, git workflow) → [AGENTS.md](../AGENTS.md) at repo root.
- **Always-on behavioural rules** → [rules/](../rules/) at repo root (auto-loaded into every session).
