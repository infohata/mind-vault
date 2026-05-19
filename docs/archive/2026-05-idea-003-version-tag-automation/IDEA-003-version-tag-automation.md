---
name: IDEA-003-version-tag-automation
description: Add a `make release` target that tags + pushes + GH-releases the version `/wrap` Step 4b just bumped, so the human runs one command post-merge instead of three. Option 2 (GHA auto-tag-on-merge) deferred to a follow-up IDEA.
status: in-progress
priority: medium
created: 2026-05-18
related:
  - 2026-05-idea-002-skill-debloat  # /wrap evolution thread
# Sprint-auto eligibility gates
auto_safe: true
auto_safe_reason: "Additive Makefile target + one-line `/wrap` hand-back tweak; reversible by deleting the target. Version-extraction is mechanically testable against fixture CHANGELOG / pyproject.toml / package.json. No migrations, no schema, no docker stack."
sensitive_paths_cleared: true
sensitive_paths_cleared_reason: "Touches the `/wrap` skill (sprint-workflow infra), but the change is a single additive line in the hand-back message; cohort-position constraint (solo or LAST) prevents in-flight wrap modification while sibling IDEAs are still running. `gh release create` is invoked only by the human post-merge, never by sprint-auto."
---

# IDEA-003 — Version-tag automation post-`/wrap`

## Problem

`/wrap`'s new Step 4b ([commit `8bc950b`](https://github.com/infohata/mind-vault/pull/121/commits/8bc950b)) lands the version bump *inside the repo* — CHANGELOG header, README badge, ONBOARDING callout all flip on PR merge. But the git tag + GitHub Release remain a manual step: the human runs `git tag v4.0.2 && git push origin v4.0.2` (or `gh release create v4.0.2 --generate-notes`) some time after the merge.

Two failure modes:

1. **Drift** — version-in-CHANGELOG advances but no corresponding tag exists. External tools that read tags (Dependabot, mirror tooling, badge services) see a stale version. The next PR's reviewer can't tell from `git tag` whether v4.0.2 actually shipped.
2. **Tag-pointing-at-deleted-SHA** — if the wrap commits are tagged on the feature branch and the PR is later closed without merging, the tag points at a SHA that no longer exists on `main`. Step 4b explicitly defers tagging post-merge to avoid this, but the manual step is easy to forget.

The cost is small per occurrence but compounds — a multi-month "what version is `main` actually on?" ambiguity emerges if a few wrap PRs in a row skip the manual tag.

## Two options surfaced during PR #121 review

### Option 1 — `Makefile` `release` target (cheap, opt-in per project)

Add a project-local target that reads the current version from the version-source file `/wrap` already detects (per Step 4b: `VERSION` / `pyproject.toml` / `package.json` / `Cargo.toml` / `setup.py` / `CHANGELOG.md` `## v<N>` header), creates the tag, and pushes it:

```makefile
release: ## tag and push the version currently in CHANGELOG.md
	@VER=$$(grep -m1 '^## v[0-9]' CHANGELOG.md | sed 's/^## \(v[^ —]*\).*/\1/'); \
	  test -n "$$VER" || (echo "no v<N> header in CHANGELOG.md"; exit 1); \
	  git tag "$$VER" && git push origin "$$VER" && \
	  gh release create "$$VER" --generate-notes
```

Then post-merge the human runs `make release` once. The wrap skill could be extended to mention this convention as the canonical follow-up command in its hand-back message.

**Pros**: simple, local, no GitHub Actions setup, the human stays in control of when the tag fires (e.g. can hold tag until downstream sanity-checks pass), works identically across project version-source formats (the version-extraction grep is the only per-source variation).

**Cons**: still manual; humans forget; doesn't catch the "tag missing for an old version" drift.

### Option 2 — GitHub Action `release-on-version-bump.yml` (true hands-off)

A workflow that watches for merges to `main` whose diff touches a `## v<N>` header in `CHANGELOG.md` (or the version field in pyproject.toml / package.json / etc.), extracts the new version, creates the tag, and publishes a GitHub Release with notes auto-generated from the merged PR's body:

```yaml
on:
  push:
    branches: [main]
    paths:
      - CHANGELOG.md       # mind-vault style
      - VERSION
      - pyproject.toml
      - package.json
jobs:
  tag-and-release:
    if: <diff contains a new ## v<N> header OR a version-field change>
    runs-on: ubuntu-latest
    steps:
      - …extract new version
      - …git tag + push
      - gh release create $NEW_VERSION --generate-notes
```

**Pros**: truly hands-off; impossible to forget; the tag fires within seconds of merge so external tooling sees a coherent state; can be templated as a reusable workflow that any project adopting mind-vault inherits.

**Cons**: more moving parts (GHA permissions, the diff-detection step is subtler than it looks — has to distinguish a *new* version section from edits to an existing one, has to handle the bump-without-CHANGELOG-edit case for VERSION-file projects), and re-firing on the same version (e.g. a typo-fix commit that touches the line) creates a duplicate-tag failure mode.

## Scope decision (2026-05-19)

**IDEA-003 = Option 1 only.** The GHA workflow (Option 2 above) is deferred to a separate follow-up IDEA — see [Follow-up: Option 2](#follow-up-option-2-gha-auto-tag-on-merge) below. Rationale: GHA permission setup + diff-detection logic is fiddly enough that getting it wrong creates more confusion than the current manual-tag flow; ship the cheap manual command first, observe whether the forgotten-tag pattern actually surfaces in practice, then decide whether to layer automation on top.

## Cohort-position constraint (sprint-auto)

This IDEA modifies the `/wrap` skill's hand-back message, and `/wrap` is invoked by sprint-auto itself. To avoid in-flight modification of `/wrap` while sibling IDEAs in the same cohort are still running their wrap passes:

- **Run solo** (single-IDEA sprint-auto cohort), OR
- **Run LAST in a multi-IDEA cohort** (after every sibling IDEA's per-IDEA wrap has completed; the modified wrap behaviour is then exercised only by the integration-branch batch wrap, which runs once).

Sprint-auto's IDEA-ordering hints (or human cohort selection) must respect this.

## Acceptance criteria

- [ ] `Makefile` `release` target added (or equivalent task in `pyproject.toml` / `package.json` scripts for non-Make projects)
- [ ] Version-extraction logic handles all the version sources `/wrap` Step 4b detects (one grep / parse per source format: `VERSION`, `pyproject.toml`, `package.json`, `Cargo.toml`, `setup.py`, `CHANGELOG.md` `## v<N>` header)
- [ ] Idempotent — re-running `make release` when the tag already exists is a no-op with a clear message, not a crash
- [ ] Version-extraction logic has unit-test coverage against fixture files for each version source (run in CI / by sprint-auto's test pass, without invoking `git tag` / `gh release` for real)
- [ ] `/wrap`'s hand-back message gains a one-line instruction: when Step 4b has fired in the just-merged PR, suggest the human runs `make release` (or the project-specific equivalent) post-merge

**Dogfood**: NOT automated as part of this IDEA's sprint-auto pass. Sprint-auto cannot run `make release` itself — tagging is post-merge to a protected branch, which is the human merge gate per [`RULE_git-safety`](../../rules/RULE_git-safety.md). Verification that the dogfood works happens manually after the human merges IDEA-003's PR and runs `make release` against mind-vault's own then-current version. The wrap hand-back message will surface the instruction.

## Follow-up: Option 2 (GHA auto-tag-on-merge)

Deferred to a separate IDEA, to be filed only after 2–3 wrap-and-bump cycles have empirically demonstrated that the manual `make release` step is being forgotten in practice. The workflow can coexist with the Makefile — the Makefile becomes the local-override / dry-run path, the workflow is the production-automation path. Scope when filed:

- [ ] GHA detects a new `## v<N>` header and skips edits to existing sections
- [ ] Multi-bump PRs (a single PR that introduces multiple `## v<N>` headers — rare but legal under cohort-finishing rules) tag the *latest* version, not the first
- [ ] Workflow-permission setup documented (the GHA token needs `contents: write` for tag creation)
- [ ] Duplicate-tag failure mode handled (re-fire on the same version, e.g. a typo-fix commit touching the line, must be a clean no-op)
- [ ] Not sprint-auto eligible — GHA permission / diff-detection edge cases need human supervision on first fire

## Why this is medium-priority

The manual tag is small per-occurrence (~30 seconds) and the loss of automation is only painful if many bumps happen in a short window. PR #121 introduces Step 4b but Step 4b is conservative — most wrap invocations will NOT trigger a bump. The automation pays off once enough version bumps have shipped to expose the forgotten-tag pattern. Not a blocker for v4.0.2.

## References

- [PR #121](https://github.com/infohata/mind-vault/pull/121) — introduced Step 4b (version-bump consideration); deferred the tag step to manual / future automation.
- [`skills/wrap/SKILL.md`](../../skills/wrap/SKILL.md) Step 4b — the version-source detection logic this IDEA's automation would consume.
- Sister memory note [`project_multi_engine_sync_cycle_insight`](../../.claude/memory/projects/mind-vault/project_multi_engine_sync_cycle_insight.md) — example of a recent /wrap-adjacent improvement.
