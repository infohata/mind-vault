# Plan-batching for sprint-auto

## When to use

The default `/plan` workflow is one-IDEA-one-PR: each `/plan` invocation creates a feature branch, emits the plan + IDEA archive move + index update, commits, and the user opens its own PR. That's the right shape for solo planning of a single in-flight feature.

**Switch to batching mode when:**

- You're planning **several IDEAs in one session** intending to feed them all to a `/sprint-auto` overnight run.
- The IDEAs are independent enough to plan in one sitting but share a deployment cycle.
- You'd rather review one PR with N plans than N PRs with 1 plan each (faster human-review-then-merge cadence; fewer GitHub notifications; one merge unblocks the entire sprint-auto wave at once).

**Stay with one-plan-one-PR when:**

- Plans are spread across days/weeks (each becomes its own context).
- The IDEAs touch wildly different surfaces and reviewers vary.
- A plan is genuinely large (≥ 800 lines) — it deserves its own PR for review focus.

## Mechanics

```
docs/plans-sprint-batch-YYYY-MM-DD     ← one feature branch
├── commit 1: docs(plan): IDEA-A — draft plan + move IDEA-A to in-progress
├── commit 2: docs(plan): IDEA-B — draft plan + move IDEA-B to in-progress
├── commit 3: docs(plan): IDEA-C — draft plan + move IDEA-C to in-progress
├── commit 4: docs(idea): IDEA-A — flip auto_safe + sensitive_paths_cleared to true
└── commit 5: docs(plan): IDEA-A — apply post-architect refinements
                                                                                
                ↓ one PR review + merge cycle
                                                                                
                ↓ /sprint-auto picks up all eligible IDEAs from docs/archive/
```

Each commit follows the standard `/plan` shape:

1. `mkdir docs/archive/YYYY-MM-idea-NNN-<slug>/`
2. `git mv docs/ideas/IDEA-NNN-<slug>.md docs/archive/<dir>/IDEA-NNN-<slug>.md`
3. Edit IDEA frontmatter: `status: idea` → `status: in-progress`
4. Write the plan file `<dir>/YYYY-MM-DD-<slug>-plan.md`
5. Update `docs/ideas/README.md`: move entry from priority section to "🚧 In Progress"
6. `git add` all four file operations + commit with the canonical message

When all the planning rounds are done (open questions resolved, architect findings integrated, sprint-auto gates flipped), `git push --set-upstream origin docs/plans-sprint-batch-YYYY-MM-DD` and open the PR.

## Sprint-auto sequencing via `depends_on`

When two batched plans modify the **same files**, sprint-auto would dispatch them to parallel worktrees and conflict at merge. The `depends_on:` frontmatter field on the dependent IDEA tells sprint-auto to sequence:

```yaml
# IDEA-128 frontmatter (depends on IDEA-126's SSOT threading)
depends_on: [126]
```

Sprint-auto reads this at dispatch time: IDEA-128 won't be picked up until IDEA-126 has merged to main. After IDEA-126 lands, IDEA-128's worktree branches off the post-merge main and sees the cleaner state without conflicts.

**File-overlap detection during planning** — before opening the batch PR, do a quick mental file-touch matrix:

| IDEA | Files modified |
|------|----------------|
| 124 | chat.html (lines 131-134, 221-231), `_chat.scss`, `_variables.scss` |
| 126 | `attachments.js`, `_attachment_upload_form.html`, `attachment_types.py` |
| 128 | `attachments.js`, `_attachment_upload_form.html` |

Any two rows sharing a file are conflict-prone. Add `depends_on: [<earlier IDEA>]` to the later one. Cheap; one frontmatter edit + a one-paragraph note in the plan's Context section explaining the dependency rationale.

The earlier IDEA gets no change (depends_on is unidirectional). The later IDEA's worktree dispatch waits.

## Generic PR shape

Title: `docs(plans): sprint-auto batch — YYYY-MM-DD`

Body template (additive — append a bullet under "Plans in this batch" for each new plan committed; no rewrites):

```markdown
## Summary

Sprint-auto plan batch for the YYYY-MM-DD overnight run. Each commit
lands a single IDEA's `/plan` output. Reviewing per-commit (rather
than the squashed diff) is recommended.

This PR is intentionally generic — additional IDEA plans can be
appended as further commits before merge.

## Plans in this batch

- **IDEA-NNN** — <title>
  - Plan: <link to plan file>
  - <one-line summary of policy decisions locked + sprint-auto status>

## What changed

For each IDEA: git mv to archive, plan file emitted, README index
updated, sprint-auto gates flipped if /plan + architect resolved the
original blockers.

No code, tests, migrations, or runtime behaviour change in this PR — docs only.

## Test plan

- [ ] Each plan file renders correctly on GitHub
- [ ] Each `git mv` commit preserves blame
- [ ] `docs/ideas/README.md` index reflects the moves (each IDEA in In Progress)
- [ ] No `.po` / `.mo` / migration / settings / view changes leak in
```

## When updating the PR description from this skill

`gh pr edit --body` currently fails with a GraphQL projects-classic deprecation error in some repos. Workaround:

```bash
gh api -X PATCH /repos/<owner>/<repo>/pulls/<N> -f body="$BODY_CONTENT"
```

Or — to avoid HEREDOC-via-env-var awkwardness — write the body to a temp file and pass it via:

```bash
gh pr edit <N> --body-file <tempfile>
```

Both bypass the deprecated `projectCards` field that breaks `gh pr edit --body`.

## Hand-off to sprint-auto

After merge:

1. `/sprint-auto` (in a fresh session — sprint-auto reads from disk, doesn't need the planning context).
2. It discovers all `auto_safe: true` + `sensitive_paths_cleared: true` IDEAs from `docs/archive/*/IDEA-*.md` with plan files present.
3. Dependencies in `depends_on:` arrays are honoured: dependents wait until their dependencies merge.
4. Per-IDEA worktree spin-up runs through `/work → /<engine>-loop → /wrap → /compound`.

Mixed-eligibility batches are fine — IDEAs in the same PR can be flagged sprint-auto-eligible OR human-driven (`auto_safe: false`). Sprint-auto skips the human-driven ones; you `/work` those manually.
