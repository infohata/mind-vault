---
name: IDEA-003-version-tag-automation
description: Automate the `git tag v<N>` + `gh release create` step that currently lives outside /wrap — Step 4b updates the version source but a human still tags by hand after merge
status: idea
priority: medium
created: 2026-05-18
related:
  - 2026-05-idea-002-skill-debloat  # /wrap evolution thread
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

## Recommendation when this is picked up

Ship Option 1 first — single Makefile target, low risk, the wrap hand-back message gets one line added pointing at `make release`. Then evaluate after 2–3 wrap-and-bump cycles whether the manual step is actually getting forgotten in practice; if yes, layer Option 2 on top (the workflow can coexist with the Makefile — the Makefile becomes the local-override / dry-run path, the workflow is the production-automation path).

**Don't ship Option 2 first** — the GHA diff-detection logic is fiddly enough that getting it wrong (false positives on commit-message typos, false negatives on multi-bump PRs) would create more confusion than the current manual-tag flow.

## Acceptance criteria

- A new IDEA-NNN sprint that delivers at least Option 1:
  - [ ] `Makefile` `release` target added (or equivalent task in `pyproject.toml` / `package.json` scripts for non-Make projects)
  - [ ] Version-extraction logic handles all the version sources `/wrap` Step 4b detects (one grep / parse per source format)
  - [ ] Idempotent — re-running `make release` when the tag already exists is a no-op with a clear message, not a crash
  - [ ] `/wrap`'s hand-back message points at the convention when Step 4b has fired
  - [ ] Mind-vault dogfoods it: the IDEA's own merge bumps a version + runs `make release` in the same wrap pass

- If Option 2 layered on later (separate IDEA):
  - [ ] GHA detects a new `## v<N>` header and skips edits to existing sections
  - [ ] Multi-bump PRs (a single PR that introduces multiple `## v<N>` headers — rare but legal under cohort-finishing rules) tag the *latest* version, not the first
  - [ ] Workflow-permission setup documented (the GHA token needs `contents: write` for tag creation)

## Why this is medium-priority

The manual tag is small per-occurrence (~30 seconds) and the loss of automation is only painful if many bumps happen in a short window. PR #121 introduces Step 4b but Step 4b is conservative — most wrap invocations will NOT trigger a bump. The automation pays off once enough version bumps have shipped to expose the forgotten-tag pattern. Not a blocker for v4.0.2.

## References

- [PR #121](https://github.com/infohata/mind-vault/pull/121) — introduced Step 4b (version-bump consideration); deferred the tag step to manual / future automation.
- [`skills/wrap/SKILL.md`](../../skills/wrap/SKILL.md) Step 4b — the version-source detection logic this IDEA's automation would consume.
- Sister memory note [`project_multi_engine_sync_cycle_insight`](../../.claude/memory/projects/mind-vault/project_multi_engine_sync_cycle_insight.md) — example of a recent /wrap-adjacent improvement.
