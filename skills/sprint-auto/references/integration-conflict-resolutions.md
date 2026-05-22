# sprint-auto — integration-stage conflict-resolution catalogue

When **S11.6** (sequential merge of `auto/<slug>` branches into `integration/sprint-auto-<batch-iso>`) hits a conflict, this catalogue is the algorithm reference. Most conflicts are mechanical and fall into one of the patterns below; only a small minority need genuinely judgement-laden resolution, and those are flagged for extra scrutiny in S11.10's review pass.

The principle: **resolutions preserve every IDEA's contribution** unless the conflict shape unambiguously indicates a destructive overlap. When in doubt, "include both contributions" is always safer than picking one side.

## Pattern 1 — Devlog entry collisions (`docs/archive/YYYY-MM-DEVELOPMENT_LOG.md`)

**Conflict shape**: each merged-in IDEA's `/wrap --scope=idea-only` (S5) leaves frontmatter alone but doesn't write devlog. The batch wrap on integration (S11.7) writes ONE devlog commit covering all N IDEAs at the top of the chronological section. So under v3.1, this conflict pattern should never surface during S11.6 — it's already eliminated at the source.

**If it does surface** (because some IDEA's `/work` accidentally appended a devlog entry, or someone hand-edited): the resolution is to remove the partial entry from the conflicted file (delete it from the merge resolution) and trust S11.7 to re-author the unified entry. The S11.10 review pass catches if S11.7's compose missed something.

**Algorithm**:
```
1. Open the conflicted file
2. Identify the conflict region (delimited by <<<<<<< / ======= / >>>>>>>)
3. Discard BOTH branches of the conflict in this region (delete to before the <<<<<<<, delete to after the >>>>>>>)
4. Save (now reflects "no per-IDEA devlog entry"); commit the resolution
5. S11.7 will write the unified entry next
```

## Pattern 2 — Ideas-index collisions (`docs/ideas/README.md`)

**Conflict shape**: same logic as Pattern 1 — under v3.1 each per-IDEA `/wrap --scope=idea-only` skips the index move; S11.7 writes one batched index update.

**Algorithm**: identical to Pattern 1 — discard both branches of the conflict region, let S11.7 re-author.

## Pattern 3 — Translation-file (`.po`) collisions

**Conflict shape**: two IDEAs both added/edited translation keys near each other in the same `.po` file. Each IDEA's keys are typically independent of the other's — they're for different new UI strings.

**Algorithm — "include both contributions"**:
```
1. Find the conflict region.
2. The two branches of the conflict each contain a sequence of msgid/msgstr blocks.
3. Concatenate them: take all blocks from <branch A> followed by all blocks from <branch B>.
4. Deduplicate by msgid: if the same msgid appears in both, keep ONE (prefer branch B's translation since it merges later — but flag this case in the resolution commit message because the duplicate suggests two IDEAs translating the same string differently, which is worth review's attention in S11.10).
5. Save; commit the resolution.
```

**Edge case — fuzzy translations**: if either side has `#, fuzzy` markers, preserve them in the resolution. The next `makemessages` pass cleans up; pretending the translation is final at integration time is wrong per `RULE_i18n-workflow`.

**Edge case — placeholder mismatch**: if the two branches' msgstrs use different placeholder counts (`%(name)s` vs `%(name)s %(count)s`), this is a substantive bug — flag the resolution commit with `[INTEGRATION-FLAG]` prefix so S11.10's review pass surfaces it.

## Pattern 4 — HTML/template collisions

**Conflict shape**: two IDEAs both edited the same template region. Common: shared layout fragments, both adding new buttons/sections nearby. Unlike `.po` files, "include both" isn't always semantically right — the rendered DOM matters.

**Algorithm — guarded "include both"**:
```
1. Read both branches of the conflict.
2. Determine whether the two changes are independent additions (common case) or
   compete for the same position (rare).
   - Independent: each adds new elements at different positions within the
     conflict region. Concatenate (branch A elements first, then branch B's
     elements). Verify the resulting DOM nesting is valid.
   - Competing: both branches replace the same element with different content.
     This is genuinely a judgement call. Apply the most plausible "include
     both" — wrap both in a parent <div> if structural, or keep branch A's
     replacement and add branch B's as a sibling. Always flag the resolution
     commit with [INTEGRATION-FLAG-HTML].
3. Verify the template still parses (run a no-op render via the project's
   smoke test if one is configured for templates; otherwise trust S11.8/S11.9).
4. Save; commit the resolution.
```

**S11.10 review pass** picks up the `[INTEGRATION-FLAG-HTML]` commits and is given priority in the review.

## Pattern 5 — JS/TS collisions

**Conflict shape**: two IDEAs both touched the same module's exports / event listeners / Alpine state. Risk: each IDEA's logic interacts with the other's state in ways neither tested in isolation.

**Algorithm — "include both with explicit interleaving"**:
```
1. Read both branches.
2. If the conflict is in non-overlapping function bodies: just include both function definitions/handlers. Order: branch A first.
3. If the conflict is in shared state (Alpine x-data object, event-listener registration): merge keys/listeners; flag any name collision with [INTEGRATION-FLAG-JS].
4. If the conflict is in a single-statement assignment (e.g. both IDEAs reassigning the same variable): this is genuinely competing. Take branch B's value (later merge wins) and flag with [INTEGRATION-FLAG-JS-COMPETING].
5. Save; commit the resolution.
```

S11.8 (union tests) and S11.10 (review) catch most JS regressions; the `[INTEGRATION-FLAG-JS]` markers ensure flagged commits get human attention.

## Pattern 6 — Python source collisions (views, models, helpers)

**Conflict shape**: two IDEAs both edited the same function. Most dangerous category — semantic conflict possible without textual conflict.

**Algorithm — strict guard**:
```
1. Read both branches.
2. If the conflict is in non-overlapping import statements: include both, sort/dedup imports per `isort` if the project uses it.
3. If the conflict is in a function body where both branches added independent statements: cautiously include both, in the order they appear (branch A's first). Run the union tests after the merge (S11.8) and the full suite (S11.9) — if either fails, the resolution was wrong and the cap-of-10 attempts kick in.
4. If the conflict is in a function body where both branches modified the same statement: STOP. Auto-resolution is unsafe. Flag the resolution commit with [INTEGRATION-FLAG-PY-COMPETING], commit the file in conflicted state if the project's pre-commit hooks allow it (otherwise pick branch B and flag), and let S11.10's review pass + human reviewer decide. This case is rare in well-curated batches.
5. If the conflict involves a method signature change in one branch and a new caller in the other: branch A's signature wins (the change is intentional); the new caller must be updated to match. Flag with [INTEGRATION-FLAG-PY-SIGNATURE].
6. If conflict involves a model field migration (Django `migrations/`): treat as the most dangerous case. The two migrations may not commute. Run them in order, then `makemigrations --check` in S11.5's reset; if it complains, bail and flag with [INTEGRATION-FLAG-MIGRATION].
```

## Pattern 7 — Settings / config collisions

**Conflict shape**: two IDEAs both added entries to `INSTALLED_APPS`, `MIDDLEWARE`, settings dicts, env-var lists, etc.

**Algorithm — "concatenate both, preserve order"**:
```
1. Read both branches.
2. Concatenate entries: branch A's additions first, then branch B's.
3. Deduplicate by key (warn if duplicate values differ).
4. For ORDER-SENSITIVE lists (Django MIDDLEWARE, INSTALLED_APPS positions): preserve each branch's relative ordering of its own entries; insert branch B's entries after branch A's entries in the conflict region.
5. Save; commit the resolution.
```

## Pattern 8 — Tests collisions

**Conflict shape**: two IDEAs both added tests near each other (same test class, fixture, or factory).

**Algorithm — "include both"**:
```
1. Read both branches.
2. If conflict is in fixtures / factories (shared scope): include both factory definitions. Flag duplicate names ([INTEGRATION-FLAG-TEST-DUP]) — one IDEA's factory may shadow the other.
3. If conflict is in test classes (each IDEA added test methods): include both. The test runner picks them up.
4. If conflict is in shared test setup (`setUp`, `setUpTestData`): SAFEST is to keep the union of both setUps. If they assign to the same attribute, branch B wins (later merge); flag with [INTEGRATION-FLAG-TEST-SETUP].
5. Save; commit the resolution.
```

## When auto-resolution is genuinely unsafe — the abort path

If multiple `[INTEGRATION-FLAG-*]` markers accumulate (≥ 5 in a single sequential-merge step) OR a `[INTEGRATION-FLAG-PY-COMPETING]` / `[INTEGRATION-FLAG-MIGRATION]` surfaces:

1. Continue the merge sequence (don't abort entire batch over flags — flagged commits are still resolutions, just commented for review).
2. Surface the count + flag types in the auto-run log's Integration check section.
3. The morning reviewer sees the flag count up-front; high counts = "go look at this batch's conflict resolutions before merging anything."

If `git merge --abort` is genuinely needed (the agent cannot produce ANY plausible resolution): log the failure for that branch, skip the merge, continue with the next branch in the sequence. The skipped branch's per-PR PR doesn't get the integration's resolutions/wrap-batch via S11.11 forward-sync — it merges to main on its own merits, with the cosmetic devlog/index conflict still present. Sub-optimal but tractable. The auto-run log records `merge_results: [{ slug, outcome: failed, reason: <human-readable> }]`.

## Verification of the resolution commit

Each resolution commit on the integration branch should be re-read by the agent before moving to the next merge:

```
1. `git show <resolution-sha>` — does the diff make sense?
2. `git diff HEAD~1..HEAD -- <conflicted-file>` — are both contributions visibly preserved?
3. If suspicious, revert + re-attempt with the alternative pattern from this catalogue (e.g. if Pattern 4 "include both" produced bad HTML, try the "wrap in <div>" form).
```

This re-read is part of the merge step, not a separate phase.

## What's catalogued here vs. what stays project-specific

This catalogue is **project-agnostic**. Patterns 1–8 cover the structural conflict classes that arise from the parallel-IDEA workflow regardless of project specifics.

**Project-specific resolutions** (e.g. "in this project, when both IDEAs edit `chat.html`, prefer the layout from `auto/audio-playback-*` because its Alpine state is canonical") are NOT catalogued here. They live in:
- The project's own `tools/sprint-auto-hooks.sh` — specifically a new optional function `resolve_integration_conflict <file>` that the integration-stage bash machinery calls before falling back to this catalogue.
- A future per-project `docs/sprint-auto-conflict-overrides.md` if the project accumulates enough patterns to warrant one. Mind-vault doesn't ship a template for this; let it emerge organically from real batches.
