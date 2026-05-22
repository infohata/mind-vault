---
name: skill-writer
description: Author or refactor `.md` skills and rules for AI coding agents — enforces YAML frontmatter schema, trigger-phrase quality, length budgets, and the references/assets progressive-disclosure layout.
---

# skill-writer

Meta-skill that governs how AI agents author and refactor skills (and rules) inside `mind-vault` or any sibling repository that follows the same convention. Fully IDE-agnostic: the same rules apply whether the invoking host is Claude Code, Cursor, Antigravity, OpenCode, Copilot, or any other skill-aware agent.

## When to use

**TRIGGER when:** user asks to "create/add/write a new skill", "extract a pattern into mind-vault", "formalize an AI codebase rule", "refactor a skill"; or when reviewing/rewriting any file matching `skills/*/SKILL.md` or `rules/RULE_*.md`.

**SKIP for:** one-off prose docs, changelogs, READMEs, ADRs, or in-project configuration files — these are not agent-invoked skills and do not need the `SKILL.md` contract.

## File layout

A skill lives in its own folder whose name is the skill slug:

```text
skills/
└── <skill-slug>/
    ├── SKILL.md              # Pattern body (required, target <500 lines)
    ├── references/           # Long examples, configs, deep-dive docs (loaded on demand)
    │   └── *.md
    ├── assets/               # Templates/snippets the agent emits verbatim
    │   └── *.{py,sh,yml,…}
    └── scripts/              # Executable helpers the agent runs
        └── *.sh
```

- **Filename must be `SKILL.md`** (uppercase). Lowercase `skill.md` is not discovered by most hosts.
- **Folder name = `name:` frontmatter field**, kebab-case, no `skill-` prefix (the folder is already under `skills/`).

## Frontmatter contract

**Required minimum:**

```yaml
---
name: <kebab-case-slug>         # matches folder name
description: <one-line trigger> # <200 chars, noun-dense
---
```

**Optional on larger skills** (use when the skill is versioned, replaces older skills, or needs provenance):

```yaml
license: MIT
metadata:
  author: mind-vault
  version: "1.0"
  replaces:
     - <older-skill-name>
```

### Writing the `description`

The description is the **probabilistic trigger** — the only text the host agent inspects when deciding whether to load the skill. Bad descriptions = skill never fires, or fires on the wrong turns.

**✅ DO — noun-dense, names the concrete stack, specific verbs:**

- `Apply global cross-project Django backend dev conventions for models, views, signals, Channels, DRF, and all backend architecture before hitting templates or JS.`
- `Debug failing tests quickly across any massive Python monolith by surgically specifying and running targeted test paths instead of running full, slow test suites locally.`
- `Search outside the project (in IDE plans, AI agent workspaces, or temporary storage) and retrieve standalone artefacts, research, or validation logs to bring them inside the project repository.`

**❌ DON'T — generic, verb-only, hand-wavy, or buzzword soup:**

- `A skill for helping write frontend code.`
- `Helps with Django stuff.`
- `Enforce robust anchor store bounding box triggers for elite deployment excellence.`

### TRIGGER / SKIP expansion

For skills that fire frequently and misfire often (language-specific, stack-specific, or tool-specific skills), add an explicit `TRIGGER when / SKIP` block at the top of `## When to use`. Example from `claude-api`:

```text
TRIGGER when: code imports `anthropic`/`@anthropic-ai/sdk`; user asks for the
Claude API, Anthropic SDK, or Managed Agents; user adds/modifies/tunes a Claude
feature (caching, thinking, compaction, tool use, batch, files, citations,
memory) or model (Opus/Sonnet/Haiku) in a file.
SKIP: file imports `openai`/other-provider SDK; filename like `*-openai.py`/
`*-generic.py`; provider-neutral code; general programming/ML.
```

This is load-bearing: it gives the host agent a crisp decision rule instead of vibes, and it's the single biggest lever against false-positive skill activation.

## Body structure

Canonical `SKILL.md` body, in order:

1. `# <title>` + one-paragraph **Overview** (what this skill covers; what it does not).
2. `## When to use` — scoping rules, with TRIGGER/SKIP block if applicable.
3. `## Pattern` — the actual conventions, numbered or named subsections.
4. `## When NOT to use these patterns` — counter-cases that prevent over-application.
5. `## References` — the **single** canonical list of links to `./references/*.md`, external docs, and related skills. **Maintain only one such block per skill.** Do not duplicate it under aliases like `**Optional extensions**`, `**Further reading**`, or a front-loaded mirror near the top of the file — every line of `SKILL.md` is loaded into context on every activation, so duplicated lists double the bill for the same information. If a reference must be foreshadowed early in the body (e.g. inside `## Critical hazards`), link to it inline at the point of mention rather than re-listing it. (Several feature-dense skills — `django`, `django-frontend`, `deployment` — historically carried both a top "Optional extensions" block and a bottom `## References` block; consolidate on `## References` when touching them.)
6. **No trailing `**Last Updated**: YYYY-MM-DD` footer.** File mtime + `git log` carry the date for free; a literal trailer costs ~10 tokens on every activation for information the host can derive from the filesystem. History lives in `CHANGELOG.md`.

## The additive-only rule

Skills document **deviations from default LLM knowledge**, not generic programming advice.

- ❌ Don't explain "what Django is" or "how to write a for-loop".
- ❌ Don't re-document framework basics (`pip install`, `git commit`, `npm run build`).
- ✅ Do document: project-specific conventions, non-obvious ordering constraints, workarounds for known bugs, mixin/base-class contracts, required Makefile targets, opinionated stack choices, negative patterns learned from incidents.

The host agent already knows `pip install -r requirements.txt`. It does not know that _this_ repo forbids manual `.po` edits and uses a map-based fill workflow. Write the latter.

## The ✅ DO / ❌ DON'T matrix

Every non-trivial convention must include an explicit counter-example. This bounds the agent's guessing space — without the negative side, agents "revert to mean" and produce idiomatic-but-wrong output.

```text
✅ DO: Use `filter(None, [...])` + `"\n".join(...)` to build optional-prefix strings.
❌ DON'T: Use ternaries or `if/else` append-vs-replace logic.
```

```text
✅ DO: `prefetch_related("content_object")` when iterating models with GenericForeignKey.
❌ DON'T: Access `.content_object` in a loop without prefetch — N+1 storm.
```

## Length budget & progressive disclosure

**Target: `SKILL.md` under 500 lines. Hard stop: ~800 lines.**

When a skill outgrows the budget:

1. Move long code examples into `references/<TOPIC>.md` and link to them.
2. Move large templates/snippets into `assets/<name>.<ext>` and instruct the agent to read them via tool.
3. Keep the `SKILL.md` body focused on **decisions, contracts, and pointers**. Details load on demand.

```markdown
<!-- ✅ SKILL.md stays lean -->
### WebSocket support
See [references/ASYNC_WEBSOCKET.md](references/ASYNC_WEBSOCKET.md) for Channels
routing, consumers, and tenant-aware auth middleware.

<!-- ❌ SKILL.md bloating -->
### WebSocket support
<100 lines of consumer code, routing setup, middleware config…>
```

Why this matters: every line of `SKILL.md` is loaded into context on every activation. A 1000-line skill spends context budget the downstream task could have used.

## Prose density — payload over framing

Skills (and references) are token-priced on every activation. Cut explanatory prose to minimum without dropping payload. Compound runs naturally overwrite because the author is mid-context; a tighten-pass before commit collapses it.

**After authoring a new skill/reference, do a tighten-pass targeting ≥30% line reduction.** Payload-intact: every code snippet, every numbered trap, every decision rule, every cross-link survives. Only framing prose collapses.

✅ Keep: code blocks; trap-name + one-sentence mechanism; "don't do X — do Y" lines; cross-references; concrete numbers (file counts, wall-time, version pins).

❌ Cut: paragraph framing ("The pieces below are…", "none of this was obvious from…"); re-statements of a bullet's content in surrounding prose; triple-framed "why this matters" expansions where the rule already implies the why; parallel-clause cascades in References-list pointer lines (one topic clause + one payload clause is enough).

Apply identically to `references/<TOPIC>.md` files — references aren't free, they cost on demand and the user reads them. A 200-line reference that says the same thing in 100 lines is strictly better.

## Cross-project portability

A skill in `mind-vault` is consumed by multiple projects. Therefore:

- **Concrete project names in the pattern body are leaks.** If the pattern says "Project X uses Y" as a universal rule, the rule is wrong for every other project. Either generalise ("Projects with constraint Y should Z") or clearly fence as an example.
- **Examples may name real projects**, but must be visually fenced:
  > Example (project-foo): the translation map lives at `tools/translation_maps/*.py`.
- **Never hard-code paths from a consuming project** in `References`. `docs/artefacts/by-agent/researcher/…` paths do not exist from the agent's perspective when invoked from a sibling project.
- **Never hard-code relative paths in templates the skill emits** when the skill supports multiple source locations. A template that writes `[docs/ideas/](../ideas/)` only works when the source file lives at `docs/execution/...`; it breaks for `docs/IDEAS.md` or root-level `IDEAS.md`. Parameterise with placeholders (`<IDEAS_REL>`), derive the path from the actual source location at emit time, and include a worked-examples table for the common cases. See [references/emitted-templates.md](references/emitted-templates.md) for the full rule + DO/DON'T.

## Skills vs commands — no thin wrappers

A skill with `name: X` in its frontmatter is already invocable as `/X` — hosts that support slash menus surface the skill directly. Creating a `commands/X.md` that just says "Invoke the `X` skill" duplicates the slash entry (both appear side-by-side in the menu) without adding any behaviour.

**Write a `commands/*.md` file only when:**

- No same-named skill exists and the command carries its own behavioural spec, OR
- The command is a deliberate **alias** for another skill (e.g. `/brainstorm` → `/plan`), where the distinct name communicates intent the skill's own slug can't.

**Don't:**

- Write a `commands/X.md` whose body is "Invoke the `X` skill. See `skills/X/SKILL.md`." — it's a redundant registration surface; delete it and trust the skill's own slash-menu entry.
- Duplicate the skill's `description` in the command frontmatter with slight rewording — drift becomes a maintenance burden and users see both entries with near-identical descriptions, which reads as noise.

```text
✅ DO: skill at `skills/plan/SKILL.md` with `name: plan` → `/plan` appears once in slash menu.
✅ DO: standalone command `commands/brainstorm.md` aliasing `/plan` — different intent framing, no skill equivalent.
❌ DON'T: `commands/plan.md` that says "Invoke the `plan` skill" → `/plan` now appears twice.
```

The failure mode surfaced as double slash-menu entries across 8 mind-vault names (`compound`, `idea`, `ideate`, `ingest-backlog`, `plan`, `sprint-auto`, `work`, `wrap`) where a thin command wrapper existed alongside the skill; dedup in PR #51.

## Maintaining skills

- **Don't add a trailing `**Last Updated**` footer.** File mtime + `git log` are the system of record; an inline date costs ~10 tokens per activation for info the host can derive for free. Narrative belongs in [`CHANGELOG.md`](../../CHANGELOG.md), keyed by the merging PR, where it costs zero context budget.
- If an example drifts out of sync with real code, fix it or delete it — stale examples are worse than none.
- When merging two skills, keep `metadata.replaces` so agents recognise old names.
- When deprecating a skill, leave a tombstone `SKILL.md` that points to the successor rather than deleting silently.

### Versioning (optional, sidecar file)

Anthropic's official Agent Skills spec defines no `version` field, and Anthropic's published skills (`github.com/anthropics/skills`) carry no version metadata. Most skills therefore don't need a version at all — `CHANGELOG.md` + `git log` is the system of record.

For feature-dense skills where a version handle is genuinely useful (a quick "are we on the same edition?" reading at a glance), use a **sidecar `VERSION` file** in the skill's directory:

```text
skills/django/
├── SKILL.md
├── VERSION          ← single line, e.g. "5.5\n"
├── references/
└── …
```

Why a sidecar:

- **Zero SKILL.md context cost.** The host loads `SKILL.md` (and references on demand), not arbitrary sibling files. A `VERSION` file is invisible to the host agent and free at activation time.
- **Easy to grep, easy to bump.** `cat skills/*/VERSION` shows the matrix; a pre-commit hook can read it.
- **Spec-neutral.** Adding a frontmatter `version:` field would conflict with the official spec the day Anthropic standardises one; a sidecar is plain ad-hoc tooling.

Bumping discipline: monotonic, project-defined (SemVer-ish or just `MAJOR.MINOR`). Bump on substantive pattern additions, not docs polish — the version handle should mean something.

Don't add a `VERSION` file to every skill. Add it only where the question "what edition am I reading?" actually arises — that's the threshold.

## Minimal skeleton

Copy this as the starting point for any new skill:

```markdown
---
name: my-skill
description: <one-line trigger under 200 chars, noun-dense, names the concrete stack>
---

# my-skill

Overview: what this pattern does, what stack it assumes, what it does not cover.

## When to use

TRIGGER when: <conditions>
SKIP: <conditions>

## Pattern

### 1. <First convention>

<short explanation>

✅ DO: <example>
❌ DON'T: <counter-example>

### 2. <Second convention>

…

## When NOT to use these patterns

- <case 1>
- <case 2>

## References

- [details](references/DETAILS.md)
- [Related skill](../other-skill/SKILL.md)

```

## References

- Adjacent examples in this repo: `skills/artefact-retrieval/SKILL.md`, `skills/surgical-tdd/SKILL.md` (lean), `skills/django/SKILL.md` (feature-dense)
- [Git Safety Rule](../../rules/RULE_git-safety.md) — applies to commits produced while authoring skills
- Anthropic's Claude Code Agent Skills documentation (`docs.claude.com`) — the official `SKILL.md` spec this skill aligns with
