# IDEA-006: v4.3 review-surface collapse — completion summary

**Status**: ✅ Complete (2026-05-25) · **Ships as**: v4.3 · **PRs**: [#139](https://github.com/infohata/mind-vault/pull/139) (prepare) + [#140](https://github.com/infohata/mind-vault/pull/140) (drop)

## What shipped

Collapsed the review surface to a single entry point. Deleted four files:

- `agents/AGENT_bugbot.md` + `agents/AGENT_copilot.md` — sub-agent profiles that predated the IDEA-005 shared core.
- `commands/bugbot-loop.md` + `commands/copilot-loop.md` — the thin wrappers deprecated in v4.2 (removal targeted at v4.3).

`/review-loop <PR> <engine>` (engine ∈ `bugbot` | `copilot` | `bugbot,copilot`) is now the sole review entry point.

**Content migration** (PR-1): the two **word-for-word identical** 19-pattern Tier-1 catalogues consolidated into one shared `skills/review-loop/references/common-review-findings.md`, deduplicated in BOTH dimensions — across the two agent copies AND against existing vault homes (#15→SHELL_INSTALLERS, #17/#18→ALPINE_HTMX_GOTCHAS, #19→RULE_self-sweep), so the catalogue is a scannable index, not relocated redundancy.

**sprint-auto rewire** (PR-1): review passes (S3/S6/S11.10/S13/S14) now dispatch a single multi-engine `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE` call (concurrent sync when >1 engine, N-engine-general). The per-pass escalation cap is a single shared budget across engines (was per-engine under sequential loops), kept distinct from `/review-loop`'s internal `max_commits_per_session`.

## Deviations from the plan

- The plan optimistically listed #1/#11 as having django homes; the execution audit found those homes were thin, so #1–#14 + #16 kept full prose in the catalogue (only #15/#17/#18/#19 link out). No scope change.

## Sequencing (rename-before-drop)

Two PRs, prepare-then-drop. PR-1 migrated content + rewired ~25 reference sites (all four files still present → no breakage); PR-2 deleted them + cut the `## v4.3` CHANGELOG header. Both PRs' multi-engine review loops ran clean (PR-1 surfaced 2 budget-semantics consistency findings from Bugbot, both fixed; PR-2 surfaced 1 Copilot Info finding on historical changelog prose, fixed).

## Cross-IDEA amendments (RULE_cross-idea-amendments)

- Deleted the `/bugbot-loop` + `/copilot-loop` wrappers **created by [IDEA-005](../2026-05-idea-005-review-loop-shared-core/IDEA-005-review-loop-shared-core.md)** — backref appended to its archive.
- Deleted `AGENT_bugbot.md` / `AGENT_copilot.md` (authored across multiple compound PRs) + migrated their catalogue; sprint-auto (IDEA-163-era) review dispatch rewired.

## Follow-ups

- None. The "AGENT_*.md trails the shared skill" no-progress category that motivated this IDEA cannot resurface — the files are gone.

After PR #140 merges: `make release` tags **v4.3** (extractor reads the topmost `## v4.3` header — no `VERSION=` override needed).
