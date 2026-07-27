# Deferrals need an expiry trigger, not just a successor ticket

A plan's out-of-scope section is where deferrals get written, and most of them are written in a form
that **cannot ever fire**. This reference is the shape to use instead, and the review question that
catches the bad form.

## The failure

A deferral is usually recorded as *what* was skipped plus *where it went*:

> ⚠ Foo remains open until IDEA-NNN. Acceptable for now — all callers are trusted internal services.

Both halves look complete, and the note is honest at the moment it is written. But the *justification*
("all callers are trusted") is a claim about the **surrounding context**, not about the work. Context
moves on its own schedule:

- a service that had one first-party caller acquires a second, then a third-party one;
- an internal-only surface gains an externally-reachable client;
- a "temporary" trusted network stops being the only network;
- a component with one consumer starts being consumed by a team that didn't write it.

Nothing in that note re-evaluates itself when the context changes. The successor ticket is inert — it
sits in a backlog being triaged on *priority*, while its actual trigger condition has already fired.
The observed case: an authorization gap deferred as "acceptable for trusted internal clients" stayed
deferred through the exact change (new, less-trusted consumers) that made it a real exposure, and
surfaced only because a human happened to ask "is there anything left to do here?" — not through any
mechanism in the plan.

**Why it hides:** the deferral note reads as *covered*. It names the risk, it names the successor, it
gives a reason. Everything a reviewer scans for is present. The missing piece is invisible — there is
no statement of what would make the reason **stop being true**.

## The shape to write

State the **invalidating condition**, so the note argues against itself the moment the condition holds:

| Form | Example | Fires? |
| --- | --- | --- |
| ❌ Inert | "Deferred to IDEA-NNN. Acceptable — all callers are trusted." | Never. Waits on backlog priority. |
| ✅ Self-invalidating | "Deferred **while every caller is first-party and trusted**. The moment a less-trusted or externally-authored consumer is onboarded, this becomes a real exposure and must be closed **first**." | On the context change, not on triage. |

Two mechanical rules:

1. **Name the assumption as a condition, not as a reason.** "Acceptable because X" is a reason; "deferred
   *while* X holds" is a condition. Same information, but only the second one can be observed to fail.
2. **Say what the expiry obligates.** "Revisit" is weak. "Must be closed before onboarding a consumer of
   kind Y" tells a future reader what to *do*, and makes the deferral a gate on that future work.

## Where this applies

- **Plan `Scope Boundaries` / out-of-scope** — the primary site. Every out-of-scope item justified by a
  context claim needs the condition form.
- **IDEA non-goals** — same test.
- **Wrap's "not done, by design" notes** — these outlive the PR and are read later as settled.

## The check, at plan and at review

For each deferral, ask: **"what would make this justification wrong?"**

- If the answer is *"someone does the deferred work"* → an ordinary backlog item. The successor ticket
  is sufficient; no trigger needed.
- If the answer is *"the environment changes"* (a new consumer, a trust boundary moving, a scale
  threshold, a component going multi-tenant) → **it needs an expiry trigger.** Write the condition.

**Reviewer heuristic — do not inherit a prior deferral's justification.** When a plan cites an earlier
decision as settled ("this was already deemed acceptable"), that justification was evaluated against
the *old* context. Re-verify the assumption against today's before reusing it. A deferral that was
correct when written can be wrong when cited, and citing it is what launders the staleness into the
new plan.

## The other half — catching one that already expired

Writing the condition helps the *next* deferral. It does nothing for the ones already sitting in the
archive in inert form, and those are the ones that bite. A well-written deferral still needs somebody to
notice its trigger fired — the note will not announce itself.

That catch belongs at **ideation**, not at plan time: by the time you are planning, you have already
chosen the work. The sweep is
[`../../ideate/references/divergent-scan.md`](../../ideate/references/divergent-scan.md) **Axis 9 —
Expired deferrals**: grep the archive for context-justified language, and for each hit ask what condition
the justification rested on and whether it still holds.

Worth knowing how the observed case actually surfaced: not by a process, but because a human asked "is
there anything left to do here?" during a backlog review. Axis 9 exists so that is a scan rather than a
lucky question.

## Related

- [`../../../rules/RULE_cross-idea-amendments.md`](../../../rules/RULE_cross-idea-amendments.md) — when
  an expiry does fire and the fix amends the earlier work's files, the bidirectional-documentation
  contract applies. Marking the original deferral note **closed, with the reason its condition expired**,
  is what stops the next reader re-deriving the whole argument.
