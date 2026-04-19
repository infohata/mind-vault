# mind-vault

Cross-host configuration library for AI coding agents — skills, commands, subagent personas, and shared rules, authored once and symlinked into every agent-aware tool.

> **Single source of truth.** You edit in `mind-vault/`; one setup script per host drops symlinks into each tool's native config directory. No copy-paste drift between Cursor, Claude Code, OpenCode, VS Code Copilot, or Antigravity.

## Structure

```text
mind-vault/
├── skills/        Agent Skills (SKILL.md + references/ + assets/ + scripts/)
├── agents/        Subagent personas (AGENT_*.md)
├── commands/      Slash commands (/test, /bugbot-loop, /create-pr, …)
├── rules/         Shared behavioural rules (RULE_*.md)
├── docs/          Reference specs, artefacts, lessons
├── scripts/       Per-host symlink setup + shared helpers
└── tools/         Utilities
```

## Skills

Canonical `SKILL.md` patterns with progressive-disclosure `references/`. Each skill has frontmatter `name` + `description` (the probabilistic trigger), stays under ~500 lines, and pushes deep-dive content to `references/`.

| Skill | Purpose |
| --- | --- |
| **skill-writer** | Meta-standard for authoring / refactoring skills — frontmatter schema, TRIGGER/SKIP, length budget, DO/DON'T matrix, cross-project portability rules. |
| **django** | Backend conventions: BaseModel, soft-delete, DRF viewsets, multi-tenancy boundaries, generic-FK pattern, permission probes, translation workflow. |
| **django-frontend** | HTMX + Alpine + Bulma + Crispy Forms — partial dispatch, modal/formset JS contracts, safe query-string generation. Pairs with `django`. |
| **deployment** | Docker Compose production deploys — change-aware scripts, pre/post-migration backups, screen-session remote execution, Let's Encrypt SSL. |
| **surgical-tdd** | Targeted test execution for large Python monoliths (Django runner + pytest nodeids + `--lf` / `-k` / `pytest-xdist` levers). |
| **artefact-retrieval** | Sweep IDE workspaces (Cursor / Antigravity / Claude Code) for plans and analyses; import into `docs/artefacts/`. |
| **idea** | Sprint workflow stage 1 — create or update atomic `IDEA-NNN-<slug>.md` files in `docs/ideas/`, maintain the per-priority index. Shape from teisutis IDEA-112. |
| **plan** | Sprint workflow stage 2 — turn an IDEA file or rough description into a durable plan; interactive brainstorm bootstrap on thin input; `AGENT_architect` as reviewer. |
| **work** | Sprint workflow stage 3 — thin orchestrator that reads a plan, enforces `RULE_git-safety` + `RULE_parallel-worktree-docker`, dispatches to implementation personas. |
| **compound** | Sprint workflow stage 5 — **the novel piece.** Routes a post-incident learning through a hybrid Shape-C probe to one of six destinations (project-local, mind-vault skill / rule / agent / command, or auto-memory). |
| **ingest-backlog** | Brownfield-takeover helper. Atomises a monolithic `IDEAS.md` / `BACKLOG.md` / `ROADMAP.md` into per-idea files matching the sprint workflow's schema. Default dry-run; `--write` for destructive. One-pass, forward-only. |

## Agents (9 subagent personas)

`AGENT_*.md` files loaded by Cursor's and Claude Code's subagent systems; consulted by OpenCode.

`architect`, `backend`, `bugbot`, `curator`, `devops`, `documentation`, `frontend`, `researcher`, `test-engineer`.

Each persona has Prime Directives, an N-pass review/implementation workflow, and a structured verdict format. The project-tuned ones carry a `**Validated in:**` tag.

## Commands (13 slash commands)

Review + PR flow: `bugbot`, `bugbot_comments`, `bugbot-loop`, `create-pr`, `git-status`, `load-rules`, `test`.

Sprint workflow: `idea`, `plan` (alias `brainstorm`), `work`, `compound`, `ingest-backlog`. See [docs/SPRINT_WORKFLOW.md](docs/SPRINT_WORKFLOW.md) for the full five-stage loop and the compound-routing story.

Invoke as `/<command-name>` in any host that supports slash commands.

## Sprint workflow

Five-stage loop inspired by Every Inc's compound-engineering plugin, re-centred on mind-vault's unique advantage: the compound stage routes learnings back into the knowledge store, so each sprint compounds the next.

```text
idea → brainstorm/plan → work → review → compound
```

- Artifacts live in the **target project's** `docs/{ideas,plans,solutions}/` tree. Mind-vault is the library; projects are the journal.
- Mind-vault grows only when `/compound` explicitly promotes a learning — new skill, extended rule, additional agent pass, new command/tool, or auto-memory entry.
- Review stays as `/bugbot-loop` (unchanged); `/compound` reads bugbot's findings file as an input source.
- `RULE_git-safety` is honoured throughout: `/compound` branches if mind-vault is on `main`, extends any existing feature branch otherwise, maintains an open PR, and never merges.

See [docs/SPRINT_WORKFLOW.md](docs/SPRINT_WORKFLOW.md) for the authoritative frontmatter schemas, the compound routing table, and right-sizing guidance.

## Rules

- **`RULE_git-safety`** — HITL gate on `main` and the release branch; feature branches are the agent's sandbox. See [rules/RULE_git-safety.md](rules/RULE_git-safety.md).
- **`RULE_i18n-workflow`** — Django translation map-first workflow; `.po` files are generated, never hand-edited.

## Setup

One setup script per host. All share `_symlink-lib.sh` (DRY helpers) so behaviour is consistent. Scripts safely update existing symlinks and skip non-symlink conflicts.

```bash
# Clone (or set MIND_VAULT=/custom/path before running scripts)
cd ~/projects
git clone git@github.com:infohata/mind-vault.git
cd mind-vault

# Pick your host(s) — run as many as apply:
./scripts/setup-cursor-symlinks.sh         # Cursor 2.4+ (verified through 3.x)
./scripts/setup-claude-code-symlinks.sh    # Claude Code — CLI + IDE extensions + Desktop
./scripts/setup-opencode-symlinks.sh       # OpenCode (XDG default; OPENCODE_HOME override)
./scripts/setup-vscode-copilot-symlinks.sh # VS Code + GitHub Copilot extension
./scripts/setup-antigravity-symlinks.sh    # Google Antigravity (VS Code fork)
```

Hosts don't conflict with each other. Restart the host client after setup for it to rescan.

### OpenCode extra config

Add to `~/.config/opencode/opencode.jsonc` so OpenCode auto-loads rules at session start:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["rules/RULE_*.md"]
}
```

### Antigravity note

Antigravity is a VS Code fork. Its **built-in Gemini chat** has no user-level skills convention, but the **Claude Code and GitHub Copilot extensions** both work inside it:

- Use `setup-claude-code-symlinks.sh` for the Claude Code extension path (reads `~/.claude/`).
- Use `setup-antigravity-symlinks.sh` for the Copilot extension path (forwards to the Copilot script with the right `VSCODE_USER`).

## Authoring

- **New skills**: follow [`docs/SKILL_SPECIFICATION.md`](docs/SKILL_SPECIFICATION.md) (Anthropic Agent Skills reference) and `skills/skill-writer/SKILL.md` (mind-vault enforcement rules).
- **Contributor conventions**: [`AGENTS.md`](AGENTS.md) — naming, structure, file organization, git workflow.

### Markdown hygiene (pre-commit)

Pre-commit hook runs `mdformat` on staged `.md` files. One-time setup:

```bash
pipx install pre-commit          # or: pip install --user pre-commit
pre-commit install               # installs the git hook
pre-commit run --all-files       # optional: one-time full-tree sweep
```

Config: [`.pre-commit-config.yaml`](.pre-commit-config.yaml) pins `mdformat` + `mdformat-gfm` + `mdformat-frontmatter`. [`.mdformat.toml`](.mdformat.toml) preserves consecutive numbering and disables line reflow.

**For documentation-heavy repos (e.g. in-project handbooks)**, prefer `markdownlint-cli2 --fix` instead of mdformat — it preserves `---` horizontal rules and emphasis style. See the note in `feedback_markdown_formatter_per_repo_type.md` memory.

## Philosophy

- **Cross-host portable**: content works in Cursor / Claude Code / OpenCode / Copilot / Antigravity — no host-specific tricks in skill bodies.
- **Progressive disclosure**: `SKILL.md` stays under ~500 lines; heavy content lives in `references/` and loads only when invoked.
- **Description = trigger**: the frontmatter `description:` is the probabilistic trigger the host agent reads to decide whether to activate. Noun-dense, specific verbs, names the concrete stack.
- **Generic patterns first, examples second**: concrete project names (e.g. Teisutis) appear only as illustrative fences, never as universal rules.

## Git workflow

Agents commit freely on feature branches — the PR is the review gate, not each commit. Agents **never** merge or push into `main` or the release branch; that's human-operated through the PR UI.

See [`rules/RULE_git-safety.md`](rules/RULE_git-safety.md) for the full contract including force-push rules and hook-bypass guardrails.

## Version control

Commit all non-sensitive configuration to git.

⚠️ **Never commit**: `.env` files, credentials, API keys, tokens, private keys.
✅ **Do commit**: skills, agent personas, rules, commands, setup scripts, docs.
