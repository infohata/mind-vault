# Linting Django split-settings — pyflakes false-positives + the noqa gap

The canonical Django split-settings pattern uses wildcard imports from `base.py` so dev/prod/test overrides inherit every setting without manual maintenance:

```python
# settings/dev.py
from .base import *  # noqa: F401,F403

DEBUG = True
ALLOWED_HOSTS = ["*"]
```

Pyflakes flags both lines:

```
settings/dev.py:1:1: 'from .base import *' used; unable to detect undefined names
settings/dev.py:1:1: '.base.*' imported but unused
```

The `# noqa` comment **does not help** — pyflakes deliberately ignores noqa directives (that's a flake8/ruff feature, not a pyflakes one). Anyone running pyflakes as a pre-push self-sweep (per `RULE_self-sweep-before-push`) gets a false positive on every override file.

## Why pyflakes gets it wrong

Pyflakes does static analysis without import resolution: it sees `from .base import *` and can't know which names come in. It flags every import-bound name as both "possibly undefined" (in the consumer file) and "unused" (because nothing in the override file references a `base.*` name explicitly). The pattern is correct — Django explicitly recommends split-settings with wildcard inheritance — but pyflakes is the wrong tool to verify it.

## Three options for resolving

### Option 1 — Exclude the override files from the lint target (lowest friction)

Scope the lint target to skip `settings/dev.py` and `settings/prod.py` (and any sibling overrides like `test.py`, `staging.py`). `base.py` and `__init__.py` stay in scope.

```make
# Makefile
lint:
	docker compose exec -T web sh -c 'find tasker apps -name "*.py" \
		-not -path "tasker/settings/dev.py" \
		-not -path "tasker/settings/prod.py" \
		-print0 | xargs -0 python -m pyflakes'
```

**Trade-off**: dev.py / prod.py are no longer linted at all, so genuine dead imports in those files (e.g. an `import os` that's only used in a now-deleted block) won't be caught. The override files are typically short enough that this is acceptable.

### Option 2 — Switch from pyflakes to flake8 or ruff (clean, slightly more setup)

Both `flake8` and `ruff check` honour `# noqa: F401,F403` directives. Replace `pyflakes` in `requirements-dev.in` with `flake8` (or `ruff`), update the Makefile target, and the wildcard import pattern lints clean without scope hacks.

```make
lint:
	docker compose exec -T web ruff check tasker apps
```

**Trade-off**: ruff brings opinions about more than just unused-imports (line length, naming, etc.). A `pyproject.toml [tool.ruff]` block needs an explicit ruleset, or contributors will trip over unfamiliar warnings. For a project that *only* wants the unused-import sweep, this is overkill.

### Option 3 — Refactor settings to explicit imports (purest, highest cost)

Replace `from .base import *` with explicit imports of every override target:

```python
from .base import BASE_DIR, INSTALLED_APPS, MIDDLEWARE, ROOT_URLCONF  # etc.
DEBUG = True
ALLOWED_HOSTS = ["*"]
```

**Trade-off**: tight coupling — adding a new setting to `base.py` no longer auto-propagates to overrides. Every new setting in `base.py` is an N-file change for N override modules. Defeats the point of split settings.

## Recommendation

**Option 1** for bootstraps and small projects: it's a one-line Makefile change with a clear comment explaining the trade-off.

**Option 2** when the project already uses flake8 or ruff for other purposes, or when the override files are large enough that "no linting at all" is a real cost.

Never **Option 3** — it defeats the inheritance pattern.

## Pattern for the bootstrap

When scaffolding a Django project with split settings + a pyflakes-based self-sweep:

1. Land the lint target with explicit exclusion of the override files.
2. Add a comment in the Makefile explaining *why* the exclusion exists (so a future maintainer doesn't "fix" it by removing the exclusion).
3. Document the pattern in the project's `CLAUDE.md` so AI agents know the linting boundary.

## Related rules / skills

- `rules/RULE_self-sweep-before-push.md` — the pyflakes-as-self-sweep convention; this reference is its Django-domain caveat.
- `skills/django/SKILL.md` — the split-settings convention this reference applies to.

---

**Last Updated**: 2026-05-19 — promoted from `tasker` IDEA-001 bootstrap. The false positive surfaced when running `make lint` on a fresh stack with the canonical split-settings layout. See `tasker/docs/archive/2026-05-DEVELOPMENT_LOG.md` for the precedent commit (`fix(make): exclude split-settings overrides from pyflakes target`).
