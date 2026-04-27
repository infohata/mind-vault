# IDEA — sprint-auto: integration branch for cross-PR conflict detection

**Status**: idea (not yet planned)
**Surfaced**: 2026-04-27 (during teisutis 2026-04-26 sprint-auto batch test loop, PR #375 + #376 staged together)
**Owner**: TBD (user mentioned a parallel Claude Code session would work on this)

## The problem

`sprint-auto` runs N IDEAs in parallel git worktrees, each with its own docker stack. Each worktree's tests run **in isolation against that worktree's branch**. Bugbot reviews each branch **in isolation against `main`**.

What never gets tested: the **integrated state** of all N branches merged together. Two PRs may individually pass tests, individually clear bugbot, and individually look fine on staging — but conflict at merge time when both edit the same regions of the same files.

Worked example from teisutis 2026-04-27:

- PR #375 (IDEA-124, audio playback fallback + dark theme) and PR #376 (IDEA-125, audio transcription pre-send) both modify `web/teisutis_ai/templates/teisutis_ai/chat.html` and 8 of the same `.po` files. Both passed bugbot. Both passed staging tests in isolation.
- When the user wanted to test #376 ON TOP of #375 to verify they work together, the local `git merge auto/audio-playback... into auto/audio-transcription...` produced **12 conflict files** to resolve manually. The conflicts were all "include both contributions" merges (each PR added independent translation keys near each other) — none were destructive, but resolving 12 files for a throwaway local test was overhead.

The merge-conflict surface is invisible during the sprint-auto run itself. It only shows up after the human starts merging (and by then bugbot's clean signal on the per-PR state has nothing to say about the merge result).

## The proposal

`sprint-auto` adopts an **integration branch** stage between per-IDEA work and per-PR opening:

```
main
  ↓
  ├── auto/IDEA-124-audio-playback        ← work + tests + bugbot per branch (existing)
  ├── auto/IDEA-125-audio-transcription   ← work + tests + bugbot per branch (existing)
  ├── auto/IDEA-126-unify-uploaders       ← work + tests + bugbot per branch (existing)
  └── ...
        ↓
  staging/sprint-auto-2026-04-26          ← NEW: merge all auto/* into staging
        ↓
        ├── run full regression suite on integrated state
        ├── bugbot review of integrated state
        └── if conflicts: surface in the auto-run summary
        ↓
  Open per-PR PRs targeting `main` (existing)
        ↓
  Human reviews + merges each PR (existing)
```

The integration branch is **disposable** — created fresh each batch, deleted after the last PR merges (or after a configurable retention window). It's the integration test-bed, not a "develop" branch in the gitflow sense.

## Open design questions for the parallel Claude session

1. **Branch lifecycle.** Created at the start of a sprint-auto batch, deleted when? On last PR merge? On a TTL? Never (kept for forensics)?
2. **Merge strategy.** `git merge --no-ff` for each `auto/*` to preserve per-IDEA history? Or `git merge -X ours/theirs` to fail-fast on conflicts? Or just sequential `merge` and stop on first conflict (manual escalation)?
3. **Conflict surfacing.** Where does the conflict report land in the auto-run summary? Per-IDEA section? A new "Integration check" section? How does the morning reviewer see at a glance "PR #376 will conflict with PR #375"?
4. **When integration fails.** Two paths:
   - (a) Open the per-PR PRs anyway and surface "expects conflicts" in the body — let the human resolve at merge time.
   - (b) Pause and ask the human upfront which PR to deprioritise (more expensive, but more decisive).
5. **Testing on the integrated state.** Run the full test suite on the integration branch? Or just the unioned per-IDEA target tests? (Cheaper: union; more thorough: full suite, but slower.)
6. **Bugbot on integration.** Does bugbot fire on the integration branch, or only on the eventual per-PR PRs? If only on PRs, a "the integration is fine but PR #X has a bug bugbot would find on its own merged tip" gap remains.
7. **Sequential vs. all-at-once merge.** Merge `auto/A → integration`, then `auto/B → integration`, then `auto/C` — surface intermediate conflict points? Or merge all at once and catalogue the union?
8. **Worktree economy.** The integration branch is a 7th worktree on top of the 6-IDEA-batch state. Adds disk + docker-compose-port-offset accounting. Worth it?
9. **Failure mode for bugbot integration findings.** If bugbot flags an integrated-state-only finding (one that wouldn't appear on either source branch in isolation), where does it get fixed? On one of the source branches? On the integration branch itself? On a third "fix" branch?

## What's NOT in scope for this idea

- **Replacing per-PR bugbot.** The integration step is additive. Each `auto/*` PR still needs its own bugbot pass against `main`.
- **Replacing the human merge.** The integration branch never gets merged to `main`. Per-PR merges still go through GitHub's UI with the human at the controls (per `RULE_git-safety`).
- **A long-lived develop/staging branch.** This is per-batch, disposable. Not gitflow.

## Concrete next step for the parallel Claude session

1. Read `skills/sprint-auto/SKILL.md` to ground in the existing state machine.
2. Read this file (`IDEA_integration_branch.md`) for the framing.
3. Walk through the design questions above and pick an answer for each (or escalate).
4. Emit a plan: where in the sprint-auto state machine the integration step lives (between S9 harvest and S12 compound is the obvious slot — after per-IDEA completes, before batch-summary writes).
5. Decide whether this is a sprint-auto change or its own skill (`/integrate` as a separate composable step).

## References

- Surfacing context: teisutis `docs/archive/auto-run-2026-04-26T02-31-00Z-summary.md` — the batch run that prompted this idea.
- Existing sprint-auto state machine: `skills/sprint-auto/SKILL.md` (S0–S15).
- `RULE_git-safety` — confirms feature-branch merges are agent-allowed; integration branch falls under this.

---

**Last Updated**: 2026-04-27 (initial idea capture during teisutis test loop)
