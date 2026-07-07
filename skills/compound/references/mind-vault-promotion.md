# Mind-vault promotion — branch policy, PR maintenance, commit conventions

Full procedure for writing to any mind-vault destination. Load on demand at `/compound` step 4.

## Locate the mind-vault checkout

1. Check `$MIND_VAULT` environment variable — if set, use that path.
2. Check `~/projects/mind-vault` (the default location per global CLAUDE.md).
3. Walk `pwd` up the tree looking for a directory whose `.git/config` points at `infohata/mind-vault` or `mind-vault/.git`.
4. If none found, ask the user for the path.

Once resolved, all git operations target that path via `git -C <mind-vault-path> ...`.

## Branch policy (sprint-workflow plan Q3 resolution, authoritative)

Probe `git -C <mind-vault-path> branch --show-current`.

| Current branch | Action |
| --- | --- |
| `main` | `git fetch origin` first, then create `compound/YYYY-MM-DD-<slug>` off `origin/main`. Switch to it. |
| `production`, `deployment` | Refuse. Protected branches. Ask the user to check out a feature branch first. |
| Any other branch (feature / sprint / compound/...) | Stay on it. No new branch. No branch spam. |

The policy is deliberate: compound commits pile into the active sprint branch so a single PR accumulates all learnings from one sprint. Branch spam would split the review surface and make the "keep an open PR alive" contract awkward.

The **single up-front `git fetch origin`** is deliberate too: the self-mode bump reads the topmost CHANGELOG version and the manifest from this base, so a stale `origin/main` ref (a checkout that hasn't fetched since the last release) computes a colliding version. One fetch before branching is the whole freshness protocol — a compound run takes minutes, so no push-time re-fetch/re-verify; if compound runs ever get slow enough for main to race ahead mid-run, that's a bigger problem than this protocol.

## The slug for compound branches

When creating a new branch off `main`:

- Slug derives from the learning's essence. Kebab-case, ≤40 chars.
- Examples: `compound/2026-04-19-async-tenant-context`, `compound/2026-04-19-hmac-flat-payload-trap`.
- If a `compound/YYYY-MM-DD-*` branch already exists from today, extend it rather than creating a second one — even when the learnings are distinct. Same day, same branch. No spam.

## Emit the file(s)

Write all target files for the routing decision. Common cases:

- **New skill:** `skills/<name>/SKILL.md` + optional `references/` + `assets/`. Use [`assets/skill-scaffold-template.md`](../assets/skill-scaffold-template.md).
- **Skill extension:** append a section to existing `SKILL.md` or a new file under `skills/<name>/references/`. Prefer the `references/` route — keeps SKILL.md bodies lean.
- **New rule:** `rules/RULE_<topic>.md` with the standard body (The Hard Rules → When This Applies → Required Workflow → Common Pitfalls). Mirror the shape of existing RULE files.
- **Rule extension:** append to the relevant "Common Pitfalls" or "Hard Rules" section of the existing file.
- **Agent pass:** edit `agents/AGENT_<persona>.md` in place, appending a bullet under the correct PASS heading.
- **Command:** new `commands/<verb>.md` following the shape of existing `commands/*.md` files.
- **Script:** new `tools/<script>.sh` with `chmod +x`. Include a brief header comment.

## Fact-check version-gated claims before emitting

A live sprint yields claims of the form "X exists only in v≥N", "flag Y was added in Z", "format
unchanged across A–B". These are the highest-error-rate content a compound promotes: the sprint
observed ONE version under ONE config, and the natural failure is over-generalizing that observation
into a version gate. Two consecutive compound PRs shipped confidently-wrong claims of exactly this
shape (PR #217: a "v3.5+" gate on a v3.0 feature; a hook blamed for a permission-layer block).

- **Verify against a primary source** — release notes, the changelog, the PR/commit that introduced
  the feature — NOT version-pinned doc pages. Docs lag features: a field absent from the vN docs
  page may have shipped in v(N−k) undocumented (Traefik `rejectStatusCode`: in core since v3.0 via
  traefik#10130, absent from doc pages until late 3.x — the "v3.5+" misread came from the docs gap).
- **Can't verify** (offline run, ambiguous sources)? **Demote the claim to an observation with
  provenance** — "observed on v3.5; introduction version unverified" — never assert the gate.
- **Attribute a block/denial to the right layer before documenting it.** A guard firing once has
  several candidate sources (harness permission matcher, plugin hook, repo hook, server-side rule).
  Reproduce against the specific component you're about to blame — if it has a self-test, run it.

## Self-mode CHANGELOG bump (mind-vault self-promotion only)

When `/compound` writes to mind-vault **itself** (a self-promotion — not a project-local `docs/solutions/` write), maintain `CHANGELOG.md` in the SAME commit:

- **Pure `/compound` PRs increment the patch component by 1** (`vX.Y.Z → vX.Y.(Z+1)` — not a bump *to* `0.0.1`). Mind-vault's policy is per-PR versioning. A compound has no IDEA, so `/wrap` (whose Step 4b would handle the bump for an IDEA PR) never fires — `/compound` owns the bump. Take the topmost `## vMAJOR.MINOR.PATCH` header, increment PATCH, insert the new section above it.
- **Section shape** (match existing entries' prose density): `## v<X.Y.Z> — <short title>`, a one-paragraph intro, then `### Added` / `### Changed` / etc. (Keep-a-Changelog keys), and a `(YYYY-MM-DD, [#N](https://github.com/infohata/mind-vault/pull/N))` tail.
- **Bump the plugin-manifest mirror in lockstep.** mind-vault ships `.claude-plugin/plugin.json` whose `version` MUST mirror the top CHANGELOG `## vX.Y.Z` (IDEA-017). In the SAME commit, `jq` in-place `.version` to the new bare `X.Y.Z`. This is the mirror half of `/wrap` Step 4b's "N sync-required sources" contract — `/compound` owns the bump for IDEA-less PRs, so it owns the mirror too. Verify: `jq -r '.version' .claude-plugin/plugin.json` equals the new top CHANGELOG version.
- **Pre-commit assertion (structural backstop — do not skip; both halves have been missed in the wild, each costing a follow-up fix PR):** two local checks, no network (the fetch already happened at branch time):
  1. `git diff --staged CHANGELOG.md | grep '^+## v'` matches — the staged diff **adds a new section header**. Appending bullets into the released top section is the recurring miss.
  2. `jq -r '.version' .claude-plugin/plugin.json` equals the new top CHANGELOG version.
- **`## Unreleased` stays `_(none)_`** — a compound that is the shipping unit writes its `## v` section directly, not a parked Unreleased bullet.
- **Post-merge:** `make release` cuts the tag from the topmost CHANGELOG header (see wrap SKILL.md Step 4b § Mechanics, `make release` sub-bullet).
- **Remote/overnight note:** this is why the policy lives here, not in auto-memory — a compound run on the VPS (sprint-auto, overnight) must apply the same bump. Auto-memory doesn't sync across hosts; mind-vault does.

Mind-vault-self-mode ONLY. For every other project, `/compound` writes project-local docs and does NOT touch any CHANGELOG.

## Commit format

One commit per `/compound` invocation. Scope reflects the destination:

```text
feat(skills): <skill-name> — <one-line summary of addition>

Provenance: <path-to-source-project>/<pr-or-file-reference>
Captured-via: /compound on <branch-of-source-project>
```

Types by destination:

| Destination | Type | Scope |
| --- | --- | --- |
| New skill | `feat` | `skills` |
| Skill extension | `docs` | `skills/<name>` |
| New rule | `feat` | `rules` |
| Rule extension | `docs` | `rules/RULE_<name>` |
| Agent pass | `docs` | `agents/AGENT_<persona>` |
| Command | `feat` | `commands` |
| Script | `feat` | `tools` |

Never `--no-verify`, never plain `--force`, per `RULE_git-safety`.

## Push and ensure open PR

1. `git -C <mind-vault-path> push --set-upstream origin <branch>`.
2. `gh pr view <branch>` to check PR existence.
3. **No PR:** `gh pr create --title "<type>(<scope>): <slug>" --body <body>`. Body includes:
   - A one-paragraph summary of what this branch does (for compound branches: "Accumulates learnings from sprint X").
   - A list of the learnings captured so far with their commit SHAs (for the first commit this is one line; for subsequent commits this grows).
4. **Existing PR:** read the PR body via `gh pr view --json body -q .body`. Append a new bullet to the learnings list referencing this invocation's commit. Update with `gh pr edit --body <new-body>`.

Never `gh pr merge`. Never `git push --force-with-lease origin main`. The human merges the PR when ready.

## PR body skeleton

```markdown
## Compounded learnings

Learnings captured from sprint work, promoted from target projects into mind-vault per the sprint workflow's compound stage.

### Landed in this PR

- `<sha>` — <one-line summary> (<destination path>)
- `<sha>` — <one-line summary> (<destination path>)

### Review notes

- Each learning is reviewable independently — each commit is self-contained.
- No commits modify `main`; this is a compound-branch PR awaiting human merge.
- See `docs/guides/SPRINT_WORKFLOW.md` for the compound-routing taxonomy.
```

## What to report back to the user

After the push and PR operations complete:

```text
Compound landed:
  Branch: <branch>
  Commit: <sha>
  Files: <destination paths>
  PR: <pr-url>

Review the diff before merging — `gh pr view <pr-url>` for details.
```

Include the PR URL explicitly so the user can click through.

## Failure modes

- **Dirty working tree on mind-vault.** If `git status --porcelain` is non-empty before the skill starts, refuse and tell the user to commit or stash first.
- **Push rejected.** Fetch, diagnose (someone else pushed to this compound branch), and ask the user how to resolve — do not force-push.
- **PR creation fails.** Most commonly: permission issue with `gh auth`. Surface the error and let the user resolve; do not silently give up.
- **Target file has merge conflicts.** The skill detected an existing file to extend but git shows conflict markers. Stop, report, and let the user resolve manually.

Silent retry loops are forbidden. Report and ask.
