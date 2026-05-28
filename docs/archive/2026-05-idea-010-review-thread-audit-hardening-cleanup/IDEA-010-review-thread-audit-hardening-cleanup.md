---
id: 010
title: Retroactive review-thread audit hardening + mind-vault stale-thread cleanup
status: in-progress          # idea | in-progress | complete | superseded
priority: medium   # high | medium | low
supersedes: []       # list of IDEA ids this replaces, or []
superseded_by: null
depends_on: []       # list of IDEA ids required before starting, or []
related: []             # list of IDEA ids that share context, or []
created: 2026-05-28
completed: null
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false                                     # true | false
auto_safe_reason: "Deliverable 2 fires bulk `resolveReviewThread` GraphQL mutations against real merged PRs and gates on per-thread refutation judgment; a human must confirm the cleared verdict before mutations run."
sensitive_paths_cleared: false         # true | false
sensitive_paths_cleared_reason: "Files touched are docs-only (skills/review-loop/references), outside auth/schema/infra zones — but the operational step mutates GitHub PR review-thread state in bulk, which warrants a human eyeball before execution."
---

# IDEA-010: Retroactive review-thread audit hardening + mind-vault stale-thread cleanup

**Status**: 💡 Idea
**Priority**: Medium

**Problem** (or opportunity): Dogfooding the v4.3.13 `THREAD_AUTO_RESOLVE` retroactive recipe (`skills/review-loop/references/THREAD_AUTO_RESOLVE.md`) against mind-vault's own ~250 unresolved Copilot threads (16 merged PRs) exposed a real gap: a **single-pass Explore-agent audit systematically over-flags STILL-REAL**. Spot-verification found **5 of 5** checked STILL-REAL verdicts were false positives — a CHANGELOG historical-accuracy reference read as a dead link (#140); an `<img>` already inside a code span read as live HTML (#144); a contract "contradiction" the very next line reconciles (#131); "absence semantics undefined" that lines 22/45 fully define (#131/#145); and a "see below / spacing" cross-reference that **does not exist in the files at all** (#145). Because Pattern 2 gates bulk-resolve on **zero STILL-REAL**, this over-flagging would either block a safe cleanup outright or send the operator chasing phantom bugs — and surface a noisy false punch list that re-creates the very signal pollution the recipe exists to clear.

**Proposal** (or idea):
1. **Harden Pattern 2 (Retroactive audit) with an adversarial-verify pass.** Every STILL-REAL verdict from the first audit must be independently re-verified by a second agent prompted to **REFUTE** it: open the cited file, locate the reconciling / defining text, and **default to false-positive if the claim's described text is not present verbatim**. Only verdicts that survive refutation count toward the zero-STILL-REAL gate or the surfaced punch list. Record the observed false-positive rate as motivating provenance. (Pattern 1 / forward auto-resolve already operates at high confidence — fix is scoped to the retroactive half.)
2. **Operationalize the cleanup.** Re-run the audit on mind-vault's 17 debt PRs *with* the adversarial pass, then bulk-resolve the confirmed-safe threads (the overwhelming majority), leaving open only genuinely-real findings — specifically the `#120 scripts/install-wsl.ps1` PowerShell-code bugs (TLS 1.2 not enforced before kernel-MSI download; `Get-FeatureState` `'Missing'` falls through the `switch` default; `$vmMonitor`/VT-x computed but never gates install; whitespace-only `-Distro`). Those are real code, handed back to the user, not docs.
3. **Memory.** Record the mind-vault cleanup event + the single-pass-audit-over-flags finding for future sessions.

**Why now**:
- The over-flag finding is fresh and concrete (5/5 false-positive sample). It directly weakens the recipe just shipped in v4.3.13; close the loop while the evidence is in hand.
- mind-vault carries a live ~250-thread noise pile that hides any genuine signal on its own PRs.

**Non-goals**:
- Fixing the `#120 install-wsl.ps1` code bugs — those are real and belong to the user's own follow-up, not this docs/ops IDEA.
- Touching the teisutis repo (a separate Claude Code session is running IDEA-155 there; do not checkout branches on its worktree). This IDEA is **mind-vault-only**.
- Re-opening the v4.3.13 thread-auto-resolve PR — it stands as self-reviewed.

**Related**: Extends the v4.3.13 `/compound` that created `skills/review-loop/references/THREAD_AUTO_RESOLVE.md` (no IDEA id — it shipped as a compound). Constraint for the review stage: **GitHub Copilot is a noop currently (service down)** — `/review-loop` runs **bugbot-only**.
