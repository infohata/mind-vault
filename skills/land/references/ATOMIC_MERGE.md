# Atomic merge — /land concludes the IDEA when the target is non-protected

**When this fires**: `/land NNN` runs pre-merge on an OPEN PR (the named merge stage of the workflow, after `/wrap` finalized docs and the single `/review-loop` cleared), when the PR's target branch is **non-protected** per [`RULE_git-safety`](../../../rules/RULE_git-safety.md). Protected branches (`main`, `production`, `deployment` — the project decides which) ALWAYS require a human merge; `/land` stops, hands the PR URL to the user. Non-protected branches (sprint cohort like `sprint/<topic>`, integration branches like `integration/sprint-auto-<batch>`, any feature branch) are agent-authority for `gh pr merge` and `/land` concludes the IDEA atomically.

The land SKILL.md body's Atomic-merge section holds the firing-conditions stub; this reference holds the mechanics.

## Why this exists

Sprint-auto already does atomic-merge at the multi-IDEA scale (S11.10 integration-PR creation + review → integration PR merge produces a single shipping moment for the batch). The single-IDEA `/land` follows the same principle: when nothing about the merge target is protected, `/land` *is* the deliverer in one shot — it collapses "review-clear then click merge" into a single operator interaction. The HITL gate is *protected-branch* merge, not *every* merge; the gate stays exactly where `RULE_git-safety` puts it.

**Why merge is its own stage, not part of `/wrap`.** Merge is the destructive, irreversible-ish step (it ships the IDEA and unblocks post-merge teardown), so it is a separate, explicit operation — `/land`, run only after `/wrap` finalized docs and `/review-loop` cleared the wrapped PR. `/wrap` cannot merge; `/land`'s precondition guard (frontmatter `complete`, devlog present, index moved) verifies docs are finalized before touching `gh pr merge`. This is the single-review chain `work → wrap → review → land` — `/land` is how you ask for the atomic conclusion once review is clean. (Legacy: this merge used to live behind `/wrap --scope=full`; that scope is now a deprecated shim that redirects here.)

## Detection

```bash
# 1. Resolve the PR's base branch.
base_branch=$(gh pr view "$PR_NUMBER" --json baseRefName --jq '.baseRefName')

# 2. Project-specific protected-branch list. Default convention: main +
#    one release branch (production OR deployment, whichever the project uses).
#    Project-level override: ~/.claude/projects/<project>/protected-branches.txt
#    OR the project's CLAUDE.md naming the protected branches under a header
#    like "## Protected branches".
protected_branches=( "main" "production" "deployment" )

is_protected=false
for pb in "${protected_branches[@]}"; do
    [[ "$base_branch" == "$pb" ]] && is_protected=true && break
done

if $is_protected; then
    echo "Target $base_branch is protected — land concludes; human merges."
    echo "PR ready: $(gh pr view "$PR_NUMBER" --json url --jq '.url')"
    exit 0
fi
```

## Pre-merge review re-clearance

Under the canonical chain `/wrap → /review-loop → /land`, the single review already ran over the **wrapped** PR — the wrap commits (frontmatter, devlog, README, downstream-doc fixes) were part of the diff the engines reviewed and cleared. So in the normal flow the clean signal already covers HEAD and `/land` just confirms it; there is no "wrap pushed unreviewed commits" gap (that was the retired review-then-wrap model).

The guard exists for the **off-path case — HEAD moved after review cleared**: a late commit, an `--amend`, or an out-of-band push between the review clearing and `/land` running. Then the clean signal is stale for the new HEAD, and `/land` must re-clear before merging:

- **Re-run `/review-loop` on the new HEAD**, wait for clean, THEN merge. This is `/land`'s default — the conservative path, and docs-only follow-up commits clear in a single short cycle anyway.
- **Skip re-clearance** (faster; defensible only when the post-review commits are pure docs — `docs/`, no code). **Future override hook** (not yet implemented in any land entry point): a project-level `LAND_SKIP_REVIEW_RECLEAR=1` env var or `--no-review-reclear` flag; the merge-sequence snippet below honors the env var, but no skill / command currently sets it or accepts the flag — adopters can wire it in when the cost calculus warrants.

## Merge sequence

```bash
# 1. Confirm review clean signal at current HEAD (skip if LAND_SKIP_REVIEW_RECLEAR).
#    Use the engine-specific find-comments tool (find_bugbot_comments.sh or
#    find_copilot_comments.sh, per the project's configured review engine);
#    abort if not clean. Example for the bugbot engine:
clean_sha=$(./tools/find_bugbot_comments.sh "$PR_NUMBER" 2>/dev/null \
    | grep -oP 'BUGBOT_CLEAN_SIGNAL=\d+ COMMIT=\K[a-f0-9]+' | head -1)
# For Copilot, swap to: ./tools/find_copilot_comments.sh + grep COPILOT_CLEAN_SIGNAL.
head_sha=$(git rev-parse HEAD)
if [[ "$clean_sha" != "$head_sha" && -z "${LAND_SKIP_REVIEW_RECLEAR:-}" ]]; then
    echo "Review-loop clean signal is at $clean_sha but HEAD is $head_sha — re-run /review-loop on the new HEAD, wait for clean, then re-run /land."
    exit 1
fi

# 2. Squash-merge. Squash strategy collapses code commits + wrap commits
#    into a single "feat: IDEA-NNN <title>" commit on the target branch —
#    a single shipping moment in the cohort branch's git log. The PR's
#    full commit history stays in the closed-PR record.
gh pr merge "$PR_NUMBER" --squash --delete-branch

# 3. Pull the now-updated target branch locally.
default_branch=$(git symbolic-ref refs/remotes/origin/HEAD --short | sed 's|origin/||')
git checkout "$base_branch"
git pull --ff-only origin "$base_branch"

# 4. Run WORKTREE_TEARDOWN.md (the /land teardown reference) now that the
#    PR is in — `git branch -d` wouldn't have agreed before merge. If the
#    work happened in a parallel worktree, the destructive teardown is
#    finally safe at this point (the same /land pass continues into teardown).
```

**Permission denials are not failures** — when `gh pr merge` is denied (the user's project-level permission settings declined the action despite the rule allowing it), this step surfaces the denial as "human-clicks-merge step required" and hands back the PR URL. The wrap commits are already pushed; the user can merge manually with no loss.

**The merge command's body** is just `gh pr merge --squash --delete-branch`. NO custom commit message — squash takes the PR title and body. The PR title was set at `/work` time per the conventional `type(scope): IDEA-NNN — <slug>` format; that becomes the cohort-branch commit title.

**Don't auto-merge into production/deployment EVEN if the rule technically allows.** Some projects use `production` or `deployment` as the staging-rolled-up branch where the human's click is a deployment trigger. Detection list above uses `( main production deployment )` as the conservative default. Override per project if a project genuinely wants `deployment` to be agent-authority — explicit env var `WRAP_AUTO_MERGE_DEPLOYMENT=1`, never silent.
