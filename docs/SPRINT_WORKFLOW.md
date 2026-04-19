# Sprint Workflow

Mind-vault's five-stage development loop, inspired by Every Inc's compound-engineering plugin but deliberately tuned for a single-user, cross-project knowledge store.

```text
┌──────┐   ┌──────────────────┐   ┌──────┐   ┌────────┐   ┌──────────┐
│ idea │ → │ brainstorm / plan│ → │ work │ → │ review │ → │ compound │
└──────┘   └──────────────────┘   └──────┘   └────────┘   └──────────┘
    ↑                                                           │
    └───── new atomic idea, or update to existing ──────────────┘
```

Each run of the loop produces durable artifacts in the target project's `docs/` tree. The loop compounds because the final stage — `/compound` — routes learnings back into mind-vault when they generalise, extending skills, rules, and reviewer personas every project thereafter will pick up.

## Philosophy

- **Each unit of engineering work should make the next unit easier.** Traditional development accumulates debt; the compound loop inverts it.
- **Stage skipping is a first-class affordance.** Trivial fixes bypass `/idea` and `/plan` entirely. The loop is a pipeline, not a bureaucracy.
- **Artifacts live in the target project.** Mind-vault is the library; projects are the journal. Mind-vault grows only when `/compound` explicitly promotes a cross-cutting pattern.
- **Review stage is unchanged.** `/bugbot-loop` + the existing review personas stay as-is. What's new is `/compound` reading bugbot's findings file as an input source and routing each cleared finding.

## The five stages

| Stage | Command | Input | Output |
| --- | --- | --- | --- |
| 1. Idea | `/idea [slug]` | Title (new) or slug (update) | `<project>/docs/ideas/IDEA-NNN-<slug>.md` |
| 2. Brainstorm / Plan | `/plan` or `/brainstorm` | IDEA file, or raw description | `<project>/docs/plans/YYYY-MM-DD-<slug>-plan.md` |
| 3. Work | `/work` | Plan file | Code changes on a feature branch |
| 4. Review | `/bugbot-loop` | Open PR | Cleared bugbot findings + loop output file |
| 5. Compound | `/compound` | Solved problem, or bugbot output file | Solution doc OR mind-vault skill/rule/agent/command/memory update |

**Brainstorm folds into plan.** `/brainstorm` is an alias for `/plan`. When the IDEA file is thin or the description is under-specified, the plan skill interactively explores requirements (the brainstorm front-end) before emitting the plan artifact.

## Compound routing (the novel piece)

When you've just solved a problem — or a bugbot-loop finding has been cleared — `/compound` classifies the learning through a hybrid narrative-probe + taxonomy-quiz and writes it to the right destination:

| Shape of learning | Destination | Example |
| --- | --- | --- |
| Project-specific fix with domain detail | `<project>/docs/solutions/<topic>.md` | Webhook HMAC mismatch due to flat-payload edge case |
| Cross-project pattern | mind-vault skill or `references/` file | "Async tenant context loss in Channels → wrap in `with tenant_context(tenant):`" |
| Guardrail-worthy hard rule | `mind-vault/rules/RULE_<name>.md` | "Never hand-edit `.po` files" |
| Reviewer-caught pattern | new pass appended to `agents/AGENT_<persona>.md` | "Dictionary key collisions silently swallow overrides" |
| Tool-worthy repeatable action | `mind-vault/commands/<verb>.md` or `tools/<script>.sh` | Regex sweep for `format_html(_(...))` migration drift |
| User-behavioural preference | auto-memory `feedback_*` / `project_*` / `user_*` / `reference_*` | "Prefer bundled PR over split for this kind of refactor" |

Mind-vault destinations land as commits on the active sprint branch (no new branch if one is in flight — no branch spam), with an open PR maintained by `/compound` itself. If mind-vault is on `main`, the skill creates a fresh `compound/YYYY-MM-DD-<slug>` branch first. `RULE_git-safety` is honoured: the agent never commits to `main`, never force-merges; the human merges the PR.

## Authoritative schemas

These are the canonical frontmatter shapes. Phase 1.5 `/ingest-backlog` and Phase 2 `/ideate` both read this section as the source of truth.

### IDEA file frontmatter

```yaml
---
id: 112
title: Split IDEAS.md into per-idea files
status: idea          # idea | in-progress | complete | superseded
priority: medium      # high | medium | low
supersedes: []        # list of IDEA ids this replaces
superseded_by: null   # scalar id of the replacement, or null
depends_on: []        # list of IDEA ids required before starting
related: []           # list of IDEA ids that share context
created: 2026-04-14   # YYYY-MM-DD
completed: null       # YYYY-MM-DD or null
---

# IDEA-112: Split IDEAS.md into per-idea files

**Problem**: <short paragraph>

**Proposal**: <short paragraph or bullets>

**Why now** / **Non-goals** / **Related** — free-form prose follows.
```

Shape lifted from teisutis IDEA-112 — deliberately small so it maps 1:1 onto a future structured data model without field-name drift.

### Plan and solution frontmatter (stage handoff)

```yaml
---
stage: plan | solution
slug: short-kebab-slug
created: 2026-04-19   # YYYY-MM-DD
source: <path-to-IDEA-file or null>
status: draft | ready | shipped
project: <project-name>
---
```

The `source` field is what makes handoff possible: `/plan` reads an IDEA file and sets `source:` to its path; `/compound` reads a plan or bugbot output and traces back through `source:` chains when documenting the learning.

## Directory layout inside a target project

```text
<project>/
└── docs/
    ├── ideas/
    │   ├── README.md                    # index grouped by priority
    │   ├── IDEA-001-<slug>.md
    │   ├── IDEA-002-<slug>.md
    │   └── ...
    ├── plans/
    │   ├── 2026-04-19-<slug>-plan.md
    │   └── 2026-04-20-<other-slug>-plan.md
    └── solutions/
        ├── async-tenant-context.md
        └── webhook-hmac-edge-cases.md
```

- `docs/ideas/README.md` is the index — one line per IDEA grouped by priority, linking to the per-idea file. Completed ideas stay as footer lines rather than being migrated (forward-only policy from teisutis IDEA-112).
- Plans and solutions use dated slugs so they sort chronologically and never collide.

## Running the loop

Typical invocation on a new feature:

```bash
/idea                      # creates IDEA-NNN-<slug>.md interactively
/plan <slug>               # or /brainstorm <slug> — produces plan doc
/work <plan-path>          # dispatches to personas, commits as it goes
# ... open PR ...
/bugbot-loop <pr-url>      # clears findings
/compound                  # routes what we learned
```

Stage skipping on a trivial fix:

```bash
# no /idea, no /plan — just go
git checkout -b fix/typo
# ... fix ...
# open PR, /bugbot-loop clears it, maybe /compound if you learned something
```

## Right-sizing

| Work shape | Minimum ceremony |
| --- | --- |
| Typo / one-liner | skip idea + plan; do work + review |
| Small bounded fix (< 30 min) | skip idea; plan is optional |
| Feature with unknowns | full loop from idea |
| Cross-cutting refactor | full loop; compound at end is non-optional |
| Post-incident learning | stages 1–3 already done elsewhere; invoke `/compound` directly |

The loop's value scales with the work's ambiguity. Don't force ceremony onto work that doesn't need it.

## References

- [skills/idea/](../skills/idea/SKILL.md) — atomic IDEA file creator / updater
- [skills/plan/](../skills/plan/SKILL.md) — merged brainstorm + plan skill
- [skills/work/](../skills/work/SKILL.md) — thin dispatch orchestrator
- [skills/compound/](../skills/compound/SKILL.md) — the router
- [skills/ingest-backlog/](../skills/ingest-backlog/SKILL.md) — brownfield-takeover helper (Phase 1.5)
- [rules/RULE_git-safety.md](../rules/RULE_git-safety.md) — what `/compound` honours when promoting to mind-vault
- [rules/RULE_parallel-worktree-docker.md](../rules/RULE_parallel-worktree-docker.md) — what `/work` cites for parallel execution

---

**Last Updated**: 2026-04-19
