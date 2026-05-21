# RULE_rename-before-drop — Rationale, Variants, Anti-Patterns

## Why This Matters

- **Bisectability.** Every intermediate commit compiles; `git bisect` works against post-merge regressions.
- **Test-pass between rename and drop is the safety gate.** Missed references surface as clean `AttributeError: 'X' object has no attribute 'old_name'` pointing exactly at the unswept site. Bundled with the drop, the same failure hides inside a multi-cause post-drop run. The canonical miss is a module-level `*_FIELDS` / `_COPY_*` constant in a file the surface-coverage matrix didn't enumerate — sequenced this way, 30+ tests fire on one cause; sequenced wrong, they hide in noise.
- **Post-drop re-test catches defensive fall-throughs.** Code shaped like `getattr(obj, 'old', default)` silently degrades when the old symbol vanishes — only the dedicated post-drop run forces it out.

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

- [`RULE_git-safety`](../../rules/RULE_git-safety.md) — every rename and drop commit lands on a feature branch; per-commit compilability makes `--force-with-lease` rebases safe inside the sequence.
- [`RULE_self-sweep-before-push`](../../rules/RULE_self-sweep-before-push.md) — pyflakes after a rename catches leftover imports of the dropped symbol.
