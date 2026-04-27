# PLAN — sprint-auto: integration branch (v3 — test-triage worktree architecture)

**Status**: revised draft v3 (post user redirects: Q4/Q5/Q6 + hardware constraint + results-oriented call)
**Date**: 2026-04-27
**Source IDEA**: [`IDEA_integration_branch.md`](IDEA_integration_branch.md)
**Driver**: teisutis 2026-04-26 batch — surface conflict (12 files) + structural conflict (every parallel `/wrap` writes the same devlog/index lines) + hardware constraint (cannot run N+1 docker stacks)
**Revision**: v1 superseded by v2 (Q4/Q5/Q6 redirects); v2 superseded by v3 (test-triage worktree architecture). Git history preserves all three.

## Naming clarification — "integration" worktree vs. existing "staging" worktree

These are two **distinct** artefacts and the plan keeps them strictly separate:

| Artefact | Purpose | Lifecycle | Owner |
|---|---|---|---|
| **Existing `staging` worktree** (project-level, predates sprint-auto) | Tracks `main`; human stacks manual experiments / pre-merge testing on top during human-present sessions | Long-lived; never owned by sprint-auto | Human |
| **`integration/sprint-auto-<batch-iso>` worktree** (NEW, created by this plan) | Disposable per-batch sprint-auto integrator + test-runner; never receives manual edits | Created at S(-1); torn down post-merge by `/wrap NNN` of last-of-batch IDEA | Sprint-auto |

Sprint-auto must never `git checkout` the human's staging branch, never bring up its docker stack, never write to its filesystem. The integration worktree is on its own branch, its own port offset (`+30000`), its own filesystem path. Earlier drafts of this plan called the new branch `staging/sprint-auto-...` — renamed throughout to `integration/sprint-auto-...` to eliminate the naming collision.

## Headline change in v3

The integration worktree is **the only docker stack for the entire batch**. Per-IDEA worktrees become pure code surfaces (no `.env`, no `docker compose up`, no port offsets). All verification — per-IDEA targeted tests, per-IDEA bugbot fix-cycles, integration union, integration full suite, integration bugbot, post-propagation re-bugbot — runs on the single shared integration stack with DB resets between IDEAs.

This is a "CI-runner-style" sprint-auto:
- One docker stack at port offset `+30000` (see "Port-offset math" below), the entire batch
- Primary dev stack on default ports never touched
- Per-IDEA worktrees on disk for code-surface isolation only
- Results-oriented: full DB reset between IDEAs guarantees each PR is tested against a main-equivalent DB → genuinely independently deliverable

## What the redirects locked in

| Decision | Choice | Source |
|---|---|---|
| Q4 (conflict) | Resolve on integration branch → validate → forward-sync into each `auto/<slug>` | v2 redirect |
| Q5 (test scope) | Union during integration **+ full suite at sprint-end** | v2 redirect |
| Q6 (bugbot) | Fire on integration branch via `[INTEGRATION]` draft PR | v2 redirect |
| Architecture | Single test-runner stack on integration worktree (NOT N+1 stacks) | v3 redirect (hardware) |
| DB reset cadence | Full reset between IDEAs (Option A) | v3 redirect (results-oriented) |
| Bugbot coverage | Per-PR (deliverables + docs) AND integration AND post-propagation re-bugbot | v3 redirect (results-oriented) |

## Port-offset math (why `+30000`, not `+70000`)

TCP port space is 16-bit: 1–65535. Linux ephemeral range (default): 32768–60999. For a stack offset `N`, the highest service port we typically remap is Elasticsearch transport at 9300, so the binding port is `9300 + N`. Constraints:

- `9300 + N ≤ 65535` → `N ≤ 56235` (hard ceiling)
- `9300 + N ≤ 49151` → `N ≤ 39851` (stay in registered-port range — recommended)
- `9300 + N ≤ 32768` → `N ≤ 23468` (stay below ephemeral range — most defensive)

**Recommend `+30000`** for the integration stack:
- Max remapped port = 9300 + 30000 = 39300 → in registered range, room to grow if a service adds a port
- Defensive against your possible ad-hoc parallel-worktree stack at the conventional `+10000` from `RULE_parallel-worktree-docker`
- Well below the hard ceiling so a future service port addition (e.g. flower 5555 → 35555) doesn't approach a limit

**Latent bug exposed (out of scope, worth follow-up)**: existing sprint-auto v1's per-IDEA `+10000, +20000, ..., +60000` scheme is broken for batches with 6+ IDEAs — IDEA-6's ES transport at 9300 + 60000 = 69300 overflows. v3's collapse to a single stack sidesteps the bug entirely; the existing rule note "+10000 is a safe starting point" should grow a ceiling caveat in a separate `RULE_parallel-worktree-docker` PR.

## Wall-clock budget reality check (6-IDEA batch)

| Phase | Cost | Notes |
|---|---|---|
| Preflight + integration bootstrap | ~5 min | One-time at batch start |
| Per-IDEA × 6: reset + work + targeted tests + bugbot | ~30 min × 6 = 180 min | Reset ~5 min; work ~10 min; tests ~3 min; bugbot ~12 min avg |
| Integration: merge + union + full suite + bugbot via [INTEGRATION] PR | ~60–120 min | Sequential merge ~5 min, union ~10 min, full suite ~25 min, bugbot avg ~30 min / worst-case ~80 min (cap 20 attempts — see S11.10 reasoning) |
| Forward-sync × 6 + per-PR re-bugbot × 6 | ~30 min | Forward-sync ~1 min each; re-bugbot ~4 min each (mostly clean against unchanged code) |
| Teardown | ~3 min | `docker compose down`, close [INTEGRATION] draft PR |
| **Total** | **~5–6.5 hours** (avg ~5 / elephant-batch worst case ~6.5) | Acceptable for overnight runs starting midnight–1 AM. Bugbot-loop's own internal bound (180 min active, 20 idle polls) caps S11.10 worst case independently of attempt count. |

Compare to current v1 sprint-auto (no integration): ~3 hours for 6 IDEAs. **+2 hours for guaranteed-no-conflict-at-merge + integration validation + result-quality gains.** Trade accepted.

## State machine (v3)

The per-IDEA loop's S0 narrows; new pre-batch state S(-1) for integration bootstrap; existing S11.5–S11.13 mostly preserved from v2 with verification routing changes.

### Pre-batch (NEW)

| State | What |
|---|---|
| **S(-1)** | **Integration bootstrap** — `git worktree add ../<project>-auto-integration-<batch-iso> -b integration/sprint-auto-<batch-iso> origin/main`; run `tools/sprint-auto-bootstrap.sh` with port offset `+30000` (see "Port-offset math" below). This is the ONLY docker stack the batch will use. Failure here = abort batch (no per-IDEA work proceeds). |

### Per-IDEA loop (modified — NO docker per IDEA)

| State | What |
|---|---|
| **S0** | **Code-surface worktree only** — `git worktree add ../<project>-auto-<slug> -b auto/<slug> origin/main`. NO `.env`. NO `docker compose up`. NO post-up init. Just code. |
| **S1** | Plan unchanged — markdown read/write, no runtime needed. |
| **S2** | `/work` writes code + commits + opens PR. **Verification routes to integration worktree**: cd to integration worktree, `git checkout auto/<slug>`, `docker compose down -v && docker compose up -d` (full reset), wait for healthchecks, `migrate + seed`, run targeted tests. Pass → continue. Fail → back to /work step. |
| **S3** | Deliverables bugbot-loop on per-PR PR. Bugbot fixes the agent commits go into the per-IDEA worktree's checkout. **Each fix's verification routes to integration worktree** with the same checkout-and-test cycle (no DB reset within an IDEA's bugbot session — fix commits don't typically migrate; reset cost would explode). One reset at IDEA entry, fix-cycle uses that reset baseline. |
| **S4** | Deliverables escalation (T2/T3) — same contract as v1, max 20 attempts. |
| **S5** | `/wrap --scope=idea-only` (NEW MODE) — frontmatter flip + downstream-docs scan ONLY. Skips devlog + ideas-index writes. Those move to S11.7 (batch wrap on integration branch). |
| **S6** | Docs bugbot-loop on per-PR PR. Verification: route to integration worktree, no DB reset (docs commits don't change runtime behavior). |
| **S7** | Docs escalation (T2/T3) — max 5 attempts. |
| **S8** | **Per-IDEA teardown — N/A in v3.** No per-IDEA stack to tear down. The integration stack stays up for the next IDEA. Skip this state; it remains in the doc only as a no-op marker for backward-compat with v1's state numbers. |
| **S9** | Capture per-IDEA compound candidates (unchanged). |
| **S10** | Finalise per-IDEA auto-run log (unchanged). |
| **S11** | Move to next IDEA — integration worktree stays up, ready for next IDEA's S2 reset cycle. |

### Integration phase (NEW — S11.5 to S11.13)

| State | What |
|---|---|
| **S11.5** | **Verify integration worktree state** — already up since S(-1). Final pre-merge reset: `docker compose down -v && docker compose up -d`, migrate + seed (back to clean main-equivalent state). |
| **S11.6** | **Sequential merge** — `git checkout integration/sprint-auto-<batch-iso>`. For each `auto/<slug>` in batch-arg order: `git merge --no-ff auto/<slug>`. On conflict: resolve on integration branch using the algorithm catalogue ([`references/integration-conflict-resolutions.md`](references/integration-conflict-resolutions.md) — NEW), commit as separate `resolve: integrate auto/<X>` commit. |
| **S11.7** | **Batch wrap on integration branch** — compose all N devlog entries (chronological/numerical concat); apply all N ideas-index moves in one commit. ONE `wrap-batch: devlog + index for sprint-auto-<batch-iso>` commit. |
| **S11.8** | **Integration tests — union** — read each merged-in IDEA's plan-doc Verification section, union test paths, run pytest. Migrate up if migrations were merged. Failure → fix on integration branch, cap of 10 attempts (fresh commits, revert between attempts). |
| **S11.9** | **Full test suite** (sprint-end gate per Q5) — full pytest on the integrated state. Same fix discipline, cap of 10. |
| **S11.10** | **Bugbot-loop on integration branch via [INTEGRATION] draft PR** — open draft PR titled `[INTEGRATION] sprint-auto-<batch-iso>` from the integration branch targeting main. Body: `Auto-generated integration validation. NOT FOR MERGE. Auto-closed at sprint-auto teardown.` Run `/bugbot-loop` against it. **Cap 20 attempts** — integration branches are elephants (N-times-larger review surface than any per-PR PR; T2/T3 findings have proportionally longer tails). Symmetric with the per-IDEA deliverables cap (S4) — integration is deliverables-class review of the integrated state, not docs-class. |
| **S11.11** | **Forward-sync integration branch into each `auto/<slug>`** — `git checkout auto/<slug>; git merge --no-ff integration/sprint-auto-<batch-iso>`. Force-push not needed (forward-sync only fast-forwards or adds merge commits). PR auto-updates; bugbot fires automatically. |
| **S11.12** | **Per-PR PR re-bugbot + verification** — for each per-PR PR: route to integration worktree, `git checkout auto/<slug>` (now post-forward-sync state), reset DB, run targeted tests one final time, run `/bugbot-loop`. Cap 5 attempts each. Most will clean-signal immediately because the new commits are wrap + resolutions, not deliverables work. |
| **S11.13** | **Integration teardown** — `docker compose down` (NOT `down -v`; volumes preserved for inspection). Worktree filesystem stays. Close `[INTEGRATION]` draft PR with comment `auto-closed by sprint-auto teardown; integration validation complete. See auto-run summary at <path>.` Integration branch lingers locally; cleaned up by human's `/wrap NNN` post-merge teardown for the LAST IDEA of the batch (extend `/wrap` to detect last-of-batch and `git branch -d integration/sprint-auto-<batch-iso>`). |

Then S12 (compound) runs unchanged.

## Wrap-stage redesign (unchanged from v2)

Per-IDEA `/wrap --scope=idea-only` (S5) writes:
- IDEA frontmatter flip — KEEP
- Downstream docs scan (per IDEA's own touched paths) — KEEP
- ideas-index entry move — REMOVE (moves to S11.7 batch operation)
- DEVELOPMENT_LOG entry append — REMOVE (moves to S11.7 batch operation)

Implementation: `skills/wrap/SKILL.md` adds `--scope=idea-only` flag.

## Verification routing — the architectural core

The defining v3 mechanism. Three skills currently bootstrap their own docker stack in the current worktree:
- `/work` (S2) verifies via `pytest` against the worktree's stack
- `/bugbot-loop` Phase 0 brings up the worktree's stack if absent
- Generic test commands assume current-worktree docker

Under sprint-auto v3, all of these route to the integration worktree instead. Mechanism:

1. **Sprint-auto exports an env var `SPRINT_AUTO_INTEGRATION_WORKTREE=/path/to/integration/worktree`** at S(-1).
2. **`/work`'s verification step**: when this env var is set, all `docker compose` and `pytest` commands `cd $SPRINT_AUTO_INTEGRATION_WORKTREE` first; before running tests, `git fetch && git checkout auto/<slug>` + `docker compose up -d --force-recreate web celery` to refresh mounted code.
3. **`/bugbot-loop`'s Phase 0**: when env var is set, skip current-worktree stack bootstrap; route verification to integration worktree.
4. **Per-IDEA reset**: at the entry to S2 for each IDEA, sprint-auto runs `docker compose down -v && docker compose up -d && migrate + seed` in the integration worktree. This is the "main-equivalent baseline" for that IDEA's tests + bugbot session.

DB reset is **per-IDEA, NOT per-bugbot-commit**. Within a bugbot session, the DB state is "main + this IDEA's migrations applied once" — fix commits don't typically migrate, so that DB state is consistent for the duration of the bugbot session. Resetting between bugbot commits would multiply wall-clock 10x with no result-quality gain. Resetting between IDEAs is what makes per-PR PRs independently deliverable.

## Files this plan would touch (during implementation)

### Major (architectural)

- `skills/sprint-auto/SKILL.md` — fundamental rewrite of S0 (code-surface only), new pre-batch S(-1), modified verification routing in S2/S3/S6, S8 marked no-op, S11.5–S11.13 detailed; new interaction rules covering env var contract
- `skills/sprint-auto/references/post-pr-sequence.md` — new state machine S(-1) → S0–S15 with verification routing
- `skills/sprint-auto/references/worktree-lifecycle.md` — drops per-IDEA stack bootstrap from default; documents code-surface-only mode + integration-worktree-as-runtime model
- `skills/sprint-auto/references/integration-stage.md` — NEW: integration worktree lifecycle, branch-switch protocol, DB reset protocol, [INTEGRATION] draft PR mechanic
- `skills/sprint-auto/references/integration-conflict-resolutions.md` — NEW: catalogued resolution patterns (devlog chronological concat, index alphabetical/numerical re-sort, .po include-both, html/js per-case)
- `skills/sprint-auto/assets/auto-run-log-template.md` — Integration check section template (merge results, test results, bugbot results, propagation results, re-bugbot results)

### Cross-skill (verification routing)

- `skills/work/SKILL.md` — verification step honors `SPRINT_AUTO_INTEGRATION_WORKTREE` env var (route to that worktree if set)
- `commands/bugbot-loop.md` — Phase 0 skip-bootstrap rule when env var set; Phase 2/3 verification routes to integration worktree

### Tooling

- `tools/sprint-auto-bootstrap.sh` (per project) — accept `--code-only` flag (skips `.env` rewrite + `docker compose up` + post-up init); standard mode (no flag) for integration worktree

### Wrap-skill changes (unchanged from v2)

- `skills/wrap/SKILL.md` — add `--scope=idea-only` mode + extend post-merge to detect last-of-batch and clean up `integration/sprint-auto-*` branch + integration worktree

## Files NOT touched (out of scope)

- IDEA gate criteria (`auto_safe`, etc.) — unchanged
- Compound stage S12+ — unchanged
- The PR-creation contract (per-PR PRs against main) — unchanged

## Open questions (down to 3, plus 1 calibration)

1. **Env var name**: `SPRINT_AUTO_INTEGRATION_WORKTREE` — verbose but explicit. Alternative: `SPRINT_AUTO_INTEG_PATH` shorter, harder to grep. Preference?

2. **Bugbot-loop Phase 0 detection**: when env var is set, skip current-worktree stack bootstrap. But bugbot-loop also currently does `.env` template-rewrite if missing — under v3 the per-IDEA worktree has NO `.env` and shouldn't get one. Add a second guard: skip `.env` creation in per-IDEA worktrees during sprint-auto. Confirm or adjust.

3. **Worktree forensic loss**: post-batch, per-IDEA worktrees are dead-code-only — the morning reviewer can read code but can't `cd` in and run anything live. Only the integration worktree retains state. Acceptable given the resource savings (the integration state IS the relevant inspection artifact), but flagging explicitly so it's not a surprise.

4. **Cap calibration** (calibrated v3 → v3.1):
   - S4 deliverables escalation: **20** (carried from v1; long T2/T3 tail on per-IDEA work)
   - S7 docs escalation: **5** (stylistic / reference-drift; converges fast or it doesn't)
   - S11.8/S11.9 integration tests: **10** each (cross-cutting failures have shorter tails than per-IDEA)
   - S11.10 integration bugbot: **20** ← raised from 5 in v3.0 per "elephants" redirect — integration branches have N-times-larger review surface than any per-PR PR; symmetric with S4 deliverables cap; this is deliverables-class review, not docs-class
   - S11.12 post-propagation re-bugbot per-PR PR: **5** (small post-propagation surface; just resolution + wrap commits on top of already-clean PR; should clean-signal immediately or with 1-2 fixes)
   First real batch confirms or adjusts.

## Acid test — first-batch validation criteria

Pick a small acid-test batch (2 IDEAs, ideally with known shared file edits) before doing a full 6-IDEA overnight run. Pass criteria:

- [ ] Single docker stack visible during the batch (port offset `+30000` only)
- [ ] Primary dev stack untouched (verifies `docker ps` shows your normal containers + the integration stack only)
- [ ] Per-IDEA verification runs on integration worktree (visible via the auto-run log's verification location field)
- [ ] DB reset confirmed between IDEAs (the integration worktree's `docker logs db` shows fresh init twice)
- [ ] [INTEGRATION] draft PR opened, bugbot ran, draft PR closed without merge at end
- [ ] Per-PR PRs forward-synced from integration branch (verifiable via `git log auto/<slug>` showing the merge commit)
- [ ] Re-bugbot fired automatically on per-PR PRs after forward-sync
- [ ] Devlog and ideas-index updated EXACTLY ONCE on integration branch (not N times across N branches)
- [ ] Both per-PR PRs merge cleanly to main without conflict (THE acid test for the wrap-stage fix)
- [ ] Wall-clock under 90 minutes for 2-IDEA batch

If acid test passes, run a 6-IDEA batch on a low-stakes night.

## Concrete next step

If you green-light v3:
1. Open `feature/sprint-auto-integration-stage` off `origin/main`
2. Implement S(-1) bootstrap + S0 code-surface narrowing in `skills/sprint-auto/SKILL.md`
3. Add verification routing in `skills/work/SKILL.md` + `commands/bugbot-loop.md`
4. Add `--scope=idea-only` mode in `skills/wrap/SKILL.md`
5. Add `--code-only` flag to `tools/sprint-auto-bootstrap.sh` (per project, e.g. teisutis first)
6. Implement S11.5–S11.13 + new reference docs
7. Open implementation PR; bugbot it; merge after review
8. Acid-test on a 2-IDEA teisutis batch; if pass, ship for next 6-IDEA overnight

## References

- [`IDEA_integration_branch.md`](IDEA_integration_branch.md) — source idea + 9 design questions
- [`SKILL.md`](SKILL.md) — current S0–S15 state machine (v3 inserts S(-1), narrows S0, adds S11.5–S11.13)
- [`references/post-pr-sequence.md`](references/post-pr-sequence.md) — per-IDEA loop detail (rewritten in v3)
- [`references/worktree-lifecycle.md`](references/worktree-lifecycle.md) — touched by v3 (code-surface mode, integration-worktree-as-runtime)
- [`../wrap/SKILL.md`](../wrap/SKILL.md) — touched by this plan (`--scope=idea-only`, last-of-batch detection)
- [`../work/SKILL.md`](../work/SKILL.md) — touched by this plan (verification routing via env var)
- [`../../commands/bugbot-loop.md`](../../commands/bugbot-loop.md) — touched by this plan (Phase 0 skip-bootstrap rule)
- [`../../rules/RULE_parallel-worktree-docker.md`](../../rules/RULE_parallel-worktree-docker.md) — worktree pattern; v3 narrows the per-worktree stack assumption for sprint-auto
- [`../../rules/RULE_git-safety.md`](../../rules/RULE_git-safety.md) — confirms forward-sync (S11.11) is agent-allowed; the [INTEGRATION] draft PR is a non-merging artefact

---

**Last Updated**: 2026-04-27 v3 (post-redirect on hardware constraint + results-oriented call). Single integration stack as the test-runner; per-IDEA worktrees code-surface-only; full DB reset between IDEAs guarantees independently deliverable PRs.

**v2 (superseded)**: 2026-04-27 — Q4/Q5/Q6 redirects, wrap-stage insight, but kept N+1 docker stacks. See git history.

**v1 (superseded)**: 2026-04-27 — initial draft. See git history.
