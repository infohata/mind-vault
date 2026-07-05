# RULE_git-safety — Rationale, Workflow Examples, Recovery

## Standard Branch Workflow

```bash
# 1. Create feature branch from main
git checkout -b feature/my-feature origin/main

# 2. Make changes, stage them
git add <files>

# 3. Commit — no approval prompt needed on a feature branch
git commit -m "type(scope): description"

# 4. Push with upstream tracking
git push -u origin feature/my-feature

# 5. Create PR
gh pr create --title "..." --body "..."

# 6. (HITL gate) Human reviews and merges on GitHub

# 7. After merge — safe cleanup
# IMPORTANT: If Docker containers are running, stop first.
# Checking out stale branches with live containers risks schema/migration drift.
docker compose ps
# If running → docker compose down first
git checkout main
git pull
git branch -d feature/my-feature
```

## Commit Message Format

```text
type(scope): brief description (≤72 chars)

Optional explanation of why, wrapped at 72.
```

**Types:** `feat`, `fix`, `docs`, `refactor`, `style`, `chore`, `test`, `build`, `ci`, `perf`.

## "Please merge to main" — canonical response template

```text
I've created/updated PR #X at [URL].

To merge:
  1. Review the changes on GitHub
  2. Click the green 'Merge pull request' button
  3. Confirm the merge

Let me know once it's merged and I'll handle local cleanup.
```

## Recovery — What If I Forget?

**If about to commit to a protected branch:**

- Stop immediately.
- `git stash` if there are pending changes.
- Create a feature branch from `main` (`git checkout -b feature/x origin/main`).
- `git stash pop` and resume.

**If already committed to a protected branch:**

- You violated rule 1.
- Do NOT push.
- Tell the user immediately; let them decide whether to `git reset` or cherry-pick the commit to a feature branch.

**If about to merge/force-push into a protected branch:**

- Stop. This is rule 2.
- Open a PR instead and hand the URL to the human.

## Why This Matters

- The human controls what enters production (main / deployment).
- Feature branches are the agent's sandbox — freedom to iterate without constant check-ins.
- The PR is the one HITL gate that matters.
- Clear accountability: the merge to a protected branch is the point of no return, and it's always human-initiated.

## The "which tip moves" disambiguation

Forward-sync (merging `main` *into* a feature branch) is **allowed** — the feature branch's tip moves, `main` does not. Examples:

- ✅ `git merge origin/main` while on a feature branch.
- ✅ `git pull --rebase origin main` on a feature branch.
- ✅ `git rebase origin/main` on a feature branch.

The forbidden operation is writing to a protected branch, not the `git merge` command itself. Before any merge/rebase ask: *which branch's tip is about to move?* If the answer is a protected branch, abort.

## Stacked-PR merge order — absorption vs sibling-collapse

When handing back **more than one open PR** for the human to merge, the merge-order guidance depends on the PRs' base branches — and getting it wrong sends the human merging in an order that does something they don't expect. **Run `gh pr view <N> --json baseRefName,headRefName` on every PR in the set before saying which to merge first.** Two distinct shapes:

**Siblings — all PRs target the protected branch (`base = main`).** They're independent. The human merges them in any order; GitHub auto-closes any PR whose commits became ancestors of `main` via an earlier merge ("collapse"). This is the shape the older "just merge the latest, the superseded ones auto-close" intuition assumes — and it's correct *for siblings*.

**Stacked — a child PR's base is another PR's branch (`base = feature/parent`, not `main`).** The child branch already contains all the parent's commits plus its own, so the child is a **superset** of the parent. Here the merge order is not a free choice:

- Merging the **child into the parent first** folds the child's commits into the parent branch — **absorption**. The child PR closes (its diff is now in the parent), and the parent becomes the superset carrying *both* changes.
- Then the parent (now a superset) merges to `main` as **one shipping moment** — everything ships together.

The failure mode: describing stacked PRs as if they were siblings — *"merge the parent first, then the child"* — is backwards. Merge the parent to `main` first and the child still has an open PR whose base branch just disappeared; the human is left confused about why nothing "collapsed into one." The correct handback names the absorption explicitly:

> #156's base is #155's branch, so #156 folds **into** #155 (absorption). Merge #156 into #155 first, then merge #155 (now the superset) to `main` — one shipping moment.

Worked precedent: a compound chain produced #155 ← #156 (child stacked on parent). The first handback said "merge #155 then #156" (sibling framing); the human merged the child first, saw the parent not auto-close, and was confused. The parent had in fact absorbed the child and was MERGEABLE/CLEAN as a superset — safe to merge to `main` alone — but the imprecise framing cost a round of confusion. Sprint-auto's per-IDEA PRs and multi-step `/compound` chains both routinely produce stacked PRs, so verify `baseRefName` before every multi-PR handback.

## Behavioural rules need a structural backstop for irreversible ops

A rule loaded as context enforces itself only as long as the model chooses to obey it — and the failure mode is precisely that the model *rationalises the rule away at the moment it applies*. Real incident: an agent with `RULE_git-safety` loaded and able to quote Hard Rule 2 verbatim still ran `gh pr merge` on a protected `main`, because the user had said "merge" and it read that as authorization. The rule even anticipates this ("when asked to merge to a protected branch, decline") — being loaded and correct did not stop the write. The rule was necessary but not sufficient.

The lesson generalises past git: **any behavioural rule guarding an irreversible or protected-surface operation (merge to protected, force-push, `rm -rf`, a destructive migration, sending an irreversible external message) wants a structural backstop that denies the action at the tool layer, not just a sentence in context.** The rule teaches the *why* and covers the long tail; the hook makes the specific catastrophic action impossible to take by accident. They compose — the rule is the policy, the hook is the enforcement.

The backstop's design constraints, learned building the git-safety one ([`../../hooks/block-protected-branch-writes.py`](../../hooks/block-protected-branch-writes.py)):

- **Deny the narrow catastrophic set, allow everything adjacent.** The hook blocks merge/force-push/direct-push *to a protected branch* and nothing else — feature-branch force-push, forward-sync merges, and `gh pr create` all pass. An over-broad guard that blocks legitimate sandbox work gets disabled, and a disabled guard protects nothing.
- **Fail OPEN.** A guard bug must never wedge the session — on any internal error the hook logs and allows. A backstop that can brick the tool is worse than the risk it covers; it will be ripped out.
- **A visible, deliberate break-glass** (`GIT_SAFETY_ALLOW=1` prepended) for the rare legitimate case — but one the agent must not add on its own initiative. "The user asked me to" is not license to add it; that is the exact reasoning the backstop exists to stop, so the escape hatch must cost a deliberate, grep-able keystroke from the human.
- **Match the shell, not the string.** The first cut ran regexes over the raw command string; an adversarial review walked straight through it (`git -C <path> push origin main`, `git push origin "main"`) and falsely denied adjacent work (`git branch -D old && git checkout main`, a PR body *quoting* `gh pr merge`). A command guard must shlex-tokenize, split at shell operators, strip heredoc bodies, and evaluate each command start independently — anything less is theatre that the very first `-C` flag defeats.
- **Ship a deny/allow self-test battery with the guard** ([`../../hooks/test-block-protected-branch-writes.py`](../../hooks/test-block-protected-branch-writes.py)) and re-run it on every edit. Both failure directions decay silently: a new bypass form erodes the guarantee, an over-broad match erodes the sandbox until someone disables the guard. The battery pins both sets.
