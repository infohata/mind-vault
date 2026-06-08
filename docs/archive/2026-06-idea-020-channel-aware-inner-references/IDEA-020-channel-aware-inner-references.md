---
id: 020
title: Channel-aware inner command/skill references (plugin-route correctness)
status: in-progress        # idea | in-progress | complete | superseded
priority: high   # high | medium | low
supersedes: []       # list of IDEA ids this replaces, or []
superseded_by: null
depends_on: []       # list of IDEA ids required before starting, or []
related: [017]             # list of IDEA ids that share context, or []
created: 2026-06-08
completed: null
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false                                     # true | false
auto_safe_reason: "Modifies the workflow-orchestration engine itself (sprint-auto stage dispatch, review-loop re-entry, every skill's sibling-command references) and hinges on an unverified unknown — how the Skill tool + literal slash dispatch resolve prefixed-vs-bare names on the plugin channel. That audit is a design/judgment call a human must own before any mechanical rewrite."                     # why safe, or what blocks — 1-2 sentences
sensitive_paths_cleared: false         # true | false
sensitive_paths_cleared_reason: "Touches the unattended-execution substrate (sprint-auto) and the review loop that gate every other IDEA's delivery — a regression here silently breaks the whole sprint workflow overnight. Human-verified rollout required, ironically most on the very plugin-only host this fixes."       # any auth/permission/schema/infra touch? — 1-2 sentences
---

# IDEA-020: Channel-aware inner command/skill references (plugin-route correctness)

**Status**: 💡 Idea
**Priority**: High

**Problem** (or opportunity): On the **plugin route** (IDEA-017), Claude Code namespaces all mind-vault commands/skills under `mv:` (`/mv:work`, `/mv:review-loop`, …). Any skill that **invokes a sibling by bare name** — a literal slash command or a `Skill` tool call — does **not** resolve on a plugin-only machine, and the failure is silent. Discovered live by switching the authoring machine to plugin-only mid-`/review-loop`: the loop's `ScheduleWakeup(prompt="/review-loop …")` self-re-entry would have fired into a non-existent command and the loop would have died on its next wake with no error. `review-loop`'s re-entry was hot-fixed in **PR #190's follow-up PR #193 (v5.1.2)** — `reentry_command` now mirrors the invocation prefix and is persisted to scratch — but that is one site of a whole class. The highest-stakes unfixed site is **`sprint-auto`**, which dispatches every stage (`/plan → /work → /wrap → /review-loop → /land → /compound`) by bare name, **unattended overnight on a VPS** — exactly the host the IDEA-017 docs (PR #193) now *recommend* run the marketplace plugin. A bare-name dispatch failure there is a silent 3am death of the entire batch.

**Proposal** (or idea): Make all inner command/skill references channel-aware.
1. **Audit first (the load-bearing unknown):** determine empirically how the `Skill` tool and literal slash dispatch resolve names on the plugin channel — does `Skill(skill="work")` resolve, or is `mv:work` required? Does a literal `/work` typed/injected by an orchestrator resolve, or only `/mv:work`? The fix shape depends entirely on this. (`${CLAUDE_PLUGIN_ROOT}` is NOT exposed in the agent's shell, so detection must come from the invocation form, not an env probe — same constraint that drove the review-loop fix.)
2. **Generalise the review-loop precedent:** "mirror the prefix you were invoked with," persisted where it must survive compaction. Apply to every sibling-dispatch site — `sprint-auto` stage calls foremost, then any `/plan`/`/work`/`/wrap`/`/land`/`/compound` cross-references that are *executed* (not merely prose-mentioned). Per Q3/IDEA-017, prose mentions of sibling commands stay bare; only **executed** dispatches need the prefix.
3. **Reconcile the IDEA-017 docs:** PR #193 recommends the marketplace plugin for the sprint-auto VPS. Until this lands, that recommendation is unsafe — add a hedge ("verify channel-safe dispatch before going plugin-only on a sprint-auto host") or hold the recommendation.

**Why now**:
- IDEA-017 just shipped the plugin route and the authoring machine is now plugin-only — the latent break is live, not theoretical.
- The docs already point the most fragile workload (unattended `sprint-auto`) at the channel it isn't safe on — a shipped contradiction.
- The precedent fix (review-loop, PR #193) exists; this generalises it before the next overnight run hits it.

**Non-goals**:
- Rewriting **prose** mentions of sibling commands to be channel-aware — Q3/IDEA-017 deliberately left those bare (skills fire by description; only *executed* dispatch needs the prefix).
- Changing the namespacing scheme itself (`mv:` is settled, IDEA-017 Q3).
- Re-architecting how skills invoke each other beyond the minimal prefix-awareness.

**Related**: Amends/depends-on [IDEA-017](../archive/2026-06-idea-017-mind-vault-cc-plugin/IDEA-017-mind-vault-as-claude-code-plugin.md) (the plugin route that introduced the namespacing). Precedent fix: review-loop `reentry_command`, shipped in PR #193 (v5.1.2).
