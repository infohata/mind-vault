---
id: "018"
title: Scrub prior-project provenance identifiers from tracked files
status: complete
priority: high
supersedes: []
superseded_by: null
depends_on: []
related: []
created: 2026-06-07
completed: 2026-06-07
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false
auto_safe_reason: "/plan research (2026-06-07) DISPROVED the functional-default worry: all 3 tool-script hits are pure comments (`bash -n` clean, no REPO=/owner= defaults). Remaining judgment is generalisation phrasing (drop tag vs neutral descriptor) + the scrub-gate instruction rewrite — model-judgment work, not a blind sed. Still human-reviewed (public-safety stakes), so left false."
sensitive_paths_cleared: false
sensitive_paths_cleared_reason: "Touches the review-loop tool scripts (tools/find_*_comments.sh) — but only their comments; scripts re-parse clean (`bash -n`). Human eyeballs the script + scrub-gate diffs before merge."
---

# IDEA-018: Scrub prior-project provenance identifiers from tracked files

**Status**: ✅ Complete (2026-06-07) · PR #186
**Priority**: High

**Problem** (or opportunity): mind-vault carries a pervasive prior-project identifier (`teisutis`) across **~90 references in ~20 tracked files** — accumulated organically over months of `/compound` provenance bullets. Locations include: ~47 lines in `CHANGELOG.md`; two **SKILL bodies** (`skills/compound/SKILL.md`, `skills/idea/SKILL.md`); the **review-loop tool scripts** (`tools/find_claude_comments.sh`, `tools/find_copilot_comments.sh`) where it may be a functional example/default rather than narrative; `docs/guides/` (AGENT_PORTABILITY, SKILL_AUTHORING_WALKTHROUGH); `README.md`; `docs/ideas/README.md`; and numerous archive IDEA/plan/session-note docs. mind-vault's own `/compound` customer-data scrub gate is explicit that the repo must be **public-repo-safe** ("private today, public tomorrow") and even names `teisutis PR #475` as an example of a foreign-project ref to drop — yet the identifier is woven throughout. Surfaced 2026-06-07 while scrubbing a *different* client leak (`BookingRobot-M`) during compound PR #184; that sprint's identifiers were cleaned in-PR, but the `teisutis` class is too large and too entangled with executable tooling to ride a compound.

**Proposal** (or idea): a deliberate, tested scrub pass that generalises every `teisutis` occurrence to neutral framing (drop the project tag, keep the lesson — e.g. "what the first-suite stand-up learned", "an external Django project") consistent with how the scrub gate already prescribes generalising IDEA-tagged narrative. Sequence by risk:
1. **Tool scripts first, with a behavioural test** — `tools/find_*_comments.sh`: determine per-hit whether `teisutis` is a hard-coded repo/owner default (functional — must be parameterised or replaced with a generic placeholder that keeps the script working) vs a comment/example (narrative — just generalise). Run each script against a real PR after editing to confirm it still resolves comments.
2. **SKILL bodies** (`skills/compound`, `skills/idea`) — these load on invocation; generalise the example references.
3. **Guides + READMEs** — narrative generalisation.
4. **CHANGELOG + archive docs** — bulk narrative generalisation (highest count, lowest risk); decide once whether to drop the tag or replace with a neutral descriptor and apply uniformly.

Real project names stay only in **local memory** (`~/.claude`, never synced/tracked) — that's the correct home per the THIS-MACHINE-ONLY routing rule.

**Why now**:
- Public-repo-safety is the scrub gate's whole point; until this clears, mind-vault cannot safely go public, and every new `/compound` risks adding more.
- The pattern was just freshly surfaced (PR #184) — the cleanup intent is hot and the extent is mapped.
- Doing it as its own IDEA gets the **tool-script edits a test pass** instead of being smuggled into an unrelated compound PR.

**Non-goals**:
- NOT part of compound PR #184 (which scrubbed only the `BookingRobot-M`/`br-*` Phase-2 leak). This is the separate, larger `teisutis` class.
- NOT a rewrite of the lessons themselves — provenance generalisation only; the compounded knowledge stays intact.
- NOT touching local memory (`~/.claude`) — real names belong there.
- NOT a broader "audit every possible identifier" sweep beyond `teisutis` (though the scrub should grep for any other stray project/owner names while it's in there).

**Related**: Surfaced during IDEA-014 Phase 2's compound (PR #184 scrubbed the sibling `BookingRobot-M` leak). Enforces the `/compound` customer-data scrub gate (`skills/compound/SKILL.md` § Mind-vault promotion, step 5) repo-wide.
