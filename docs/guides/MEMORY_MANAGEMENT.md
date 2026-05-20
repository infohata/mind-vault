# Memory management

mind-vault works across four layers of persistent context, each with different lifetimes, costs, and right-use cases. Conflating them — putting always-true facts in auto-memory, or pinning ephemeral session state to `CLAUDE.md` — leads to either stale context that misleads or wasted token budget that costs you per session.

## The four layers

| Layer | Loaded when? | Right for | Cost | Example |
| --- | --- | --- | --- | --- |
| **Auto-memory** (`~/.claude/projects/<slug>/memory/`) | Every conversation in that project | Cross-session facts the agent should remember (user preferences, project status, references to external systems) | Permanent context budget per project | "User prefers Daphne-only over Gunicorn+Daphne split" |
| **`CLAUDE.md`** (per-project + global) | Every conversation in the project (project-local) or every conversation everywhere (global `~/.claude/CLAUDE.md`) | Always-true facts: stack, conventions, hard guardrails | Permanent context budget | "Python 3.13, Django 5.2.9, docker compose only" |
| **Skills + rules** (`skills/`, `rules/`) | Rules: every session. Skills: on-demand. | Reusable patterns + always-on guardrails | Rules permanent; skills per-fire | `RULE_git-safety`, `skills/django/` |
| **Project docs** (`docs/`, `README.md`, plan archives) | When the agent reads them | Detailed reference content too large for memory | Per-read | Architecture decisions, IDEA archives, plans |

## When to write where

### Auto-memory — the most often misused layer

Auto-memory is for facts that are **about the user or project** and would help future sessions, but don't fit one of the more structured layers.

✅ **Save to auto-memory**:

- User preferences ("user prefers terminal over IDE for long-running loops")
- Project status that decays slowly ("Phase 2 shipped 2026-04-23, follow-up tracked in IDEA-051")
- References to external systems ("bugs live in Linear project INGEST")
- Feedback that shapes behaviour ("never mock the database in integration tests — prod-divergence incident Q1 2026")

❌ **DON'T save to auto-memory**:

- Code patterns, conventions, architecture — those go in skills or `CLAUDE.md`.
- Git history or who-changed-what — `git log` is authoritative.
- Debugging solutions or fix recipes — the fix is in the code; the PR description holds the why.
- Anything already in `CLAUDE.md`.
- Ephemeral task details: current conversation context, in-progress work, "what we just did".

The agent's global instructions (`~/.claude/CLAUDE.md`) include the canonical auto-memory taxonomy — `user` / `feedback` / `project` / `reference`. Use those four types; resist inventing new ones.

### `CLAUDE.md` — the always-true layer

Per-project `CLAUDE.md` answers: what would I want every new contributor (human or agent) to know about this codebase before they touch a single file?

✅ **Belongs**:

- Stack summary (language, framework, versions, DB, deploy target).
- Conventions (naming, test framework, lint rules, formatter).
- Hard guardrails (`.env` off-limits, never push to `main`, Makefile preference).
- Project-specific commands the agent should prefer (e.g., `make test` over `pytest`).

❌ **Doesn't belong**:

- Tutorials / explainers — that's `docs/`.
- Decisions with rationale — that's an ADR in `docs/`.
- Per-IDEA status — that's the IDEAs index.
- Anything the agent can derive from the code itself.

Global `CLAUDE.md` (`~/.claude/CLAUDE.md`) is for **cross-project** truths: your role, stack expertise, preferences across all your work. Per-project `CLAUDE.md` is for **this project's** truths.

### Skills + rules — the reusable-pattern layer

Covered in [SKILL_AUTHORING_WALKTHROUGH.md](SKILL_AUTHORING_WALKTHROUGH.md). Short version: pattern that recurs across projects → mind-vault skill or rule. Pattern unique to one project → keep it as a project doc.

### Project docs — the reference layer

Architecture decisions, plan archives, runbooks, ADRs. The agent reads these *when asked* — they don't load by default. Lower cost per fact, but discovery depends on naming + linking from `CLAUDE.md` or the README.

## Periodic pruning — what rots and how to spot it

Auto-memory and `CLAUDE.md` both rot over time. Watch for:

| Rot symptom | Source |
| --- | --- |
| Auto-memory references a function/file that no longer exists | Memory was written before a rename or removal |
| `CLAUDE.md` says "Python 3.11" but the project upgraded to 3.13 | Stack drift |
| Memory says "Phase 2 shipped" but Phase 3 also shipped weeks ago | Status fact missed an update |
| Memory references a Slack channel / Linear project that's been archived | External-system reorg |
| Two memory files say contradictory things | Update wrote a new memory instead of editing the existing one |

### Pruning cadence

- **Per `/compound` invocation**: when `/compound` routes a lesson to auto-memory, it scans for related existing memories and updates rather than duplicates.
- **Per sprint wrap**: `/wrap` doesn't currently touch memory (deliberate — `/wrap` is project-scoped, memory is cross-project), but it's a natural moment to ask "did anything I just learned invalidate an old memory?"
- **Quarterly**: open `~/.claude/projects/<slug>/memory/MEMORY.md` and audit. The index is by design <200 lines so a single read covers it. Anything stale → delete or refresh.
- **On major refactor**: if the project just did a big rename or framework upgrade, do a targeted sweep — every memory mentioning the old name is suspect.

### How to verify before acting on a memory

Memory is a *snapshot* of what was true when it was written. Before recommending or relying on a remembered fact:

- If memory names a file path → check the file exists.
- If memory names a function or flag → grep for it.
- If memory describes project status → cross-check `git log` / current IDEA index.

The global `CLAUDE.md` codifies this discipline. The short form: **"the memory says X exists" is not the same as "X exists now"**.

## Memory hygiene anti-patterns

| Anti-pattern | Symptom | Fix |
| --- | --- | --- |
| Inflating auto-memory with what should be in `CLAUDE.md` | Memory bloats, repeats stack facts | Move stack/conventions to project `CLAUDE.md`; keep memory for cross-session deltas |
| Writing a new memory for every conversation | MEMORY.md grows past 200 lines, gets truncated | Audit + dedupe; prefer updating existing memory over creating new |
| Treating memory as a TODO list | "Remember to refactor X" — never actually surfaces | Use IDEA-NNN files; memory isn't a task tracker |
| Saving exact code snippets | Snippet goes stale on next edit; memory now misleads | Save the *pattern* or the *principle*, not the literal code; link to the file |
| Saving secrets to memory | Catastrophic | Never. Same rule as `.env`. |
| Recommending from memory without verifying | Acting on a 6-month-old fact that's no longer true | Always verify before acting (grep, file-exists, git log) |

## When to use `Skill` (a skill) vs memory

Tempting confusion — both persist across sessions. The distinction:

- **Skill** → reusable across projects, shareable, structured, version-controlled. "How to handle Django N+1." "Multi-engine PR review workflow."
- **Memory** → project-local or user-local, narrative, evolves as facts change. "Project status." "User's preference for X over Y."

If the same memory would be true for someone else using mind-vault → it's a skill or rule candidate. If it's about *your* projects or *your* preferences → it's memory.

## Memory and other forms of persistence

A few less-obvious layers worth naming:

- **Plans** (`docs/archive/YYYY-MM-idea-NNN-<slug>/*-plan.md`) — durable record of how an IDEA was decomposed. Don't put plan content in memory; the plan IS the persistent artefact.
- **Tasks** (per-conversation TodoWrite list) — ephemeral, conversation-scoped. Don't persist task lists to memory.
- **Git commit messages** — for the *why* of a change. Don't persist "we changed X because Y" to memory; the commit message holds it.

The right test: would a future session reading the IDEA archive + git log + current `CLAUDE.md` + current memory + current skills be confused, redundant, or contradicted? If contradiction, something needs an update. If redundancy, prune the cheaper layer.

## See also

- Global `~/.claude/CLAUDE.md` — canonical auto-memory taxonomy (`user` / `feedback` / `project` / `reference`) + when-to-save rules.
- [`skills/compound/SKILL.md`](../../skills/compound/SKILL.md) — the lesson-to-destination router (memory is one of six destinations).
- [SKILL_AUTHORING_WALKTHROUGH.md](SKILL_AUTHORING_WALKTHROUGH.md) — when to convert a recurring memory into a skill.
- [`rules/`](../../rules/) — when a recurring memory deserves to be always-on instead.
