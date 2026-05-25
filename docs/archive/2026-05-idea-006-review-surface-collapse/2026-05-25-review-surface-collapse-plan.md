---
stage: plan
slug: review-surface-collapse
created: 2026-05-25
source: ./IDEA-006-review-surface-collapse.md
status: ready
project: mind-vault
target_version: v4.3
---

# Plan: v4.3 review-surface collapse

## 1. Context

IDEA-005 (complete, PR #131) collapsed `/bugbot-loop` + `/copilot-loop` from full ~260L skills into thin wrappers over one shared `skills/review-loop/SKILL.md` + per-engine adapter references. It left two residual surfaces that still duplicate orchestration knowledge:

1. `agents/AGENT_bugbot.md` (210L) + `agents/AGENT_copilot.md` (220L) — sub-agent profiles that predate the shared core. PR #131's dogfood surfaced a recurring no-progress category: every shared-skill change risked not propagating to these files (cycles 4/5/7/8/10).
2. `commands/bugbot-loop.md` + `commands/copilot-loop.md` — thin wrappers deprecated in v4.2 with removal targeted at v4.3.

This plan deletes all four, shipping as **v4.3** (the wrapper-removal narrative the v4.2 CHANGELOG reserved). `/review-loop <PR> <engine>` becomes the sole review entry point.

## 2. Problem Frame

Three surfaces (shared skill + agent profiles + command wrappers) encode review orchestration. Two are now pure duplication:

- The agent files duplicate orchestration mechanics already in `SKILL.md` + carry a Common-Patterns/Findings catalogue that should live in the references.
- The command wrappers are deprecated but still the dispatch target for `skills/sprint-auto/SKILL.md` and a tool comment.

Every shared-skill edit must be manually mirrored to the agent files or it drifts — a structural tax IDEA-005 reduced but didn't eliminate.

## 3. Requirements Trace

- **R1** — Delete `AGENT_bugbot.md` + `AGENT_copilot.md`; no content loss for the load-bearing material.
- **R2** — Delete `commands/bugbot-loop.md` + `commands/copilot-loop.md`; `/review-loop` is the sole entry point.
- **R3** — `skills/sprint-auto/SKILL.md` review dispatch (S3, S6, S11.10, S13, S14 + References) rewired to a **single multi-engine** `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE` call that passes the full resolved engine list, replacing today's two sequential single-engine loop invocations. When ≥2 engines are configured/available, this uses review-loop's native concurrent multi-engine sync (`dual-engine-sync.md` — wait for slowest per SHA, batch findings into one fix commit). Generalizes to N engines with no further change. `SPRINT_AUTO_REVIEW_ENGINE` selector *grammar* unchanged; *dispatch semantics* change from per-engine-sequential to one concurrent session. The `none` path still skips.
- **R4** — Common review patterns + failure-mode taxonomy + autonomy-ladder examples preserved in the shared skill / engine references.
- **R5** — All cross-references (README, guides, ONBOARDING, tool comment, AGENTS/CLAUDE, engine-ref attributions) point at `/review-loop` / engine refs; v4.2 deprecation banners removed.
- **R6** — Ships as v4.3; `make test-release` extracts `v4.3`; CHANGELOG section added.
- **R7** — `rename-before-drop`: rewire/migrate lands + verifies green BEFORE any delete.

## 4. Scope Boundaries

**In scope:** the four file deletions, content migration into references/shared skill, project-wide reference rewire, sprint-auto dispatch rewire, v4.3 release.

**Out of scope:**
- `AGENT_curator.md` — stays; it's the `none`-engine review gate. Only its one stale *example* line (proposing to extend `AGENT_bugbot` PASS 2) gets re-pointed.
- The shared `SKILL.md` Phase 0–4 orchestration — already canonical; not re-authored.
- Historical records: CHANGELOG dated sections, `docs/archive/2026-05-idea-005-*`, `docs/plans/2026-04-19-sprint-workflow.md` — **never rewritten** (they describe what was true at the time).

**Non-goals:** no behavioural change to the review loop; no new engine; no change to `SPRINT_AUTO_REVIEW_ENGINE` selector grammar.

## 5. Context & Research

**Reference rewire is grep-driven, NOT a line-targeted enumeration.** Architect review found the surface is ~25 files — far more than a hand-listed table captures, and line numbers drift as files change. The authoritative scope is the grep itself, run at PR-1 time:

```bash
grep -rln 'AGENT_bugbot\|AGENT_copilot\|/bugbot-loop\|/copilot-loop' --exclude-dir=.git . \
  | grep -v 'CHANGELOG.md\|docs/archive/\|docs/plans/'
```

Every live hit is rewired in PR-1; use **full-file replace** per file, not line-targeted edits (the sprint-auto Interaction-rules block at L264/L267 and References sit outside the procedure-step lines and are easy to miss otherwise). The set as of 2026-05-25 (authoritative list is the live grep):

- **High-blast dispatch** — `skills/sprint-auto/SKILL.md` (description, S3/S6/S11.10/S13/S14, selector block L268-273, Interaction-rules L264/L267, References L302) + `skills/sprint-auto/references/escalation-policy.md` (L3, L9, L50). Replace every per-engine `/bugbot-loop` / `/copilot-loop` call with **one** `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE` per pass (concurrent multi-engine when >1; per KD3). Rewrite the L268-273 selector block's "invoke both loops sequentially, bugbot first then copilot" → "pass the resolved engine list to one `/review-loop` call (concurrent sync per `dual-engine-sync.md`)". Reconcile the "20 cycles per engine" budget wording (L267 + escalation-policy L50) to review-loop's session cap (KD6). Preserve `none`-skip.
- **Engine refs / shared skill** — `engine-bugbot.md` (§ Common patterns pointer, § Notes — delete), `engine-copilot.md` (§ Common patterns pointer + ×3 "Per AGENT_copilot.md" attributions; the stale-context + first-run-calibration sections are already engine-local — leave), `engine-adapter-contract.md` (L99 "Borrows from AGENT_<engine>.md" → point at `common-review-findings.md`), `dual-engine-sync.md`, `SKILL.md` (L111 scratch note, L216 References entry).
- **Commands** — `commands/review-loop.md` (L47-48 "See also" links to the wrappers → remove), and the two wrapper files themselves (deleted in PR-2).
- **Skills referencing the loop as input/source** — `skills/compound/SKILL.md`, `skills/compound/references/review-finding-ingest.md` (L7 names the command files explicitly), `skills/compound/references/routing-decision-tree.md`, `skills/work/references/AUDIT_NEWLY_REACHABLE_CODE.md` (L61), `skills/dependabot-triage/SKILL.md` (L184), `skills/deployment/references/SHELL_INSTALLERS.md` (L458 backref to AGENT_bugbot §9 → point at migrated location).
- **Docs** — `README.md` (mermaid node + design note; "deprecated as of v4.3 (upcoming)" → "removed in v4.3"), `docs/guides/SPRINT_WORKFLOW.md` (mermaid), `docs/guides/WORKTREE_PRACTICES.md` (L96/L113), `docs/guides/GIT_WORKFLOW.md` (L56/L63/L75/L180), `docs/guides/ONBOARDING.md` (L25/L40/L239), `tools/README.md` (L132), `docs/ideas/README.md` (the IDEA-006 entry — leave; it legitimately names what's being deleted).
- **`agents/AGENT_curator.md`** (L141-143 stale proposal to extend AGENT_bugbot PASS 2 → re-point to engine-ref / `/compound`).
- **Tool-script comments** — `tools/find_bugbot_comments.sh` (7 hits), `tools/find_copilot_comments.sh` (L18). These are informational comments in tools that are NOT being deleted. **Decision: rewire them in PR-1** (cheap, keeps PR-2's re-grep a clean zero) rather than carrying an exclusion list.
- **`skills/sprint-auto/IDEA_integration_branch.md`** — `Status: planned (v3.1)` but sprint-auto is now v3.2: an effectively-superseded design doc still sitting outside `docs/archive/`. Treat as live and rewire the wrapper names (lowest-risk); flag at `/wrap` whether it should be archived.
- **Historical — leave untouched:** CHANGELOG dated sections, `docs/archive/2026-05-idea-005-*`, `docs/plans/2026-04-19-*`.

**Critical finding — the two catalogues are duplicates.** `AGENT_bugbot.md` "Common Bugbot Patterns" §1-19 and `AGENT_copilot.md` "Common Review Findings" §1-19 are the *same 19 patterns, near-verbatim* (only #19 swaps "Bugbot"↔"Copilot" in prose). The IDEA's original wording ("append §1-8 to engine-bugbot, copilot findings to engine-copilot") predates the catalogue growing to 19 and would duplicate it across both engine refs — re-creating the drift IDEA-006 exists to remove.

**Genuinely engine-specific content** (small): bugbot's `CHECKRUN status=in_progress >15min` stall threshold; copilot's reviewer-self-removal retrigger semantics, service-error patterns, stale-context bail rule (already in `engine-copilot.md` § Stale-context). The autonomy ladder + hard bounds are already in `SKILL.md` (Phase 1 § Triage, Hard bounds) — the agent files' versions are near-identical restatements.

**Institutional learnings:** `RULE_rename-before-drop` (sequence rename→test→drop; never bundle multi-file rename with drop) and `RULE_self-sweep-before-push` (trigger 5 doc-consistency, just shipped v4.2.2) both apply directly.

## 6. Key Technical Decisions

- **KD1 — Shared catalogue, deduplicated in BOTH dimensions.** Migrate the catalogue ONCE into `skills/review-loop/references/common-review-findings.md`; both engine refs link to it. But the dedup is two-dimensional, not just bugbot↔copilot:
  1. **Across the two agent files** — the lists are word-for-word identical → merge to one.
  2. **Across the rest of the vault** — several of the 19 already have canonical homes and must NOT be re-stated (that relocates redundancy instead of removing it): #15 shell-installer → `skills/deployment/references/SHELL_INSTALLERS.md`; #19 contract-change sweep → `rules/RULE_self-sweep-before-push.md` § Contract-Change Sweep (trigger 2); and several Django/HTMX ones overlap domain refs (#1 `transaction.atomic`, #11 queryset re-filter/N+1 → `skills/django/`; #16 messages-middleware, #17/#18 Alpine+HTMX reactive → `skills/django-frontend/references/{ALPINE_HTMX_GOTCHAS,HTMX_PATTERNS}.md`).
  
  **Catalogue shape:** a scannable review-lens index — one-line description per pattern (so it works as a "what bots commonly flag" checklist) + a link to the canonical home for depth. Full prose stays in the catalogue ONLY for patterns with no existing home. This keeps the catalogue DRY against the *whole* vault, which is the IDEA-005/006 thesis taken to its conclusion. *(Reusable lesson — flag at `/wrap` for `/compound`: "consolidating a duplicated catalogue → dedup against ALL existing homes, not just the obvious copies.")*
- **KD2 — Autonomy ladder + hard bounds are already canonical in `SKILL.md`.** Do NOT re-add them; only port any pedagogically-richer *example* the agent files have into `SKILL.md` Phase 1 § Triage if it adds signal. Expect near-zero net new content here.
- **KD3 — sprint-auto rewire is the load-bearing verification, and a behavioral simplification (not pure string-sub).** The original `auto_safe` "verify sprint-auto" concern resolves here: sprint-auto couples to the *commands*, not the agents. Rather than substitute two sequential calls (`/bugbot-loop`→`/review-loop <PR> bugbot`, then `/copilot-loop`→`/review-loop <PR> copilot`), collapse each pass to **one** `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE` call passing the whole engine list — review-loop runs single-engine when |engines|=1 and concurrent multi-engine when >1. Must preserve the `none`-skip path; the fixed bugbot-then-copilot sequential ordering wording is *replaced* by concurrent-sync, not preserved.
- **KD4 — Deprecation banners come down.** The v4.2 banners on the wrappers warned of v4.3 removal; in PR-2 they're deleted with the files, and README's "deprecated as of v4.3 (upcoming)" line becomes "removed in v4.3".
- **KD5 — Two PRs, prepare-then-drop** (user-selected). PR-1 additive + rewire (all four files still present, verify green); PR-2 deletes + v4.3 bump.
- **KD6 — Budget semantics: delegate to review-loop's session caps.** Today sprint-auto frames the caps as "20 cycles **per engine**" (an artifact of two sequential single-engine loops — SKILL L267, escalation-policy.md). One concurrent `/review-loop` session has **session-level** caps (`max_commits_per_session=20`, `max_idle_polls=20` across all engines) and batches findings from all engines into one fix commit per cycle — so the unified 20-commit budget covers both engines together, not 20-each. Reconcile the per-engine wording in `skills/sprint-auto/SKILL.md` L267 + `references/escalation-policy.md` L3/L9/L50 to the session-cap model. Net effect: simpler and tighter, no behavioural surprise (a multi-engine cycle already fixes both engines' findings in one commit).

## 7. Open Questions — all resolved at architect review (2026-05-25)

- **Q1 — Shared-catalogue home? RESOLVED: new dedicated `common-review-findings.md`.** Not folded into `engine-adapter-contract.md` — that file is an interface spec (required scripts/sections/output schema); injecting 19 concrete patterns + code blocks would bloat it ~137→~500L and dilute its single responsibility. Both engine refs link out to the content file. (KD1 stands.)
- **Q2 — v4.3 timing? RESOLVED: PR-1 → `## Unreleased`, PR-2 creates `## v4.3`.** The version IS the deletion; no `v4.3-rc` header (would confuse `make test-release`'s `## v4.X` anchor). Matches the v4.2 pattern + the reserved CHANGELOG placeholder.
- **Q3 — Live sprint-auto run to verify R3? RESOLVED: no, but the residual-risk note carries more weight now.** R3 is no longer pure string-sub — it changes dispatch from per-engine-sequential to one concurrent multi-engine session (KD3/KD6). The concurrent mode is a tested first-class path (IDEA-005 dogfooded `/review-loop 131 bugbot,copilot`), so static verification (grep audit + the v4.3 PRs' own review pass + budget-wording reconciliation check) still suffices for merge. **Mandatory PR-2 hand-back line:** the first post-v4.3 sprint-auto run with `SPRINT_AUTO_REVIEW_ENGINE=bugbot,copilot` must confirm the single-call concurrent dispatch + session-cap budget behave as intended.

## 8. Execution Sequence

### PR-1 — Prepare (rename phase; additive + rewire, zero deletions) — ✅ shipped as [PR #139](https://github.com/infohata/mind-vault/pull/139)

> Commits: `d98484f` (catalogue migration), `aec0704` (sprint-auto multi-engine dispatch), `1412bf5` (reference sweep), `cf31ef0` (CHANGELOG Unreleased). Verified: live-ref grep clean (only the 4 targets + historical/index), `make extract-version`→`v4.2.2`, links resolve. PR-2 (drop) pending — opens after PR-1 merges.

1. **Create `skills/review-loop/references/common-review-findings.md`** — migrate from `AGENT_bugbot.md` (the canonical copy; #19 prose generalised to "the engine"), deduplicated per KD1. For each of the 19, audit for an existing canonical home (`grep -rl` the pattern's keyword across `rules/`, `skills/django*/`, `skills/deployment/`): if one exists, write a **one-line review-lens entry + link** (do not restate); only patterns with no home keep full prose. Known homes to link, not restate: #15→SHELL_INSTALLERS, #19→RULE_self-sweep § Contract-Change Sweep, #1/#11→django, #16/#17/#18→django-frontend gotchas. Result is a scannable Tier-1 index, not a 19-pattern wall.
2. **`engine-bugbot.md`** — replace § Common patterns "defer to AGENT_bugbot.md" with a link to `common-review-findings.md`; fold the bugbot-specific stall threshold into § Failure modes; delete § Notes (the AGENT_bugbot location note is obsolete).
3. **`engine-copilot.md`** — point § Common patterns at `common-review-findings.md`; inline the three "Per AGENT_copilot.md" empirical facts (reviewer self-removal, COMMENTED-never-APPROVED, clean≡no-new-comments) as adapter-owned statements; drop the agent-file attributions.
4. **`SKILL.md`** — port any load-bearing autonomy-ladder *example* into Phase 1 § Triage (likely none new); reword the L111 scratch note to drop the `AGENT_*.md` backref; drop the L216 References entry pointing at `AGENT_bugbot.md`.
5. **Rewire sprint-auto dispatch to single multi-engine `/review-loop`** (KD3 + KD6) — `skills/sprint-auto/SKILL.md`: collapse each pass's per-engine call into one `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE` across description, S3 (L116), S13/S14 (L192), selector block (L268-273), Interaction-rules (L264/L267), References (L302); rewrite the "sequential, bugbot-first" selector prose to "concurrent multi-engine sync"; reconcile the per-engine budget wording (L267 + `escalation-policy.md` L3/L9/L50) to the session cap. Preserve `none`-skip.
6. **Rewire ALL live references — grep-driven full sweep** (§5 authoritative grep). Includes the high-blast sprint-auto dispatch + escalation-policy, compound/work/dependabot skills, all four guides, README, both tool-script comment sets, `engine-adapter-contract.md` L99, `commands/review-loop.md` See-also links, and `IDEA_integration_branch.md`. Full-file replace per file, not line-targeted. Verify zero double-insert of the COMMENTED-never-APPROVED fact in `engine-copilot.md` (it exists in both the migrated calibration block and § Clean-signal parsing).
7. **CHANGELOG** — add `## Unreleased` bullets (Added: common-review-findings.md; Changed: sprint-auto dispatch, engine refs, docs).
8. **Self-sweep (triggers 1 + 5)** + push; run `/review-loop <PR-1> copilot` (+ bugbot if available). All four target files still exist → green gate confirms the rewired dispatch is correct.

### PR-2 — Drop (destructive phase; v4.3)

9. `git rm agents/AGENT_bugbot.md agents/AGENT_copilot.md commands/bugbot-loop.md commands/copilot-loop.md`.
10. **Re-grep + triage** (not a bare zero-assert). Run the §5 grep; for each survivor: rewire it here if it's a live reference PR-1 missed, or confirm it's historical (CHANGELOG/archive/old-plan). Because PR-1 rewires the tool-script comments too, the live set should be empty — any hit is either a PR-1 miss to fix now or a historical exclusion. Also grep `](.*\(AGENT_bugbot\|AGENT_copilot\|bugbot-loop\|copilot-loop\)` for dead relative links.
11. **CHANGELOG v4.3** — create `## v4.3` header; the deletion is the release. Headline: review-surface collapse to single `/review-loop` entry.
12. Self-sweep + push; `/review-loop <PR-2>` for regression. After merge: `make release` (extracts `v4.3`).

## 9. Verification

- `grep -rn 'AGENT_bugbot\|AGENT_copilot\|/bugbot-loop\|/copilot-loop' --exclude-dir=.git .` after PR-2 → only historical hits (CHANGELOG dated sections, `docs/archive/2026-05-idea-005-*`, `docs/plans/2026-04-19-*`).
- No content loss AND no relocated redundancy: each of the 19 patterns is reachable from `common-review-findings.md` (as full prose if homeless, else a one-line entry + link to its canonical home); no pattern with an existing home (`SHELL_INSTALLERS`, `RULE_self-sweep`, django/django-frontend refs) is re-stated verbatim. Each engine-specific fact present in its engine ref.
- `make test-release` → `v4.3`.
- sprint-auto dispatch audit: every former wrapper call now reads a single `/review-loop <PR> $SPRINT_AUTO_REVIEW_ENGINE`; the selector block describes concurrent multi-engine (not sequential); per-engine budget wording reconciled to the session cap; `none`-skip preserved.
- Both PRs clear their own `/review-loop` pass.
- Markdown link integrity: no broken relative links to the deleted files (grep `](.*AGENT_bugbot` etc.).

## 10. Architect review (2026-05-25)

**Verdict: ARCHITECTURALLY SOUND** — no blocking flaws. The 2-PR sequencing is correct under `rename-before-drop`; the shared-catalogue decision is correct; coupling model is clean. Findings folded into §5/§7/§8 above:

- **Major — reference-site list was incomplete.** Independent grep found ~25 live sites vs the draft's ~11. Resolution: §5 is now grep-driven (full sweep), not a hand-listed table; PR-1 step 6 rewrites every live hit via full-file replace; PR-2 step 10 is now triage-not-assert.
- **Confirmed: duplication claim accurate.** AGENT_bugbot §1-19 and AGENT_copilot §1-19 are word-for-word identical (only #19 + two drill-side sentences swap engine name). KD1 shared catalogue is the correct fix.
- **Confirmed: no content loss.** PASS 0 (worktree bootstrap), "How to Deliver Your Verdict", first-run-calibration, and the autonomy ladder / hard bounds are all already canonical in `SKILL.md` / engine refs (KD2). The only uniquely-engine content (bugbot stall threshold; copilot self-removal / COMMENTED-never-APPROVED / stale-context) is explicitly preserved. engine-copilot's § Stale-context + § first-run-calibration are already engine-local → leave in place, don't migrate.
- **Minor — double-insert risk** in engine-copilot.md (COMMENTED-never-APPROVED appears in both the calibration block and § Clean-signal parsing) → guarded in step 6.
- **Q1/Q2/Q3 — resolved** (see §7).

Plan marked `status: ready` post-review.
