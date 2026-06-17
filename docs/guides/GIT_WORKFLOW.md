# Git workflow

How mind-vault structures git work across one-IDEA-at-a-time sprints and multi-IDEA cohorts. The hard rules live in [`rules/RULE_git-safety`](../../rules/RULE_git-safety.md) (auto-loaded every session). This doc is the *why* and the *when*.

## The cardinal rule

**`main` (and any `production` / `deployment` branch) is off-limits to the agent for writes.** The agent never commits to, merges into, or force-pushes a protected branch. The agent's job ends at "PR open, here's the URL — please review and merge." This is the **HITL merge gate** and it's the only HITL gate in the workflow.

Everything else is the agent's sandbox.

## Branch per IDEA

One feature branch per IDEA, named `<type>/<idea-slug>` or `<type>/idea-NNN-<slug>`:

```
feat/idea-003-version-tag-automation
docs/idea-004-onboarding-walkthrough
fix/idea-007-htmx-pagination-bug
chore/idea-011-deps-bump-2026-05
```

The branch is born from `origin/main` (not a stale local main):

```bash
git checkout -b feat/idea-NNN-<slug> origin/main
```

This pattern is enforced by `/work` and `/sprint-auto`. The IDEA-to-branch link is what makes the cohort traceable months later (`git log --grep IDEA-NNN` shows the full work history).

## Inside the feature branch — agent has normal commit authority

No per-commit approval. The agent commits as work progresses, amends, squashes, rebases freely. The human reviews **at the PR**, not per-commit.

What the agent *will* respect on feature branches:

- ✅ `git commit` whenever a logical unit is done.
- ✅ `git rebase origin/main` to keep current.
- ✅ `git push --force-with-lease` after a rebase (never plain `--force`).
- ❌ Never `--no-verify` or `--no-gpg-sign` (hook bypass).
- ❌ Never delete a branch the agent doesn't recognise — it may be someone else's WIP.

## Independent review — Bugbot, Copilot, Claude, or any subset

mind-vault supports three external review engines and one local fallback:

| Engine | Trigger | Wait | Cost |
| --- | --- | --- | --- |
| **Cursor Bugbot** | `tools/bugbot_retrigger.sh <PR>` posts a `bugbot run` comment | 1–10 min | Cursor subscription |
| **GitHub Copilot** | `tools/copilot_retrigger.sh <PR>` (wraps the canonical `gh pr edit --remove-reviewer @copilot ; sleep 1 ; gh pr edit --add-reviewer @copilot` sequence — `;` not `&&` so the add step still fires even if `@copilot` wasn't currently requested) | 2–15 min | GitHub Actions minutes (from Jun 2026) |
| **Claude Code Review** | **Push-triggered** — `claude-code-action@v1` + `code-review` plugin auto-runs on every push, so a fix push IS the retrigger; `tools/claude_retrigger.sh <PR>` (posts `@claude review once`) is a bootstrap **fallback** only | minutes (GitHub Actions job) | Claude subscription / OAuth (no per-review SKU) |
| **AGENT_curator** | Local Claude pass before push | Seconds | Free; weakest gate |

> ⚠️ **Claude here = the `claude-code-action` + `code-review` plugin, NOT Anthropic's managed Code Review GitHub App.** It posts inline + summary comments off a GitHub Actions job — there is no named check-run or severity JSON. See [`skills/review-loop/references/engine-claude.md`](../../skills/review-loop/references/engine-claude.md).

### Single-engine flow

```text
/work …          # feature branch, commits, push
/review-loop <PR> <engine>   # semi-autonomous fix-rerun cycle
```

Each loop polls the engine's GitHub API surface, classifies findings into tiers (auto-fix / approve-then-fix / escalate), batches fixes per review-cycle into ONE commit, retriggers, repeats until CLEAN or a hard bound trips.

### Multi-engine flow

Use a comma-separated engine list e.g. `/review-loop <PR> bugbot,copilot,claude` (the canonical multi-engine entry) — the loop **syncs each cycle**: wait for the slowest engine, batch findings from ALL engines into one fix commit, push once, retrigger each. Prevents the failure mode where independent single-engine sessions' pushes invalidate each other's pending reviews — always drive all engines through the one `/review-loop` session. (claude **is** retriggered after a fix push like the other engines, *once it has posted its first review*: the push's `synchronize` auto-run skip-no-ops once claude has already reviewed the PR, so the explicit `claude_retrigger.sh` is what forces a fresh verdict on the fix. The lone exception is a still-in-flight **first** claude review — then the auto-run carries it and the explicit retrigger is withheld to avoid a double-run. See [`skills/review-loop/references/engine-claude.md`](../../skills/review-loop/references/engine-claude.md) § A7.)

Escape hatches when one engine stalls or service-errors are codified in [`skills/review-loop/references/multi-engine-sync.md`](../../skills/review-loop/references/multi-engine-sync.md) — see the trade-off escape-hatch table.

**When to multi-engine**: high-stakes PRs (auth, payments, migrations), or any PR where one engine alone has historically missed things in your repo. The engines have complementary blind spots.

## Force-push discipline

- ✅ `git push --force-with-lease` after a rebase on a feature branch the agent owns. The `--force-with-lease` form protects a collaborator's newer commits — plain `--force` overwrites them silently.
- ❌ Never force-push to a protected branch.
- ❌ Never force-push to a branch with an *open PR* without telling the human first — it invalidates pending review threads (Bugbot / Copilot / Claude have to re-scan from scratch).

If a review-loop is mid-cycle and you need to rebase to resolve a conflict, push the rebase, then post a comment on the PR saying "rebased — pending reviews will need to re-fire" so any human reviewer isn't confused by missing inline threads.

## Integration branches — multi-IDEA cohorts

When a sprint runs **multiple IDEAs in parallel** (`/sprint-auto` overnight, for example), per-IDEA PRs need to integrate **before** any of them merges to `main`. Otherwise the first IDEA to merge forces every subsequent IDEA to forward-sync, re-review, and possibly conflict-resolve — each at the cost of a review cycle.

### The pattern (sprint-auto v3.2)

```
                                                      ┌─→ per-IDEA PR #A (base: sprint-2026-05)
                                                      │
main ── sprint-2026-05 (integration branch) ──────────┼─→ per-IDEA PR #B
                                                      │
                                                      └─→ per-IDEA PR #C

                                                                ↓ (sequential merge into integration)

main ←── [INTEGRATION] PR — sprint-2026-05 → main ←── integrated state of A + B + C + compat patches
```

- Per-IDEA PRs target the **integration branch** (`sprint-2026-05`), not `main`.
- Each per-IDEA PR is reviewed in isolation against the integration branch — the engine sees clean diffs.
- An `[INTEGRATION]` PR targets the parent (`main`). This is the SINGLE PR the human reviews + merges.
- Compatibility patches (caused by IDEA-A's surface meeting IDEA-B's) live as visible commits on the integration branch — not hidden in per-IDEA branches.

### Why this beats "merge per-IDEA, forward-sync the rest"

- **No per-PR re-review on forward-sync** — every other IDEA's PR would need to re-trigger Bugbot/Copilot after the first merge. Integration branches eliminate that.
- **Per-IDEA PRs stay IDEA-isolated** — reviewer sees only IDEA-A's changes when looking at PR-A, not "IDEA-A's changes plus IDEA-B's that already merged."
- **One HITL gate, not N** — the human reviews ONE integration PR, not N forward-synced PRs.
- **Bisect-friendly** — once `main` gets the squash-merge of the integration PR, the sprint lands as one commit with a clean per-IDEA history available via `git log sprint-2026-05`.

### When NOT to use an integration branch

- Single IDEA, single PR — adds ceremony for no benefit.
- IDEAs that genuinely don't touch the same surfaces — forward-sync is cheap.
- Project lacks the GitHub permissions to create new long-lived branches.

## Forward-sync allowed direction

The forbidden operation is writing *to* a protected branch, not the `git merge` command itself.

✅ **Allowed** on a feature branch:
```bash
git merge origin/main           # bring upstream changes into the feature
git pull --rebase origin main   # same, rebase variant
git rebase origin/main          # same, replays your commits on top
```

❌ **Forbidden** (write *to* protected):
```bash
git checkout main && git merge feature/xyz   # writes to main
git push origin feature:main                 # writes to main
gh pr merge                                  # writes to main
```

The distinguishing question before any merge: *which branch's tip is about to move?* Protected tip → abort. Feature tip → safe.

## Conventional commit messages

```text
type(scope): brief description (≤72 chars)

Optional explanation of WHY, wrapped at 72.
```

**Types**: `feat`, `fix`, `docs`, `refactor`, `style`, `chore`, `test`, `build`, `ci`, `perf`.

Trailing co-author line for agent-driven commits:

```text
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

## After merge — local cleanup

The agent waits for the human's "merged" signal, then:

```bash
docker compose ps                       # any running containers?
docker compose down                     # if yes — stop before checkout
git checkout main
git pull
git branch -d feat/idea-NNN-<slug>      # safe — git refuses if unmerged
# or:
git branch -D feat/idea-NNN-<slug>      # squash-merged branches need -D
                                        # (git doesn't recognise the squash as a merge)
```

The container-stop step is non-obvious but important: checking out a stale branch while containers run risks schema/migration drift between the running DB and the checked-out code.

## What can go wrong

| Symptom | Cause | Recovery |
| --- | --- | --- |
| Accidentally on `main` with staged changes | Forgot to branch | `git stash && git checkout -b feat/<slug> origin/main && git stash pop` |
| Pushed to `main` directly | Rule violation | **STOP**. Tell the human. Don't push more. They decide whether to `git reset --hard origin/<good-sha>` and re-push, or cherry-pick to a feature branch. |
| Force-pushed without `--lease` and lost a collaborator's commit | Hard rule violated | Recoverable via `git reflog` on the collaborator's machine; treat as an incident, file a `/compound` so it doesn't repeat. |
| Review bot stuck "in_progress" >15 min | Engine hung (see the escape-hatch table in [`multi-engine-sync.md`](../../skills/review-loop/references/multi-engine-sync.md)) | Proceed with the other engine(s) under multi-engine mode; otherwise hand back to user. |
| Integration branch builds locally but per-IDEA PRs disagree | Compatibility patch needed | Add a commit *on the integration branch* (NOT inside a per-IDEA PR) — that's exactly what compat commits are for. |

## See also

- [`rules/RULE_git-safety.md`](../../rules/RULE_git-safety.md) — the always-on hard rules.
- [`rules/RULE_rename-before-drop.md`](../../rules/RULE_rename-before-drop.md) — multi-commit rename sequencing.
- [`skills/review-loop/SKILL.md`](../../skills/review-loop/SKILL.md) — shared Phase 0/1/2/3/4 orchestrator; [`commands/review-loop.md`](../../commands/review-loop.md) is the command entry. Engine specifics live in `skills/review-loop/references/engine-{bugbot,copilot,claude}.md`.
- [`skills/sprint-auto/SKILL.md`](../../skills/sprint-auto/SKILL.md) — integration-branch pattern in full.
- [WORKTREE_PRACTICES.md](WORKTREE_PRACTICES.md) — parallel-worktree counterpart.
