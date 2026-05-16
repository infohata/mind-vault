---
stage: plan
slug: sprint-workflow
created: 2026-04-19
source: null
status: draft
title: "feat: Sprint workflow loop — CE-inspired, compound-routing first"
type: feat
project: mind-vault
branch: ce-inspired-evolution
inspired_by: https://github.com/EveryInc/compound-engineering-plugin
---

## Overview

Introduce a six-stage sprint workflow to mind-vault — `ideate → brainstorm → plan → work → review → compound` — inspired by Every Inc's compound-engineering plugin but deliberately pared down and re-centred on mind-vault's unique advantage: **mind-vault is the cross-project knowledge store, so the compound stage has a richer routing surface than CE's project-local `docs/solutions/` pattern.**

The value driver is not the upstream ceremony (brainstorm, plan) — those are useful, standard. The value driver is a working **compound router**: a skill that, after every solved problem, decides whether the learning is (a) project-local noise, (b) a cross-project pattern worth promoting into a mind-vault skill / rule / agent / command, or (c) a user-behavioural preference for auto-memory. Each correctly-routed learning compounds every future sprint in every project that symlinks this repo.

Ship four new skills and light glue. Do **not** vendor CE code; CE is inspiration only. Keep mind-vault's cross-host portability (symlinks into `~/.claude/`, `~/.config/opencode/`, Cursor, etc.) untouched.

## Problem Frame

Mind-vault today is strong on two fronts:

- **Review:** `AGENT_bugbot`, `AGENT_curator`, `AGENT_architect`, `/bugbot`, `/bugbot-loop` — a mature, opinionated review stack tuned on a multi-tenant Django SaaS.
- **Execution rules:** `RULE_git-safety`, `RULE_parallel-worktree-docker`, `RULE_i18n-workflow` — hard guardrails the agent enforces during work.

Mind-vault is weak on two fronts:

- **Upstream ceremony.** There is no skill that produces a durable requirements or plan artifact. Agents jump from "what do you want?" straight to "let me start editing". Context evaporates between sessions; requirements are re-invented.
- **Downstream learning.** There is no systematic skill that routes a post-incident learning to the right destination. Valuable patterns surface in conversation and either die there, get auto-saved as loose memory, or get dumped into a project's `docs/` directory where other projects never see them. Mind-vault grows by luck, not by ritual.

The second gap is the expensive one. Every un-promoted learning is a cross-project debt: the next project re-hits the same bug, the same reviewer persona misses the same anti-pattern, the same rule isn't codified. CE solves the upstream gap well but routes compound output to a single project-local location — because CE is a product distributed to teams whose private knowledge lives in their repos. Mind-vault's situation is inverted: the user owns the knowledge store, and the routing options are richer.

## Requirements Trace

From the conversation that spawned this plan:

- **R1.** Six-stage workflow: `ideate (optional) → brainstorm → plan → work → review → compound`. Each stage is independently invocable; stages may be skipped when right-sized for the task. The **ideate** stage writes one atomic file per idea — `<project>/docs/ideas/IDEA-NNN-<slug>.md` — with structured YAML frontmatter (`id`, `title`, `status`, `priority`, `supersedes`, `superseded_by`, `depends_on`, `related`, `created`, `completed`) plus the prose body. The shape comes from a meta-idea that surfaced when a real project's `docs/execution/IDEAS.md` had grown past 1500 lines and every edit produced painful reviews — splitting into per-idea files made each addition independently reviewable. Each new idea appends a one-line entry to a lightweight `<project>/docs/ideas/README.md` index grouped by priority. No monolithic `IDEAS.md` — the idea file IS the record.
- **R2.** Stage outputs are markdown artifacts with dated filenames and standard frontmatter, written to the **target project's** `docs/` tree — not into mind-vault itself. Mind-vault is the library; projects are the journal.
- **R3.** Handoff between stages happens via artifact paths. Each stage reads the previous stage's output if supplied, or bootstraps from a raw description.
- **R4.** The compound stage is a **router**, not a writer. It classifies the learning and writes to one of six destinations: project-local solution doc, mind-vault skill update, mind-vault rule update, mind-vault agent-persona update, mind-vault command/tool, or auto-memory entry. Promotions into mind-vault must produce a reviewable diff on the current mind-vault feature branch — never an unattended commit on `main`.
- **R5.** Stages reuse existing mind-vault assets instead of duplicating them. Review delegates to `/bugbot-loop` + `AGENT_bugbot`/`curator`/`architect`. Work enforces `RULE_parallel-worktree-docker` and `RULE_git-safety`. No stage silently supersedes a rule that already exists.
- **R6.** Cross-host portable: skills stay under the mind-vault `skills/` layout (SKILL.md + `references/` + `assets/`) and work through the existing symlink setup for Claude Code, Cursor, OpenCode, Copilot, Antigravity. No host-specific tricks inside SKILL bodies.
- **R7.** No `ce-` prefix collision with the upstream plugin. Naming decision (bare vs. prefixed) is an open question — default to bare unless prefix conflict surfaces.
- **R8.** Branch for this work: `ce-inspired-evolution`. This plan file itself is the first artifact — dogfooding the handoff contract on the plan that proposes it.
- **R9.** A separate **backlog-ingest skill** exists for brownfield takeovers. When the mind-vault user adopts the sprint workflow on a project that already has a monolithic backlog document (`IDEAS.md`, `BACKLOG.md`, `ROADMAP.md`, `TODO.md`, `FEATURES.md`, or a giant GitHub issues export), the skill scans the file, atomises each entry into the `<project>/docs/ideas/IDEA-NNN-<slug>.md` shape from R1, regenerates the index, and leaves completed/archived entries as index footers (not as migrated files). Forward-only, mechanical, one-pass. This is not part of the sprint loop; it is a bootstrap step run once per brownfield adoption.

  **Future-proofing is explicit, not hypothetical.** V1 is validated end-to-end on one real brownfield backlog, but the parser, schema, and CLI must accept arbitrary target files and common alternative shapes so the second brownfield takeover (whenever one appears) does not force a rewrite. Legacy-format recognition lives in `references/legacy-formats.md` and grows by addition, never by special-casing the core skill.

## Scope Boundaries

**In scope (Phase 1):**

- `skills/brainstorm/SKILL.md` — one-question-at-a-time requirements capture; writes `<project>/docs/brainstorms/YYYY-MM-DD-<slug>-requirements.md`.
- `skills/plan/SKILL.md` — consumes a requirements doc or rough idea; writes `<project>/docs/plans/YYYY-MM-DD-<slug>-plan.md`. Invokes `AGENT_architect` as a reviewer pass, not as author.
- `skills/work/SKILL.md` — thin orchestrator; reads a plan, enforces `RULE_parallel-worktree-docker` + `RULE_git-safety`, dispatches to existing personas (`AGENT_backend`, `AGENT_frontend`, `AGENT_devops`, `AGENT_test-engineer`), checks off plan items as commits land.
- **`skills/compound/SKILL.md`** — the router. Classifies a learning; writes to one of six destinations; when destination is mind-vault, stages a diff and prints a review hint (does not auto-commit).
- `commands/compound.md` — `/compound` shortcut invoking the skill.
- `docs/SPRINT_WORKFLOW.md` — the user-facing explainer; links the five skills and the handoff contract.
- README update: add a "Sprint workflow" section with the diagram and promotion-path story.

**In scope (Phase 1.5, separate small PR on the same branch, immediately after Phase 1):**

- `skills/ingest-backlog/SKILL.md` + `references/legacy-formats.md` + `assets/idea-template.md` — brownfield-takeover helper per R9. V1 validated on one real brownfield `docs/execution/IDEAS.md`; parser/CLI accept arbitrary target files and recognised legacy shapes. Runs once per brownfield project. Read-only dry-run mode prints the proposed file tree without writing.

**In scope (Phase 2, gated behind Phase 1 + 1.5 dogfood):**

- `skills/ideate/SKILL.md` — divergent improvement scan with adversarial filter; writes `<project>/docs/ideas/IDEA-NNN-<slug>.md` in the per-file shape defined in R1 (schema already fixed in Phase 1 / consumed by ingest in Phase 1.5), appending a one-line entry to the index. Optional entry point; not needed on routine feature work.
- Extension to `AGENT_curator`: a "sprint-end promotion sweep" pass that scans `<project>/docs/solutions/` for recurring patterns (≥3 occurrences) and proposes a `/compound --promote` invocation.
- Optional `skills/code-review/SKILL.md` thin wrapper that chains bugbot → curator → architect as persona passes for high-stakes diffs. Only if Phase 1 shows `/bugbot-loop` alone is insufficient for multi-persona review.

**Out of scope:**

- Vendoring CE code. No files from `EveryInc/compound-engineering-plugin` are copied into this repo. The influence is structural only.
- Claude Code plugin marketplace packaging (`.claude-plugin/plugin.json` layout). Mind-vault keeps its flat `skills/` + symlink design.
- Multi-provider converter infrastructure (CE's `src/converters/`). Mind-vault symlinks solve this at the filesystem layer.
- Sprint-level ceremony (`/sprint-start`, `/sprint-end`). The sprint emerges from repeated per-feature cycles; curator's periodic sweep is enough.
- Rails/Ruby-flavoured reviewer personas. Mind-vault's review stack is Python/Django tuned and stays that way.
- Auto-commit-to-mind-vault behaviour from `/compound`. Mind-vault PRs stay human-initiated per `RULE_git-safety`.
- Any change to `/bugbot`, `/bugbot-loop`, or the existing `AGENT_*` review personas. Phase 1 only *calls* them; Phase 2 may extend curator.

## Context & Research

### Existing mind-vault assets the workflow leans on

- **`AGENT_architect`** (`agents/AGENT_architect.md`) — 4-pass structural architecture workflow. Consumed by `skills/plan/` as a reviewer pass over draft plans.
- **`AGENT_bugbot`** + **`AGENT_curator`** (`agents/AGENT_bugbot.md`, `agents/AGENT_curator.md`) — the 6-pass pre-commit review personas validated on a multi-tenant Django SaaS. Review stage delegates here unchanged.
- **`AGENT_backend`, `AGENT_frontend`, `AGENT_devops`, `AGENT_test-engineer`** — implementation personas dispatched by `skills/work/`.
- **`RULE_parallel-worktree-docker`** (`../../skills/sprint-auto/references/PARALLEL_WORKTREE_DOCKER.md`) — isolation contract for parallel work streams. `skills/work/` cites it as the prerequisite when the plan flags parallel execution.
- **`RULE_git-safety`** (`rules/RULE_git-safety.md`) — HITL merge gate on `main` / `production`. Governs `skills/compound/`'s mind-vault promotion path (stage files, never commit to main).
- **`RULE_i18n-workflow`** — enforced by `AGENT_backend` when translated strings change; compound promotions must not regress this.
- **Auto-memory system** (`~/.claude/projects/-home-kestas-projects-mind-vault/memory/`) — destination for user-behavioural learnings from `/compound`. Types: `feedback_*`, `project_*`, `user_*`, `reference_*`. Already documented in global `CLAUDE.md`.
- **`skills/skill-writer/`** — the meta-standard used when `/compound` proposes a new skill. Phase-1 `compound` reads this before emitting a skill scaffold.
- **`docs/SKILL_SPECIFICATION.md`** — canonical SKILL.md schema (frontmatter, length budget, references layout). All four new skills conform.

### CE patterns we adopt verbatim

- **Dated-slug artifact naming** (`YYYY-MM-DD-<slug>.md`). Portable, sortable, no ambiguity across projects.
- **Handoff frontmatter** with `stage`, `slug`, `created`, `source`, `status`. Lets any stage pick up cold from another's output.
- **One-question-at-a-time interaction** in brainstorm. CE's `ce-brainstorm` validates this — batched questions produce shallow answers.
- **Plan structure:** problem frame → requirements trace → scope → key decisions → open questions. The shape of this plan file is the proof it works.
- **Right-sizing.** Small work gets a compact artifact or is skipped entirely; large work gets the full stack. No mandatory ceremony.
- **Progressive disclosure** inside skills (SKILL.md under ~500 lines, deep content in `references/`). Already mind-vault's convention via `skill-writer`.

### CE patterns we reject

- **`ce-` prefix on every skill and agent.** Adds noise in a namespace mind-vault controls. Bare names win unless collision forces otherwise.
- **50 agents / 42 skills.** CE ships a catalogue; mind-vault ships a curated toolkit. Five new skills, maximum.
- **Rails/Ruby stylistic reviewers** (`dhh-rails-style`, `andrew-kane-gem-writer`, `dspy-ruby`). Mismatch with Python/Django stack.
- **Single-destination compound.** CE writes to `docs/solutions/` only. Mind-vault's routing is the point of this whole plan.
- **Multi-provider conversion CLI.** Mind-vault's symlinks are the conversion layer.

### Institutional signal from current repo state

- `/bugbot-loop` (`commands/bugbot-loop.md`) already implements a review loop with a bounded-autonomy policy (Option B+). Review-stage orchestration does not need to be reinvented.
- `AGENT_curator` and `AGENT_architect` both carry "Reject the Specific for the Generic" as a prime directive — they are already primed to think about cross-project promotion. Compound routing leans on this mindset.
- The existing memory index (`memory/MEMORY.md`) uses concise one-line pointers to per-topic files. `/compound`'s auto-memory destination reuses this format unchanged.

## Key Technical Decisions

- **Artifacts live in the target project, not mind-vault.** `<project>/docs/brainstorms/`, `<project>/docs/plans/`, `<project>/docs/solutions/`. Mind-vault grows only when `/compound` explicitly promotes. Rationale: mind-vault is a library; projects are journals. Mixing the two pollutes both.
- **`/compound` stages, never commits, mind-vault changes.** When routing to mind-vault, the skill writes the new/updated file(s), writes a one-line index update (e.g. in `MEMORY.md` or the relevant README), prints a concrete review hint (`Review diff on branch <current>, commit when ready`), and stops. Honours `RULE_git-safety` without any special case.
- **Compound routing is an explicit decision tree, surfaced to the user.** The skill asks: "Is this project-specific or cross-cutting? Is it a guardrail, a pattern, a reviewer finding, a tool, or a preference?" and shows the shortlist of destinations with the consequence of each. No silent routing. Rationale: the cost of routing incorrectly (pollution of mind-vault, or buried project knowledge) is higher than the cost of one extra prompt.
- **Stage skipping is a first-class affordance.** Small fixes bypass brainstorm and plan. The workflow doesn't gate `/work` on the existence of a plan artifact; it only reads one if present. Rationale: the six-step shape is the pipeline, not the bureaucracy.
- **Review stage stays as `/bugbot-loop`.** No new skill wrapper in Phase 1. If the experiment shows multi-persona review adds enough value over bugbot alone, Phase 2 adds a thin chainer. Rationale: one additional primitive at a time; don't replace proven infrastructure on day one.
- **Plan stage invokes `AGENT_architect` as reviewer, not author.** The skill drafts the plan; architect reviews it for coupling, scaling, abstraction. Rationale: architect's 4-pass workflow is a review shape, not a generation shape.
- **Work stage is thin.** ~150 lines. Reads the plan, checks off items, dispatches to implementation personas. It does not re-implement their decision logic. Rationale: keep composition cheap; avoid the `ce-work` trap of becoming a mini-orchestrator that re-litigates every decision.
- **Compound's mind-vault promotion staging uses the feature-branch-in-mind-vault that the user is currently on.** If the user is running `/compound` from inside a project worktree (not mind-vault), the skill detects this, computes the mind-vault repo path, confirms with the user, and stages there. If mind-vault is on `main`, refuses and tells the user to create a branch first. Rationale: `RULE_git-safety` is not negotiable; directing the user to the right branch is the skill's job, not the user's.
- **Auto-memory integration routes through the existing memory filesystem, not a new store.** `/compound` writes `memory/feedback_*.md` / `project_*.md` / `user_*.md` files with the canonical frontmatter, appends the one-liner to `MEMORY.md`. Rationale: auto-memory is already a working system; adding a parallel one is waste.
- **Stage artifacts use slug-based filenames chosen by the stage, confirmed by the user.** Prevents collision; allows resume via "is there a recent doc for `<topic>` I should continue?". Rationale: CE's resume-existing-work pattern is load-bearing for iterative sprints.
- **No bun/npm/typescript dependency.** Anything that needs scripting uses bash or Python (mind-vault's existing convention). Rationale: user's stack, and scripts stay portable across the symlinked hosts.

## Open Questions

These are the decisions we'll tune before executing Phase 1. Each has a suggested default but is explicitly tunable.

### Q1. Naming — bare vs. prefixed?

**Default:** bare (`/brainstorm`, `/plan`, `/work`, `/compound`).
**Alternative:** prefixed (`/mv-brainstorm`, `/sp-plan`, etc.) to namespace against any future marketplace plugin a user might install.
**Trade-off:** bare reads better and matches mind-vault's current flat commands. Prefixed future-proofs against collision if the user ever installs CE or similar plugins into the same Claude Code instance.

### Q2. Artifact location for brainstorm / plan — confirmed target-project-local?

**Default:** `<target_project>/docs/{brainstorms,plans,solutions}/`.
**Alternative:** optional `mind-vault/docs/journal/<project>/` for cross-project work that doesn't belong to any one project.
**Trade-off:** target-project-local is clean separation; journal-in-mind-vault is useful when the work is about mind-vault itself (as this plan is), and would need a convention for which bucket to pick. Current plan lives in `mind-vault/docs/plans/` because this IS mind-vault work — that precedent is probably the right rule: if the target repo is mind-vault, write there; else write in the target.

### Q3. `/compound` autonomy on mind-vault promotions — stage-only, or stage + auto-branch?

**Default:** stage-only. Skill writes files on the current branch, prints "commit when ready".
**Alternative:** if mind-vault is on `main`, skill auto-creates a `compound/<slug>-<date>` branch and switches to it before staging.
**Trade-off:** stage-only is the safest `RULE_git-safety` posture. Auto-branching is more ergonomic but creates branches the user didn't explicitly ask for. Lean stage-only; revisit if the friction becomes real.

### Q4. Review stage — keep `/bugbot-loop` or build a thin chainer?

**Default:** keep `/bugbot-loop` as-is in Phase 1. Add a chainer only if Phase-1 sprints reveal multi-persona review (bugbot → curator → architect) adds enough over bugbot alone to justify a new skill.
**Alternative:** build `skills/code-review/` now as a thin wrapper that chains the three personas.
**Trade-off:** default avoids premature abstraction; alternative gets the full CE-style review pipeline sooner.

### Q5. Ideate — Phase 1 or Phase 2?

**Default:** Phase 2. The six-step loop works without it; divergent ideation is a different mode (asking "what could we do?" vs. "how should we do this?") that only lights up when the user is between sprints looking for the next direction.
**Alternative:** Phase 1. Build all six at once.
**Trade-off:** deferring keeps Phase 1 small (4 skills instead of 5) and tests the four-stage happy path before adding divergent ideation. Building all six at once ships the whole shape and lets the user pick cycles that include/exclude ideate.

### Q5b. Ingest-backlog — Phase 1, Phase 1.5, or Phase 2?

**Resolved → Phase 1.5.** A real-project brownfield-backlog split executes downstream of this mind-vault work, most likely the day after mind-vault Phase 1 lands. The ingest skill is the execution vehicle for that split — not a nice-to-have follow-up. Placing it in Phase 2 would block the brownfield consumer; placing it in Phase 1 would bloat the first PR with a skill that isn't needed for ordinary per-feature cycles. Phase 1.5 (a second small PR on the same branch, landing immediately after Phase 1) is the right slot: it means the target-shape decision in Phase 1 fixes the schema once, then ingest reuses it without waiting on ideate.

**Implication for Phase 1:** the `docs/ideas/IDEA-NNN-<slug>.md` frontmatter schema must be fixed and documented during Phase 1 (not deferred into ideate), because ingest in Phase 1.5 depends on it. The schema lives in `docs/SPRINT_WORKFLOW.md` as authoritative — ideate (Phase 2) and ingest (Phase 1.5) both consume it.

### Q6. The compound router — questionnaire shape?

Three candidate shapes for the router's decision tree:

- **Shape A — Explicit taxonomy quiz:** the skill presents the six destinations as a numbered list with one-sentence descriptions of each; user picks.
- **Shape B — Narrative probe:** skill asks two or three questions ("is this project-specific or likely to recur in other projects?" → "is this a pattern, a guardrail, a reviewer finding, a tool, or a preference?") and computes the routing.
- **Shape C — Hybrid:** narrative probe first; if confident, propose one destination and ask to confirm; if ambiguous, fall back to explicit taxonomy quiz.

**Default:** Shape C. Best case is zero friction; worst case is one extra prompt.

### Q7. How does `/compound` verify its learning actually lands?

A promotion only compounds if the next invocation in the relevant context actually picks up the new skill/rule/agent. Options:

- **Option 1:** `/compound` prints a manual verification command (`grep -r <new-pattern> ~/.claude/skills/`) and trusts the user.
- **Option 2:** `/compound` runs the verification itself post-promotion.
- **Option 3:** Defer. Verification is a Phase-2 concern once Phase-1 promotions are happening in practice.

**Default:** Option 3. Don't over-engineer the first version.

## Proposed Execution Sequence (once tuned)

Phase 1 (single PR, ~2–3 working days of curation/authoring):

1. `skills/brainstorm/SKILL.md` + `skills/brainstorm/assets/requirements-template.md` + `skills/brainstorm/references/interaction-patterns.md`.
2. `skills/plan/SKILL.md` + `skills/plan/assets/plan-template.md` + `skills/plan/references/architect-handoff.md`.
3. `skills/work/SKILL.md` + `skills/work/references/persona-dispatch.md`.
4. `skills/compound/SKILL.md` + `skills/compound/references/routing-decision-tree.md` + `skills/compound/references/mind-vault-promotion.md` + `skills/compound/assets/solution-template.md` + `skills/compound/assets/skill-scaffold-template.md`.
5. `commands/compound.md` (slash-command pointer).
6. `docs/SPRINT_WORKFLOW.md` (user-facing explainer with the six-stage diagram + promotion-path story + **the authoritative `docs/ideas/IDEA-NNN-<slug>.md` frontmatter schema** so Phase 1.5 ingest has a fixed target).
7. README update: new "Sprint workflow" section.
8. Register the four new skills in the setup scripts' target lists (`scripts/setup-*-symlinks.sh`) — zero change expected since the symlink pattern is `skills/*/SKILL.md` already.

Phase 1.5 (separate small PR, same branch, lands immediately after Phase 1 — unblocks brownfield consumer):

- `skills/ingest-backlog/SKILL.md` + `skills/ingest-backlog/references/legacy-formats.md` + `skills/ingest-backlog/assets/idea-template.md`.
- Dry-run mode flag + destructive-write mode flag — default dry-run.
- Validate end-to-end against a real `docs/execution/IDEAS.md` source before merging. Execute the actual split from the consuming project's worktree once the skill is in place.

Phase 2 (follow-up branch, decided after Phase 1 + 1.5 dogfood):

- `skills/ideate/SKILL.md` (per-idea-file output matching the schema fixed in Phase 1).
- `AGENT_curator` "sprint-end promotion sweep" pass extension.
- Optional `skills/code-review/SKILL.md` chainer (only if multi-persona review need is proven).

---

**Status:** draft — tune Q1–Q7 with the user before writing any skill code. This plan file is itself the first dogfood of the handoff contract: a later `/plan` invocation against this file should pick it up via the `stage: plan` frontmatter.
