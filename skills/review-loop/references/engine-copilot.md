# engine-copilot — GitHub Copilot adapter

Adapter specification for the GitHub Copilot review engine. The orchestrator at [`SKILL.md`](../SKILL.md) drives this engine via the tool surface; the reference surface (this file) documents quirks the agent needs when triaging findings.

## § Identity

- Vendor: GitHub Copilot.
- GitHub user logins — **dual identity**:
  - `Copilot` (single-token) on `/pulls/<N>/requested_reviewers`.
  - `copilot-pull-request-reviewer[bot]` (bracketed) on `/pulls/<N>/reviews`.
- Phase 1's comment fetcher filters on BOTH logins to capture review-requests + actual review posts.

## § Tool invocations

- `./tools/find_copilot_comments.sh <PR_NUMBER>` — fetches reviews + inline findings from BOTH Copilot logins (`Copilot` on `/pulls/<N>/requested_reviewers` and `copilot-pull-request-reviewer[bot]` on `/pulls/<N>/reviews` — see § Identity above), emits the contract-shape stream (`COPILOT_LATEST_REVIEW=...`, `COPILOT_CLEAN_SIGNAL=...` if applicable, then findings, plus optional `COPILOT_CHECKRUN=...` informational marker).
- `./tools/copilot_retrigger.sh <PR_NUMBER>` — runs `gh pr edit <PR> --add-reviewer @copilot` (requires `gh` ≥ 2.88). Pre-approvable in `~/.claude/settings.json`. A `remove+add` fallback is commented in the script body for projects where Copilot has NOT self-removed after a prior review (rare; the bare `--add` works for the typical post-review re-trigger case).

**Retrigger semantics — empirically confirmed**: Copilot self-removes from `requested_reviewers` after posting each review. Bare `--add-reviewer @copilot` therefore IS the canonical retrigger for the in-loop case (Copilot has posted a review and self-removed; we re-add to request another). The earlier "bare `--add` is a no-op" observation applies only to the *still-pending* reviewer state (review never posted) — for which the commented-out `remove+add` fallback exists.

## § Clean detection

**Clean is structural** — see § Review-state gate: Copilot's check-run `STATUS=completed` (DONE) AND zero active findings matching `COPILOT_LATEST_REVIEW`. Copilot's review state is always `COMMENTED` (never `APPROVED`), so APPROVED-state matching is not applicable, and `CONCLUSION=success` means "Copilot ran", not "code is clean" — never read a verdict off it.

`find_copilot_comments.sh` may still emit a legacy `COPILOT_CLEAN_SIGNAL` line (body-text match, or check-run synthesis); the orchestrator does **not** consume it for the verdict. Always count active findings explicitly.

**The body template drifts, and body matching fails SILENTLY when it does (mind-vault PR #240, 2026-08-25).** Copilot's review body moved to an emoji-bucket header — `### 🟢 Approval recommended` / `### 🟡 Changes recommended` / `### 🔵 Needs a closer look` — with the count moved into a collapsed `<details>` block as `Comments generated: 0 new`. Neither legacy phrase (`found no new issues`, `generated no new comments`) appears in **any** of them, so body-level clean detection went fully blind and nothing complained: the check-run synthesis quietly took over and kept answering. The matcher now carries all three phrasings, and the drift class is covered by `tests/test_copilot_clean_detection.sh` against captured payloads — the point of the fixtures is that a format change now fails a test instead of silently changing which code path answers.

**Check-run synthesis is gated on there being no review body at all.** The fallback exists for the case where copilot posts a check-run and never posts a review. If a body for the head SHA exists, that body **is** the verdict: a clean one sets the signal itself, so reaching the fallback with a body present means the body was *not* clean and synthesizing over it is a false CLEAN. Before this gate, a green check-run papered over a review carrying two real suppressed findings (same PR). `CONCLUSION=success` still means "Copilot ran".

**Anti-pattern observed during IDEA-005 dogfood (PR #131 cycle 2)**: the agent parroted the script's `COPILOT_CLEAN_SIGNAL` line as a verdict without checking active-findings count. That's exactly why clean is now structural — the finding count is the verdict.

## § Staleness rule

Uses the orchestrator's default `pull_request_review_id` filter — a finding is active iff its `review <rid>` matches `COPILOT_LATEST_REVIEW`.

Copilot's GitHub UI behavior matches bugbot's: persistent threads linger until manually resolved. The default filter handles this correctly.

## § Race-condition caveats

Copilot review latency: ~30 seconds between trigger and the *check-run*, but the inline **review** can post minutes later (3m42s observed, PR #148). The check-run-completes-before-review gap is the dangerous window — see § Review-state gate "Review-pending race guard" for how the adapter holds the loop in RUNNING until the review actually lands.

**Heuristic when strict `COMMIT === last_push_sha` fails**: same as bugbot — if intervening commits since signal's `COMMIT` are docs-only, accept the clean signal. Empirically calibrate whether Copilot reviews prose-only diffs (initial assumption: no).

## § Failure modes

| Symptom | Detection | Orchestrator action |
|---|---|---|
| Copilot service error | Review `state: COMMENTED` with body literally `"Copilot encountered an error and was unable to review this pull request. You can try again by re-requesting a review."` and zero inline comments | First occurrence: count toward consecutive-error tally. |
| Copilot service-errored 2× consecutive | Two consecutive HEAD SHAs produce service-error reviews | Stop retriggering Copilot this cycle (additional remove+add compounds the failure). Proceed with other engines' findings if any. |
| Copilot service-errored 3× consecutive | Third consecutive error | Durable service issue. Hand back to user with the offending review ids + SHAs so they can retry from UI, wait for recovery, or merge without Copilot's verdict. |
| Copilot stalled (no review at all) | Review never posts within ~10× normal latency (~5 min) on `last_push_sha` | Proceed with other engines; surface in hand-back if Copilot doesn't recover within the idle-poll budget. |
| **Silent request consumption** (2026-06-11) | The reviewer request **disappears** — `gh api .../requested_reviewers` returns empty — with NO review posted, NO check-run created, NO error body. Distinct from "stalled": the request was visibly accepted-and-dropped, not pending. | Each occurrence counts toward the consecutive-error tally (same ladder as service errors). 2× consecutive on different SHAs → mark the engine **ERRORED**, exclude it from the multi-engine sync wait (don't let a never-arriving verdict gate the slowest-engine rule), note the asymmetric clearance in hand-back. Likely cause: Copilot code review not (or no longer) enabled for the repo/org plan — surface "check org Copilot settings" to the user. Detection requires polling `requested_reviewers`, not just reviews: an empty request list + zero reviews is the signature. |
| **Suppressed comment holds a valid finding** (2026-08-14) | Not detectable from the loop: the comment exists only in the PR **web UI**, collapsed under Copilot's low-confidence suppression, and appears on NONE of the surfaces the adapter reads (`/pulls/<N>/reviews` bodies, `/pulls/<N>/comments`). The engine's visible verdict for the same cycle can simultaneously read "generated no new comments". | See § Suppressed comments below — CLEAN is clean-over-the-visible-set; the standing hand-back caveat and the user-relay path are the mitigations. |

## § Suppressed comments — a valid finding the API never shows

The incident (mind-vault PR #233, 2026-08-14): the loop converged CLEAN over four cycles — copilot's final verdict "generated no new comments" — while a **suppressed** copilot comment held a valid contradiction finding (the prose said "lowercase kebab" for a token whose wired regex allowed `[a-z0-9._-]`). The maintainer found it by expanding the suppressed set in the PR web UI; it entered the loop as a user-relayed finding and shipped as a fifth cycle.

The mechanism: Copilot's confidence filter suppresses some generated comments. Suppressed comments render in the PR UI collapsed, behind a suppressed-comments indicator, and post **no inline comment** — so the adapter's inline-findings pre-check cannot see them, and neither can a finding count taken over `/pulls/<N>/comments`.

> **PARTLY REVERSED, 2026-08-25 (mind-vault PR #240).** This section used to say suppressed comments were absent from *every* API surface the adapter reads, and that the adapter therefore *could not* be extended to fetch them. That is no longer true. The emoji-bucket body template renders them **inside the review body** on `/pulls/<N>/reviews`, under a `<details>` block as `### Suppressed comments (N)` with each finding's file, line and text. The adapter now reads that: a body carrying a suppressed-comments section is never clean, whatever its header or its `Comments generated: 0 new` count says.
>
> **What is still true, and still the reason for the human glance:** presence is detected, but *completeness* is not guaranteed — the count in the body is the count copilot chose to render, and nothing certifies it against what the filter actually held back. A copilot CLEAN still certifies only the set the API surfaced. The hand-back caveat below stays.
>
> **REVERSED AGAIN, 2026-08-28 — detection was not delivery.** Reading the block only made the adapter *withhold* `COPILOT_CLEAN_SIGNAL` and stamp `CLEAN=false` on the `COPILOT_LATEST_REVIEW` line. Neither reaches the verdict: the orchestrator derives clean **structurally** (check-run `DONE` + zero active findings) and is explicitly instructed to **ignore** that trailing legacy `CLEAN=` token. Suppressed items post no inline comment, so the structural count was 0 and copilot read **CLEAN with real findings on the table** — the adapter knew and the loop could not hear it. Observed on mind-vault PR #243, whose suppressed block held three valid findings (one of them a factually wrong claim, one an invalid CI expression that would never have matched) while the visible inline set was empty; they were caught only because the operator opened the review body by hand. The adapter now emits `COPILOT_SUPPRESSED=<n> REVIEW=<id> COMMIT=<sha> AT=<ts>` plus the items verbatim, and the core skill counts them as active findings ([`../SKILL.md`](../SKILL.md) § Per-engine fetch). **The general lesson: a detection that terminates in a flag nobody reads is not a mitigation.** When an adapter learns something the verdict machinery is told to ignore, the fix is to route it into the count, not to add a second flag beside the first.

One more instance of "a green result certifies only the universe it could reach" — and of a claim that stopped being true without anything failing, which is why it is corrected here in place rather than deleted (see [`RULE_self-sweep-before-push`](../../../rules/RULE_self-sweep-before-push.md) § 5b. Reversal sweep).

What the loop does about it:

- **Suppressed findings are surfaced and counted** (2026-08-28): `COPILOT_SUPPRESSED=<n>` + the items verbatim; `n>0` for the head-SHA review means copilot is not clean, and each item enters triage like an inline finding (verify against the tree first — suppression correlates with low confidence, so the false-positive rate is higher). Covered by `tests/test_copilot_clean_detection.sh` § (b), whose asserts were proven red against the pre-fix adapter.
- **Standing hand-back caveat** (still stands — presence is detected, completeness is not): when the loop hands back a converged PR whose engine set includes copilot, the hand-back carries one line — *"copilot CLEAN covers API-visible comments only; expand any suppressed comments in the PR UI before merging."* One human glance closes the gap the adapter cannot.
- **User-relayed suppressed findings are first-class loop input**: they enter the current cycle's fix batch exactly like an engine finding (verify against the tree first — suppression correlates with low confidence, so the false-positive rate is higher than for posted comments; the incident's finding was valid).
- **Never weaken the verdict machinery over this**: the CLEAN classification stays structural (active-findings count over the visible set). The blind spot is documented and human-checked, not papered over with a always-HUNG or always-dirty verdict that would break convergence.

## § Stale-context findings — when to bail

**Pattern**: Copilot's review prompt window includes prior review summaries / context, not just the current file state. When a fix lands that resolves a finding category at the root, Copilot may still flag the same category on an *adjacent surface* in the next cycle — arguing about the original broken-state geometry rather than the post-fix geometry. The agent's first instinct is "fix the new angle too", which triggers another cycle, and the pattern repeats.

**Detection**: the orchestrator's no-progress map (per-engine, per-category) tracks this. If `copilot.<category>` hits ≥3 attempts and copilot's next review still flags the category — even on a different file/line — the loop is in a stale-context loop, NOT making real progress.

**Hand-back rule**: when the per-engine no-progress counter for a category hits 3, **stop attempting that category**. Route the next same-category finding to Tier 3 with note `copilot reasoning from stale review-context, not current file state`. Surface in hand-back as: *"Open finding `<comment-id>` is a false positive — references state already resolved in commit `<sha>`. Resolve conversation on the PR."*

**Why this rule is per-engine**: bugbot's review prompt appears to focus on current diff state more strictly (empirically less prone to this) — the rule doesn't fire as often for bugbot. Copilot's prompt includes more historical context, hence the higher no-progress trip rate.

**Field-observed example** (PR #133, 2026-05-21):
1. Cycle 4 (rules-rationale category attempt 1): forward link `rule → rationale` broken under host-symlink layout. Fix: add `docs/rules` symlink to claude-code/cursor/opencode setup scripts.
2. Cycle 8 (attempt 2): same category re-flagged on VS Code Copilot host (different symlink layout). Fix: also symlink `docs/rules` under VS Code user dir.
3. Cycle 9 (attempt 3): same category re-flagged on the REVERSE link (rationale → rule backlinks broken in VS Code's flat instructions/ layout). Root-cut fix: drop the backlink line from all 4 rationale files.
4. Cycle 10 (attempt 4): copilot STILL flagged the category on `scripts/setup-vscode-copilot-symlinks.sh`, arguing rationale backlinks "still break VS Code Copilot" — but the backlinks had been removed in cycle 9. Pure stale-context false positive. **No-progress detector tripped; loop handed back with the finding as Tier 3.**

**The compound rule**: counter ≥3 → next same-category finding is Tier 3 regardless of whether the finding text *looks* legitimate. The pattern is the signal, not the individual finding's apparent validity. Save the cycle.

## § Common patterns (codified Tier 1)

The codified Tier-1 catalog is shared across engines — see [`common-review-findings.md`](common-review-findings.md). No copilot-specific deltas at present; copilot's behavioral quirks live in § Stale-context findings and § Clean detection above.

## § Review-state gate

Copilot posts a `copilot-pull-request-reviewer` check-run on the PR head. `find_copilot_comments.sh` surfaces it as `COPILOT_CHECKRUN ... STATUS=<status>`: `queued`/`in_progress` = **RUNNING**, `completed` = **DONE**. Corroborating signal: Copilot adds itself to `requested_reviewers` when assigned and self-removes when done (present = pending, absent = done).

`CONCLUSION` is **not** a verdict — Copilot's check-run concludes `success` even when it posted inline findings. **Clean for copilot**: check-run DONE AND zero active findings matching `COPILOT_LATEST_REVIEW`. The orchestrator retriggers only after a push or from the zero-activity bootstrap and never while a check-run is RUNNING, so there is no retrigger interval to enforce.

**Review-pending race guard (check-run completes BEFORE the review posts).** Copilot's check-run flips to `completed`+`success` *before* its inline review lands — observed lag **3m42s** on mind-vault PR #148 (2026-05-27: check-run `completed` 13:32:56Z, review with 2 findings posted 13:36:38Z). A poll in that gap sees DONE + zero findings and the loop concludes a **false CLEAN**, shipping the about-to-post findings unreviewed. So `find_copilot_comments.sh` trusts a `completed` check-run as DONE **only once Copilot has posted a review for the head SHA**; until then it downgrades the emitted `STATUS` to `in_progress` (the orchestrator reads it as RUNNING and keeps waiting) and emits an informational `COPILOT_REVIEW_PENDING=...` marker. The downgrade is **conclusion-agnostic** (any `completed` check-run, not just `success`) for parity with the engine-general contract + the Bugbot adapter — Copilot always concludes `success` so the gate is moot here today, but uniformity future-proofs it. A settle valve (`COPILOT_REVIEW_SETTLE_SECONDS`, default 600) trusts a review-less check-run as DONE after it elapses **only when its conclusion is `success`** (the rare check-run-only-no-review case); a non-success review-less run is held → idle-timeout HUNG, never reported clean. `CONCLUSION=success` gates only `CLEAN_SIGNAL` synthesis + the settle-valve release, never the downgrade. The orchestrator needs no special handling — the `STATUS` downgrade is what keeps the loop honest.

## § Notes on first-run calibration

The 2026-05-18 calibration run + 2026-05-20 IDEA-005 dogfood (PR #131) established the following confirmed state:
- ✅ Dual user.login identity (Copilot + copilot-pull-request-reviewer[bot]).
- ✅ Plain `--add-reviewer @copilot` retrigger after Copilot has self-removed post-review. Remove+add fallback exists for the still-pending state.
- ✅ Service-error failure mode pattern.
- ✅ Review-state gate: `copilot-pull-request-reviewer` check-run `STATUS` (RUNNING/DONE) + `requested_reviewers` self-removal. Clean is structural — DONE + zero active findings — never `CONCLUSION` (`success` ≠ "no findings") or review-body prose.

If the loop misbehaves on first use against a new Copilot deployment, inspect `gh api repos/.../pulls/<N>/reviews --jq '.[].user.login'` to confirm the bot login, and adjust constants in the tool scripts accordingly.
