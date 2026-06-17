---
id: 022
title: Claude adapter HAS_FINDINGS false-positive on resolved-recap summaries
status: complete          # idea | in-progress | complete | superseded
priority: high   # high | medium | low
supersedes: []
superseded_by: null
depends_on: []
related: [012, 021]
created: 2026-06-17
completed: 2026-06-17
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false
auto_safe_reason: "Refining the claude adapter's findings heuristic is a judgment-heavy parsing change with a real regression risk — it must not weaken the genuine dual-substantive-verdict detection that legitimately catches disagreeing same-SHA verdicts. Needs design + test cases."
sensitive_paths_cleared: false
sensitive_paths_cleared_reason: "Touches tools/find_claude_comments.sh + skills/review-loop, the core review orchestration every review run (and sprint-auto) depends on. A human should review the heuristic change."
---

# IDEA-022: Claude adapter HAS_FINDINGS false-positive on resolved-recap summaries

**Status**: ✅ Complete (2026-06-17)
**Priority**: High

**Problem** (or opportunity): `tools/find_claude_comments.sh`'s `HAS_FINDINGS` / dual-verdict-masking heuristic **over-flags a clean summary as findings-bearing** when that summary is a *"previous findings — all resolved"* recap. Surfaced live in the IDEA-021 dogfood (PR #207): claude posted a summary reading **"Verdict: ready to merge. No open issues. All findings from both prior review rounds are resolved in HEAD. The PR is clean."** with a `### Previous findings — all resolved ✅` checklist — and the adapter set `CLAUDE_HAS_FINDINGS=true`, raising a spurious **dual-verdict-masking STILL_FINDING** alarm. The heuristic appears to key on the literal token "findings" and/or `[x]` checklist / resolved-list markers rather than on *open, actionable* findings.

Impact: this is a **convergence-blocker for any multi-cycle claude review**. Iterative review almost always ends with claude posting an "all previous findings resolved" recap — exactly the shape that trips the false-positive. A loop following the structural rule mechanically would read STILL_FINDING forever and never declare CLEAN. In the dogfood it was only caught because the agent adversarially read the full verdict and overrode (consistent with [`THREAD_AUTO_RESOLVE`] / the retroactive-audit "always refute" lesson) — but that manual override shouldn't be load-bearing.

**Proposal** (or idea): **Replace the prose regex classifier with an orchestrator-inline model-judge** (settled during `/plan`, 2026-06-17). Trying to classify claude's *model-generated prose* with regex (`CLAUDE_CLEAN_PATTERNS` / `CLAUDE_FINDING_MARKERS`) is the wrong tool by construction — this false-positive and its inverse (a marker-less prose finding reading false-CLEAN, surfaced by the architect review of the abandoned regex-broadening draft) are the same root failure. Instead:

- `find_claude_comments.sh` is reduced to **surfacing material** (structural Actions-job RUNNING/DONE, inline-finding enumeration, summary body, per-SHA verdict set); it stops computing a clean/findings verdict from prose.
- The `/review-loop` agent **judges the full review material** and emits a **tiered verdict — `CLEAN` · `BLOCKING` · `NON_BLOCKING[]`**. Non-blocking items don't block convergence; they're absorbed (fixed this PR) or formalized as new IDEAs.
- The never-false-CLEAN bias moves from regex to a **judge instruction** + a structural backstop (unresolved head-SHA inline threads ⇒ not CLEAN). Claude-only; bugbot/copilot keep structured parsing. Full design in the plan.

**Why now**:
- Just surfaced concretely in the IDEA-021 dogfood as **F-dogfood-5** with a captured real example (PR #207, claude summaries `4729548936` / `4729623919`) — a reproducible artefact to design + test against.
- It silently undermines the claude engine's value in the exact workflow it's meant for (iterate-to-clean); worth fixing before the next claude-engine-heavy review.

**Non-goals**:
- Weakening the never-false-CLEAN bias (a missed blocking finding) — it's preserved, relocated from regex to a judge instruction + the unresolved-inline-thread structural backstop.
- Changing the Monitor accelerator or any IDEA-021 surface.
- Touching bugbot/copilot classification — claude-only (they emit structured findings where the structural rule works).
- Auto-creating IDEAs from non-blocking items without human confirmation.

**Related**: [IDEA-012](../archive/2026-06-idea-012-claude-code-review-engine/IDEA-012-claude-code-review-engine.md) (the claude engine adapter this refines) · IDEA-021 (the Monitor-accelerator dogfood that surfaced it, PR #207).
