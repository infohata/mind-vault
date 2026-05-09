---
name: wrap
description: Documentation sweep — flip idea frontmatter to complete, re-sort the ideas index, append a devlog entry, scan project docs (guides, reference, README) for references that need updating, and (conditionally) emit a manual-evaluation checklist for IDEAs that opted into the eval-gate mode. Default is PRE-merge on the feature branch so merge lands the final docs state in one shot; post-merge fallback handles PRs that shipped without a wrap. **Concludes atomically when the PR target is non-protected** — Step 8 squash-merges via `gh pr merge` after a bugbot re-clearance, eliminating the "wrap then click merge" two-step. Protected targets (main / production / deployment) preserve the human-merge HITL gate. Destructive worktree/volume teardown is strictly post-merge — extended in v3.1 sprint-auto mode to detect last-of-batch and tear down the integration worktree + branch. --scope=idea-only mode narrows the wrap to frontmatter + downstream-docs + eval-checklist only (devlog + ideas-index deferred to sprint-auto's batch wrap on the integration branch); used by sprint-auto S5 to eliminate the structural N-way line-conflict on devlog/index that every parallel /wrap produces. Runs between /bugbot-loop's pass 1 (deliverables) and pass 2 (docs) in sprint-auto mode.
license: MIT
metadata:
  author: mind-vault
  version: '1.0'
---

# wrap

The sprint-workflow step that closes the loop from code-shipped back to docs-coherent — everything that was "in flight" during `/work` + `/bugbot-loop` and now needs a finalized paper trail. Catches the class of work that's cheap to forget and expensive to find later — the devlog entry that didn't get written, the idea still marked `status: in-progress`, the README link that now points at a removed env var, the reference doc section that quotes deleted code.

**Default is pre-merge.** The wrap commits (frontmatter flip, ideas-index move, devlog entry, downstream docs fixes) land on the feature branch, so the PR carries the final docs state into merge in one shot. No follow-up PR, no stale-on-main window between merge and wrap. The "what if the PR doesn't merge?" concern is a non-concern: unmerged commits never reach main, so no stale state can exist — if the branch is closed, the docs commits evaporate with it.

**Concludes atomically for non-protected targets.** When the PR's base branch is non-protected per [`RULE_git-safety`](../../rules/RULE_git-safety.md) (i.e. anything that isn't `main` / `production` / `deployment`), the wrap's final step (Step 8) squash-merges via `gh pr merge --squash --delete-branch` after a bugbot re-clearance pass. This mirrors what sprint-auto already does at the multi-IDEA scale (S11.10 integration PR → S11.12 docs-bugbot → integration merge produces ONE shipping moment for the batch). Single-IDEA wrap follows the same principle: when nothing about the merge target is the HITL gate, the wrap is the deliverer. Protected targets always require a human merge — Step 8 detects and skips, handing back the PR URL.

**Post-merge is the fallback.** If a PR landed without a wrap pass (human merged directly, wrap was forgotten, a hotfix went in on the fly), invoking `/wrap NNN` after the fact creates a small `docs/idea-NNN-wrap` branch with the same outputs and opens a cleanup PR. The skill auto-detects PR state (`gh pr view <N> --json state`) and branches accordingly.

**Destructive worktree teardown** (`docker compose down -v` removing volumes, `git worktree remove`, `git branch -d`) is *always* post-merge — the worktree's diagnostic value is only fully spent once the PR is in. Non-destructive container shutdown (`docker compose down` keeping volumes) on the integration worktree happens in `/sprint-auto`'s S11.13 step; see the sprint-auto skill for that contract.

**`--scope=idea-only` mode (v3.1 sprint-auto)** narrows the wrap to per-IDEA-local work (frontmatter flip + downstream-docs scan); skips ideas-index re-sort and devlog entry append. Used at sprint-auto's S5 to defer those batch-wide writes to S11.7's batch wrap on the integration branch — eliminates the N-way line-conflict that every parallel `/wrap` would otherwise produce on `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md` and `docs/ideas/README.md`. Outside sprint-auto, the flag has no effect (the conflict only arises with parallel branches).

**Last-of-batch integration cleanup (v3.1 sprint-auto post-merge)**: when `/wrap NNN` post-merge detects the IDEA was part of a sprint-auto batch AND no other `auto/<batch-mate-slug>` worktrees still exist locally (i.e. the human has merged + wrapped them all), Step 5 additionally tears down the integration worktree + branch. See Step 5 § "Last-of-batch integration cleanup" below.

## When to use

**TRIGGER when:**

- A feature branch has bugbot-loop-cleared deliverables and is ready for its docs pass (pre-merge default).
- Sprint-auto completes its S3+S4 deliverables-bugbot pass and is about to enter its S6+S7 docs-bugbot pass — wrap runs between them.
- A PR merged without a wrap (post-merge fallback) and the ideas index / devlog / frontmatter are stale on main.
- Phrasings the user might use: "mark the IDEA complete and update docs", "close out this sprint's paper trail", "devlog + index sort", "finalize the docs side of the merge", "sort the docs before merging".

**SKIP when:**

- The merge landed a revert / rollback (no paper trail to create).
- The work was purely experimental and won't ship to users (no reference docs to re-point).
- Hotfixes that don't touch a documented surface (typo fix, null-guard on internal function, test-only bug) — skip and go straight to `/compound` if there's a learning worth routing.

## Pattern

Seven steps in order, one of which (Step 7 — eval-gate emission) is conditional on the IDEA's frontmatter. Most steps are guards — skip silently if the state is already correct. The skill is safe to re-run; it produces the same final state regardless of which steps an earlier run completed.

### Scope detection (alongside mode detection)

Before any step, parse the `--scope=idea-only` flag (or its alias `--no-batch-writes` if encountered):

```bash
SCOPE_IDEA_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --scope=idea-only|--no-batch-writes) SCOPE_IDEA_ONLY=true ;;
    esac
done
```

When `SCOPE_IDEA_ONLY=true`:
- Step 1 (Resolve idea): RUN
- Step 2 (Frontmatter flip): RUN
- Step 3 (Re-sort ideas index): **SKIP** — deferred to sprint-auto S11.7 batch wrap on integration branch
- Step 4 (Devlog entry): **SKIP** — deferred to sprint-auto S11.7
- Step 5 (Worktree teardown): RUN (per usual mode-detection rules — post-merge only)
- Step 6 (Downstream docs scan): RUN
- Step 7 (Eval-gate checklist emission): RUN if frontmatter has `auto_safe_with_eval_gate: true` AND mode is pre-merge
- Step 8 (Atomic merge): **SKIP** — sprint-auto v3.1 hands per-IDEA wraps to the orchestrator's S11 integration phase; the integration PR (NOT per-IDEA PRs) is the merge gate. `--scope=idea-only` always skips Step 8 to preserve that boundary.

The flag is a no-op outside sprint-auto context (manual `/wrap NNN` invocations don't need it; the parallel-conflict problem only arises when N branches' `/wrap`s collide).

### Mode detection (first action each invocation)

Before anything else, determine which mode is running — pre-merge default, post-merge fallback, or self-mode (see below). The decision drives which branch the wrap commits land on:

```bash
# 1. Is this mind-vault itself?
git remote get-url origin | grep -q mind-vault && MODE=self

# 2. Otherwise, what's the PR state for the current branch's open PR, or for the
#    explicit PR number passed as arg?
gh pr view "${PR_OR_BRANCH}" --json state,headRefName --jq '.state'
#   OPEN    → pre-merge default: commit Steps 2-6 onto the current feature branch
#   MERGED  → post-merge fallback: `git checkout -b docs/idea-NNN-wrap origin/main`
#             before committing
#   CLOSED  → refuse: the branch was abandoned; no wrap to do
```

If no PR exists yet (branch pushed but PR not opened), treat as pre-merge default and commit onto the current branch — the PR can be opened later and will carry the wrap commits.

### Self-mode: running on mind-vault itself

Mind-vault does **not** track IDEA-NNN files of its own — per-project IDEA numbering would collide across the projects mind-vault serves (teisutis, etc.). If `/wrap` is invoked on the mind-vault repository itself, Steps 1–3 (IDEA resolution, frontmatter flip, ideas index re-sort) do not apply and must be skipped.

Detection (first match wins):

- `git remote get-url origin` → URL contains `mind-vault`.
- Repo root has `skills/`, `rules/`, `commands/`, and **no** `docs/ideas/README.md` — the mind-vault signature.

In self-mode, Step 4 targets `CHANGELOG.md` at the repo root (not `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md`, which is the per-project convention). **End-to-end maintenance is the wrap's job** — not split between "add to Unreleased pre-merge" and "promote to dated section manually later":

**Preamble — know your PR set.** Before editing, run `gh pr list --state merged --base main --limit 20 --json number,title,mergedAt` (mind-vault uses squash-merge; `git log --merges` alone would miss them) and `gh pr list --state open --base main --json number,title`. The merged list + the just-merged PR determine which Unreleased bullets are eligible to promote; the open list determines which stay. Cross-reference both against existing CHANGELOG bullet PR-links.

1. **Promote, selectively** — move bullets from `## Unreleased` into the current `## YYYY-MM` section **only when the bullet's PR is merged**. Leave bullets for still-open PRs in Unreleased (this is why they were parked there pre-merge). Place promoted bullets above any existing entries in the month (reverse-chronological within the month). Append `(YYYY-MM-DD, [#N](https://github.com/infohata/mind-vault/pull/N))` to each promoted bullet's tail if the date/PR-link aren't already there.
2. **Add** any new entries for the just-merged PR directly into the dated section (not Unreleased) if they weren't added pre-merge. Category keys follow Keep a Changelog: **Added / Changed / Fixed / Removed / Deprecated / Security**. See the existing entries for prose-density anchors.
3. **Reconcile Unreleased**: after Step 1, `## Unreleased` should contain only bullets for still-open PRs (per the preamble's open list). If there are none, reset to `(none)`. If the bullets that remain don't match the current open-PR list, something drifted — surface in the hand-back rather than auto-delete.
4. **Backfill-gap detection**: using the merged-PR list from the preamble, identify any merged PRs without matching CHANGELOG bullets. Judgement call: if the gap is ≤3 PRs, backfill them in this wrap. If larger, surface the gap in the wrap's hand-back message (`"CHANGELOG is missing entries for PRs #N1-#N2 (M PRs). Shall I backfill in this wrap PR or open a separate chore PR?"`) and wait for direction.

The point: after wrap, `Unreleased` reflects only actually-open PRs, the dated section is current, and no human intervention is needed to "catch up" the log.

Step 5 (worktree teardown) almost never applies because mind-vault has no docker stack, but the guards are branch-agnostic — run them if they fire.

The load-bearing self-mode work is Step 6: catch `README.md` / `docs/SPRINT_WORKFLOW.md` / `tools/README.md` / `AGENTS.md` / `CLAUDE.md` drift from newly-added skills, commands, rules, or agent passes. That is what `/wrap` is *for* on mind-vault — the paper trail of its own evolution, alongside the changelog.

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
completed: YYYY-MM-DD
```

**`completed:` date source** depends on mode:

- **Pre-merge default**: use today's date (the day the wrap is running and the PR is about to merge). If merge slips by a day, the date is off by one — tolerable, and still better than waiting for merge to write the date. The `related:` field may also gain entries here if the wrap sweep reveals sibling IDEAs.
- **Post-merge fallback**: use `gh pr view <N> --json mergedAt --jq '.mergedAt | split("T")[0]'` to get the real merge date.

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

**Genesis**: introduced in 2026-05 during the 25-IDEA `sprint/ux-overhaul` cohort (teisutis project) — the context cost of re-reading 25 plan docs to remember decisions had crossed a pain threshold. A small `auto-memory` reference entry pointing at the recap location makes the pattern survive across agent sessions.

### Step 4 — Devlog entry

**First, resolve the target file for the NEW entry (month-rollover check).** Compute today's `YYYY-MM`. If `docs/archive/<YYYY-MM>-DEVELOPMENT_LOG.md` doesn't exist yet (first write of the month), create it with the standard header — see any prior month's top lines for the template. **The just-merged PR's entry goes in *today's month* file**, even if the PR's own merge timestamp is right at a month boundary; the chronological log is indexed by when the entry is authored, not when the underlying work shipped minutes earlier. Backfill (Step 2) handles its own per-missed-PR file targeting separately from this.

**Maintain end-to-end** — the same discipline that applies to CHANGELOG in self-mode applies here. Once the target file for the new entry is resolved, the wrap's responsibility for the monthly devlog is:

1. **Add** the entry for the just-merged PR at the top of the chronological section (newest first) in the file resolved above — template below.
2. **Backfill-gap detection**: list recently merged PRs via `gh pr list --state merged --base <main-or-production> --limit 20 --json number,title,mergedAt` (squash-merge-friendly; `git log --merges` alone would miss squash-merged PRs). Cross-reference against devlog bullets (this month's file *plus* last month's, so month-boundary drift is caught). If prior PRs merged without devlog entries (drift happens — manual merges, rushed wraps on other PRs, etc.), judgement call on scope: ≤3 gaps → backfill in this wrap. **Each missed PR's bullet goes in the devlog for the month when *that* PR merged** (creating the file if it's a month that hasn't been logged yet). For example, today's wrap on a 2026-05 PR that discovers a missed 2026-04 PR writes the new entry to `2026-05-DEVELOPMENT_LOG.md` and the backfill bullet to `2026-04-DEVELOPMENT_LOG.md`. Larger gap → surface in the wrap's hand-back (`"DEVELOPMENT_LOG has M missing entries from PRs #N1-#N2 — backfill in this wrap or separate chore PR?"`) and wait for direction.

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

### Step 5 — Worktree teardown (POST-MERGE ONLY, conditional)

**Fires when** wrap is running post-merge AND the sprint ran in a parallel git worktree with its own docker-compose stack. **Skipped** when running from the primary checkout (`git rev-parse --git-common-dir` equals `.git`), when the PR is still open, when the user signalled keep-the-stack-up (`WRAP_KEEP_STACK=1` / `--keep-stack`), or when the worktree has uncommitted work. In `sprint-auto` mode, teardown remains **deferred** to morning review.

Mechanics — destructive teardown sequence (`docker compose down -v` → `git worktree remove` → `git branch -d`), per-file evaluation when `git worktree remove` refuses (forgotten commits, missing gitignore rules, stale ephemera, container-as-root permission residue), and last-of-batch integration cleanup for sprint-auto v3.1 batches — are in [`references/WORKTREE_TEARDOWN.md`](references/WORKTREE_TEARDOWN.md). Read that reference when this step fires.

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
- **Patch now — documentation catch-up.** If the finding is that a project pattern exists in the code but has no documentation of how to use it (e.g. `PLURAL_TRANSLATIONS` used by seven msgid pairs in `tools/translation_maps/shared.py` but no section in the translation-workflow guide), **patch it in the wrap**. Documentation catching up to existing reality is `/wrap` scope. Do not escalate to a new IDEA, do not defer to a separate PR — a new-IDEA ticket for "document this existing pattern" is noise that never ships; the wrap is where it belongs. This class of finding often surfaces during `/bugbot-loop`'s docs-pass review, which is another reason the wrap commits ride on the feature branch — bugbot reviews the filled-in docs as part of the same PR cycle.
- **Flag as follow-up** (larger rewrite — e.g. a reference doc section that needs rewriting for a new architecture, a full walkthrough for a genuinely new concept). Note in the PR description. Legitimate follow-ups: reference-doc *rewrites*, architecture-diagram updates, how-to *tutorials*. Illegitimate follow-ups that should be patched now: "this line is stale", "this pattern isn't documented anywhere", "this section describes a deprecated flow". The test: if one to three paragraphs of documentation would close the gap, it's a patch-now, not a follow-up.

Commit the documentation edits on the same branch that carries the IDEA-completion commits from Steps 2–4:

- **Pre-merge mode** — the feature branch (`auto/<slug>` in sprint-auto, or whatever feature branch the work has been happening on). All wrap commits ride into the merge together.
- **Post-merge fallback** — a fresh `docs/idea-NNN-wrap` branch off `origin/main` (matches the `/compound` branch-or-extend decision tree).

### Step 7 — Eval-gate manual evaluation checklist (PRE-MERGE ONLY, conditional)

**Fires when** the IDEA's frontmatter has `auto_safe_with_eval_gate: true` AND the wrap is running in pre-merge mode (default) or in `--scope=idea-only` mode (sprint-auto S5). **Skipped** in post-merge fallback (the artefact is intended for the integration-PR walk; post-merge it's pointless) and when the frontmatter lacks the flag (the IDEA opted out of the gate).

The gate exists for IDEAs whose behaviours render-and-assert tests cannot verify — visual correctness, keyboard nav, screen-reader semantics, animation timing, mobile gesture nuance. Wrap emits the checklist alongside the per-IDEA work; the human walks it as part of integration-PR review. Mechanics — emission shell snippet, placeholder substitution rules, Playwright-coverage pre-fill algorithm for Direction-1 IDEAs, MANUAL_EVAL_TRACKER hand-off when the walk surfaces issues — are in [`references/EVAL_GATE_EMISSION.md`](references/EVAL_GATE_EMISSION.md). Read that reference when this step fires.

### Step 8 — Atomic merge (PRE-MERGE ONLY, conditional on non-protected target)

**Fires when** the wrap is running in pre-merge mode AND the PR's target branch is **non-protected** per [`RULE_git-safety`](../../rules/RULE_git-safety.md). Protected branches (`main`, `production`, `deployment` — the project decides which) ALWAYS require a human merge; the wrap stops at "docs are coherent on the feature branch" and hands the PR URL to the user. Non-protected branches (sprint cohort like `sprint/<topic>`, integration branches like `integration/sprint-auto-<batch>`, any feature branch) are agent-authority for `gh pr merge` and the wrap concludes the IDEA atomically.

The HITL gate is *protected-branch* merge, not *every* merge; the gate stays exactly where `RULE_git-safety` puts it. Mechanics — protected-branch detection, pre-merge bugbot re-clearance options (default: wait for re-clean), squash-merge sequence, permission-denial handling, deployment-branch override — are in [`references/ATOMIC_MERGE.md`](references/ATOMIC_MERGE.md). Read that reference when this step fires.

## Interaction rules

- **Pre-merge is the default.** Unless the PR has already merged (post-merge fallback), the wrap commits land on the feature branch and ride into merge together. This eliminates the stale-on-main window between merge and wrap.
- **Atomic merge for non-protected targets** (Step 8). When the PR base is `sprint/<topic>` / `integration/<batch>` / any feature branch, the wrap squash-merges itself. Protected targets always preserve the human-merge HITL gate.
- **Destructive teardown is strictly post-merge.** Step 5's `-v` volume removal + worktree removal + branch delete require the PR to have landed. Non-destructive container shutdown is handled by `/sprint-auto` S5, not here. Step 8's atomic-merge path naturally unblocks Step 5 in the same wrap pass.
- **Never skip Step 6** just because it reports zero findings — the grep itself is the value; its output is the audit trail.
- **Never auto-patch architectural docs** (reference `/architecture.md`, high-level guides). Human review required; list findings, let the author decide.
- **Documentation catch-up is wrap-scope, never new-IDEA.** If a pattern exists in code but has no docs, the wrap pass that surfaces the gap is where it gets documented — not a future IDEA, not a separate PR. "Document existing thing" tickets never ship; wrap's docs-pass bugbot review is what keeps the project's reference material honest.
- **In `sprint-auto` mode** (unattended orchestrator): the wrap runs as sprint-auto's S5 step between the two bugbot passes, invoked with `--scope=idea-only`. Steps 1, 2, 6 commit onto the `auto/<slug>` branch; Step 7 (eval-gate emission) runs when the IDEA's frontmatter has `auto_safe_with_eval_gate: true` and lands the checklist in the per-IDEA archive dir; the second bugbot pass reviews those commits (including the eval-checklist) against the codebase; Steps 3 + 4 are deferred to sprint-auto's S11.7 batch wrap on the integration branch (eliminates the structural N-way line-conflict every parallel `/wrap` would otherwise produce); Step 5 stays deferred to the morning-review `/wrap NNN` invocation after merge — including the v3.1 last-of-batch integration worktree cleanup when applicable.
- **Eval-gate is opt-in per IDEA, not per invocation.** Step 7 fires when the IDEA's own frontmatter declares `auto_safe_with_eval_gate: true`. There is no `--mode=eval-gate` flag — making the behaviour frontmatter-driven means manual `/wrap NNN` invocations on an eval-gate IDEA also emit the checklist (pre-merge), and post-merge fallbacks correctly skip emission without needing a flag distinction.
- **The HITL gate is *protected-branch* merge, not *every* merge.** Step 8 squash-merges into non-protected targets (sprint cohort, integration, feature) by default; protected targets always preserve the human-merge gate. This matches `RULE_git-safety` § 2 ("Never merge or push into a protected branch") rather than reading it as "never merge anything."

## When NOT to use these patterns

- Hotfixes that don't touch a documented surface. A typo fix, a null-guard added to a non-public internal function, a test-only bug — no downstream docs to update, no idea to flip. Skip `/wrap`; go straight to `/compound` if there's a learning worth routing.

## References

- [`references/WORKTREE_TEARDOWN.md`](references/WORKTREE_TEARDOWN.md) — Step 5 mechanics: destructive teardown sequence, per-file evaluation when `git worktree remove` refuses, last-of-batch integration cleanup for sprint-auto v3.1 batches.
- [`references/EVAL_GATE_EMISSION.md`](references/EVAL_GATE_EMISSION.md) — Step 7 mechanics: emission shell + placeholder substitution, Playwright-coverage pre-fill algorithm for Direction-1 IDEAs, MANUAL_EVAL_TRACKER hand-off when the walk surfaces issues.
- [`references/ATOMIC_MERGE.md`](references/ATOMIC_MERGE.md) — Step 8 mechanics: protected-branch detection, pre-merge bugbot re-clearance, squash-merge sequence, permission-denial handling, deployment-branch override.
- [`RULE_ideas-location-status`](../idea/references/IDEAS_LOCATION_STATUS.md) — the frontmatter-only transition this skill relies on.
- [`RULE_parallel-worktree-docker`](../sprint-auto/references/PARALLEL_WORKTREE_DOCKER.md) — the worktree + compose-project contract Step 5 tears down.
- [`/work`](../work/SKILL.md) — the stage before; its output (a PR on a feature branch, bugbot-cleared deliverables) is `/wrap`'s input.
- [`/compound`](../compound/SKILL.md) — the stage after; `/wrap` leaves the paper trail `/compound` references.
- [`/sprint-auto`](../sprint-auto/SKILL.md) — the orchestrator that stitches `idea → plan → work → bugbot-loop(deliverables) → wrap-docs → bugbot-loop(docs) → compound` for the unattended case. Sprint-auto's S5 step handles the non-destructive container shutdown; post-merge destructive teardown in Step 5 here complements it. **Step 8's atomic-merge pattern derives from sprint-auto's integration-stage** — the same principle ("when nothing about the merge target is protected, the orchestrator delivers atomically") applies at single-IDEA scale. Manual `/wrap` and sprint-auto's S11 integration merge are two scales of the same idea.
- [`RULE_git-safety`](../../rules/RULE_git-safety.md) — Step 8's protected-branch detection list (`main` / `production` / `deployment`) and the "merge into protected branch" prohibition that scopes Step 8 to non-protected targets only.

---

**Last Updated**: 2026-04-30
