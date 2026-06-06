---
name: land
description: Merge + teardown operations — the final operational stage of the sprint workflow, after the single post-wrap review clears. Atomic-merges a review-cleared, docs-finalized PR when the target branch is non-protected per RULE_git-safety (squash-merge via `gh pr merge`; protected targets — main / production / deployment — preserve the human-merge HITL gate and get the PR URL handed back), then runs the strictly-post-merge destructive worktree/volume teardown (`docker compose down -v`, `git worktree remove`, `git branch -d`). Three modes, auto-detected: `/land NNN` pre-merge = atomic merge then teardown in one pass; `/land NNN` post-merge (PR already merged) = teardown only; `/land --integration <batch-iso>` = sprint-auto v3.2 batch teardown (integration worktree + branch + every per-IDEA worktree/branch). Opens with a precondition guard (pre-merge merge branch only) that refuses to merge un-wrapped work — pointing at `/wrap NNN` — so docs are always finalized before the merge. Splits the merge/teardown operations out of `/wrap` (which keeps documentation finalization); the two were fused under one trigger with different timing, HITL gates, and blast radius.
license: Apache-2.0
metadata:
  author: mind-vault
  version: '1.0'
---

# land

The operational close of the sprint workflow — the step that ships a review-cleared, docs-finalized PR and reclaims its disposable infrastructure. Everything destructive or irreversible about concluding an IDEA lives here, separated from `/wrap` (which is non-destructive documentation finalization).

**Canonical chain:** `/idea → /plan → /work → /wrap (docs) → /review-loop → /land (merge) → /compound`. `/land` is the named merge stage — what used to hide behind `/wrap --scope=full`. The single `/review-loop` runs over the wrapped (docs-finalized) PR, then `/land` merges and tears down.

**Two operations, three modes.** The merge is *pre-merge* (it performs the squash-merge); teardown is *post-merge* (destructive, requires the PR to have landed). `/land` mode-detects which applies:

- **`/land NNN` pre-merge** (PR open) — atomic merge on a non-protected target, then (since the merge unblocks teardown) teardown in the same pass. Protected target → no merge, hand back the PR URL.
- **`/land NNN` post-merge** (PR already merged) — teardown only. The merge already happened (human-clicked, or a prior `/land` on a protected target); this reclaims the worktree.
- **`/land --integration <batch-iso>`** — sprint-auto v3.2 batch teardown (no merge, no docs): tear down the integration worktree + branch + every per-IDEA `auto/<slug>` worktree/branch.

## When to use

**TRIGGER when:**

- A PR has cleared `/review-loop` at its docs-finalized (post-`/wrap`) state and is ready to merge — `/land NNN`.
- A PR merged (human-clicked or protected-target) and a parallel worktree/stack still needs teardown — `/land NNN` post-merge.
- A sprint-auto v3.2 batch's `[INTEGRATION]` PR has merged and the batch worktrees need reclaiming — `/land --integration sprint-auto-<batch-iso>`.
- Phrasings: "merge it", "land the PR", "ship the IDEA", "tear down the worktree", "clean up the sprint stack".

**SKIP when:**

- Docs aren't finalized yet — run `/wrap NNN` first (the precondition guard will refuse anyway).
- The review loop hasn't cleared — merging unreviewed code is never `/land`'s job.
- The target branch is protected AND you only want docs — that's `/wrap`, not `/land`.

## Mode detection (first action each invocation)

```bash
# 0. Batch-teardown invocation? `/land --integration sprint-auto-<batch-iso>` is
#    a distinct post-merge batch mode — NOT a per-IDEA merge. SHORT-CIRCUIT: if it
#    matches, jump to § `--integration` mode (teardown only; no merge, no guard).
case "$*" in *--integration*) MODE=integration ;; esac
if [ "$MODE" = integration ]; then
    : # → § `--integration` mode; skip the rest
else
    # 1. PR state for the current branch's PR (or the explicit PR number arg).
    pr_state=$(gh pr view "${PR_OR_BRANCH}" --json state --jq '.state')
    #   OPEN    → pre-merge: precondition guard, then atomic merge, then teardown.
    #   MERGED  → post-merge: teardown only (skip guard + merge).
    #   CLOSED  → refuse: branch abandoned; nothing to land.
fi
```

## Precondition guard (pre-merge merge branch ONLY)

Before merging an OPEN PR, confirm docs are finalized — `/land` must never merge un-wrapped work:

1. IDEA frontmatter is `status: complete` (the `/wrap` Step 2 flip ran).
2. The devlog/CHANGELOG entry for this IDEA exists.
3. The ideas-index entry moved out of a priority/In-Progress section into References — Implemented.

Any check fails → **refuse**, print: `Docs not finalized — run /wrap NNN first, then re-run /land NNN.` No override flag. The guard is reversible (run `/wrap`, re-run `/land`), so refusing is the safe default.

**The guard runs ONLY in the pre-merge merge branch.** Post-merge teardown and `--integration` batch teardown SKIP it — there is nothing to merge, and `--integration` operates on a sprint-auto batch whose per-IDEA devlog entries are *deliberately deferred* to the S11.7 batch wrap, so a devlog-existence check there would false-refuse every batch.

## Atomic merge (pre-merge, non-protected target)

**Fires when** the PR is OPEN and its target branch is **non-protected** per [`RULE_git-safety`](../../rules/RULE_git-safety.md). Protected targets (`main` / `production` / `deployment` — the project decides which) ALWAYS require a human merge: `/land` stops, hands back the PR URL. Non-protected targets (sprint cohort `sprint/<topic>`, integration `integration/sprint-auto-<batch>`, any feature branch) are agent-authority for `gh pr merge`.

The HITL gate is *protected-branch* merge, not *every* merge — exactly where `RULE_git-safety` § 2 puts it. Mechanics — protected-branch detection, pre-merge review re-clearance (the wrap commits moved HEAD, so re-confirm the loop's clean SHA == HEAD), squash-merge sequence, permission-denial handling, deployment-branch override — are in [`references/ATOMIC_MERGE.md`](references/ATOMIC_MERGE.md). Read that reference when this step fires.

## Teardown (POST-MERGE ONLY, destructive)

**Fires when** the PR has merged (this `/land` pass just merged it on a non-protected target, OR a prior human merge) AND the sprint ran in a parallel git worktree with its own docker-compose stack. **Skipped** when running from the primary checkout (`git rev-parse --git-common-dir` equals `.git`), when the user signalled keep-the-stack-up (`WRAP_KEEP_STACK=1` / `--keep-stack`), or when the worktree has uncommitted work.

Destructive sequence (`docker compose down -v` → `git worktree remove` → `git branch -d`) + per-file evaluation when `git worktree remove` refuses (forgotten commits, missing gitignore rules, stale ephemera, container-as-root permission residue) are in [`references/WORKTREE_TEARDOWN.md`](references/WORKTREE_TEARDOWN.md). Read that reference when this step fires. For a sprint-auto v3.2 batch, whole-batch teardown runs via `--integration` below, not the per-IDEA path.

## `--integration <batch-iso>` mode (sprint-auto v3.2 batch teardown)

A distinct post-merge invocation the human runs once after merging the single `[INTEGRATION]` PR of a sprint-auto v3.2 batch: `/land --integration sprint-auto-<batch-iso>`. Teardown-only — no merge, no doc steps, no precondition guard. Mechanics:

1. **Confirm the integration PR merged** — `gh pr list --search "head:integration/sprint-auto-<batch-iso>" --state merged` returns it. If not merged, refuse (teardown is strictly post-merge).
2. **Tear down the integration worktree + branch** — `docker compose down -v` in the integration worktree (the batch's only docker stack, port offset +30000), then `git worktree remove`, then `git branch -d integration/sprint-auto-<batch-iso>` and delete the remote branch.
3. **Tear down each per-IDEA worktree + branch** from the batch manifest — the `auto/<slug>` branches auto-closed as merged ancestors when the integration PR merged, so for each: `git worktree remove` + `git branch -d auto/<slug>`.

The destructive-sequence + refusal mechanics in [`references/WORKTREE_TEARDOWN.md`](references/WORKTREE_TEARDOWN.md) apply per worktree.

## Interaction rules

- **`/land` never finalizes docs.** If docs aren't done, it refuses and points at `/wrap NNN`. Documentation finalization is `/wrap`'s job; `/land` only ships and tears down.
- **The HITL gate is *protected-branch* merge, not *every* merge.** `/land` squash-merges into non-protected targets by default; protected targets always preserve the human-merge gate (detect → skip → hand back PR URL).
- **Destructive teardown is strictly post-merge.** The `-v` volume removal + worktree removal + branch delete require the PR to have landed. On a pre-merge `/land`, the atomic-merge path naturally unblocks teardown in the same pass.
- **Never force-push, never `--no-verify`, never merge into a protected branch** (per `RULE_git-safety`). Permission denial on `gh pr merge` is not a failure — surface it as "human-clicks-merge required" and hand back the PR URL; the wrap commits are already pushed, nothing is lost.

## References

- [`references/ATOMIC_MERGE.md`](references/ATOMIC_MERGE.md) — merge mechanics: protected-branch detection, pre-merge review re-clearance, squash-merge sequence, permission-denial handling, deployment-branch override.
- [`references/WORKTREE_TEARDOWN.md`](references/WORKTREE_TEARDOWN.md) — teardown mechanics: destructive sequence, per-file evaluation when `git worktree remove` refuses, the `--integration` batch path.
- [`/wrap`](../wrap/SKILL.md) — the stage before: non-destructive documentation finalization. `/land`'s precondition guard verifies `/wrap` ran.
- [`/review-loop`](../review-loop/SKILL.md) — the single review pass that clears before `/land` merges.
- [`/compound`](../compound/SKILL.md) — the stage after: routes the sprint's learnings once the IDEA has landed.
- [`RULE_git-safety`](../../rules/RULE_git-safety.md) — the protected-branch list (`main` / `production` / `deployment`) and the merge-into-protected prohibition that scopes `/land`'s atomic merge to non-protected targets.
