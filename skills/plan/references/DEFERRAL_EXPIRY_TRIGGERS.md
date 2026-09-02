# Deferrals need an expiry trigger, not just a successor ticket

A plan's out-of-scope section is where deferrals get written, and most of them are written in a form
that **cannot ever fire**. This reference is the shape to use instead, and the review question that
catches the bad form.

A deferral is the most common instance of a wider failure — a written statement standing in for a
mechanism — and this file is that failure's home. Deferrals first; the general form, and the second
family of instances, are in [§ The wider mechanism](#the-wider-mechanism--a-record-is-not-a-mechanism).

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

Deferrals get written at almost every stage of the workflow cycle; each write-site points back here:

- **Plan `Scope Boundaries` / out-of-scope** — the primary site. Every out-of-scope item justified by a
  context claim needs the condition form. (Wired: plan SKILL step 4 + the plan template's out-of-scope
  placeholder.)
- **IDEA non-goals** — same test. (Wired: idea SKILL Phase B template substitution.)
- **Work's punt list** — follow-up work punted to new IDEAs mid-execution, recorded in the archive-dir
  README. (Wired: work SKILL § 6a.)
- **Wrap's "not done, by design" notes and follow-up flags** — these outlive the PR and are read later
  as settled. (Wired: wrap SKILL Step 6 follow-up disposition.)
- **Review-loop deferred findings** — a `NON_BLOCKING` finding formalized into an IDEA instead of fixed.
  (Wired: review-loop SKILL § NON_BLOCKING disposition.)

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
there anything left to do here?" during a backlog review. Axis 9 exists so that catch is a scan rather than a
lucky question.

## The wider mechanism — a record is not a mechanism

> A written statement is consumed as though it were a live control or a live fact, when **nothing in
> the system evaluates it at the moment of action** and **nothing invalidates it when the world moves**.

Two halves, and a deferral note manages to be both:

- **Not refreshed.** The record was true when filed, and nothing emits an event when its premise dies —
  so only drift somebody happened to notice is ever corrected. Everything above is this half; a backlog
  item's scope statement and a "resolved" question note expire the same way, silently.
- **Not enforced.** The record is true *right now* and still does nothing, because no code path reads it
  at the moment it matters. The two instance families below are this half.

One obligation per half: **every deferral needs an expiry trigger, not just a successor ticket; every
condition you could assert should be asserted rather than printed.**

**Discriminator.** If several live copies of a fact disagree, that is the sweep pattern
([`../../../rules/RULE_self-sweep-before-push.md`](../../../rules/RULE_self-sweep-before-push.md)) —
making them agree fixes it. If a single statement is already correct and self-consistent and still
fails, it is this one, and agreement changes nothing: the missing piece is a trigger or a wire.

### Guidance a tool PRINTS is untested code that runs in the operator's hands

Output that instructs a human — a suggested command, a warning emitted by a dry run, a "consider rolling
back" hint — is neither tested nor enforced, yet it executes at the moment the operator is already stuck.
No test in any toolchain runs advice. Three shapes, in ascending severity:

1. **A condition the tool could assert but only prints is not a control at all.** Observed: a repair
   script's dry run printed *"if the account is already the production one, STOP — do not `--apply`"*,
   while `--apply` unconditionally reset that account and dropped the artifact it held. The repair was
   two executable `die` guards ahead of the destructive stage. **Re-assert every precondition a dry run
   states, programmatically, in the destructive path — die, do not print.** A block pasted into an
   operator's terminal must `exit`, not warn: pasted blocks carry no strict mode, so a warning that
   should have been a refusal simply scrolls past into the privileged commands beneath it.
2. **A recipe rendered from machine status is wrong in exactly the states the author never enumerated** —
   sometimes plausible *and* destructive. Mechanics and the per-state recipe partition live in
   [`../../shell/references/MAINTENANCE_SCRIPT_CONTRACT.md`](../../shell/references/MAINTENANCE_SCRIPT_CONTRACT.md).
   The planning-level rule is the enumeration axis: **enumerate the state space on the axis the FORMAT
   uses, not the axis your prose uses** — for a two-column status format that is the cross product of
   both columns, not your four prose categories — and the discriminator is never *"which category is
   this"* but ***"which command actually clears this entry"***, verified by running the emitted recipe
   and re-reading status.
3. **An expected, benign condition recommending the undoing of the change that just succeeded.** Observed:
   a `--verify` tripped on a lingering established socket and printed *"consider `--rollback`"* — which
   would have restored the very access the change had just removed. The fix is a WARN plus an explicit
   *"do NOT roll back for this"*, with `--apply` clearing the transient itself.

**Review will not converge on this on its own.** Asked outright for *"any unaccounted status class"*, a
reviewer enumerates the full set; left to itself, each round surfaces only the input class it happened to
construct — four consecutive rounds landed on one ~15-line block and the founding defect was still live
afterwards, because a fix verified at the point of extraction was undone at the point of use. So ask for
the enumeration explicitly, and **rank fixes by the severity of following the advice**: "useless" costs a
detour, "runs and destroys work" is a different class.

### A rule you wrote is not a rule you ran

An entry in an ignore file is an untested assertion that fails silently, and the file parses cleanly
either way. Two shapes:

1. **Annotation kills the pattern.** Where the format opens comments only at line start, `path   # why`
   is stored as one literal pattern, prose and spaces included, and matches nothing. Grammar and the
   proof recipe (assert against a comment-free neighbour so a green result cannot be a broken instrument)
   are in [`../../shell/references/SAFE_CONFIG_EDITS.md`](../../shell/references/SAFE_CONFIG_EDITS.md).
2. **DERIVED paths are not covered by the name they derive from.** A pattern keyed on an exact or
   suffixed name never matches what tooling writes *beside* it: `x.bak.<stamp>`, `x.age`, `x.enc` are
   matched by neither `x` nor `*x`. A break-glass backup inherits the protected file's directory and the
   reviewer's *"that's ignored"* while inheriting none of its pattern.

Guardrail: **run the ignore-check on every protected path AND on every path any script writes** —
backups, encrypted blobs, probe output, logs — and **write break-glass backups outside the repository**,
into a mode-`700` temp dir, never beside the file they protect. Observed dwell between introduction and
discovery ran 2 to 19 days and discovery was accidental every time (a review, or an unrelated file turning
up untracked); one instance was authored weeks *after* the identical lesson had been written down, by the
person who wrote it. The failure is habitual rather than knowledge-shaped — which is exactly why the
remedy has to be a check that executes, not a better note.

**State the severity honestly when one of these is found.** In every documented case the gap was *latent*
rather than a staged secret: the protected artifact did not yet exist, or the run that would have created
it had never happened, or the gap was caught in review before it reached the default branch. Verify the
artifact existed inside the window before calling it exposed — a pattern's name is a record of intent, not
evidence of what was on disk.

## Staged gates rot — re-probe the dependency's source before honoring one

A phase plan parked a feature set as *"backend-gated — pending amounts are not in the record's
detail payload"*. The gate was true as stated and architect-confirmed. The **same evening**, thirty
minutes of reading the backend repo's source showed the entire feature was served by a
*different, pre-existing* endpoint family — filterable index, send endpoints, history, template
list — and the "gated" phase shipped client-only that night. The gate had never been false; it
had been **scoped to one data path** while an adjacent path already existed.

The lesson generalizes past expiry: an out-of-scope list is a snapshot of what the planner knew,
and "blocked on X" often means "blocked on the one approach we considered". So:

- **Before honoring a staged gate as the reason to pick different work, re-probe it from the
  dependency's source** — not from the plan that recorded it. Half an hour of reading the other
  repo is cheap against a phase parked for weeks. Only possible when the dependency's source is
  readable; when it isn't, say so in the gate ("verified from the API surface only").
- **Write gates as the *capability* that is missing, not the *endpoint* that lacks it.** "The
  record's detail payload has no pending amounts" invites checking one payload; "no API serves
  pending amounts anywhere" invites the sweep that would have un-gated it immediately.
- When a re-probe un-gates a phase, the plan that parked it gets the same closed-with-reason
  annotation an expired deferral gets — the next reader must not re-derive the gate.

## Related

- [`../../../rules/RULE_cross-idea-amendments.md`](../../../rules/RULE_cross-idea-amendments.md) — when
  an expiry does fire and the fix amends the earlier work's files, the bidirectional-documentation
  contract applies. Marking the original deferral note **closed, with the reason its condition expired**,
  is what stops the next reader re-deriving the whole argument.
