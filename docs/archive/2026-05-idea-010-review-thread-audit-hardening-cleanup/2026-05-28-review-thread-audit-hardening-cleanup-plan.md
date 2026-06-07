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
- **R4** (IDEA proposal 2) — Operationalize: re-run the audit on the 17 mind-vault debt PRs *with* the adversarial pass, then bulk-resolve confirmed-safe threads.
- **R5** (IDEA proposal 3) — Memory: record the cleanup event + the over-flag finding.

## 4. Scope Boundaries

**In scope:** edit `skills/review-loop/references/THREAD_AUTO_RESOLVE.md` (Pattern 2 + Risks + Provenance); the operational mind-vault cleanup; one memory entry; CHANGELOG entry + version bump (handled at `/wrap`).

**Out of scope / non-goals:**
- Fixing `#120 scripts/install-wsl.ps1` PowerShell bugs (TLS 1.2, `Missing` switch fallthrough, `$vmMonitor` unused, whitespace `-Distro`) — real code, **handed back to the user**.
- Any work in a consuming project — a separate Claude Code session is running its own IDEA there; **do not checkout branches on its worktree**. mind-vault-only.
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

**Phase A status:** ✅ done (commit `b724768`) — Step 2.5 + gate retarget + worktree hazard + provenance; count 16→17 corrected.

**Phase B — Operational cleanup (R4) — no source change:**
6. ✅ Re-ran the audit on the 17 debt PRs with the Step 2.5 adversarial-refute pass (4 refuter agents over the first-pass STILL-REAL set). **Result: of ~27 first-pass STILL-REAL, only 4 confirmed (~85% over-flag) — 1 doc (#118 S15 diagram), 3 code (#120).**
7. ✅ Confirmed-STILL-REAL set: #120 (whitespace `-Distro`, `$vmMonitor` ungated, no TLS 1.2) + #118 (post-pr-sequence.md S15 diagram). All other STILL-REAL refuted.
8. ✅ **HUMAN-CONFIRM GATE** — user approved "resolve 15 safe PRs now". **176 threads resolved** across #124,#133,#134,#135,#136,#137,#141,#146,#148,#149,#150,#131,#140,#144,#145; verified 0 unresolved remaining. **#118 (35) + #120 (39) held** — disposition options in § 10.

**Phase C — Memory (R5):**
9. ✅ Wrote `feedback_retroactive_audit_overflags_still_real.md` + MEMORY.md pointer.

**Phase D — wrap (separate `/wrap` stage):** frontmatter → complete, index re-sort, devlog, CHANGELOG + patch bump, archive README backref.

## 9. Verification

- **Phase A:** `python -m mdformat --check` (or repo md convention) clean on the file; manual read confirms Step 2.5 prose, the gate wording in Step 3 + Risks #1 both say *confirmed* STILL-REAL, Provenance carries the 5/5 note. No broken intra-doc `§` refs.
- **Phase B:** the refuter re-classifies the prior STILL-REAL set; verify by spot-checking 2–3 of its "false-positive" flips against the actual files (the same way the 5/5 were caught). Confirmed-STILL-REAL list contains only #120 code items.
- **Phase B resolve:** after mutation, re-run the Step 1 inventory sweep — each cleaned PR returns 0 unresolved bot threads except its intentionally-left opens; `#120` unchanged.
- **Review:** `/review-loop <PR> bugbot` clears (bugbot-only; Copilot noop).

## 10. Phase B follow-up — held PRs (#118, #120) — ✅ RESOLVED

**Outcome (user chose fix-and-resolve for both):**
- **#120** (B-120-c) — fixed the 3 confirmed PowerShell bugs (commit `354c485`: TLS 1.2 before kernel-MSI download; `$vmMonitor` consulted in the virtualization warning — *not* a hard gate, to avoid the Hyper-V-owns-VT-x false negative; `-Distro` trimmed). Resolved all 39 threads. IDEA non-goal amended.
- **#118** (C-118-b) — full refute-discipline re-audit of all 35 threads (1 background agent): 21 FIXED + 7 FIXED-by-deletion + 2 WON'T-FIX + **3 confirmed STILL-REAL**. Fixed all 3 (commit `f7d682d`: README Skills 15→17 + Agents 9→8, sprint-auto S15 diagram). Resolved all 35 threads.
- **Cohort total: 250 threads resolved across 17 PRs; verified 0 unresolved Copilot threads remain.** PowerShell + doc fixes land on `main` when this IDEA's PR merges.

Original options (for the record):

After the 176-thread resolve, two PRs remained held. Each has a clean noise-vs-signal split now that Step 2.5 has run. Options (decide per-PR):

### #120 — `scripts/install-wsl.ps1` (39 unresolved; 3 confirmed code bugs)

Confirmed real (refuter, with line evidence): whitespace-only `-Distro` reaches `wsl --install -d "   "` (line ~507); `$vmMonitor`/VT-x computed + displayed but never gates install (line ~183, unlike `$slat`); `Invoke-WebRequest` for the kernel MSI lacks TLS 1.2 enforcement (line ~331). The `'Missing'` switch-case claim was **refuted** (a try/catch already handles it gracefully).

- **B-120-a — Leave fully untouched.** You own the PowerShell fixes + the threads. Matches the IDEA's current non-goal. _(default)_
- **B-120-b — Resolve the ~36 safe threads, leave the 3 confirmed code threads open** as a clean punch list (recipe-ideal: noise cleared, signal stands out). No code touched.
- **B-120-c — Fix the 3 bugs in this IDEA** (TLS 1.2 line ~331; `$vmMonitor` gate beside `$slat`; `.Trim()` + `IsNullOrWhiteSpace` guard on `-Distro`), then resolve all #120 threads. **Expands scope into PowerShell code** (currently an explicit non-goal — would need a non-goal amendment).

### #118 — sprint-auto/onboarding docs (35 unresolved; 1 confirmed doc bug + 11 pass-1 UNCERTAIN)

Confirmed real: `skills/sprint-auto/references/post-pr-sequence.md` S15 diagram (line ~159) still lists "forward-sync results, re-review results" that v3.2 deleted (S11.11/S11.12). The 11 UNCERTAIN (>10% → recipe's human-walk threshold) were mostly "cited file deleted/moved, couldn't verify" — likely FIXED-by-deletion but unconfirmed.

- **C-118-a — Leave fully untouched.** _(default)_
- **C-118-b — Full clear: verify + fix.** Run a refute/verify pass over the 11 UNCERTAIN, fix the 1 confirmed S15 doc bug (in-scope mind-vault doc, small), then resolve #118's now-safe threads (likely all). Most thorough.
- **C-118-c — Partial: resolve the clear FIXED/WON'T-FIX subset now, leave the 11 UNCERTAIN + the S15 thread open** until walked/fixed.
