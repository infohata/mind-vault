---
name: wrap
description: Documentation sweep — flip idea frontmatter to complete, re-sort the ideas index, append a devlog entry, and scan project docs (guides, reference, README) for references that need updating. Default is PRE-merge on the feature branch so merge lands the final docs state in one shot; post-merge fallback handles PRs that shipped without a wrap. Destructive worktree/volume teardown is strictly post-merge — extended in v3.1 sprint-auto mode to detect last-of-batch and tear down the integration worktree + branch. New --scope=idea-only mode narrows the wrap to frontmatter + downstream-docs only (devlog + ideas-index deferred to sprint-auto's batch wrap on the integration branch); used by sprint-auto S5 to eliminate the structural N-way line-conflict on devlog/index that every parallel /wrap produces. Runs between /bugbot-loop's pass 1 (deliverables) and pass 2 (docs) in sprint-auto mode.
license: MIT
metadata:
  author: mind-vault
  version: '1.0'
---

# wrap

The sprint-workflow step that closes the loop from code-shipped back to docs-coherent — everything that was "in flight" during `/work` + `/bugbot-loop` and now needs a finalized paper trail. Catches the class of work that's cheap to forget and expensive to find later — the devlog entry that didn't get written, the idea still marked `status: in-progress`, the README link that now points at a removed env var, the reference doc section that quotes deleted code.

**Default is pre-merge.** The wrap commits (frontmatter flip, ideas-index move, devlog entry, downstream docs fixes) land on the feature branch, so when the human merges the PR the docs state is already correct in one shot. No follow-up PR, no stale-on-main window between merge and wrap. The "what if the PR doesn't merge?" concern is a non-concern: unmerged commits never reach main, so no stale state can exist — if the branch is closed, the docs commits evaporate with it.

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

Six steps in order. Most are guards — skip silently if the state is already correct. The skill is safe to re-run; it produces the same final state regardless of which steps an earlier run completed.

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

**This step runs only after the PR has merged.** Pre-merge wrap runs stop here — skip Step 5 entirely and continue to Step 6. Destructive teardown (`-v` volume removal, `git worktree remove`, `git branch -d`) unconditionally requires the PR to be in; the worktree's diagnostic value is only fully spent once merge happens, and `git branch -d` itself will refuse the delete if the branch isn't merged into the target (the safety check that keeps accidental unmerged-work loss from being possible).

Non-destructive container shutdown (`docker compose down` without `-v`) is handled elsewhere — `/sprint-auto`'s S5 teardown step stops containers pre-merge to free CPU/RAM/ports while keeping volumes and the worktree filesystem for reviewer inspection. This step is the rest of the cleanup: volumes removed, worktree removed, branch deleted.

If the sprint ran in a parallel git worktree with its own docker-compose stack (see [`RULE_parallel-worktree-docker`](../../rules/RULE_parallel-worktree-docker.md)) — the idea-specific `.env`, per-worktree stack with port offset, dedicated compose project — this is the natural moment to tear it down completely. Leaving it live holds disk hostage and invites port collisions when the next sprint starts.

Skip this step when:

- Running from the primary checkout (no worktree). `git rev-parse --git-common-dir` equals `.git`.
- The PR is still open (pre-merge mode). Destructive teardown is post-merge only.
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

#### Per-file evaluation when `git worktree remove` refuses

When step 3 errors with "contains modified or untracked files", do **not** reach for `--force`. Run `git status --short` in the worktree, list every path, and classify each one. The cleanup step is the last chance to catch four distinct classes of finding, each with a different follow-up:

1. **Forgotten commit** — a real code or asset change the author meant to commit but didn't. Unlikely on a well-run sprint; catastrophic if lost because the worktree is the only copy. Commit it on the feature branch (post-merge? open a followup PR — cheaper than silently losing the change) then retry teardown.
2. **Missing `.gitignore` rule** — a file generated by a newly-shipped feature that should have been gitignored upstream. Add the rule to the primary checkout's `.gitignore` in a small followup PR; the pattern never bites again in future worktrees. Example: a worktree-local `docker-compose.override.yml` emitted by a bootstrap script whose header says "do not commit" but whose project lacks the matching gitignore line — the one-line followup PR closes the gap permanently.
3. **Stale ephemera with a known origin** — the sentinel `.env` from the bootstrap, a scratch log, an `.orig` backup from a sed edit. Safe to `rm <explicit-path>` once identified; name every path explicitly rather than `rm -rf` or `--force`.
4. **Permission residue from container-as-root writes** — gitignored bytecode caches (`__pycache__/*.pyc`), translation `.po`/`.mo` artefacts, pytest cache — generated by a container whose entrypoint runs as root, bind-mounted back to a host user who can't unlink them. Git doesn't warn because they're gitignored, but `git worktree remove`'s underlying `rm` fails on permission. Fix ownership before teardown:

   ```bash
   # Preferred: no host sudo required
   docker run --rm -v <absolute-worktree-path>:/work alpine \
       chown -R "$(id -u):$(id -g)" /work

   # Fallback if sudo is available and docker isn't
   sudo chown -R "$(id -u):$(id -g)" <worktree-path>
   ```

   The docker-based chown works because containers run as root on the daemon and have full UID authority on bind mounts — see `RULE_parallel-worktree-docker` for the security caveats before leaning on this pattern.

Only after every untracked/modified path has been explicitly classified and handled does plain `git worktree remove` (no `--force`) run. The forcefully-silent path hides all four categories; the deliberate path surfaces them as follow-up PRs that improve the project.

In `sprint-auto` mode, teardown remains **deferred**: per the sprint-auto skill, worktrees stay up for morning review. The `/wrap` reminder block in the sprint-auto batch summary now includes teardown as a post-review action per IDEA, same list as the frontmatter flip.

#### Last-of-batch integration cleanup (v3.1 sprint-auto post-merge)

When `/wrap NNN` runs post-merge and the IDEA was part of a sprint-auto v3.1 batch, additionally tear down the **integration worktree + branch** if this is the last-of-batch IDEA. Detection:

```bash
# 1. Was this IDEA part of a sprint-auto batch? Check the per-IDEA archive
#    dir for an auto-run-YYYY-MM-DD.md log with a batch_iso reference.
batch_iso=$(grep -hoP 'sprint_auto_integration_worktree:.*-(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z)' \
    "<project>/docs/archive/<YYYY-MM-idea-NNN-slug>/auto-run-"*.md \
    | head -1 | grep -oP '\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z')
[[ -n "$batch_iso" ]] || return 0  # not a sprint-auto v3.1 batch

# 2. Are there other batch-mate worktrees still on disk?
#    Sprint-auto's batch-mate worktrees share the integration_worktree_path
#    in their auto-run logs, OR equivalently their auto/<slug> branches all
#    point at commits that include the same integration/sprint-auto-<batch-iso>
#    branch. Cheaper detection: enumerate existing local auto/* worktrees,
#    check each one's auto-run log for the same batch_iso.
remaining=0
for wt in $(git worktree list --porcelain | awk '/^worktree /{print $2}' | grep -E '/<project>-auto-[^/]+$' | grep -v '/<project>-auto-integration-'); do
    other_log=$(find "$wt/docs/archive" -name 'auto-run-*.md' 2>/dev/null | head -1)
    [[ -z "$other_log" ]] && continue
    grep -q "$batch_iso" "$other_log" 2>/dev/null && (( remaining++ ))
done

# 3. If this is the last-of-batch (remaining == 0 after teardown of THIS worktree),
#    tear down the integration worktree too.
if (( remaining == 0 )); then
    integration_path="$HOME/projects/<project>-auto-integration-${batch_iso}"
    if [[ -d "$integration_path" ]]; then
        cd "$integration_path"
        docker compose down -v 2>/dev/null || true
        cd -
        git worktree remove "$integration_path" 2>/dev/null \
            || log_warn "git worktree remove $integration_path failed; manual cleanup needed"
        git branch -d "integration/sprint-auto-${batch_iso}" 2>/dev/null \
            || log_warn "git branch -d integration/sprint-auto-${batch_iso} failed (unmerged?); use -D after confirming"
        # Optional: also delete the remote integration branch
        git push origin --delete "integration/sprint-auto-${batch_iso}" 2>/dev/null || true
        echo "Last-of-batch integration cleanup complete: removed worktree + branch + volumes for batch ${batch_iso}"
    fi
fi
```

The detection is **conservative**: if any sibling `auto/<batch-mate-slug>` worktree is still on disk, we don't tear down the integration worktree. The reviewer is presumed to still be working through the batch's PRs in some order.

When this firing fails (network down for remote-branch delete, the integration worktree was manually moved, etc.): log the failure, continue with the per-IDEA wrap normally. The integration worktree's leftover state is recoverable by hand and isn't a blocker for completing this IDEA's wrap.

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

## Interaction rules

- **Pre-merge is the default.** Unless the PR has already merged (post-merge fallback), the wrap commits land on the feature branch and ride into merge together. This eliminates the stale-on-main window between merge and wrap.
- **Destructive teardown is strictly post-merge.** Step 5's `-v` volume removal + worktree removal + branch delete require the PR to have landed. Non-destructive container shutdown is handled by `/sprint-auto` S5, not here.
- **Never skip Step 6** just because it reports zero findings — the grep itself is the value; its output is the audit trail.
- **Never auto-patch architectural docs** (reference `/architecture.md`, high-level guides). Human review required; list findings, let the author decide.
- **Documentation catch-up is wrap-scope, never new-IDEA.** If a pattern exists in code but has no docs, the wrap pass that surfaces the gap is where it gets documented — not a future IDEA, not a separate PR. "Document existing thing" tickets never ship; wrap's docs-pass bugbot review is what keeps the project's reference material honest.
- **In `sprint-auto` mode** (unattended orchestrator): the wrap runs as sprint-auto's S5 step between the two bugbot passes, invoked with `--scope=idea-only`. Steps 1, 2, 6 commit onto the `auto/<slug>` branch; the second bugbot pass reviews those commits against the codebase; Steps 3 + 4 are deferred to sprint-auto's S11.7 batch wrap on the integration branch (eliminates the structural N-way line-conflict every parallel `/wrap` would otherwise produce); Step 5 stays deferred to the morning-review `/wrap NNN` invocation after merge — including the v3.1 last-of-batch integration worktree cleanup when applicable.
- **Don't merge** — every `/wrap` output is on a branch; the human merges it (same HITL gate as `/work`'s feature branch).

## When NOT to use these patterns

- Hotfixes that don't touch a documented surface. A typo fix, a null-guard added to a non-public internal function, a test-only bug — no downstream docs to update, no idea to flip. Skip `/wrap`; go straight to `/compound` if there's a learning worth routing.

## References

- [`RULE_ideas-location-status`](../../rules/RULE_ideas-location-status.md) — the frontmatter-only transition this skill relies on.
- [`RULE_parallel-worktree-docker`](../../rules/RULE_parallel-worktree-docker.md) — the worktree + compose-project contract Step 5 tears down.
- [`/work`](../work/SKILL.md) — the stage before; its output (a PR on a feature branch, bugbot-cleared deliverables) is `/wrap`'s input.
- [`/compound`](../compound/SKILL.md) — the stage after; `/wrap` leaves the paper trail `/compound` references.
- [`/sprint-auto`](../sprint-auto/SKILL.md) — the orchestrator that stitches `idea → plan → work → bugbot-loop(deliverables) → wrap-docs → bugbot-loop(docs) → compound` for the unattended case. Sprint-auto's S5 step handles the non-destructive container shutdown; post-merge destructive teardown in Step 5 here complements it.

---

**Last Updated**: 2026-04-30
