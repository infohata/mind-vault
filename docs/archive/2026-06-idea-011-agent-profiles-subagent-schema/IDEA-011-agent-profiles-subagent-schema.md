---
id: 011
title: Agent Profiles → Recognized Subagent Schema
status: complete      # idea | in-progress | complete | superseded
priority: high   # high | medium | low
supersedes: []       # list of IDEA ids this replaces, or []
superseded_by: null
depends_on: []       # list of IDEA ids required before starting, or []
related: [002]             # list of IDEA ids that share context, or []
created: 2026-05-31
completed: 2026-06-01
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false                                     # true | false
auto_safe_reason: "Judgment-heavy: per-persona model assignment, authoring rich dispatch descriptions with <example> blocks, and a filename-convention decision that ripples to ~13 skill references (rename-before-drop territory). Not blind-runnable until /plan nails the convention + per-agent model map."
sensitive_paths_cleared: false         # true | false
sensitive_paths_cleared_reason: "The `tools:` frontmatter IS a capability-grant surface — translating the OpenCode `tools: {bash: true}` map to CC's comma-string changes what each subagent may invoke (write/edit/bash). A mistranslation could over-grant tool access, so a human should eyeball the tool maps even though no auth/schema/infra code is touched."
---

# IDEA-011: Agent Profiles → Recognized Subagent Schema

**Status**: ✅ Complete (2026-06-01) · Residual post-merge check: fresh-session `subagent_type` dispatch probe (R1)
**Priority**: High

**Problem** (or opportunity): The eight `agents/AGENT_*.md` profiles use an **OpenCode-style frontmatter** (`mode: subagent`, `temperature:`, `tools:` as a `{write: true}` map, an `allowed_tools:` list, and **no `name:` field**). Claude Code's subagent system — and every plugin marketplace agent (superpowers, claude-plugins-official `feature-dev`/`code-modernization`, etc.) — keys subagents off a different schema: a required `name:`, a rich trigger-oriented `description:`, a **comma-separated `tools:` string**, and optional `model:`/`color:`. `agents/` *is* symlinked into `~/.claude/agents/`, so CC scans these files — but the wrong frontmatter shape means they register **degraded or not at all** as dispatchable `subagent_type`s. The result: when `/work`, `/plan`, `/compound`, `/ideate`, and `/sprint-auto` say "dispatch to `AGENT_backend`" (~13 references across skills), the orchestrator can't actually call `Agent(subagent_type: …)` — it falls back to hand-reading the persona file and crafting an ad-hoc Task prompt, losing the model-pinning, tool-scoping, and auto-dispatch the recognized schema provides.

**Proposal** (or idea): Full re-author of all eight profiles to the recognized Claude Code / plugin subagent schema, modeled on the in-repo examples (`feature-dev/agents/code-architect.md`, `code-reviewer.md`, superpowers `code-reviewer.md`):

- **Frontmatter migration** — add `name:` (the dispatchable id), convert `tools:` map → comma-separated CC tool-name string (auditing each grant during translation), assign a deliberate `model:` per persona (e.g. architect/curator → opus, backend/frontend → inherit/sonnet), drop the OpenCode-only `mode`/`temperature`/`allowed_tools` keys, optionally add `color:`.
- **Description upgrade** — replace the one-line persona blurbs with rich, dispatch-triggering `description:` text including `<example>` blocks (the pattern superpowers/feature-dev use to drive correct auto-selection), so the model recognizes *when* to reach for each persona, not just what it is.
- **Filename / id convention** — decide on `name` ids and whether files stay `AGENT_<persona>.md` or move to the kebab `<persona>.md` plugin convention; if renamed, update all ~13 skill references in the **same** rename-before-drop sequence (renames land + green, then any legacy alias drops).
- **Verify recognition** — confirm each profile shows up as a usable `subagent_type` in a fresh session (the `/idea` Phase-6 manual-verify pattern: start a fresh agent, ask for the persona, confirm dispatch).

**Why now**:
- Agents are the dispatch substrate of five of the six sprint-workflow skills; a silently-degraded registration weakens every `/work` and `/plan` run and we only just noticed the schema mismatch.
- The recognized-schema examples are now sitting in-repo (`~/.claude/plugins/.../feature-dev/agents/`, superpowers cache) — a concrete, copyable target spec, no guessing.
- Cheap to validate (fresh-session dispatch check) and the blast radius is contained to `agents/` + skill cross-references.

**Non-goals**:
- Not changing *what* the personas do — the prime-directive bodies stay; this is a schema/description/registration refactor, not a behavior rewrite.
- Not building a multi-harness portability generator (CC + OpenCode + Cursor dual-frontmatter) in this IDEA — note it as a possible follow-up if the user later needs the profiles to run unchanged in non-CC harnesses.
- Not adding new personas — roster stays the existing eight.

**Related**: IDEA-002 (skill debloat) shares the "mind-vault config must be recognized + lean by the consuming agent" hygiene theme — same motivation, different surface (skills there, agents here).

---

**Plan-time decisions (2026-06-01)** — the user added a cross-harness compatibility requirement, which shifted two of this IDEA's proposals:

- **Model pinning → all `model: inherit`.** The proposal suggested deliberate per-persona pinning (architect/curator → opus). The plan instead pins **every** persona to `inherit`, because any non-inherit value breaks single-file Cursor compatibility for that persona. This also dissolves the `auto_safe_reason`'s "per-persona model assignment" judgement load.
- **Filenames kept as `AGENT_*.md`; dispatch ids namespaced `mv-<persona>`.** CC dispatches on the frontmatter `name:`, not the filename — so no rename, `RULE_rename-before-drop` does not bind, and the `~/.claude/agents/` + `.cursor/agents/` symlinks plus every `agents/AGENT_*.md` link stay valid.
- **Compatibility deliverable = methodology doc, not a generator** (honours the existing non-goal). See [`docs/guides/AGENT_PORTABILITY.md`](../../guides/AGENT_PORTABILITY.md): Cursor = straight copy (already symlinked), OpenCode + Antigravity = fork recipes.
