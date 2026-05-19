---
stage: plan
slug: version-tag-automation
created: 2026-05-19
source: ./IDEA-003-version-tag-automation.md
status: draft
project: mind-vault
---

# Plan — Version-tag automation post-`/wrap` (Option 1: `make release`)

## Context

[`IDEA-003`](./IDEA-003-version-tag-automation.md) was scoped to Option 1 in the 2026-05-19 scope-decision pass: ship a `make release` target that collapses the three-command post-merge sequence (`git tag` + `git push origin <tag>` + `gh release create`) into one human-invoked command. `/wrap` Step 4b (introduced in [PR #121](https://github.com/infohata/mind-vault/pull/121)) already handles the in-repo version bump on merge; the tag step is the missing link. This plan delivers the Makefile target + unit-test coverage for the version-extraction logic + a `/wrap` hand-back instruction. mind-vault is the first consumer; other projects copy the Makefile recipe as-is.

## Problem Frame

After a wrap PR lands a version bump (e.g. CHANGELOG `## v4` → `## v5`, or VERSION `4.1.0` → `4.2.0`), the human is currently expected to remember three follow-up commands post-merge. Forgotten tags create drift between the in-repo version and `git tag --list` — external tools (Dependabot, mirror tooling, badge services) read tags, not CHANGELOG headers, and surface stale state. A reviewer querying `git tag` later cannot tell whether v4.0.2 actually shipped or just appeared in CHANGELOG. The cost is small per occurrence but compounds across multiple wrap-and-bump cycles.

## Requirements Trace

- **R1.** A `Makefile` exists at the mind-vault repo root with a `release` target (per IDEA-003 acceptance criterion #1).
- **R2.** The `release` target's version-extraction logic handles all six version sources `/wrap` Step 4b detects (`VERSION`, `pyproject.toml`, `package.json`, `Cargo.toml`, `setup.py`, `CHANGELOG.md` with `## v<N>` headers).
- **R3.** Re-running `make release` when the target tag already exists is a no-op with a clear message — not a `git tag` failure (per IDEA-003 acceptance criterion #3).
- **R4.** Version-extraction logic has unit-test coverage against fixture files for each source type, runnable without invoking real `git tag` / `gh release create` (per IDEA-003 acceptance criterion #4).
- **R5.** `/wrap` Step 4b's "Mechanics when a bump is warranted" section gains a hand-back instruction pointing at `make release` (per IDEA-003 acceptance criterion #5).
- **R6.** An explicit `VERSION=` argument overrides auto-extraction — escape hatch for projects (like mind-vault) where the CHANGELOG header version differs from the intended tag (e.g. CHANGELOG `## v4` but tagging `v4.0.2`).

## Scope Boundaries

**In scope:**

- New `Makefile` at repo root (mind-vault has no existing Makefile).
- New `tests/test_release_extraction.sh` + `tests/fixtures/release/` fixtures for unit tests.
- Edit to `skills/wrap/SKILL.md` Step 4b adding the hand-back instruction.

**Out of scope:**

- Option 2 (GHA `release-on-version-bump.yml` workflow) — deferred to a follow-up IDEA per IDEA-003's scope decision.
- Auto-running `make release` from `/wrap` or `/sprint-auto` — `RULE_git-safety` requires the human as the tagger; the Makefile target is explicitly invoked by the human post-merge.
- Per-project version source overrides — every supported source has a single canonical extraction recipe; projects with custom layouts can override the target locally.
- Bumping the version itself — Step 4b owns that; `make release` consumes whatever Step 4b decided.

**Explicit non-goals:**

- The target must NOT push to a protected branch (`git push origin <tag>` pushes a tag ref, not a branch; this is allowed under `RULE_git-safety` § 2, but flag if anyone reads it the wrong way).
- The target must NOT skip GH hooks or signing (`--no-verify`, `--no-gpg-sign`) on the tag command.
- The target must NOT attempt to fix CHANGELOG entries, write release notes from scratch, or modify any source file — it reads version, tags, pushes, and asks GitHub to generate notes from PR titles.

## Context & Research

### Existing code and patterns to reuse

- [`skills/wrap/SKILL.md`](../../../skills/wrap/SKILL.md) Step 4b (lines 239–288) — canonical version-source detection logic. The Makefile's extraction must produce the same answer for each source type. Notably line 282: *"don't `git tag` from the wrap commit itself unless the project's CI requires it (the human is the tagger by default)"* — `make release` is exactly the convenience target for that human-tagger step.
- [`CHANGELOG.md`](../../../CHANGELOG.md) header `## v4 — Multi-engine code review + open-source release candidate` — mind-vault's current latest version header. The regex must strip the trailing description (everything after the first space-em-dash).
- `git tag --sort=-v:refname | head -1` returns `v4.0.1` — mind-vault's most recent tag, demonstrating the CHANGELOG-header vs git-tag divergence that motivates R6's explicit-override.
- `tools/sprint-auto-bootstrap.sh` (lines 116–117) already requires `docker`, `jq` on PATH for sprint-auto-eligible repos — `jq` is a safe dependency for `package.json` parsing.

### Institutional learnings

- [`RULE_git-safety`](../../../rules/RULE_git-safety.md) § 2 — tag-push is allowed (tag refs are not branch refs), but `gh release create` against a protected branch is fine because it only annotates the existing commit, doesn't push to it.
- [`RULE_self-sweep-before-push`](../../../rules/RULE_self-sweep-before-push.md) — the Makefile change is shell, not Python/JS, so pyflakes doesn't apply; sweep means `shellcheck` if available, otherwise eyeball.

### External references

- [`gh release create`](https://cli.github.com/manual/gh_release_create) — `--generate-notes` flag uses GitHub's automatic release-notes-from-PRs feature; falls back to commit-message log if no PRs match. Confirmed compatible with annotated and lightweight tags.

## Key Technical Decisions

- **Single-file Makefile, no auxiliary scripts.** Keep the surface minimal — the extraction logic is ~30 lines of bash, well within Makefile recipe scope. No separate `tools/release.sh` adds nothing.
- **Bash + `jq` only.** `jq` for `package.json`; pure `grep`/`sed` for everything else. Avoids a Python dependency for a five-format extractor.
- **Explicit `VERSION=` arg overrides auto-extraction.** When the user runs `make release VERSION=v4.0.2`, the extraction step is skipped. When omitted, the target extracts per source type. Mind-vault's CHANGELOG/tag divergence is handled by the user always passing `VERSION=` for patch tags; auto-extraction is the convenience for projects whose CHANGELOG header IS the canonical version (most projects following Keep-a-Changelog with explicit patch headers).
- **Idempotency via `git tag -l <ver>` pre-check.** If the tag exists locally, exit 0 with a clear message (`tag <ver> already exists — skipping`). If the local tag is missing but the remote has it, the `git push origin <ver>` step's failure is the natural signal (don't pre-check `git ls-remote --tags` — slower, and the push's error is already informative).
- **`--generate-notes` for the GH release.** Per IDEA-003 description — GitHub generates notes from the merged PRs between the previous tag and this one. No template authoring required.
- **Tests in shell, not pytest.** Mind-vault has no Python test infrastructure; adding pytest for one shell-extractor test would be ceremony. `tests/test_release_extraction.sh` uses bash assertions (`[[ "$actual" == "$expected" ]] || die "..."`) and exits non-zero on first failure. Runnable via `make test-release` (a sibling Makefile target).

## Open Questions

- **Q1. Should `make release` print the GH release URL after creating it?**
  - **Default:** Yes — pipe `gh release create`'s stdout (which prints the URL) directly. Adopters appreciate the copy-pasteable link without an extra `gh release view` step.
  - **Trade-off:** Adds nothing on failure (the error already prints); on success, +1 line of useful output.

- **Q2. Should the `tests/` dir's fixtures be checked into git or generated at test-run time?**
  - **Default:** Checked in. Diffability matters when the extraction logic changes — reviewers see "fixture changed to add this edge case, here's why" in the same commit as the extraction logic edit. Generated fixtures hide the test surface.
  - **Trade-off:** Six small files (one per source format) added to the repo (~1KB total). Acceptable.

- **Q3. Should the wrap hand-back instruction be conditional (`if SCOPE_IDEA_ONLY != true, suggest make release`) or unconditional?**
  - **Default:** Unconditional — Step 4b itself is already conditional (skipped in `--scope=idea-only`, line 241), so by the time the instruction renders, the user is in a context where the bump applies. Sprint-auto's S5 wrap won't reach Step 4b at all.
  - **Trade-off:** Slight risk of the instruction appearing in a context where the user doesn't want it; the cost is one line of mistaken docs, no executable impact.

## Execution Sequence

1. **Create `tests/fixtures/release/` directory and six fixture files**, each with a known version that the extractor must produce:
   - `tests/fixtures/release/VERSION-only/VERSION` → `1.2.3`
   - `tests/fixtures/release/pyproject/pyproject.toml` → `version = "2.0.0"`
   - `tests/fixtures/release/package/package.json` → `{"version": "3.1.4"}`
   - `tests/fixtures/release/cargo/Cargo.toml` → `version = "0.5.0"`
   - `tests/fixtures/release/setup-py/setup.py` → `setup(name="foo", version="0.9.1", ...)`
   - `tests/fixtures/release/changelog/CHANGELOG.md` → `## v4.0.2 — Some headline`

2. **Create `tests/test_release_extraction.sh`** — bash test harness. For each fixture, run the extraction function (sourced from a small helper or invoked via `make extract-version FIXTURE_DIR=...`), assert the output matches expected. Add cases for: explicit `VERSION=` override returns the override unchanged; missing source dir exits with clear error; CHANGELOG with `## [v4.0.2]` Keep-a-Changelog bracket form also extracts correctly.

3. **Create `Makefile`** at repo root with these targets:
   - `release` — runs version extraction (unless `VERSION=` passed), checks idempotency, tags + pushes + GH-releases.
   - `extract-version` — exposes the extraction logic standalone for testing (`make extract-version FIXTURE_DIR=tests/fixtures/release/cargo` prints `0.5.0`). Implemented as a recipe that sources a small inline script or invokes a function.
   - `test-release` — runs `tests/test_release_extraction.sh`.
   - `help` — prints the available targets and one-line descriptions (standard Makefile-with-help pattern).

4. **Run `make test-release`** — expect all assertions green. Iterate the extraction logic against any fixture that fails until clean.

5. **Run `make release VERSION=v4.0.1`** against the live mind-vault repo (the most recent existing tag) — expect the idempotency check to fire: `tag v4.0.1 already exists — skipping`. Exit 0.

6. **Edit `skills/wrap/SKILL.md` Step 4b** — add a new sub-bullet inside "Mechanics when a bump is warranted" after the existing point 5 (the "tag the commit" note):

   > **5b. Hand-back instruction (post-merge).** When the project ships a `Makefile` with a `release` target (the mind-vault convention from IDEA-003), surface this in the wrap summary: *"After merging, run `make release` (or `make release VERSION=v<N>` if the auto-extracted version differs from the intended tag) to create the git tag + GitHub release."* Projects without a Makefile fall back to the manual `git tag <ver> && git push origin <ver> && gh release create <ver> --generate-notes` sequence.

7. **Self-sweep the changed shell** — `shellcheck Makefile tests/test_release_extraction.sh` if shellcheck is available; otherwise eyeball for quoting + word-splitting hazards.

## Verification

- `make test-release` exits 0 with all assertions green; expected output includes one line per fixture confirming extraction matches expected.
- `make release VERSION=v4.0.1` against the live repo prints `tag v4.0.1 already exists — skipping` and exits 0.
- `make release VERSION=v0.0.0-test-do-not-push` on a throwaway branch (then `git tag -d v0.0.0-test-do-not-push` to clean up) confirms the happy-path tag creation works locally; **do NOT push the test tag**.
- `grep -n 'make release' skills/wrap/SKILL.md` returns the new hand-back instruction text.
- `make help` lists all four targets with their one-line descriptions.

---

**Status:** draft — architect-review skipped (scope is SMALL-bordering-MEDIUM, well-bounded; the riskiest surface is the version-extraction regex per source type, which is covered by R4's unit-test gate). User-approval expected before `/work` execution.
