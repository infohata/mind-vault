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

## Forced-atomic member: module → package collision (flat → package refactor)

When the refactor splits a flat module into a package — `app/x.py` becomes `app/x/` (dir +
`__init__.py` + submodules) — one member of the rename can't follow the normal "keep a shim,
drop later" bridge, because **a module and a package can't share the same dotted name**
(`app/x.py` and `app/x/__init__.py` are the same import path; both can't exist). That single
name is *forced atomic* — it must become the package in the very commit that creates it.

The resolution: that name's consumers are bridged **transparently by the package `__init__`**,
not by a shim. `from app import x` / `from app.x import Foo` resolve identically whether `x`
is a module or a package whose `__init__` re-exports `Foo` — so **no consumer of the colliding
name needs editing, and there is no shim to drop for it.** Sequence the *other* flat modules
the package absorbs (`app/x_kb.py`, `app/x_orgs.py` → `app/x/kb.py`, `app/x/orgs.py`) the
normal way: leave them as one-commit shims (`from app.x import *` + explicit re-export of any
cross-module privates) so every old import path resolves at the green gate, then drop the
shims in the dedicated drop commit.

So a flat→package split has a **mixed bridge**: the colliding name rides the `__init__`
re-export (atomic, permanent, invisible), the rest ride throwaway shims (rename-before-drop
proper). Keep a *temporary* private re-export in `__init__` for any cross-module private the
colliding module exposed to a test (`from app.x import _helper`), and trim it in the same drop
commit once that consumer is repointed to the submodule path. Mechanics of the byte-exact split
itself: [`skills/django/references/MODULE_SPLIT_AST_EXTRACTION.md`](../../skills/django/references/MODULE_SPLIT_AST_EXTRACTION.md).

## Anti-Patterns

- ❌ Big-bang rename + drop in one commit — bisectability dies, regressions become undifferentiated noise.
- ❌ Drop first, then rename references — every intermediate commit is broken; tests can't run.
- ❌ Skip the post-drop re-test because the rename pass was green — defensive `getattr` fall-throughs hide here.
- ❌ Append the drop to the same Django migration as the data migration — couples data + schema steps in development; separate `0NNN_drop_legacy_*.py` is cleaner for review.

## Relationship To Other Rules

- [`RULE_git-safety`](../../rules/RULE_git-safety.md) — every rename and drop commit lands on a feature branch; per-commit compilability makes `--force-with-lease` rebases safe inside the sequence.
- [`RULE_self-sweep-before-push`](../../rules/RULE_self-sweep-before-push.md) — pyflakes after a rename catches leftover imports of the dropped symbol.
