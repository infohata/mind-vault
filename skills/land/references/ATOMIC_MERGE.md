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

Pushing the wrap commits invalidates any prior review clean signal because the head SHA changed. Two options before merging:

- **Wait for review re-clean** (cautious; recommended when the project rate-limits review per PR or when wrap touched code-adjacent files). Trigger via the project's `tools/bugbot_retrigger.sh` or `tools/copilot_retrigger.sh` (per the configured engine) after the wrap commits push, then `/<engine>-loop` until clean. THEN run merge.
- **Merge without re-clearance** (faster; defensible when the wrap commits are pure docs — `docs/`, no code changes whatsoever). The pre-wrap clean signal already covered the substantive code; the wrap commits add only frontmatter, devlog, README, and grep-driven downstream-doc fixes. Review-loop has near-zero learnable signal on those.

`/land`'s default is **wait for re-clean**, because (a) it's the conservative path, (b) docs-only commits clear review in a single short cycle anyway, and (c) detecting "purely docs" mechanically is messier than just running the loop. **Future override hook** (not yet implemented in any land entry point): a project-level `WRAP_SKIP_REVIEW_RECLEAR=1` env var or `--no-review-reclear` flag for projects that prefer the faster path; the merge-sequence snippet below honors the env var, but no skill / command currently sets it or accepts the flag — adopters can wire it in when the cost calculus warrants.

## Merge sequence

```bash
# 1. Confirm review clean signal at current HEAD (skip if WRAP_SKIP_REVIEW_RECLEAR).
#    Use the engine-specific find-comments tool (find_bugbot_comments.sh or
#    find_copilot_comments.sh, per the project's configured review engine);
#    abort if not clean. Example for the bugbot engine:
clean_sha=$(./tools/find_bugbot_comments.sh "$PR_NUMBER" 2>/dev/null \
    | grep -oP 'BUGBOT_CLEAN_SIGNAL=\d+ COMMIT=\K[a-f0-9]+' | head -1)
# For Copilot, swap to: ./tools/find_copilot_comments.sh + grep COPILOT_CLEAN_SIGNAL.
head_sha=$(git rev-parse HEAD)
if [[ "$clean_sha" != "$head_sha" && -z "${WRAP_SKIP_REVIEW_RECLEAR:-}" ]]; then
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
