---
stage: plan
slug: mind-vault-cc-plugin
created: 2026-06-07
source: ./IDEA-017-mind-vault-as-claude-code-plugin.md
status: ready
project: mind-vault
architect_review: "🟡 REQUIRES ABSTRACTION → all 7 findings folded (2026-06-07): F1 load-rules-vs-rules-out-of-band contradiction (Q5 + exec step 5), F2 per-depth SKILL_CONTRACT repoint table + link-resolution gate, F3 namespacing blast-radius + canonical-note decision (Q3), F4 6-command verification, F5 guard-honesty (one-directional/dev-loop-exempt, Q4), F6 source './' , F7 update-cadence consequence (Q1). Verifies sound on repo-root-as-plugin-root, auto-discovery, coexist, source pointer."
---

# IDEA-017: mind-vault as a Claude Code plugin (additive / coexist)

## Context

mind-vault is distributed into agent hosts by a fleet of per-host symlink scripts
(`scripts/setup-{claude-code,cursor,opencode,vscode-copilot,antigravity}-symlinks.sh`
+ `_symlink-lib.sh`). The mechanism works but carries a per-machine, per-skill,
per-host tax. Claude Code now ships a **native plugin system** — skills + commands
+ agents bundled under a `.claude-plugin/plugin.json`, installed via `/plugin`.
That is the *intended* distribution mechanism for exactly what mind-vault is.

This plan makes mind-vault installable as a first-class CC plugin **as an additive
channel** — a single `/plugin marketplace add infohata/mind-vault` for **new**
machines — while leaving the existing symlink path **fully intact** for machines
already wired that way (no migration ceremony). Decided with the user 2026-06-07:
**coexist, no CC-script trim.** Rationale: trimming `setup-claude-code-symlinks.sh`
would break existing machines' re-run path (the opposite of "no ceremony"); the
plugin is a parallel install path, picked per-machine.

Grounded throughout by the research spike:
[`2026-06-07-idea-017-plugin-research-spike.md`](./2026-06-07-idea-017-plugin-research-spike.md)
(migrated into this archive dir from the IDEA-016 archive where it was run).

## Problem Frame

- **Per-machine, manual.** Each host re-runs `setup-<host>-symlinks.sh` after clone
  and again whenever a skill/command/agent is added (the `/land` skill once went
  dark this way). A plugin's `/plugin install` + auto-update removes that for CC.
- **Per-skill symlink growth.** The CC install surface grows with every skill. A
  plugin bundles them under one manifest.
- **No CC-native install for fresh machines.** Today a new CC box needs the repo
  cloned + the script run. A private-marketplace plugin is one command.

The plugin only ever covers the **CC host's skills/commands/agents slice** — it is
additive, not a replacement (research §E/§D: `rules/`, `docs/rules/`, statusline
have no plugin home; non-CC hosts have no plugin system at all).

## Requirements Trace

- **R1.** mind-vault is installable on a fresh CC host with no prior symlink setup,
  via a **private** path — `/plugin marketplace add infohata/mind-vault` then
  `/plugin install mind-vault@<marketplace>` — with **no public marketplace
  submission** (research §B).
- **R2.** A `.claude-plugin/plugin.json` at repo root makes `skills/`, `commands/`,
  `agents/` auto-discovered as plugin components (research §1).
- **R3.** A `.claude-plugin/marketplace.json` at repo root lists mind-vault as a
  private-installable plugin (research §1 marketplace schema).
- **R4.** `agents/` contains **only the 8 real `AGENT_*.md`** after this work, so
  the plugin loads exactly 8 agents — `SKILL_CONTRACT.md` (a non-agent) moves out,
  and **every reference to it is repointed** (a stray non-agent `.md` in `agents/`
  is loaded as a bogus agent — research §3; this also fixes the *same latent bug*
  in today's symlink path, where `mv_link_tree agents` symlinks it into
  `~/.claude/agents/`).
- **R5.** The working-tree dev loop survives with **no build/publish step** —
  documented via `--plugin-dir ~/projects/mind-vault` + `/reload-plugins`
  (research §A).
- **R6.** `setup-claude-code-symlinks.sh` is **unchanged** (coexist): existing
  machines keep working, re-runs still link skills/commands/agents/rules/docs-rules/
  statusline. `rules/`, `docs/rules/`, and statusline remain script-wired on both
  paths (no plugin home — research §C/§E).
- **R7.** The **double-load trap is documented and guarded**: on a single CC
  machine, use the plugin **or** the symlink script, not both. Docs state this; an
  optional light guard in `setup-claude-code-symlinks.sh` warns if the plugin is
  already installed.
- **R8.** Non-CC host scripts (`setup-{cursor,opencode,vscode-copilot,antigravity}-symlinks.sh`,
  `_symlink-lib.sh`) are **untouched** (research §D).
- **R9.** Docs (README, AGENTS.md, ONBOARDING) gain a "Install as a Claude Code
  plugin" path alongside the existing symlink path, and state the namespacing
  consequence (R-note below).

## Scope Boundaries

**In scope:**

- `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` (repo root).
- `agents/SKILL_CONTRACT.md` relocation + all reference repoints (R4).
- Plugin-readiness audit of the 8 `AGENT_*.md` frontmatter (no `hooks`/`mcpServers`/
  `permissionMode` — disallowed for plugin agents, research §1).
- **`commands/load-rules.md` fix** so it resolves `rules/` from the repo on the
  plugin path (architect F1).
- Install + dev-loop + coexist docs; the **canonical namespacing note** (architect
  F3); best-effort double-load guard in the CC script.

**Out of scope (deliberate, coexist):**

- **Trimming `setup-claude-code-symlinks.sh`** — would break existing machines'
  re-run (user decision). The research's partial-dissolve trim is explicitly NOT done.
- Force-migrating existing machines off symlinks.
- Repackaging `rules/` as an always-fire skill (research §C option) — rules stay
  out-of-band; revisit only if the out-of-band channel proves insufficient.
- Any non-CC host plugin equivalent (none exists).

**Explicit non-goals:**

- Not publishing to a public marketplace (`claude-plugins-official` / `claude-community`).
- Not changing skill/command/agent *content* — purely a packaging layer + the one
  agents/ hygiene move.

## Context & Research

### Decisive research findings (from the spike — read it for sourcing)

- **Manifest:** `.claude-plugin/plugin.json`, `name` the only required field;
  `skills/`/`commands/`/`agents/` auto-discovered at repo root. mind-vault's
  `skills/<name>/SKILL.md` + `commands/*.md` shapes are **already plugin-native**.
- **Dev loop preserved:** `--plugin-dir ./path` + `/reload-plugins`; `@skills-dir`
  in-place live edit. No build step.
- **Private install:** local-path or `infohata/mind-vault` git shorthand; no public
  marketplace.
- **rules/ has no plugin home; `../docs/rules/` relative links are stripped on
  install** → rules + docs/rules stay script-wired.
- **Partial-dissolve (§E):** plugin absorbs skills/commands/agents for CC; `rules/`,
  `docs/rules/`, statusline cannot be absorbed → the CC script stays (and, in
  coexist, is not even trimmed).

### Repo facts (measured 2026-06-07)

- `agents/` = 8 `AGENT_*.md` + **`SKILL_CONTRACT.md`** (the only non-agent file).
  `persona-dispatch.md` is already at `skills/work/references/` (no move needed).
- `SKILL_CONTRACT.md` referrers (~14): all 8 `AGENT_*.md`, `AGENTS.md`, `README.md`,
  `docs/guides/AGENT_PORTABILITY.md`, `docs/ideas/README.md`,
  `skills/laravel-frontend/SKILL.md`, `skills/work/references/persona-dispatch.md`
  (+ `CHANGELOG.md` historical — leave). `git grep -l SKILL_CONTRACT` is the gate.
- No existing `.claude-plugin/`.
- `setup-claude-code-symlinks.sh` links: skills (per-dir), commands, agents, rules,
  docs/rules, statusline.

### Institutional learnings

- [`RULE_cross-idea-amendments`](../../../rules/RULE_cross-idea-amendments.md) —
  moving `SKILL_CONTRACT.md` **amends IDEA-014** (which created it). Tag the commit,
  refresh the file's inline comment, backref IDEA-014's archive (all four steps).
- [`RULE_rename-before-drop`](../../../rules/RULE_rename-before-drop.md) — the move +
  ~14-reference repoint: move first, repoint all, grep-gate (`git grep agents/SKILL_CONTRACT`
  = 0 outside CHANGELOG/archive), then it's a doc move (no separate drop commit needed
  — the move *is* the drop, but verify no stale path remains).
- [`AGENT_PORTABILITY.md`](../../guides/AGENT_PORTABILITY.md) — the canonical agent
  frontmatter (`name`/`description`/`model: inherit`/`color`/`tools`) is already
  plugin-allowed; confirm none drifted to `hooks`/`mcpServers`/`permissionMode`.

## Key Technical Decisions

- **Coexist, no CC-script trim.** Plugin is an additive CC install path; the symlink
  script stays whole. Picked per-machine. (User decision; rationale in Context.)
- **Repo root IS the plugin root.** `skills/`/`commands/`/`agents/` already sit at
  root → drop `.claude-plugin/` beside them; zero relayout.
- **`SKILL_CONTRACT.md` → `skills/work/references/`.** Co-located with
  `persona-dispatch.md` (the other agent-orchestration reference already linked from
  agent profiles) — consistent precedent for agent-profile → `skills/work/references/`
  cross-links. (Q2.)
- **rules/ stays out-of-band.** Surfaced via `~/.claude/CLAUDE.md` references, as
  today. The plugin cannot carry always-on rules.
- **Plugin `name: mind-vault`** → commands namespace to `/mind-vault:<cmd>`. Skills
  are description-invoked (unaffected); only slash-commands gain the prefix. (Q3.)

## Open Questions

- **Q1. `version` in `plugin.json` — mirror the CHANGELOG (`5.1.0`) or omit?**
  - **Default:** **omit** — on a git source, every commit counts as an update
    (research §1), which matches mind-vault's rolling-library nature and adds no
    per-release bump discipline. (Downside: no pinnable plugin version; acceptable
    for a private single-consumer lib.)
  - **Trade-off:** setting `5.1.0` gives pinning + explicit updates but means every
    release MUST bump `plugin.json` too (a new `/wrap` Step-4b obligation).
  - **Consequence either way (architect F7):** with auto-update on, plugin-path
    machines track `main` *per-commit*; symlink-path machines update only on manual
    `git pull`. The two channels have **different update latency by design** —
    acceptable for a single-consumer private lib, stated so it's not a surprise.
- **Q2. `SKILL_CONTRACT.md` destination? — ✅ RESOLVED (user, 2026-06-07):**
  `skills/work/references/SKILL_CONTRACT.md` (beside `persona-dispatch.md`). The
  phantom-agent gets a proper home.
- **Q3. Command namespacing — accept `/mind-vault:<cmd>`, or pick a short plugin
  name (e.g. `mv` → `/mv:wrap`)?** **Blast radius (architect F3):** the workflow
  chain and dozens of skill/command bodies reference siblings by **bare** slash name
  (`/plan`, `/compound`, `/wrap`, `/review-loop`, `/land`, `/work`, "`/plan` alias"
  in `commands/brainstorm.md`, etc.). Under the **plugin** path *every* bare in-prose
  invocation is the wrong thing to type — it's `/mind-vault:wrap`. Skills still
  *fire* (description-invoked, channel-agnostic); only literal slash-command typing
  breaks. The 6 commands affected: `brainstorm, create-pr, git-status, load-rules,
  review-loop, test` (+ the skill-hybrids `/wrap /plan /work /land /compound /idea`).
  - **Default:** `mind-vault`, and **do NOT rewrite skill bodies channel-aware**
    (reject the specific for the generic). Instead add **one prominent canonical
    note** — "On the plugin path, prefix every mind-vault slash command with
    `mind-vault:` (`/mind-vault:wrap`); skill triggers are unaffected" — in README +
    ONBOARDING, and leave bodies as-is.
  - **Trade-off:** `mv` (`/mv:wrap`) is terser typing but less self-evident in the
    `/plugin` UI list. Rewriting 20+ bodies to be channel-aware is rejected outright
    (un-maintainable; the symlink path is still canonical for existing machines).
- **Q4. Double-load guard — script-side warning, or docs-only?** **Architect F5:**
  the guard is inherently **one-directional and best-effort** — `setup-claude-code-symlinks.sh`
  can warn *if the plugin is already installed* (plugin-then-script order), but the
  **script-then-plugin order is unguardable** (`/plugin install` has no hook into
  mind-vault's script). And `~/.claude/plugins` detection misses the `--plugin-dir`/
  `@skills-dir` dev-loop (those don't register there).
  - **Default:** **docs-first** — the canonical mitigation is the prose rule "CC: one
    channel per machine." Add a **light, best-effort, plugin-then-script** warning to
    the script and label it exactly that; explicitly exempt the dev-loop paths (a dev
    running both knows what they're doing).
  - **Trade-off:** a fuller guard is impossible from the script side; over-promising
    it would be worse than the honest docs rule.
- **Q5. `commands/load-rules.md` under the plugin path (architect F1).** It globs
  `rules/RULE_*.md` — but the plugin path does **not** carry `rules/` (no plugin
  home; R6/§C). So `/mind-vault:load-rules` on a plugin-only machine finds zero
  rules. A rules-loader shipping in a channel that omits rules is a real contradiction.
  - **Default:** make `load-rules` **resolve `rules/` from the mind-vault repo
    location** (it already needs the repo on disk) rather than the plugin's
    component tree, and have it **detect + warn** when no rules resolve — so it works
    on both paths. Document that rules themselves remain out-of-band regardless.
  - **Trade-off:** alternatively mark `load-rules` symlink-path-only and have it
    no-op-with-warning under the plugin — simpler but leaves a dead command in the
    plugin's command list. Resolve-from-repo is preferred (keeps the command useful).

## Execution Sequence

1. **Audit agent frontmatter (gate before packaging).** Confirm none of the 8
   `AGENT_*.md` declare `hooks` / `mcpServers` / `permissionMode` (disallowed for
   plugin agents). `grep -lE '^(hooks|mcpServers|permissionMode):' agents/AGENT_*.md`
   → expect empty. If any hit, fix before R2.
2. **Relocate `SKILL_CONTRACT.md` out of `agents/` (R4, amends IDEA-014).**
   `git mv agents/SKILL_CONTRACT.md skills/work/references/SKILL_CONTRACT.md` (Q2).
   **Repoint per-depth — NO blanket find-replace** (the new relative path differs by
   referrer location; a sed would also corrupt sibling links — see the
   `AGENT_architect.md` hazard below):

   | Referrer location | New link to `skills/work/references/SKILL_CONTRACT.md` |
   | --- | --- |
   | `skills/work/references/persona-dispatch.md` (now same dir) | `SKILL_CONTRACT.md` (was `../../../agents/SKILL_CONTRACT.md`) |
   | repo root — `README.md`, `AGENTS.md` | `skills/work/references/SKILL_CONTRACT.md` (no `../`) |
   | `agents/AGENT_*.md` (×8) | `../skills/work/references/SKILL_CONTRACT.md` |
   | `docs/guides/AGENT_PORTABILITY.md` | `../../skills/work/references/SKILL_CONTRACT.md` |
   | `docs/ideas/README.md` | `../skills/work/references/SKILL_CONTRACT.md` |
   | `skills/laravel-frontend/SKILL.md` | `../work/references/SKILL_CONTRACT.md` |

   **`AGENT_architect.md:38` hazard:** that line links *both* `SKILL_CONTRACT.md`
   (same-dir form, repoint it) *and* `../skills/work/references/persona-dispatch.md`
   (already correct — DO NOT touch). Edit the `SKILL_CONTRACT` link only.
   Leave `CHANGELOG.md` historical.
   Commit: `refactor(agents): IDEA-017 — move SKILL_CONTRACT.md out of agents/ for plugin agent-discovery` with an `Amends IDEA-014 <file:line> …` trailer.
   **Two gates** (the first catches stale paths, the second catches wrong-new paths
   that resolve nowhere — a grep for the old path can't):
   - `git grep -n 'agents/SKILL_CONTRACT' -- ':!CHANGELOG.md' ':!docs/archive/'` = 0.
   - **Link-resolution check:** for every file linking `SKILL_CONTRACT.md`, resolve
     the relative path from that file's dir and confirm it lands on the moved file.
3. **Add `.claude-plugin/plugin.json` (R2).** `name: mind-vault`, `description`,
   `author`, `homepage`/`repository`, `keywords`; `version` per Q1 (default omit).
   No `skills`/`commands`/`agents` keys needed (defaults auto-discover at root).
4. **Add `.claude-plugin/marketplace.json` (R3).** `name` (kebab public-facing),
   `owner`, `plugins: [{ name: "mind-vault", source: "./", description }]`. Use
   `"./"` (not `"."`) — the verified in-the-wild form from the `superpowers`
   marketplace (plugin-at-repo-root pattern; no self-reference/recursion — architect F6).
5. **Fix `commands/load-rules.md` for the plugin path (Q5, F1).** Make it resolve
   `rules/RULE_*.md` from the mind-vault **repo** location (not the plugin component
   tree) and **warn + no-op** if no rules resolve — so it works on both channels.
6. **Docs (R9).** README + AGENTS.md + `docs/guides/ONBOARDING.md`: add the "Install
   as a Claude Code plugin" path (`/plugin marketplace add infohata/mind-vault`),
   the `--plugin-dir` dev-loop, the **coexist note** ("CC: plugin OR symlink script,
   not both — best-effort guard only, see Q4"), the **one canonical namespacing note**
   (Q3 — "plugin path: prefix slash commands with `mind-vault:`; skill triggers
   unaffected"), and the statement that `rules/`/`docs/rules/`/statusline stay
   script-wired regardless.
7. **Best-effort double-load guard (R7, Q4).** Light non-fatal *plugin-then-script*
   warning in `setup-claude-code-symlinks.sh`; label it best-effort; exempt the
   `--plugin-dir`/`@skills-dir` dev-loop.
8. **`/wrap` backref (RULE_cross-idea-amendments step 3).** On wrap, append the
   `SKILL_CONTRACT.md` move backref to IDEA-014's archive.

## Verification

- **Plugin loads from working tree:** `claude --plugin-dir ~/projects/mind-vault`
  (or the session-equivalent) → skills discoverable, `/reload-plugins` works. **All 6
  commands appear namespaced (F4):** `/mind-vault:{brainstorm,create-pr,git-status,
  load-rules,review-loop,test}` — confirm each is present and none shadows a built-in
  CC slash command. (Manual — record in a verification log in this archive dir.)
- **`load-rules` works on the plugin path (Q5):** invoke `/mind-vault:load-rules`
  under `--plugin-dir` and confirm it resolves rules from the repo (or warns cleanly),
  not silently zero.
- **plugin.json valid:** `jq -e '.name' .claude-plugin/plugin.json` = `"mind-vault"`.
- **marketplace.json valid:** `jq -e '.plugins[0].source' .claude-plugin/marketplace.json`.
- **agents/ is plugin-clean:** `ls agents/*.md | wc -l` = 8; `ls agents/SKILL_CONTRACT.md` → absent.
- **No stale contract path:** `git grep -n 'agents/SKILL_CONTRACT' -- ':!CHANGELOG.md' ':!docs/archive/'` = 0.
- **Agent frontmatter plugin-safe:** `grep -lE '^(hooks|mcpServers|permissionMode):' agents/AGENT_*.md` = empty.
- **Coexist intact:** `setup-claude-code-symlinks.sh` diff = only the optional guard (if Q4 yes); skills/commands/agents/rules/docs-rules/statusline linking all still present. `bash -n` clean.
- **Non-CC scripts untouched:** `git diff --stat` shows no change to `setup-{cursor,opencode,vscode-copilot,antigravity}-symlinks.sh` / `_symlink-lib.sh`.

---

**Status:** ready — architect-reviewed (🟡 → all 7 findings folded). Q2 resolved
(`SKILL_CONTRACT.md` → `skills/work/references/`). Q1 (version omit), Q3 (namespacing
note), Q4 (best-effort guard), Q5 (load-rules resolve-from-repo) carry defaults —
surface at `/work` start for yes/no. Next: `/work docs/archive/2026-06-idea-017-mind-vault-cc-plugin/2026-06-07-mind-vault-cc-plugin-plan.md`.
