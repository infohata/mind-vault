# RULE_git-safety

Protected branches are `main` and the release branch (`production` or `deployment`, whichever the project uses). Everything else is a feature branch and is the agent's sandbox. The HITL gate is **merge to a protected branch**, nothing else.

Worked examples, recovery prose, the full standard branch workflow, and commit-message format live in [`../docs/rules/RULE_git-safety-rationale.md`](../docs/rules/RULE_git-safety-rationale.md). Load that file when adjudicating an edge case or when the user asks for the full workflow.

## The Hard Rules

### 1. NEVER COMMIT TO MAIN

- Always work on feature branches: `git checkout -b feature/name origin/main`.
- Never `git checkout main` with intent to commit.
- If accidentally on main: `git stash`, create a feature branch, `git stash pop`.
- `main` is off limits for direct push, force-push, rewriting history, and direct merge.

### 2. NEVER MERGE OR PUSH INTO A PROTECTED BRANCH

The forbidden operation is writing to a protected branch, not the `git merge` command itself. Before any merge/rebase ask: *which branch's tip is about to move?* If the answer is a protected branch, abort.

**On protected branches the agent:**

- ❌ Never commits directly.
- ❌ Never runs `git merge <feature>` while checked out on a protected branch.
- ❌ Never runs `gh pr merge`, GitHub API merges, or browser-click merges.
- ❌ Never force-pushes, `git reset --hard`, or rewrites history.
- ✅ Creates PRs with `gh pr create` and hands the URL back to the human.
- ✅ Cleans up local feature branches **after** the human has merged upstream.

**Forward-sync IS allowed** — feature-branch tip moves, protected tip doesn't:

- ✅ `git merge origin/main` while on a feature branch.
- ✅ `git pull --rebase origin main` on a feature branch.
- ✅ `git rebase origin/main` on a feature branch.

When asked to merge to a protected branch, decline with this template:

```text
I've created/updated PR #X at [URL].

To merge:
  1. Review the changes on GitHub
  2. Click the green 'Merge pull request' button
  3. Confirm the merge

Let me know once it's merged and I'll handle local cleanup.
```

**Being asked is not authorization.** A user saying "merge" does not lift Hard Rule 2 — protected-branch merge is a *human action*, so hand back the button (above). The one exception is the deliberate break-glass in the enforcement hook below (`GIT_SAFETY_ALLOW=1`), which the agent never adds on its own.

**Structural enforcement (backstop for this rule).** This rule is behavioural context and can be rationalised away exactly when it matters (real incident: an agent merged to protected `main` with the rule loaded, reading a user "merge" as license). Mind-vault ships a `PreToolUse(Bash)` hook — [`hooks/block-protected-branch-writes.py`](../hooks/block-protected-branch-writes.py), wired in [`hooks/hooks.json`](../hooks/hooks.json) — that **denies** `gh pr merge`, API merge writes, and direct/force/bare pushes to a protected branch at the tool layer, so a lapse can't move a protected tip. Forward-sync, feature-branch pushes, and `gh pr create` pass through. Symlink-channel installs register it by hand in `~/.claude/settings.json`. The *why* (behavioural rules need structural backstops for irreversible ops) is in [`../docs/rules/RULE_git-safety-rationale.md`](../docs/rules/RULE_git-safety-rationale.md).

### 3. Feature branches — agent has normal commit authority

On any non-protected branch the agent commits freely. **No per-commit approval prompt.** The human reviews at the PR, not per-commit.

**Allowed without asking:** commit as work progresses; amend, squash, rebase interactively; reset, cherry-pick, stash, delete local feature branches; `git push --force-with-lease` on a feature branch the agent owns.

**Still forbidden (even on feature branches):**

- ❌ `--no-verify`, `--no-gpg-sign`, or any flag that bypasses hooks or signing, unless the user explicitly asks.
- ❌ Plain `git push --force` — always use `--force-with-lease`.
- ❌ Force-pushing to a branch with an open PR *without informing the human first* — it invalidates existing review threads.
- ❌ Deleting or resetting a branch the agent doesn't recognise — it may be someone else's in-progress work.
- ❌ Committing files that likely contain secrets (`.env`, `credentials.json`, private keys). Warn the user if a commit includes any.

### Compound-command gotcha: the "main" over-match in *string-level* guards

A guard that matches the **whole Bash command string** can false-positive on a **legitimate
feature-branch operation** when the literal `main` appears elsewhere in a chained command —
classically `git push origin <feature> && gh pr create --base main …`, or any `… --base main …`
batched after a push. The block kills the **entire** invocation (so an earlier `git add`/`git commit`
in the same chain doesn't run either), reporting a protected-branch push that you never intended.

The string-level matchers that trip this are the **tool-permission layer** (settings.json allow/deny
patterns match over the full command string) and **outdated naive guards**. Mind-vault's shipped hook
(`hooks/block-protected-branch-writes.py`) is **per-segment and quote-aware** — it ALLOWS this chain
(covered by its self-test), so if it appears to fire here the plugin is stale: update it rather than
working around it.

**Fix: split the push and the PR-create into separate Bash invocations** — push the feature branch
alone, then run `gh pr create --base main …` on its own. Universally safe, and single-purpose calls
match permission allowlists cleanly anyway. Don't reach for the break-glass override
(`GIT_SAFETY_ALLOW=1`) — the operation is genuinely allowed, and a permission-layer match wouldn't
honour it anyway. (Same applies to any command that legitimately names `main`/`master`/`production`
as a *target-of* rather than a *push-to*.)

### Fold small work into the open PR — do not stack a second one

**Default: if a PR for this work is open and unmerged, extend it.** Push the follow-up commit
onto its branch rather than opening a second PR — and never branch a new PR off an open PR's
branch. This binds hardest on exactly the work most likely to get its own PR by reflex: doc
finalization, CHANGELOG/version fixes, review-driven fixes, scrub sweeps, "just one more nit".

The cost is not merge count, it is **conflicts on append-at-top shared files**. `CHANGELOG.md`,
`docs/ideas/README.md`, and the monthly devlog are all written by inserting at the top, so two
open branches that each add a section conflict on the same lines by construction — and the
second one conflicts again after every rebase. One PR carrying both edits has no conflict at
all. Stacking also exposes the strand-off-base hazard documented below.

**A separate PR is right when** the work is genuinely independent of the open one (a different
IDEA, an unrelated bug), when a large mechanical sweep would swamp review of the substantive
change, or when the two must ship on different cadences. "It felt tidier" is not one of those —
neither is "the first PR was already reviewed", which is an argument for one more review cycle,
not for a second PR.

### Stacked PRs: merging in quick succession can strand the dependent PR off-base

When PR **B** is opened with PR **A**'s branch as its base (a *stacked* PR — B's diff is only clean on
top of A), the platform auto-retargets B to A's base (`main`) **when A's head branch is DELETED** —
not on the merge itself (auto-delete-on-merge makes deletion — and so the retarget — follow the merge
near-instantly; without auto-delete it never fires at all). Merge A and then B within the same short
window (seconds) and B can merge into **A's now-obsolete branch instead of `main`** — because at
click-time B's base was still A's branch. The result: B's commits land off `main` entirely (into a
dangling branch), the work looks merged in the PR UI but **`main` never receives it**, and nobody
notices until a later `git ls-tree origin/main` / "where did that file go?" moment.

Diagnose with `gh pr view <B> --json baseRefName,mergeCommit` — `baseRefName` still showing A's branch
means it never retargeted, and `git merge-base --is-ancestor <mergeCommit-oid> origin/main` non-zero
means the merged result is **not** on main. (Test the **merge commit**, not B's branch tip — a squash-
or rebase-merged tip is never an ancestor of `main`, so the tip test false-alarms on healthy PRs.)
**Recover** by cherry-picking B's reviewed commits onto a fresh `origin/main`-based branch and opening
a new PR that targets `main` directly — do **not** try to re-merge the stranded branch.

**Avoid it:** after merging A, confirm B's base actually flipped to `main` (PR UI / `baseRefName`) —
or force it deterministically with `gh pr edit <B> --base main`, or rebase B onto `main` first so it's
no longer stacked — before merging B. Never batch "merge A, merge B" as one rapid action.
