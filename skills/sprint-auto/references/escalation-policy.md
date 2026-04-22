# sprint-auto — escalation-resolution policy

When `/bugbot-loop` hands back with unresolved Tier 2 or Tier 3 findings, the default interactive behaviour is "ask the user". Under sprint-auto the user is asleep. The policy below is what sprint-auto substitutes for the human decision.

## Authority model — sprint-auto IS the caller

`/bugbot-loop` treats its invoker as the decision-maker for Tier 2 (explicit fix-direction approval) and Tier 3 (human escalation). Under sprint-auto:

- **The whole run is pre-authorized.** The user explicitly typed `/sprint-auto <IDEA-list>` with the `auto_safe` frontmatter gate already cleared per IDEA. That authorization transitively covers the bugbot-fix work downstream of `/work`. If the user didn't want sprint-auto making fixes, they wouldn't have run sprint-auto.
- **Tier 2 is auto-approved.** The skill applies bugbot's suggested fix (or its own best interpretation) without asking.
- **Tier 3 is attempted, not escalated.** The fix is harder and less codified, but sprint-auto tries with maximum thinking effort rather than handing back. If no safe fix is found, the finding ships unresolved (see "Ship non-clean" below).
- **Theoretical Tier 4+** — anything bugbot flags that seems beyond its normal taxonomy (architectural, "this needs a refactor first", "the whole module is wrong") — same contract as T3: one attempt at max effort, then ship-unresolved.

## Rollback discipline

Each attempt cycle is a **fresh commit**, never an amend or force-push.

### Why fresh commits

1. **Every attempt is a rollback point.** If attempt 2 makes things worse than attempt 1, `git revert <attempt-2-sha>` restores attempt 1's state without losing the history.
2. **The PR carries the trail.** A reviewer reading the PR after sprint-auto finishes can see exactly what sprint-auto tried, in order — "this agent tried A, then reverted, then tried B" is a far better handoff than "this agent made one mysterious commit that I have to reverse-engineer".
3. **`git revert` preserves the finding context.** A revert commit's body explains WHY the previous attempt was abandoned. A force-push erases the attempt and the reason.

### The revert-then-retry loop

When attempt N didn't resolve the bugbot finding (either bugbot still flags it or the attempt introduced a regression):

```bash
# 1. Revert the bad attempt cleanly
git revert --no-edit <attempt-N-sha>

# 2. Now working tree is back to pre-attempt-N state — try a different angle
# ... edit, test ...

# 3. Commit the new attempt with context
git commit -m "fix(scope): attempt N+1 — <different approach> (bugbot #M)"

# 4. Push, re-trigger bugbot-loop, wait
```

**Never**:
- `git reset --hard <pre-attempt-sha>` on a pushed branch — rewrites history, invalidates bugbot's comment anchors, and the reviewer can't see what was tried.
- `git commit --amend` once a bugbot cycle has posted comments on the previous head — same problem.
- `git push --force` on a feature branch with an open bugbot review — forbidden per `RULE_git-safety` without explicit authorization.

`--force-with-lease` is technically safer than `--force` but is still not appropriate during bugbot escalation because it erases the attempt from the reviewer's view. Use `git revert`.

## Attempt cap — 3 cycles per bugbot finding category

After 3 attempt cycles on the same finding (or finding category, if the fixes are adjacent), stop and ship the current state regardless of bugbot status.

### Why 3

- One attempt catches the "I misread the finding" case.
- Two attempts catches the "my first approach was structurally wrong" case.
- Three attempts catches the "the right fix needs more context than the finding alone provides" case.
- Four+ attempts almost never converge — they signal the finding is a genuine design question that needs a human. Shipping the PR with the unresolved finding is a better hand-back than burning further wall-clock time.

### Cap mechanics

Per-IDEA attempt counter, not per-finding. If bugbot-loop hands back 3 separate findings and sprint-auto fixes them all in a single commit (the normal batching pattern), that's 1 attempt against all 3 findings. If any of them re-surfaces on the next bugbot pass, that pass counts as attempt 2 for whichever ones re-surfaced.

The `no_progress_map` in bugbot-loop's own scratch file already catches the pathological case where the same finding category keeps re-flagging — sprint-auto inherits that tripwire. When bugbot-loop itself hands back with `no_progress_map` tripped, sprint-auto does NOT start a new attempt; it ships-unresolved immediately.

## "Ship non-clean" — why an unresolved finding is not a failure

A PR with transparent unresolved findings is a better outcome than a PR with hidden ones. When sprint-auto exhausts its attempt cap, it:

1. **Leaves the last-attempt SHA in the branch** (no revert of the final attempt, even if it didn't clear bugbot — the reviewer may see it's close enough and merge as-is).
2. **Annotates the auto-run log** with the attempt history — every SHA, every approach, every bugbot outcome.
3. **Annotates the PR body** with a "Sprint-auto escalation summary" section showing:
   - Findings sprint-auto resolved (by SHA).
   - Findings sprint-auto attempted and left unresolved, with the reasoning for each approach.
   - Recommendation for the reviewer (accept as-is / fix forward / revert sprint-auto's attempts).
4. **Does NOT block the IDEA pipeline.** The next IDEA in the batch proceeds normally. Non-clean is an IDEA-level outcome, not a batch-level abort.

## When NOT to attempt — hard skips

Some bugbot findings are not appropriate for sprint-auto to attempt, regardless of tier:

- **Findings that require knowledge outside the repo.** "Check whether this credential is actually still valid" — sprint-auto has no way to verify external state.
- **Findings that ask for design choices.** "Is this field really supposed to be unique?" — not a code fix; needs the human.
- **Findings against the sprint-auto-written commits themselves being the problem.** Bugbot flagging sprint-auto's fix as "this introduces a new anti-pattern" usually means the fix direction was wrong and should revert-only, not iterate further. Revert once; do not keep attempting — that's the "your premise is broken" signal.
- **Findings on the compound PR that contradict the IDEA's premise.** If bugbot reviews the mind-vault compound PR (step 3 of batch compound) and says "this pattern doesn't belong in mind-vault", revert and close the compound PR. Don't keep trying — that IS the human-asked feedback, delivered by bugbot.

In each hard-skip case, annotate the log and ship as-is; the reviewer decides.

## Recording what happened

Per-IDEA auto-run log gains an `escalation_attempts` section (see [`../assets/auto-run-log-template.md`](../assets/auto-run-log-template.md)):

```yaml
escalation_attempts:
  - attempt: 1
    sha: abc1234
    approach: "Added null-check at UserView.get_context_data"
    bugbot_outcome: still_flagged
    reason_abandoned: "bugbot re-flagged — null-check wasn't the issue; the type was wrong"
  - attempt: 2
    sha: def5678  # revert of abc1234 was attempt 1.5; not counted against cap
    approach: "Corrected annotation + made the field Optional"
    bugbot_outcome: clean_for_this_finding
    reason_abandoned: null
  - attempt: 3
    sha: null  # not needed; cleared at attempt 2
```

Every attempt's commit is in git history; the log is just the human-readable narrative pointer.

---

**Last Updated**: 2026-04-22 (initial — codifies autonomous escalation under sprint-auto, rollback-discipline, 3-attempt cap, "ship non-clean" contract)
