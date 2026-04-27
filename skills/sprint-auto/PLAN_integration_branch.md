# PLAN — sprint-auto: integration branch for cross-PR conflict detection

**Status**: draft (recommendations + open-for-redirect)
**Date**: 2026-04-27
**Source IDEA**: [`IDEA_integration_branch.md`](IDEA_integration_branch.md)
**Driver**: teisutis 2026-04-26 overnight batch — PR #375 + PR #376 both bugbot-clean, both staging-clean, **12 conflict files** when user tried to test #376 on top of #375 locally

This plan answers the 9 design questions from the IDEA file with concrete recommendations + rationale, slots the integration step into the existing S0–S15 state machine, and decides skill structure. Each recommendation is **redirectable** — the implementation PR will be drafted from the answers the user lands on, not the ones in this draft.

## TL;DR — what changes

Between **S11** (per-IDEA loop done) and **S12** (compound consolidation), insert a new batch-level integration stage:

- Bootstrap a 7th worktree (`<project>-auto-integration-<batch-iso>`) with port offset `+70000`.
- Sequentially `git merge --no-ff` each `auto/<slug>` from this batch into a `staging/sprint-auto-<batch-iso>` branch off `origin/main`.
- On conflict per branch: `git merge --abort`, record the colliding files + which prior-merged set the conflict was against, continue to the next branch.
- If at least one branch merged cleanly: bring up the integration stack, run the **union of per-IDEA target tests** (not full suite), record outcome.
- `docker compose down` (keep volumes), keep worktree on disk for human inspection.
- Append an **Integration check** section to the batch summary listing per-pair conflicts and integration-test outcome.
- No bugbot pass on the integration branch in v1.
- Branch + worktree cleanup is post-merge, owned by the human via the existing `/wrap` short-circuit teardown — no new chore.

Skill structure: **change to `sprint-auto/`**, not a new `/integrate` skill. Rationale at the bottom.

## Recommendations on the 9 design questions

### Q1. Branch lifecycle

**Recommend**: Created at start of new state **S11.5** (after the last per-IDEA loop completes). Naming convention: `staging/sprint-auto-<batch-iso>` mirroring the existing batch-summary filename (`auto-run-<ISO>-summary.md`). Deleted on last per-IDEA PR merge — human picks it up via the existing `/wrap NNN` short-circuit teardown chore.

Concrete cleanup mechanism: each `/wrap NNN` post-merge invocation already runs `git worktree remove + git branch -d auto/<slug>`. Extend `/wrap`'s post-merge mode to additionally `git branch -d staging/sprint-auto-<batch-iso>` IFF this is the last `auto/*` of its batch (detect by checking whether any other `auto/<slug>` is still tracked locally with a matching batch ISO in its worktree dir). If batch aborted, the staging branch lingers — that's the diagnostic.

**Rejected alternatives**:
- TTL ("delete after 7 days") — adds a separate cleanup mechanism with its own failure modes; the existing `/wrap` chore already gives precise lifetime tied to merge.
- Keep forever — branch namespace pollution; nothing references staging branches once their batch is merged.

### Q2. Merge strategy

**Recommend**: Sequential `git merge --no-ff <branch>` in argument order. `--no-ff` preserves per-IDEA commit history (important for forensics: "was the conflict introduced by IDEA-124's commit X or its later commit Y?"). On conflict: `git merge --abort`, record the failure, continue to the next branch.

**Rejected alternatives**:
- `git merge -X ours` / `-X theirs` — silently picks one side; cross-IDEA data loss is worse than a visible conflict report. The whole point of this stage is *surfacing* conflicts, not auto-resolving them.
- Octopus merge (`git merge auto/A auto/B auto/C`) — git refuses octopus on any conflict and gives you no diagnostic on which pair collided. Sequential gives "PR-C conflicts with the (A+B) baseline" which is the precise diagnostic the human needs.

### Q3. Conflict surfacing

**Recommend**: New **Integration check** section in `docs/archive/auto-run-<ISO>-summary.md`, between the per-IDEA list and the Compound section. Stub the section even on clean integration so its presence is uniform:

```markdown
## Integration check

**Integration branch**: `staging/sprint-auto-2026-04-26T02-31-00Z` (worktree: `../teisutis-auto-integration-2026-04-26T02-31-00Z`)

**Sequential merge result** (in batch-arg order):
- ✅ PR #375 (auto/audio-playback-browser-compat-dark-theme) → merged cleanly onto staging
- ⚠️  PR #376 (auto/audio-transcription-pre-send-text-input) → CONFLICTS against (main + #375):
    - web/teisutis_ai/templates/teisutis_ai/chat.html
    - web/teisutis_ai/locale/lt/LC_MESSAGES/django.po
    - web/teisutis_ai/locale/en/LC_MESSAGES/django.po
    - … 9 more
  Conflict shape: 12 files, all "include both contributions" pattern
  Prior-merged baseline: main + #375
- ✅ PR #377 (auto/json-health-check-endpoint) → merged cleanly onto (main + #375 + abort #376)

**Integration tests**: 414 passed (union of teisutis_ai + teisutis_kb target tests; full suite NOT run).

**Recommendation for the morning reviewer**: merge #375 first, then resolve #376 against the new main; #377 is independent.
```

The block is computed mechanically from the merge-attempt log; the "Recommendation for the morning reviewer" line is templated based on which branches merged clean and which collided.

### Q4. When integration fails — open PRs anyway, or pause?

**Recommend**: **Path (a) — open the per-PR PRs anyway**, surface "expects conflicts with PR #X (N files)" in the PR body via a callout block. Don't pause the batch.

Rationale: pausing the batch breaks the unattended-overnight contract that justifies sprint-auto's existence. The integration step is *advance warning*, not a gate. The human is still in control at merge time on GitHub — they just now have a list of files to expect conflicts in, instead of discovering them on `git pull && git merge` the next morning.

The PR body callout looks like:

```markdown
> ⚠️  **Cross-PR integration alert** — sprint-auto detected this PR conflicts with PR #375 in 12 files (all `chat.html` + `.po` files; "include both contributions" pattern). If you merge #375 first, expect to resolve those 12 files when rebasing this PR onto fresh main. See `docs/archive/auto-run-2026-04-26T02-31-00Z-summary.md` § Integration check.
```

The reviewer chooses the merge order; sprint-auto just makes the cost visible.

### Q5. Testing on the integrated state — full suite or union?

**Recommend**: **Union of per-IDEA target tests**, not full suite.

Each `/plan` already records the apps/test paths the IDEA touches (in the plan doc's "Verification" section). The integration test step reads those paths from each merged-clean IDEA's plan doc and runs the union. If IDEA-124 touched `web/teisutis_ai/`, IDEA-125 touched `web/teisutis_ai/`, IDEA-127 touched `web/teisutis_kb/` — run pytest against `web/teisutis_ai web/teisutis_kb` once.

Why union beats full suite:
- ~10x cost reduction (full teisutis suite is ~3000 tests; union of 3 apps is ~400)
- The bug class integration tests catch is **cross-IDEA regression in shared code paths** — exactly what the union exercises
- Tests in apps no IDEA touched can't have regressed from this batch's changes; running them is wasted budget
- If a future IDEA changes deep shared code (e.g. auth middleware), its plan declares it, and the union picks it up automatically

Why union beats no testing:
- Conflict-free merge does NOT imply test-clean merge. Two PRs can edit different lines of the same function and produce a function whose union breaks. Sequential merge passing → tests still need to run.

**Rejected alternative**: full suite. Diminishing returns on the marginal bug class caught vs. the wall-clock cost.

### Q6. Bugbot on integration — fire it, or skip?

**Recommend**: **Skip in v1.** Each `auto/*` PR still gets its own deliverables + docs bugbot pass against `main`. Adding a third per-batch bugbot session against the integration branch costs an additional escalation budget (5+ attempts cap × N IDEAs in the batch), an additional 30+ minutes of wall-clock, and would surface mostly findings that would have been caught by per-PR bugbot OR are integration-state-only artefacts (defensive `getattr` falling through, etc.) that don't surface in normal review either.

**Revisit when**: real-world post-merge incidents start coming from "integration-state-only" bugs that bugbot would have caught if it had run on the integration branch. The decision to add it then is data-driven, not speculative.

### Q7. Sequential vs all-at-once merge

**Recommend**: **Sequential** (already chosen in Q2's mechanics). Surfaces *which pair* collides — "PR-C conflicts with (main + A + B baseline)". All-at-once tells you only "the union has conflicts somewhere" which is a vague half-diagnostic.

Aside: sequential also means the integration test step in S11.7 runs against a deterministic state ("main + A + B + C cleanly merged") rather than an undefined state — easier to reproduce later.

### Q8. Worktree economy — worth a 7th worktree?

**Recommend**: **Yes**, on a fresh port offset (`+70000` if base offset is `+10000`, with N=6 worktrees occupying `+10000..+60000`).

Cost: ~5GB extra disk for the worktree filesystem + a single docker stack on its own ports. ~2-5 minutes of bootstrap wall-clock. ~10-15 minutes of merge + test wall-clock for a 6-IDEA batch.

Benefit: averts the human resolving 12 conflict files at merge time on a stale-context morning. Prevents a "shipped main breaks because PR-A and PR-B both passed bugbot but their union didn't" incident, which is the highest-cost class of post-merge regression — production bug + post-mortem + revert + re-ship.

Net: cheap. The worktree pattern is already battle-tested; adding one more on a higher offset is a config tweak, not a new system.

### Q9. Failure mode for bugbot integration findings — N/A given Q6

If Q6 changes and bugbot DOES run on integration, the answer is: **fix on a third branch** (`auto/integration-fix-<batch-iso>`) so the per-IDEA `auto/*` branches stay immutable for their per-PR review history. Cherry-pick the fix to the affected `auto/*` branch only if it makes that PR's standalone state better; otherwise keep it on the fix branch. Avoid retroactively changing `auto/*` PRs that are already in the human's review queue.

But again, given Q6's recommendation, this is dead code in v1.

## Where it slots in — the new state-machine states

Inserted between **S11** (per-IDEA loop done, all `auto/<slug>` PRs opened) and **S12** (compound consolidation):

| State | Step | What happens |
|-------|------|---|
| **S11.5** | Integration prep | `git worktree add ../<project>-auto-integration-<batch-iso> -b staging/sprint-auto-<batch-iso> origin/main`; run `tools/sprint-auto-bootstrap.sh` with port offset `+70000`. On bootstrap failure: skip S11.6–S11.8, log `integration_outcome: bootstrap_failed`, jump to S12. |
| **S11.6** | Sequential merge | For each `auto/<slug>` from this batch in argument order: `git merge --no-ff auto/<slug>`. On conflict: capture `git diff --name-only --diff-filter=U`, `git merge --abort`, append failure entry. Continue. Track which branches merged-clean for S11.7's input. |
| **S11.7** | Integration test | If ≥1 branch merged-clean: union the test paths from each merged-clean IDEA's plan doc, run pytest against the union. Capture outcome. If 0 branches merged clean: skip, log `integration_tests: skipped_no_clean_merges`. |
| **S11.8** | Integration teardown | `docker compose down` (NOT `down -v`; volumes preserved for inspection). Worktree filesystem stays on disk. |

Then S12 (compound consolidation) runs unchanged.

After all per-IDEA PRs land, the human's `/wrap NNN` post-merge teardown for the *last* IDEA of the batch additionally `git branch -d staging/sprint-auto-<batch-iso>` and `git worktree remove ../<project>-auto-integration-<batch-iso>` (post-merge `/wrap` already does this for `auto/<slug>` worktrees; we extend to also clean up the integration worktree once all its inputs are merged).

## Skill-structure decision — modify sprint-auto, NOT new /integrate

**Recommend**: implement as new states inside `skills/sprint-auto/SKILL.md` + a new `references/integration-stage.md`, NOT a new top-level `/integrate` skill.

Reasoning:
1. The integration step has no meaning outside sprint-auto's batch context. It needs `auto/<slug>` branches with `auto_safe` provenance, isolated worktrees with bootstrap-script-validated environments, and a known port-offset scheme. None of those preconditions exist for a manual "I have N feature branches, integrate them" use case.
2. Promoting to `/integrate` would invite future use without sprint-auto's preconditions (manually-typed branch names, no `auto_safe` gate, host-port collision with a primary stack). Either we re-implement the gates inside `/integrate` or we ship a less-safe public surface.
3. We lack evidence the pattern generalises beyond sprint-auto. If someone surfaces a non-sprint-auto need ("I want this for my 3 in-flight feature branches"), we can split it then with calibration data.

If usage demand surfaces, splitting `/integrate` out as its own skill is a cheap follow-up (extract S11.5–S11.8 logic + parameterise the branch-discovery step that today reads from sprint-auto's per-IDEA list). Don't do it pre-emptively.

## Files this plan would touch (during implementation, not now)

- `skills/sprint-auto/SKILL.md` — add S11.5–S11.8 to the per-IDEA loop description, update the state-table reference, update the auto-run summary template excerpt, add a new "Integration check" interaction rule
- `skills/sprint-auto/references/post-pr-sequence.md` — extend S11 to S11.8, add a new state-by-state section
- `skills/sprint-auto/references/integration-stage.md` — NEW reference doc detailing the merge-attempt-log format, conflict-detection mechanics, integration-test path-union resolution
- `skills/sprint-auto/assets/auto-run-log-template.md` — add Integration check section template
- `skills/wrap/SKILL.md` — extend post-merge mode to detect last-of-batch and clean up `staging/sprint-auto-*` branch + integration worktree
- `tools/sprint-auto-bootstrap.sh` (in each adopting project, e.g. teisutis) — confirm it accepts a `--port-offset 70000` parameter, or document the convention

## Out of scope for this plan

- Implementing it. This is the plan; the next step after the user accepts the recommendations is a feature branch that touches the files above.
- Changing how `auto/<slug>` branches are produced. Per-IDEA loop is unchanged through S11; integration is purely additive.
- Replacing per-PR bugbot or staging tests. Integration is additive; per-PR contracts are untouched.
- A long-lived develop/staging branch or anything resembling gitflow. The integration branch is per-batch, disposable.

## Open for redirect — your call before implementation

If you want any of the recommendations changed, the most consequential redirects to flag are:

1. **Q5 (test scope)** — full suite vs. union. Cheapest to flip; biggest wall-clock impact.
2. **Q6 (bugbot on integration)** — adding it now vs. waiting for a real incident. Most expensive to add later if we skip it now (the integration-bug class would appear in production once before we noticed).
3. **Q4 (PR-creation behaviour on conflict)** — open-with-warning vs. pause-batch. Most user-visible behaviour change.

Everything else (naming, branch lifecycle, skill structure) is mechanical and easy to flip in implementation if the bigger ones land differently.

## Concrete next step (after redirect lands)

1. Open feature branch `feature/sprint-auto-integration-stage` off `origin/main`.
2. Implement the state-machine changes in `skills/sprint-auto/SKILL.md` + new `references/integration-stage.md` per the answered design questions.
3. Update `assets/auto-run-log-template.md` with the Integration check block.
4. Add `/wrap` post-merge cleanup for the last-of-batch staging branch.
5. Open PR; bugbot it; merge after review.
6. **Validate against the next real teisutis sprint-auto batch** — the worked-example acid test is "would this batch have flagged the IDEA-124/IDEA-125 conflict ahead of time?" If yes, ship; if no, debug and re-plan.

## References

- [`IDEA_integration_branch.md`](IDEA_integration_branch.md) — source idea + 9 design questions
- [`SKILL.md`](SKILL.md) — current S0–S15 state machine (this plan inserts S11.5–S11.8)
- [`references/post-pr-sequence.md`](references/post-pr-sequence.md) — per-IDEA loop detail
- [`../../rules/RULE_parallel-worktree-docker.md`](../../rules/RULE_parallel-worktree-docker.md) — worktree pattern the integration worktree reuses
- [`../../rules/RULE_git-safety.md`](../../rules/RULE_git-safety.md) — confirms feature-branch merges are agent-allowed; integration branch falls under this

---

**Last Updated**: 2026-04-27 (initial draft from Claude Code session, pre-redirect by user)
