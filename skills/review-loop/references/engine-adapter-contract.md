# Engine adapter contract

Every review engine that plugs into `skills/review-loop/SKILL.md` must satisfy this contract. Adapters live under `skills/review-loop/references/engine-<name>.md` and consist of two surfaces:

1. **Tool surface** — shell scripts under `tools/<engine>_*.sh` that the orchestrator invokes.
2. **Reference surface** — the `engine-<name>.md` file itself, documenting parsing rules, failure modes, and Common-Patterns codification.

The orchestrator (`SKILL.md`) only calls into the tool surface. The reference surface is consumed by the agent (Claude) reading the adapter doc when triaging findings or interpreting unusual signals.

## Tool surface — required scripts

Every adapter MUST provide these scripts (project-local, `tools/<engine>_*.sh`). The orchestrator invokes them by name; the contract is the script's stdout shape.

### `tools/find_<engine>_comments.sh <PR_NUMBER>`

Emit zero or more marker lines on stdout. **Order is not guaranteed** — the orchestrator parses by anchor-based grep on `^<ENGINE>_<MARKER>=` rather than positional reading. Adapters MAY emit markers in any order, MAY interleave informational output (banners, summaries) between markers, and SHOULD prefer printing markers as early as possible after their underlying data is fetched. The required marker set:

```text
<ENGINE>_LATEST_REVIEW=<review-id> COMMIT=<sha> AT=<iso8601> CLEAN=<true|false>
[<ENGINE>_CLEAN_SIGNAL=<review-id> COMMIT=<sha> AT=<iso8601>]   # optional, present iff most-recent review is classified clean (body-text match OR check-run synthesis)
[<ENGINE>_CHECKRUN=<id> COMMIT=<sha> STATUS=<...> CONCLUSION=<...> AT=<iso8601>]   # optional, informational, present when a check-run for this engine exists on the PR head
```

Followed by zero or more inline-finding blocks, each in this shape:

```text
[N/M] Severity: <LOW|MEDIUM|HIGH|CRITICAL> (comment id <cid>, review <rid>)
File: <path>:<line>
Title: <short title>
Description:
<body, possibly multi-line>

Locations:
  - <path>#L<a>-L<b>
  - <additional location>

Link: <github URL>
```

Followed by an empty line, then optionally:

```text
💡 PR: <github URL>
```

**Required semantics:**

- `<ENGINE>` literal is uppercase engine name (`BUGBOT`, `COPILOT`).
- `<ENGINE>_LATEST_REVIEW` is **mandatory** when any review exists for the PR — the orchestrator's staleness rule depends on it.
- `<ENGINE>_CLEAN_SIGNAL` is emitted when the most-recent review is classified clean. Detection is engine-defined and may be best-effort (body-text match against fixed phrases like "found no new issues", and/or synthesis from a successful check-run). False positives are acceptable — the orchestrator's Phase 4 ordering (new-findings branch precedes clean-signal branch) supersedes a synthesized CLEAN when active findings exist.
- `<ENGINE>_CHECKRUN` is optional/informational. Adapters that don't have a check-run concept omit it.
- Each inline finding must include the `review <rid>` token so the orchestrator can filter active findings (`rid == LATEST_REVIEW`) vs persistent-thread stale findings (`rid != LATEST_REVIEW`).
- The `COMMIT=<sha>` on `LATEST_REVIEW` / `CLEAN_SIGNAL` is the trigger-anchor SHA, NOT the reviewed SHA (race-condition caveat documented in the orchestrator).
- Exit code 0 on success (regardless of whether findings exist); non-zero only on auth/network failure.

### `tools/<engine>_retrigger.sh <PR_NUMBER>`

Trigger a new review for the PR. Engine-specific mechanism (comment post for bugbot, reviewer remove+add for copilot, etc.).

**Required semantics:**

- Exit code 0 on success.
- Hard-coded body / action so the script can be pre-approved in `~/.claude/settings.json` without permission prompts on each call.
- Idempotent against pre-existing pending reviews — calling twice should not break the engine's queue (the orchestrator's spacing rule prevents abuse, but the script must not crash if the engine is already mid-review).
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

### § Clean-signal parsing

How the engine signals "found no new issues". For most engines this is a review-body marker (`<!-- CLEAN -->` or natural-language equivalent). Document the exact string match the `find_comments.sh` script uses.

### § Staleness rule

Engine-specific staleness semantics if any. The default contract (active iff `review.id == LATEST_REVIEW`) is uniform across engines, but engines with persistent-thread quirks (bugbot: stale findings linger in `/comments` until manual resolve) document them here.

### § Race-condition caveats

Any engine-specific race conditions between review-firing and SHA observation. Document the timestamp tiebreaker and docs-only-commit skip-retrigger heuristic.

### § Failure modes

Engine-specific failure signatures the orchestrator must recognise:

- Stall / hang patterns (bugbot: `BUGBOT_CHECKRUN status=in_progress` >15 min; copilot: review never posts within ~10× normal latency).
- Service-error patterns (copilot's literal `"Copilot encountered an error..."` body).
- Rate-limit patterns.

Each failure mode mapped to an orchestrator action (proceed with other engines, hand back, etc.).

### § Common patterns (codified Tier 1 findings)

Numbered list of engine-specific recurring findings the orchestrator can auto-fix without per-finding approval. Borrows from `AGENT_<engine>.md`'s Common Patterns block where one exists.

### § Spacing rule

The minimum interval between same-engine retriggers. Default 5 min; engines with different rate-limit profiles override here.

## Scratch-file state ownership

The orchestrator owns the per-engine state slots in the loop's scratch file under `~/.claude/memory/projects/<project>/review-loop-pr-<N>.md`. Adapters do NOT write directly to scratch; the orchestrator updates state based on adapter outputs.

Per-engine state slots:

- `last_seen_<engine>_review` — `<id> @ <sha> CLEAN=<bool>`
- `last_seen_<engine>_signal_id` — most recent processed inline finding id (engine-defined: comment id for comment-based engines, unset until first review for reviewer-assignment engines)
- `last_<engine>_retrigger_at` — ISO-8601 timestamp of most recent retrigger
- `pending_<engine>_retrigger` — bool, set true when Phase 3 defers due to spacing

The `pending_<engine>_retrigger` field is independent per engine — under dual-engine mode it's possible to have one engine pending and the other fired this cycle.

## Adding a new engine

To add a third engine (e.g. CodeRabbit, a hypothetical new vendor):

1. Author `skills/review-loop/references/engine-<name>.md` following the section template above.
2. Implement `tools/find_<engine>_comments.sh` and `tools/<engine>_retrigger.sh` per the tool-surface contract.
3. Add `<name>` to the recognised engine list in `commands/review-loop.md` § Engine selection (the user-visible enum).
4. Optionally add `commands/<name>-loop.md` as a thin single-engine wrapper.

`SKILL.md` itself processes engines from the `ENGINES` argument generically and does not enumerate them by name in code — adding a new engine does not require structural changes to the orchestrator's phase logic. The "no changes required" applies to the orchestrator's algorithmic surface; the user-facing engine list lives in `commands/review-loop.md` so it can document what the user can pass.

## Anti-patterns

- ❌ Adapter writes directly to the orchestrator's scratch file. The orchestrator owns scratch; adapters expose stdout shape only.
- ❌ Engine-specific decision-tree branches in the orchestrator. If an engine needs special-case handling, lift it into the adapter contract (e.g. service-error retry-budget) or hand back to the user.
- ❌ Cross-engine knowledge in an adapter (e.g. bugbot's adapter referencing copilot's spacing rule). Each adapter is self-contained; cross-engine coordination lives in `dual-engine-sync.md` and the orchestrator.
- ❌ Skipping the `review <rid>` token in `find_comments.sh` output. The orchestrator's staleness filter depends on it.
