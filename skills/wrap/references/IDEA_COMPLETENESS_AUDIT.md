# IDEA-completeness audit — before flipping `status: complete`

Pre-condition for Step 2's frontmatter flip from `in-progress` to `complete`. Stops the most common /wrap regression: closing an IDEA when one or more of its plan's acceptance criteria (R-numbers) is unmet, leaving silent debt that decays into "we shipped it" lore until the next reader of the archive trips over the gap.

## When this fires

Step 2 of `/wrap NNN` — at the moment the IDEA file's frontmatter is about to change `status: in-progress` → `complete`. The audit is mandatory; no exceptions.

## The audit

Open the IDEA file and the plan doc side-by-side. Walk the requirement list — every `R1`, `R2`, … — and ask one question per requirement:

> **"Does the merged code at the PR's HEAD demonstrably satisfy this requirement, or is there work referenced in the plan that has not shipped?"**

Three possible answers per requirement:

| Answer | Action |
|---|---|
| ✅ **Satisfied** by merged code | Continue to next requirement |
| ⚠️ **Partially satisfied** — half the surface shipped, the other half is in a separate planned PR / phase / follow-up | **Do not flip frontmatter to `complete`.** Either (a) ship the remaining work on the same PR before continuing /wrap, or (b) keep `status: in-progress` and document the missing piece as a follow-up. The wrap output (devlog entry, ideas-index entry, hand-back report) must explicitly call out the deferred piece with the ⚠️ marker. |
| 🔍 **Unclear** — the requirement was implicit and the plan didn't enumerate concrete acceptance signals | Investigate first. If you can't confidently answer ✅ within 5 minutes, treat as ⚠️. |

The audit is per-requirement, not per-PR. A multi-phase IDEA may legitimately satisfy `R1..R6` on PR #N but leave `R7` for PR #N+1 — the right wrap shape is "PR #N satisfies R1..R6, R7 still pending, IDEA stays in-progress until PR #N+1 ships".

## The ⚠️ visual marker is load-bearing

Every wrap output that summarises an IDEA's status must surface unmet criteria with ⚠️. The marker survives compaction; soft phrasing does not. Examples:

```
✅ IDEA-NNN: Phase 1 shipped (canonical helper + walker + 15 emit-site dual-emission).
⚠️ Phase 2 pending — drop legacy per-name keys + retire 4 modal.js listeners.
   R7 acceptance criterion ("legacy listeners retired") unmet until Phase 2 ships.
```

Not this:

```
✅ IDEA-NNN complete — helper + walker + 15 emit-site migration shipped in PR #N.
```

The soft form elides the gap. The next reader — possibly the same agent post-compaction — reads "complete" and stops digging. The deferred work disappears into a memory note, then drifts out of the next session's load, and surfaces months later as "wait, why is legacy code still emitting?".

## Phase-shipped IDEAs in the index + devlog

When an IDEA legitimately ships in phases over multiple PRs, the wrap commit on each PR uses a different shape:

- **Phase 1 PR's wrap** — frontmatter stays `in-progress`, banner adds a "Phase 1 shipped / Phase 2 pending" section with ⚠️ on the pending half. Devlog entry titled `IDEA-NNN Phase 1: <subject> (PR #N)`. Ideas-index keeps the IDEA in "In Progress" with a Phase 2 stub explaining what's outstanding.
- **Phase N+1 (final) PR's wrap** — frontmatter flips to `complete`, IDEA banner updates to a combined Phase 1 + Phase 2 + … summary, devlog gets a new entry titled `IDEA-NNN Phase 2: <subject> (PR #N+1)`, the prior Phase 1 entry stays untouched (chronological log), ideas-index entry moves from In Progress to References — Implemented with the combined close-out.

The "frozen mid-flight" Phase 1 wrap shape isn't an exception to this audit — it's a successful application: the audit caught R7 as unmet, the wrap respected that, the IDEA stayed in-progress on purpose. The failure mode the audit prevents is the *premature* flip that ignores R7.

## Frontmatter convention for phase tracking

When phase-shipped, keep both timestamps in the IDEA frontmatter so future readers can distinguish "when Phase 1 landed" from "when the whole IDEA closed":

```yaml
---
id: 163
status: complete
created: 2026-05-09
phase_1_completed: 2026-05-14     # Phase 1 PR merge date
completed: 2026-05-14             # Final phase merge date (matches the last shipped phase)
---
```

`phase_N_completed` keys are optional (only added when the IDEA actually shipped in phases). `completed` is canonical and always present at final close-out.

## When the audit catches a premature wrap

Walk back the wrap:

1. **Frontmatter** — revert `status: complete` → `in-progress`. Drop `completed: <date>`. Keep `phase_N_completed: <date>` for any phase that actually shipped.
2. **IDEA banner** — switch from ✅ COMPLETE to 🚧 IN PROGRESS — Phase N pending. Document the pending piece with ⚠️ and the R-number.
3. **Ideas-index** — move the entry from "References — Implemented" back to "In Progress". If a phase did ship, the References entry can stay as a "Phase 1 (canonical landed, legacy still firing alongside)" stub pointing at the In Progress entry; or just delete and re-add when the IDEA fully closes.
4. **Devlog** — if a devlog entry was already written under the wrong assumption, edit it in place to add the ⚠️ Phase N pending note. Don't delete — the entry's chronological position is load-bearing.
5. **Hand-back the gap to the user** — surface the unmet R-criterion as a follow-up task. Either ship the missing work in the same PR (preferred when the gap is small), or file as a sibling IDEA / follow-up PR.

## Anti-patterns

- ❌ **"Functionally complete" / "shipped" / "the visible behaviour works"** as justification for flipping to `complete` when R-criteria are unmet. Phrases like these are red flags during review; replace with literal R-number satisfaction.
- ❌ **Burying ⚠️ inside a longer summary paragraph** — comprehension cost compounds with summary length. The marker must be the first character of the line that mentions the gap.
- ❌ **Trusting the user's satisfaction with the visible behaviour over the plan's literal R-criteria.** The user may be happy with what shipped; the plan's R-criteria are the wrap-time contract. If they diverge, surface the divergence as a question before flipping status.
- ❌ **Adding "Phase 2 (future)" to a wrap output without ⚠️.** The future framing softens the gap; combined with no marker, it's a recipe for the next reader to skip the deferred work.

## Worked precedent — teisutis IDEA-163

Original wrap (2026-05-14): flipped `status: complete` after Phase 1 (PR #443) shipped canonical `entityChanged` alongside legacy per-name keys. R7 acceptance ("Per-name HX-Trigger emit sites and the corresponding per-name JS listeners are retired") was unmet — the legacy keys still fired and 2 JS consumers still listened on per-name events. Wrap output framed the gap as "Phase 2 (future)" with no ⚠️.

User caught the inconsistency mid-`/compound` when the compound PR body re-mentioned the deferred work ("wait IDEA-163 isn't fully implemented?"). IDEA re-opened, Phase 2 delivered as a sibling PR #444 on the same `sprint/ux-overhaul` cohort. Final close-out wrap landed on PR #444 with both phases satisfying R7.

The lesson driving this reference: the soft "Phase 2 (future)" framing without ⚠️ was the load-bearing failure. Had the original wrap output been `⚠️ Phase 2 pending — R7 unmet`, the next session's reader (the same agent post-compaction in /compound) would have seen the gap immediately and either deferred /compound until R7 closed OR opened a follow-up PR before the compound went out. Instead, the gap surfaced as a user catch-out.

## Relationship to other rules

- [`RULE_rename-before-drop`](../../../rules/RULE_rename-before-drop.md) — phase-shipped IDEAs are most common for convention migrations (rename in Phase 1, drop in Phase 2). The two-PR cadence is the normal shape; this audit ensures each phase's wrap honestly represents what shipped.
- [`RULE_cross-idea-amendments`](../../../rules/RULE_cross-idea-amendments.md) — when an IDEA's deferred work surfaces a defect in an already-shipped sibling IDEA, the wrap of the deferred PR may carry a cross-IDEA amendment. Audit each amended IDEA separately for its own R-criteria.

## Test before commit

Before pushing the wrap commit, re-read the final state of:

1. The IDEA file's frontmatter — does `status` and the date fields match what actually shipped?
2. The IDEA banner — would a reader who has not seen this conversation be able to tell what's complete vs pending just from this file?
3. The devlog entry — is the title prefixed with `Phase N` if applicable?
4. The ideas-index entry — does it land in the right section (In Progress vs References — Implemented)?

If any of the four answers is unclear, the audit has failed silently; revisit before committing.

**Last Updated**: 2026-05-14
