# SKILL_CONTRACT

The interface between a **stack-agnostic agent profile** (`agents/AGENT_*.md`) and the
**framework-stack skill** that supplies the concrete idioms for the repo under work.

A persona's `## Stack adapter` section never names a concrete framework. It names a
*role* ("the active backend skill", "the active frontend skill") plus a **contract
heading** below. At dispatch time the active stack is resolved (see
[`../skills/work/references/persona-dispatch.md`](../skills/work/references/persona-dispatch.md)),
and the agent reads the rule under that heading in the resolved skill. Swap the stack,
swap the skill — the profile is untouched. That is the whole mechanism.

## The tiering invariant

```text
craft agent  →  framework-stack skill  →  language-base skill
(AGENT_*.md)     (django, django-frontend,   (python — language-general;
                  future laravel*)            NOT contract-bearing)
```

**Only framework-stack skills expose this contract.** A language-base skill
(`skills/python/`, the IDEA-009 layer) sits *beneath* the framework skill and carries
language-general recipes, not stack idioms — it has no contract headings and an agent
never resolves a contract heading against it. The down-pointer `django → python` is the
same *shape* as the up-pointer `agent → django` defined here, one tier lower.

## How a stack skill satisfies the contract

A framework-stack skill MUST expose every **required** heading below as a literal
`###` section so a generic agent resolves it uniformly across stacks (grep-resolvable —
same string in every stack's skill). It MAY add any number of **optional extras**; the
contract is a *floor*, not a checklist every stack must exhaust. Forcing empty slots on
a stack that has no answer is the over-abstraction failure this floor is sized to avoid
— it is what keeps a new stack (Phase 2 Laravel) a true zero-agent-edit drop-in.

### Backend — required floor (6)

| Contract heading                  | What it answers (stack-neutral)                                         | Django section (worked example)            |
| --------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------ |
| **ORM eager-loading**             | How to avoid N+1 / over-fetch when traversing relations                | `### ORM eager-loading` (select/prefetch)  |
| **Input-validation boundary**     | Where untrusted input is validated — at the edge, never deeper         | `### Input-validation boundary` (index)    |
| **Background jobs**               | How deferred / async work is queued and run                            | `### Background jobs` → `references/CELERY.md` |
| **Data isolation / scoping boundary** | How every query is scoped to the caller's data; never leak across   | `### Data isolation / scoping boundary`    |
| **Permissions/authorization**     | The single source of truth for "is this caller allowed?"               | `### Permissions/authorization` (probe)    |
| **Testing conventions**           | How tests are written, isolated, and kept fast                         | `### Testing conventions` → `references/TESTING.md` |

**Fail-closed bar (Data isolation / scoping boundary).** The canonical scope
sample a stack skill ships for this heading MUST **fail closed**: when there is no
caller/tenant context, it returns **zero rows**, never an unscoped query. The naive
`if ($ctx) { …add filter… }` (no `else`) fails *open* — in any context where the
context resolver is empty (a background worker, a CLI command, a scheduler tick with
no request/session), it adds no filter and leaks every tenant's rows. This bar is
load-bearing because the same section invariably tells readers to *trust the scope*
(don't re-add manual filters), which removes the manual fallback — and an
implicit-rewrite scope hides the open-fail (reads look correct). Both voices enforce
it: the author (`mv-backend`) fills the heading fail-closed; the reviewer
(`mv-curator`) asserts it and flags any context-gated filter with no zero-rows else.

### Frontend — required floor (4)

| Contract heading              | What it answers (stack-neutral)                          | Django-frontend section (worked example) |
| ----------------------------- | ------------------------------------------------------- | ---------------------------------------- |
| **Reactivity model**          | Where client state lives and how the UI reacts to it    | `### Reactivity model` (Alpine on `<html>`) |
| **Partial/fragment response** | How a server returns a fragment vs a full page          | `### Partial/fragment response`          |
| **Component system**          | How reusable UI units are composed (markup + styling)   | `### Component system` (Cotton + Bulma)  |
| **Form-submission lock**      | How a form is guarded against double-submit             | `### Form-submission lock`               |

### Optional extras (skill keeps; NOT required of every stack)

Backend: translation/i18n workflow, async / real-time (Channels/WebSocket), model-layer
abstractions, migrations, caching. Frontend: modal management, URL-query safety, HTMX
dynamics, template hazards, accessibility, scroll preservation. These stay as skill
content; a second stack fills them only if its passes need them.

## Reviewers consume the same contract — they don't define their own

`mv-curator` and `mv-test-engineer` *check* the same headings their author-side
counterparts *fill*. There is one contract, read in two voices:

- **Author voice** (`mv-backend`/`mv-frontend`): "satisfy the active backend skill's
  **ORM eager-loading** rule."
- **Assert voice** (`mv-curator`/`mv-test-engineer`): "confirm the queryset satisfies
  the active backend skill's **ORM eager-loading** rule."

No parallel reviewer-contract exists. Same anchors, different verb.

## Fail-open contract (load-bearing)

Pre-split, a stack rule was inline in the profile = always enforced. Post-split, it is
enforced only if the stack skill loads. So **every `## Stack adapter` MUST state its
resolution-failure behaviour**: when stack resolution yields no skill (no pin, no
detect, ambiguous), the agent enforces its **craft core only** and **announces the
unresolved-stack gap** — it never silently skips a stack rule. Silent fall-through on an
un-provisioned repo is the exact failure a new-stack adopter would hit; announcing it is
the difference between a loud gap and an invisible one.

## Stack resolution

Resolution order and the auto-detect signal table live in
[`../skills/work/references/persona-dispatch.md`](../skills/work/references/persona-dispatch.md):
`.claude/dispatch.md` `stack:` pin → `AGENTS.md` pin → auto-detect signals → ask once.
