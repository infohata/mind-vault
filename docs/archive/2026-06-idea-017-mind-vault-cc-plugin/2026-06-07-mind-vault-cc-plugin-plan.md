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
- **R11. `plugin.json` `version` mirrors the CHANGELOG, kept in sync by `/wrap`
  (Q1).** `plugin.json` carries an explicit `version` equal to the top CHANGELOG
  `## vX.Y.Z`. `/wrap` Step 4b — today **first-match-single-source** — must be
  generalised to recognise `.claude-plugin/plugin.json` as a version source **and to
  bump *all* sync-required locations together** (here: CHANGELOG + plugin.json), not
  just the first match. A version-consistency check (`plugin.json.version` == top
  CHANGELOG `## v`) is the stricter review gate. Design the wrap change **generically**
  (a project may declare N sync-required version files), not mind-vault-special-cased.
- **R12. Rules load on the plugin path (Q5).** Ship (a) a `/mv:load-rules` command
  that resolves `RULE_*.md` from `${CLAUDE_PLUGIN_ROOT}/rules/` (plugin) or repo
  (symlink) with a detect-and-warn, and (b) a `hooks/hooks.json` `SessionStart`
  **welcome note** that fires when the plugin is active, telling the user to run
  `/mv:load-rules`. Rules themselves remain out-of-band (no always-on channel), but
  the plugin path is now self-announcing and one command from loaded — not silently
  rule-less. (Stretch: auto-inject via `SessionStart` if supported — verify in `/work`.)

## Scope Boundaries

**In scope:**

- `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` (repo root).
- `agents/SKILL_CONTRACT.md` relocation + all reference repoints (R4).
- Plugin-readiness audit of the 8 `AGENT_*.md` frontmatter (no `hooks`/`mcpServers`/
  `permissionMode` — disallowed for plugin agents, research §1).
- **Rule-loading on the plugin path (R12, Q5):** `/mv:load-rules` resolving
  `${CLAUDE_PLUGIN_ROOT}/rules/` (plugin) or repo (symlink) + a `hooks/hooks.json`
  `SessionStart` welcome note prompting it. (Stretch: auto-inject if `SessionStart`
  supports it.)
- Install + dev-loop + coexist docs; the **canonical namespacing note** (architect
  F3); best-effort double-load guard in the CC script.
- **`skills/wrap/SKILL.md` Step 4b update (R11)** — multi-location version sync
  (recognise `.claude-plugin/plugin.json`; bump all sync-required sources together;
  add a CHANGELOG↔plugin.json consistency check). Generic, not mind-vault-special.

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
- **Plugin `name: "mv"` + `displayName: "Mind-Vault"`** → commands namespace to
  `/mv:<cmd>` (coherent with the `mv-` subagent prefix; research-verified clash-free),
  UI shows "Mind-Vault". Skills are description-invoked (unaffected); only
  slash-commands gain the prefix. (Q3.)

## Open Questions

- **Q1. `version` in `plugin.json` — ✅ RESOLVED (user, 2026-06-07): SET it, mirror
  the CHANGELOG.** The plugin.json `version` is the plugin-compliance mirror of the
  top CHANGELOG `## vX.Y.Z`. This gives proper pinning + explicit updates (no
  per-commit auto-bump surprise — addresses architect F7's cadence concern by making
  both channels release-gated, not per-commit). The accepted cost: **one more wrap
  ceremony step + a stricter review gate** — `/wrap` must bump plugin.json in lockstep
  with CHANGELOG, and a consistency check flags drift. User: "little downside, one
  more ceremony step." See R11 + the wrap-skill update in Execution.
- **Q2. `SKILL_CONTRACT.md` destination? — ✅ RESOLVED (user, 2026-06-07):**
  `skills/work/references/SKILL_CONTRACT.md` (beside `persona-dispatch.md`). The
  phantom-agent gets a proper home.
- **Q3. Command namespacing — ✅ RESOLVED (user + research, 2026-06-07): `name: "mv"`
  + `displayName: "Mind-Vault"`.** → commands are `/mv:wrap`, `/mv:idea`, etc.;
  the `/plugin` UI still shows "Mind-Vault" (`displayName` is UI-only, doesn't affect
  namespacing — confirmed). `mv` is **coherent with the existing `mv-` subagent
  prefix** (`mv-backend`, `mv-curator` …) and terse. Research verdict **`mv` SAFE**:
  no collision in the official catalog, no installed-plugin collision, no built-in
  shadowing (plugin commands are *always* namespaced), 2-char kebab is valid.
  - **Blast radius (architect F3) stands:** the workflow chain + dozens of skill/
    command bodies reference siblings by **bare** slash name (`/plan`, `/compound`,
    `/wrap`, `/review-loop`, `/land`, `/work`; "`/plan` alias" in `commands/brainstorm.md`).
    Under the plugin path the literal is `/mv:wrap`. Skills still *fire*
    (description-invoked); only literal slash-typing changes. **Do NOT rewrite skill
    bodies channel-aware** — add **one canonical note** ("plugin path: prefix slash
    commands with `mv:`, e.g. `/mv:wrap`; skill triggers unaffected") in README +
    ONBOARDING; leave bodies as-is.
  - **Known caveat (research, CC issue #11328):** *subagents* can be flaky discovering
    plugin-namespaced commands (`/mv:foo`) — name-agnostic, affects agent
    self-invocation only, not human typing. Note it; not a blocker.
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
- **Q5. Rule-loading on the plugin path — ✅ RESOLVED (user, 2026-06-07): rules MUST
  load. Wire a loader command + an install/session welcome note.** The plugin has no
  always-on rules channel (§C), so make rule-loading explicit and self-announcing:
  1. **Loader command** — `commands/load-rules.md` (`/mv:load-rules`) resolves
     `RULE_*.md` from **`${CLAUDE_PLUGIN_ROOT}/rules/`** when set (the plugin-root env
     var CC exposes; `rules/` lives inside the plugin root so it IS copied to the
     install cache — verify this in §Verification), falling back to repo-relative on
     the symlink path. Detect + warn if none resolve. Works on both channels.
  2. **Welcome note on install (`hooks/hooks.json`, `SessionStart`)** — on a session
     where the plugin is active, surface a one-time note: *"Mind-Vault plugin active.
     Behavioural rules aren't auto-loaded on the plugin channel — run `/mv:load-rules`
     to load them."* (The hook only fires on the plugin path; symlink-path machines
     auto-load rules via `~/.claude/CLAUDE.md` refs and never see it — correct.)
  - **Stretch / verify in `/work`:** check whether a `SessionStart` hook can inject
    rule *content* directly (`additionalContext`) — if supported, **auto-load** the
    rules and demote the note to a confirmation (research §C said `InstructionsLoaded`
    only *observes*; `SessionStart` injection is the open question). If not supported,
    the loader-command + welcome-note is the reliable design.

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
3. **Add `.claude-plugin/plugin.json` (R2, R11).** `name: "mv"`,
   `displayName: "Mind-Vault"` (Q3), `description`, `author`, `homepage`/`repository`,
   `keywords`, and **`version` SET to the release's CHANGELOG version** (the v5.1
   number at ship — Q1). No `skills`/`commands`/`agents` keys (defaults auto-discover
   at root).
4. **Add `.claude-plugin/marketplace.json` (R3).** Marketplace top-level `name`
   stays descriptive (`mind-vault`), `owner`, `plugins: [{ name: "mv", source: "./",
   description }]` — **plugin id is `mv`** (matches plugin.json `name`), so install is
   `/plugin install mv@mind-vault`. Use `"./"` (not `"."`) — the verified in-the-wild
   form from the `superpowers` marketplace (plugin-at-repo-root; no self-reference —
   architect F6).
4b. **Update `skills/wrap/SKILL.md` Step 4b for multi-location version sync (R11).**
   Generalise the first-match-single-source detection so a project can declare
   **multiple sync-required version locations**, and a bump updates **all** of them.
   Add `.claude-plugin/plugin.json` (`jq -e '.version'`) to the recognised sources.
   For mind-vault: a release bumps `CHANGELOG.md` (`## vX.Y.Z`) **and**
   `plugin.json.version` together. Add a **consistency check** (the stricter gate):
   `plugin.json.version` must equal the top CHANGELOG `## v` — surface drift in the
   wrap hand-back and as a self-sweep item. Keep it **generic** (the mechanism is
   "N sync-required sources," mind-vault is just the first user). Self-mode CHANGELOG
   handling already exists; this extends it to the paired plugin.json.
5. **Rule-loading on the plugin path (R12, Q5, F1).**
   a. **`commands/load-rules.md`** (`/mv:load-rules`): resolve `RULE_*.md` from
      `${CLAUDE_PLUGIN_ROOT}/rules/` when that env var is set (plugin path), else
      repo-relative (symlink path); **detect + warn** if none resolve. Works on both.
   b. **`hooks/hooks.json`** — a `SessionStart` hook that prints the welcome note
      ("Mind-Vault plugin active — run `/mv:load-rules` to load behavioural rules").
      This adds `hooks/` as a shipped plugin component.
   c. **Investigate** whether `SessionStart` can inject rule *content* directly
      (`additionalContext`); if yes, auto-load and demote the note to a confirmation.
6. **Docs (R9).** README + AGENTS.md + `docs/guides/ONBOARDING.md`: add the "Install
   as a Claude Code plugin" path (`/plugin marketplace add infohata/mind-vault`),
   the `--plugin-dir` dev-loop, the **coexist note** ("CC: plugin OR symlink script,
   not both — best-effort guard only, see Q4"), the **one canonical namespacing note**
   (Q3 — "plugin path: prefix slash commands with `mv:`, e.g. `/mv:wrap`; skill
   triggers unaffected"), and the statement that `rules/`/`docs/rules/`/statusline
   stay script-wired regardless.
7. **Best-effort double-load guard (R7, Q4).** Light non-fatal *plugin-then-script*
   warning in `setup-claude-code-symlinks.sh`; label it best-effort; exempt the
   `--plugin-dir`/`@skills-dir` dev-loop.
8. **`/wrap` backref (RULE_cross-idea-amendments step 3).** On wrap, append the
   `SKILL_CONTRACT.md` move backref to IDEA-014's archive.

## Verification

- **Manifest lint:** `claude plugin validate ./ --strict` (the real CLI — research)
  passes with no stray/misspelled fields. Run before declaring done.
- **Plugin loads from working tree:** `claude --plugin-dir ~/projects/mind-vault`
  (or the session-equivalent) → skills discoverable, `/reload-plugins` works, UI shows
  "Mind-Vault". **All 6 commands appear namespaced (F4):** `/mv:{brainstorm,create-pr,
  git-status,load-rules,review-loop,test}` — confirm each is present. (Manual — record
  in a verification log in this archive dir.)
- **Rule-loading on the plugin path (R12, Q5):**
  - The **welcome note fires** — start a session with the plugin active and confirm
    the `SessionStart` hook surfaces the "run `/mv:load-rules`" note.
  - **`/mv:load-rules` resolves rules** under `--plugin-dir` (via `${CLAUDE_PLUGIN_ROOT}/rules/`),
    not silently zero; warns cleanly if absent.
  - **Cache actually carries `rules/`** — after a real `/plugin install`, confirm
    `rules/RULE_*.md` exists under the cached plugin root (it's inside the plugin root,
    so it should copy; if the install prunes non-component dirs, fall back to the
    note-points-at-repo approach — record which holds).
- **plugin.json valid:** `jq -e '.name' .claude-plugin/plugin.json` = `"mind-vault"`.
- **Version sync (R11, the stricter gate):** `jq -r '.version' .claude-plugin/plugin.json`
  equals the top `## vX.Y.Z` in `CHANGELOG.md`. Plus: dry-run `/wrap` Step 4b on a
  mock bump and confirm it updates *both* files (not just the first match).
- **marketplace.json valid:** `jq -e '.plugins[0].source' .claude-plugin/marketplace.json`.
- **agents/ is plugin-clean:** `ls agents/*.md | wc -l` = 8; `ls agents/SKILL_CONTRACT.md` → absent.
- **No stale contract path:** `git grep -n 'agents/SKILL_CONTRACT' -- ':!CHANGELOG.md' ':!docs/archive/'` = 0.
- **Agent frontmatter plugin-safe:** `grep -lE '^(hooks|mcpServers|permissionMode):' agents/AGENT_*.md` = empty.
- **Coexist intact:** `setup-claude-code-symlinks.sh` diff = only the optional guard (if Q4 yes); skills/commands/agents/rules/docs-rules/statusline linking all still present. `bash -n` clean.
- **Non-CC scripts untouched:** `git diff --stat` shows no change to `setup-{cursor,opencode,vscode-copilot,antigravity}-symlinks.sh` / `_symlink-lib.sh`.

---

**Status:** ready — architect-reviewed (🟡 → all 7 findings folded). **Q1 resolved**
(set plugin.json `version`, mirror CHANGELOG, `/wrap` keeps both in sync → R11 + the
wrap Step-4b update). **Q2 resolved** (`SKILL_CONTRACT.md` → `skills/work/references/`).
**Q3 resolved** (`name: mv` + `displayName: Mind-Vault` → `/mv:<cmd>`; research-verified
clash-free). **Q5 resolved** (loader command `/mv:load-rules` + `SessionStart`
welcome-note hook; rules load on the plugin path). Only **Q4** (best-effort guard
scope) carries its default — surface at `/work` start. Next: `/work docs/archive/2026-06-idea-017-mind-vault-cc-plugin/2026-06-07-mind-vault-cc-plugin-plan.md`.
