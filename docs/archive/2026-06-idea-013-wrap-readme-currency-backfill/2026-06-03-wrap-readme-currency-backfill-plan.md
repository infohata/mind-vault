---
stage: plan
slug: wrap-readme-currency-backfill
created: 2026-06-03
source: ./IDEA-013-wrap-readme-currency-backfill.md
status: shipped
project: mind-vault
---

> **Progress (2026-06-03):** Execution items 1–4 → `90209c7`
> (feat: Step 6b + reference + WRAP_BEFORE_REVIEW/recap sync). Items 5–7 →
> `504ea0f` (dogfood: README v4.0.4→v4.6 banner + marker + hint block).
> Headline-ordering precursor → `86f798e`. Verification V1–V6 ✅ (marker read
> `2026-06-03`; same-day count 0 ⇒ idempotency guard confirmed; dogfood diff
> mechanical-only; Skills 17 = filesystem). PR opened as draft.

# Plan: Amend /wrap with a staleness-gated whole-README currency audit

## 1. Context

`/wrap`'s Step 6 (downstream-docs scan) only greps the project README for the
**current IDEA's** changed identifiers. No single IDEA's wrap is responsible for
**whole-README currency**, so the README accumulates silent drift across many
IDEAs — version-highlight framing, skill/command/agent counts, feature tables,
stale ⚠️ flags. Step 4 already solves this exact shape for the devlog via
backfill-gap detection; the README has no equivalent. This plan adds one.

The headline workflow-ordering drift that IDEA-013's audit first surfaced (the
`work → review → wrap` glyphs contradicting wrap-before-review) is **already
fixed** on this branch (commit `86f798e`) — see the IDEA body's "Folded-in
finding". This plan covers the remaining, generic piece: the reusable
`/wrap`-step automation.

## 2. Problem Frame

A partial README touch (Step 6 patching one IDEA's identifiers) is **not** a
whole-README refresh, yet it looks like recent activity. mind-vault's README
drifted *despite* IDEA-012 touching it — the other sections rotted unnoticed.
Any staleness signal keyed on "was README.md touched recently" would be reset by
that partial edit and **never fire on the very case that motivates this IDEA**.

## 3. Requirements Trace

- **R1** (IDEA Proposal) — audit the README as a *whole* against current
  reality, not just the IDEA's touched identifiers.
- **R2** (IDEA Open-Q "Cadence", resolved → staleness threshold) — the audit
  fires on a **staleness threshold**: N merged PRs since the last *whole-README
  audit* (not since the last partial touch — see R3).
- **R3** (derived this plan) — staleness is measured against the last **audit**,
  tracked by a marker the audit itself writes; Step-6 identifier patches must not
  reset it.
- **R4** (IDEA Open-Q "Where it lives", resolved → references doc) — the audit
  checklist + mechanics live in `skills/wrap/references/README_CURRENCY.md`;
  SKILL.md gains only a thin trigger (SKILL.md is 409L vs the ~500 budget).
- **R5** (IDEA Open-Q "project-agnostic counts", resolved → heuristic + optional
  hint) — probes are generic (version string, filesystem-glob counts, ⚠️ flags)
  and work with zero config; an optional per-project hint can override N and
  declare count sources.
- **R6** (IDEA Non-goals) — mechanical drift (counts, version string, missing
  table row, resolved ⚠️) is patched in-wrap; large prose / architectural-
  narrative rewrites are **flagged as follow-up**, never auto-rewritten. Mirrors
  Step 6's patch-now-vs-follow-up dispositions.
- **R7** (IDEA Non-goals + Related IDEA-008) — the audit respects `--scope`:
  **skipped** under `--scope=idea-only`; eligible under `docs` / `full`.
- **R8** (architect 2.2) — the `WRAP_BEFORE_REVIEW.md` pass-1 step enumeration
  ("Steps 1–4 and 6, plus … Step 7") must be updated to include 6b. Shipping 6b
  without this is the exact headline-vs-body drift IDEA-013 exists to kill.
- **R9** (architect 4.2) — the audit must **degrade, not crash**, where
  `gh pr list` is unavailable (fork, mirror, no token, air-gapped).

## 4. Scope Boundaries

**In scope**

- New `skills/wrap/references/README_CURRENCY.md` (full audit: trigger, marker,
  probe checklist, dispositions).
- Thin trigger in `skills/wrap/SKILL.md` — a new **Step 6b** (~10–15 lines)
  pointing at the reference, gated on scope + staleness.
- One-line update to the SKILL frontmatter `description` and the Step-6
  section's intro noting the whole-README sub-step.
- The **first dogfood**: run the audit against mind-vault's own README and land
  the mechanical fixes (version framing `v4 highlights` → current, skill/agent/
  command/engine counts, missing feature-table rows, the sprint-auto ⚠️ if its
  cause resolved) in this PR. Seeds the marker.

**Out of scope / non-goals**

- Auto-rewriting architectural prose / high-level narrative (R6).
- A separate `/readme-audit` command — it's a `/wrap` sub-step (IDEA non-goal).
- Generated/templated README — stays hand-authored; the check keeps it honest.
- Per-project count config beyond the optional single hint block (R5).

## 5. Context & Research

- **Pattern to mirror** — `skills/wrap/SKILL.md` Step 4 §2 backfill-gap
  detection (`gh pr list --state merged --base <base> --json number,mergedAt`,
  cross-reference, ≤3 patch-now / larger → hand-back). The README audit reuses
  the same `gh pr list` merged-PR enumeration for the staleness count.
- **Host step** — `skills/wrap/SKILL.md` Step 6 (downstream-docs scan, line 339)
  and its three dispositions (patch-now-mechanical / patch-now-doc-catchup /
  flag-follow-up, lines 356–362). README audit findings reuse these verbatim.
- **Version source** — Step 4b's detection block (lines 273–283) already
  computes the top CHANGELOG `## vMAJOR.MINOR[.PATCH]`; the version-framing probe
  reads the same source so "v4 highlights" can be checked against it.
- **Scope gating** — Step 4b's `idea-only` skip (line 271) is the exact pattern
  for R7.
- **Convention** — `references/`-first promotion (auto-memory
  `feedback_compound_prefer_references`); SKILL stays lean, deep content loads on
  demand. Existing siblings: `WRAP_BEFORE_REVIEW.md`, `IDEA_COMPLETENESS_AUDIT.md`.
- **Markdown** — repo is doc-heavy → `markdownlint-cli2 --fix` convention
  (auto-memory `feedback_markdown_formatter_per_repo_type`).

## 6. Key Technical Decisions

- **D1 — Staleness keyed on a whole-README audit marker, not file mtime.**
  README carries an HTML-comment marker:
  `<!-- wrap:readme-currency-audited YYYY-MM-DD -->`. The trigger counts merged
  PRs on the base branch merged after that date. Partial Step-6 edits don't touch
  the marker, so they don't reset the counter. No marker present → treat as stale
  (fire on first eligible wrap). **Future-dated / clock-skewed marker (date >
  today) → also treat as stale** (architect 4.3) — symmetric with the no-marker
  case, prevents a skewed marker silently disabling the audit forever. Solves R3
  and the IDEA's own evidence case. The comment is invisible in rendered markdown.
- **D1a — Marker write is atomic with the patches it gates** (architect 3.1).
  The marker is written in the **same commit/branch as the README edits the audit
  produced** — pre-merge: the feature branch; post-merge fallback: the
  `docs/idea-NNN-wrap` cleanup branch. Never write the marker on a different ref
  than the audit. Guarantees "marker present ⟺ audit ran on this ref"; an
  abandoned post-merge cleanup PR simply never lands the marker → next wrap
  re-fires (safe).
- **D2 — Default N = 5, overridable.** Optional per-project hint block (see D4)
  may set `N`. Absent → 5. Count source is a **server-side date-filtered query**
  (architect 4.1), not the enumerate-then-filter recipe Step 4 uses for backfill:
  `gh pr list --state merged --base <base> --search "merged:>YYYY-MM-DD" --json
  number --jq 'length'`, keyed on the marker date. No client-side `--limit` cap to
  couple a display limit to gate correctness; squash-merge-friendly (`git log`
  alone misses squash merges).
- **D2a — `gh`-unavailable fallback: calendar staleness** (architect 4.2, R9). If
  `gh pr list` errors (no auth / non-GitHub remote), fall back to a zero-network
  signal: audit if marker absent OR marker date older than a calendar threshold
  (default 30 days) computed from `date`. The audit degrades to time-based; it
  never crashes the wrap.
- **D3 — Marker is always refreshed when the audit runs**, regardless of whether
  it found anything to patch — a clean audit still resets the counter (the
  README *was* reviewed whole). This makes the cadence self-regulating. **Same-day
  idempotency guard** (architect 3.3): a marker dated today ⇒ count is 0 ⇒
  short-circuit skip — an explicit guard in the 6b pseudocode (mirrors Step 4
  L241's `grep -q … && skip`), so the `docs`→`full` two-pass re-run never
  double-audits.
- **D4 — Optional per-project hint, zero-config default.** The reference
  documents an optional fenced block the audit reads if present, e.g.:
  ```
  <!-- wrap:readme-currency
  N: 5
  counts:
    skills: ls skills/*/SKILL.md | wc -l
    agents: ls agents/AGENT_*.md | wc -l
  -->
  ```
  Absent → heuristic probes only (version string vs CHANGELOG, ⚠️ flags, and
  best-effort count detection). Keeps R5's project-agnosticism without mandating
  config.
- **D4a — Heuristic count-probe fails LOUD, never silent** (architect 1.1, the
  RULE_self-sweep #3 skip-on-no-match trap). The `"Skills (NN)"`-style heading
  regex is a mind-vault artifact; a Django adopter's README counts apps /
  endpoints / models in shapes the regex won't match. When **no hint block AND no
  count-shaped heading matches**, the probe must NOT report "counts OK" — it emits
  *"count sources not auto-detectable — declare them in the optional hint block to
  enable count-drift detection"* in the wrap hand-back. Genericity = failing loud
  on the unknown shape, not pattern-matching mind-vault's shape and calling a
  non-match clean.
- **D4b — Version-framing probe is no-op-when-absent** (architect 1.2). Most
  internal projects don't version their README; the probe reads Step 4b's
  `VER_SOURCE` but if the README carries no version-framing string at all, it
  skips cleanly rather than inventing a finding. Same no-op-when-absent contract
  applies to the ⚠️-flag probe.
- **D5 — Step 6b, not inside Step 6's per-identifier loop.** Distinct sub-step so
  the staleness gate is evaluated once per wrap, not per identifier. Placed
  immediately after Step 6 (whole-README pass follows the per-identifier pass).
- **D6 — Dispositions inherited from Step 6** (R6). The reference doesn't invent
  a new disposition vocabulary; it maps each probe's findings onto patch-now-
  mechanical vs flag-follow-up, with explicit examples per probe.

## 7. Open Questions

- **Q1 — Marker placement.** Top-of-file (after H1) vs bottom. *Default:* bottom,
  so it never intrudes on the reader's first screen. (Low stakes; resolve in
  /work.)
- **Q2 — Does the dogfood audit's marker date count this PR's own merge?** The
  marker is written *in* this PR, dated today; the first post-merge staleness
  count starts from 0. *Default:* yes — writing the marker = "audited now."
  (Resolved: consistent with D3.)
- **Q3 — Should `--scope=full` (merge path) re-run the staleness check?**
  *Resolved (architect 3.3 → D3):* the check runs in every eligible wrap, but the
  same-day idempotency guard (marker dated today ⇒ count 0 ⇒ skip) makes the
  `full` re-run a no-op after the `docs` pass already audited. No special-casing
  the pass — the guard handles it.

## 8. Execution Sequence

1. **Write `skills/wrap/references/README_CURRENCY.md`** — sections: *When this
   fires* (scope gate + staleness marker + N + same-day/future-date/`gh`-down
   handling per D1/D2a/D3), *The marker* (format, read/count/write mechanics,
   server-side `gh pr list --search "merged:>DATE"` recipe per D2, atomic-branch
   rule per D1a), *Audit probes* (the five from the IDEA, each with a concrete
   grep/glob, its patch-now-vs-follow-up disposition, and explicit
   no-op-when-absent / fail-loud contract per D4a/D4b), *Optional per-project
   hint* (D4), *Sprint-auto asymmetry* (architect 3.2 — per-IDEA `idea-only`
   wraps skip 6b and never touch the marker; the S11.7 batch wrap is the single
   whole-README audit point for the cohort; per-IDEA partial touches not
   resetting the marker is intentional, the D1/R3 insight at batch scale),
   *Dogfood note*. Target ≤ ~130 lines.
2. **Add Step 6b to `skills/wrap/SKILL.md`** — thin trigger after Step 6: scope
   check (skip if `idea-only`), read marker, count merged PRs (server-side date
   query; `gh`-down → calendar fallback), same-day idempotency short-circuit, fire
   iff ≥ N → "see `references/README_CURRENCY.md`"; refresh marker on the same
   branch. ~12–18 lines.
3. **Update SKILL.md frontmatter `description`** — append the whole-README
   currency audit to the doc-scan clause (one phrase). Update Step 6 intro line
   to mention the 6b whole-README pass. **Update the Pattern header count**
   ("Nine steps…" → reflect 6b) and any step-list recap.
4. **Update `skills/wrap/references/WRAP_BEFORE_REVIEW.md`** (R8 / architect 2.2)
   — its pass-1 step enumeration (L16: "Steps 1–4 and 6, plus … Step 7") becomes
   "Steps 1–4, 6, and 6b, plus … Step 7". Doc-consistency obligation; ships in the
   same commit as the SKILL.md trigger so the two surfaces never disagree.
5. **Dogfood — audit mind-vault's own README.md** per the new reference: fix
   version framing, counts (skills/agents/commands/engines vs filesystem),
   missing feature-table rows, and re-evaluate the sprint-auto ⚠️ flag. Add the
   `<!-- wrap:readme-currency-audited 2026-06-03 -->` marker. Mechanical fixes
   only; flag any prose rewrite as follow-up in the PR body.
6. **Self-sweep (RULE_self-sweep trigger 5)** — frontmatter↔body symmetry on the
   IDEA, count claims in the edited README match the listed set, the SKILL.md
   step-count recap ↔ the WRAP_BEFORE_REVIEW enumeration ↔ the new 6b are
   symmetric, markdownlint.
7. **Commit** on `idea/013-wrap-readme-currency-backfill`; the headline-ordering
   commit (`86f798e`) already rides this branch.

## 9. Verification

- **V1 — Reference renders + lints.** `markdownlint-cli2 README_CURRENCY.md`
  clean; the `gh pr list` recipe is copy-pasteable.
- **V2 — Trigger logic dry-run.** Walk the Step-6b pseudocode by hand against
  two states: (a) no marker → fires; (b) marker dated today, 0 merged PRs since →
  skips. Confirm `idea-only` scope skips.
- **V3 — Dogfood diff is mechanical-only.** Every README edit in step 4 is a
  count / version-string / table-row / flag change — no architectural prose
  rewritten (grep the diff for prose-paragraph changes; there should be none
  beyond the highlight version string).
- **V4 — Counts are correct post-fix.** Each count claim in the README matches
  its filesystem source: `ls skills/*/SKILL.md | wc -l`, `ls agents/AGENT_*.md |
  wc -l`, commands, review engines.
- **V5 — Marker present + dated 2026-06-03**, and the SKILL frontmatter
  description mentions the whole-README audit.
- **V6 — Degradation + genericity contracts present in the reference** (architect
  must-fixes): `gh`-down calendar fallback documented; heuristic count-probe's
  fail-loud no-op-disclosure line documented; `WRAP_BEFORE_REVIEW.md` pass-1
  enumeration includes 6b; sprint-auto asymmetry paragraph present.

## Architect review — AGENT_architect (2026-06-03)

**Verdict: 🟡 REQUIRES ABSTRACTION → all findings folded into this plan; now `ready`.**

Core design ratified as sound: marker-as-staleness-anchor (D1), references-first
hosting, Step-6 disposition inheritance, forward-only data flow from Step 4b's
`VER_SOURCE`, once-per-wrap gate cardinality (D5). No redesign required.

Six must-fix items, all incorporated above:

1. **3.1 (Critical)** marker write atomic with its patches' branch → **D1a**.
2. **1.1 (Major)** heuristic count-probe fails loud, no silent pass → **D4a**.
3. **2.2 (Major)** `WRAP_BEFORE_REVIEW.md` pass-1 enumeration must include 6b →
   **R8 + Execution step 4**.
4. **4.2 (Major)** `gh`-unavailable calendar-staleness fallback → **D2a + R9**.
5. **4.1 (Major)** server-side `--search "merged:>DATE"` count, drop `--limit`
   cap → **D2**.
6. **3.2 (Major)** sprint-auto asymmetry documented as intentional → **Execution
   step 1 reference contents**.

Should-fix (also folded): same-day idempotency guard (D3 / Q3), future-dated
marker clamp (D1), version-framing no-op-when-absent (D4b).
