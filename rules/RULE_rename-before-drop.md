# RULE_rename-before-drop

## The Hard Rule

For any refactor that **renames a field, function, or symbol** AND **eventually drops the old name**, sequence commits so renames land first, a full test pass confirms green, **then** the legacy symbol drops in its own commit, **then** re-test for regressions. Never bundle "drop legacy" with the rename when the rename touches more than one or two files.

## When This Applies

- Schema field collapses (multi-field → fewer fields).
- Function / class / method renames with many callers.
- Module-level constant renames (`OLD_FIELDS` → `NEW_FIELDS`) consumed by multiple modules.
- Data-model migrations where new + old shapes coexist for some commits.

Does **not** apply to: in-file local variable renames, pure logic-internal refactors, single-commit hotfixes.

## The Pattern

```text
1.   Add new schema / new symbol     ← old still present, no new callers yet
2.   Data-migrate / populate new     ← bridge state: old and new coexist
3-N. Rename references everywhere    ← every read path → new symbol
N+1. Full test pass                  ← green-light gate; missed refs surface here
N+2. Drop old symbol                 ← destructive moment, isolated commit
N+3. Re-run full test pass           ← regression check
N+4. Docs / housekeeping
```

Django specifically: the drop lives in a separate `0NNN_drop_legacy_*.py` migration — **not** appended to the AddField+RunPython migration. Deploy-time atomic (one `migrate` call), but split for review and dev-cycle test gating.

## Why This Matters

- **Bisectability.** Every intermediate commit compiles; `git bisect` works against post-merge regressions.
- **Test-pass between rename and drop is the safety gate.** Missed references surface as clean `AttributeError: 'X' object has no attribute 'old_name'` pointing exactly at the unswept site. Bundled with the drop, the same failure hides inside a multi-cause post-drop run. The canonical miss is a module-level `*_FIELDS` / `_COPY_*` constant in a file the surface-coverage matrix didn't enumerate — sequenced this way, 30+ tests fire on one cause; sequenced wrong, they hide in noise.
- **Post-drop re-test catches defensive fall-throughs.** Code shaped like `getattr(obj, 'old', default)` silently degrades when the old symbol vanishes — only the dedicated post-drop run forces it out.

## How To Apply

1. **Plan the commit sequence explicitly** in the plan doc's Execution Sequence section. Push back at architect review if the plan bundles rename + drop.
2. **Surface-coverage matrix audit.** Before rename commits, grep for `*_FIELDS`, `*_COLUMNS`, `_COPY_*`, `_TEXT_*` — any module-level list enumerating the old symbol.
3. **In-flight reorder is allowed.** The plan's narrative ordering is a presentation choice; reorder commits if /work reveals a better sequence. The migration's *internal* operation order stays canonical.
4. **One commit per logical step.** Don't pack "rename module A + drop legacy from module B" into one commit.
5. **Post-drop green is the merge gate.** If post-drop tests fail, fix-and-retest before merging.

## Two-PR Variant (Convention Migrations)

When the rename is a JS-level event-name / API-name convention rather than a schema field — e.g. many emit sites + many consumer modules — sequence as two PRs:

- **Phase 1 PR**: introduce the canonical helper; emit BOTH canonical AND legacy keys from every emit site (zero-risk overlap, legacy consumers unaffected); migrate consumers to the canonical signal. Phase 1 alone is functionally complete.
- **Phase 2 PR (later)**: drop legacy keys + remove legacy consumer listeners. Reversible if Phase 2 surfaces a regression.

The test-pass between phases is the safety gate that surfaces asymmetries (e.g. helper emitting on success path only, never on failure path — caught cleanly when isolated, hides inside a drop-bundled diff).

## Anti-Patterns

- ❌ Big-bang rename + drop in one commit — bisectability dies, regressions become undifferentiated noise.
- ❌ Drop first, then rename references — every intermediate commit is broken; tests can't run.
- ❌ Skip the post-drop re-test because the rename pass was green — defensive `getattr` fall-throughs hide here.
- ❌ Append the drop to the same Django migration as the data migration — couples data + schema steps in development; separate `0NNN_drop_legacy_*.py` is cleaner for review.

## Relationship To Other Rules

- [`RULE_git-safety`](RULE_git-safety.md) — every rename and drop commit lands on a feature branch; per-commit compilability makes `--force-with-lease` rebases safe inside the sequence.
- [`RULE_self-sweep-before-push`](RULE_self-sweep-before-push.md) — pyflakes after a rename catches leftover imports of the dropped symbol.

---

**Last Updated**: 2026-05-14
