# sprint-auto: integration branch for cross-PR conflict detection

> **⚠️ SUPERSEDED IN PART by v3.2 (integration-as-merge-gate).** This is the v3.1 **design record**, retained for provenance. The v3.1 mechanics described below — **forward-sync (S11.11)**, **per-PR re-review (S11.12)**, the **`--draft` / auto-closed `[INTEGRATION]` PR**, and **last-of-batch `/wrap NNN` teardown** — were all deleted or inverted in v3.2: the `[INTEGRATION]` PR is now **non-draft and the merge gate** (left OPEN for the human; per-IDEA PRs target the integration branch and auto-close as ancestors), and batch teardown runs via **`/wrap --integration <batch-iso>`**. For current behavior see [`references/integration-stage.md`](references/integration-stage.md), [`references/post-pr-sequence.md`](references/post-pr-sequence.md) (diagrams = v3.2), and `SKILL.md`. The **first-batch monitoring signals** below still apply.

**Status**: planned (v3.1, ready to implement) — **superseded by v3.2; see banner above**
**Surfaced**: 2026-04-27 (during a sprint-auto batch — two PRs staged together produced a 12-file conflict that no per-PR check caught)
**Last revised**: 2026-04-27 v3.1 — all open design questions resolved through user redirects in this session. Implementation gated only on a green-light to open `feature/sprint-auto-integration-stage`.

This document captures both the **problem** (the original idea, written by an agent overnight) and the **planned solution** (the implementation design, drafted with user redirects in this session). The single-file form replaces the earlier split across `IDEA_*` + `PLAN_*` per the user's preference.

---

# Part 1 — The problem

`sprint-auto` runs N IDEAs in isolated git worktrees, each with its own docker stack. Each worktree's tests run **in isolation against that worktree's branch**. The review loop reviews each branch **in isolation against `main`**.

What never gets tested: the **integrated state** of all N branches merged together. Two PRs may individually pass tests, individually clear review, and individually look fine on staging — but conflict at merge time when both edit the same regions of the same files.

## Worked example — 2026-04-27

- Two PRs (IDEA-124, audio playback fallback + dark theme; IDEA-125, audio transcription pre-send) both modify `web/<ai-app>/templates/<ai-app>/chat.html` and 8 of the same `.po` files. Both passed review. Both passed staging tests in isolation.
- When the user wanted to test #376 ON TOP of #375 to verify they work together, the local `git merge auto/audio-playback... into auto/audio-transcription...` produced **12 conflict files** to resolve manually. The conflicts were all "include both contributions" merges (each PR added independent translation keys near each other) — none were destructive, but resolving 12 files for a throwaway local test was overhead.

The merge-conflict surface is invisible during the sprint-auto run itself. It only shows up after the human starts merging (and by then review's clean signal on the per-PR state has nothing to say about the merge result).

## The deeper structural insight

The 12-file conflict was the visible part. There is a **structural** problem hiding underneath: every per-IDEA `/wrap` commit (S5 in the existing state machine) edits the same lines of two files:

- `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md` (every IDEA appends an entry near the top)
- `docs/ideas/README.md` (every IDEA moves itself from "priority" to "References — Implemented")

When N IDEAs run in parallel, all N worktrees write the same lines. **Every batch ≥2 IDEAs guarantees N-way line-conflicts** on those two files. The conflicts have been a silent tax on every batch — not just IDEA-124/125. The integration-branch design has to fix this at the source, not just resolve it after the fact.

## Out of scope for this design

- **Replacing per-PR review.** The integration step is additive. Each `auto/*` PR still gets its own review pass against `main`.
- **Replacing the human merge.** The integration branch never gets merged to `main`. Per-PR merges still go through GitHub's UI with the human at the controls (per `RULE_git-safety`).
- **A long-lived develop/staging branch.** This is per-batch, disposable. Not gitflow.
- **The existing project-level `staging` worktree** (which tracks `main` + manual human-present testing). That artefact is human-owned and untouched by sprint-auto. The new integration worktree is a separate disposable artefact named `integration/sprint-auto-<batch-iso>`.

---

# Part 2 — The solution (v3.1 plan)

## Naming clarification — "integration" worktree vs. existing "staging" worktree

These are two **distinct** artefacts the plan keeps strictly separate:

| Artefact | Purpose | Lifecycle | Owner |
|---|---|---|---|
| **Existing `staging` worktree** (project-level, predates sprint-auto) | Tracks `main`; human stacks manual experiments / pre-merge testing on top during human-present sessions | Long-lived; never owned by sprint-auto | Human |
| **`integration/sprint-auto-<batch-iso>` worktree** (NEW, created by this plan) | Disposable per-batch sprint-auto integrator + test-runner; never receives manual edits | Created at S(-1); torn down post-merge by `/wrap NNN` of last-of-batch IDEA | Sprint-auto |

Sprint-auto must never `git checkout` the human's staging branch, never bring up its docker stack, never write to its filesystem. The integration worktree has its own branch, its own port offset (`+30000`), its own filesystem path.

## Headline change

The integration worktree is **the only docker stack for the entire batch**. Per-IDEA worktrees become pure code surfaces (no `.env`, no `docker compose up`, no port offsets). All verification — per-IDEA targeted tests, per-IDEA review fix-cycles, integration union, integration full suite, integration review, post-propagation re-review — runs on the single shared integration stack with DB resets between IDEAs.

This is a "CI-runner-style" sprint-auto:
- One docker stack at port offset `+30000` (see "Port-offset math" below), the entire batch
- Existing project staging stack on default ports never touched
- Per-IDEA worktrees on disk for code-surface isolation only
- Results-oriented: full DB reset between IDEAs guarantees each PR is tested against a main-equivalent DB → genuinely independently deliverable

## Locked decisions

| Decision | Choice | Source |
|---|---|---|
| Q4 (conflict) | Resolve on integration branch → validate → forward-sync into each `auto/<slug>` | user redirect |
| Q5 (test scope) | Union during integration **+ full suite at sprint-end** | user redirect |
| Q6 (review) | Fire on integration branch via `[INTEGRATION]` draft PR | user redirect |
| Architecture | Single test-runner stack on integration worktree (NOT N+1 stacks) | user redirect (hardware) |
| DB reset cadence | Full reset between IDEAs | user redirect (results-oriented) |
| The review loop coverage | Per-PR (deliverables + docs) AND integration AND post-propagation re-review | user redirect (results-oriented = review everything) |
| Env var | `SPRINT_AUTO_INTEGRATION_WORKTREE` | user redirect |
| Per-IDEA `.env` | Never created. The review loop is review-only; verification routes to integration worktree | user redirect |
| Per-IDEA worktree forensics | Not maintained; disposable | user redirect |

## Port-offset math (why `+30000`, not `+70000`)

TCP port space is 16-bit: 1–65535. Linux ephemeral range (default): 32768–60999. For a stack offset `N`, the highest service port we typically remap is Elasticsearch transport at 9300, so the binding port is `9300 + N`. Constraints:

- `9300 + N ≤ 65535` → `N ≤ 56235` (hard ceiling)
- `9300 + N ≤ 49151` → `N ≤ 39851` (stay in registered-port range — recommended)
- `9300 + N ≤ 32768` → `N ≤ 23468` (stay below ephemeral range — most defensive)

**`+30000`** for the integration stack:
- Max remapped port = 9300 + 30000 = 39300 → in registered range, room to grow
- Defensive against any ad-hoc parallel-worktree stack at the conventional `+10000` from `RULE_parallel-worktree-docker`
- Well below the hard ceiling

**Latent bug exposed (out of scope, worth follow-up)**: existing sprint-auto v1's per-IDEA `+10000, +20000, ..., +60000` scheme is broken for batches with 6+ IDEAs — IDEA-6's ES transport at 9300 + 60000 = 69300 overflows. v3's collapse to a single stack sidesteps the bug entirely; the existing rule note "+10000 is a safe starting point" should grow a ceiling caveat in a separate `RULE_parallel-worktree-docker` PR.

## Wall-clock budget (6-IDEA batch)

| Phase | Cost | Notes |
|---|---|---|
| Preflight + integration bootstrap | ~5 min | One-time at batch start |
| Per-IDEA × 6: reset + work + targeted tests + review | ~30 min × 6 = 180 min | Reset ~5 min; work ~10 min; tests ~3 min; review ~12 min avg |
| Integration: merge + union + full suite + review via [INTEGRATION] PR | ~60–120 min | Sequential merge ~5 min, union ~10 min, full suite ~25 min, review avg ~30 min / worst-case ~80 min (cap 20 attempts — see S11.10) |
| Forward-sync × 6 + per-PR re-review × 6 | ~30 min | Forward-sync ~1 min each; re-review ~4 min each (mostly clean against unchanged code) |
| Teardown | ~3 min | `docker compose down`, close [INTEGRATION] draft PR |
| **Total** | **~5–6.5 hours** (avg ~5 / elephant-batch worst case ~6.5) | Acceptable for overnight runs starting midnight–1 AM. Review-loop's own 180-min active bound caps S11.10 worst case independently. |

Compare to current v1 sprint-auto (no integration): ~3 hours for 6 IDEAs. **+2 to +3.5 hours** for guaranteed-no-conflict-at-merge + integration validation + result-quality gains. Trade accepted.

## State machine

The per-IDEA loop's S0 narrows; new pre-batch state S(-1) for integration bootstrap; S11.5–S11.13 added between per-IDEA loop end and compound consolidation.

### Pre-batch (NEW)

| State | What |
|---|---|
| **S(-1)** | **Integration bootstrap** — `git worktree add ../<project>-auto-integration-<batch-iso> -b integration/sprint-auto-<batch-iso> origin/main`; run `tools/sprint-auto-bootstrap.sh` with port offset `+30000`. This is the ONLY docker stack the batch will use. Failure here = abort batch. Export `SPRINT_AUTO_INTEGRATION_WORKTREE=<path>` for downstream skill routing. |

### Per-IDEA loop (modified — NO docker per IDEA)

| State | What |
|---|---|
| **S0** | **Code-surface worktree only** — `git worktree add ../<project>-auto-<slug> -b auto/<slug> origin/main`. NO `.env`. NO `docker compose up`. NO post-up init. Just code. |
| **S1** | Plan unchanged — markdown read/write, no runtime needed. |
| **S2** | `/work` writes code + commits + opens PR. **Verification routes to integration worktree** via env var: cd to `$SPRINT_AUTO_INTEGRATION_WORKTREE`, `git checkout auto/<slug>`, `docker compose down -v && docker compose up -d` (full reset), wait for healthchecks, `migrate + seed`, run targeted tests. Pass → continue. Fail → back to /work step. |
| **S3** | Deliverables review-loop on per-PR PR. The review loop is a code-review service: Cursor reviews remotely, review-loop reads findings + commits fixes locally to per-IDEA branch. Review-loop's Phase 0 detects the env var and skips entirely (no `.env`, no docker in per-IDEA worktree). **Each fix's verification routes to integration worktree** with checkout-and-test cycle (no DB reset within an IDEA's review session — fix commits don't typically migrate; reset cost would explode). One reset at IDEA entry, fix-cycle uses that reset baseline. |
| **S4** | Deliverables escalation (T2/T3) — same contract as v1, max 20 attempts. |
| **S5** | `/wrap --scope=idea-only` (NEW MODE) — frontmatter flip + downstream-docs scan ONLY. Skips devlog + ideas-index writes. Those move to S11.7 (batch wrap on integration branch). |
| **S6** | Docs review-loop on per-PR PR. Verification: route to integration worktree, no DB reset (docs commits don't change runtime behavior). |
| **S7** | Docs escalation (T2/T3) — max 5 attempts. |
| **S8** | **Per-IDEA teardown — N/A in v3.** No per-IDEA stack to tear down. The integration stack stays up for the next IDEA. Skip; remains in the doc as a no-op marker for backward-compat with v1's state numbers. |
| **S9** | Capture per-IDEA compound candidates (unchanged). |
| **S10** | Finalise per-IDEA auto-run log (unchanged). |
| **S11** | Move to next IDEA — integration worktree stays up, ready for next IDEA's S2 reset cycle. |

### Integration phase (NEW — S11.5 to S11.13)

| State | What |
|---|---|
| **S11.5** | **Verify integration worktree state** — already up since S(-1). Final pre-merge reset: `docker compose down -v && docker compose up -d`, migrate + seed (back to clean main-equivalent state). |
| **S11.6** | **Sequential merge** — `git checkout integration/sprint-auto-<batch-iso>`. For each `auto/<slug>` in batch-arg order: `git merge --no-ff auto/<slug>`. On conflict: resolve on integration branch using the algorithm catalogue (`references/integration-conflict-resolutions.md` — NEW), commit as separate `resolve: integrate auto/<X>` commit. |
| **S11.7** | **Batch wrap on integration branch** — compose all N devlog entries (chronological/numerical concat); apply all N ideas-index moves in one commit. ONE `wrap-batch: devlog + index for sprint-auto-<batch-iso>` commit. |
| **S11.8** | **Integration tests — union** — read each merged-in IDEA's plan-doc Verification section, union test paths, run pytest. Migrate up if migrations were merged. Failure → fix on integration branch, cap of 10 attempts (fresh commits, revert between attempts). |
| **S11.9** | **Full test suite** (sprint-end gate per Q5) — full pytest on the integrated state. Same fix discipline, cap of 10. |
| **S11.10** | **Review-loop on integration branch via [INTEGRATION] draft PR** — open draft PR titled `[INTEGRATION] sprint-auto-<batch-iso>` from the integration branch targeting main. Body: `Auto-generated integration validation. NOT FOR MERGE. Auto-closed at sprint-auto teardown.` Run `/<engine>-loop` against it. **Cap 20 attempts** — integration branches are elephants (N-times-larger review surface than any per-PR PR; T2/T3 findings have proportionally longer tails). Symmetric with the per-IDEA deliverables cap (S4) — integration is deliverables-class review of the integrated state, not docs-class. |
| **S11.11** | **Forward-sync integration branch into each `auto/<slug>`** — `git checkout auto/<slug>; git merge --no-ff integration/sprint-auto-<batch-iso>`. Force-push not needed (forward-sync only fast-forwards or adds merge commits). PR auto-updates; review fires automatically. |
| **S11.12** | **Per-PR PR re-review + verification** — for each per-PR PR: route to integration worktree, `git checkout auto/<slug>` (now post-forward-sync state), reset DB, run targeted tests one final time, run `/<engine>-loop`. Cap 5 attempts each. Most will clean-signal immediately because the new commits are wrap + resolutions, not deliverables work. |
| **S11.13** | **Integration teardown** — `docker compose down` (NOT `down -v`; volumes preserved for inspection). Worktree filesystem stays. Close `[INTEGRATION]` draft PR with comment `auto-closed by sprint-auto teardown; integration validation complete. See auto-run summary at <path>.` Integration branch lingers locally; cleaned up by human's `/wrap NNN` post-merge teardown for the LAST IDEA of the batch (extend `/wrap` to detect last-of-batch and `git branch -d integration/sprint-auto-<batch-iso>`). |

Then S12 (compound) runs unchanged.

## Wrap-stage redesign

Per-IDEA `/wrap --scope=idea-only` (S5) writes:
- IDEA frontmatter flip (`status: in-progress` → `status: complete` + `completed: <date>`) — KEEP
- Downstream docs scan (per IDEA's own touched paths) — KEEP
- ideas-index entry move — REMOVE (moves to S11.7 batch operation)
- DEVELOPMENT_LOG entry append — REMOVE (moves to S11.7 batch operation)

This eliminates the structural N-way conflict on devlog/index lines at its source. `skills/wrap/SKILL.md` adds the `--scope=idea-only` flag.

## Verification routing — the architectural core

Sprint-auto exports `SPRINT_AUTO_INTEGRATION_WORKTREE=/path/to/integration/worktree` at S(-1). When this env var is set:

1. **`/work`'s verification step**: all `docker compose` and `pytest` commands `cd $SPRINT_AUTO_INTEGRATION_WORKTREE` first; before running tests, `git fetch && git checkout auto/<slug>` + `docker compose up -d --force-recreate web celery` to refresh mounted code.
2. **`/<engine>-loop`'s Phase 0**: skip entirely. No `.env` creation, no `docker compose up` in per-IDEA worktree. The review loop is a code-review service; it doesn't need a runtime in the per-IDEA worktree. Fix-verification (the only step that needs runtime) routes to the integration worktree.
3. **Per-IDEA reset**: at the entry to S2 for each IDEA, sprint-auto runs `docker compose down -v && docker compose up -d && migrate + seed` in the integration worktree. This is the "main-equivalent baseline" for that IDEA's tests + review session.

DB reset is **per-IDEA, NOT per-review-commit**. Within a review session, the DB state is "main + this IDEA's migrations applied once" — fix commits don't typically migrate, so that DB state is consistent for the duration of the review session. Resetting between review commits would multiply wall-clock 10x with no result-quality gain. Resetting between IDEAs is what makes per-PR PRs independently deliverable.

## Cap budgets (starting points; calibrate over time)

| State | Cap | Reason |
|---|---|---|
| S4 deliverables escalation | **20** | Long T2/T3 tail on per-IDEA work |
| S7 docs escalation | **5** | Stylistic / reference-drift; converges fast or not at all |
| S11.8 / S11.9 integration tests | **10** each | Cross-cutting failures have shorter tails than per-IDEA |
| S11.10 integration review | **20** | Elephants — N-times-larger review surface; deliverables-class, not docs-class |
| S11.12 post-propagation re-review | **5** | Small post-propagation surface; resolution + wrap commits on already-clean PR |

First batches will calibrate; numbers above are starting points, not contracts.

## Files this plan would touch (during implementation)

### Major (architectural)
- `skills/sprint-auto/SKILL.md` — fundamental rewrite of S0 (code-surface only), new pre-batch S(-1), modified verification routing in S2/S3/S6, S8 marked no-op, S11.5–S11.13 detailed; new interaction rules covering env var contract
- `skills/sprint-auto/references/post-pr-sequence.md` — new state machine S(-1) → S0–S15 with verification routing
- `skills/sprint-auto/references/worktree-lifecycle.md` — drops per-IDEA stack bootstrap from default; documents code-surface-only mode + integration-worktree-as-runtime model
- `skills/sprint-auto/references/integration-stage.md` — NEW: integration worktree lifecycle, branch-switch protocol, DB reset protocol, [INTEGRATION] draft PR mechanic
- `skills/sprint-auto/references/integration-conflict-resolutions.md` — NEW: catalogued resolution patterns (devlog chronological concat, index alphabetical/numerical re-sort, .po include-both, html/js per-case)
- `skills/sprint-auto/assets/auto-run-log-template.md` — Integration check section template (merge results, test results, review results, propagation results, re-review results)

### Cross-skill (verification routing)
- `skills/work/SKILL.md` — verification step honors `SPRINT_AUTO_INTEGRATION_WORKTREE` env var
- `skills/review-loop/SKILL.md` — Phase 0 skip-bootstrap rule when env var set (the unified loop carries it)

### Tooling (per project)
- `tools/sprint-auto-bootstrap.sh` — accept `--code-only` flag (skips `.env` rewrite + `docker compose up` + post-up init); standard mode (no flag) for integration worktree

### Wrap-skill changes
- `skills/wrap/SKILL.md` — add `--scope=idea-only` mode + extend post-merge to detect last-of-batch and clean up `integration/sprint-auto-*` branch + integration worktree

## Files NOT touched (out of scope)

- IDEA gate criteria (`auto_safe`, etc.) — unchanged
- Compound stage S12+ — unchanged
- The PR-creation contract (per-PR PRs against main) — unchanged

## Stakes context

There is no "low-stakes night" for this workflow. The originating project has grown massive pre-release; the budget/timeline pressure is what makes sprint-auto necessary in the first place — every batch is high-risk-high-reward, and the workflow exists because the alternative is shipping slower than the project can afford. v3's design leans into that: results-oriented over performance, review-everything, full DB reset between IDEAs. Validation framing throughout this plan is about the **first batch under v3 mechanics**, not about choosing safe IDEAs — the IDEAs in any given batch will be whatever's next in the queue.

## First-batch monitoring — what to watch on signal

The first sprint-auto run with v3 mechanics is a real batch (every batch is). Watch these signals during and after; they're how you'll catch v3 implementation bugs early before they corrupt batch state:

- [ ] Single docker stack visible during the batch (port offset `+30000` only) — `docker compose ls` should show one project, not N
- [ ] Existing staging worktree's stack untouched throughout — your manual-testing surface stays clean
- [ ] Per-IDEA verification routes to integration worktree (visible in the auto-run log's `verification_location` field; should be the integration worktree path, never a per-IDEA worktree path)
- [ ] DB reset between IDEAs (`docker logs db` for the integration worktree shows N fresh init events for an N-IDEA batch, not one)
- [ ] `[INTEGRATION]` draft PR opened, review ran on it, draft PR closed without merge at S11.13
- [ ] Per-PR PRs forward-synced from integration branch — `git log auto/<slug>` shows the merge commit at the tip
- [ ] Re-review fired automatically on per-PR PRs after forward-sync (visible in PR comment timeline)
- [ ] **Devlog and ideas-index updated EXACTLY ONCE on integration branch**, not N times across N `auto/<slug>` branches — this is the wrap-stage-conflict acid test; if you see N devlog edits across N branches, the `--scope=idea-only` flag isn't being honored
- [ ] Per-PR PRs merge to main without conflict (THE structural acid test — if any PR conflicts at human merge time, v3's premise is broken)
- [ ] Wall-clock within budget (~5–6.5h for 6 IDEAs; flag if outside)

If these signals hold on the first batch, v3 is working. If a signal breaks, the auto-run log gives the diagnostic point — no need to recreate state.

## Concrete next step

When green-lit:
1. Open `feature/sprint-auto-integration-stage` off `origin/main`
2. Implement S(-1) bootstrap + S0 code-surface narrowing in `skills/sprint-auto/SKILL.md`
3. Add verification routing in `skills/work/SKILL.md` + `skills/review-loop/SKILL.md`
4. Add `--scope=idea-only` mode in `skills/wrap/SKILL.md`
5. Add `--code-only` flag to `tools/sprint-auto-bootstrap.sh` (per project)
6. Implement S11.5–S11.13 + new reference docs
7. Open implementation PR; review it; merge after review
8. First real batch under v3.1; monitor signals above

## References

- [`SKILL.md`](SKILL.md) — current S0–S15 state machine (v3.1 inserts S(-1), narrows S0, adds S11.5–S11.13)
- [`references/post-pr-sequence.md`](references/post-pr-sequence.md) — per-IDEA loop detail (rewritten in v3.1)
- [`references/worktree-lifecycle.md`](references/worktree-lifecycle.md) — touched by v3.1 (code-surface mode, integration-worktree-as-runtime)
- [`../wrap/SKILL.md`](../wrap/SKILL.md) — touched by this plan (`--scope=idea-only`, last-of-batch detection)
- [`../work/SKILL.md`](../work/SKILL.md) — touched by this plan (verification routing via env var)
- [`../review-loop/SKILL.md`](../review-loop/SKILL.md) — touched by this plan (Phase 0 skip-bootstrap rule when env var set, in the unified loop)
- [`references/PARALLEL_WORKTREE_DOCKER.md`](references/PARALLEL_WORKTREE_DOCKER.md) — worktree pattern; v3.1 narrows the per-worktree stack assumption for sprint-auto
- [`../../rules/RULE_git-safety.md`](../../rules/RULE_git-safety.md) — confirms forward-sync (S11.11) is agent-allowed; the `[INTEGRATION]` draft PR is a non-merging artefact
- Existing sprint-auto state machine: `skills/sprint-auto/SKILL.md` (S0–S15)

---

## Revision history

- **2026-04-27 v3.1**: all open Qs resolved (env var name locked, review per-IDEA worktrees no-`.env`/no-docker, per-IDEA worktrees not maintained as forensic artefacts, cap budgets accepted); stakes context added; ready for implementation
- **2026-04-27 v3**: post-redirect on hardware constraint + results-oriented call. Single integration stack as the test-runner; per-IDEA worktrees code-surface-only; full DB reset between IDEAs guarantees independently deliverable PRs
- **2026-04-27 v2**: Q4/Q5/Q6 redirects, wrap-stage insight surfaced, but kept N+1 docker stacks (rejected by hardware constraint)
- **2026-04-27 v1**: initial draft with v1 recommendations on Q4/Q5/Q6 (superseded by v2)
- **2026-04-27 (initial)**: IDEA captured by agent during overnight batch test loop. 9 open design questions left for the parallel Claude session — all resolved through user redirects in this same session
