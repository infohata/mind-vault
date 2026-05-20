---
id: 005
title: Review-loop shared core — unify /bugbot-loop + /copilot-loop with engine adapters
status: backlog
priority: high
supersedes: []
superseded_by: null
depends_on: []
related: []
created: 2026-05-20
auto_safe: false
auto_safe_reason: "Touches the two skill files most-invoked under sprint-auto's review-engine selector. Refactor sequencing (rename-before-drop applies — engine adapters land first, dual-engine sync block extracts to references/, then commands/bugbot-loop.md + copilot-loop.md become thin wrappers, then a sprint passes before removing the old single-engine code paths). /plan must resolve the adapter shape + dual-engine state-machine before this is auto-safe."
sensitive_paths_cleared: true
sensitive_paths_cleared_reason: "Pure skill-architecture refactor in commands/ + skills/. No auth, schema, secrets, or runtime config involved."
---

# IDEA-005: Review-loop shared core — unify /bugbot-loop + /copilot-loop with engine adapters

**Status**: 💡 Backlog
**Priority**: High
**Motivation**: PR #129 made the duplication cost concrete (four successive meta-findings on the same retrigger-spacing scaffolding across two mirrored files).

## The pain

`/bugbot-loop` and `/copilot-loop` are ~90% structurally identical — Phase 0 (worktree bootstrap), Phase 1 (triage tier classification), Phase 3 (commit cadence), Phase 4 (wake decision tree), hard bounds, scratch-file schema, hand-back shape. Engine-specific surface is small: finding fetcher, retrigger mechanic, clean-signal parsing, failure modes.

Every bugbot-loop-cycle of PR #129 demonstrated the cost:

- **Cycle 1**: spacing-rule clarification + scratch field — 4 edits across 2 files for 2 logical changes.
- **Cycle 2**: Phase 3 step-3 restructure + Phase 4 pending-retrigger branch + scratch field — 6 edits across 2 files for 3 logical changes.
- **Self-referential meta-loop**: bugbot's first review introduced a spacing rule which (when added) created a structural gap that bugbot's second review caught. With a shared core, the structural gap would have been a single edit, not a mirrored-pair edit.

The dual-engine sync rule itself currently lives in BOTH files in near-duplicate form — and the design constraint that motivated this IDEA is that **dual-engine concurrent execution must be a first-class supported mode**, not just a co-incidence of two separately-invoked loops.

## Two abstraction shapes considered

### Option 1 — Shared skill + engine adapters (preferred)

```text
skills/review-loop/
  SKILL.md                     — Phase 0/1/3/4 skeleton, dual-engine orchestrator
  references/
    engine-bugbot.md           — fetcher, retrigger, clean-signal, failure modes
    engine-copilot.md          — ditto
    dual-engine-sync.md        — promoted from the currently-duplicated block
commands/
  bugbot-loop.md               — thin wrapper: ENGINES=bugbot → /review-loop
  copilot-loop.md              — thin wrapper: ENGINES=copilot → /review-loop
  review-loop.md               — direct entry: ENGINES=bugbot,copilot (any subset)
```

**Why preferred**:

- Dual-engine sync becomes a single orchestrator function iterating over an enabled-engines array. Adding a third engine later is one more adapter, not a third copy of the sync rule.
- Sprint-auto's `SPRINT_AUTO_REVIEW_ENGINE` selector (`bugbot` / `copilot` / `both` / `none`) is already the public API for this — the shared skill makes the implementation match the interface.
- Trade-off escape hatches (bugbot stalled >15min, copilot 2× service-error, etc.) become per-adapter timeout/error policies feeding one shared decision loop.
- Tier-1 codified patterns (currently bugbot-specific in `AGENT_bugbot.md` §1-8) can grow a copilot-specific sibling without touching the orchestrator.

**Risks**:

- Real refactor with rename-before-drop sequencing across both files.
- Phase 1 of the refactor must keep both entry points working byte-identical until the shared skill is validated; phase 2 cuts over the wrappers.
- Engine-adapter boundary needs careful design — too narrow (just shell commands) leaves prose decision-trees still duplicated; too wide (engine owns Phase 4 wake logic) defeats the purpose.

### Option 2 — Shared references, separate skills

```text
references/review-loop-core.md   — shared narrative both skills `[[link]]` into
commands/bugbot-loop.md          — still standalone, references the core file
commands/copilot-loop.md         — ditto
```

**Why considered**:

- Lower-risk, no executable plumbing.
- Fits the mind-vault references/ progressive-disclosure pattern.

**Why rejected as primary**:

- Skills still diverge over time — every cycle of PR #129 would have required editing both files anyway, because the **same prose** lives in two files.
- Does not support dual-engine concurrent execution as a first-class mode — that's still implemented as "run two loops, coordinate via ad-hoc sync block in each."

**Status**: kept as a fallback if Option 1's design constraints (adapter boundary, dual-engine state machine) prove unresolvable in /plan.

## Acceptance criteria

- One canonical skeleton for Phase 0/1/3/4 — no near-duplicate prose between bugbot and copilot entry points.
- Engine adapter contract documented in `references/engine-adapter-contract.md` — what an adapter must implement (fetch, retrigger, parse_clean, failure_modes) for the shared core to drive it.
- Dual-engine mode invokable directly via `/review-loop` with engine list, not just as a side effect of running both wrappers.
- Sprint-auto's `SPRINT_AUTO_REVIEW_ENGINE=both` continues to work without changes to sprint-auto itself.
- Mind-vault CHANGELOG entry attributes the refactor to PR #129's duplication-cost evidence.

## Sequencing (rename-before-drop applies)

1. **Phase 1**: Add `skills/review-loop/SKILL.md` + adapters; keep existing commands/ files untouched. New `/review-loop` command works end-to-end against either or both engines.
2. **Test pass** — run `/review-loop` on a real PR with both engines; verify behavioural parity with current `/bugbot-loop` + `/copilot-loop`.
3. **Phase 2**: Cut over `commands/bugbot-loop.md` and `commands/copilot-loop.md` to thin wrappers that invoke the shared skill with single-engine arg.
4. **Test pass** — re-run `/bugbot-loop <PR>` and `/copilot-loop <PR>` on real PRs; verify byte-identical hand-back semantics.
5. **Phase 3 (separate sprint)**: Remove the legacy duplicated prose from commands/ if it's not already gone (likely fully gone after Phase 2).

## Related

- PR #129 — the compound branch that surfaced the duplication cost concretely via bugbot's self-referential meta-loop on the spacing rule.
- `skills/sprint-auto/` — already uses `SPRINT_AUTO_REVIEW_ENGINE` selector; consumer of this abstraction.
