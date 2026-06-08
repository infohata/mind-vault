---
stage: plan
slug: channel-aware-inner-references
created: 2026-06-08
source: ./IDEA-020-channel-aware-inner-references.md
status: shipped
project: mind-vault
architect_review: "🟡 REQUIRES ABSTRACTION → all 6 findings folded (2026-06-08): (1) convention covers 3 mechanisms (Skill / slash / subagent_type), stacked mv:mv- prefix called out; (2) R4 split — R4a stage dispatch + R4b persona dispatch (work/persona-dispatch.md + work/SKILL.md + plan/architect-handoff.md), sprint-auto reaches personas transitively via /work; (3) shared reference relocated sprint-auto/references → work/references (fix inverted dependency arrow); (4) dual-mode token-OR-inline-path exception documented (architect-handoff fail-safe); (5) R1 demoted keystone→record-3-facts+confirm, dead 'if bare resolves' branch deleted; (6) SPRINT_AUTO_PLAYWRIGHT_AVAILABLE batch-state precedent cited, persist channel_prefix at setup time. Core boundary sound + reusable."
---

# IDEA-020: Channel-aware inner command/skill references (plugin-route correctness)

## Context

IDEA-017 shipped the Claude Code **plugin route**, which namespaces every mind-vault
command/skill/**agent** under `mv:` (`/mv:work`, `Skill mv:plan`, `subagent_type mv:mv-architect`).
The authoring machine was then switched to **plugin-only** (symlinks removed), and a
latent bug surfaced live: a skill that **executes a sibling by bare name** doesn't
resolve when only the `mv:`-namespaced plugin is installed — silently. review-loop's
`ScheduleWakeup(prompt="/review-loop …")` self-re-entry was hot-fixed in PR #193
(v5.1.2): `reentry_command` mirrors the invocation prefix, persisted to scratch. This
IDEA generalises that one-site fix across the whole **executed-dispatch** surface —
which architect review + live discovery widened to **three dispatch mechanisms across
four skills**, with `/work`'s persona dispatch (transitively reached by every
sprint-auto IDEA) the highest blast radius.

## Problem Frame

- **Three executed-dispatch mechanisms, all bare today, all broken on the plugin route:**
  1. **`Skill` tool** (skill names) → needs `mv:<skill>` (e.g. `mv:plan`). *Confirmed live this session.*
  2. **Literal slash** (ScheduleWakeup `prompt`, typed) → needs `/mv:<command>` (review-loop, **fixed** PR #193).
  3. **`Agent` tool `subagent_type`** (persona dispatch) → needs the **stacked** `mv:mv-<persona>` (the `mv:` plugin prefix on top of the existing `mv-` subagent prefix). *Confirmed live this session — bare `mv-architect` returns "Agent type not found"; `mv:mv-architect` resolves.*
- **`/work`'s persona dispatch is the blast-radius case.** `work/references/persona-dispatch.md` maps personas to bare `mv-<persona>` with **no channel awareness and no host-availability fallback**. Every sprint-auto IDEA dispatches personas **transitively through `/work`** (`sprint-auto/SKILL.md:127`), so a bare matrix silently degrades every persona to generic-Claude on a plugin-only VPS — the morning reviewer sees stages ran, not that the personas never engaged.
- **sprint-auto stage dispatch is the other exposed surface** — it invokes `plan`/`work`/`/wrap`/`/review-loop`/`/compound` by bare name, unattended overnight.
- **The IDEA-017/#193 docs already point the fragile workload at the unsafe channel** (recommend the marketplace plugin for "a VPS running overnight sprint-auto"). Unsafe until this lands.

## Requirements Trace

- **R1. Record the resolution facts + one confirmatory probe each (NOT an open keystone).** Three facts are already observed this session — log them with evidence, then run one read-only confirmatory probe per mechanism. **There is no "bare might resolve" branch** (empirically false for all three):
  - `Skill` tool → requires `mv:<skill>` (registry shows only `mv:` entries; `Skill mv:plan` ran).
  - `Agent subagent_type` → requires stacked `mv:mv-<persona>` (bare `mv-architect` → "not found").
  - Literal slash → requires `/mv:<command>` (PR #193).
- **R2. Detect by invocation form (no env probe).** `${CLAUDE_PLUGIN_ROOT}` is absent from the agent's shell (verified). The agent mirrors how it was invoked; persist the prefix where it must survive compaction / subshell boundaries.
- **R3. One shared convention covering all THREE mechanisms.** Author a single reference enumerating Skill / slash / `subagent_type`, the **stacked `mv:mv-` prefix** trap called out explicitly, the executed-vs-prose test, and the dual-mode exception (R5b). review-loop + work + plan + sprint-auto all point at it.
- **R4a. Fix sprint-auto STAGE dispatches** (`plan`/`work`/`/wrap`/`/review-loop`/`/compound`, S1/S2/S5/S6/S12 + the selector rule) to mirror the `/sprint-auto` invocation prefix.
- **R4b. Fix PERSONA dispatch (the surface the first draft missed).** `work/references/persona-dispatch.md` + `work/SKILL.md` matrix + `plan/references/architect-handoff.md` reference bare `mv-<persona>`. Make them channel-aware (`mv:mv-<persona>` on the plugin channel). sprint-auto reaches personas transitively via `/work`, so this single fix covers the unattended persona layer too.
- **R5a. Confirm the non-targets are prose-only** (`land`/`wrap` human-facing instructions, `skill-writer` doc examples) — leave bare per IDEA-017 Q3. Document the executed-vs-prose test.
- **R5b. Document the dual-mode (token-OR-inline-path) exception.** `architect-handoff.md:19` dispatches the architect via `subagent_type` **OR** inline-invoke from `agents/AGENT_architect.md` by filesystem path (channel-independent). Rule: prefix the token, **keep the inline-path fallback** — the path is the channel-agnostic backstop. Don't let the sweep flatten it into a hard `mv:mv-architect`.
- **R6. Reconcile the IDEA-017/#193 docs** — add the channel-safety caveat to the sprint-auto-VPS plugin recommendation.

## Scope Boundaries

**In scope:** the R1 fact-record + confirm; a shared `CHANNEL_AWARE_DISPATCH.md` covering 3 mechanisms (R3); sprint-auto stage-dispatch fix (R4a); persona-dispatch fix across `/work` + `/plan` (R4b); the dual-mode exception (R5b); the #193 doc hedge (R6); `channel_prefix` persisted to sprint-auto's batch state file at setup time (R2).

**Out of scope (deliberate):**

- **Rewriting prose cross-references** (IDEA-017 Q3 — prose stays bare; only *executed* dispatch needs the prefix). `land`/`wrap`/`skill-writer` prose untouched.
- **review-loop's re-entry** — already fixed (PR #193); this IDEA only repoints its inline explanation at the shared doc, keeping `reentry_command` mechanics intact.
- **Changing the `mv:` scheme** (settled, IDEA-017 Q3); a runtime host-state auto-detector (invocation-form signal suffices); making sprint-auto runnable end-to-end (UNSTABLE for separate reasons).

## Context & Research

### Live session evidence (this machine, plugin-only — R1 facts)

- `Skill(skill="mv:idea")` / `Skill(skill="mv:plan")` **resolved**; registry shows mind-vault skills only as `mv:<name>`.
- `Agent(subagent_type="mv-architect")` → **"Agent type not found"**; `Agent(subagent_type="mv:mv-architect")` **resolved** — the stacked-prefix fact, discovered by the `/plan` architect handoff failing live.
- `ScheduleWakeup(prompt="/mv:review-loop 193 …")` **re-entered correctly**; bare `/review-loop` was the original bug.

### Dispatch sites (measured 2026-06-08)

- **sprint-auto stage dispatch (R4a):** `sprint-auto/SKILL.md` S1`:114`, S2`:127`, S5`:135`, S6`:147`, S12`:211`, selector `:296/:298`.
- **Persona dispatch (R4b):** `work/references/persona-dispatch.md:11-16` (bare `mv-<persona>` map, no fallback), `work/SKILL.md:50-58` (matrix passed verbatim to `Agent(subagent_type:)`), `plan/references/architect-handoff.md:19` (dual-mode — the R5b exception).
- **Transitive coupling:** `sprint-auto/SKILL.md:127` — "`/work` dispatches personas" — so fixing `/work` covers sprint-auto's persona layer.
- **Non-targets (prose — leave bare):** `land/SKILL.md:33,63`, `wrap/SKILL.md:391,396`, `skill-writer/SKILL.md:170,179,185`.

### Institutional learnings

- **PR #193 precedent** — `review-loop/SKILL.md:118,177-179` (`reentry_command`): invocation-form-derived prefix, persisted, used for executed dispatch. The pattern to generalise.
- **`SPRINT_AUTO_PLAYWRIGHT_AVAILABLE` precedent** — `sprint-auto/SKILL.md:89` persists cross-worktree state to the **batch state file** because "env vars don't survive subshells"; per-IDEA `/plan`/`/work` read it back. `channel_prefix` rides the **identical rail** — closes Q3/Q6.
- [IDEA-017 Q3](../2026-06-idea-017-mind-vault-cc-plugin/2026-06-07-mind-vault-cc-plugin-plan.md) — "don't rewrite bodies channel-aware; skills fire by description." This IDEA is the scoped carve-out: only *executed* dispatch (a literal lookup) needs the prefix.

## Key Technical Decisions

- **Detect by invocation form, persist the prefix.** No env probe. review-loop → scratch; sprint-auto → batch state file, **written at S(-1)/setup time** (alongside the Playwright export) so a post-compaction resume reads a stable value, not a per-stage re-derivation.
- **One shared reference, foundational home (architect F3).** `skills/work/references/CHANNEL_AWARE_DISPATCH.md` — `/work` is the most-depended-on consumer and already owns `persona-dispatch.md` (natural sibling). **Reject `sprint-auto/references/`** — pointing stable `/work` + `/plan` at a doc owned by UNSTABLE sprint-auto inverts the dependency arrow.
- **Executed-vs-prose is the gating test, mechanism-agnostic.** "Does the skill *itself* programmatically pass this token to a tool's lookup (`Skill`/slash/`subagent_type`)?" → prefix it. Human-typed instructions + description-invokes → bare. Plus the **dual-mode** third category: token-OR-inline-path → prefix the token, keep the path fallback.

## Open Questions

- **Q1 — RESOLVED (architect F5).** Bare does not resolve for any of the three mechanisms (live evidence). R1 is a fact-record + confirmatory probe, not a gating unknown. The "if bare resolves, narrow scope" branch is deleted (unreachable).
- **Q2 — RESOLVED (architect F3):** shared reference lives at `skills/work/references/CHANNEL_AWARE_DISPATCH.md` (foundational home, correct dependency direction).
- **Q3/Q6 — RESOLVED (architect F6):** the batch-state-file persist rail exists and is proven across the subshell boundary (`SPRINT_AUTO_PLAYWRIGHT_AVAILABLE`, `sprint-auto/SKILL.md:89`); persist `channel_prefix` at setup time.

## Execution Sequence

1. **R1 — record + confirm.** Write a verification log in this archive dir stating the three observed resolution facts (Skill → `mv:`; Agent → stacked `mv:mv-`; slash → `/mv:` per #193) with this session's evidence, then one read-only confirmatory probe per mechanism. No scope-narrowing branch.
2. **R3 — author `skills/work/references/CHANNEL_AWARE_DISPATCH.md`:** the convention (invocation-form detection, persist-the-prefix, executed-vs-prose test, **dual-mode exception**), all **three** mechanisms enumerated with the **stacked `mv:mv-`** persona trap called out, and the two worked instances (review-loop `reentry_command`, `/work` persona matrix). Repoint review-loop's inline explanation at it (keep `reentry_command` mechanics).
3. **R4b — fix persona dispatch (do this before R4a; it's the higher-blast surface).** `work/references/persona-dispatch.md` + `work/SKILL.md` matrix: channel-aware `mv:mv-<persona>` form mirroring the invocation prefix; add the missing host-availability fallback. `plan/references/architect-handoff.md`: prefix the `subagent_type` token **and keep the inline-path fallback** (R5b).
4. **R4a — fix sprint-auto stage dispatches** (S1/S2/S5/S6/S12 + selector): `<channel_prefix>`-aware `plan`/`work`/`/wrap`/`/review-loop`/`/compound`; add `channel_prefix` to the batch state file at setup time (cite the Playwright precedent). Persona layer is already covered by R4b via the transitive `/work` dispatch.
5. **R5a — confirm-only:** verify `land`/`wrap`/`skill-writer` cross-refs are prose; **do not edit** them. Document the executed-vs-prose test in the shared reference.
6. **R6 — reconcile docs:** channel-safety caveat on the sprint-auto-VPS plugin recommendation (README "Authoring vs consuming" / ONBOARDING).
7. **`/wrap`:** self-mode patch bump + plugin.json mirror (IDEA-017 Step 4b).

## Verification

- **R1 recorded:** verification-log entry with evidence for all three mechanisms.
- **Persona dispatch channel-aware:** `work/references/persona-dispatch.md` + `work/SKILL.md` carry the `mv:mv-<persona>`-on-plugin form + fallback; `grep -n 'mv-architect\|mv-backend' skills/work/` shows no bare *executed* `subagent_type` without channel-aware handling.
- **architect-handoff dual-mode preserved:** `plan/references/architect-handoff.md` prefixes the token AND retains the inline-path fallback.
- **sprint-auto stage + persona safe:** stage dispatches reference `<channel_prefix>`; `channel_prefix` persisted in the batch state file at setup; persona layer covered transitively via `/work`.
- **Shared reference exists at `work/references/` and is pointed at** from review-loop, work, plan, sprint-auto (not the reverse).
- **Non-targets untouched:** `git diff --stat` shows no change to `skills/land/SKILL.md`, `skills/wrap/SKILL.md`, `skills/skill-writer/SKILL.md`.
- **review-loop regression-free:** `reentry_command` mechanics intact.
- **Docs reconciled:** sprint-auto-VPS recommendation carries the caveat.

## Execution Progress (shipped 2026-06-08)

| Step | Status | Commit |
| --- | --- | --- |
| R1 resolution-audit log | ✅ 3 facts recorded + evidence | `8f6b814` |
| R3 `CHANNEL_AWARE_DISPATCH.md` (3 mechanisms) | ✅ | `8f6b814` |
| R4b persona dispatch (work + plan) | ✅ + inline fallback + dual-mode | `8f6b814` |
| R4a sprint-auto stage dispatch + `channel_prefix` | ✅ S(-1) step 10 + 6 sites | `b8fd00d` |
| R5a non-targets confirmed prose (untouched) | ✅ land/wrap/skill-writer = 0 diff | (verification) |
| R6 docs hedge (README + ONBOARDING) | ✅ v5.1.3+ caveat | `<this>` |
| review-loop → shared-doc pointer | ✅ | `<this>` |

Verification all green (persona dispatch channel-aware ×3 files; architect-handoff dual-mode preserved; shared ref pointed at by 4 consumers; non-targets 0-diff; review-loop `reentry_command` intact). The Agent-tool/persona-dispatch surface (stacked `mv:mv-`) — the architect's scope-expansion catch — was discovered live when this IDEA's own `/plan` architect handoff failed on bare `mv-architect`.

---

**Status:** shipped — architect-reviewed (🟡 → all 6 findings folded), all execution steps landed + verified.
