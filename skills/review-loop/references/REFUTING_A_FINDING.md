# Refuting a finding — the evidence bar for overruling a review engine

Deciding a finding is a false positive is not a neutral act of triage. It is a **counter-claim**, and
it ships: the code stays as-is on the strength of it. This file sets the bar, because a refutation
made cheaply is the one triage error the loop cannot detect on its own — a wrongly-fixed finding shows
up as a bad diff, a wrongly-refuted one shows up as nothing at all.

## The two failure shapes, both observed in one PR (mind-vault PR #248, 2026-09-04)

**Shape 1 — the refutation rested on a remembered premise about our own pipeline, and the premise was
wrong.** An engine flagged a doc sentence claiming a branch deletion closes a stacked PR. The
refutation was: *"our per-IDEA PRs are absorbed by the integration merge, never merged individually,
so the platform's retarget-on-merge path cannot fire."* That premise was never checked — and the
pipeline's own skill body says the opposite a few lines later ("GitHub auto-closes each per-IDEA PR
**as a merged ancestor**"), which is precisely the precondition the retarget behavior keys on. Two
engines had independently flagged the sentence; both were right, and the refutation was reversed two
cycles later.

**Shape 2 — the same class of claim, tested instead of asserted, held.** An engine flagged a
`git worktree add … origin/auto/<A>` recipe as unreliable because "remote-tracking refs are updated by
fetch, not push". Rather than argue it, build the thing: a throwaway repo, a push, then
`git rev-parse origin/auto/A`. The ref resolved with no fetch and the `worktree add` succeeded. The
refutation held, and the other engine reached the same conclusion independently on the next cycle.

Same reviewer, same PR, same confidence — opposite outcomes. The difference was entirely the evidence.

## The bar

1. **A refutation needs evidence of the same grade as the finding it overrules.** "I don't think that's
   right" is not a disposition. Write the one-sentence *why*, and if it only paraphrases your prior
   belief, you have not refuted anything — drop it to Tier 3 and hand it back instead.
2. **A premise about our OWN repo or pipeline must be read, never recalled.** This is the trap, because
   it is the premise you feel most entitled to assert. Grep the skill body, the reference, the tool —
   the cost is one command, and it is the exact step that was skipped in Shape 1.
3. **A claim about tool or platform behavior should be tested, not argued.** A throwaway repo, a scratch
   container, a one-line API call. Empirical beats documented beats remembered. Where docs are the only
   option, prefer a changelog or release note over a version-pinned doc page, and quote it.
4. **Two independent engines converging raises the bar, and is a signal in its own right.** Distinct
   engines rarely invent the same false positive. Convergence does not make a finding correct, but a
   refutation must then explain *both* — if yours only addresses one, it is incomplete.
5. **A refuted finding that comes back unchanged is a no-progress signal, not an argument to re-win.**
   Same category, second cycle, no new evidence → Tier 3. Record the refutation and hand back; see
   [`COSMETIC_NONCONVERGENCE.md`](COSMETIC_NONCONVERGENCE.md).

## Record it in-band, not only in the hand-back

Put the refutation and its evidence in the **commit message** of the cycle that declines to fix it —
not solely in the hand-back report the engines never see. A body-only or suppressed finding has no
thread to reply to, so the commit is the only durable, reviewable place the reasoning lands.

This is load-bearing rather than tidy: on the next cycle the reviewing engine reads the branch and its
messages, and a refutation it can *see* is one it can agree with or rebut on the merits. Observed in
PR #248 — the following cycle's verdict took up the declined finding by name, worked through it
independently, and concluded *"I checked it and it's not actually a bug"*, converging the loop instead
of re-litigating it. The same in-band-acknowledgment mechanism [`../SKILL.md`](../SKILL.md) relies on
for deferred non-blocking items applies to refusals.

## Anti-patterns

- **Refuting to converge.** Wanting the loop to end is not evidence. If the only thing that changed is
  your patience, hand back with the finding open.
- **A refutation only a human could check, left for the human anyway.** If it needs a real instance to
  settle, say so explicitly in the hand-back and mark it unresolved — do not bank it as refuted.
- **Silently declining.** A finding that is neither fixed, refuted in writing, nor escalated has been
  dropped, and nothing in the loop will notice.
