# Adversarial filter — critique and prune

The convergence phase of `/ideate`. Every divergent candidate gets subjected to the challenges below; those that survive get ranked; the rest are dropped. Load on demand at step 3.

## The filter's posture

Be the reviewer the ideas deserve, not the one you'd want to receive. Kind critique produces soft lists that turn into nothing; rigorous critique surfaces the handful that actually matter. Target dropping 30–50% of candidates. If fewer drop, the generation was too filtered already. If more drop, the generation was sloppy — the issue is upstream.

Do **not** rewrite candidates in the filter. Either keep or drop. Marginal candidates can be kept with a "weak — confirm before capturing" note.

## Challenge 1 — YAGNI probe

> "Who benefits from this, specifically, when?"

- If the answer is "future us, someday, probably" → drop.
- If the answer is "a user we've already heard complain / a metric we've already seen drag / a known bug" → keep.
- If the answer is "it would be more elegant / idiomatic" without a concrete downstream user → drop unless the cost is trivial.

The YAGNI probe is specifically about speculative work. Fixing known bugs always survives this challenge; adding capability we might need someday rarely does.

## Challenge 2 — Cost vs. value

Rough ratio:

| Effort | Value signal |
| --- | --- |
| XS (≈ 1 hour) | Any plausible user / future-maintainer benefit keeps it |
| S (≈ half day) | Needs one concrete beneficiary or one recurring pain point |
| M (≈ 1–2 days) | Needs a cited ROI — metric, incident, recurring user complaint |
| L (≈ week+) | Needs a business case or a plan-level initiative, not a one-off idea |

If the effort is L but the ideation context is "next sprint's quick wins" — drop. Suggest a separate `/plan` for large initiatives.

If the effort is XS but the value is imperceptible (whitespace cleanup, trivial rename) — keep as a background cleanup tagged `priority: low`, or drop if the list is already crowded.

## Challenge 3 — Prior-art check

For each candidate, grep:

```bash
# Mind-vault coverage — is this already a known pattern?
rg -l "<keyword-from-candidate>" ~/projects/mind-vault/skills ~/projects/mind-vault/rules ~/projects/mind-vault/agents

# Project-local coverage — already a documented solution?
rg -l "<keyword-from-candidate>" <project>/docs/solutions/

# Existing IDEA — already captured?
rg -l "<keyword-from-candidate>" <project>/docs/ideas/
```

If any match:

- **Mind-vault match** → the convention/pattern exists; the candidate is probably restating it. Drop unless the user wants to re-emphasise it.
- **`docs/solutions/` match** → the problem was solved before. Drop unless this is a recurrence (in which case the candidate is "make the old solution durable" — re-frame, keep).
- **Existing IDEA match** → already captured. Drop; don't create a duplicate.

## Challenge 4 — Sharpness

A candidate must be specific enough that a reader who's never touched the project could find the work. Test:

- Does the summary name a file path, module, command, or concrete behaviour?
- If two different engineers picked up the candidate, would they produce the same `/plan`?
- If the summary contains "improve", "modernise", "clean up", or "refactor" with no qualifier — challenge.

Fix the summary if it's close; drop if it's hopeless.

✅ **Sharp**: "Replace hand-rolled cookie parser in `static/js/auth.js:34` with the existing `utils.parseCookie` helper."
❌ **Vague**: "Improve JS code quality."

## Challenge 5 — Dependency awareness

If the candidate requires another candidate (from the same scan) or an existing IDEA to land first, flag with `depends_on: [<ids>]`. This doesn't drop it — it sequences it.

If the dependency chain is >2 deep (A needs B needs C), challenge: maybe the real work is the chain, not the leaf, and the user should `/plan` the chain as a single initiative.

## Challenge 6 — Ownership question

Who would execute the candidate? If the answer is:

- "The agent autonomously" → candidate is fine.
- "An implementation persona (backend / frontend / devops / test-engineer)" → candidate is fine; `AGENT_<persona>` dispatches in `/work`.
- "Requires external stakeholder approval / design input / product call" → the candidate isn't ready for IDEA capture. Drop or convert to an "ask" note.

## Challenge 7 — Cost of being wrong

For each candidate, ask:

> "If we capture this IDEA and later discover it's wrong, what's the cost?"

- **Low cost** (mark it as superseded, delete the file) → keep.
- **High cost** (we'd have wasted sprint capacity, or the IDEA existing in the index would mislead future ideation) → challenge harder. If the candidate isn't at least medium-confidence, drop it.

## Ranking the survivors

After dropping, rank remaining candidates:

1. Bugs / correctness → top (high priority, usually).
2. Recurring pain points with existing incident history → top.
3. High-value / low-effort wins → next.
4. Enabling work that unblocks multiple other candidates → next.
5. Polish / speculative improvements → bottom.

Ties broken by:

- Concreter scope wins over vaguer scope.
- Shorter effort wins over longer effort at the same value.

## Output for step 4

Emit the ranked survivors as a compact menu with:

- Priority band: 🔴 high / 🟡 medium / 🟢 low.
- Effort: XS / S / M / L.
- One-line summary.
- One-line "why it survived the filter" rationale.
- `depends_on:` pointers if applicable.

Example:

```text
1. 🔴 high · S — Add `select_related` to OrderListView queryset (orders/views.py:45)
   Why: Known N+1 storm on the orders dashboard (30+ queries per page load).
   depends_on: none.

2. 🟡 medium · M — Extract cookie parsing into shared utils (static/js/, 3 copies)
   Why: Same ~12-line parser copy-pasted in 3 places; drift risk.
   depends_on: none.

3. 🟢 low · XS — Add `make test-api` target for the DRF-only subset
   Why: User runs `./manage.py test api.tests` manually ~3×/week.
   depends_on: none.
```

Hand to step 4 for user selection.

---

**Last Updated**: 2026-04-19
