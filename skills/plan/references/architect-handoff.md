# Architect reviewer-pass handoff

How `/plan` invokes `AGENT_architect` as a reviewer over a drafted plan, and how it integrates the findings. Load this file on demand at step 5 of the plan skill.

## Why architect is a reviewer, not an author

`AGENT_architect`'s 4-pass workflow — abstraction/genericity sweep, coupling/dependency probe, boundary contradiction analysis, deployment/scaling pre-check — is shaped around reviewing an existing design, not generating one. Using it as author would degrade both: the plan becomes a verdict document, the architect's review loses its independent read.

Plan drafts the design; architect reviews it. Two distinct passes, two distinct outputs.

## When to invoke the reviewer

- **Required for medium and large plans** (see "Right-sizing" in `SKILL.md`).
- **Optional for small plans** if the scope touches coupling, abstraction boundaries, or cross-cutting concerns.
- **Skip for trivial plans** — architect review is over-engineering for a one-file fix.

## Invocation protocol

Use the Agent tool to spawn a subagent with `subagent_type: architect` (if available in the host) or invoke the persona inline from `agents/AGENT_architect.md`.

Prompt shape:

```text
You are AGENT_architect (see mind-vault/agents/AGENT_architect.md).

Review the drafted plan at <absolute-path-to-plan-draft>.

Run all four passes. Deliver the verdict in the structured ADR format from your
prime directives. Do NOT modify the plan file — findings go into your response
only.

Context:
- IDEA source: <path-to-IDEA-file or "none">
- Project: <project-name>
- Scope class: <small | medium | large>
```

Pass absolute paths. Do not inline the plan's contents — architect reads the file itself.

## Integrating the verdict

Architect returns one of three verdicts:

| Verdict | Integration action |
| --- | --- |
| 🟢 ARCHITECTURALLY SOUND | Mark the plan `status: ready`. Note the reviewer pass in the plan's Open Questions section as "Architect-reviewed 2026-04-19 — no findings." |
| 🟡 REQUIRES ABSTRACTION | Add each architect finding to the plan's Open Questions section with a recommended resolution. Revise the plan body (decisions, execution sequence) to reflect the required abstractions. Re-run architect review if the revision is substantial. |
| 🔴 REJECTED | Stop. The plan has a fundamental structural flaw. Return to the thin-input bootstrap or discuss with the user before re-drafting. Do not proceed to `/work`. |

## What architect is looking for

From `agents/AGENT_architect.md`:

- **Abstraction and genericity.** One-off hack or reusable pattern? If generic, belongs in `mind-vault/skills/` before being used.
- **Coupling and dependency.** Does frontend manipulate ORM directly? Tight coupling → isolation boundaries enforced.
- **Boundary contradictions.** Record deletion vs. attached CMS metadata — where are the fallback contracts?
- **Horizontal scalability.** Can it run on 5 load-balanced instances, or is state trapped in local sqlite / in-memory?

These are structural, not stylistic. If the plan passes architect but has, say, N+1 query risks, that's for `/bugbot-loop` in the review stage, not here.

## What NOT to pass to architect

- **The IDEA file alone.** Architect reviews plans, not ideas. If the plan hasn't been drafted, there's nothing for architect to do.
- **A plan that is still in bootstrap mode.** Thin-input bootstrap must complete first.
- **Plans without explicit file paths in the execution sequence.** Architect will reject for lack of tractable review surface; draft a real plan first.

## When architect is unavailable

If the host doesn't expose subagent dispatch, or `agents/AGENT_architect.md` isn't loaded:

1. Load `agents/AGENT_architect.md` as a reference read.
2. Apply the four passes inline, documenting findings in the plan's Open Questions.
3. Note in the plan: "Architect pass applied inline — lack of independent reviewer is a risk on this plan."

Do not skip the review for medium+large plans. Inline-applied is acceptable; unreviewed is not.

---

**Last Updated**: 2026-04-19
