# IDEA-017 Plugin Research Spike (run during IDEA-016)

> **Status:** spike. Run on 2026-06-07 as an IDEA-017 (mind-vault-as-CC-plugin) research
> spike, executed inside IDEA-016 (scripts/tools taxonomy) to settle the
> `scripts/`-config-wiring decision. **Migrate this file to IDEA-017's archive dir at
> `/plan 017`.** It lives here because 016 needs the verdict in section E now.

## Sources surveyed

- <https://code.claude.com/docs/en/plugins> — "Create plugins" (quickstart, structure, dev-loop, migration). Note `docs.claude.com/.../claude-code/plugins` 301-redirects to `code.claude.com/docs/en/plugins`.
- <https://code.claude.com/docs/en/plugins-reference> — "Plugins reference" (manifest schema, skills-dir plugins, version mgmt, caching, CLI).
- <https://code.claude.com/docs/en/plugin-marketplaces> — "Plugin marketplaces" (marketplace.json schema, private-repo install, sources, seed dirs).
- Local installed plugins: `~/.claude/plugins/cache/claude-plugins-official/` — `superpowers/5.1.0/`, `skill-creator/`, `feature-dev/`, `frontend-design/`, `code-review/`, `code-simplifier/`. Read manifests + dir layout directly.
- mind-vault working tree: `scripts/setup-claude-code-symlinks.sh`, `skills/`, `commands/`, `agents/`, `rules/`.

## 1. Plugin manifest schema (`.claude-plugin/plugin.json`)

Manifest is **optional**; if present, `name` is the **only required field**. Lives at `<plugin-root>/.claude-plugin/plugin.json`. Everything else (skills/, commands/, agents/, hooks/, .mcp.json) sits at the **plugin root**, NOT inside `.claude-plugin/`.

```json
{
  "name": "plugin-name",            // REQUIRED. kebab-case. Namespaces components: /plugin-name:skill
  "displayName": "Plugin Name",     // optional, UI-only (v2.1.143+)
  "version": "1.2.0",               // optional. If set, MUST bump for users to get updates.
                                    //   If omitted on a git source, commit SHA = version (every commit = update)
  "description": "…",               // optional
  "author": { "name": "…", "email": "…", "url": "…" },
  "homepage": "…", "repository": "…", "license": "MIT", "keywords": ["…"],
  "skills":   "./custom/skills/",   // ADDS to default skills/  (string|array)
  "commands": ["./custom/x.md"],    // REPLACES default commands/ (string|array)
  "agents":   ["./agents/x.md"],    // REPLACES default agents/   (string|array)
  "hooks":    "./config/hooks.json",
  "mcpServers": "./mcp.json", "lspServers": "./.lsp.json",
  "experimental": { "themes": "./themes/", "monitors": "./monitors.json" },
  "dependencies": [ { "name": "secrets-vault", "version": "~2.1.0" } ]
}
```

**Component discovery — default locations at plugin root** (auto-scanned, no manifest entry needed):

| Component | Default location | How declared / discovered |
| :--- | :--- | :--- |
| Manifest | `.claude-plugin/plugin.json` | the only thing inside `.claude-plugin/` |
| Skills | `skills/<name>/SKILL.md` | auto-discovered; YAML frontmatter `description` drives model-invocation |
| Commands | `commands/*.md` (flat) | auto-discovered; "use `skills/` for new plugins" |
| Agents | `agents/*.md` | auto-discovered; frontmatter `name`/`description`/`model`/`tools`/`disallowedTools`/etc. `hooks`,`mcpServers`,`permissionMode` NOT allowed for plugin agents |
| Hooks | `hooks/hooks.json` | event-handler JSON (`PostToolUse`, `SessionStart`, … incl. `InstructionsLoaded`) |
| MCP / LSP | `.mcp.json` / `.lsp.json` | server configs |
| Monitors / Themes | `monitors/monitors.json` / `themes/` | experimental |
| Executables | `bin/` | added to Bash `PATH` while enabled |
| Settings | `settings.json` | only `agent` + `subagentStatusLine` keys honored |

Path rule worth noting: `skills` **adds to** the default `skills/`; `commands`/`agents`/`outputStyles`/`themes`/`monitors` **replace** their default dir.

**Marketplace catalog** (`.claude-plugin/marketplace.json`, separate repo-root file):

```json
{
  "name": "company-tools",                 // REQUIRED, public-facing, kebab-case
  "owner": { "name": "…", "email": "…" },  // REQUIRED (name required)
  "plugins": [                             // REQUIRED array
    { "name": "my-plugin", "source": "./plugins/my-plugin", "description": "…" }
  ]
}
```

`source` can be a relative path (`./…`), or an object: `github` (`repo`/`ref`/`sha`), `url` (git URL), `git-subdir` (`url`+`path`, sparse clone for monorepos), or `npm`. `metadata.pluginRoot` lets entries drop the `./plugins/` prefix.

## 2. Worked example — `superpowers` (verbatim)

`~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0/.claude-plugin/plugin.json`:

```json
{
  "name": "superpowers",
  "description": "Core skills library for Claude Code: TDD, debugging, collaboration patterns, and proven techniques",
  "version": "5.1.0",
  "author": { "name": "Jesse Vincent", "email": "jesse@fsck.com" },
  "homepage": "https://github.com/obra/superpowers",
  "repository": "https://github.com/obra/superpowers",
  "license": "MIT",
  "keywords": ["skills", "tdd", "debugging", "collaboration", "best-practices", "workflows"]
}
```

Observations directly relevant to mind-vault:

- **Bundles 14 skills** as `skills/<name>/SKILL.md` (brainstorming, executing-plans, writing-plans, systematic-debugging, test-driven-development, using-git-worktrees, writing-skills, …). This is exactly mind-vault's `skills/<name>/SKILL.md` shape — **already plugin-native.**
- Each `SKILL.md` is plain frontmatter (`name` + `description`) + body — identical to mind-vault skills.
- Versioned explicitly (`5.1.0`) and cached per-version at `…/superpowers/5.1.0/`. Contrast: `skill-creator`'s manifest omits `version` → cache path is `…/skill-creator/unknown/`.
- `skill-creator`'s manifest is even thinner — `name` + `description` + `author`, no version. Confirms how little is mandatory.
- Ships `hooks/` (e.g. `hooks-cursor.json` with a `sessionStart` runner) and `tests/` — plugins can carry arbitrary support dirs.
- **No CLAUDE.md / rules mechanism anywhere** in any installed plugin. Confirmed against docs (§C).

## 3. Layout-delta table (mind-vault → CC plugin)

| mind-vault today | plugin expectation | Match? | Gap / action |
| :--- | :--- | :--- | :--- |
| `skills/<name>/SKILL.md` + `references/` + `assets/` (21) | `skills/<name>/SKILL.md` + supporting files | ✅ exact | none — supporting files travel alongside SKILL.md |
| `commands/*.md` (slash commands, with frontmatter) | `commands/*.md` flat-file skills | ✅ shape matches | becomes namespaced `/mind-vault:create-pr` etc. Docs nudge new work to `skills/` but `commands/` still supported |
| `agents/AGENT_*.md` persona profiles | `agents/*.md` subagents | ⚠️ mostly | filename free, but plugin agents may NOT declare `hooks`/`mcpServers`/`permissionMode`. `agents/SKILL_CONTRACT.md` + `agents/persona-dispatch` refs are not agents — they'd need to move to a skill or `references/` (a stray non-agent `.md` in `agents/` is loaded as an agent) |
| `rules/RULE_*.md` (auto-loaded via `~/.claude/CLAUDE.md` refs) | **no native home** | ❌ gap | plugins have no always-on rules channel (see §C). Stays out-of-band or repackaged as an always-on skill |
| `docs/rules/*-rationale.md` (relative `../docs/rules/` links from rules) | n/a | ❌ | path-traversal outside plugin root is **stripped** on install (`../` not copied). Relative cross-links from a packaged rule/skill to `docs/` would break |
| `tools/`, `scripts/` (host wiring + utilities) | not a plugin concept (except `bin/`, `scripts/` for hooks) | partial | host-wiring scripts have no plugin analogue; runnable tools could live in `bin/` |
| per-host `setup-*-symlinks.sh` | n/a | ❌ | non-CC hosts have no plugin system (§D) |

## Decision questions

### A. Dev-loop survival — PRESERVED (and arguably better)

Two mechanisms keep a live working-tree edit→effect loop with **no build/publish step**:

1. **`--plugin-dir ./path`** loads a plugin straight from a working directory for the session; `/reload-plugins` picks up changes without restart. A `--plugin-dir` plugin **overrides** an installed same-named one for that session — ideal for dogfooding.
2. **Skills-directory plugins**: any folder under `~/.claude/skills/` (or `<cwd>/.claude/skills/`) containing `.claude-plugin/plugin.json` auto-loads as `<name>@skills-dir` with **no marketplace, no install, discovered in place** (not copied to cache). "Changes you make to a skill's `SKILL.md` take effect immediately in the current session." (Other components — hooks/.mcp.json/agents — need `/reload-plugins`.)

So the symlink-to-`~/.claude/skills/` dev loop mind-vault already uses *is* the supported `@skills-dir` path once a `.claude-plugin/plugin.json` sits at the root. Source: plugins-reference §"Skills-directory plugins", §"Test your plugins locally". **Caveat:** the in-place live-edit guarantee is strongest for `skills/`; agents/hooks still need a reload.

### B. Private-repo install — YES, no public marketplace required

Multiple no-publish paths (plugin-marketplaces §"Private repositories", §"Plugin sources", discover-plugins §"Add marketplaces"):

- **Local path:** `/plugin marketplace add ./my-marketplace` then `/plugin install x@name`. Pure filesystem, fine for a private checkout.
- **Private git URL / GitHub shorthand:** `/plugin marketplace add infohata/mind-vault` or a git URL. Manual install/update uses your existing git credential helpers (`gh auth login`, SSH agent). Background auto-update needs `GITHUB_TOKEN`/`GH_TOKEN` in env.
- **Skills-dir** (§A) needs no marketplace at all.

A private repo needs a `.claude-plugin/marketplace.json` at its root listing the plugin (or be added as a skills-dir plugin). No submission to `claude-plugins-official`/`claude-community` is involved.

### C. `rules/` handling — NO native always-on home; stays out-of-band

Decisive quote (plugins-reference §"Plugin directory structure"):

> "A `CLAUDE.md` file at the plugin root is **not loaded as project context**. Plugins contribute context through skills, agents, and hooks rather than CLAUDE.md. To ship instructions that load into Claude's context, put them in a [skill]."

So a plugin has **no channel equivalent to mind-vault's auto-loaded `RULE_*.md`**. Options, none equal to today's behavior:

- Repackage rules as a **skill** with an aggressive always-fire description (the superpowers `using-superpowers` pattern — "if there's a 1% chance it applies, invoke it"). Model-invoked, not guaranteed-loaded; weaker than a CLAUDE.md reference.
- Keep `RULE_*.md` exactly as today, surfaced via `~/.claude/CLAUDE.md` content references — **fully out-of-band of the plugin.**

Hooks are NOT a substitute: the `InstructionsLoaded` hook only *fires when* a CLAUDE.md/`.claude/rules/*.md` loads — it observes rule loading, it does not inject always-on rule text. Precise answer: **rules stay out-of-band; the plugin cannot carry them as always-on guardrails.**

Note also the path-traversal limitation: rules' `../docs/rules/*-rationale.md` relative links point outside any plugin root and would be **stripped on install** — another reason `rules/` + `docs/rules/` stay outside the plugin boundary.

### D. Non-CC hosts — NO plugin system; symlink scripts stay

Confirmed: the `.claude-plugin` manifest, `marketplace.json`, and `/plugin` CLI are **Claude Code-specific**. Cursor, OpenCode, Antigravity, and VS Code Copilot have no equivalent installer for this format. (Quick verification, not exhaustive: the entire spec lives under code.claude.com/Claude Code docs; superpowers ships a *separate* `hooks-cursor.json` + `GEMINI.md` precisely because each host needs bespoke wiring — there is no shared plugin standard.) Therefore `setup-cursor-symlinks.sh`, `setup-opencode-symlinks.sh`, `setup-antigravity-symlinks.sh`, `setup-vscode-copilot-symlinks.sh`, and `_symlink-lib.sh` **all remain necessary** regardless of CC plugin adoption.

### E. **Does adopting the CC plugin DISSOLVE `setup-claude-code-symlinks.sh`?**

**VERDICT: PARTIALLY DISSOLVES.**

The script does five distinct jobs (see `scripts/setup-claude-code-symlinks.sh`). The plugin format absorbs three and **cannot** absorb two:

| Job in `setup-claude-code-symlinks.sh` | Absorbed by plugin? |
| :--- | :--- |
| `mv_link_skills_per_dir → ~/.claude/skills` | ✅ YES — plugin `skills/` (or `@skills-dir`) carries these natively |
| `mv_link_tree commands → ~/.claude/commands` | ✅ YES — plugin `commands/` |
| `mv_link_tree agents → ~/.claude/agents` | ✅ MOSTLY — plugin `agents/` (after moving non-agent `.md` like `SKILL_CONTRACT.md` out of `agents/`) |
| `mv_link_tree rules → ~/.claude/rules` | ❌ NO — no always-on rules channel (§C). Must stay symlinked + referenced from `~/.claude/CLAUDE.md` |
| `mv_link_tree docs/rules → ~/.claude/docs/rules` | ❌ NO — rule-rationale relative links; outside any plugin root, stripped on install (§C) |
| `statusline-command.sh` symlink + `settings.json` snippet | ❌ NO — status line is a `settings.json` host config, not a plugin component (`settings.json` in a plugin only honors `agent`/`subagentStatusLine`) |

So adopting the plugin lets the **skills/commands/agents** thirds of the script retire **for the CC host**, but a residual CC wiring script (or trimmed version) **must survive** to handle `rules/` + `docs/rules/` + statusline. The script is not fully obsolete — it shrinks.

## Recommendation for IDEA-016's `scripts/` decision

**Choose option (a): leave `scripts/` config-wiring untouched now + drop a short deferral README.** Rationale:

1. **The CC symlink wiring does NOT fully dissolve (§E).** Even a fully-adopted plugin leaves `rules/`, `docs/rules/`, and statusline needing a host script. Dissolving `scripts/` config-wiring in 016 would orphan those.
2. **Non-CC hosts keep all their symlink scripts unconditionally (§D).** `scripts/` remains a live, multi-host concern no matter what 017 decides — it is not a "legacy to retire" directory.
3. **017 is real and ergonomically viable (§A/§B)** — `@skills-dir` + `--plugin-dir` preserve the live-edit loop, and private install works — so 016 should *not* pre-empt the design. But the plugin only ever covers the CC host's skills/commands/agents slice; it is an **additive distribution channel**, not a replacement for `scripts/`.
4. Concretely for 016: keep `scripts/` taxonomy as-is; add a `scripts/README.md` (or section) noting "CC-plugin packaging (IDEA-017) may later retire the skills/commands/agents portion of `setup-claude-code-symlinks.sh`; rules/, docs/rules/, statusline, and all non-CC host scripts stay regardless." Defer any `setup-claude-code-symlinks.sh` slimming to IDEA-017's implementation, where the agents/-cleanup (move `SKILL_CONTRACT.md` out of `agents/`) and the rules-channel question get designed together.
