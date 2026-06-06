---
name: wrap
description: Documentation finalization sweep — flip idea frontmatter to complete, re-sort the ideas index, append a devlog entry, surface a version-bump consideration for versioned projects (any version source: VERSION / pyproject.toml / package.json / Cargo.toml / setup.py / versioned CHANGELOG), scan project docs (guides, reference, README) for references that need updating — including a staleness-gated whole-README currency audit (Step 6b) that backfills version framing / counts / feature-table / stale-flag drift the per-IDEA scan misses — and (conditionally) emit a manual-evaluation checklist for IDEAs that opted into the eval-gate mode. Runs PRE-merge on the feature branch, BEFORE the single `/review-loop` pass (wrap-before-review), so the reviewer sees docs at their merged shape; post-merge fallback handles PRs that shipped without a wrap. **`/wrap` never merges** — merge + teardown are the separate `/land` stage (split out in IDEA-015). Two live scopes: `docs` (default, full doc finalization) and `--scope=idea-only` (sprint-auto S5 subset — frontmatter + downstream-docs + eval-checklist only; devlog + ideas-index + version-bump deferred to sprint-auto's batch wrap so the whole sprint ships as ONE versioned release, eliminating the N-way devlog/index line-conflict every parallel /wrap would produce). `--scope=full` is a **deprecated** shim: it finalizes docs then prints guidance to run `/land` (it never merges).
license: Apache-2.0
metadata:
  author: mind-vault
  version: '1.0'
---

# wrap

The sprint-workflow step that closes the loop from code-shipped back to docs-coherent — everything that was "in flight" during `/work` + `/<engine>-loop` and now needs a finalized paper trail. Catches the class of work that's cheap to forget and expensive to find later — the devlog entry that didn't get written, the idea still marked `status: in-progress`, the README link that now points at a removed env var, the reference doc section that quotes deleted code.

**Runs pre-merge.** The wrap commits (frontmatter flip, ideas-index move, devlog entry, downstream docs fixes) land on the feature branch, so the PR carries the final docs state into merge in one shot. No follow-up PR, no stale-on-main window between merge and wrap. The "what if the PR doesn't merge?" concern is a non-concern: unmerged commits never reach main, so no stale state can exist — if the branch is closed, the docs commits evaporate with it.

**`/wrap` finalizes docs; it never merges.** A `/wrap NNN` runs the doc-finalization steps and stops — the safe behaviour the wrap-before-review pass wants: finalize docs, then let the single `/review-loop` review them at shipped state, then `/land NNN` merges. Merge + teardown are the separate **`/land`** stage (split out in IDEA-015), which opens with a precondition guard verifying this wrap ran. This replaces the older "`/wrap --scope=full` auto-merges" model.

**`--scope=full` is deprecated.** Invoking `/wrap --scope=full NNN` emits a one-time deprecation notice, runs the `docs` doc-finalization steps, and at the end — where the old Step 8 atomic merge used to fire — prints the canonical next steps (run the single `/review-loop` over the wrapped PR, then `/land NNN`) and **"this did NOT merge (it did under the old `--scope=full`)"**. It never merges, and it never skips the review — `/land` is the merge. See [`Scope detection`](#scope-detection-alongside-mode-detection).

**Post-merge is the fallback.** If a PR landed without a wrap pass (human merged directly, wrap was forgotten, a hotfix went in on the fly), invoking `/wrap NNN` after the fact creates a small `docs/idea-NNN-wrap` branch with the same doc outputs and opens a cleanup PR. The skill auto-detects PR state (`gh pr view <N> --json state`) and branches accordingly. **The post-merge fallback does docs only — it does not tear down.** If a parallel worktree still needs reclaiming, its hand-back points at `/land NNN` (post-merge teardown mode).

**`--scope=idea-only` mode (v3.1 sprint-auto)** narrows the wrap to per-IDEA-local work (frontmatter flip + downstream-docs scan); skips ideas-index re-sort and devlog entry append. Used at sprint-auto's S5 to defer those batch-wide writes to S11.7's batch wrap on the integration branch — eliminates the N-way line-conflict that every parallel `/wrap` would otherwise produce on `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md` and `docs/ideas/README.md`. Outside sprint-auto, the flag has no effect (the conflict only arises with parallel branches).

## When to use

**TRIGGER when:**

- A feature branch's deliverables are committed and the PR is about to enter review — finalize docs first (pre-merge default).
- **A doc-heavy / IDEA PR is about to enter `/review-loop`** — run me (bare `/wrap`, `--scope=docs` default) BEFORE the single review, so the engines review docs at shipped state. `/wrap` never merges; merge is the separate `/land` stage after review clears. This is the manual-path mirror of what sprint-auto sequences. Mechanics: [`references/WRAP_BEFORE_REVIEW.md`](references/WRAP_BEFORE_REVIEW.md).
- Sprint-auto reaches its S5 step — wrap runs (`--scope=idea-only`) before the single S6 review pass.
- A PR merged without a wrap (post-merge fallback) and the ideas index / devlog / frontmatter are stale on main.
- Phrasings the user might use: "mark the IDEA complete and update docs", "close out this sprint's paper trail", "devlog + index sort", "finalize the docs side of the merge", "sort the docs before merging".

**SKIP when:**

- The merge landed a revert / rollback (no paper trail to create).
- The work was purely experimental and won't ship to users (no reference docs to re-point).
- Hotfixes that don't touch a documented surface (typo fix, null-guard on internal function, test-only bug) — skip and go straight to `/compound` if there's a learning worth routing.

## Pattern

Eight steps in order (6 numbered — 1, 2, 3, 4, 6, 7 — plus Step 4b version-bump + Step 6b README-currency audit, both conditional sub-steps). Several are conditional: Step 4b fires only when a version source is detected, Step 6b fires on a staleness threshold (skipped under `idea-only`), Step 7 (eval-gate emission) gates on IDEA frontmatter. Most steps are guards — skip silently if the state is already correct. The skill is safe to re-run; it produces the same final state regardless of which steps an earlier run completed. (Merge + teardown are NOT wrap steps — the old Step 5 teardown and Step 8 atomic merge moved to `/land` in IDEA-015.)

### Scope detection (alongside mode detection)

Before any step, parse the `--scope` flag. Two live values — **`docs` is the default** (no flag → `docs`) — plus the deprecated `full` shim:

```bash
SCOPE=docs                       # docs (default) | idea-only
DEPRECATED_FULL=0
for arg in "$@"; do
    case "$arg" in
        --scope=docs)                 SCOPE=docs ;;
        --scope=idea-only|--no-batch-writes) SCOPE=idea-only ;;
        --scope=full)                 SCOPE=docs; DEPRECATED_FULL=1 ;;  # deprecated → runs docs, redirects to /land
    esac
done
```

**`--scope=full` is deprecated — it no longer merges** (merge moved to `/land`, IDEA-015). When `DEPRECATED_FULL=1`, run the `docs` steps normally, then at hand-back emit the loud notice:

> ⚠️ `--scope=full` is deprecated and **did NOT merge** (it did under the old model). Docs are finalized; run the single **`/review-loop`** over the wrapped PR, then **`/land NNN`** to merge + tear down.

**Why `docs` is the default.** A `/wrap NNN` finalizes docs and stops — it never merges. Merge is the separate, explicit `/land` stage (the destructive step that ships the IDEA and unblocks teardown), run after the single `/review-loop` clears. This makes the wrap-before-review pass a single clean invocation: `/wrap` before `/review-loop`, then `/land`. See [`references/WRAP_BEFORE_REVIEW.md`](references/WRAP_BEFORE_REVIEW.md).

Per-scope step-set (the canonical table — each value names a coherent step subset):

| Step | `docs` (default) | `idea-only` (sprint-auto S5) |
| --- | --- | --- |
| 1 Resolve idea | RUN | RUN |
| 2 Frontmatter flip (+ body status sub-step) | RUN | RUN |
| 3 Re-sort ideas index | RUN | **SKIP** — deferred to sprint-auto S11.7 batch wrap |
| 4 Devlog entry | RUN | **SKIP** — deferred to S11.7 |
| 4b Version-bump | conditional | **SKIP** — sprint-level, deferred to batch wrap |
| 6 Downstream-docs scan | RUN | RUN |
| 6b README currency audit | conditional (staleness-gated) | **SKIP** — cohort audit deferred to sprint-auto S11.7 batch wrap |
| 7 Eval-gate emission | conditional (pre-merge + frontmatter) | conditional |

**Merge + teardown are no longer wrap steps.** The old Step 5 (worktree teardown) and Step 8 (atomic merge) moved to `/land` (its Teardown and Atomic-merge sections). `/wrap` — at any scope, any mode — never merges and never tears down.

- **`docs` runs Steps 3 + 4** (ideas-index + devlog), so it is **NOT safe for parallel-branch invocations** — N concurrent `docs` wraps would re-introduce the exact N-way line-conflict on `DEVELOPMENT_LOG.md` / `ideas/README.md` that `idea-only` was designed to avoid. Manual `docs` wraps run one-at-a-time (human-directed); never wire `docs` into an automated multi-branch context — that's what `idea-only` is for.

`idea-only` is the sprint-auto S5 scope (parallel per-IDEA branches): it skips Steps 3/4/4b/6b to keep batch-wide writes on the integration branch. `docs` ⊋ `idea-only` on the doc steps (adds 3/4/4b/6b).

### Mode detection (first action each invocation)

Before anything else, determine which mode is running — pre-merge default, post-merge docs fallback, or self-mode. The decision drives which branch the wrap commits land on. (Batch teardown — `/land --integration` — and merge/teardown generally are no longer wrap's job; they live in `/land`.)

```bash
# 1. Is this mind-vault itself?
git remote get-url origin | grep -q mind-vault && MODE=self

# 2. Otherwise, what's the PR state for the current branch's open PR, or for
#    the explicit PR number passed as arg?
[ -n "$MODE" ] || gh pr view "${PR_OR_BRANCH}" --json state,headRefName --jq '.state'
#   OPEN    → pre-merge default: commit the doc steps onto the current feature branch
#   MERGED  → post-merge docs fallback: `git checkout -b docs/idea-NNN-wrap origin/main`
#             before committing. Docs only — NO teardown (if a worktree still needs
#             reclaiming, the hand-back points at `/land NNN`).
#   CLOSED  → refuse: the branch was abandoned; no wrap to do
```

If no PR exists yet (branch pushed but PR not opened), treat as pre-merge default and commit onto the current branch — the PR can be opened later and will carry the wrap commits.

### Self-mode: running on mind-vault itself

Mind-vault **dogfoods its own sprint workflow** — it tracks its own IDEAs in `docs/ideas/` + `docs/archive/YYYY-MM-idea-NNN-<slug>/` and maintains `docs/ideas/README.md`, exactly like any project it serves. So when a mind-vault wrap maps to a mind-vault IDEA, **Steps 1–3 (IDEA resolve, frontmatter flip, ideas-index re-sort) DO apply** — run them normally. Skip Steps 1–3 only when the PR has **no associated IDEA** (a pure `/compound`, chore, or tooling PR) — and that's the universal "no IDEA → nothing to flip" rule, not anything special to mind-vault.

The **only** self-mode specialization is **Step 4**: the chronological log is `CHANGELOG.md` at the repo root (Keep-a-Changelog + `## v<N>` version sections), NOT the per-project `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md`.

Detection: `git remote get-url origin` → URL contains `mind-vault`. (Do NOT use "absence of `docs/ideas/README.md`" as a signature — mind-vault has one.)

In self-mode, Step 4 targets `CHANGELOG.md` at the repo root (not `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md`, which is the per-project convention). **End-to-end maintenance is the wrap's job** — not split between "add to Unreleased pre-merge" and "promote to dated section manually later":

**Preamble — know your PR set.** Before editing, run `gh pr list --state merged --base main --limit 20 --json number,title,mergedAt` (mind-vault uses squash-merge; `git log --merges` alone would miss them) and `gh pr list --state open --base main --json number,title`. The merged list + the just-merged PR determine which Unreleased bullets are eligible to promote; the open list determines which stay. Cross-reference both against existing CHANGELOG bullet PR-links.

1. **Promote, selectively** — move bullets from `## Unreleased` into the current `## YYYY-MM` section **only when the bullet's PR is merged**. Leave bullets for still-open PRs in Unreleased (this is why they were parked there pre-merge). Place promoted bullets above any existing entries in the month (reverse-chronological within the month). Append `(YYYY-MM-DD, [#N](https://github.com/infohata/mind-vault/pull/N))` to each promoted bullet's tail if the date/PR-link aren't already there.
2. **Add** any new entries for the just-merged PR directly into the dated section (not Unreleased) if they weren't added pre-merge. Category keys follow Keep a Changelog: **Added / Changed / Fixed / Removed / Deprecated / Security**. See the existing entries for prose-density anchors.
3. **Reconcile Unreleased**: after Step 1, `## Unreleased` should contain only bullets for still-open PRs (per the preamble's open list). If there are none, reset to `(none)`. If the bullets that remain don't match the current open-PR list, something drifted — surface in the hand-back rather than auto-delete.
4. **Backfill-gap detection**: using the merged-PR list from the preamble, identify any merged PRs without matching CHANGELOG bullets. Judgement call: if the gap is ≤3 PRs, backfill them in this wrap. If larger, surface the gap in the wrap's hand-back message (`"CHANGELOG is missing entries for PRs #N1-#N2 (M PRs). Shall I backfill in this wrap PR or open a separate chore PR?"`) and wait for direction.

The point: after wrap, `Unreleased` reflects only actually-open PRs, the dated section is current, and no human intervention is needed to "catch up" the log.

Self-mode's CHANGELOG handling is one application of the project-agnostic Step 4b below — see that step for the version-bump consideration that applies here too (mind-vault uses CHANGELOG with `## v<N>` headers as its version source).

The load-bearing self-mode work is Step 6: catch `README.md` / `docs/guides/SPRINT_WORKFLOW.md` / `tools/README.md` / `AGENTS.md` / `CLAUDE.md` drift from newly-added skills, commands, rules, or agent passes. That is what `/wrap` is *for* on mind-vault — the paper trail of its own evolution, alongside the changelog.

### Step 1 — Resolve the idea

Derive the IDEA-NNN from one of (in order of precedence):

1. An explicit argument (`/wrap 042` or `/wrap IDEA-042-...`).
2. The branch name — `feature/idea-118-...` → `118`.
3. The most recently merged PR on the repo's default branch, by scanning its body for an `IDEA-NNN` token.

Locate the idea file. Per `RULE_ideas-location-status`, it's at `docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md` once `/plan` or `/work` has run; if still in `docs/ideas/`, the `/plan` → archive move was skipped — fire it now (single `git mv` + frontmatter update) before continuing.

Short-circuit: if frontmatter already shows `status: complete`, skip the frontmatter flip — but still run the body-prose status-line sub-step below (it's idempotent and catches a pre-existing frontmatter↔body mismatch the flip-skip would otherwise leave). Steps 3–5 are idempotent and should run regardless.

### Step 2 — Flip the idea frontmatter

**Pre-condition — IDEA completeness audit.** Before flipping `status: in-progress` → `complete`, walk the plan's acceptance criteria one by one and confirm each is satisfied by the merged code at PR HEAD. Any unmet criterion BLOCKS the flip — either ship the missing work on the same PR, or keep `status: in-progress` and document the pending piece with the ⚠️ marker in every wrap output (devlog entry, ideas-index entry, hand-back report). Phase-shipped IDEAs (multiple PRs over time) use `phase_N_completed:` plus `completed:` to track both phase boundaries and final close-out. Full audit procedure + a worked premature-wrap precedent (status flipped despite a later-phase criterion unmet, surfaced at /compound time) live in [`references/IDEA_COMPLETENESS_AUDIT.md`](references/IDEA_COMPLETENESS_AUDIT.md). Read that reference when this step fires for any IDEA whose plan documented multiple phases or whose acceptance criteria might not all be shipped on this PR.

Per `RULE_ideas-location-status`, edit the frontmatter in place — **no file move** (archive dir already exists); the body-prose status line is synced in the mandatory sub-step below:

```yaml
status: complete
completed: YYYY-MM-DD
```

**`completed:` date source** depends on mode:

- **Pre-merge default**: use today's date (the day the wrap is running and the PR is about to merge). If merge slips by a day, the date is off by one — tolerable, and still better than waiting for merge to write the date. The `related:` field may also gain entries here if the wrap sweep reveals sibling IDEAs.
- **Post-merge fallback**: use `gh pr view <N> --json mergedAt --jq '.mergedAt | split("T")[0]'` to get the real merge date.

Leave `created:` unchanged. If the completed PR superseded or was superseded by another idea, update `superseded_by:` / `supersedes:` too.

**Mandatory sub-step — sync the body-prose status line.** The frontmatter flip isn't the whole job: IDEA files (and many plan/README docs) carry a *second*, human-readable `**Status**: 🚧 In Progress` prose line. After editing frontmatter, grep the same file (and sibling plan/index docs) for a `**Status**:` / `Status:` line and sync it (`✅ Complete (YYYY-MM-DD)`). Skipping this leaves a frontmatter↔body mismatch a doc-reviewing engine **will** flag — a self-inflicted finding. Zero review cost. See [`references/WRAP_BEFORE_REVIEW.md`](references/WRAP_BEFORE_REVIEW.md).

### Step 3 — Re-sort the ideas index

Edit `docs/ideas/README.md`:

**Idempotency guard (run first).** `/wrap` is safe to re-run (re-invoked after a review cycle touches docs, or as a post-merge fallback), so guard against double-insert: `grep -q "^### IDEA-NNN:" docs/ideas/README.md` — if the heading already sits under `## ✅ References — Implemented`, this step already ran; skip the insert (but still remove any lingering `## 🚧 In Progress` entry). Without the guard, a re-run inserts a duplicate Implemented entry.

- Remove the entry from `## 🚧 In Progress`. If that section becomes empty, leave `_(none)_` as its body.
- **Remove the originating breadcrumb from the old priority tier too.** When `/plan` moved the idea into In Progress it often left a stub in its former priority section — `_(IDEA-NNN moved to In Progress above — /plan …)_` or similar. Grep `grep -n "IDEA-NNN" docs/ideas/README.md` and delete that breadcrumb; if removing it empties a priority tier, leave `_(none)_` as its body (matching the In Progress handling above) — never drop the tier header, the index keeps the full tier skeleton. Skipping this is silent rot: the markers accumulate and falsely read as active backlog (a sprint can amass a dozen stale "moved to In Progress" stubs before anyone notices). Zero-cost to clear at wrap time.
- Insert a new entry at the top of `## ✅ References — Implemented` with this shape:

  ```markdown
  ### IDEA-NNN: <Title> ✅ COMPLETE

  **Status**: ✅ **COMPLETE** · **Completed**: YYYY-MM-DD · **See**: [Archive](../archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md), [PR #<N>](<PR_URL>).
  One to three sentences on what actually shipped (not the plan's aspirational framing — what the merged diff delivered). Cross-reference spinoff IDEAs and related docs.
  ```

- If the idea's frontmatter `related:` points at a complementary idea that also just shipped (batched PR), note it inline in the summary.

#### Decisions Recap section — for multi-IDEA cohorts

When the project is running a multi-IDEA cohort (sprint-auto batch, named sprint branch with N feature-branch PRs targeting it, or any case where the human is going to navigate ≥10 IDEAs that share a context), maintain a **Decisions Recap** section at the top of `docs/ideas/README.md`. Living index that solves the "re-reading 25 plan docs to remember what was decided" problem.

**Placement** — between `## 🚧 In Progress` and `## 💡 High Priority`. Make it the first thing a future agent or human sees when picking up sprint work.

**Shape** (compact, ~50 lines):

```markdown
## 🧭 <Sprint name> — Decisions Recap

Living recap of the N-IDEA `<sprint-branch>` cohort (NNN→NNN). Read this first when picking up sprint work — it indexes status + key decisions so a fresh session doesn't have to re-read every plan. Updated by `/plan` and `/wrap` as IDEAs progress.

**Sprint progress**

| # | Title (short) | Status | Key decision committed |
|---|---|---|---|
| NNN | … | ✅ complete | one-line key decision |
| NNN | … | 🚧 in-progress | _(see decisions M–N below)_ |
| NNN | … | 💡 idea | — |
| … | … | … | … |

**Major architectural decisions (cross-cutting; amended as the sprint progresses)**

1. **<Decision name>** — one-paragraph resolution. Source: link to the artefact / IDEA where it was locked. _Decided IDEA-NNN; amended IDEA-NNN._
2. …

**Per-topic source-of-truth artefacts** (read for depth)

- [`<artefact-1>.md`](…) — covers decisions N, M.
- [`<artefact-2>.md`](…) — covers decisions K.
```

**Maintenance contract**:

- `/plan` for a new IDEA in the cohort: append a row to the sprint-progress table; flip status to 🚧 when the IDEA enters in-progress.
- `/wrap` for a completing IDEA: flip its row to ✅ with a one-line key decision; if any new cross-cutting decision was locked, append a numbered row to the architectural decisions block.
- The recap **never duplicates** the per-topic artefacts — it indexes them. Each decision row points at the artefact where the full reasoning lives.

**When to skip**: cohort < ~10 IDEAs, or the IDEAs don't share enough context that re-reading their plans is expensive (typical for opportunistic backlog clearing). The recap pays off when there's a coherent sprint where late-cohort IDEAs need to know what early-cohort IDEAs decided.

**Genesis**: introduced in 2026-05 during a 25-IDEA `sprint/ux-overhaul` cohort — the context cost of re-reading 25 plan docs to remember decisions had crossed a pain threshold. A small `auto-memory` reference entry pointing at the recap location makes the pattern survive across agent sessions.

### Step 4 — Devlog entry

**First, resolve the target file for the NEW entry (month-rollover check).** Compute today's `YYYY-MM`. If `docs/archive/<YYYY-MM>-DEVELOPMENT_LOG.md` doesn't exist yet (first write of the month), create it with the standard header — see any prior month's top lines for the template. **The just-merged PR's entry goes in *today's month* file**, even if the PR's own merge timestamp is right at a month boundary; the chronological log is indexed by when the entry is authored, not when the underlying work shipped minutes earlier. Backfill (Step 2) handles its own per-missed-PR file targeting separately from this.

**Maintain end-to-end** — the same discipline that applies to CHANGELOG in self-mode applies here. Once the target file for the new entry is resolved, the wrap's responsibility for the monthly devlog is:

1. **Add** the entry for the just-merged PR at the top of the chronological section (newest first) in the file resolved above — template below. **Idempotency guard (run first):** `grep -q "IDEA-NNN.*(PR #<N>)" docs/archive/<YYYY-MM>-DEVELOPMENT_LOG.md` — if an entry for this IDEA+PR already exists (an earlier wrap run wrote it), skip the append rather than writing a second copy. Re-runs are routine (a review cycle touches docs, or a post-merge fallback), so the guard is load-bearing, not theoretical.
2. **Backfill-gap detection**: list recently merged PRs via `gh pr list --state merged --base <main-or-production> --limit 20 --json number,title,mergedAt` (squash-merge-friendly; `git log --merges` alone would miss squash-merged PRs). Cross-reference against devlog bullets (this month's file *plus* last month's, so month-boundary drift is caught). If prior PRs merged without devlog entries (drift happens — manual merges, rushed wraps on other PRs, etc.), judgement call on scope: ≤3 gaps → backfill in this wrap. **Each missed PR's bullet goes in the devlog for the month when *that* PR merged** (creating the file if it's a month that hasn't been logged yet). For example, today's wrap on a 2026-05 PR that discovers a missed 2026-04 PR writes the new entry to `2026-05-DEVELOPMENT_LOG.md` and the backfill bullet to `2026-04-DEVELOPMENT_LOG.md`. Larger gap → surface in the wrap's hand-back (`"DEVELOPMENT_LOG has M missing entries from PRs #N1-#N2 — backfill in this wrap or separate chore PR?"`) and wait for direction.

Append a new entry at the **top** of the chronological section (newest first). Template:

```markdown
## YYYY-MM-DD — IDEA-NNN: <Title> (PR #<N>)

**Scope**: One-paragraph what-and-why. Link batched IDEAs if the PR shipped multiple.

### What shipped

- Bullet per material user-facing or infra-facing change. File paths with line refs for hotspots. Code-fence the one-liner when a specific snippet is load-bearing.

### Infrastructure fixes landed in the same PR

- Only if applicable. `/<engine>-loop`-driven scope creep often lands here (pool deadlocks, translator bugs, makefile defaults). Keeping them adjacent to the feature context they surfaced from is more useful than scattering into "chore" entries.

### Related

- [IDEA-NNN archive](…)
- [PR #N](…)
- Companion PRs (dependencies that merged in the same window)
- [Mind-vault compound PR](…) — if `/compound` has already been run, link its PR; else leave this line for `/compound` to append.
```

Use the last two devlog entries in the same file as style anchors — match prose density, heading structure, and linking style. Do **not** cargo-cult the template above verbatim if the project's convention diverges.

### Step 4b — Version-bump consideration (versioned projects only)

**Fires when** the project has a discoverable version source AND the scope is `docs` or `full` (i.e. not `idea-only`). **Skipped** when no version source exists (most internal projects without a published surface), or when scope is `idea-only` (per-IDEA wraps inside sprint-auto defer the version bump to the integration-branch batch wrap so the whole sprint ships as ONE versioned release).

**Version-source detection** — first match wins:

```bash
if   [ -f VERSION ];        then VER_SOURCE=VERSION
elif [ -f pyproject.toml ] && grep -Eq '^[[:space:]]*version[[:space:]]*=' pyproject.toml; then VER_SOURCE=pyproject.toml
elif [ -f package.json ]   && jq -e '.version' package.json >/dev/null 2>&1; then VER_SOURCE=package.json
elif [ -f Cargo.toml ]     && grep -Eq '^[[:space:]]*version[[:space:]]*=' Cargo.toml; then VER_SOURCE=Cargo.toml
elif [ -f setup.py ]       && grep -Eq 'version[[:space:]]*=' setup.py; then VER_SOURCE=setup.py
elif [ -f CHANGELOG.md ]   && grep -Eq '^## (v|V)[0-9]+\.[0-9]|^## \[[0-9]+\.[0-9]' CHANGELOG.md; then VER_SOURCE=CHANGELOG.md  # versioned changelog (mind-vault, Keep-a-Changelog); require MAJOR.MINOR so a bare `## v5` milestone banner can't shadow the real release header
else VER_SOURCE=none
fi
```

If `VER_SOURCE=none`, skip this step entirely — the project doesn't publish a versioned surface, no bump to consider.

**Bump triggers** (any one is sufficient; cluster of two+ makes it near-certain). These are abstract criteria — apply to whatever version scheme the project uses (semver, milestone-based, calver, custom):

- **Architectural pivot** — a workflow stage gains / loses an alternative, a core contract changed, a major subsystem was replaced. In semver: minor or major.
- **Adopter-surface promise** — explicit release-readiness signal, breaking change to a published API / CLI flag / config schema, or a feature that materially widens who can adopt the project. In semver: minor (additive) or major (breaking).
- **Compatibility cliff** — a public file moved or was renamed, a dependency floor raised, a config-key removed without a deprecation cycle. In semver: major.
- **Three-or-more cohesive features bundled** under the current dated section / Unreleased / milestone, sharing a single narrative theme. The bundle is what's load-bearing, not any single PR. In semver: minor.

**Negative triggers** (these alone are NOT bumps):

- Single body refactor / debloat / file-rename within an existing artefact.
- Bug-fix PR or doc-only PR (these still bump *patch* in strict-semver projects; whether to bump-per-PR or batch is a project policy decision — see "When patch-bumps are project policy" below).
- A single isolated tool / script addition with no thematic siblings.
- Internal-only changes that don't change the published surface (memory entries, internal helpers, test-only changes).

**Mechanics when a bump is warranted:**

1. **Confirm with the user** before editing the version source — show the proposed new version + headline rationale linking back to which bump-trigger criterion fired. The user picks the version number (`v4.1`, `v5`, named milestone like "Cross-platform-ready", semver `2.3.0`, etc.). **Never decide the number autonomously** — projects have policy on minor-vs-major calls that an outside agent doesn't know.
2. **Update the version source** detected above:
    - `VERSION` file → single-line replace
    - `pyproject.toml` / `package.json` / `Cargo.toml` → in-place version-field edit
    - `setup.py` → in-place version-arg edit
    - `CHANGELOG.md` with `## v<N>` headers → insert a new section above the most recent dated/Unreleased block; move only entries that are *part of the new version's narrative*, leave unrelated rolling entries in place
3. **Write a headline paragraph** — one paragraph describing what's new, how it relates to the prior version, and what adopter-facing change (if any) it implies. Goes in CHANGELOG, GitHub release notes draft, or the project's release artefact.
4. **Update downstream version references** — README.md, ONBOARDING / docs callouts (`> You're reading the v<N> docs`), badge URLs that pin to `:latest` vs `:v4`, deploy manifests if the project releases container images, etc. The Step 6 grep pass catches these naturally; flag any that surface for explicit attention here.
5. **Tag the commit** in the wrap branch's diff so the eventual GitHub release / `git tag` can fast-forward — but **don't `git tag` from the wrap commit itself** unless the project's CI requires it (the human is the tagger by default).
6. **Surface the post-merge hand-back instruction.** When the project ships a `Makefile` with a `release` target (the mind-vault convention from [IDEA-003](../../docs/archive/2026-05-idea-003-version-tag-automation/IDEA-003-version-tag-automation.md)), include this line in the wrap summary handed back to the human: *"After merging, run `make release` to create the git tag + GitHub release; pass `VERSION=<tag>` if the auto-extracted version differs from the intended tag (the extractor takes the topmost `## vMAJOR.MINOR[.PATCH]` header — keep the newest release header fully-qualified so it isn't read as a bare `v5`; tags from `package.json` / `pyproject.toml` / `Cargo.toml` sources are typically `1.2.3` without a `v` prefix)."* Projects without a Makefile fall back to the manual `git tag -a -m "Release <tag>" -- <tag> && git push origin -- <tag> && gh release create --generate-notes -- <tag>` sequence (annotated tag + `--` separator so a tag name beginning with `-` is treated as a positional, not a flag); mention both forms so the user picks whichever applies. `make release` is idempotent — re-running when the tag already exists is a no-op with a clear "skipping" message, not a `git tag` failure.

**When patch-bumps are project policy.** Some projects bump-per-PR (every merge advances patch); some batch by dated section; some never patch-bump (only minor/major matter for the public). Detect from the project's CHANGELOG style and prior commit log — if the prior two versions advanced by patch on consecutive PRs, treat per-PR patch-bumps as policy and bump without asking. If the prior two versions advanced by minor/major over multi-PR cohorts, the wrap is one of those cohorts' members and the bump-decision is the integration-PR call (sprint-auto path) or the explicit-cohort-finish call (manual path), NOT this individual PR.

**Mind-vault's own policy** is per-PR patch-bump — and that extends to pure `/compound` PRs (no IDEA, so this wrap step never runs for them). `/compound` itself executes the bump in self-mode; see [`../compound/SKILL.md`](../compound/SKILL.md) step 6 + [`../compound/references/mind-vault-promotion.md`](../compound/references/mind-vault-promotion.md) § Self-mode CHANGELOG bump.

**Sprint-auto interaction.** When scope is `idea-only` this step is **skipped** — per-IDEA wraps inside sprint-auto never bump. The sprint's integration-branch batch wrap (sprint-auto S11.7) is the moment when the cumulative IDEA cohort gets considered as one versioned release. At that point all the cohort's IDEA-archive entries, devlog bullets, and CHANGELOG additions are visible together — the bundle criterion ("three-or-more cohesive features") then has a meaningful denominator. Doing per-IDEA bumps inside sprint-auto would produce N patch-bumps in a single sprint, which is noise.

**When in doubt, don't bump.** A rolling entry under the current version is the safe default. The wrap's job is to *surface the question* — if no trigger fires, write the entry and move on without mentioning the bump. If a trigger fires, ask once, then act on the user's call.

### Step 5 — (moved to `/land`)

Worktree teardown left `/wrap` in IDEA-015 — it's destructive and strictly post-merge, so it belongs with the merge. Run `/land NNN` (post-merge teardown) or `/land --integration <batch-iso>` (sprint-auto batch teardown); mechanics live in [`../land/references/WORKTREE_TEARDOWN.md`](../land/references/WORKTREE_TEARDOWN.md). Step number kept as a marker so Step 6/6b/7 numbering stays stable.

### Step 6 — Downstream docs scan

The highest-value and most-skipped step. Everything that referenced the pre-merge state may now be stale. Grep is the workhorse.

For each of: **deleted classes/functions, deleted env vars, renamed models, moved files, removed settings keys, added migrations, new config surface** — run a grep across the project docs tree (`docs/guides/`, `docs/reference/`, `docs/README.md`, top-level `README.md`, `AGENTS.md` / `CLAUDE.md`, and any `.cursor/rules/` equivalents) and list the hits.

Concrete checklist — run each applicable probe, report findings:

- [ ] **Deleted identifier?** `grep -rn <name> docs/` — update references, unlink dead callouts.
- [ ] **Function/method signature changed in source but reference doc still shows the old shape?** For each public callable touched by the PR (or any callable touched recently — bugfix PRs often shift signatures across other in-flight work), grep `docs/reference/` for the function name and verify the documented signature matches the source. Reference-doc signature drift is the highest-frequency Step-6 finding class because (a) signature changes don't fail tests, (b) docs aren't grep-coupled to source, and (c) a parameter added "for one specific caller" is rarely propagated to the doc by the original author. Probe shape: `grep -rn 'def <funcname>' docs/reference/` cross-checked against `grep -n 'def <funcname>' web/<app>/<module>.py`. Patch-now mechanical fix — update the documented signature, args, and (if non-trivial) one usage example.
- [ ] **New migration touched a public-surface model?** `grep -rn <model> docs/reference/` — update field tables if present.
- [ ] **Env var added / removed?** `grep -rn <VAR_NAME> docs/reference/environment_variables.md` + `.env.template` + any deploy runbook.
- [ ] **Slash-command / make-target added or changed?** `grep -rn 'make <target>' docs/` — update README quick-start, AGENTS, CI/CD runbook.
- [ ] **New top-level module / app?** Check `docs/README.md` feature list and any architecture diagrams.
- [ ] **New settings surface?** `docs/reference/environment_variables.md` and any configuration guide need the knob + default + when-to-change.
- [ ] **Removed settings / defaults flipped?** Same files — deprecate with a clear "As of YYYY-MM-DD, this variable is ignored" note for one release cycle before deletion.

Each finding → one of three dispositions:

- **Patch now — mechanical** (cheap, obvious — e.g. replace `GOOGLE_CLOUD_STT_KEY` with `nothing; STT removed 2026-04-20`). Single commit on the wrap branch.
- **Patch now — documentation catch-up.** If the finding is that a project pattern exists in the code but has no documentation of how to use it (e.g. `PLURAL_TRANSLATIONS` used by seven msgid pairs in `tools/translation_maps/shared.py` but no section in the translation-workflow guide), **patch it in the wrap**. Documentation catching up to existing reality is `/wrap` scope. Do not escalate to a new IDEA, do not defer to a separate PR — a new-IDEA ticket for "document this existing pattern" is noise that never ships; the wrap is where it belongs. This class of finding often surfaces during `/<engine>-loop`'s docs-pass review, which is another reason the wrap commits ride on the feature branch — the review bot reviews the filled-in docs as part of the same PR cycle.
- **Flag as follow-up** (larger rewrite — e.g. a reference doc section that needs rewriting for a new architecture, a full walkthrough for a genuinely new concept). Note in the PR description. Legitimate follow-ups: reference-doc *rewrites*, architecture-diagram updates, how-to *tutorials*. Illegitimate follow-ups that should be patched now: "this line is stale", "this pattern isn't documented anywhere", "this section describes a deprecated flow". The test: if one to three paragraphs of documentation would close the gap, it's a patch-now, not a follow-up.

  **A ⚠️-stale marker is NOT a disposition.** When the IDEA's own migration is what made a reference section describe a now-dead architecture, the correct wrap action is to **rewrite that section for the new architecture in this wrap** — not to drop a "⚠️ stale as of `<date>`, see IDEA-NNN" banner and move on. The banner leaves the reference *actively wrong* (a future reader still mis-learns the dead shape), defers the real work to an IDEA that may never run, and reads as "covered" when it isn't. The rewrite is bounded — you just shipped the new architecture, so you know its true shape — and it rides the same wrap commit the engines then review. Reserve the genuine follow-up flag for rewrites that depend on work not yet done (e.g. a section that can't be finalized until a *later* IDEA deletes the legacy template); even then, rewrite for the new architecture now and leave only a one-line "residual `<legacy>` pointer drops when IDEA-NNN deletes it" note, not a whole-section stale banner.

Commit the documentation edits on the same branch that carries the IDEA-completion commits from Steps 2–4:

- **Pre-merge mode** — the feature branch (`auto/<slug>` in sprint-auto, or whatever feature branch the work has been happening on). All wrap commits ride into the merge together.
- **Post-merge fallback** — a fresh `docs/idea-NNN-wrap` branch off `origin/main` (matches the `/compound` branch-or-extend decision tree).

If Step 6b fires next, its whole-README audit patches **and** the `wrap:readme-currency-audited` marker must land on this same branch (the marker contract in [`references/README_CURRENCY.md`](references/README_CURRENCY.md) requires *marker present ⟺ audit ran on this ref*) — so either defer this commit until after 6b, or land 6b's patches + marker as a follow-on commit on the same branch. Don't merge until Step 6b has either fired (patches + marker landed) or skipped per its gates below — just don't pre-empt a fire by merging first.

### Step 6b — Whole-README currency audit (staleness-gated, conditional)

Step 6 patches what *this* IDEA touched; nothing makes any single wrap responsible for the **whole** README, so it drifts across many IDEAs (version framing, counts, feature tables, stale ⚠️ flags). Step 6b is the devlog backfill-gap rule (Step 4 §2) applied to the README — it fires on a staleness threshold and patches mechanical drift in-wrap.

**Gated three ways** (the scope + staleness gates skip silently when they fail; the degraded-env gate *falls back* rather than skips): **scope** — eligible under `docs`, **skipped under `idea-only`** (sprint-auto's batch wrap is the cohort's audit point); **staleness** — count merged base-branch PRs since the last *whole-README audit* (a `<!-- wrap:readme-currency-audited YYYY-MM-DD -->` marker, **not** the file mtime, so Step-6 partial touches don't reset it), fire iff `count >= N` (default 5); **degraded env** — if `gh` is unavailable, fall back to calendar staleness (marker absent or >30 days old) rather than skipping the audit. A marker dated today ⇒ count 0 ⇒ skip (idempotency guard for a same-day re-run). Future-dated/skewed marker ⇒ treat as stale.

When it fires: run the project-agnostic probes (version framing vs Step-4b `VER_SOURCE`, counts vs filesystem globs, feature-table completeness, stale-flag verification, command surface), map each finding onto Step 6's patch-now-mechanical vs flag-follow-up dispositions, and **refresh the marker on the same branch as the patches**. Full probe checklist, marker mechanics, the fail-loud rule for non-mind-vault count shapes, the optional per-project hint block, and the sprint-auto asymmetry are in [`references/README_CURRENCY.md`](references/README_CURRENCY.md). Read that reference when this step fires.

### Step 7 — Eval-gate manual evaluation checklist (PRE-MERGE ONLY, conditional)

**Fires when** the IDEA's frontmatter has `auto_safe_with_eval_gate: true` AND the wrap is running in pre-merge mode (default) or in `--scope=idea-only` mode (sprint-auto S5). **Skipped** in post-merge fallback (the artefact is intended for the integration-PR walk; post-merge it's pointless) and when the frontmatter lacks the flag (the IDEA opted out of the gate).

The gate exists for IDEAs whose behaviours render-and-assert tests cannot verify — visual correctness, keyboard nav, screen-reader semantics, animation timing, mobile gesture nuance. Wrap emits the checklist alongside the per-IDEA work; the human walks it as part of integration-PR review. Mechanics — emission shell snippet, placeholder substitution rules, Playwright-coverage pre-fill algorithm for Direction-1 IDEAs, MANUAL_EVAL_TRACKER hand-off when the walk surfaces issues — are in [`references/EVAL_GATE_EMISSION.md`](references/EVAL_GATE_EMISSION.md). Read that reference when this step fires.

### Step 8 — (moved to `/land`)

Atomic merge left `/wrap` in IDEA-015 — `/wrap` finalizes docs and **never merges**. After the single `/review-loop` clears the wrapped PR, run `/land NNN`: it squash-merges non-protected targets or hands back the PR URL on protected ones, then proceeds to teardown. Mechanics live in [`../land/references/ATOMIC_MERGE.md`](../land/references/ATOMIC_MERGE.md). The deprecated `/wrap --scope=full` invocation finalizes docs then redirects here (see Scope detection).

## Interaction rules

- **Pre-merge is the default.** Unless the PR has already merged (post-merge docs fallback), the wrap commits land on the feature branch and ride into merge together. This eliminates the stale-on-main window between merge and wrap.
- **`/wrap` never merges and never tears down.** Both moved to `/land` (IDEA-015). A `/wrap NNN` finalizes docs and stops; run `/land NNN` after the single `/review-loop` clears to merge + tear down. The deprecated `/wrap --scope=full` finalizes docs then redirects to `/land`.
- **Never skip Step 6** just because it reports zero findings — the grep itself is the value; its output is the audit trail.
- **Never auto-patch architectural docs** (reference `/architecture.md`, high-level guides). Human review required; list findings, let the author decide.
- **Documentation catch-up is wrap-scope, never new-IDEA.** If a pattern exists in code but has no docs, the wrap pass that surfaces the gap is where it gets documented — not a future IDEA, not a separate PR. "Document existing thing" tickets never ship; the single review then sees the filled-in docs in the same PR cycle.
- **In `sprint-auto` mode** (unattended orchestrator): the wrap runs as sprint-auto's S5 step **before** the single S6 review pass, invoked with `--scope=idea-only`. Steps 1, 2, 6 commit onto the `auto/<slug>` branch; Step 7 (eval-gate emission) runs when the IDEA's frontmatter has `auto_safe_with_eval_gate: true` and lands the checklist in the per-IDEA archive dir; the single S6 review then reviews those commits (including the eval-checklist) against the codebase; Steps 3 + 4 are deferred to sprint-auto's S11.7 batch wrap on the integration branch (eliminates the structural N-way line-conflict every parallel `/wrap` would otherwise produce); teardown is `/land --integration` at batch end, not wrap's job.
- **Eval-gate is opt-in per IDEA, not per invocation.** Step 7 fires when the IDEA's own frontmatter declares `auto_safe_with_eval_gate: true`. There is no `--mode=eval-gate` flag — making the behaviour frontmatter-driven means manual `/wrap NNN` invocations on an eval-gate IDEA also emit the checklist (pre-merge), and post-merge fallbacks correctly skip emission without needing a flag distinction.

## When NOT to use these patterns

- Hotfixes that don't touch a documented surface. A typo fix, a null-guard added to a non-public internal function, a test-only bug — no downstream docs to update, no idea to flip. Skip `/wrap`; go straight to `/compound` if there's a learning worth routing.

## References

- [`references/IDEA_COMPLETENESS_AUDIT.md`](references/IDEA_COMPLETENESS_AUDIT.md) — Step 2 pre-condition: walk plan acceptance criteria before flipping `status: complete`. ⚠️ marker for unmet criteria, phase-tracking frontmatter (`phase_N_completed:` + `completed:`), worked premature-wrap precedent.
- [`references/EVAL_GATE_EMISSION.md`](references/EVAL_GATE_EMISSION.md) — Step 7 mechanics: emission shell + placeholder substitution, Playwright-coverage pre-fill algorithm for Direction-1 IDEAs, MANUAL_EVAL_TRACKER hand-off when the walk surfaces issues.
- [`references/WRAP_BEFORE_REVIEW.md`](references/WRAP_BEFORE_REVIEW.md) — ordering for doc-heavy PRs: run wrap's doc-finalization steps *before* the single `/review-loop` so the reviewer sees docs at shipped state (catches doc-consistency findings in the same pass, no post-review drift). Merge is the separate post-review `/land` stage. Includes the Step 2 body-prose status-line sync rationale.
- [`/land`](../land/SKILL.md) — the stage AFTER the review: merge + teardown. `/wrap`'s old Step 5 (teardown) and Step 8 (atomic merge) live there now ([`ATOMIC_MERGE.md`](../land/references/ATOMIC_MERGE.md), [`WORKTREE_TEARDOWN.md`](../land/references/WORKTREE_TEARDOWN.md)); `/land`'s precondition guard verifies this wrap ran.
- [`RULE_ideas-location-status`](../idea/references/IDEAS_LOCATION_STATUS.md) — the frontmatter-only transition this skill relies on.
- [`/work`](../work/SKILL.md) — the stage before; its output (a PR on a feature branch, deliverables committed) is `/wrap`'s input.
- [`/compound`](../compound/SKILL.md) — the final stage; `/wrap` leaves the paper trail `/compound` references.
- [`/sprint-auto`](../sprint-auto/SKILL.md) — the orchestrator that stitches `idea → plan → work → wrap (idea-only) → review-loop → /land → compound` for the unattended case. Sprint-auto invokes `/wrap --scope=idea-only` at S5 (before the single S6 review); merge + batch teardown are sprint-auto's integration-stage + `/land --integration`, not wrap.
- [`RULE_git-safety`](../../rules/RULE_git-safety.md) — the protected-branch list (`main` / `production` / `deployment`) and the merge-into-protected prohibition — now enforced by `/land`'s atomic merge, not wrap.
