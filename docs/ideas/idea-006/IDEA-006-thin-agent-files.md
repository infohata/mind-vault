---
id: 006
title: Thin AGENT_bugbot.md + AGENT_copilot.md to delegate orchestration to the shared review-loop skill
status: backlog
priority: high
supersedes: []
superseded_by: null
depends_on: [005]
related: []
created: 2026-05-20
auto_safe: false
auto_safe_reason: "Doable mechanically following the IDEA-005 pattern, but the agent files carry rich Common Patterns and failure-mode taxonomies that must be preserved verbatim. /plan must decide which sections delegate to the shared skill vs stay in the agent files. Once that's resolved, the cutover itself is a straight rename-before-drop sequence."
sensitive_paths_cleared: true
sensitive_paths_cleared_reason: "Touches agents/AGENT_bugbot.md + AGENT_copilot.md, both consumed by sprint-auto. No auth, schema, secrets, or runtime config involved."
---

# IDEA-006: Thin AGENT_bugbot.md + AGENT_copilot.md (sibling to IDEA-005's command-surface thinning)

**Status**: 💡 Backlog
**Priority**: High
**Motivation**: PR #131's dogfood of IDEA-005 surfaced a recurring no-progress category — "AGENT_*.md trails the shared review-loop skill". Cycles 4, 5, 7, 8, 10 of that PR all caught different gaps where a shared-skill change (Phase 4 ordering, scratch-field rename, HARD SHORT-CIRCUIT directive, `no_progress_map` shape, etc.) didn't propagate to the agent files. Each cycle fixed the specific gap; the next cycle caught the next un-propagated change.

## The pain

IDEA-005 thinned `commands/bugbot-loop.md` + `commands/copilot-loop.md` from ~260L each to ~15L wrappers that delegate to the shared `skills/review-loop/SKILL.md`. The command surface no longer drifts.

But `agents/AGENT_bugbot.md` and `agents/AGENT_copilot.md` still carry **the same orchestration mechanics in full** — Hard Bounds, the 4-Pass workflow, decision-tree wording, scratch-file schema, retrigger discipline. Every shared-skill update needs to be mirrored across these two files, which is exactly the duplication IDEA-005 set out to eliminate.

## Two preservation targets in the agent files

Unlike the command wrappers (which had nothing unique to preserve), the agent files carry content the shared skill does NOT have:

1. **Common Bugbot Patterns / Common Review Findings** — codified Tier 1 auto-fix recipes. Bugbot's catalogue is empirically validated against multi-tenant Django SaaS PRs; Copilot's is shorter but growing.
2. **Failure-mode taxonomy** — service-error patterns (Copilot), stall-detection thresholds (bugbot's `CHECKRUN status=in_progress` >15min), false-positive shapes (shallow-grep, ping-pong, etc.).
3. **Autonomy ladder explanation** — narrative description of Tier 1/2/3 with concrete examples.

These MUST survive the thinning. The shared skill's references (`engine-bugbot.md`, `engine-copilot.md`) already gesture at them but don't carry the full content.

## Proposed shape

```text
agents/AGENT_bugbot.md   (target ~80L)
  - Identity + role
  - Common Bugbot Patterns §1-8 (verbatim from current)
  - Failure-mode taxonomy (verbatim)
  - Autonomy ladder examples
  - Delegate to skills/review-loop/SKILL.md for: hard bounds, 4-pass workflow,
    scratch schema, retrigger discipline, decision tree

agents/AGENT_copilot.md  (target ~70L)
  - Same shape, Copilot-specific content (dual login, service-error pattern,
    remove+add caveat)
```

Or — alternatively — fold the unique content into the existing
`skills/review-loop/references/engine-<x>.md` adapter docs and delete the
agent files entirely. The adapter docs already carry most of the engine-specific
prose; pulling in Common Patterns would complete the migration. Sprint-auto's
sub-agent dispatch would then route through the wrapper commands directly.

`/plan` resolves which approach fits sprint-auto's actual usage pattern.

## Acceptance criteria

- After cutover, a change to the shared review-loop's Phase 4 decision tree, scratch schema, or hard bounds requires editing ONLY `skills/review-loop/SKILL.md` (or the relevant reference). No mirror-edit in agent files.
- Common Bugbot Patterns §1-8 + Copilot failure-mode taxonomy preserved verbatim somewhere in the repo (no content loss).
- Sprint-auto's sub-agent dispatch continues to work without changes to sprint-auto itself.
- A repeat dogfood on a follow-on PR confirms the "AGENT_*.md trails shared skill" no-progress category does not resurface.

## Sequencing (rename-before-drop applies)

1. **Phase 1**: Decide the target shape (thin agents preserving unique content vs full migration into `references/engine-*.md`). `/plan` deliverable.
2. **Phase 2**: Apply the cutover. Keep the legacy mechanics paragraphs as collapsed-by-default sections OR delete entirely depending on Phase 1 outcome.
3. **Test pass**: Re-run a representative review-loop session against a fresh PR; verify no behavioural drift from IDEA-005's state.
4. **Phase 3** (separate sprint): If the agent files survive Phase 2, audit them again 1-2 sprints later for any new drift; remove residual duplication.

## Related

- IDEA-005 ([docs/ideas/idea-005/](../idea-005/IDEA-005-review-loop-shared-core.md)) — parent refactor; thinned the command surface. This IDEA extends the treatment to the agent surface.
- PR #131 dogfood — concrete cycle-by-cycle evidence that AGENT_*.md drift is the residual duplication cost IDEA-005 didn't address.
