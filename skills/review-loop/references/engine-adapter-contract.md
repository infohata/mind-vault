# Engine adapter contract

Every review engine that plugs into `skills/review-loop/SKILL.md` must satisfy this contract. Adapters live under `skills/review-loop/references/engine-<name>.md` and consist of two surfaces:

1. **Tool surface** — shell scripts under `tools/<engine>_*.sh` that the orchestrator invokes.
2. **Reference surface** — the `engine-<name>.md` file itself, documenting parsing rules, failure modes, and Common-Patterns codification.

The orchestrator (`SKILL.md`) only calls into the tool surface. The reference surface is consumed by the agent (Claude) reading the adapter doc when triaging findings or interpreting unusual signals.

## Adapter categories

Adapters fall into two trigger/state shapes. The orchestrator's phase logic is identical for both — the difference is entirely inside the `find_*` / `*_retrigger` scripts and documented in the engine's reference surface.

| Category | Trigger model | Review-state source | Clean source | Staleness anchor | Instances |
|---|---|---|---|---|---|
| **Check-run / request-driven** | Idle until explicitly retriggered (`*_retrigger.sh` fires post-push + on the zero-activity bootstrap) | A **named check-run** on the head SHA; `STATUS` → RUNNING/DONE | DONE + zero active findings; `CONCLUSION=success` is a meaningful "ran" signal that gates the settle valve | `pull_request_review_id` | `bugbot`, `copilot` |
| **Auto-trigger / comment-anchored** | **Push-triggered** — a CI/Actions hook auto-runs on every push, so a fix push IS the retrigger; the `*_retrigger.sh` is a **fallback** for the no-auto-run bootstrap only | A **CI/Actions job** status (NO named check-run); `STATUS` synthesized → RUNNING/DONE; its conclusion is green regardless of findings, never a verdict | A **summary-comment body** substring OR zero head-SHA inline comments; the settle valve releases on comment **presence**, never the job conclusion | A **synthesized comment id** (summary-comment id, or newest head-SHA inline comment id) | `claude` (first instance — [`engine-claude.md`](engine-claude.md)) |

The auto-trigger / comment-anchored category exists because `anthropics/claude-code-action@v1` running the `code-review` plugin violates all three check-run-category assumptions (no named check-run, findings are comments not a stateful review, auto-runs on push). The contract accommodates it without orchestrator changes — see the comment-presence settle note in § Review-state gate and the synthesized-anchor case in § Scratch-file state ownership.

## Tool surface — required scripts

Every adapter MUST provide these scripts (project-local, `tools/<engine>_*.sh`). The orchestrator invokes them by name; the contract is the script's stdout shape.

> **⚠️ CWD / repo-resolution gotcha — invoke from the TARGET PROJECT's checkout.** These scripts shell out to `gh`, which resolves the repo from the **CWD's git remote** unless given `-R owner/repo`. When the scripts live in a *shared* tools dir (mind-vault symlinked / cloned separately from the project under review), running them with the shared dir as CWD makes `gh` query the *wrong* repo — the PR won't resolve, `find_*` reports a false **"no activity yet"**, `*_retrigger` fails with `Could not resolve to a PullRequest`. The false "no activity" is the dangerous one — the orchestrator may wrongly take the zero-activity branch or miss findings. **Invoke by absolute path with CWD = the project under review** (`cd <project> && /path/to/shared/tools/find_<engine>_comments.sh <PR>`), or hardcode `gh -R` in the script. When in doubt, cross-check with `gh api repos/<owner>/<repo>/pulls/<PR>/reviews` — authoritative and CWD-independent.

### `tools/find_<engine>_comments.sh <PR_NUMBER>`

Emit zero or more marker lines on stdout. **Order is not guaranteed** — the orchestrator parses by anchor-based grep on `^<ENGINE>_<MARKER>=` rather than positional reading. Adapters MAY emit markers in any order, MAY interleave informational output (banners, summaries) between markers, and SHOULD prefer printing markers as early as possible after their underlying data is fetched. The marker set (each emitted when its underlying data exists — see per-line notes and the semantics below):

```text
<ENGINE>_LATEST_REVIEW=<review-id> COMMIT=<sha> AT=<iso8601> [CLEAN=<bool>]   # trailing CLEAN= is legacy/ignored; parsers must tolerate extra trailing fields
[<ENGINE>_CHECKRUN=<id> COMMIT=<sha> STATUS=<queued|in_progress|completed> CONCLUSION=<...> AT=<iso8601>]   # state gate — emitted when a check-run exists on the head SHA; ABSENCE = NOT_TRIGGERED or TRIGGERED (check-run not yet created). STATUS: RUNNING (queued/in_progress) vs DONE (completed)
[<ENGINE>_CLEAN_SIGNAL=<review-id> COMMIT=<sha> AT=<iso8601>]   # legacy, non-authoritative — orchestrator derives clean structurally (DONE + zero active findings), NOT from this line
```

Followed by zero or more inline-finding blocks. The exact display format is implementation-defined — current `tools/find_*_comments.sh` scripts emit ANSI-coloured + markdown-bold output (`**File:**`, separator lines, etc.) for human readability. The orchestrator consumes findings by anchor-based grep on the `(comment id <cid>, review <rid>)` token, so adapters MAY choose any human-readable layout as long as **every finding block includes this token verbatim**. Recommended fields per block (any layout):

- `Severity: <LOW|MEDIUM|HIGH|CRITICAL|INFO>`
- `(comment id <cid>, review <rid>)` — **mandatory** identifier-pair
- `File: <path>` (line number optional — see line-number-drift caveat in the orchestrator)
- `Title: <short title>` (free-text; may be a placeholder for engines without titles)
- `Description: <body>` (free-text)
- `Link: <github URL>` (optional, for forensics)

Followed by an empty line, then optionally:

```text
💡 PR: <github URL>
```

**Required semantics:**

- `<ENGINE>` literal is uppercase engine name (e.g. `BUGBOT`, `COPILOT`, `CLAUDE`).
- `<ENGINE>_LATEST_REVIEW` is **mandatory** when any review exists for the PR — the orchestrator's staleness rule depends on it. It may carry a trailing legacy `CLEAN=<bool>` token; the orchestrator ignores it (clean is structural), and parsers must tolerate extra trailing fields.
- `<ENGINE>_CHECKRUN` is the **review-state gate**, emitted whenever the engine has a check-run on the head SHA. Its **absence means the engine has no check-run for this SHA yet** — either `NOT_TRIGGERED` (no retrigger fired) or `TRIGGERED` (retrigger fired, check-run not yet created); Phase 4 distinguishes them by whether a trigger fired this SHA, so absence alone must not prompt a re-trigger. When present, `STATUS` maps to `RUNNING` (`queued`/`in_progress`) vs `DONE` (`completed`); `CONCLUSION` is a run outcome, never a clean verdict. A `completed` check-run must not be surfaced as DONE until a review for the head SHA has posted — with one exception, the **success-only settle valve** (a `success` review-less check-run is trusted after the window; a non-success one never is). See § Review-state gate's review-pending guard for the full rule.
- `<ENGINE>_CLEAN_SIGNAL` is **legacy and non-authoritative**: the orchestrator derives clean structurally (engine `DONE` + zero active findings matching `LATEST_REVIEW`), never from this line. A script MAY still emit it; the orchestrator ignores it for the verdict.
- Each inline finding must include the `review <rid>` token so the orchestrator can filter active findings (`rid == LATEST_REVIEW`) vs persistent-thread stale findings (`rid != LATEST_REVIEW`).
- The `COMMIT=<sha>` on `LATEST_REVIEW` is the trigger-anchor SHA; the authoritative review state is the `CHECKRUN STATUS` for the current head SHA.
- Exit code 0 on success (regardless of whether findings exist); non-zero only on auth/network failure.

### `tools/<engine>_retrigger.sh <PR_NUMBER>`

Trigger a new review for the PR. Engine-specific mechanism (comment post for bugbot, reviewer remove+add for copilot, etc.).

**Required semantics:**

- Exit code 0 on success.
- Hard-coded body / action so the script can be pre-approved in `~/.claude/settings.json` without permission prompts on each call.
- Idempotent against pre-existing pending reviews — calling twice should not break the engine's queue (the orchestrator only retriggers post-push or from the zero-activity bootstrap, never while RUNNING, but the script must not crash if the engine is already mid-review).
- **Recommended (not required)**: print a tracking reference to stdout — the GitHub URL of the action taken (comment URL for comment-based engines like bugbot) or a status line. Useful for log forensics but not consumed by the orchestrator.

## Reference surface — required sections

Every `engine-<name>.md` MUST include the following sections, in this order:

### § Identity

Engine name, vendor, what the user sees in the GitHub UI (e.g. "cursor[bot]" for bugbot, "Copilot" for copilot). The orchestrator filters PR comments/reviews by `user.login` matching this identity.

### § Tool invocations

The literal shell commands the orchestrator dispatches:

- `tools/find_<engine>_comments.sh <PR>` — output shape per contract above.
- `tools/<engine>_retrigger.sh <PR>` — semantics per contract above.

Any engine-specific quirks (e.g. Copilot's bare `--add-reviewer` no-op against already-requested reviewers) documented inline.

### § Review-state + clean detection

Document the engine's check-run (name / app-slug) and how `STATUS` maps to `RUNNING`/`DONE`. Clean is structural: `DONE` + zero active findings matching `LATEST_REVIEW`. If the script also emits a legacy `CLEAN_SIGNAL` (e.g. a review-body marker), note it as corroboration only — the orchestrator does not consume it for the verdict.

### § Staleness rule

Engine-specific staleness semantics if any. The default contract (active iff `review.id == LATEST_REVIEW`) is uniform across engines, but engines with persistent-thread quirks (bugbot: stale findings linger in `/comments` until manual resolve) document them here.

### § Race-condition caveats

Any engine-specific race conditions between review-firing and SHA observation. Document the timestamp tiebreaker and docs-only-commit skip-retrigger heuristic.

### § Failure modes

Engine-specific failure signatures the orchestrator must recognise:

- Stall / hang patterns (bugbot: `BUGBOT_CHECKRUN STATUS=in_progress` >15 min; copilot: review never posts within ~10× normal latency).
- Service-error patterns (copilot's literal `"Copilot encountered an error..."` body).
- Rate-limit patterns.

Each failure mode mapped to an orchestrator action (proceed with other engines, hand back, etc.).

### § Common patterns (codified Tier 1 findings)

Engine-specific recurring findings the orchestrator can auto-fix without per-finding approval. The shared cross-engine catalogue lives in [`common-review-findings.md`](common-review-findings.md); an adapter's § Common patterns section links there and documents only its engine-specific deltas.

### § Review-state gate

The adapter MUST expose its engine's check-run on the PR head as `<ENGINE>_CHECKRUN ... STATUS=<status>`, mapping the engine's native status to `queued`/`in_progress` (**RUNNING**) and `completed` (**DONE**). The orchestrator gates on this: it never reads a verdict while RUNNING and never retriggers except after a push or from the zero-activity bootstrap — so no inter-retrigger interval exists. `CONCLUSION` is a run outcome, never a clean verdict.

**Review-pending guard — a `completed` check-run is NOT a verdict until a review for the head SHA has posted.** Engines flip their check-run to `completed` *before* the review / inline-comment objects land (observed: copilot, 3m42s lag, PR #148). A poll in that gap sees DONE + zero findings, and the orchestrator's structural clean (DONE + zero active findings) fires a **false CLEAN**, shipping the about-to-post findings unreviewed — `CONCLUSION` doesn't help, whatever its value: it reports the *run's* outcome, not whether the inline review / comment objects have landed (and it varies by engine — Copilot concludes `success` even with findings, Bugbot concludes non-success on findings). So an adapter MUST NOT report DONE off **any** `completed` check-run — *regardless of `CONCLUSION`* — until a review for the head SHA has posted (a `LATEST_REVIEW` whose `COMMIT` == head SHA). The downgrade is conclusion-agnostic on purpose: an engine that concludes **non-success on findings** (e.g. Bugbot) would otherwise slip a findings check-run that completes before its comments post straight through to DONE + zero-findings = false CLEAN. `CONCLUSION=success` gates **only** the `CLEAN_SIGNAL` synthesis (non-success ⇒ findings ⇒ never synthesize clean), never the DONE-suppression. Until that review posts, downgrade the emitted `STATUS` to `in_progress` (the orchestrator keeps waiting) and MAY emit an informational `<ENGINE>_REVIEW_PENDING=...` marker. A settle valve (`<ENGINE>_REVIEW_SETTLE_SECONDS`, default 600) trusts a review-less check-run as DONE after the window elapses **only when its conclusion is `success`** (the rare clean-check-run-only case, so it doesn't poll to the idle timeout). A **non-success** review-less check-run is **never** trusted — it signaled findings, but the review/comments never arrived, so trusting it would report findings as clean; keep it non-DONE (held → idle-timeout HUNG → human investigates the missing review). Both shipped adapters implement this (`find_copilot_comments.sh`, `find_bugbot_comments.sh`); any new engine whose `find_*` synthesizes clean from a check-run MUST too. Compute the settle age in Python `datetime` (cross-platform), never `date -d` (GNU-only; fails on BSD/macOS and pins the guard permanently on).

**Comment-anchored engines gate DONE on comment PRESENCE, not conclusion.** An auto-trigger / comment-anchored engine (see § Adapter categories) has no native check-run *and* no conclusion that ever signals findings — its synthesized RUNNING/DONE comes from a CI/Actions job whose conclusion is green regardless of what it found. For such an engine the settle valve **must** release on comment presence (or, on a genuine empty-result no-comment case, the zero-inline clean arm) and **never** on the job conclusion — a conclusion gate would always release and ship lagged findings as a false CLEAN. The success-only settle valve above applies to **check-run** engines (copilot, bugbot) where a `success` conclusion is a meaningful "ran clean" signal; it does NOT transfer to comment-anchored engines. `claude` is the first instance — see [`engine-claude.md`](engine-claude.md) § Race-condition caveats for the load-bearing divergence.

## Scratch-file state ownership

The orchestrator owns the per-engine state slots in the loop's scratch file under `~/.claude/memory/projects/<project-slug>/review-loop-pr-<N>.md` (placeholder `<project-slug>` standardised across all review-loop docs). Adapters do NOT write directly to scratch; the orchestrator updates state based on adapter outputs.

Per-engine state slots:

- `<engine>_review_state` — `NOT_TRIGGERED` | `TRIGGERED` | `RUNNING` | `DONE` for the current head SHA (from the engine's check-run `STATUS`)
- `last_seen_<engine>_review` — `<id> @ <sha>` (LATEST_REVIEW last acted on; staleness anchor)
- `last_seen_<engine>_signal_id` — most recent processed inline finding id (engine-defined: comment id for comment-based engines; unset until first review for reviewer-assignment engines; for **comment-anchored** engines whose `LATEST_REVIEW` anchor is a *synthesized summary-comment id* — see § Adapter categories — it's that summary-comment id, falling back to the newest head-SHA inline comment id when no summary exists)

## Adding a new engine

To add a new engine (e.g. CodeRabbit, a hypothetical new vendor):

1. Decide the adapter **category** (§ Adapter categories) — check-run/request-driven or auto-trigger/comment-anchored. The category dictates where review-state and clean come from and whether the retrigger is primary or fallback.
2. Author `skills/review-loop/references/engine-<name>.md` following the section template above.
3. Implement `tools/find_<engine>_comments.sh` and `tools/<engine>_retrigger.sh` per the tool-surface contract.
4. Add `<name>` to the recognised engine list in `commands/review-loop.md` § Engine selection and the `ENGINES` enum in `review-loop/SKILL.md` (the user-visible surfaces).
5. **If the engine should join the *default* engine set**, gate it on a **reachability probe** in `find_<engine>_comments.sh` (e.g. claude probes for its `claude-code-review.yml` workflow). Where the engine is not provisioned on the target repo, emit a `<ENGINE>_NOT_INSTALLED=true` marker + exit 0 so the orchestrator's default resolution self-excludes it (degrade loudly on an explicit invocation, never HUNG). An engine with no per-repo provisioning step (bugbot, copilot) needs no probe.
6. Wire the **sync-doc touchpoints** in [`multi-engine-sync.md`](multi-engine-sync.md): add the engine's stall/error rows to the trade-off escape-hatch table, its `<engine>_review_state` / `last_seen_<engine>_*` scratch slots, its slot in the alphabetical retrigger order (noting any push-triggered/fallback-only retrigger so Phase 3 skips it), and extend the asymmetric-clearance hand-back template to cover the new engine count.
7. Optionally add `commands/<name>-loop.md` as a thin single-engine wrapper.

`SKILL.md` itself processes engines from the `ENGINES` argument generically and does not enumerate them by name in code — adding a new engine does not require structural changes to the orchestrator's phase logic. The "no changes required" applies to the orchestrator's algorithmic surface; the user-facing engine list lives in `commands/review-loop.md` so it can document what the user can pass.

## Anti-patterns

- ❌ Adapter writes directly to the orchestrator's scratch file. The orchestrator owns scratch; adapters expose stdout shape only.
- ❌ Engine-specific decision-tree branches in the orchestrator. If an engine needs special-case handling, lift it into the adapter contract (e.g. service-error retry-budget) or hand back to the user.
- ❌ Cross-engine knowledge in an adapter (e.g. bugbot's adapter referencing copilot's check-run name). Each adapter is self-contained; cross-engine coordination lives in `multi-engine-sync.md` and the orchestrator.
- ❌ Skipping the `review <rid>` token in `find_comments.sh` output. The orchestrator's staleness filter depends on it.
