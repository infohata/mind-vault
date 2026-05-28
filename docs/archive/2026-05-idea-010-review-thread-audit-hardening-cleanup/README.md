# IDEA-010 — Retroactive review-thread audit hardening + mind-vault stale-thread cleanup

**Status:** ✅ Complete (2026-05-28) · **PR:** [#155](https://github.com/infohata/mind-vault/pull/155) · **Ships as:** v4.3.14

## What shipped

A two-part follow-on to the v4.3.13 `THREAD_AUTO_RESOLVE` compound, born from dogfooding that recipe against mind-vault's own Copilot-thread debt.

1. **Recipe hardening** (`skills/review-loop/references/THREAD_AUTO_RESOLVE.md`)
   - **Step 2.5 — adversarially verify every STILL-REAL**: an independent refuter agent (default-to-false-positive, verbatim evidence required) re-checks every first-pass STILL-REAL before it gates bulk-resolve or reaches a punch list. Only confirmed survivors count.
   - Bulk-resolve gate (Step 3, "when NOT to fire" #1, intro summary) retargeted to *confirmed* STILL-REAL.
   - **Shared-worktree read hazard**: audit/refute agents read via `git show <ref>:<path>`, never `git checkout` (one agent checked out `main` and switched the parent session's branch mid-run).
   - Provenance: the 5/5-false-positive observation.

2. **Operational cleanup** — re-audited the 17 debt PRs with Step 2.5 (collapsed ~27 first-pass STILL-REAL → **4 confirmed**, ~85% over-flag caught), then **resolved 250 stale Copilot threads** across all 17 PRs. The 4 genuine findings were fixed in-branch:
   - `#120 scripts/install-wsl.ps1` ×3 — TLS 1.2 before kernel-MSI download; `$vmMonitor` consulted in the virt warning (not a hard gate — Hyper-V false-negative); `-Distro` trim.
   - `#118` docs ×3 — README Skills 15→17 + Agents 9→8 (removed deleted bugbot/copilot row); sprint-auto S15 diagram.

3. **Memory** — `feedback_retroactive_audit_overflags_still_real.md` (auto-memory, outside repo).

## Key learning

A single-pass audit is a **finder, not a verifier** — it over-flags STILL-REAL (~85% here), and a gate on raw verdicts either blocks a safe cleanup or ships a false punch list. The retroactive recipe now gets the same adversarial confidence the forward recipe always had.

## Deviations from the plan

- The plan's non-goal "leave #120 code to the user" was **amended mid-flight** — at the held-PR gate the user opted into fixing #120's PowerShell + #118's docs. Both done in-branch.
- Step-6 wrap scan surfaced a clean contradiction in `sprint-auto/SKILL.md` (S15 artefact list) — patched in this PR.

## Follow-ups (punted)

- ✅ **sprint-auto v3.1→v3.2 doc sweep — ADDRESSED** (the find we expected). A multi-dimensional `sprint-auto` review (6 reviewers + adversarial refute, the IDEA-010 Step-2.5 discipline applied to a skill audit) confirmed 25 findings; the v4.4 sprint-auto doc-migration (`chore/sprint-auto-v32-doc-migration`) reconciled all of them — forward-sync/re-review/draft-PR drift across SKILL.md + references + the log template, plus the real cross-skill gap (added the `/wrap --integration` mode that the docs handed off to but didn't exist). sprint-auto flagged ⚠️ unstable pending a runtime shakedown.
- **`install-wsl.ps1` Win10 smoke test** — the 3 PowerShell fixes can't be runtime-tested in a Linux/Docker environment.

## Pointers

- [IDEA-010 file](IDEA-010-review-thread-audit-hardening-cleanup.md)
- [Plan](2026-05-28-review-thread-audit-hardening-cleanup-plan.md)
