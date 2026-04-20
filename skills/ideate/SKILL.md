---
name: ideate
description: Optional entry point above /idea — discover high-impact improvement candidates through divergent ideation across multiple axes (bugs / tech debt / features / refactors / tooling / docs) followed by an adversarial filter that prunes weak candidates. User picks which to capture as atomic IDEA-NNN-<slug>.md files via the existing /idea schema. Phase-2 addition to the mind-vault sprint workflow.
---

# ideate

Optional zeroth stage of the sprint workflow, above `/idea`. Where `/idea` captures **one** specific idea the user already has in mind, `/ideate` **discovers** a set of candidate improvements the user didn't know they wanted yet. Divergent generation followed by adversarial filtering, producing a menu of strong candidates. The user picks which to promote into actual IDEA files via the existing schema.

This skill does not plan, brainstorm requirements, or execute. It surfaces, critiques, and hands off to `/idea` for per-candidate capture. Typical trigger: a user between sprints, or starting on a new project area, asking "what should we tackle?" rather than "how do we build X?".

## When to use

**TRIGGER when:**

- user says "what should we build next", "help me find improvements", "let's ideate", "scan the codebase for issues", "what could we clean up", "what's worth tackling", "surface candidate work", "I'm between sprints"
- user is new to a codebase area and wants a landscape of what to improve
- sprint-end retrospective moment when the next-sprint backlog is empty or thin
- `AGENT_curator`'s sprint-end promotion sweep surfaces multiple compound candidates and the user wants to triage them as a batch

**SKIP when:**

- user already has one specific idea → route to `/idea`
- user has a filled-out IDEA file and wants to flesh it out → route to `/plan` (or `/brainstorm`)
- user wants to execute an existing plan → route to `/work`
- the scope is unclear ("help me think about things") — ask for a bounded area first (a specific app, layer, file-tree scope) before running the scan

## Pattern

### 1. Establish scope

Ideation without a bounded scope produces noise. Before generating candidates, pin down:

- **Project / area.** Whole project, one Django app, one feature surface, the test suite, the docker setup, the docs tree?
- **Timeline.** Candidates for this sprint? Next quarter? "Someday"?
- **Budget.** How many candidates does the user want surfaced — 5? 10? 20? Default to 10.
- **Constraints.** Anything explicitly off-limits (frozen module, legacy app nobody touches)?

Use the platform's blocking question tool (`AskUserQuestion` in Claude Code, `request_user_input` in Codex) for the scope and budget choices. One question at a time.

### 2. Divergent scan

Once scope is set, generate candidates across multiple axes. Do **not** self-censor at this stage — the adversarial filter in step 3 is where weak ideas die. Surface more than you'll ultimately keep.

Axes to walk (pick the applicable subset per scope):

- **Bugs & correctness** — any TODO / FIXME / XXX comments, mentioned-but-not-fixed issues in `docs/solutions/`, areas with low test coverage, known-flaky tests.
- **Tech debt** — files with recent churn (`git log --stat --since='3 months ago'`), N+1 query hotspots, hand-rolled parsers that should use libraries, duplicated code blocks.
- **New features** — user-visible gaps mentioned in recent PRs, commented-out features awaiting re-enable, half-shipped work (`TODO(phase-2)`), integration points that expose value without bespoke UI work.
- **Refactors** — god-object classes, modules that grew from one concern into five, naming collisions, abstractions that leak.
- **Tooling** — repeated manual commands, screen-recording-worthy cognitive tax, missing Makefile targets, setup friction for new contributors.
- **Docs** — stale README, missing ONBOARDING, outdated architecture diagrams, undocumented conventions the user has to keep re-explaining.
- **Observability** — gaps in logging, missing metrics, error swallowing, no alert on known-critical paths.
- **Process** — missing CI checks, test-running friction, PR template gaps.

Capture each candidate with a one-sentence summary, a tentative priority, and a rough dependency signal. Reference [`references/divergent-scan.md`](references/divergent-scan.md) for per-axis prompt fragments, grep recipes, and the canonical "good candidate" shape.

Do not write any files yet. Capture in working memory.

### 3. Adversarial filter

Divergent is easy; convergence is the value. For each candidate, subject it to the adversarial critique in [`references/adversarial-filter.md`](references/adversarial-filter.md). Core challenges:

- **YAGNI probe.** Is this speculative? Who benefits, when?
- **Cost-vs-value.** Rough effort estimate; rough value estimate. Reject anything with effort > value.
- **Prior-art check.** Does `mind-vault/skills/*/` or `<project>/docs/solutions/` already cover this? Drop duplicates.
- **Sharpness.** Is the summary specific enough to act on, or vague ("improve performance")? Drop fuzzy items unless the user wants to keep them as exploration seeds.
- **Dependency awareness.** Does it require another prerequisite idea? Flag as `depends_on:`.

Aim to drop 30–50% of candidates in the filter. If you drop fewer, you were too kind at generation time; if you drop more, you generated noise.

Rank survivors high → low. Present as a compact menu.

### 4. Present the menu

Show the filtered list. For each survivor:

- Priority band (high / medium / low).
- One-line summary.
- Brief rationale (why it survived the filter).
- Rough effort (XS / S / M / L).
- Any `depends_on` pointers to existing IDEAs or other surfaced candidates.

Ask the user which subset to capture as real IDEA files. Accept "all of the high-priority ones", "items 1, 3, 7", or "none, just show me the filter output".

### 5. Promote selected candidates to IDEA files

For each selected candidate, invoke the same emit pattern as `/idea`:

1. Derive the next IDEA-NNN (auto-increment from existing `<project>/docs/ideas/IDEA-*.md`).
2. Slug-derive from the title (kebab-case, stopwords stripped, truncated to ~40 chars).
3. Emit `<project>/docs/ideas/IDEA-NNN-<slug>.md` using [`skills/idea/assets/idea-template.md`](../idea/assets/idea-template.md) — one template across the sprint workflow.
4. Fill the frontmatter from the survivor's fields (priority, depends_on, related).
5. Append the index line to `<project>/docs/ideas/README.md` under the matching priority heading.

When the scan surfaced candidates that reference one another (e.g. idea A depends on idea B that also surfaced), emit them in dependency order and wire the `depends_on:` / `related:` fields correctly.

### 6. Hand off

End with:

- The list of IDEA files created with paths.
- The list of survivors that were NOT promoted (user declined), one-liners only — discarded from working memory, not persisted.
- Suggested next command: `/plan <slug>` for the highest-priority captured IDEA.

## Right-sizing

| Scope | Candidates to generate | Filter target |
| --- | --- | --- |
| Single file / small module | 3–5 | keep 1–3 |
| Single Django app / feature | 8–12 | keep 3–6 |
| Project-wide landscape | 15–25 | keep 6–10 |
| Multi-project / meta | — | hand off to a human retrospective — skill not designed for it |

Generating more than 25 candidates rarely helps; the filter gets overwhelmed and the user's menu selection degrades.

## Interaction rules

- **Bounded scope first.** Refuse to ideate on unbounded inputs. Ask for a specific area.
- **One question at a time** on scoping. Bundle candidate presentation into one message.
- **Divergent phase is silent-or-brief.** Don't narrate every candidate as it's generated; show them all at the filter step.
- **Adversarial filter is transparent.** Show WHY each survivor survived (one-line rationale). Makes the menu reviewable instead of opaque.

## When NOT to use these patterns

- **Scope can't be pinned down.** If the user resists the scoping question ("I don't know what area"), ask them to pick one module or one user complaint to start. The skill refuses unbounded ideation.
- **User already has a shortlist in mind.** If they can list the candidates themselves, skip to `/idea` for each one — the discovery phase is wasted effort.
- **Sprint is in full swing.** This is a between-sprint skill. Running it mid-execution produces churn.
- **The "idea" is actually a known bug.** Bugs go through `/idea` → `/plan` → `/work` → `/compound` like any other work. Don't ideate on a specific reproducible bug.

## References

- [references/divergent-scan.md](references/divergent-scan.md) — per-axis prompt fragments, grep recipes, "good candidate" shape
- [references/adversarial-filter.md](references/adversarial-filter.md) — YAGNI probe, cost-vs-value heuristics, duplicate detection
- [../idea/SKILL.md](../idea/SKILL.md) — the skill that consumes the emit shape this skill produces
- [../idea/assets/idea-template.md](../idea/assets/idea-template.md) — shared template; both `/idea` and `/ideate` write the same schema
- [../compound/SKILL.md](../compound/SKILL.md) — `/compound`'s curator-driven sprint-end promotion sweep can feed candidates back into `/ideate` for the next cycle
- [../../docs/SPRINT_WORKFLOW.md](../../docs/SPRINT_WORKFLOW.md) — full sprint-workflow explainer

---

**Last Updated**: 2026-04-19
