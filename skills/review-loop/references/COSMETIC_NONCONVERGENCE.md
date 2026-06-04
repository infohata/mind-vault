# Cosmetic / convention non-convergence — knowing when to stop fixing

Review engines — especially the slower, prose-sensitive ones — can emit a fresh low-value finding **every cycle** on descriptive or convention-governed text (changelog phrasing, doc wording, persona descriptions) without ever converging. Each finding is technically "new" yet the category never closes. Chasing each one burns billed review cycles for diminishing returns. Two disciplines keep the loop bounded.

## 1. Adopt-don't-fight — codify the convention or accept the valid point

When an engine flags the **same convention gap across multiple cycles** (each time a slightly different phrasing of the same complaint), the fix is NOT to re-word the instance again — it is to remove the gap at its root:

- **The engine is enforcing a stated rule the file drifted from** → make the file consistent with the rule, OR update the rule to match deliberate practice. Worked example: a `CHANGELOG` preface said "each bullet references the PR" but subsectioned releases carried provenance on the section's intro paragraph instead. The terminal fix was to **codify both styles in the preface** (per-bullet for rolling month-grouped entries, intro-paragraph for single-PR version sections) — not to stamp every bullet. The rule now matches practice and the bot has no gap left to flag.
- **The engine makes a valid technical point you'd been wording around** → accept it and state the limitation honestly. Worked example: a "read-only" reviewer persona that still grants `Bash` (which can mutate via `sed -i`). Successive rewords ("inspection only", "never to mutate") didn't satisfy it because the underlying claim — *tool-enforced* read-only — was false. The terminal fix was to say it accurately: "read-only here is a behavioral constraint, not a tool-enforced sandbox."

**Test:** if you've reworded the same line twice and the engine refines its complaint each time, you are re-litigating. Settle the convention or accept the point — one edit that ends the category, never a third instance-level patch.

## 2. Asymmetric hard-stop — trust the substance gate

In multi-engine mode the engines differ in what they catch. When a **substance engine** (correctness/bug-focused, e.g. Bugbot) is CLEAN for several consecutive SHAs while a **slower prose-sensitive engine** (e.g. Copilot) emits one cosmetic-wording nit per cycle:

- The clean substance gate is the **real merge signal**. The cosmetic engine is in one-nit-per-cycle mode on illustrative / descriptive prose (see auto-memory `feedback_illustrative_examples_not_production`).
- **Hard-stop on the substance gate.** Hand back with the residual cosmetic findings surfaced as Tier-3 the human can wave through at merge — do NOT spin another fix cycle for them.
- The no-progress guard (SKILL.md Phase 4) treats repeated same-**category** cosmetic-prose nits (changelog wording, doc phrasing, persona description) as a hand-back trigger **even when each cycle's specific finding is technically "new"** — the category recurrence is the signal, not the exact text.

**Exception — keep fixing only when a finding is genuinely non-cosmetic:** a logic error, a real contradiction, a broken link/reference, or a NEW finding from the substance engine. Those justify another cycle; prose-polish refinements do not.

---

**Field provenance:** emerged on a docs-heavy mind-vault PR where Bugbot cleared in one cycle and Copilot ran 4+ cycles of changelog / persona-wording nits. The productive resolution was to **adopt the conventions (§1) and hard-stop (§2)** rather than chase cycle 5+. The user's framing: "if changelog has a convention maybe we could adopt it rather than fighting on every review."
