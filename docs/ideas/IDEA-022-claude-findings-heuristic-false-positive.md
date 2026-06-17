---
id: 022
title: Claude adapter HAS_FINDINGS false-positive on resolved-recap summaries
status: idea          # idea | in-progress | complete | superseded
priority: high   # high | medium | low
supersedes: []
superseded_by: null
depends_on: []
related: [012, 021]
created: 2026-06-17
completed: null
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false
auto_safe_reason: "Refining the claude adapter's findings heuristic is a judgment-heavy parsing change with a real regression risk — it must not weaken the genuine dual-substantive-verdict detection that legitimately catches disagreeing same-SHA verdicts. Needs design + test cases."
sensitive_paths_cleared: false
sensitive_paths_cleared_reason: "Touches tools/find_claude_comments.sh + skills/review-loop, the core review orchestration every review run (and sprint-auto) depends on. A human should review the heuristic change."
---

# IDEA-022: Claude adapter HAS_FINDINGS false-positive on resolved-recap summaries

**Status**: 💡 Idea
**Priority**: High

**Problem** (or opportunity): `tools/find_claude_comments.sh`'s `HAS_FINDINGS` / dual-verdict-masking heuristic **over-flags a clean summary as findings-bearing** when that summary is a *"previous findings — all resolved"* recap. Surfaced live in the IDEA-021 dogfood (PR #207): claude posted a summary reading **"Verdict: ready to merge. No open issues. All findings from both prior review rounds are resolved in HEAD. The PR is clean."** with a `### Previous findings — all resolved ✅` checklist — and the adapter set `CLAUDE_HAS_FINDINGS=true`, raising a spurious **dual-verdict-masking STILL_FINDING** alarm. The heuristic appears to key on the literal token "findings" and/or `[x]` checklist / resolved-list markers rather than on *open, actionable* findings.

Impact: this is a **convergence-blocker for any multi-cycle claude review**. Iterative review almost always ends with claude posting an "all previous findings resolved" recap — exactly the shape that trips the false-positive. A loop following the structural rule mechanically would read STILL_FINDING forever and never declare CLEAN. In the dogfood it was only caught because the agent adversarially read the full verdict and overrode (consistent with [`THREAD_AUTO_RESOLVE`] / the retroactive-audit "always refute" lesson) — but that manual override shouldn't be load-bearing.

**Proposal** (or idea): Refine the claude adapter's findings detection to distinguish an **open-findings** summary from a **resolved-recap / clean** summary. Candidate directions (to be settled in `/plan`):

- Anchor `HAS_FINDINGS` on actual inline review-thread findings for the head SHA (line-anchored comments) rather than summary-body token matching; treat the summary body as corroborating, not authoritative.
- If summary-body parsing is kept, require an *open*-finding signal (e.g. unchecked `[ ]` items, an explicit "Issues found" / severity block) and explicitly exclude resolved-recap structures ("all resolved", "✅", "ready to merge", "no open issues", "no new issues").
- Preserve the genuine dual-substantive-verdict detection (the case where two same-SHA verdicts actually disagree, one carrying a real open finding) — the refinement must narrow false positives **without** reintroducing the masking the dual-verdict rule exists to catch.

**Why now**:
- Just surfaced concretely in the IDEA-021 dogfood as **F-dogfood-5** with a captured real example (PR #207, claude summaries `4729548936` / `4729623919`) — a reproducible artefact to design + test against.
- It silently undermines the claude engine's value in the exact workflow it's meant for (iterate-to-clean); worth fixing before the next claude-engine-heavy review.

**Non-goals**:
- Weakening or removing dual-substantive-verdict detection (the legitimate case where same-SHA verdicts disagree on a real open finding).
- Changing the Monitor accelerator or any IDEA-021 surface — this is the claude *adapter* parse layer only.
- Re-architecting the engine-adapter contract; this is a targeted heuristic fix within the existing claude adapter.

**Related**: [IDEA-012](../archive/2026-06-idea-012-claude-code-review-engine/IDEA-012-claude-code-review-engine.md) (the claude engine adapter this refines) · IDEA-021 (the Monitor-accelerator dogfood that surfaced it, PR #207).
