---
name: wrap
description: Post-merge documentation sweep — flip idea frontmatter to complete, re-sort the ideas index, append a devlog entry, and scan project docs (guides, reference, README) for references that need updating. Runs between /work's merge moment and /compound's learning-routing stage.
license: MIT
metadata:
  author: mind-vault
  version: '1.0'
---

# wrap

The sprint-workflow step that runs **after the PR merges and before `/compound`**. It closes the loop from code-shipped back to docs-coherent: everything that was "in flight" during `/work` + `/bugbot-loop` and now needs a finalized paper trail.

Catches the class of work that's cheap to forget and expensive to find later — the devlog entry that didn't get written, the idea still marked `status: in-progress`, the README link that now points at a removed env var, the reference doc section that quotes deleted code.

## When to use

**TRIGGER when:** a feature branch has just merged (`gh pr view <N> --json state` → `MERGED`) and the work is not yet routed through `/compound`. Equivalent phrasings the user might use: "mark the IDEA complete and update docs", "close out this sprint's paper trail", "devlog + index sort", "finalize the docs side of the merge".

**SKIP when:** a pre-merge docs change (that's just `/work` with a documentation persona); the merge landed a revert / rollback (no paper trail to create); the work was purely experimental and won't ship to users (no reference docs to re-point).

## Pattern

Six steps in order. Most are guards — skip silently if the state is already correct. The skill is safe to re-run; it produces the same final state regardless of which steps an earlier run completed.

### Step 1 — Resolve the idea

Derive the IDEA-NNN from one of (in order of precedence):

1. An explicit argument (`/wrap 042` or `/wrap IDEA-042-...`).
2. The branch name — `feature/idea-118-...` → `118`.
3. The most recently merged PR on the repo's default branch, by scanning its body for an `IDEA-NNN` token.

Locate the idea file. Per `RULE_ideas-location-status`, it's at `docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md` once `/plan` or `/work` has run; if still in `docs/ideas/`, the `/plan` → archive move was skipped — fire it now (single `git mv` + frontmatter update) before continuing.

Short-circuit: if frontmatter already shows `status: complete`, assume Step 2 has run and skip it. Steps 3–5 are idempotent and should run regardless.

### Step 2 — Flip the idea frontmatter

Per `RULE_ideas-location-status`, frontmatter-edit only — **no file move** (archive dir already exists):

```yaml
status: complete
completed: YYYY-MM-DD   # date the PR merged; gh pr view --json mergedAt
```

Leave `created:` unchanged. If the completed PR superseded or was superseded by another idea, update `superseded_by:` / `supersedes:` too.

### Step 3 — Re-sort the ideas index

Edit `docs/ideas/README.md`:

- Remove the entry from `## 🚧 In Progress`. If that section becomes empty, leave `_(none)_` as its body.
- Insert a new entry at the top of `## ✅ References — Implemented` with this shape:

  ```markdown
  ### IDEA-NNN: <Title> ✅ COMPLETE

  **Status**: ✅ **COMPLETE** · **Completed**: YYYY-MM-DD · **See**: [Archive](../archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md), [PR #<N>](<PR_URL>).
  One to three sentences on what actually shipped (not the plan's aspirational framing — what the merged diff delivered). Cross-reference spinoff IDEAs and related docs.
  ```

- If the idea's frontmatter `related:` points at a complementary idea that also just shipped (batched PR), note it inline in the summary.

### Step 4 — Devlog entry

Locate the current month's devlog: `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md`. If the month just rolled over and the file for the current month doesn't exist yet, create it with the standard header (see any prior month's top lines for the template).

Append a new entry at the **top** of the chronological section (newest first). Template:

```markdown
## YYYY-MM-DD — IDEA-NNN: <Title> (PR #<N>)

**Scope**: One-paragraph what-and-why. Link batched IDEAs if the PR shipped multiple.

### What shipped

- Bullet per material user-facing or infra-facing change. File paths with line refs for hotspots. Code-fence the one-liner when a specific snippet is load-bearing.

### Infrastructure fixes landed in the same PR

- Only if applicable. `/bugbot-loop`-driven scope creep often lands here (pool deadlocks, translator bugs, makefile defaults). Keeping them adjacent to the feature context they surfaced from is more useful than scattering into "chore" entries.

### Related

- [IDEA-NNN archive](…)
- [PR #N](…)
- Companion PRs (dependencies that merged in the same window)
- [Mind-vault compound PR](…) — if `/compound` has already been run, link its PR; else leave this line for `/compound` to append.
```

Use the last two devlog entries in the same file as style anchors — match prose density, heading structure, and linking style. Do **not** cargo-cult the template above verbatim if the project's convention diverges.

### Step 5 — Worktree teardown (conditional)

If the sprint ran in a parallel git worktree with its own docker-compose stack (see [`RULE_parallel-worktree-docker`](../../rules/RULE_parallel-worktree-docker.md)) — the idea-specific `.env`, per-worktree stack with port offset, dedicated compose project — this is the natural moment to tear it down. By the time `/wrap` runs, the PR has merged; the worktree's diagnostic value is spent. Leaving it live holds CPU / RAM / disk hostage and invites port collisions when the next sprint starts.

Skip this step when:

- Running from the primary checkout (no worktree). `git rev-parse --git-common-dir` equals `.git`.
- The user has signalled "keep it up for manual re-testing" (e.g. a `WRAP_KEEP_STACK=1` env var, or an explicit arg `/wrap --keep-stack`).
- The worktree has uncommitted work. Teardown would be safe for docker (volumes are scoped to the worktree's compose project), but a human might still be iterating; refuse and surface `git status` instead.

Teardown sequence, inside the worktree directory:

```bash
# 1. Stop + remove containers + named volumes scoped to this worktree's compose project.
#    -v wipes the per-worktree postgres/redis/minio volumes — safe because the worktree
#    never held production data; the primary checkout's stack is unaffected (different
#    COMPOSE_PROJECT_NAME derived from the worktree dir name).
docker compose down -v

# 2. Leave the worktree directory so `git worktree remove` can take it cleanly.
cd -

# 3. Remove the worktree and its branch (only if merged; `git worktree remove` refuses
#    when there are uncommitted changes — keep that safety).
git worktree remove ../<worktree-dir>
git branch -d <feature-branch>   # -d not -D; safe-merge check remains in force
```

If the project has a teardown wrapper (`tools/sprint-teardown.sh` or similar), prefer that — it's the right place for project-specific cleanup (bucket policies, search index cleanup, seed-data reset).

In `sprint-auto` mode, teardown remains **deferred**: per the sprint-auto skill, worktrees stay up for morning review. The `/wrap` reminder block in the sprint-auto batch summary now includes teardown as a post-review action per IDEA, same list as the frontmatter flip.

### Step 6 — Downstream docs scan

The highest-value and most-skipped step. Everything that referenced the pre-merge state may now be stale. Grep is the workhorse.

For each of: **deleted classes/functions, deleted env vars, renamed models, moved files, removed settings keys, added migrations, new config surface** — run a grep across the project docs tree (`docs/guides/`, `docs/reference/`, `docs/README.md`, top-level `README.md`, `AGENTS.md` / `CLAUDE.md`, and any `.cursor/rules/` equivalents) and list the hits.

Concrete checklist — run each applicable probe, report findings:

- [ ] **Deleted identifier?** `grep -rn <name> docs/` — update references, unlink dead callouts.
- [ ] **New migration touched a public-surface model?** `grep -rn <model> docs/reference/` — update field tables if present.
- [ ] **Env var added / removed?** `grep -rn <VAR_NAME> docs/reference/environment_variables.md` + `.env.template` + any deploy runbook.
- [ ] **Slash-command / make-target added or changed?** `grep -rn 'make <target>' docs/` — update README quick-start, AGENTS, CI/CD runbook.
- [ ] **New top-level module / app?** Check `docs/README.md` feature list and any architecture diagrams.
- [ ] **New settings surface?** `docs/reference/environment_variables.md` and any configuration guide need the knob + default + when-to-change.
- [ ] **Removed settings / defaults flipped?** Same files — deprecate with a clear "As of YYYY-MM-DD, this variable is ignored" note for one release cycle before deletion.

Each finding → either:
- **Patch now** (cheap, obvious — e.g. replace `GOOGLE_CLOUD_STT_KEY` with `nothing; STT removed 2026-04-20`).
- **Flag as follow-up** (larger rewrite — e.g. a reference doc section that needs rewriting for a new architecture) in the PR description or a follow-up IDEA stub.

Commit the documentation edits on the same branch that carries the IDEA-completion commits from Steps 2–4 (or as a fresh `docs/idea-NNN-wrap` branch if the feature branch is already merged into main — matches the `/compound` branch-or-extend decision tree).

## Interaction rules

- **Never skip Step 5** just because it reports zero findings — the grep itself is the value; its output is the audit trail.
- **Never auto-patch architectural docs** (reference `/architecture.md`, high-level guides). Human review required; list findings, let the author decide.
- **In `sprint-auto` mode** (unattended orchestrator): Steps 1–4 run autonomously. Step 5 produces a docs-findings report attached to the auto-run log; the human checkpoint reviews before `/compound`.
- **Don't merge** — every `/wrap` output is on a branch; the human merges it (same HITL gate as `/work`'s feature branch).

## When NOT to use these patterns

- Hotfixes that don't touch a documented surface. A typo fix, a null-guard added to a non-public internal function, a test-only bug — no downstream docs to update, no idea to flip. Skip `/wrap`; go straight to `/compound` if there's a learning worth routing.
- Pre-merge runs. `/wrap` is a post-merge skill; running it against an unmerged PR gives a confusingly partial result (the devlog entry references a PR that hasn't landed, the index says "complete" before the merge lands).

## References

- [`RULE_ideas-location-status`](../../rules/RULE_ideas-location-status.md) — the frontmatter-only transition this skill relies on.
- [`RULE_parallel-worktree-docker`](../../rules/RULE_parallel-worktree-docker.md) — the worktree + compose-project contract Step 5 tears down.
- [`/work`](../../commands/work.md) — the stage before; its output (a merged PR) is `/wrap`'s input.
- [`/compound`](../../commands/compound.md) — the stage after; `/wrap` leaves the paper trail `/compound` references.
- [`/sprint-auto`](../../commands/sprint-auto.md) — the orchestrator that stitches `idea → plan → work → bugbot-loop → wrap → compound` for the unattended case.
