# PLAN — sprint-auto: integration branch (v2 — post-redirect)

**Status**: revised draft v2 (post user redirects on Q4/Q5/Q6)
**Date**: 2026-04-27
**Source IDEA**: [`IDEA_integration_branch.md`](IDEA_integration_branch.md)
**Driver**: teisutis 2026-04-26 batch — 12-file conflict on chat.html + .po + parallel devlog/index conflicts surfaced as a structural problem, not a one-off
**Revision**: v1's Q4/Q5/Q6 recommendations superseded by user redirects in this conversation. v1 history preserved in git.

## What the redirects changed

| Q | v1 recommendation | v2 (user redirect) | Cascading impact |
|---|---|---|---|
| Q4 (conflict) | Open per-PR PRs anyway with warning | Resolve on staging, validate deliverable, **propagate back to per-PR PRs**. Side benefit: solves the wrap-stage devlog/index line-conflict that every parallel `/wrap` produces today | Adds propagate-back states; redesigns per-IDEA `/wrap` to defer batch-level writes to staging |
| Q5 (test scope) | Union of per-IDEA target tests | **Union during integration**, **full suite at sprint-end** as the final gate | Adds a separate full-suite state after the union state |
| Q6 (bugbot) | Skip on integration in v1 | **Fire on integration branch**. Each PR gets its own loop AND the staging branch gets its own loop | Adds bugbot-loop-on-staging mechanic; raises a tooling question (bugbot-loop is PR-anchored) |

## The wrap-stage insight (the strongest justification for this whole feature)

Right now, `/wrap` (pre-merge) at S5 in each per-IDEA worktree writes three things:

1. IDEA frontmatter flip (`status: in-progress` → `status: complete` + `completed: <date>`) — **idea-local, never conflicts**
2. ideas-index entry move (`docs/ideas/README.md`) — **line-conflicts with parallel branches**
3. DEVELOPMENT_LOG entry append — **line-conflicts with parallel branches**

When N IDEAs run in parallel, all N worktrees write the same devlog/index lines. **Every** batch produces N-way merge conflicts on those two files. The teisutis 2026-04-26 batch's 12-file conflict was the visible part; the devlog/index conflicts are a structural tax on every batch ≥2 IDEAs.

Right design: **per-IDEA `/wrap` does ONLY the frontmatter flip; devlog + index writes move to a batch-level operation on the staging branch, ONCE per batch covering all N IDEAs.** This eliminates the structural conflict at its source instead of resolving it after the fact.

## State machine after redirects

Inserted between **S11** (per-IDEA loop done, all `auto/<slug>` PRs opened, deliverables + docs bugbot already done per branch) and **S12** (compound consolidation):

| State | Step | What happens |
|-------|------|---|
| **S11.5** | Integration prep | `git worktree add ../<project>-auto-integration-<batch-iso> -b staging/sprint-auto-<batch-iso> origin/main`; run `tools/sprint-auto-bootstrap.sh` with port offset `+70000`. Bootstrap failure → skip S11.6–S11.11, log `integration_outcome: bootstrap_failed`, jump to S12. |
| **S11.6** | Sequential merge | For each `auto/<slug>` in argument order: `git merge --no-ff auto/<slug>`. On conflict: keep the index in conflicted state, resolve manually (algorithmic resolutions catalogued in [a new `references/integration-conflict-resolutions.md`](#new-reference-doc)), commit as a separate "resolve: integrate auto/<X> conflicts" commit. Continue to next branch. Track which branches needed resolution for the auto-run log. |
| **S11.7** | Batch wrap on staging | Compose ONE devlog entry per IDEA (concatenated chronologically) + ONE ideas-index batch update (all moves in one commit). This is the work that per-IDEA `/wrap` no longer does (see "Wrap-stage redesign" below). |
| **S11.8** | Integration tests — union | Read each merged-in IDEA's plan-doc Verification section, union the test paths, run pytest against the union. Failure → fix on staging until passing (target: same per-IDEA escalation discipline — fresh commits + revert between attempts), with a cap of **10 attempts** (lower than per-IDEA caps because integration failures should be cross-cutting; tail length is shorter). Cap-exceeded → log + proceed to S11.9. |
| **S11.9** | Integration tests — full suite (sprint-end gate) | Per Q5 redirect. Cheaper than re-running per-PR full suites N times because shared docker stack + warm caches. Same fix-on-staging-with-cap-of-10 discipline. Failure cap-exceeded → log + proceed; integration-non-clean is shipable as a known-flagged state (mirrors the per-PR ship-non-clean policy). |
| **S11.10** | Bugbot-loop on staging | Per Q6 redirect. Tooling friction: bugbot-loop is PR-anchored (Cursor Bugbot polls per-PR). Recommendation: open a draft PR titled `[INTEGRATION] sprint-auto-<batch-iso>` from staging targeting `main`, run `/bugbot-loop` against it, then close the draft PR without merging at S11.13 teardown. Same escalation discipline as docs pass: cap of **5 attempts** (single pass, integration-state findings tend to be either trivial — clear up — or structural — out of scope). |
| **S11.11** | Propagate resolutions back | For each `auto/<slug>`: `git checkout auto/<slug>; git merge --no-ff staging`. Forward-sync brings the integration's resolution commits, batch wrap commits, and any S11.10 bugbot fixes onto the per-PR branch. Force-push not needed (forward-sync only fast-forwards or adds merge commits — feature branch tip moves, RULE_git-safety compliant). The per-PR PR auto-updates; bugbot fires automatically against the new head. |
| **S11.12** | Re-validate per-PR PRs | After propagation, each per-PR PR has new commits on top. Run `/bugbot-loop` against each one more time (deliverables-equivalent pass; cap of 10 — most of these will clean-signal immediately because the new commits are wrap + resolutions, not deliverables work). Findings here are most likely "the resolution touched X which now has issue Y" — auto-fix on the per-PR branch, push, re-evaluate. This pass does NOT have its own S6 docs phase — propagation is a single mixed delivery. |
| **S11.13** | Integration teardown | `docker compose down` (NOT `down -v`; volumes preserved for inspection). Worktree filesystem stays. Close the `[INTEGRATION]` draft PR opened at S11.10 with comment `auto-closed by sprint-auto teardown; integration validation complete, see auto-run summary`. The staging branch lingers locally — cleaned up by the human's `/wrap NNN` post-merge teardown for the LAST IDEA of the batch (extend `/wrap` to detect last-of-batch and `git branch -d staging/sprint-auto-<batch-iso>`). |

Then S12 (compound) runs unchanged.

## Wrap-stage redesign (the structural change)

Per the wrap-stage insight above:

**Per-IDEA `/wrap` (S5) — narrowed**:
- IDEA frontmatter flip (`status: in-progress` → `status: complete` + `completed: <date>`) — KEEP
- Downstream docs scan (per IDEA's own touched paths) — KEEP
- ideas-index entry move — **REMOVE** (moves to S11.7 as a batch operation)
- DEVELOPMENT_LOG entry append — **REMOVE** (moves to S11.7 as a batch operation)

**Batch wrap on staging (S11.7) — new**:
- Compose all N devlog entries concatenated chronologically (algorithmic; each IDEA's entry is the same shape `/wrap` would have written, just composed against the post-integration baseline)
- Apply all N ideas-index moves in one commit (each IDEA gets moved from its priority section to References — Implemented; algorithmic merge of N independent moves)
- Commit shape: ONE `wrap-batch: devlog + index for batch <iso>` commit on staging covering all N IDEAs

**Why this is safer than "let per-IDEA `/wrap` write and then resolve at integration"**:
- The conflict resolution at integration time (Option B from v1 plan) requires the agent to algorithmically interleave N concurrent text edits. The composition at integration time (Option A from v1 plan, now adopted) starts from the unconflicted baseline and writes the unified state from scratch. Strictly less ambiguity.
- The `/wrap` skill needs a `--scope=idea-only` flag (or the `wrap` skill auto-detects it's running under sprint-auto) to skip the index/devlog writes. Either is a small, isolated change.

**Implication for the `/wrap` skill itself**:
- Add a new mode `wrap --scope=idea-only` (sprint-auto's S5 invokes it; standalone `/wrap NNN` keeps current behaviour).
- Document the new mode in `skills/wrap/SKILL.md`.
- The pre-merge `/wrap` invoked manually (outside sprint-auto) keeps writing devlog + index because in the standalone case there's no parallel-conflict problem.

## The bugbot-on-staging tooling friction

Cursor Bugbot triggers per PR. The staging branch is never going to merge to main; it's an integration test-bed. To get bugbot-loop coverage on the integrated state, one of:

**Option B1 (recommended) — open a `[INTEGRATION]` draft PR**:
- After integration tests pass at S11.9, open a draft PR with title `[INTEGRATION] sprint-auto-<batch-iso>` and body `Auto-generated integration validation PR. NOT FOR MERGE. Auto-closed at sprint-auto teardown.` Base: `main`, head: `staging/sprint-auto-<batch-iso>`.
- Run `/bugbot-loop` against it. Cursor Bugbot reviews against main → diff is the union of all N IDEAs' work + integration resolutions + batch wrap. That's a lot of diff but bugbot scales OK.
- At S11.13 teardown, post a comment `auto-closed by sprint-auto teardown; see auto-run summary at <path>` and close the PR (without merging).
- The closed PR's URL goes into the auto-run summary so the morning reviewer can read bugbot's integration-state findings without recreating the state.

**Option B2 — non-PR bugbot anchor**: Cursor Bugbot's API may support reviewing a specific commit/branch without a PR. Investigate; if available, this is cleaner. If not available, fall back to B1.

**Option B3 — skip bugbot on integration if it's mechanically impossible**: only as a last resort. Document the gap in the auto-run summary.

Recommendation: **B1 in v1 implementation; investigate B2 in parallel; never fall back to B3 without explicit retreat.**

## Architectural shape decision (resolves the v1 plan's open propagate-back question)

The user's redirect "On conflict, update sprint branch to resolution, then update incoming PRs" maps onto **forward-sync from staging into each `auto/<slug>`** (S11.11 above). Rejected alternatives:

- **Cherry-pick the resolution commits**: brittle. Conflict resolutions reference both branches' contributions; cherry-picking onto a branch with only its own contribution produces a partial / non-applicable patch. Forward-sync brings the full integrated state, which is the only state that's coherent.
- **Hold off opening per-PR PRs until integration completes**: cleanest end state but breaks current S2/S3 contract (`/work` opens PR; deliverables bugbot anchors to it). Would require deferring deliverables bugbot to after integration too. High cost for a cosmetic improvement.

**Cosmetic tradeoff acknowledged**: forward-sync makes each per-PR PR's diff against main contain commits from every other PR in the batch. This is weird-looking but consistent — the morning reviewer's mental model becomes: "this PR represents the post-batch state if I merge in this order." When PR-A is merged to main first, PR-B's diff against main shrinks (PR-A's contribution is now common ancestor); bugbot re-fires automatically; eventually all merge cleanly. The weirdness has bounded duration (until the batch is fully merged) and is offset by the absence of merge-time conflicts that today block the human at the worst possible moment.

## Files this plan would touch (during implementation, not now)

- `skills/sprint-auto/SKILL.md` — add S11.5–S11.13 to the per-IDEA loop description, update state-table reference, update the auto-run-log shape to include `Integration` section, update interaction rules to cover the propagate-back step
- `skills/sprint-auto/references/post-pr-sequence.md` — extend S11 to S11.13, document the new states
- `skills/sprint-auto/references/integration-stage.md` — NEW: merge-attempt log format, conflict-resolution algorithm catalogue (devlog interleaving, index alphabetical re-sort, etc.), integration-test path-union resolution, [INTEGRATION] draft PR mechanic
- `skills/sprint-auto/references/integration-conflict-resolutions.md` — NEW (or in the same doc as above): catalogued resolution patterns. Devlog: chronological concat. ideas-index: alphabetical/numerical re-sort. Translation `.po` files: include both contributions. HTML/JS: case-by-case (escalate to per-IDEA bugbot if non-trivial)
- `skills/sprint-auto/assets/auto-run-log-template.md` — add Integration check section template (with merge results, test results, bugbot results, propagation results)
- `skills/wrap/SKILL.md` — **add `--scope=idea-only` mode** (frontmatter + downstream-docs only; skip devlog + index). Document when to use (sprint-auto S5 invocation only).
- `skills/wrap/SKILL.md` — extend post-merge mode: detect last-of-batch and clean up `staging/sprint-auto-*` branch + integration worktree
- `tools/sprint-auto-bootstrap.sh` (in each adopting project) — confirm acceptance of `--port-offset 70000` parameter

## Files NOT touched (out of scope)

- Per-IDEA `/work` and per-IDEA `/bugbot-loop` for deliverables/docs — unchanged through S11
- The `auto/<slug>` branch naming, IDEA gating, `auto_safe` frontmatter — unchanged
- The compound stage S12+ — unchanged

## Open questions raised by redirects (need your second-pass call)

1. **Q5 — full-suite test cap**: 10 attempts feels right (~ same as integration-test cap). Lower because integration-state full-suite failures are usually deeply structural (e.g. a migration's row data conflicts) — adding fix attempts past 10 means the batch is not shippable. Confirm or adjust.

2. **Q6 — bugbot-on-staging mechanic**: Option B1 (draft `[INTEGRATION]` PR) recommended. The "open + later close-without-merging" pattern is slightly polluting on the GitHub PR list. Is that acceptable, or do you want me to investigate B2 (non-PR bugbot) before finalising? This gates the implementation start.

3. **Q4 — propagation cosmetic**: forward-sync makes per-PR PRs cumulative-looking. Acceptable in v1, or do you want me to invest in the higher-cost "hold off opening per-PR PRs" alternative?

4. **`/wrap` mode flag naming**: `--scope=idea-only` reads OK but a literal flag like `--no-devlog --no-index` might be clearer for the maintainer. Preference?

5. **Integration cap calibration**: I picked 10 (tests) and 5 (bugbot) because integration findings have shorter tails than per-PR findings. These are educated guesses; first real batch will calibrate them.

If none of these feel like blockers, the plan is implementable as-is and I'll open `feature/sprint-auto-integration-stage` straight from this draft.

## Concrete next step

After your call on the open questions:
1. Open `feature/sprint-auto-integration-stage` off `origin/main`
2. Implement the state-machine changes in `skills/sprint-auto/SKILL.md` + new reference docs
3. Add `/wrap --scope=idea-only` mode in `skills/wrap/SKILL.md`
4. Update `assets/auto-run-log-template.md` with the Integration section
5. Open PR; bugbot it; merge after review
6. **Validate against the next teisutis sprint-auto batch** — acid test: does it flag the IDEA-124/IDEA-125 conflict ahead of time AND eliminate the wrap-stage devlog/index conflicts?

## References

- [`IDEA_integration_branch.md`](IDEA_integration_branch.md) — source idea + 9 design questions
- [`SKILL.md`](SKILL.md) — current S0–S15 state machine (this plan inserts S11.5–S11.13)
- [`references/post-pr-sequence.md`](references/post-pr-sequence.md) — per-IDEA loop detail
- [`../wrap/SKILL.md`](../wrap/SKILL.md) — touched by this plan (new `--scope=idea-only` mode + post-merge last-of-batch detection)
- [`../../rules/RULE_parallel-worktree-docker.md`](../../rules/RULE_parallel-worktree-docker.md) — worktree pattern the integration worktree reuses
- [`../../rules/RULE_git-safety.md`](../../rules/RULE_git-safety.md) — confirms forward-sync (`git merge staging` while on `auto/<slug>`) is agent-allowed; force-push is NOT used in S11.11; the `[INTEGRATION]` draft PR is a non-merging artefact

---

**Last Updated**: 2026-04-27 v2 (post-redirect on Q4/Q5/Q6; restructured around the wrap-stage devlog/index conflict insight as the dominant motivator)

**v1 (superseded)**: 2026-04-27 — initial draft with v1 recommendations on Q4/Q5/Q6. See git history for the prior version.
