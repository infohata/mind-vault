---
id: 006
title: Delete AGENT_bugbot.md + AGENT_copilot.md — migrate unique content into review-loop adapter references
status: backlog
priority: high
supersedes: []
superseded_by: null
depends_on: [005]
related: []
created: 2026-05-20
auto_safe: false
auto_safe_reason: "Mechanical migration following the IDEA-005 pattern — preserve Common Patterns + failure-mode taxonomy + autonomy-ladder examples into skills/review-loop/references/engine-<x>.md, then delete the agent files. Sprint-auto sub-agent dispatch needs verification that the shared review-loop skill + AGENT_curator cover what AGENT_bugbot / AGENT_copilot previously did. /plan resolves the sprint-auto integration check before this is auto_safe."
sensitive_paths_cleared: true
sensitive_paths_cleared_reason: "Touches agents/AGENT_bugbot.md + AGENT_copilot.md + skills/review-loop/references/engine-<x>.md. Both agent files consumed by sprint-auto (sub-agent dispatch). No auth, schema, secrets, or runtime config involved."
---

# IDEA-006: Delete AGENT_bugbot.md + AGENT_copilot.md (3rd-party-engine sub-agent profiles supersede)

**Status**: 💡 Backlog
**Priority**: High
**Motivation**: PR #131's dogfood of IDEA-005 surfaced a recurring no-progress category — "AGENT_*.md trails the shared review-loop skill". Cycles 4, 5, 7, 8, 10 of that PR all caught different gaps where a shared-skill change (Phase 4 ordering, scratch-field rename, HARD SHORT-CIRCUIT directive, `no_progress_map` shape, etc.) didn't propagate to the agent files. Each cycle fixed the specific gap; the next cycle caught the next un-propagated change. The pattern is structural — orchestration mechanics live in two places (shared skill + agent files), so every shared-skill change risks drift.

## The decision (locked 2026-05-20)

**Delete `agents/AGENT_bugbot.md` and `agents/AGENT_copilot.md` entirely.** They were created when the per-engine commands were full skills with their own orchestration prose; IDEA-005 collapsed that surface to a single shared skill (`skills/review-loop/SKILL.md`), and `AGENT_curator` already carries the internal review-heuristics persona. There is no remaining role for separate sub-agent profiles dedicated to 3rd-party review engines (Bugbot / Copilot). Their unique content migrates into the shared skill's per-engine adapter references.

Two preservation targets that MUST survive the deletion:

1. **Common Bugbot Patterns §1-8** and **Common Copilot Patterns** (when populated) — codified Tier 1 auto-fix recipes. Bugbot's catalogue is empirically validated against multi-tenant Django SaaS PRs; Copilot's is shorter but growing. Migrate to `skills/review-loop/references/engine-bugbot.md` § Common patterns (currently defers; will inline) and `references/engine-copilot.md` § Common patterns (currently empty; will populate).
2. **Failure-mode taxonomy** — service-error patterns (Copilot), stall-detection thresholds (bugbot's `CHECKRUN status=in_progress` >15min), false-positive shapes (shallow-grep, ping-pong, etc.) and the response decision trees. Already partially mirrored in the engine references; merge the agent files' fuller treatments into those references.
3. **Autonomy ladder narrative** — Tier 1/2/3 narrative description with concrete examples. The shared skill already enumerates the tiers; the agent files have richer examples that should land in the shared skill's Phase 1 § Triage tier classification block.

Once these land in the references / shared skill, the agent files have no remaining unique value — `AGENT_curator` covers the internal sweep persona, the shared skill covers orchestration, the engine references cover engine specifics. Delete with confidence.

## Acceptance criteria

- `agents/AGENT_bugbot.md` and `agents/AGENT_copilot.md` deleted from the repo.
- Common Bugbot Patterns §1-8 preserved verbatim in `skills/review-loop/references/engine-bugbot.md` § Common patterns (no content loss).
- Copilot failure-mode taxonomy preserved verbatim in `skills/review-loop/references/engine-copilot.md` (consolidating any overlap with the existing § Failure modes table).
- Autonomy-ladder examples preserved in `skills/review-loop/SKILL.md` Phase 1 § Triage tier classification (whichever examples are pedagogically load-bearing).
- `sprint-auto` continues to dispatch the review stage correctly without `AGENT_bugbot` / `AGENT_copilot` references — verify the `SPRINT_AUTO_REVIEW_ENGINE` selector path still works end-to-end on a representative test PR.
- All cross-references in `docs/`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `rules/`, other `skills/` updated to point at the shared skill / engine references instead of the deleted agent files.
- A repeat dogfood on a follow-on PR confirms the "AGENT_*.md trails shared skill" no-progress category does not resurface (cannot — the files no longer exist).

## Sequencing (rename-before-drop applies)

1. **Phase 1** — Migrate content INTO the references:
   - Append Common Bugbot Patterns §1-8 to `skills/review-loop/references/engine-bugbot.md` § Common patterns (replacing the "defer to AGENT_bugbot.md" line).
   - Merge Copilot failure-mode taxonomy from `agents/AGENT_copilot.md` into `skills/review-loop/references/engine-copilot.md` § Failure modes (deduplicating overlap with the existing table).
   - Move autonomy-ladder examples into `skills/review-loop/SKILL.md` Phase 1 § Triage tier classification.
   - Ship as PR-1. After merge, content lives in BOTH places (rename-before-drop's overlap window).

2. **Phase 2** — Update all cross-references project-wide:
   - `grep -rln 'AGENT_bugbot\|AGENT_copilot'` and update each hit to point at the shared skill or engine reference.
   - Spot-check `AGENTS.md`, `CLAUDE.md`, `README.md`, `docs/guides/`, `rules/`, `skills/sprint-auto/SKILL.md`.
   - Ship as PR-2 (separable from PR-1 so the cross-ref sweep can be reviewed independently).

3. **Phase 3** — Delete the agent files:
   - `git rm agents/AGENT_bugbot.md agents/AGENT_copilot.md`.
   - Verify `sprint-auto` still dispatches correctly (test PR + `SPRINT_AUTO_REVIEW_ENGINE=bugbot` AND `=copilot` paths).
   - Ship as PR-3. Post-merge, the duplication is gone.

The three-PR split keeps each diff bisectable and reviewable in isolation. If sprint-auto's review-engine path needs surgery to remove `AGENT_*` references, that happens in PR-2 or PR-3 as appropriate.

## Why three PRs not one

- **PR-1 alone is safe to merge** — adds content without removing anything; both old and new locations exist, no breakage possible.
- **PR-2 alone is safe** — updates references but the old files still exist; broken pointers (if any) surface at link-check time, not at runtime.
- **PR-3 is the destructive step** — deleting the files. Doing this AFTER PR-1 and PR-2 land means: when something downstream still references the deleted files, the failure is loud (404, agent-not-found) and easy to bisect to PR-3 — not muddled with content-migration questions.

## Related

- IDEA-005 ([archive](../../archive/2026-05-idea-005-review-loop-shared-core/IDEA-005-review-loop-shared-core.md)) — parent refactor; collapsed the command surface. This IDEA finishes the job by collapsing the agent surface.
- PR #131 dogfood — concrete cycle-by-cycle evidence that AGENT_*.md drift is the residual duplication cost IDEA-005 didn't address.
- `agents/AGENT_curator.md` — the remaining sub-agent persona for review heuristics (internal sweep, codified Common Review Findings); takes over the slot the deleted agents leave.
