# sprint-auto — escalation-resolution policy

When the configured `/review-loop` session (carrying one or all engines per `SPRINT_AUTO_REVIEW_ENGINE`) hands back with unresolved Tier 2 or Tier 3 findings, the default interactive behaviour is "ask the user". Under sprint-auto the user is asleep. The policy below is what sprint-auto substitutes for the human decision.

Two passes run per IDEA (deliverables, then docs), plus a separate pass per mind-vault compound PR at batch end. Each pass has its own independent escalation budget — see "Attempt caps per pass" below.

## Authority model — sprint-auto IS the caller

The configured `/review-loop` session treats its invoker as the decision-maker for Tier 2 (explicit fix-direction approval) and Tier 3 (human escalation). Under sprint-auto:

- **The whole run is pre-authorized.** The user explicitly typed `/sprint-auto <IDEA-list>` with the `auto_safe` frontmatter gate already cleared per IDEA. That authorization transitively covers the review-fix work downstream of `/work` AND the documentation sweep work downstream of `/wrap-docs`. If the user didn't want sprint-auto making fixes, they wouldn't have run sprint-auto.
- **Tier 2 is auto-approved.** The skill applies review's suggested fix (or its own best interpretation) without asking.
- **Tier 3 is attempted, not escalated.** The fix is harder and less codified, but sprint-auto tries with maximum thinking effort rather than handing back. If no safe fix is found, the finding ships unresolved (see "Ship non-clean" below).
- **Theoretical Tier 4+** — anything review flags that seems beyond its normal taxonomy (architectural, "this needs a refactor first", "the whole module is wrong") — same contract as T3: one attempt at max effort, then ship-unresolved.

## Rollback discipline

Each attempt cycle is a **fresh commit**, never an amend or force-push.

### Why fresh commits

1. **Every attempt is a rollback point.** If attempt 2 makes things worse than attempt 1, `git revert <attempt-2-sha>` restores attempt 1's state without losing the history.
2. **The PR carries the trail.** A reviewer reading the PR after sprint-auto finishes can see exactly what sprint-auto tried, in order — "this agent tried A, then reverted, then tried B" is a far better handoff than "this agent made one mysterious commit that I have to reverse-engineer".
3. **`git revert` preserves the finding context.** A revert commit's body explains WHY the previous attempt was abandoned. A force-push erases the attempt and the reason.

### The revert-then-retry loop

When attempt N didn't resolve the review finding (either review still flags it or the attempt introduced a regression):

```bash
# 1. Revert the bad attempt cleanly
git revert --no-edit <attempt-N-sha>

# 2. Now working tree is back to pre-attempt-N state — try a different angle
# ... edit, test ...

# 3. Commit the new attempt with context
git commit -m "fix(scope): attempt N+1 — <different approach> (review #M)"

# 4. Push, re-trigger review-loop, wait
```

**Never**:
- `git reset --hard <pre-attempt-sha>` on a pushed branch — rewrites history, invalidates review's comment anchors, and the reviewer can't see what was tried.
- `git commit --amend` once a review cycle has posted comments on the previous head — same problem.
- `git push --force` on a feature branch with an open review — forbidden per `RULE_git-safety` without explicit authorization.

`--force-with-lease` is technically safer than `--force` but is still not appropriate during review escalation because it erases the attempt from the reviewer's view. Use `git revert`.

## Attempt caps per pass — 20 / 5 / 5, each independent

Three distinct review passes happen under sprint-auto, each with its own independent escalation budget:

| Pass | Where | Cap | Counted against |
|---|---|---|---|
| Deliverables | Per IDEA, after `/work` (state S3+S4 in the state machine) | **20** attempts | `deliverables_escalation_attempts` in the per-IDEA log |
| Docs | Per IDEA, after `/wrap-docs` (state S6+S7) | **5** attempts | `docs_escalation_attempts` in the per-IDEA log |
| Mind-vault compound | Per compound PR at batch end (state S13+S14) | **5** attempts | attempt table in the mind-vault compound PR's summary block |

Each cap counts **escalation attempts** (sprint-auto re-entries to resolve T2/T3 findings) for that pass — distinct from `/review-loop`'s own internal session bounds (`max_commits_per_session` etc.). With one multi-engine session per pass, the cap is a single shared budget, *not* multiplied by engine count.

An IDEA may legitimately burn up to 25 escalation attempts (20 deliverables + 5 docs) and still produce a valid PR. That is the point of the budget being generous: overnight wall-clock is cheap, and the alternative (shipping non-clean when one more attempt would have landed) erases the value of automating the fix work at all.

### Why 20 for deliverables

Deliverables are real code changes — the review findings that arise against them have a genuinely long tail. Common patterns that need more than 3 attempts to land:

- **Subtle ordering / state-machine drift** — the kind of cross-file invariant this very PR (#62) kept generating. Each point-fix revealed a neighbouring contradiction the fixer hadn't loaded into context. The fix-and-retry shape *is* the solution; being stingy converts would-be resolutions into shipped-non-clean.
- **Migration + model + test triad** — when a review finding touches model fields, the migration layer, and the test fixtures, getting all three aligned often takes 4–6 attempts because each attempt reveals the next adjacent constraint.
- **Async / concurrency / race windows** — review can correctly describe the race but sprint-auto may need several attempts to pick the right lock / queue / backoff pattern; each failed attempt teaches which primitive does NOT fit.
- **Type-system refactors** — the first attempt usually fixes half the type flow; review re-flags the propagated error at the next call site; attempt two fixes that and bubbles up another, etc.

The failure mode "sprint-auto tried 4 times and kept failing so the cap was clearly right" is rare; the failure mode "sprint-auto tried 3 times, got stingy-capped, and the reviewer's first fix was a trivial variant of sprint-auto's third attempt" is common. The cap is there to prevent pathological divergence, not to gatekeep legitimate iteration.

### Why 5 for docs + mind-vault compound

Documentation findings — stale references, broken anchors, contradicted devlog entries, dead-end cross-links — have fundamentally different convergence behaviour. Either the fix is obvious within 1–3 attempts, or the finding is a genuinely ambiguous editorial call that no number of further attempts will resolve. 5 attempts is generous enough to try substantially different angles (rewrite from scratch, delete-and-restart, reorganize surrounding context) without burning budget on what should be a human judgement call.

Mind-vault compound PRs (state S13+S14) are documentation by nature — they add/edit skills, rules, references, and agents — so the docs-pass 5-attempt budget applies there too.

### Cap mechanics

Per-pass attempt counter, not per-finding. If review-loop hands back 3 separate findings and sprint-auto fixes them all in a single commit (the normal batching pattern), that's 1 attempt against all 3 findings. If any of them re-surfaces on the next review pass, that pass counts as attempt 2 for whichever ones re-surfaced.

The `no_progress_map` in review-loop's own scratch file already catches the pathological case where the same finding category keeps re-flagging — sprint-auto inherits that tripwire. When review-loop itself hands back with `no_progress_map` tripped, sprint-auto does NOT start a new attempt on THAT finding category; it ships-unresolved immediately for that category while continuing with the budget on unrelated findings.

## "Ship non-clean" — why an unresolved finding is not a failure

A PR with transparent unresolved findings is a better outcome than a PR with hidden ones. When sprint-auto exhausts its attempt cap (on ANY pass — deliverables, docs, or mind-vault compound), it:

1. **Leaves the last-attempt SHA in the branch** (no revert of the final attempt, even if it didn't clear review — the reviewer may see it's close enough and merge as-is).
2. **Annotates the auto-run log** with the attempt history — every SHA, every approach, every review outcome.
3. **Annotates the PR body** with a "Sprint-auto escalation summary" section showing:
   - Findings sprint-auto resolved (by SHA).
   - Findings sprint-auto attempted and left unresolved, with the reasoning for each approach.
   - Recommendation for the reviewer (accept as-is / fix forward / revert sprint-auto's attempts).
4. **Does NOT block the IDEA pipeline.** The next IDEA in the batch proceeds normally. Non-clean is an IDEA-level outcome, not a batch-level abort.

## When NOT to attempt — hard skips

Some review findings are not appropriate for sprint-auto to attempt, regardless of tier:

- **Findings that require knowledge outside the repo.** "Check whether this credential is actually still valid" — sprint-auto has no way to verify external state.
- **Findings that ask for design choices.** "Is this field really supposed to be unique?" — not a code fix; needs the human.
- **Findings against the sprint-auto-written commits themselves being the problem.** Review flagging sprint-auto's fix as "this introduces a new anti-pattern" usually means the fix direction was wrong and should revert-only, not iterate further. Revert once; do not keep attempting — that's the "your premise is broken" signal.
- **Findings on the compound PR that contradict the IDEA's premise.** If the review loop reviews the mind-vault compound PR (step 3 of batch compound) and says "this pattern doesn't belong in mind-vault", revert and close the compound PR. Don't keep trying — that IS the human-asked feedback, delivered by the review.

In each hard-skip case, annotate the log and ship as-is; the reviewer decides.

## Recording what happened

Per-IDEA auto-run log gains an `escalation_attempts` section (see [`../assets/auto-run-log-template.md`](../assets/auto-run-log-template.md)):

```yaml
deliverables_escalation_attempts:
  - attempt: 1
    sha: abc1234
    approach: "Added null-check at UserView.get_context_data"
    review_outcome: still_flagged
    reason_abandoned: "review re-flagged — null-check wasn't the issue; the type was wrong"
  - attempt: 2
    sha: def5678  # revert of abc1234 was attempt 1.5; not counted against cap
    approach: "Corrected annotation + made the field Optional"
    review_outcome: clean_for_this_finding
    reason_abandoned: null
  # (cap is 20; further slots remain available if other findings need more attempts)

docs_escalation_attempts: []   # cleared on first docs-pass review invocation; cap is 5
```

Every attempt's commit is in git history; the log is just the human-readable narrative pointer.
