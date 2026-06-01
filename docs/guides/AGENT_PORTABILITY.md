# Agent Profile Portability (cross-harness)

**Purpose**: The eight `agents/AGENT_*.md` persona profiles are authored in the **Claude Code recognized subagent schema** — that is the single source of truth. This guide documents how far one file travels unchanged across other harnesses (Cursor, OpenCode, Antigravity) and gives a fork-and-fix recipe where a translation step is unavoidable.

**Priority**: Claude Code. When compatibility breaks, the profile stays CC-correct and you fork a harness-specific copy per the recipes below — we do **not** degrade the canonical file to chase a lowest-common-denominator that satisfies no harness well.

## Canonical schema (Claude Code)

```yaml
---
name: mv-backend                                   # required; lowercase-hyphen, 3–50 chars
description: |                                      # rich, trigger-oriented, with <example> blocks
  Use this agent for ... Examples:
  <example> ... </example>
model: inherit                                      # inherit | sonnet | opus | haiku
color: blue                                         # optional, cosmetic
tools: Read, Grep, Glob, Bash, Write, Edit, TodoWrite  # comma-string OR YAML list; omit = all
---

<persona body / prime directives>
```

Two deliberate choices make the file maximally portable:

- **`name: mv-<persona>`** — namespaced so it never collides with marketplace plugin agents in the shared subagent registry.
- **`model: inherit` across the whole roster** — any pinned model (`opus`/`sonnet`) would break single-file Cursor compatibility for that persona. Inherit keeps every profile a straight copy into Cursor.

## Compatibility matrix (verified June 2026)

| Harness | Single file works? | What to do |
| --- | --- | --- |
| **Claude Code** | ✅ native | source of truth — `agents/` symlinked into `~/.claude/agents/` |
| **Cursor** (2.4+, `.cursor/agents/`) | ✅ straight copy | already symlinked (`.cursor/agents` → `agents/`); `tools:`/`color:` are silently ignored, `name`+`description` align, `model: inherit` is the shared value. See [`CURSOR_SETUP.md`](CURSOR_SETUP.md). |
| **OpenCode** (`.opencode/agents/`) | ❌ fork | `tools` value-type (boolean map) and `model` format (`anthropic/…`) are irreconcilable with CC — apply the recipe below |
| **Antigravity** (`.agents/agents.md`) | ❌ fork | no per-file persona format — collapse to prose sections per the recipe below |

**Bottom line:** write once for **Claude Code + Cursor**; **OpenCode** and **Antigravity** each need a generated artifact.

### Downstream-consumer safety

Projects that consume mind-vault (e.g. teisutis) and reference personas by their display name (`AGENT_backend`) or by file path (`agents/AGENT_backend.md`) are **unaffected** by the `mv-` dispatch ids:

- File paths are unchanged — the profiles keep their `AGENT_*.md` filenames (CC dispatches on the frontmatter `name:`, not the filename).
- An unknown `subagent_type` degrades gracefully: the orchestrating skill falls back to reading the persona file inline (the pre-existing behaviour), so nothing breaks if a host hasn't picked up the `mv-` registration yet.

## Fork recipe — OpenCode

Target: `~/.config/opencode/agents/<id>.md` (global) or `.opencode/agents/<id>.md` (project). OpenCode derives the id from the **filename**, so name the file `mv-backend.md`.

| CC field | OpenCode transform |
| --- | --- |
| `name: mv-backend` | **drop** — filename is the id (`mv-backend.md`) |
| `description:` (+`<example>`) | keep a **one-line** description; OpenCode doesn't use `<example>` blocks for triggering — trim them or leave them in the body |
| `model: inherit` | **omit** (uses OpenCode's default model) or set a provider-prefixed string, e.g. `anthropic/claude-sonnet-4-20250514` |
| `color: blue` | keep — `color:` is supported |
| `tools: Read, Grep, Bash, …` | convert to a **boolean map** `{read: true, grep: true, bash: true, …}` (or migrate to the newer `permission:` map of `allow`/`ask`/`deny`) |
| — | **add** `mode: subagent` |
| — | optional: `temperature: 0.1` |

**Worked example** — `agents/AGENT_backend.md` (CC) → `.opencode/agents/mv-backend.md` (OpenCode):

```yaml
---
description: Django server-side implementation — models, DRF viewsets, ORM optimization, kill N+1s.
mode: subagent
model: anthropic/claude-sonnet-4-20250514   # or omit to inherit OpenCode's default
temperature: 0.1
color: blue
tools:
  read: true
  grep: true
  glob: true
  bash: true
  write: true
  edit: true
---

<same persona body as AGENT_backend.md>
```

Map the CC tool names to OpenCode keys: `Read→read`, `Grep→grep`, `Glob→glob`, `Bash→bash`, `Write→write`, `Edit→edit`. CC `TodoWrite`/`WebFetch`/`WebSearch` have no boolean-map equivalent — drop them (OpenCode exposes its own tool set).

## Fork recipe — Antigravity

Antigravity has **no per-file persona format**. Personas are prose `## Name (@handle)` sections inside one shared file: `.agents/agents.md`. Collapse all eight profiles into sections; tool/model frontmatter is dropped, and per-role file-modify scope (if you want it) is declared in `AGENTS.md` prose per Antigravity convention.

**Worked example** — `.agents/agents.md`:

```markdown
# Agent Team

## Backend Engineer (@backend)

Use for Django server-side implementation — models, migrations, DRF viewsets,
Channels, Celery tasks, and ORM optimization (select_related / prefetch_related,
killing N+1s, service-layer extraction).

<persona body from agents/AGENT_backend.md>

## Frontend Engineer (@frontend)

Use for templates, HTMX partials, Alpine.js state, Bulma components, static
assets, and JS. Enforces server-driven UI and accessibility.

<persona body from agents/AGENT_frontend.md>

## ... (remaining six personas as further sections)
```

The handle (`@backend`) is how you summon the persona in Antigravity chat. There is no tool-scoping field; restrict capability via the `AGENTS.md` "which roles may modify which files" prose instead.

## Regenerating after a body change

The canonical profile bodies live only in `agents/AGENT_*.md`. When you edit a persona's body or description:

1. Claude Code + Cursor pick it up automatically (shared symlinked file).
2. Re-run the OpenCode transform for any `.opencode/agents/<id>.md` you maintain.
3. Re-paste the section into `.agents/agents.md` for any Antigravity setup.

Forks are **derived artifacts** — never edit them as the source. If a fork needs a behaviour the canonical profile lacks, change the canonical profile first, then regenerate.

## Sources

- Claude Code subagents — in-repo examples `~/.claude/plugins/.../feature-dev/agents/*.md`, `.../plugin-dev/agents/agent-creator.md`
- OpenCode Agents — <https://opencode.ai/docs/agents/> · Permissions — <https://opencode.ai/docs/permissions/>
- Cursor Subagents — <https://cursor.com/docs/context/subagents> · Background Agent — <https://docs.cursor.com/background-agent>
- AGENTS.md vs CLAUDE.md vs Cursor (2026) — <https://codersera.com/blog/agents-md-vs-claude-md-vs-cursor-rules-comparison-2026/>
- Antigravity pipelines codelab (`agents.md` / skills / workflows) — <https://codelabs.developers.google.com/autonomous-ai-developer-pipelines-antigravity>
- Antigravity agent docs — <https://antigravity.google/docs/agent>
