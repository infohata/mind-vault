# RULE_audit-newly-reachable-code

## The Hard Rule

When fixing a bug whose pre-fix behaviour **short-circuited a code path** (the buggy code "did nothing visible", silently dropped a value, never entered a branch, never opened a UI surface), audit the **now-reachable code** for latent secondary bugs **before merging the fix**. The secondary bugs were masked while the primary bug short-circuited the path; they go from "invisible" to "visibly wrong" the moment the primary fix lands.

## Why this rule exists

A bug fix that turns a previously dead-end path into a live path **changes the symptom of every latent issue downstream of the fix**. Where the user previously saw "nothing happens" (the worse bug), they now see "the wrong thing happens" (the latent bug that was always there, just hidden).

The cost of not auditing is two-fold:

1. **The user perceives the fix as a regression.** They've never seen the latent issue before — the primary fix is what made it visible. From their seat, the symptom is new, and the new symptom landed in the fix's commit. Blame attaches to the fix, not the pre-existing gap.
2. **A second fix-cycle costs more than auditing once.** The user reports the "regression", the agent investigates, discovers it's pre-existing, and ships a follow-on commit. That whole cycle was avoidable: one audit pass at the moment of writing the primary fix would have surfaced the latent issue and let both fixes ship together.

The discipline this rule encodes: **a fix removes a layer of camouflage from the code it touches**, and the audit at fix-time is the only cheap moment to find what the camouflage was hiding.

## When this applies

- **Empty-input / empty-state guards added to a primitive.** Pre-fix: empty input fell through silently. Post-fix: empty input goes through the normal flow. Audit: does the normal flow handle empty / minimally-populated frames the way real frames are handled?
- **Short-circuit returns removed.** Pre-fix: early-return on a flag prevented downstream code from running. Post-fix: the flag is gone and downstream code runs unconditionally. Audit: did anything downstream silently rely on the early-return as an invariant ("we never get here when X is true")?
- **Missing call inserted.** Pre-fix: code path lacked an `init()` / `open()` / `register()` call so the side effect never happened. Post-fix: the call fires. Audit: do all the downstream consumers of that side effect produce sensible output with the freshly-initialised state?
- **Async / promise chain fixed to actually resolve.** Pre-fix: a callback never fired because of a missing `.then()` / `await`. Post-fix: the callback fires. Audit: does the callback's payload have the shape the consumer expects, or was it always going to crash on first real invocation?
- **Type-gate / permission-gate relaxed.** Pre-fix: a check rejected some inputs that should have been accepted. Post-fix: more inputs reach the consumer. Audit: does the consumer handle the freshly-accepted shapes, or was it tested only against the narrower pre-fix set?

Does **not** apply to: bug fixes that *narrow* a code path's reach (adding stricter validation, removing a fallback that was wrong, tightening a type). Those don't unmask latent bugs — they hide bugs further. (They have their own rule shape: regression test on the now-rejected inputs.)

## How to apply

At the moment of writing the fix, **before pushing the commit**:

1. **Identify the code path the fix unblocks.** Trace from the fix site outward: which functions / DOM elements / templates / consumers will now run / render / receive payloads they previously couldn't?
2. **Audit each downstream surface for the "first-time-reachable" hazards:**
   - Are all the fields / attributes / DOM nodes the downstream code reads actually populated for the now-reachable case?
   - Does the downstream code's existing test coverage exercise this newly-reachable path, or was it only tested via paths that bypass the buggy primitive?
   - Are there assertions, getters, or template bindings downstream that would render empty / null / undefined visibly to the user?
3. **Decide one of three responses per latent issue found:**
   - **Fix in the same commit / PR** when the latent issue is in the same file or a tightly-coupled file — the fix is the prompt; bundling is the natural scope. (Example: teisutis PR #446 — `openWith()` empty-stack guard + the prefix-frame title pairing both landed in the same PR.)
   - **Fix as a follow-on commit on the same branch** when the latent issue needs server-side template changes or cross-app coordination that would balloon the primary fix's diff. Still ship in the same PR, but as a discrete commit so the trail is clear.
   - **File a follow-up IDEA / issue** only when the latent issue requires substantially more work than the primary fix and shipping the primary alone is genuinely better than holding both. Document the trade-off explicitly in the PR body so the reviewer sees the scope decision.

The **most common wrong response** to finding a latent issue during the audit: shipping the primary fix alone and "leaving the latent for later". This is the path the cycle math punishes — the latent surfaces in user smoke or in a bugbot follow-up review, costing the second-fix cycle the audit was meant to prevent.

## Anti-patterns

- ❌ Shipping the primary fix without an audit, then treating the smoke-surfaced latent as a separate "new edge case found while testing". It wasn't new — it was always there; the fix just made it visible.
- ❌ Auditing only the file the primary fix touches. Latent issues often live in template-binding sites, downstream getters, or consumer modules — the camouflage was at the primitive, the latent often is at the surface.
- ❌ "The latent has its own bug class — it's not part of this fix." True in isolation; false in context. The primary fix's effect on the latent's *visibility* couples them whether the codebase wants it or not.
- ❌ Defending shipping-primary-alone with "the latent existed before my fix". The user's experience starts from the moment the primary fix lands. Audit + bundle, or audit + explicit scope-decision in the PR body.

## Concrete example — teisutis PR #446 (provenance)

The rule surfaced from this PR. `previewSurface.openWith()`'s empty-stack case used to push frames invisibly because the path lacked an `open()` call. The fix added the missing `open()` and the drawer now opens correctly. **But** the prefix frames born via the now-reachable path carried `title: ''` because `_parseStackPrefix` never paired titles — a separate latent in the server emit + client parse contract. The user smoke caught it; a follow-on commit (`facd6c08`) paired titles with the prefix CSV. Both fixes shipped in the same PR but as discrete commits. The whole "second fix cycle" was avoidable if the audit pass had been done at primary-fix time.

The divergence-branch `lcpLen === 0` path inside `openWith` had the same title-less prefix problem; it just wasn't routinely exercised by real-user clicks, so it stayed hidden. Without the audit, that branch would have continued shipping with the bug masked by usage frequency.

## Relationship to other rules

- [`RULE_self-sweep-before-push`](RULE_self-sweep-before-push.md) — covers **structural** sweep (dead imports, unused locals, stale comments). This rule covers **behavioural** sweep (latent issues newly reachable). Both run pre-push but on different surfaces; one rule's pass-clean signal does not satisfy the other.
- [`RULE_git-safety`](RULE_git-safety.md) — branch policy is unchanged. The audit happens on the feature branch before push; the merge-to-protected gate stays human-initiated.
- [`RULE_rename-before-drop`](RULE_rename-before-drop.md) — the "post-drop re-test" guidance there is the same shape as this rule's audit pass: a fix changes a code path's reach, and re-test catches the latent issues the prior code's behaviour was hiding. This rule generalises the discipline beyond rename-drop sequences.

---

**Last Updated**: 2026-05-15
