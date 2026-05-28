---
stage: plan
slug: review-thread-audit-hardening-cleanup
created: 2026-05-28
source: ./IDEA-010-review-thread-audit-hardening-cleanup.md
status: ready
project: mind-vault
architect_review: waived — single recipe-doc refinement reusing the existing adversarial-verify pattern; no new abstraction, coupling, or deployment surface. The one design decision (Step 2.5 vs better-single-prompt) is justified inline in § 6.
---

# Plan — IDEA-010: Retroactive review-thread audit hardening + mind-vault stale-thread cleanup

## 1. Context

`THREAD_AUTO_RESOLVE.md` shipped in v4.3.13 (#154). Dogfooding its Pattern 2 (retroactive audit + bulk-resolve) against mind-vault's own ~250 unresolved Copilot threads (16 merged PRs) exposed a concrete failure mode: a **single-pass Explore-agent audit systematically over-flags STILL-REAL**. Of the STILL-REAL verdicts spot-checked by hand, **5 of 5 were false positives** (CHANGELOG historical ref read as dead; `<img>` already in a code span read as live HTML; a contract "contradiction" the next line reconciles; "absence semantics undefined" that two lines define; a "see below" cross-ref absent from the file). Separately, one audit agent ran `git checkout main` in the **shared worktree**, switching the branch under the orchestrator.

## 2. Problem Frame

Pattern 2 gates bulk-resolve on **zero STILL-REAL**. With a high false-positive rate, that gate (a) **blocks a safe cleanup** outright, or (b) emits a **noisy false punch list** that re-creates the very signal pollution the recipe exists to clear — sending the operator chasing phantom bugs. The recipe's forward half (Pattern 1) already operates at high confidence; the retroactive half has no second opinion. And the worktree-checkout hazard can silently move the orchestrator's branch mid-run.

## 3. Requirements Trace

- **R1** (IDEA proposal 1) — Insert an adversarial-verify (refute) pass over STILL-REAL verdicts before they gate bulk-resolve or surface as a punch list. Only verdicts surviving refutation count.
- **R2** (IDEA proposal 1) — Record the observed false-positive rate as motivating provenance.
- **R3** (dogfooding side-effect) — Add a hazard rule: audit agents must read via `git show <ref>:<path>`, never `git checkout`, in a shared worktree.
- **R4** (IDEA proposal 2) — Operationalize: re-run the audit on the 16 mind-vault debt PRs *with* the adversarial pass, then bulk-resolve confirmed-safe threads.
- **R5** (IDEA proposal 3) — Memory: record the cleanup event + the over-flag finding.

## 4. Scope Boundaries

**In scope:** edit `skills/review-loop/references/THREAD_AUTO_RESOLVE.md` (Pattern 2 + Risks + Provenance); the operational mind-vault cleanup; one memory entry; CHANGELOG entry + version bump (handled at `/wrap`).

**Out of scope / non-goals:**
- Fixing `#120 scripts/install-wsl.ps1` PowerShell bugs (TLS 1.2, `Missing` switch fallthrough, `$vmMonitor` unused, whitespace `-Distro`) — real code, **handed back to the user**.
- Any teisutis work — a separate Claude Code session is running IDEA-155 there; **do not checkout branches on its worktree**. mind-vault-only.
- Pattern 1 (forward auto-resolve) — already high-confidence, untouched.
- Re-opening v4.3.13 (#154) — shipped + self-reviewed.

## 5. Context & Research

- Target file `skills/review-loop/references/THREAD_AUTO_RESOLVE.md` (on `main` as of #154). Anchors: `## Pattern 2 — Retroactive audit + bulk-resolve` → `### Step 2 — Audit before bulk-resolve` (line ~153), `### Step 3 — Bulk-resolve on a clean verdict` (line ~177), `## Risks + when not to fire` → "When retroactive audit should NOT auto-resolve" #1 (line ~231), `## Provenance` (line ~256).
- Existing in-repo pattern to reuse: the recipe **already references adversarial-verify as a known technique** (the Workflow/quality-patterns vocabulary; "spawn N skeptics prompted to REFUTE, default to refuted if uncertain"). R1 applies that existing pattern to the retroactive half — no new abstraction invented.
- Bulk-resolve primitive + normalized author filter (`sub("\\[bot\\]$"; "")`) already in the file (lines 140/195) — reused verbatim by R4.
- Bugbot-only review this cycle: Copilot engine is a noop (service down) — `/review-loop <PR> bugbot`.

## 6. Key Technical Decisions

- **Adversarial-verify as a discrete Step 2.5, not a better single-prompt audit.** A second independent agent prompted to *refute* (open the cited file, find the reconciling/defining text, default to false-positive if the claimed text isn't present verbatim) catches over-literal verdicts that a single pass — however well-prompted — structurally cannot self-catch. Mirrors Pattern 1's confidence model.
- **Default-to-false-positive on refutation.** The refuter's bias is opposite the auditor's: absent verbatim evidence of breakage, the verdict flips to false-positive. This is what fixes the 5/5 over-flag.
- **Gate on _confirmed_ STILL-REAL.** Step 3 and the "when NOT to fire" #1 change from "STILL-REAL count > 0" to "*confirmed* STILL-REAL (survived refutation) > 0". UNCERTAIN >10% rule unchanged.
- **`git show <ref>:<path>` mandate.** Audit agents in a shared worktree read file contents via `git show main:<path>` (or against the merge base), never `git checkout` — which mutates the shared branch. Stated as a hazard note in Step 2.
- **Per-PR resolution, not cohort-global.** Operationally, resolve each PR's confirmed-safe threads; leave only genuine opens visible (the recipe's "threads are the signal" ideal). `#120` stays fully open for the user.

## 7. Open Questions

- **Q1 — Resolve scope for #120.** Leave #120 entirely untouched (hand user the full punch list), or resolve its FIXED/WON'T-FIX threads and leave only the ~4 real code findings visible? _Default: leave #120 fully untouched_ — the user reserved it. (Resolved at execution per user confirm on the bulk-resolve gate.)
- **Q2 — Memory granularity.** One combined memory (cleanup event + over-flag finding) or two? _Default: one `feedback`-type entry_ (the over-flag finding is the durable lesson; the cleanup event is its provenance).

## 8. Execution Sequence

**Phase A — Harden the recipe (R1, R2, R3) — single commit:**
1. `THREAD_AUTO_RESOLVE.md`: insert `### Step 2.5 — Adversarially verify STILL-REAL` between Step 2 and Step 3. Define the refute-agent prompt + default-to-false-positive + "only survivors count."
2. Same file Step 2: add the `git show <ref>:<path>` hazard note (never `git checkout` in a shared worktree).
3. Same file Step 3 + "When retroactive audit should NOT auto-resolve" #1: retarget the gate to *confirmed* STILL-REAL.
4. Same file `## Provenance`: append the 5/5-false-positive dogfooding observation as motivation.
5. Self-sweep (RULE_self-sweep trigger 5, doc-consistency): section cross-refs, count claims, terminology.

**Phase B — Operational cleanup (R4) — no source change:**
6. Re-run the audit on the 16 debt PRs (#118,#120,#124,#131,#133,#134,#135,#136,#137,#140,#141,#144,#145,#146,#148,#149,#150) with the Step 2 + Step 2.5 adversarial pass. Reuse the prior audit output as the first-pass input; run the refuter only over its STILL-REAL set.
7. Produce the confirmed-STILL-REAL set (expected: ~0 in docs; the real ones isolated to #120).
8. **HUMAN-CONFIRM GATE** (`auto_safe: false`): present the confirmed set + resolve plan; on approval, bulk-resolve confirmed-safe threads per-PR. Leave #120 + any genuine opens.

**Phase C — Memory (R5):**
9. Write one `feedback`-type memory: single-pass retroactive audit over-flags STILL-REAL → adversarial refute pass required; names the mind-vault cleanup event as provenance. Add MEMORY.md pointer.

**Phase D — wrap (separate `/wrap` stage):** frontmatter → complete, index re-sort, devlog, CHANGELOG + patch bump, archive README backref.

## 9. Verification

- **Phase A:** `python -m mdformat --check` (or repo md convention) clean on the file; manual read confirms Step 2.5 prose, the gate wording in Step 3 + Risks #1 both say *confirmed* STILL-REAL, Provenance carries the 5/5 note. No broken intra-doc `§` refs.
- **Phase B:** the refuter re-classifies the prior STILL-REAL set; verify by spot-checking 2–3 of its "false-positive" flips against the actual files (the same way the 5/5 were caught). Confirmed-STILL-REAL list contains only #120 code items.
- **Phase B resolve:** after mutation, re-run the Step 1 inventory sweep — each cleaned PR returns 0 unresolved bot threads except its intentionally-left opens; `#120` unchanged.
- **Review:** `/review-loop <PR> bugbot` clears (bugbot-only; Copilot noop).
