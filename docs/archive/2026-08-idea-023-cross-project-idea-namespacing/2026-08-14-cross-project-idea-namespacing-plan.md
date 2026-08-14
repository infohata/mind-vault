---
stage: plan
slug: cross-project-idea-namespacing
created: 2026-08-14
source: ./IDEA-023-cross-project-idea-namespacing.md
status: shipped                                # draft | ready | shipped
project: mind-vault
---

# Plan — Cross-project idea namespacing (`IDEA-NNN:project`)

## Context

Every sprint-workflow project keeps an independent `IDEA-NNN` stream. Bare numbers collide the moment two projects share a surface: a live session (2026-08-14) answered a "where were we" question from inside mind-vault by citing another project's IDEAs with bare numbers — mind-vault and that project each have an unrelated IDEA-016/017 — and the user could not tell which repo the session was on. Memory notes already improvise disambiguators by hand (`project-x IDEA-112`, `(project-x) IDEA-178`). This plan turns the improvisation into one convention and wires it into the write-sites that produce cross-project references.

Architect review chain (all passes 2026-08-14): pass 1 REQUIRES ABSTRACTION (3 must-fix, 4 should-fix folded; note 10 adopted as a decision) → pass 2 on the amended draft REQUIRES ABSTRACTION, narrow (residuals R1–R3: truncated detector spelling with 362 measured false positives, example/rule contradiction, carve-out drift — all folded below) → pass 3 ARCHITECTURALLY SOUND (2026-08-14) — reviewer re-ran D1/D2/D3 independently; D1 (full-pattern grep with `:project-` carve-out) = 0 hits repo-wide.

## Problem Frame

- Bare `IDEA-NNN` is ambiguous on any surface that can mention more than one project: session prose, auto-memory, estate docs, harvest ledgers, compound provenance.
- The existing defenses are one-sided: `/idea` § 4 defends *numbering* ("never carry a number from another project's stream") but says nothing about *referencing*; the `/compound` scrub gate treats foreign refs as scrub candidates but relies on surrounding context to recognise them.
- Ad-hoc prose disambiguators (`(project) IDEA-N`, `project IDEA-N`) are inconsistent and not grep-able as a class.

## Requirements Trace

- **R1** — A single attribution grammar: bare `IDEA-NNN` always means the stream of the repo the text lives in (or the session's working repo, for conversation prose); foreign refs are written `IDEA-NNN:project`. (IDEA body, Proposal.)
- **R2** — The convention is wired at the write-sites that produce cross-project refs, catchment-style per the PR #227 wired-pointer convention, with a `Wired:` list in the owning reference. (IDEA body, Proposal.)
- **R3** — Mind-vault file bodies remain scrub-clean: the convention must NOT legitimize real foreign project names inside skill/rule/agent/reference bodies — **and this repo's `docs/` tree is part of that surface** (the provenance-scrub runbook scans `docs/archive/**`; this plan and its IDEA file are themselves written placeholder-only). Confirmed by the user at plan time: "the rule that no project-related items should stick in mind-vault still applies." (User instruction, 2026-08-14.)
- **R4** — Forward-only: no renumbering, no retro-editing of merged archives, no global registry. (IDEA body, Non-goals.)

## Scope Boundaries

**In scope**

- The convention text (grammar, bare-ref semantics, project-token definition) as a load-on-demand reference owned by the `idea` skill.
- One-line wired pointers at the producing write-sites (see Execution Sequence).
- Scrub-gate integration: the namespaced class as a *mechanical* scrub-detection aid in mind-vault diffs (see Decision 6 for the enforcement framing).
- Auto-memory guidance (compound SKILL's auto-memory destination row + its THIS-MACHINE-ONLY routing test at SKILL.md:104-115 — no separate memory-routing reference exists; verified 2026-08-14).

**Out of scope / non-goals**

- Frontmatter schema change: `related` / `depends_on` / `supersedes` stay same-project bare ids. *Invalidating condition:* the first real machine-readable cross-repo dependency (e.g. sprint-auto sequencing across repos) — that becomes its own IDEA, not a silent extension.
- Git branch names — **a real, known-ambiguous surface this grammar cannot reach.** Mind-vault compound branches already carry the *originating project's* IDEA number in their slug (`compound/2026-05-DD-idea-NNN-...`), and an agent has already misread one — that incident is the origin of `/idea` § 4's numbering rule. The colon form is impossible there: `:` is illegal in git refnames (`git check-ref-format --branch "idea-050:x"` → fatal; measured 2026-08-14). The defense for branch names remains § 4's scan-from-disk rule ("the branch name is NOT the target project's next number"); the new reference cross-links it rather than inventing a second separator. *Invalidating condition:* a new workflow that must encode a foreign idea ref in a refname unambiguously — that workflow designs its own encoding then.
- Retro-editing existing memory notes / archives. Old `(project) IDEA-N` prose stays; the convention applies forward.
- Per-project enforcement tooling. Outside mind-vault the suffix is a correctness convention, not a leak hazard; it travels to consumer projects via the plugin-distributed skill prose itself. No CI, no hooks there. (Architect note 10.)

## Context & Research

- `skills/idea/SKILL.md` § 4 (line ~135) — "Each project's numbering is independent" — the defensive half; this plan adds the attribution half. Measured: additive, no contradiction. Natural co-owner.
- `skills/compound/SKILL.md` — the scrub gate is **single-sourced** at step 5 (lines 136-165); `references/mind-vault-promotion.md` carries **no scrub mirror** (measured 2026-08-14 — an earlier draft of this plan assumed one and was corrected in architect review). The second compound touch is § 5 Cross-link (SKILL.md:174), whose "foreign-project IDEA numbers go in the commit message only" bullet is a natural wired site.
- `rules/RULE_cross-idea-amendments.md` — `Amends IDEA-MMM` trailers are same-repo by construction (amending commit and amended file live in one repo; measured).
- Memory survey (2026-08-14): live cross-project refs in auto-memory use ad-hoc `<project> IDEA-N` prose — inconsistent, not grep-able.
- PR #227 (deferral expiry triggers) established the catchment convention this plan reuses: one-liner per write-site + bidirectional `Wired:` list. PR #232 re-validated it (a missed write-site was the one review finding).
- `docs/archive/2026-06-idea-018-provenance-scrub/PROVENANCE_SCRUB_RUNBOOK.md` — scans `docs/archive/**`; the runbook whitelists only its own dir (it must define the tokens it scrubs). This plan claims no such exemption: its files are placeholder-only.

## Key Technical Decisions

1. **Grammar: `IDEA-NNN:project`, colon separator, number first.** Matches the requested shape; the colon reads as a qualifier and cannot appear in the bare form, so the two forms are visually and grep-ably distinct. **One canonical pattern, defined once in the reference and quoted verbatim at wired sites:** `IDEA-[0-9]{3,}:[a-z0-9._-]+` (`{3,}` so a future 4-digit stream doesn't silently escape the class). Earlier draft carried three divergent spellings; consolidated per architect finding 5.
2. **Project token = the repo's own name as its docs refer to it** (its checkout dir name in the standard layout), lowercased; charset = the detector regex's suffix class `[a-z0-9._-]`, since repo names are not kebab-strict (post-review alignment — prose originally said "lowercase kebab", contradicting the regex). **Never an alias**: not a plugin/marketplace name, not an env-var name — for mind-vault that means `IDEA-NNN:mind-vault`, never `IDEA-NNN:mv` (the `mv` plugin alias is a competing token in every session's face; architect finding 6). Teaching examples throughout this plan and the reference spell the number as non-digit `NNN` deliberately — such spellings fall outside the canonical regex by construction, keeping the verification grep at zero hits (architect R2). GitHub `org/name` is longer, remote-dependent, and would leak org names into surfaces the scrub gate polices. Tokens must be estate-unique; if two repos ever share a name across orgs, a qualified form is the tiebreak on non-mind-vault surfaces only (architect note 11).
3. **Bare-ref semantics are positional**: bare `IDEA-NNN` inside a repo's files = that repo's stream; in session/conversation prose = the session's working repo. If the working repo is ambiguous (multi-repo session), every ref must be suffixed. This is the rule that would have prevented the triggering incident.
4. **Owning home: `skills/idea/references/CROSS_PROJECT_IDEA_REFS.md`** (new, load-on-demand), stub + pointer in the idea SKILL body. References-first per the compound placement rule; NOT a new top-level rule — the guardrail fires when writing cross-project references, a doing-the-workflow moment, not an always-on session concern.
5. **Mind-vault bodies: the scrub rule wins, unchanged (R3).** A namespaced ref with a *real* foreign project name is still a scrub violation inside mind-vault bodies — including `docs/` — and the convention makes it *easier to catch*, not legal. Permitted spellings in mind-vault: bare refs to mind-vault's own stream, and placeholder-namespaced refs with non-digit numbers (`IDEA-NNN:project-x`) in teaching examples. The stronger rule the suffix enables, stated in both the reference and the gate: **in mind-vault, any namespaced ref whose suffix is not a placeholder is a violation by construction.** Commit messages stay exempt (git history is acknowledged-noisy, per the existing gate).
6. **Enforcement framing (reconciled with the gate's stance, architect finding 7):** the scrub gate's *classification* (model judgment) remains the enforcement mechanism, exactly as SKILL.md:163 states. The namespaced class is the one scrub class where a regex is *sufficient* — the ref self-identifies as foreign — so the optional grep aid gains this pattern **with the placeholder carve-out** so it doesn't fire on the gate's own teaching examples (alarm-fatigue erosion, architect finding 4): `grep -rEn 'IDEA-[0-9]{3,}:[a-z0-9._-]+' | grep -v ':project-'`. The full canonical pattern is load-bearing — the truncated `IDEA-[0-9]{3,}:` spelling matches every ordinary idea-title colon (362 measured false positives repo-wide; architect R1) — and the carve-out is the `:project-` prefix class, quoted byte-identically here and in Verification (architect R3). An aid promoted for this class only; judgment still owns everything else.

## Open Questions

All resolved at plan time (user delegated: "go planning and answering open questions"):

- ~~Q1: project token — dir name or org/repo?~~ → **Repo's own name, aliases excluded** (Decision 2).
- ~~Q2: where does the convention live?~~ → **`skills/idea/references/CROSS_PROJECT_IDEA_REFS.md`** + wired one-liners (Decision 4).
- ~~Q3: are namespaced foreign refs allowed inside mind-vault bodies?~~ → **No** — user confirmed the scrub rule still applies; placeholder form only, violation-by-construction otherwise (Decision 5).
- ~~Q4: what about branch names, where `:` is illegal?~~ → **Out-of-scope with a real justification**: the surface exists and is known-ambiguous; its defense is § 4's scan-from-disk rule, cross-linked from the reference (Scope Boundaries).

## Execution Sequence

_Executed 2026-08-14: steps 1–2 ✅ `9f2ba8a`; steps 3–6 ✅ `b6e68a1` (step 5's routing-test half re-scoped to the "For auto-memory" write-up — the routing test chooses destinations, it doesn't spell refs; Wired list corrected to match); step 7 ✅ swept, zero hits, nothing to update; step 8 → `/wrap` (v5.6.0 — minor, not the default patch: user-selected per the adopter-magnitude rule, the convention reaches every consuming project's write surfaces). Verification: detector grep 0 hits; all wired sites back-grep; frontmatter guard COULD-NOT-RUN (no PyYAML on host) — eye-verified, no ids touched; § 4 consistency re-read clean._

_Review-cycle additions (2026-08-14, cycle 1): step 3's second half — the drop-the-tag policy bullet — was initially unshipped with no re-scope recorded (curator Minor, the PR #232 missed-write-site class); now wired, "qualified" defined. Two sites added beyond the plan on review + user direction: wrap Step 4 devlog Related-section refs (user-requested write-site) — both in the Wired list. IDEA Proposal reconciled to the as-shipped set: `/plan` carries no foreign-ref prose site, dropped with reason (claude engine finding)._

1. **Author `skills/idea/references/CROSS_PROJECT_IDEA_REFS.md`** — the grammar (canonical regex, Decision 1), bare-ref positional semantics (Decision 3), project-token rule with the alias exclusion (Decision 2), the branch-name paragraph (surface exists, colon impossible, § 4 cross-link), the scrub interaction (placeholder-only inside mind-vault, violation-by-construction rule, all examples spelled with non-digit `NNN`), a half-line on YAML-colon safety (a suffixed ref inside an unquoted frontmatter title is one more instance of § 4's quote-your-titles rule; architect note 9), and the closing `Wired:` list. Concrete-first: open with the 2026-08-14 IDEA-016/017 collision incident, placeholder-named. Target ≤60 lines.
2. **Stub in `skills/idea/SKILL.md`** — 2-line stub + pointer in § 4, extending the existing "never carry a number" rule with "and never cite a foreign number bare — `IDEA-NNN:project`, see reference". Add the reference to the References list.
3. **Wire `skills/compound/SKILL.md` step 5** — in the scrub table's foreign-ref row and the drop-the-tag policy bullet: namespaced spelling as the preferred/detectable form, placeholder rule unchanged; add the carved-out grep (Decision 6) to the optional aid line.
4. **Wire `skills/compound/SKILL.md` § 5 Cross-link (line ~174)** — one-liner on its "foreign-project IDEA numbers go in the commit message only" bullet: when prose (not commit trailers) must carry a foreign ref on a non-mind-vault surface, the suffixed form is the spelling. (Replaces the earlier draft's phantom `mind-vault-promotion.md` mirror touch — no scrub mirror exists there; architect finding 1.)
5. **Wire auto-memory guidance** — compound SKILL.md:68 destination row + the § THIS-MACHINE-ONLY routing test: cross-project idea refs in memory notes use the suffix, replacing ad-hoc `(project) IDEA-N` prose.
6. **Wire `rules/RULE_cross-idea-amendments.md`** — half-sentence: `Amends IDEA-MMM` trailers are same-repo by construction; a genuinely cross-repo amendment narrative uses the suffixed form in prose.
7. **Consumer sweep** — grep `docs/guides/SPRINT_WORKFLOW.md`, `README.md`, `AGENTS.md` for idea-reference guidance that should mention the convention; update only where a reader would otherwise write a bare foreign ref.
8. **CHANGELOG + version bump** — per-PR patch bump per mind-vault policy; `/wrap` Step 4b owns it at wrap time (this is an IDEA PR).

## Verification

- **Full-repo scrub grep** (not just `skills/`): `grep -rEn 'IDEA-[0-9]{3,}:[a-z0-9._-]+' --include='*.md' . | grep -v ':project-'` over the final tree returns **zero hits** — teaching examples use non-digit `NNN` numbers and so fall outside the pattern by construction; no escape clause (R3, violation-by-construction; architect R1+R2). Scope includes `docs/archive/**` per the provenance-scrub runbook; this plan's own dir must pass (architect finding 2).
- Separately, confirm the plan/IDEA files carry no bare foreign names either: the runbook's token classes, applied to this archive dir.
- The `Wired:` list in the new reference names exactly the write-sites edited in steps 2–6; each named site greps back to a pointer (the PR #232 review finding, applied prophylactically).
- `python3 skills/idea/assets/check-idea-frontmatter.py .` still passes (no frontmatter schema drift, R4). If the guard cannot run (PyYAML absent), record COULD-NOT-RUN and verify by eye — a skipped check is not a pass.
- Re-read `skills/idea/SKILL.md` § 4 after step 2: the numbering rule and the attribution rule must not contradict (numbering stays independent; attribution is additive; branch-name defense unchanged).
