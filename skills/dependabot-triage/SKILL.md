---
name: dependabot-triage
description: Triage and batch-merge accumulated Dependabot PRs in multi-requirements-file Python repos (web + lsp + dev + per-workspace) — diff-based duplicate detection across the root vs per-workspace ecosystems, risk-tier batching for git-bisect cleanliness, worktree-isolated verification, live-staging smoke, post-merge forward-sync of remaining branches. TRIGGER when the user says "review dependabot PRs", "merge dependabot batch", "dependabot sweep", "what to do with these dep PRs", "clean up the dep updates", or asks for a roadmap merging multiple `chore(deps)` PRs.
license: MIT
metadata:
  author: mind-vault
  version: '1.0'
---

# dependabot-triage

A workflow for processing 5–20 accumulated Dependabot PRs as one coherent sweep instead of one-PR-at-a-time fatigue. The non-obvious pieces are (1) **two PRs touching the same package are not necessarily duplicates** when the repo has multiple requirements files served by separate dependabot ecosystems, and (2) **risk-tier batching with one commit per dep** preserves `git bisect` even when the PR ships a bundle.

## When to use

**TRIGGER when:**

- A pile of Dependabot PRs has accumulated and the user asks for a roadmap to merge them.
- Two PRs look like duplicates but the user is unsure whether to close one.
- A version-scheme jump (e.g. pre-1.0 → post-1.0, or `0.0.x → 1.x.x`) is mixed in with low-risk patch bumps and the user wants to know how to split them.
- A dep PR floor-bumps a package that's actively used somewhere subtle (Vertex / OpenAI / Stripe / etc.) — needs targeted smoke beyond the test suite.

**SKIP when:**

- Single Dependabot PR with no version-scheme jumps and no actively-used SDK — just merge it.
- Repo has only one requirements file and one ecosystem — the multi-ecosystem nuance doesn't apply, simpler triage.
- Security-only batch where every PR must merge same day — risk-tier batching is overkill, ship them as one or sequentially.

## Pattern

### 1. Survey

```bash
gh pr list --author "app/dependabot" --state open --limit 100 \
  --json number,title,headRefName,mergeable,labels
```

For each PR, capture: number, title, branch path (`dependabot/pip/<pkg>...` vs `dependabot/pip/<workspace>/<pkg>...`), files touched, diff size. The branch path tells you which dependabot ecosystem opened it.

### 2. Detect duplicates by diff content, not titles

Multi-requirements-file repos typically configure two or more `pip` ecosystems in `.github/dependabot.yml`:

```yaml
- package-ecosystem: "pip"
  directory: "/"                    # → root: requirements-web.txt, requirements-lsp.txt, …
- package-ecosystem: "pip"
  directory: "/<workspace>"         # → workspace: <workspace>/requirements-*.txt
```

When both ecosystems see the same package needing a bump, you get **two PRs that look identical by title** but are produced by independent ecosystems. Sometimes they're true duplicates (same diff, same file). Sometimes they're not (root PR bumps web + lsp + workspace; workspace-PR bumps only the workspace file).

**The hard rule: never close a duplicate by title alone.** Diff every candidate pair:

```bash
gh pr diff <PR_A> > /tmp/A.diff
gh pr diff <PR_B> > /tmp/B.diff
diff /tmp/A.diff /tmp/B.diff
```

Close only when one diff is byte-identical to the other, or a strict superset (the larger diff includes every line of the smaller diff and nothing the smaller PR uniquely contributes is omitted).

The closing comment should cite the canonical PR carrying the change forward: `Closing as duplicate of #X — both update <pkg> to <ver> in <file> with identical diffs.`

### 3. Conflict map (single-PR feasibility)

For each unique PR, record the files it touches. Build a per-file table:

| File | PRs touching it | Lines collide? |
|---|---|---|
| `requirements-web.txt` | #A, #B, #C | No (different deps) |
| `<workspace>/requirements.txt` | #A, #D, #E | No |

If no two PRs touch the same line of the same file, a bundled merge is conflict-free. Almost always the case for Dependabot — each PR floor-bumps one package on its own line.

### 4. Risk-tier classification

Slot each unique bump into one of four tiers:

| Tier | What | Treatment |
|---|---|---|
| 🟢 Patch | `2.0.1 → 2.0.2`, security-floor patch | Bundle freely. |
| 🟢 Minor | `>=0.45 → >=0.46` | Bundle freely. |
| 🟡 Moderate | Many minor versions (e.g. `>=0.100 → >=0.136`), but pre-1.0 still pre-1.0 | Bundle if surface area is small; isolate if the package is load-bearing. |
| 🔴 High | Version-scheme jump (pre-1.0 → 1.x), API-breaking range, library actively used in subtle code paths (SDKs, parsers, embedders) | Isolate into its own PR. |

The dividing line for isolation is **bisectability**: if a regression appears post-merge, can `git bisect` point at the responsible commit (or PR) without ambiguity? If the high-risk bump is bundled with five low-risk ones in a single squash-merge, bisect resolves to the bundle and the operator has to manually un-bundle.

### 5. Bundle layout — one commit per dep

Even when bundling 5 deps into a single PR, use **5 separate commits** (one per dep):

```text
chore(deps): bump xlrd 2.0.1 → 2.0.2
chore(deps): bump uvicorn[standard] >=0.45.0 → >=0.46.0
chore(deps): bump requests >=2.32.5 → >=2.33.1
chore(deps): bump markdown >=3.7 → >=3.10.2
chore(deps): bump fastapi >=0.100 → >=0.136.1
```

Order low-to-high risk so the riskiest commit is on top — if a regression surfaces post-merge, `git revert HEAD~N..HEAD` peels off the riskier ones first. Every commit message mentions `Closes #<original-PR>` so the bundle PR auto-closes the dependabot PRs on merge.

The PR description lists every closed PR — `gh pr merge` honours `Closes` lines from any commit message in the PR.

**Merge-strategy gotcha — non-negotiable.** Per-dep commits only preserve `git bisect` resolution if the merge into `main` keeps them as separate commits. GitHub's default *Squash and merge* collapses every commit in the PR into a single squash-commit, defeating the entire bisect benefit. For a bundled dep PR specifically, the operator must:

- Use **Create a merge commit** (branch's commits land on `main` verbatim, plus a merge commit), OR
- Use **Rebase and merge** (branch's commits land on `main` linearly, no merge commit).

`gh pr merge --merge` (merge commit) or `gh pr merge --rebase` (rebase) — never `gh pr merge --squash` for dep-bundle PRs. If the repo is configured to allow only squash-merge, change the per-PR setting via the GitHub web UI dropdown before clicking merge, or escalate to a maintainer who can. The bisect benefit and the per-dep commit discipline are coupled; if the merge strategy can't be controlled, the per-dep commits are theatre — fall back to a single squashed commit and accept the loss of post-merge bisect.

### 6. Worktree-isolated verification (per RULE_parallel-worktree-docker)

Each PR (bundle and isolated-high-risk) gets its own worktree:

```bash
git worktree add ../<repo>-deps-<slug> -b chore/dependabot-<slug>-YYYY-MM origin/main
```

Per-worktree:

- Sentinel `.env` (never copy real secrets except where targeted smoke needs them — for SDK floor bumps that exercise real APIs, copy the credentials file bytewise without reading: `cp credentials.json <worktree>/path/credentials.json`).
- `docker-compose.override.yml` with port offset (+30000 / +50000 etc.) and non-overlapping subnet (172.30.0.0/16 etc.).
- `make build` (cache-aware — pip layer is invalidated automatically because requirements file content hash changed; `--no-cache` only needed if a prior build with the same hash got a silent skip).
- `make migrate` and `make test`.
- Targeted smoke per the bumped SDK (e.g. real Vertex `embedContent` round-trip for `google-genai`; real PDF extraction for `pymupdf4llm`).

**Resource ceiling**: two parallel test stacks on a 16 GB box hits CPU contention with each running `pytest -n 8`. Sequential is faster end-to-end. Cooperative-pause technique: kill the lower-priority stack's `pytest` mid-flight (`docker compose stop web celery` on the worktree releases its CPU), let the higher-priority finish uncontended, then resume.

### 7. Live-staging smoke

After the bundle PR merges, switch staging to the next isolated-high-risk PR's branch:

```bash
make stop                                    # avoid migration drift on branch switch
git fetch origin <pr-branch>
git checkout <pr-branch>
make build                                   # pip layer rebuilds since deps changed
make start
make migrate                                 # idempotent
```

Hand back to the user for live verification. Per `RULE_git-safety` the human reviews + merges; the agent never does.

### 8. Post-merge forward-sync of remaining branches

When the first PR merges, the remaining isolated PRs are now behind. Forward-sync each:

```bash
git fetch origin main                        # critical — without this, origin/main is stale and the merge silently misses the just-landed merge commit (or rebased / squashed lineage, depending on which strategy the bundle PR used)
git checkout <next-pr-branch>
git merge --no-edit origin/main
git push origin <next-pr-branch>             # regular push, no force — additive merge commit
```

The `git fetch origin main` step is non-optional. The remote ref `origin/main` is local cache that only updates on fetch; web-UI merges on GitHub do not propagate to your local view automatically. Skip the fetch and the merge becomes a no-op (or worse: a partial sync against a stale snapshot that masks a real conflict you'll only discover at merge time).

Forward-sync is **always allowed** by `RULE_git-safety` (the feature branch's tip moves; main's doesn't). A regular `git push` keeps PR review threads intact; only `--force-with-lease` would invalidate them.

### 9. Documentation wrap

Open a small docs PR (or fold into the still-open dep PR) covering:

- Devlog entry in the current month's `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md` — what merged, what shipped isolated, operational lessons.
- Live-doc references to bumped packages (setup guides, validation snippets, version pins) — refresh stale "ad-hoc install" notes that predate the package landing in requirements.
- Skip historical references (archived IDEAs, past deployment-session files) — frozen by convention.

If only one isolated PR remains and its review window is short, fold the docs commit into that PR; otherwise a standalone `chore/docs-dep-updates-YYYY-MM` branch off main keeps it independently mergeable.

## Anti-patterns

- **Title-based duplicate triage.** "Same package, same version → duplicate" is wrong when ecosystems differ. Diff comparison is the only valid test.
- **Mass-bundle including version-scheme jumps.** Bisect ambiguity wipes out the audit trail when the high-risk bump regresses.
- **Single-commit bundle PR.** Per-dep commits preserve `git bisect` resolution post-merge — but **only** if the operator picks merge-commit or rebase-merge as the merge strategy. GitHub's default *Squash and merge* collapses per-dep commits into one squash-commit and silently negates the entire bisect benefit (see step 5's merge-strategy gotcha). The two pieces — per-dep commits *and* non-squash merge — are coupled; doing one without the other is theatre.
- **Real `.env` copy into a worktree.** Worktree must use sentinels (per `RULE_parallel-worktree-docker`); only the credentials file backing a specific SDK smoke gets copied bytewise — and only into the worktree where that smoke runs.
- **Skipping live-staging for SDK bumps.** Test suites typically mock SDK clients. Real-API smoke against the upgraded floor is the only signal that the new SDK shape works in production.
- **Force-pushing the dep PR mid-review.** Forward-sync via `git merge origin/main` + regular push, not rebase + force-push. Review threads survive.

## Provenance

Compounded from the teisutis 2026-04-28 dependabot sweep — 9 open PRs triaged into 2 dups closed, 1 bundled merged PR (#390), 1 isolated PR pending merge (#391), 1 docs commit folded post-feedback. The duplicate-detection nuance specifically traces to feedback during that sweep when the user flagged "we have multiple requirements files now, don't mix duplicates up".

## Composes with

- [`rules/RULE_parallel-worktree-docker.md`](../../rules/RULE_parallel-worktree-docker.md) — the worktree + override-file + sentinel-env mechanics this skill leans on for verification isolation.
- [`rules/RULE_git-safety.md`](../../rules/RULE_git-safety.md) — forward-sync is allowed; merge-into-main is HITL.
- [`skills/wrap/SKILL.md`](../wrap/SKILL.md) — for the docs sweep at step 9 when the dep sweep was non-trivial enough to deserve a devlog entry.
- [`skills/bugbot/SKILL.md`](../bugbot/SKILL.md) — when a bundle PR's review surfaces issues (rare for dep bumps, but the bugbot loop applies if invoked).

---

**Last Updated**: 2026-04-28
