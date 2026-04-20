---
name: plan
description: Turn an IDEA file or rough feature description into a durable technical plan at docs/plans/YYYY-MM-DD-<slug>-plan.md. Interactively explores requirements when input is thin (brainstorm front-end merged in). Invokes AGENT_architect as a reviewer pass. Second stage of the mind-vault sprint workflow; aliased as /brainstorm.
---

# plan

Second stage of the five-stage sprint workflow (`idea → brainstorm/plan → work → review → compound`). Turns an atomic IDEA file or a rough feature description into a durable plan that an agent — or a human — can execute from without re-inventing product behaviour, scope boundaries, or test scenarios.

This skill merges the brainstorm + plan stages from CE. When input is already specific (a filled-out IDEA file, a bug report with clear repro), the skill skips straight to plan authoring. When input is thin (a one-line description, an IDEA stub), a **thin-input bootstrap** fires — the interactive brainstorm front-end — before the plan is written. Brainstorming is a mode, not a separate skill. `/brainstorm` is an alias for `/plan`.

This skill does not write code, run tests, or modify project source. It does, however, author the plan artifact and — per [`RULE_ideas-location-status`](../../rules/RULE_ideas-location-status.md) and step 7 below — trigger the single `git mv` that moves the source IDEA file from `docs/ideas/` into its `docs/archive/YYYY-MM-idea-NNN-<slug>/` dir. The plan artifact itself lands in that same archive dir. Execution belongs in `/work` (the next stage).

## When to use

**TRIGGER when:**

- user says "plan this", "write a tech plan", "plan the implementation", "how should we build X", "break this down", "what's the approach for Y", "let's brainstorm X", "help me think through X", "deepen the plan"
- user references an existing IDEA file by slug (`/plan sprint-workflow`) or path
- an IDEA file was just created by `/idea` and the natural next step is to turn it into a plan
- the user provides a bug report, a feature idea, or a rough description that would benefit from structured decomposition before execution

**SKIP when:**

- the work is a one-off trivial fix (typo, one-line bugfix) that a plan would over-engineer
- the user wants to start coding immediately on something well-understood — route to `/work` directly
- the user is still exploring "what to build" at a portfolio level with no single target in mind — route to `/idea` (or multiple `/idea` invocations) to surface candidates first

## Pattern

### 1. Resume, source, and scope

Before drafting anything, check for existing work and classify the input.

1. **Check for an existing plan.** Plans live inside the source IDEA's archive dir per step 7 (`docs/archive/YYYY-MM-idea-NNN-<slug>/YYYY-MM-DD-<slug>-plan.md`); there is no separate `docs/plans/` tree. If the slug (explicit argument or derived from the input) matches `<project>/docs/archive/*-<slug>/*-<slug>-plan.md`, offer to continue: "Found `2026-04-19-sprint-workflow-plan.md` in `docs/archive/2026-04-idea-042-sprint-workflow/`. Resume or start fresh?" Default to resume unless the user says otherwise. For small-scope plans that were emitted ad hoc per step 6's skip-condition, also fall back to a repo-wide `*-<slug>-plan.md` glob as a best-effort.
2. **Resolve the input source.** Accept in order: IDEA file path, IDEA slug (`/plan sprint-workflow` → glob **both locations** `docs/ideas/IDEA-*-sprint-workflow.md` AND `docs/archive/*/IDEA-*-sprint-workflow.md`, since an already-in-progress idea has been moved to its archive dir per step 7 and a deepening pass must still find it), plan-file path for deepening, raw description in the command argument, or nothing (ask the user what to plan).
3. **Classify scope** early: trivial / small / medium / large. Trivial skips out of the skill entirely. Small gets a compact plan. Medium and large get the full structure. Do not force ceremony onto work that doesn't need it.

### 2. Thin-input bootstrap (brainstorm front-end)

When the input is thin — a one-liner, an empty IDEA stub, or a description with evident gaps — enter interactive mode before drafting the plan.

Thin-input indicators:

- IDEA file has fewer than ~3 substantive prose paragraphs in the body.
- Raw description is under ~30 words.
- No success criteria, no scope boundary, no constraints surfaced.
- Multiple valid interpretations of what the user wants.

When thin, run the bootstrap per [`references/thin-input-bootstrap.md`](references/thin-input-bootstrap.md): one-question-at-a-time, prefer single-select blocking question tools, capture decisions in-memory, then proceed to plan authoring with the enriched context. Bootstrap output may also update the source IDEA file's prose body if one exists — confirm with the user before writing back.

Not thin — skip the bootstrap and go straight to step 3.

### 3. Research before structuring

Before drafting the plan, do the research the plan depends on.

- **Repo pattern scan.** Grep for existing abstractions the work should reuse — base classes, utility functions, similar features. Do not propose new code when a suitable implementation exists.
- **Institutional-learnings pass.** Check `<project>/docs/solutions/` for prior solved problems tagged with overlapping keywords. Check `mind-vault/skills/*/SKILL.md` and `mind-vault/rules/RULE_*.md` for cross-project patterns that apply.
- **External-references pass (only when warranted).** If the plan depends on framework behaviour, SDK semantics, or a spec the agent isn't sure of, note the reference; surface ambiguity in the plan's Open Questions section rather than guessing.

Right-size the research — a one-session fix doesn't need a literature review.

### 4. Draft the plan

Read [`assets/plan-template.md`](assets/plan-template.md) and fill its sections. Canonical plan structure (mirrors the CE-inspired shape that this mind-vault plan was itself written in):

1. **Context** — why this work, what prompted it, intended outcome.
2. **Problem Frame** — what's broken or missing, how it hurts today.
3. **Requirements Trace** — R1, R2, … each traceable back to the IDEA body or the user's request.
4. **Scope Boundaries** — in-scope / out-of-scope / explicit non-goals.
5. **Context & Research** — existing code and patterns to reuse (with file paths), institutional learnings, external references.
6. **Key Technical Decisions** — opinionated defaults with one-line rationale each.
7. **Open Questions** — things that need user input before execution starts. Suggest a default per question; mark resolved questions inline.
8. **Execution Sequence** — ordered steps (files to create/modify, commands to run, tests to write).
9. **Verification** — how to confirm the work lands correctly. Commands or checks, not vibes.

Plan quality bar:

- Repo-relative file paths everywhere. Never absolute.
- Concrete file paths in the execution sequence, not "the auth module".
- Test scenarios listed per feature-bearing unit, specific enough that an implementer knows exactly what to test without inventing coverage.
- Decisions carry rationale, not just names.

### 5. Architect reviewer pass

Once the draft is written, invoke `AGENT_architect` as a reviewer. Not as author — the plan is already drafted. See [`references/architect-handoff.md`](references/architect-handoff.md) for the handoff protocol.

The architect's 4-pass workflow (abstraction/genericity sweep → coupling/dependency probe → boundary contradiction analysis → deployment/scaling pre-check) produces a verdict: ARCHITECTURALLY SOUND, REQUIRES ABSTRACTION, or REJECTED. Incorporate findings before marking the plan `status: ready`.

The reviewer pass is optional for trivial and small plans. Required for medium and large.

### 6. Transition the source IDEA — single move, then never again

Per [`RULE_ideas-location-status`](../../rules/RULE_ideas-location-status.md), the act of drafting a plan is the signal that an idea has left the backlog. This triggers the **one and only** filesystem move in the IDEA file's life — and it must run **before** step 7 writes the plan file, because step 7 emits the plan into the dir this step creates:

```bash
mkdir -p <project>/docs/archive/YYYY-MM-idea-NNN-<slug>/
git mv <project>/docs/ideas/IDEA-NNN-<slug>.md \
       <project>/docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md
# + update frontmatter: status: in-progress
# + update docs/ideas/README.md: move the entry from its priority section
#   into "🚧 In Progress" (link now points at ../archive/<dir>/)
```

`YYYY-MM` = current month. Stays fixed across the rest of the idea's life — neither completion nor rejection renames this dir.

After this step's move, step 7 emits the plan file into the same dir. All subsequent artefacts (research notes, session prompts, screenshots, the eventual README) go into this dir too. Future `/work` on completion edits frontmatter to `status: complete` — **no further file movement**.

**Always run this step when `/plan` is invoked**, even for trivial or small scopes. Earlier drafts allowed skipping the move for small scopes; that created a gap where a complete IDEA could end up sitting in `docs/ideas/` (location-status mismatch per `RULE_ideas-location-status` hard rule #2). `/plan` is the primary owner of this transition; if the user bypassed `/plan` entirely and went straight to `/work`, `/work` performs the same move as a fallback.

### 7. Emit the plan file into the idea's archive dir

Plans live **alongside the IDEA file they implement**, inside the same `docs/archive/YYYY-MM-idea-NNN-<slug>/` dir per [`RULE_ideas-location-status`](../../rules/RULE_ideas-location-status.md). There is no separate `docs/plans/` tree — that was an earlier draft and was dropped in favour of co-location (cross-refs between plan and IDEA file stay local; no cross-tree paths).

Step 6's move has already created the archive dir and moved the IDEA file into it, so this step just writes the plan file alongside:

```text
docs/archive/YYYY-MM-idea-NNN-<slug>/
  ├── IDEA-NNN-<slug>.md             # moved here in step 6
  └── YYYY-MM-DD-<slug>-plan.md      # emitted here in step 7
```

Stage-handoff frontmatter:

```yaml
---
stage: plan
slug: sprint-workflow
created: 2026-04-19
source: ./IDEA-NNN-<slug>.md                # relative to the plan's own dir
status: draft                                # draft | ready | shipped
project: <project-name>
---
```

Print the created path + a one-line summary. Suggest `/work <plan-path>` as the next command.

**Special cases** (skip step 6's move, emit the plan differently):

- The source IDEA file already lives in `docs/archive/<dir>/` — this is a plan revision on work already in-progress or a re-plan after rejection; just emit the new plan into the existing dir. Step 6's move was already done by the original `/plan` run.
- There is no source IDEA file — the plan is a standalone artefact; emit it to a context-appropriate location (often `docs/plans/` as a fallback, which exists only for orphan plans). Step 6 doesn't apply because there's nothing to move.

Commit message for the combined IDEA-move + plan-emit change: `docs(plan): <slug> — draft plan + move IDEA-NNN to in-progress`.

## Right-sizing the artifact

| Scope | Plan structure |
| --- | --- |
| Trivial (typo, one-liner) | Skip the skill entirely — just do the fix |
| Small (bounded, < 30 min, single file) | Context + Scope + Execution Sequence only (~50 lines) |
| Medium (feature with clear boundaries) | All sections, brief (~200 lines). Architect review required. |
| Large (cross-cutting, multi-file, unknown unknowns) | Full plan, phased execution, architect review mandatory, open questions explicit |

The plan's philosophy stays the same at every scope; the depth scales.

## Interaction rules

- **One question at a time.** Never batch unrelated questions into a single message.
- **Prefer single-select** blocking-question tools (`AskUserQuestion` in Claude Code, `request_user_input` in Codex) for direction choices. Multi-select only for compatible sets (constraints, success criteria).
- **Short sections, brief bullets.** The plan is a reference document for executors, not a manifesto.
- **Repo-relative paths everywhere.** Absolute paths break portability across machines, worktrees, and teammates.

## When NOT to use these patterns

- **You're already in `/work`.** Don't re-plan in the middle of execution; update the plan's Open Questions section and handle execution-time unknowns inline.
- **The user wants to capture a new idea, not plan existing work.** Route to `/idea`.
- **The work is one-off and known.** A typo fix does not earn a plan.
- **You're documenting a solved problem.** Route to `/compound`, not `/plan`.

## References

- [assets/plan-template.md](assets/plan-template.md) — the verbatim plan structure the skill emits
- [references/thin-input-bootstrap.md](references/thin-input-bootstrap.md) — the interactive brainstorm front-end for thin inputs
- [references/architect-handoff.md](references/architect-handoff.md) — how to invoke AGENT_architect as a reviewer and integrate findings
- [rules/RULE_ideas-location-status.md](../../rules/RULE_ideas-location-status.md) — the location-by-status contract driving step 7's `idea` → `in-progress` move
- [docs/SPRINT_WORKFLOW.md](../../docs/SPRINT_WORKFLOW.md) — full sprint-workflow explainer with authoritative schemas
- [skills/idea/SKILL.md](../idea/SKILL.md) — previous stage; produces the IDEA file this skill consumes
- [skills/work/SKILL.md](../work/SKILL.md) — next stage; executes the plan this skill emits
- [agents/AGENT_architect.md](../../agents/AGENT_architect.md) — the reviewer persona invoked in step 5

---

**Last Updated**: 2026-04-20 (second revision — plans emit INTO the idea's archive dir, not a separate `docs/plans/` tree; step 7 is now the single-move-then-never-again lifecycle per revised RULE_ideas-location-status)
