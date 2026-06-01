---
stage: plan
slug: agent-profiles-subagent-schema
created: 2026-06-01
source: ./IDEA-011-agent-profiles-subagent-schema.md
status: ready
project: mind-vault
---

# IDEA-011: Agent Profiles → Recognized Subagent Schema

## Context

The eight `agents/AGENT_*.md` persona files carry **OpenCode-style frontmatter** (`mode: subagent`, `temperature:`, a `tools: {write: true}` boolean map, an `allowed_tools:` list, and **no `name:`**). Claude Code — and every plugin marketplace agent (`feature-dev`, `code-modernization`, superpowers, `agent-creator`) — keys dispatchable subagents off a different schema: a required `name:`, a trigger-oriented `description:` (often with `<example>` blocks), a comma-separated `tools:` string, and optional `model:`/`color:`. Because `agents/` is symlinked into `~/.claude/agents/`, CC scans these files but registers them **degraded or not at all** as `subagent_type`s. So when `/work`, `/plan`, `/compound`, `/ideate`, `/sprint-auto` say "dispatch to `AGENT_backend`" (~45 token references), the orchestrator can't issue a real `Agent(subagent_type: …)` call — it falls back to hand-reading the persona file, losing model-pinning, tool-scoping, and auto-dispatch.

This plan re-authors all eight profiles to the recognized CC schema and adds a cross-harness portability methodology doc. The user added one requirement beyond the captured IDEA: keep the profiles **compatible where possible** with OpenCode, Antigravity, and Cursor — with Claude Code as the priority. Where compatibility is structurally impossible, the deliverable is a fork-and-fix methodology doc, **not** a multi-harness generator (the IDEA's standing non-goal).

## Problem Frame

- **Silent degraded registration.** The wrong frontmatter shape means `mv-`-less, `name:`-less files don't surface as clean dispatch targets. Five of six sprint-workflow skills route through these personas, so every `/work` and `/plan` run is weakened.
- **No real tool-scoping.** The OpenCode `tools: {write: true, …}` map isn't read by CC, so each persona effectively inherits **all** tools — including reviewer personas (`AGENT_curator`, the architect's reviewer mode) that should be read-only. The grant surface is unaudited (the IDEA's `sensitive_paths_cleared` concern).
- **Capability gaps.** `AGENT_researcher` ("venture outwards, rip patterns from the wider world") has **no web tools** in its current map — only write/edit/bash/grep/glob/read. It literally cannot fetch.
- **Cross-harness drift untracked.** The profiles are *accidentally* OpenCode-ish today but satisfy none of the four harnesses cleanly. No doc tells a teammate how to run them under Cursor / OpenCode / Antigravity.

## Requirements Trace

- **R1.** Each of the eight personas registers as a usable CC `subagent_type` under a deliberate `name:` — verified by fresh-session dispatch (IDEA "Verify recognition").
- **R2.** Frontmatter migrates to the recognized schema: add `name:`, convert the `tools:` map → comma-separated CC tool-name string, drop OpenCode-only `mode`/`temperature`/`allowed_tools`, set `model:`, add `color:` (IDEA "Frontmatter migration").
- **R3.** Each persona's `tools:` grant is **audited per-role** during translation, not blanket-copied — reviewer personas lose write/edit; the researcher gains web tools (IDEA "auditing each grant"; `sensitive_paths_cleared` concern).
- **R4.** One-line persona blurbs are upgraded to rich, dispatch-triggering `description:` text with 2–3 `<example>` blocks each (IDEA "Description upgrade").
- **R5.** Dispatch-name tokens in skill/command prose are updated to the new `name:` ids so real dispatch works; markdown **link-paths** to `agents/AGENT_*.md` stay valid (files are not renamed).
- **R6.** A cross-harness portability methodology doc documents: Cursor = straight copy; OpenCode + Antigravity = fork recipes with worked before/after examples (user's compatibility requirement; IDEA follow-up note pulled partially into scope as a doc, not a generator).
- **R7.** Behaviour is preserved — the prime-directive persona bodies are not rewritten (IDEA non-goal).

## Scope Boundaries

**In scope:**

- Re-author frontmatter of all 8 `agents/AGENT_*.md` (bodies untouched except the researcher's missing-web-tools fix is frontmatter-only).
- Update dispatch-name tokens in the canonical dispatch sites: `skills/work/SKILL.md`, `skills/work/references/persona-dispatch.md`, `skills/plan/references/architect-handoff.md`.
- New `docs/guides/AGENT_PORTABILITY.md` methodology doc.
- Update `agents/README.md` if it enumerates the roster/schema (verify in step 1).

**Out of scope:**

- Renaming the `AGENT_*.md` files (decided: keep — CC dispatches on `name:`, not filename).
- Generating actual OpenCode / Cursor / Antigravity variant files (decided: methodology doc only; avoids dual-source sync burden).
- Adding/removing personas — roster stays the existing eight (IDEA non-goal).
- Rewriting persona behaviour/prime-directives (IDEA non-goal).

**Explicit non-goals:**

- No multi-harness portability *generator* (script/tool). The portability artifact is a human-followed methodology doc.
- No per-persona `opus`/`sonnet` pinning — decided **all `model: inherit`** (preserves single-file CC+Cursor compat across the whole roster; supersedes the IDEA body's "architect/curator → opus" suggestion).

## Context & Research

### Recognized CC schema — confirmed from in-repo examples

- `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/feature-dev/agents/code-architect.md` — canonical shape: `name`, single-line `description`, `tools:` **comma-string** (`Glob, Grep, LS, Read, …`), `model: sonnet`, `color: green`. Read-only toolset (no Write/Edit/Bash) for a design/reviewer agent.
- `.../feature-dev/agents/code-reviewer.md` — same shape; `color: red`; read-only.
- `.../plugin-dev/agents/agent-creator.md` — **authoritative authoring spec**: `name` = lowercase + hyphens, 3–50 chars; `description` with the `<example>` block format (Context / user / assistant / `<commentary>`); `model: inherit` default (sonnet=complex, haiku=simple); `color` palette (blue/cyan=analysis, green=generation, yellow=validation, red=security/critical, magenta=transformation); `tools:` minimal set or omit for full access; supports `tools: ["A","B"]` array form too.

### Existing code and patterns to reuse

- `agents/AGENT_*.md` (×8) — current OpenCode frontmatter + the persona bodies to preserve verbatim.
- `skills/work/references/persona-dispatch.md` — the dispatch table; **promote to the canonical "persona → file → subagent_type" map** (single source of truth for the id mapping so other skills can keep conceptual `AGENT_xxx` prose).
- `rules/RULE_self-sweep-before-push.md` trigger 5 (doc-consistency) + `rules/RULE_rename-before-drop.md` — see Key Decisions for why rename-before-drop does **not** bind here.

### Institutional learnings

- `mind-vault/skills/skill-writer/SKILL.md` + `docs/guides/SKILL_AUTHORING_WALKTHROUGH.md` — frontmatter-schema discipline, `<example>`/trigger-quality bar, length budgets; apply the same rigor to agent descriptions.
- IDEA-002 (skill debloat) — sibling "config must be recognized + lean by the consuming agent" hygiene theme.
- Auto-memory `feedback_illustrative_examples_not_production` — the methodology doc's fork examples are illustrative; don't over-harden them.

### External references (web-verified June 2026 — see AGENT_PORTABILITY.md for source URLs)

- **Cursor** subagents (`.cursor/agents/*.md`, v2.4+): `name` (filename-fallback), `description`, `model` (`inherit`/`fast`/`composer-2`/…), `readonly`, `is_background`. **Single-file compatible with CC iff `model: inherit`**; CC's `tools:`/`color:` are silently ignored (additive). → with all-inherit, Cursor needs **zero fork** (straight copy).
- **OpenCode** (`.opencode/agents/` or `~/.config/opencode/agents/`): `name` from filename; `tools:` **boolean map** (`{write: false}`, deprecating toward `permission:`); `model:` **provider-prefixed** (`anthropic/claude-…`). **Irreconcilable** with CC on `tools` value-type + `model` format → needs fork.
- **Antigravity** (`.agents/agents.md`): personas are **prose `## Name (@handle)` sections in one shared file**, no per-file frontmatter. Structurally incompatible → needs prose-section fork.

## Key Technical Decisions

- **Keep `AGENT_*.md` filenames; dispatch id lives in `name:`.** CC dispatches on the `name:` frontmatter field, so filenames are cosmetic for CC. Keeping them means zero file renames, the `~/.claude/agents/` symlink and every `agents/AGENT_*.md` markdown link-path stays valid, and **`RULE_rename-before-drop` does not bind** (no symbol is dropped — `name:` is purely additive).
- **Namespaced `name: mv-<persona>`.** `subagent_type` resolves from a shared registry that also holds plugin agents (`code-reviewer`, `code-architect`). Generic ids (`architect`, `backend`) risk collision; the `mv-` prefix is collision-safe and unmistakably ours. Ids: `mv-architect`, `mv-backend`, `mv-frontend`, `mv-devops`, `mv-test-engineer`, `mv-curator`, `mv-researcher`, `mv-documentation`.
- **All `model: inherit`.** Maximizes single-file CC+Cursor compatibility across the whole roster (any non-inherit value breaks Cursor for that persona) and removes the IDEA's judgment-heavy per-persona model map. Net effect: Cursor stops being a "fork" and becomes a straight copy — strengthening the portability story. Supersedes the IDEA body's opus/sonnet suggestion; record this divergence in the IDEA archive.
- **Per-role tool audit (R3).** Grants diverge by role rather than the current uniform write/edit/bash/grep/glob/read:

  | Persona | `name` | `color` | `tools:` (comma-string) | Rationale |
  |---|---|---|---|---|
  | architect | `mv-architect` | green | `Read, Grep, Glob, Bash, Write, Edit, TodoWrite` | dual-mode: reviewer in `/plan` **and** author in `/work` — keeps write |
  | backend | `mv-backend` | blue | `Read, Grep, Glob, Bash, Write, Edit, TodoWrite` | implementer |
  | frontend | `mv-frontend` | cyan | `Read, Grep, Glob, Bash, Write, Edit, TodoWrite` | implementer |
  | devops | `mv-devops` | yellow | `Read, Grep, Glob, Bash, Write, Edit, TodoWrite` | implementer |
  | test-engineer | `mv-test-engineer` | red | `Read, Grep, Glob, Bash, Write, Edit, TodoWrite` | authors tests + runs suites |
  | curator | `mv-curator` | red | `Read, Grep, Glob, Bash, TodoWrite` | **reviewer — no Write/Edit** (mirrors feature-dev reviewer read-only) |
  | researcher | `mv-researcher` | magenta | `Read, Grep, Glob, WebFetch, WebSearch, Write, TodoWrite` | **gains web tools** (fixes capability gap); Write to map findings into vault; no Bash/Edit |
  | documentation | `mv-documentation` | blue | `Read, Grep, Glob, Write, Edit, TodoWrite` | writer — no Bash |

  Confirm exact CC tool-name spellings against an in-repo example before writing (`WebFetch`, `WebSearch`, `TodoWrite`, `Glob`, `Grep`). Human eyeballs this table at review → flips `sensitive_paths_cleared`.
- **`description` upgrade with `<example>` blocks.** Each persona gets a `description:` (multiline `|`) opening with "Use this agent when…" + 2–3 `<example>` blocks in the agent-creator format. Pull trigger scenarios from the existing skill dispatch tables (e.g. backend's are the work/SKILL.md "Models, views, signals, DRF…" rows).
- **`persona-dispatch.md` as the canonical id map.** Add a `Persona | File | subagent_type` table there so other skills keep conceptual `AGENT_xxx` prose + file links, and only the true dispatch sites switch to `mv-` ids — minimizing churn while making the literal dispatch string discoverable in one place.

## Open Questions

- **Q1. Does `agents/README.md` (or any guide) enumerate the roster/schema and need a parallel update?**
  - **Default:** Grep in step 1; if it lists personas or shows the old frontmatter, update it in the same commit as the profiles.
  - **Trade-off:** Missing it leaves a stale schema example; trivial to catch with the step-1 grep.
- **Q2. Keep the conceptual `AGENT_xxx` prose in non-dispatch skills, or globally rename prose to `mv-xxx`?**
  - **Default:** Keep `AGENT_xxx` as the human-readable persona name + file link in conceptual prose; switch only the literal dispatch sites to `mv-xxx`, with `persona-dispatch.md` holding the map. Less churn, no broken links.
  - **Trade-off:** Two surface names (display `AGENT_`, dispatch `mv-`) — mitigated by the one-place mapping table. Resolved: default chosen.

## Execution Sequence

1. **Pre-flight audit.** `grep -rn 'AGENT_' agents/README.md docs/guides/ 2>/dev/null` and re-confirm CC tool-name spellings from `feature-dev/agents/code-architect.md`. Resolve Q1.
2. **Re-author the 8 profiles** (one cohesive commit). Per file: replace the frontmatter block with `name`/`description`(+`<example>`)/`tools`/`model: inherit`/`color` per the audit table; drop `mode`/`temperature`/`allowed_tools`; leave the body verbatim. Self-sweep (RULE_self-sweep trigger 1 + 5, doc-heavy). Commit: `feat(agents): IDEA-011 — re-author 8 profiles to recognized CC subagent schema`.
3. **Update dispatch sites** (second commit). `skills/work/SKILL.md` dispatch table → `mv-` ids; `skills/work/references/persona-dispatch.md` → add the canonical `Persona | File | subagent_type` map + switch its table ids; `skills/plan/references/architect-handoff.md` line ~19 `subagent_type: architect` → `mv-architect`. Re-grep `subagent_type:` to confirm no stale literal remains. Commit: `docs(skills): IDEA-011 — point dispatch sites at mv-* subagent_type ids`.
4. **Write `docs/guides/AGENT_PORTABILITY.md`** (third commit). Sections: canonical source = `agents/`; the 4-harness compat matrix; **Cursor = copy as-is** (model:inherit caveat, ignored keys); **OpenCode fork recipe** (drop `name`, `tools` comma-string→boolean map, `model: inherit`→provider string/omit, add `mode: subagent`, target `.opencode/agents/`) with one worked before/after; **Antigravity fork recipe** (collapse 8 files → `## Persona (@handle)` prose sections in `.agents/agents.md`) with one worked example; a "regenerate after body change" note. Source URLs from research. Commit: `docs(guides): IDEA-011 — AGENT_PORTABILITY cross-harness fork methodology`.
5. **Record the model-pinning divergence** in the IDEA archive (one-line note: IDEA suggested opus/sonnet; plan chose all-inherit for Cursor compat) — keeps the archive self-consistent.
6. **Architect-lens review** of the changes (see Verification) before hand-back. Note: dispatch via `subagent_type: mv-architect` only works **after** step 2 lands in a *fresh* session; until then use the inline architect-handoff fallback.

## Verification

- **Fresh-session dispatch probe (R1).** In a new CC session, for each of the 8 `mv-*` ids, issue a trivial `Agent(subagent_type: "mv-<persona>")` task and confirm it resolves (no "unknown subagent_type"). This is the IDEA's Phase-6 manual-verify.
- **Schema lint.** Each profile's frontmatter parses as YAML; `name` matches `^mv-[a-z-]{1,}$` and is 3–50 chars; `tools:` is a comma-string of valid CC tool names; `model: inherit`; `description` contains ≥2 `<example>` blocks. `grep -L 'name: mv-' agents/AGENT_*.md` returns empty.
- **No stale dispatch literal.** `grep -rn 'subagent_type:' skills/ commands/` shows only `mv-*` (or generic host-fallback prose), no bare `architect`/`backend`.
- **Link integrity.** `grep -rn 'agents/AGENT_' skills/ commands/ docs/` — every path still resolves (files weren't renamed).
- **Tool-grant audit sign-off (R3).** Human confirms the per-role tool table at PR review → flip `sensitive_paths_cleared: true` with the table as the reasoning.
- **Portability doc check.** `AGENT_PORTABILITY.md` contains the compat matrix + one worked OpenCode and one worked Antigravity before/after, and states Cursor = straight copy.

## Architect review (inline-lens pass, 2026-06-01)

Run inline because `mv-architect` cannot self-dispatch until step 2 lands in a fresh session (architect-handoff fallback).

- **Abstraction/genericity.** Sound. Generator correctly rejected in favour of a methodology doc; `persona-dispatch.md`-as-canonical-id-map is the right single abstraction, no over-engineering.
- **Coupling/dependency.** The display-name (`AGENT_xxx`) vs dispatch-id (`mv-xxx`) split is decoupled via one mapping table; only true dispatch sites switch, so cross-skill prose + file links don't move. Symlink preserved by keeping filenames.
- **Boundary contradiction.** Two boundaries flagged + resolved: (a) architect keeps Write because it is author-mode in `/work` (diverges from feature-dev's read-only architect — justified, documented); (b) curator is read-only review (no Write/Edit) — emits fixes as text. Model-inherit-vs-IDEA-opus divergence recorded in step 5.
- **Deployment/scaling.** No infra/migration — symlinked config, picked up next session. **Downstream consumers (e.g. teisutis) referencing `AGENT_xxx` are unaffected:** file links are unchanged, and an unknown `subagent_type` degrades gracefully to the existing inline persona-read fallback. Add this reassurance as a one-line note in `AGENT_PORTABILITY.md`.

**Verdict: ARCHITECTURALLY SOUND.** One non-blocking addition folded in (downstream-consumer note → portability doc).

---

**Status:** ready — architect-reviewed (inline-lens, sound). Hand to `/work` with this plan path.
