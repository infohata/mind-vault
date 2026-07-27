---
id: "019"
title: Research gstack — mine sprint-workflow patterns for mind-vault
status: idea          # idea | in-progress | complete | superseded
priority: medium   # high | medium | low
supersedes: []       # list of IDEA ids this replaces, or []
superseded_by: null
depends_on: []       # list of IDEA ids required before starting, or []
related: ["014"]             # list of IDEA ids that share context, or []
created: 2026-06-08
completed: null
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false                                     # true | false
auto_safe_reason: "Pure comparative research — the entire output is judgment calls about which gstack patterns are worth adopting and how they'd map onto mind-vault's conventions. No mechanical, reversible change to automate."
sensitive_paths_cleared: false         # true | false
sensitive_paths_cleared_reason: "The research pass itself touches no code (read-only analysis + a findings doc), but any adoption follow-on it spawns may hit skills/rules/plugin config and must clear its own gate. Left false so a human reads the recommendations before any are acted on."
---

# IDEA-019: Research gstack — mine sprint-workflow patterns for mind-vault

**Status**: 💡 Idea
**Priority**: Medium

**Problem** (or opportunity): [gstack](https://github.com/garrytan/gstack) is an open-source Claude Code "software factory" with a sprint-based workflow (Think → Plan → Build → Review → Test → Ship → Reflect) that is a direct cousin of mind-vault's own (idea → plan → work → review → compound). It ships a much wider surface — ~23 skills + ~8 power tools — covering capabilities mind-vault currently has thin or no coverage for. We have no systematic read on what it does better, where the designs diverge, and which patterns are worth porting vs. deliberately rejecting.

**Proposal** (or idea): A read-only comparative research pass that produces a findings doc mapping gstack's surface against mind-vault's, stage by stage, and flags concrete adopt / adapt / reject candidates — each as a potential downstream IDEA. Candidate areas to probe (from a first-pass scan; confirm in research):

- **Cross-model review** — gstack's `/codex` runs OpenAI Codex as a second-model reviewer. mind-vault's review-loop is multi-engine (Bugbot/Copilot/Claude) but single-vendor on the model axis; is a cross-model adversarial pass worth adding?
- **Real-browser testing** — `/browse` with a stealth Chromium. We have Playwright MCP available; is there a skill-level pattern worth formalizing?
- **Persistent knowledge base** — GBrain / `/learn` for cross-session memory vs. our auto-memory + `/compound`. Compare routing + recall models.
- **Security audit stage** — `/cso` with OWASP Top 10 + STRIDE. mind-vault has `security-review` but no dedicated threat-modeling persona/stage.
- **Parallel-sprint orchestration** — gstack's "Conductor" vs. our `sprint-auto` integration-as-merge-gate model.
- **Reflect / release stages** — `/document-release`, `/canary`, `/reflect` vs. our `/wrap` + `/land` + CHANGELOG discipline.
- **Prompt-injection defense** — ML-classifier guard; do we want any analog given the scrub-gate work (IDEA-018)?

**Why now**:
- It's a live, actively-maintained peer system solving the same problem — the cheapest learning available is reading someone else's converged design before we re-derive it.
- Feeds the backlog: each confirmed gap becomes a scoped IDEA, making future sprints richer without blocking current work.
- Relates to the stack-agnostic agent direction ([IDEA-014](IDEA-014-stack-agnostic-agents.md)) — gstack's multi-role / cross-model agent model is a reference point for where that architecture could go.

**Non-goals**:
- Not a wholesale port. mind-vault's minimalism (skills + rules + symlinks, no heavy runtime) is a deliberate stance; the output is a curated shortlist, not "adopt everything gstack has."
- Not implementation. This IDEA ends at a findings doc + spawned candidate IDEAs; each adoption is its own plan → work cycle with its own gates.
- No license/attribution decisions made here — flag them for follow-on if any pattern is borrowed closely.

**Related**: IDEA-014 (stack-agnostic agents) — gstack's multi-role/cross-model agent model is a comparison point for that architecture's trajectory.
