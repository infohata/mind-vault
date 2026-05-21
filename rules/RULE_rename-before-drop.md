# RULE_rename-before-drop

For any refactor that **renames a field, function, or symbol** AND **eventually drops the old name**, sequence commits so renames land first, a full test pass confirms green, **then** the legacy symbol drops in its own commit, **then** re-test for regressions. Never bundle "drop legacy" with the rename when the rename touches more than one or two files.

Why-this-matters (bisectability, post-drop fall-through detection), anti-patterns, and the JS two-PR convention variant live in [`references/RULE_rename-before-drop-rationale.md`](references/RULE_rename-before-drop-rationale.md).

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

## How To Apply

1. **Plan the commit sequence explicitly** in the plan doc's Execution Sequence section. Push back at architect review if the plan bundles rename + drop.
2. **Surface-coverage matrix audit.** Before rename commits, grep for `*_FIELDS`, `*_COLUMNS`, `_COPY_*`, `_TEXT_*` — any module-level list enumerating the old symbol.
3. **In-flight reorder is allowed.** The plan's narrative ordering is a presentation choice; reorder commits if /work reveals a better sequence. The migration's *internal* operation order stays canonical.
4. **One commit per logical step.** Don't pack "rename module A + drop legacy from module B" into one commit.
5. **Post-drop green is the merge gate.** If post-drop tests fail, fix-and-retest before merging.
