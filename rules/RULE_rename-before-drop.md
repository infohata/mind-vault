# RULE_rename-before-drop

## The Hard Rule

For any refactor that **renames a field, function, or symbol** AND **eventually drops the old name**, sequence the commit history so renames land first, full test pass confirms, **then** the legacy symbol drops, **then** re-test for regressions. Never bundle "drop legacy" with the rename in a single commit if the rename touches more than one or two files.

## When This Applies

- Schema field collapses (`problem_goal + context + steps_procedure + results_notes` → `contents + notes` — the canonical case).
- Function / class renames where the old name is callable from many sites.
- Module-level constant renames (`OLD_FIELDS = [...]` → `NEW_FIELDS = [...]`) consumed by multiple modules.
- Data-model migrations where the new shape coexists with the old for some commits.

Does **not** apply to:

- Simple in-file local variable renames.
- Refactors with no name change (pure logic-internal).
- Hotfixes that need to ship in one commit.

## The Pattern

Phased commit sequence within a single PR:

```text
1. Add new schema / new symbol      ← old still present, no callers reference new yet
2. Data-migrate / populate new      ← bridge state: both old and new exist with matching content
3-N. Rename references everywhere   ← every read path → new symbol; old becomes unreferenced
                                        … run tests after each commit; intermediate states compile
N+1. Run full test pass              ← green-light gate; if anything still references old, it surfaces here
N+2. Drop old symbol                 ← the destructive moment, isolated in its own commit
N+3. Re-run full test pass           ← regression check; green = refactor verified
N+4. Docs / housekeeping             ← devlog, rule updates, etc.
```

For Django schema collapses specifically, "Drop old symbol" is a separate `0NNN_drop_legacy_*.py` migration file — **not** appended to the same migration as `AddField + RunPython`. Atomic at deploy time (Django runs both in one `migrate` call), but split for development experience: the data-migration step gets verified against rows still holding old values; the drop step is reviewed in isolation.

## Why This Matters

### Per-commit compilability + bisectability

Every intermediate commit leaves the codebase compilable. `git bisect` works. If a regression surfaces post-merge, you can isolate the bad commit instead of staring at a 30-file diff.

### Test-pass between rename and drop is the actual safety gate

If you drop the old symbol AND rename references in one commit, the only test signal is "everything builds with the new shape." That doesn't tell you which references were missed. The dedicated test-pass between rename and drop is the moment where missed references surface as `AttributeError: 'X' object has no attribute 'old_name'` — pointing exactly at the file and line that wasn't swept.

The teisutis IDEA-127 audit scope was wide (forms, views, serializers, signals, templates, JS, AI prompts — 8+ files), but the surface coverage matrix missed `web/teisutis_kb/recurrence.py:_COPY_FIELDS` because that module wasn't enumerated. Sequenced this rule's way, the recurrence.py-driven failures (36 tests) surfaced cleanly during the rename-only test pass; sequenced the wrong way, they would have hidden inside a 40-failure post-drop run that mixed rename omissions with genuine drop bugs.

### Re-test after drop is the final regression catch

Some failures appear ONLY after the legacy symbol is gone — code that defensively `getattr(obj, 'old', default)` will silently fall back, hiding regressions until production. The post-drop re-test forces these out.

## How To Apply

1. **Plan the commit sequence explicitly in the plan doc.** Section in the execution sequence: "Commit ordering — rename first, drop last, test between." If the plan bundles them, push back during architect review.
2. **Surface coverage matrix audit.** Before starting renames, grep for `*_FIELDS`, `*_COLUMNS`, `_COPY_*`, `_TEXT_*`, any module-level lists that enumerate the old symbol. Listed in the plan, audited in /work.
3. **In-flight reorder is allowed.** If during /work the planned sequence reveals a problem, reorder commits — the plan's narrative ordering is a presentation choice, not a contract. The migration file's *internal* operation order (e.g. AddField → RunPython → RemoveField) stays canonical regardless of which commit each operation lands in.
4. **One commit per logical step.** Don't pack "rename module A + drop legacy from module B" into one commit just because they're related.
5. **Final test pass on green** is the merge gate. If post-drop tests fail, fix-and-retest before merging — don't push the destructive moment to main with red tests.

## Worked Example: teisutis IDEA-127 (2026-04-25)

`Article` and `Event` models had four legacy `TextField` content slots collapsed into two markdown fields. Initial plan: `AddField → RunPython → RemoveField` as Commits 1+2+3 (per the migration's internal canonical order). User direction during planning:

> "Reorder, drop legacy fields after all code is re-implemented and tests passing. That's a good compound for refactoring runs. Then after dropping re-test for regressions. I think that's best possible outcome approach."

Execution adapted: Commits 1+2 (AddField + RunPython) → Commits 4-13 (rename references across forms / admin / serializers / signals / views / templates / JS / iCal / AI app) → Commit 14 (translations) → Commit 15 (test fixture sweep, full kb pass green at 90/90) → Commit 3 (deferred — `0037_drop_legacy_content_fields.py` RemoveField × 4) → re-test (508 passed, 0 IDEA-127 failures). The Commit-15 test pass surfaced one missed reference at `web/teisutis_kb/recurrence.py:_COPY_FIELDS` cleanly via 36 `AttributeError` tests; one-line fix unblocked the cluster. Bundled, that finding would have been a needle inside a haystack of post-drop noise.

## Worked Example: teisutis IDEA-163 (2026-05-14) — 15-emit-site convention migration

Same rule applied to a JS-level convention rename rather than a schema collapse: per-entity HX-Trigger names (`articleSaved`, `eventSaved`, `articleDeleted`, `eventDeleted`, etc.) → one canonical `entityChanged` event with `{type, id, action}` payload. 15 server emit sites + 8 client consumer modules + several Django views.

Sequenced as a two-PR migration to keep deploy windows safe:

- **Phase 1 PR (#443)**: introduce canonical `entity_changed()` helper in `web/teisutis_core/htmx_triggers.py`; emit BOTH canonical AND legacy per-name keys from each of the 15 server sites (zero-risk overlap — legacy consumers unaffected); add the walker module that subscribes to `entityChanged` and routes the refresh; per-entity capture-phase modules slim down to entity-specific cosmetics only.
- **Phase 2 PR (future)**: drop legacy per-name HX-Trigger keys from emit sites; remove per-name consumer listeners that the walker now subsumes. Cleanly reversible if Phase 2 surfaces a regression — Phase 1 alone is functionally complete.

The Phase 1 PR carried all 15 emit-site changes alongside the helper, the walker, and the entity-specific cosmetics — one bisectable commit cluster per surface (server emit changes + matching client-side refactor in adjacent commits). Bugbot caught the modal-scoping mismatch (`form_invalid` returning 200 still triggered modal close) cleanly because the helper emitted the canonical signal only on form_valid, never on form_invalid — the test pass between phases was the gate that surfaced the asymmetry. Bundled with a Phase-2 drop, the validation-failure regression would have hidden inside the broader drop-related test churn.

## Anti-Patterns

- ❌ "Big-bang rename + drop in one commit" — bisectability dies, regressions surface as undifferentiated noise.
- ❌ "Drop first, then rename references" — every commit between drop and full-rename is broken; can't run any tests.
- ❌ "Skip the post-drop re-test because the rename pass was green" — defensive `getattr(obj, 'old', default)` + similar fall-throughs hide here.
- ❌ "Append the drop to the same migration as the data migration" (Django specifically) — couples the data step to the schema step in development; separate `0NNN_drop_legacy_*.py` migration is cleaner for review and test cycles. The deploy-time atomicity argument is correct but applies post-merge; pre-merge the split is cheaper.

## Relationship To Other Rules

- [`RULE_git-safety`](RULE_git-safety.md) — every rename and drop commit lands on a feature branch; per-commit-compilability makes `--force-with-lease` rebases safe inside the rename sequence.
- [`RULE_ideas-location-status`](../skills/idea/references/IDEAS_LOCATION_STATUS.md) — IDEA file's archive dir holds the plan doc that captures the commit sequence as part of the Execution Sequence section.

---

**Last Updated**: 2026-05-14
