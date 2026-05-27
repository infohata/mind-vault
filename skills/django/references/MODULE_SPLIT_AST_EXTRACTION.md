# Splitting a large flat module into a package — AST byte-exact extraction

**Fires when** a single large module (`app/views.py`, `app/models.py`, a multi-kLOC
`app/views_<domain>.py`) needs to become a `views/` (or `models/`, `services/`) **package**
with per-domain submodules + an `__init__.py` that re-exports the public surface — and you
want the move to be reviewable as a *move*, not a rewrite, with **zero transcription risk**.

Hand-copying functions between files over thousands of lines is error-prone (a dropped
decorator, a mis-pasted body, a lost leading comment). Drive the extraction with Python's
`ast` so each symbol's source is sliced byte-exact from the original file. Pair it with a
blank-line-only formatter pass so the diff stays a clean move.

> **Python-general, not django-specific.** The split itself is stdlib `ast` + `autopep8` +
> `pyflakes` — nothing here knows about django. Only the verification step is framework-flavored:
> swap the `manage.py` import-graph check below for your framework's equivalent, or a plain
> `python -c "import app.x"` for a non-framework package.

## The recipe

1. **Parse + bucket by name.** `ast.parse` the source; walk top-level statements
   (`FunctionDef` / `AsyncFunctionDef` / `ClassDef` / `Assign` / `AnnAssign`). Bucket each by a
   name-prefix rule into target submodules (`article_*` / `_resolve_article_*` → `articles.py`, etc.).
   Include **`AnnAssign`** — annotated module-level constants (`FOO: tuple[str, ...] = (...)`) are
   `AnnAssign`, *not* `Assign`; miss them and step 3's lossless-coverage assertion flags their lines
   as uncovered (or they get silently dropped). The name is on `node.target` (a single node), not
   `node.targets` (the list `Assign` carries) — read the right attribute when bucketing.
   Symbols used by **more than one** bucket go to a neutral `helpers.py` — never let one
   domain submodule import from a sibling (keeps the dependency graph a star, not a mesh).

2. **Slice by line span — but extend for two things `ast` omits:**
   - **Leading comment blocks.** `node.lineno` starts at the `def`/assignment, *not* the
     `# ...` block above it. Walk backwards from the node, across one blank-line separator,
     over a contiguous `#` run, bounded by the previous consumed symbol's `end_lineno` so a
     comment is never double-claimed. Include the comment block in the symbol's span.
   - **PEP-224 attribute docstrings.** A bare string `Expr` immediately following an
     `Assign`/`AnnAssign` (`FOO = (...)` or `FOO: T = (...)`, then `"""docstring for FOO"""`) is a
     *separate* top-level node with no name — attach it to the preceding assignment's bucket.

3. **Verify coverage before writing.** Assert no two spans overlap, and that every non-blank
   source line outside the import header + module docstring is claimed by exactly one bucket.
   A zero-uncovered-non-blank result proves the split is lossless.

4. **Emit submodules.** Each = a fresh module docstring + the relevant import header +
   the concatenated symbol spans. **Join spans with two blank lines** — `ast` spans end at a
   function's last body line, so naive concatenation glues `return x` to the next `def`
   (PEP-8 E302). Either insert `\n\n` between spans, or fix it in step 6.

5. **Re-exporting `__init__.py`.** Import the public callables from each submodule (mirror the
   sibling packages' `__init__` style; add `__all__` so linters treat the re-exports as used,
   not dead). Cross-module **private** helpers that external callers import stay on the
   submodule path (`from app.views.api import _validate_x`), not the package surface.

6. **Blank-line normalization — formatter, not reflow.** Run `autopep8 --in-place
   --select=E301,E302,E303,E305,E306 <files>` (blank-line checks **only**). This fixes the
   glued-def spacing from step 4 without touching quotes, line length, or import order — so
   the diff still reads as a move. Do **not** run `black` / full `autopep8` (they reformat
   bodies and destroy the move-ness + `git log --follow` value).

7. **Trim imports.** Each submodule carrying the original file's full import header will have
   unused imports (sibling-domain render fns, etc.). Run `pyflakes` per submodule and delete
   the flagged lines. `pyflakes` is also the safety net for step 1: an **undefined name**
   means a real cross-bucket runtime dependency you missed — promote that symbol to
   `helpers.py` (or accept the cross-import deliberately).

## Sequencing — the forced-atomic member

The flat→package move is a [`RULE_rename-before-drop`](../../../docs/rules/RULE_rename-before-drop-rationale.md)
cycle, with one wrinkle the rule defers to here: **one member can't keep a drop-later shim.**

A module and a package can't share a dotted name — `app/x.py` and `app/x/__init__.py` are the
same import path, both can't exist. So when `app/x.py` becomes the package `app/x/`, the name
`x` is *forced atomic*: it must become the package in the very commit that creates it. There is
no flat-module shim to keep, because the flat module is gone.

The bridge is the package `__init__` itself, not a shim. `from app import x` and
`from app.x import Foo` resolve identically whether `x` is a module or a package whose `__init__`
re-exports `Foo` — so **no consumer of the colliding name needs editing, and there is nothing to
drop for it.** The re-export bridge is atomic, permanent, and invisible.

The *other* flat modules the package absorbs (`app/x_kb.py`, `app/x_orgs.py` → `app/x/kb.py`,
`app/x/orgs.py`) ride the normal rename-before-drop bridge: one-commit shims (`from app.x import *`
+ explicit re-export of any cross-module privates) so every old import path resolves at the green
gate, then dropped in the dedicated drop commit.

So a flat→package split has a **mixed bridge**: the colliding name on the permanent `__init__`
re-export, the rest on throwaway shims. One temporary exception — a cross-module *private* the
colliding module exposed to a test (`from app.x import _helper`) needs a temporary private
re-export in `__init__`; trim it in the same drop commit once the test is repointed to the
submodule path.

## Verification checklist

- `python -c "import app.views as v; print(all(hasattr(v, n) for n in (...)))"` — package
  public surface (run inside the framework context, e.g. `manage.py shell`, so app registry
  is configured; a bare `python -c` import of model-touching modules raises
  `ImproperlyConfigured`).
- `manage.py check` — the authoritative import-graph validation (loads every urlconf →
  imports every view). Green here means the package resolves in the real runtime.
- `grep -rn "from .sibling import" app/views/<domain>.py` returns nothing — no sibling-entity
  imports crept in (only `from .helpers import ...`).
- Full targeted test suite green at the bridge commit, the repoint commit, AND the drop commit.
- `git show --stat` on the move commit reads 1→1 renames where possible (`git mv` the
  single-target moves; a 1→N split is necessarily new-files + a shim, history is best-effort).
