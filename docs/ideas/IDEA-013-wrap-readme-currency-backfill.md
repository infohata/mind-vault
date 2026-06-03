---
id: 013
title: Amend /wrap docs pass to audit + backfill the project's main README
status: idea          # idea | in-progress | complete | superseded
priority: medium   # high | medium | low
supersedes: []
superseded_by: null
depends_on: []
related: [3, 8]
created: 2026-06-03
completed: null
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
auto_safe: false
auto_safe_reason: "Design judgment to resolve in /plan — the audit cadence (every wrap vs doc-heavy-only vs version-bump-only vs staleness-threshold) and the audit checklist scope are open forks, not a mechanical additive change."
sensitive_paths_cleared: true
sensitive_paths_cleared_reason: "Touches only skills/wrap/SKILL.md (+ possibly a references/ doc) and project README.md — docs/process surface, no auth / permission / schema / infra / secrets."
---

# IDEA-013: Amend /wrap docs pass to audit + backfill the project's main README

**Status**: 💡 Idea
**Priority**: Medium

**Problem** (or opportunity): `/wrap`'s Step 6 (downstream docs scan) only greps the main README for the **current IDEA's** changed identifiers (deleted symbols, renamed models, new make-targets). It never audits the README as a **whole** against current reality. So the main README accumulates silent drift across many IDEAs — version-highlight framing goes stale (mind-vault's README still frames "v4 highlights" at v4.6), skill/command/agent counts fall behind, feature/capability tables miss newer skills, and stability flags (e.g. the sprint-auto ⚠️) outlive their cause — because **no single IDEA's wrap is responsible for whole-README currency**. Step 4 already solves exactly this shape for CHANGELOG/devlog via **backfill-gap detection** (list recently-merged PRs, cross-reference against entries, backfill ≤3 / surface larger gaps); the README has no equivalent.

**Evidence**: mind-vault's own README is dated despite IDEA-012 having just updated its claude/review-loop bits — the *other* sections (version highlights, counts, feature tables) had drifted unnoticed.

**Proposal** (or idea): Amend `/wrap`'s docs pass (extend Step 6, or a dedicated sub-step / `references/` doc) with a **main-README currency + backfill** check that audits the whole README — not just the IDEA's touched identifiers — against current reality. Candidate audit probes:

- **Version/highlight framing** vs the actual top CHANGELOG version (the `## v<N>` Step-4b already detects) — e.g. "v4 highlights" → "v4.6".
- **Counts** (skills / commands / agents / engines) vs the filesystem (`ls skills/*/SKILL.md | wc -l`, etc.).
- **Feature / capability tables** completeness vs shipped skills (a skill exists but isn't in the README's table).
- **Stale stability / ⚠️ flags** whose cause has since resolved.
- **Quick-start / command surface** vs the current commands + slash-invocable skills.

Disposition mirrors Step 6's patch-now-vs-follow-up + Step 4's backfill-gap rule: small mechanical drift (counts, version string, a missing table row) → fix in this wrap; large prose rewrite → surface as a follow-up (human-reviewed, never auto-rewritten).

**Why now**:
- mind-vault's README is the live dated example — the **dogfood / first backfill** lands in the same work.
- The capability surface is growing fast (a third review engine just shipped); the drift rate is increasing.

**Non-goals**:
- **Not** auto-rewriting architectural prose / high-level narrative — the existing Step 6 rule (human-review for architectural docs) stands; this audit flags + applies mechanical count/version/table fixes only.
- **Not** a separate `/readme-audit` command — it's a `/wrap` docs-pass enhancement, gated by cadence so it doesn't bloat every single-file wrap.
- **Not** a generated/templated README — it stays hand-authored; the check keeps the hand-authored file *honest*, it doesn't own it.

**Open questions** (for `/plan`):
- **Cadence** — run the whole-README audit on *every* wrap (too heavy for a one-file IDEA), only on **doc-heavy** wraps, only when **Step 4b version-bump fired**, or on a **staleness threshold** (e.g. README untouched for N merges)? Lean toward "version-bump wraps + doc-heavy wraps," but resolve in plan.
- Where it lives — inline Step 6 checklist additions vs a dedicated `skills/wrap/references/README_CURRENCY.md` loaded on demand (per the references-first promotion principle).
- How to make the counts project-agnostic (mind-vault counts skills/agents; another project counts apps/endpoints) — a small per-project hint, or purely heuristic.

**Related**: [IDEA-008](../archive/2026-05-idea-008-wrap-doc-finalization-scope/IDEA-008-wrap-doc-finalization-scope.md) (the `/wrap` `--scope` enum — the README audit should respect scope, e.g. skip under `idea-only`). [IDEA-003](../archive/2026-05-idea-003-version-tag-automation/IDEA-003-version-tag-automation.md) (Step-4b version-source detection — the README version-framing check should align with the version it detects).
