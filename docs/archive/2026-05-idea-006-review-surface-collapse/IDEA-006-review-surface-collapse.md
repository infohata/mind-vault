---
id: 006
title: v4.3 review-surface collapse — delete AGENT_bugbot/AGENT_copilot + the /bugbot-loop·/copilot-loop wrappers, leaving only /review-loop
status: complete
completed: 2026-05-25
priority: high
supersedes: []
superseded_by: null
depends_on: [005]
related: []
created: 2026-05-20
target_version: v4.3
auto_safe: false
auto_safe_reason: "Two coupled deletions shipping as v4.3: (1) AGENT_bugbot/AGENT_copilot — migrate Common Patterns + failure-mode taxonomy + autonomy-ladder examples into skills/review-loop/references/engine-<x>.md + the shared skill, then delete; (2) the deprecated /bugbot-loop·/copilot-loop command wrappers — rewire every caller (notably sprint-auto's S3/S6/S11.10/S13/S14 dispatch + tool comment + README/guides) to /review-loop <PR> <engine>, then delete. /plan finding: sprint-auto couples to the COMMAND wrappers, not the agent files — the rewire is the load-bearing verification, done in PR-1 (prepare) and confirmed green before PR-2 (drop)."
sensitive_paths_cleared: true
sensitive_paths_cleared_reason: "Touches agents/AGENT_bugbot.md + AGENT_copilot.md, commands/{bugbot,copilot}-loop.md, skills/review-loop/** and skills/sprint-auto/SKILL.md (review-stage dispatch). /plan finding: sprint-auto couples via the /bugbot-loop·/copilot-loop COMMANDS, not the agent files. No auth, schema, secrets, or runtime config involved."
---

# IDEA-006: v4.3 review-surface collapse (delete the 3rd-party-engine agent profiles + the deprecated command wrappers)

**Status**: ✅ Complete (2026-05-25)
**Priority**: High
**Ships as**: v4.3 (the wrapper-removal narrative the v4.2 CHANGELOG reserved + the deprecation banners targeted)

## Scope expansion (2026-05-25): fold in the /bugbot-loop·/copilot-loop wrapper removal

IDEA-006 was originally agent-files-only. It now also lands the **deletion of the deprecated `/bugbot-loop` and `/copilot-loop` command wrappers** (deprecated in v4.2, removal targeted at v4.3), leaving `/review-loop <PR> <engine>` as the sole review entry point. The two collapses ship together as v4.3 because they're the same "one review surface, not three" cleanup.

**Critical /plan finding**: `skills/sprint-auto/SKILL.md` dispatches its review passes through the `/bugbot-loop` / `/copilot-loop` **commands** (S3, S6, S11.10, S13, S14 + its References list), NOT through `AGENT_bugbot` / `AGENT_copilot`. The agent files are referenced only by doc prose + the engine refs' "defer to" pointers. So the higher-blast-radius change is the command-wrapper rewire (sprint-auto must call `/review-loop <PR> bugbot|copilot`), and that rewire — not the agent-file deletion — is the load-bearing sprint-auto verification the original `auto_safe` blocker called for.
**Motivation**: PR #131's dogfood of IDEA-005 surfaced a recurring no-progress category — "AGENT_*.md trails the shared review-loop skill". Cycles 4, 5, 7, 8, 10 of that PR all caught different gaps where a shared-skill change (Phase 4 ordering, scratch-field rename, HARD SHORT-CIRCUIT directive, `no_progress_map` shape, etc.) didn't propagate to the agent files. Each cycle fixed the specific gap; the next cycle caught the next un-propagated change. The pattern is structural — orchestration mechanics live in two places (shared skill + agent files), so every shared-skill change risks drift.

## The decision (locked 2026-05-20)

**Delete `agents/AGENT_bugbot.md` and `agents/AGENT_copilot.md` entirely.** They were created when the per-engine commands were full skills with their own orchestration prose; IDEA-005 collapsed that surface to a single shared skill (`skills/review-loop/SKILL.md`), and `AGENT_curator` already carries the internal review-heuristics persona. There is no remaining role for separate sub-agent profiles dedicated to 3rd-party review engines (Bugbot / Copilot). Their unique content migrates into the shared skill's per-engine adapter references.

Two preservation targets that MUST survive the deletion:

1. **Common Bugbot Patterns §1-8** and **Common Copilot Patterns** (when populated) — codified Tier 1 auto-fix recipes. Bugbot's catalogue is empirically validated against multi-tenant Django SaaS PRs; Copilot's is shorter but growing. Migrate to `skills/review-loop/references/engine-bugbot.md` § Common patterns (currently defers; will inline) and `references/engine-copilot.md` § Common patterns (currently empty; will populate).
2. **Failure-mode taxonomy** — service-error patterns (Copilot), stall-detection thresholds (bugbot's `CHECKRUN status=in_progress` >15min), false-positive shapes (shallow-grep, ping-pong, etc.) and the response decision trees. Already partially mirrored in the engine references; merge the agent files' fuller treatments into those references.
3. **Autonomy ladder narrative** — Tier 1/2/3 narrative description with concrete examples. The shared skill already enumerates the tiers; the agent files have richer examples that should land in the shared skill's Phase 1 § Triage tier classification block.

Once these land in the references / shared skill, the agent files have no remaining unique value — `AGENT_curator` covers the internal sweep persona, the shared skill covers orchestration, the engine references cover engine specifics. Delete with confidence.

## Acceptance criteria

**Agent-file collapse:**

- `agents/AGENT_bugbot.md` and `agents/AGENT_copilot.md` deleted from the repo.
- The two identical 19-pattern catalogues (Common Bugbot Patterns ≡ Copilot Common Review Findings, word-for-word) consolidated into ONE shared `skills/review-loop/references/common-review-findings.md`, **deduplicated in both dimensions**: merged across the two agent files, AND not re-stating patterns that already have canonical homes elsewhere in the vault (#15→SHELL_INSTALLERS, #19→RULE_self-sweep § Contract-Change Sweep, #1/#11→django, #16/#17/#18→django-frontend gotchas). Catalogue is a scannable Tier-1 index (one-line + link to home; full prose only for homeless patterns) — no relocated redundancy. Both engine refs link to it.
- Engine-specific facts kept in their engine ref (`engine-bugbot.md` stall threshold; `engine-copilot.md` self-removal / COMMENTED-never-APPROVED / stale-context).
- Autonomy-ladder + hard-bounds already canonical in `skills/review-loop/SKILL.md` — not re-added; only port a pedagogically load-bearing example into Phase 1 § Triage if one adds signal (expect ~none).

**Command-wrapper collapse:**

- `commands/bugbot-loop.md` and `commands/copilot-loop.md` deleted; `/review-loop <PR> <engine>` is the sole review entry point.
- `skills/sprint-auto/SKILL.md` rewired: every `/bugbot-loop` / `/copilot-loop` dispatch (S3, S6, S11.10, S13, S14, References) collapses to a **single multi-engine** `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE` call — concurrent multi-engine sync when ≥2 engines are configured/available, generalizing to N engines. Selector *grammar* unchanged; the per-engine-sequential dispatch + "20 cycles per engine" budget are replaced by review-loop's concurrent session + session-level caps (reconcile `references/escalation-policy.md`). `none`-skip preserved.
- `tools/find_copilot_comments.sh` extend-the-tuple comment updated (no longer points at `commands/copilot-loop.md` / `AGENT_copilot.md`).

**Both:**

- All cross-references in `docs/`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `rules/`, other `skills/` updated to point at `/review-loop` / engine references instead of the deleted files. README + SPRINT_WORKFLOW mermaid nodes + ONBOARDING table updated; the v4.2 deprecation banners are removed (the thing they warned about has happened).
- Ships as **v4.3** with a CHANGELOG section; `make test-release` extracts `v4.3`.
- The "AGENT_*.md trails shared skill" no-progress category cannot resurface (files gone). Verified by the v4.3 PRs' own review loop.

## Sequencing — 2-PR prepare-then-drop (rename-before-drop applies)

Chosen over the original 3-PR shape (2026-05-25) because both surfaces share one "rename" phase (rewire + migrate) and one "drop" phase (delete), and they ship as one version. `rename-before-drop` forbids bundling the multi-file rewire with the deletes.

1. **PR-1 — Prepare (the "rename" phase; additive + rewire, zero deletions):**
   - Inline Common Bugbot Patterns §1-8 into `engine-bugbot.md` § Common patterns; merge Copilot taxonomy + Common Review Findings into `engine-copilot.md`; move autonomy-ladder examples into the shared skill's Triage block.
   - Rewire every `/bugbot-loop` / `/copilot-loop` and `AGENT_bugbot` / `AGENT_copilot` reference (sprint-auto, README, guides, ONBOARDING, tool comment, engine-ref "Per AGENT_*" attributions) to `/review-loop` / the engine refs.
   - All four target files still exist → no breakage. **Verify green** (full self-sweep + the v4.3 PR's own review loop). This is the merge gate that confirms sprint-auto's rewired dispatch is correct.

2. **PR-2 — Drop (the destructive phase; deletes only):**
   - `git rm agents/AGENT_bugbot.md agents/AGENT_copilot.md commands/bugbot-loop.md commands/copilot-loop.md`.
   - Re-grep for any surviving reference (must be zero). Re-run review loop for regression.
   - Bump + ship **v4.3**.

## Why 2 PRs not 1

- **PR-1 alone is safe to merge** — purely additive content + reference rewiring; all old files still exist, so even a missed pointer resolves. Both old and new locations coexist (rename-before-drop's overlap window).
- **PR-2 is the destructive step** — deleting the four files AFTER PR-1 lands green means any surviving reference fails loud (broken link / command-not-found) and bisects cleanly to PR-2, not muddled with content-migration questions.
- A single combined PR would bundle the multi-file rewire with the deletes — exactly the rename-before-drop anti-pattern (regressions become undifferentiated noise; no green-gate between rename and drop).

## Related

- IDEA-005 ([archive](../../archive/2026-05-idea-005-review-loop-shared-core/IDEA-005-review-loop-shared-core.md)) — parent refactor; collapsed the command surface. This IDEA finishes the job by collapsing the agent surface.
- PR #131 dogfood — concrete cycle-by-cycle evidence that AGENT_*.md drift is the residual duplication cost IDEA-005 didn't address.
- `agents/AGENT_curator.md` — the remaining sub-agent persona for review heuristics (internal sweep, codified Common Review Findings); takes over the slot the deleted agents leave.
