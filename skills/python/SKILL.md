---
name: python
description: Base Python-language layer beneath the framework skills — AST byte-exact flat-module→package splits and env-driven frozenset allowlists. Language-general recipes, framework or not.
---

# python

The vault's **base Python-language layer** — the deliberate home for engineering
patterns that are true of *any* Python project, framework or not. It sits
**beneath** the framework-stack skills (`django`, `django-frontend`, and future
`fastapi`/`flask`/etc.): those skills own framework concepts (ORM, request
lifecycle, background jobs, templating); this skill owns language-general
mechanics that would otherwise misfile into whichever framework skill happened
to need them first. New Python-general patterns land here — not under a
framework skill by gravity. Framework skills point *down* into this layer's
references rather than copying the recipes.

## When to use

**TRIGGER when:** working a Python task whose mechanics are language-general — restructuring a large flat module into a package, parsing per-deployment config into immutable in-memory lookups, and similar stdlib-level engineering — **and** the recipe doesn't depend on a specific framework's runtime.

**SKIP when:** the task is framework-specific — defer to the repo's active **framework-stack skill** (`django` / `django-frontend` today; `laravel` and others once IDEA-014's stack detection lands). `python` is the broadest false-positive surface in the vault (almost everything touches a `.py` file); it must NOT fire on, or double-load alongside, a framework task. When framework context is present, the framework skill leads and reaches *down* into these references as needed — `python` does not also activate.

## Pattern

### 1. Splitting a flat module into a package

**Fires when** a single large module (`views.py`, `models.py`, a multi-kLOC
domain module) needs to become a package with per-domain submodules + a
re-exporting `__init__.py`, and you want the move reviewable as a *move* (zero
transcription risk), not a rewrite.

The shape: drive the extraction with Python's `ast` so each symbol is sliced
byte-exact from the original; bucket by name-prefix into submodules; assert
lossless line-coverage before writing; blank-line-only `autopep8` + `pyflakes`
import-trim so the diff stays a clean move. It also owns the
[`RULE_rename-before-drop`](../../rules/RULE_rename-before-drop.md)
*forced-atomic-member* wrinkle (a module and a package can't share a dotted
name). Full recipe, AST-omission edge cases, and the mixed-bridge sequencing are
in [`references/MODULE_SPLIT_AST_EXTRACTION.md`](references/MODULE_SPLIT_AST_EXTRACTION.md).

### 2. Config & environment parsing

**Fires when** you need a list (blocked MIME types, blocked extensions, IP
allowlists, feature flags) that wants three properties at once: per-deployment
override without a code change, O(1) membership lookup at hot paths, and
immutability so request handlers can't mutate global state.

The shape: a `frozenset` parsed from a comma-separated env var with a sane
default literal in code — replace-not-extend semantics, normalise-on-parse,
`filter(None, ...)` for trailing commas, `frozenset` not `set` so `.add()`
raises. Full pattern, the five earn-their-keep notes, and when-not-to-use
(small-cardinality / per-tenant cases) are in
[`references/ENV_DRIVEN_ALLOWLISTS.md`](references/ENV_DRIVEN_ALLOWLISTS.md).

## References

- [references/MODULE_SPLIT_AST_EXTRACTION.md](references/MODULE_SPLIT_AST_EXTRACTION.md) — byte-exact `ast`-driven flat-module → package split (bucket-by-prefix, leading-comment + PEP-224 attr-docstring capture, lossless-coverage assertion, blank-line-only `autopep8`, `pyflakes` import trim); owns the `RULE_rename-before-drop` forced-atomic-member sequencing.
- [references/ENV_DRIVEN_ALLOWLISTS.md](references/ENV_DRIVEN_ALLOWLISTS.md) — env-driven allowlists/denylists as `frozenset` (env override + O(1) hot-path + immutable global), replace-not-extend env semantics, extensionless-filename guard.
- [references/STRUCTURED_ERROR_DETECTION.md](references/STRUCTURED_ERROR_DETECTION.md) — classify a caught client-library exception on its structured error body (`err.body` root-cause type/reason), never the rendered message string; two narrowing layers (exception class + body predicate) so only the one precise upstream failure is skipped and everything else propagates; tests must construct the synthetic exception WITH a real `body` dict (a bare-message exception leaves the structured path unexercised).
- [references/MOCK_PATCH_STACK_LEAK.md](references/MOCK_PATCH_STACK_LEAK.md) — same mock.patch target patched at two test layers with mixed stop disciplines (base tearDown + subclass addCleanup) inverts the stack unwind and re-installs the base's Mock onto the process global — poisoning every later test on the xdist worker; rules (never re-patch what the base patches; one target/one layer/one discipline; addCleanup immediately after start) + the heal-and-attribute autouse canary that names every leaker in one diagnostic run + the full-suite-deterministic/isolated-green tell.
