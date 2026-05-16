---
name: surgical-tdd
description: Debug failing tests quickly in any massive Python monolith by running fully-qualified test paths (pytest nodeids, Django dotted paths) instead of the full slow suite, and pairing surgical execution with regression-probe-first workflow.
---

# surgical-tdd

Targeted test execution for repos where a full suite takes 10+ minutes. Iterate with pinpoint tests while editing the code; let CI handle broad regression. Pairs with the regression-probe workflow: write the test first, watch it fail in isolation, watch it flip green when the fix lands.

Not a strict TDD framework — the "TDD" in the name refers to the red-green probe loop for reported bugs, not a write-test-first-for-all-code discipline.

## When to use

**TRIGGER when:** Python monolith with 500+ tests; local full-suite runs >2 min; debugging a specific failure or implementing a feature that touches a narrow surface; writing a regression probe for a reported bug.

**SKIP for:** small repos where the full suite is \<30 s (no time saved); first-contribution exploration of an unfamiliar test layout (broader runs teach you the shape); flaky-test triage (surgical runs hide intermittent failures that only appear under parallel contention).

## Pattern

### 1. Verify the exact target before running

Never guess a test name from memory. Grep the source first:

```bash
rg "class ShortcutTest\b" path/to/app/tests/
rg "def test_upgrade_pro_to_enterprise\b"
```

If the target doesn't match anything, the runner happily reports `0 tests collected` as a success — silent false green.

✅ DO: Confirm exact class + method name with `rg` (or `grep -rn`) before running.
❌ DON'T: Type a test path from memory; a typo passes silently and wastes container spin-up.

### 2. Run with a fully-qualified target, not a directory

The finer the scope, the tighter the feedback loop.

**Django test runner:**

```bash
make test ARGS="billing.tests.test_models.BillingPlanTest.test_upgrade_pro_to_enterprise"
# or without a Makefile:
python manage.py test billing.tests.test_models.BillingPlanTest.test_upgrade_pro_to_enterprise
```

**Plain pytest (nodeid or keyword):**

```bash
pytest path/to/app/tests/test_models.py::BillingPlanTest::test_upgrade_pro_to_enterprise
pytest -k "upgrade_pro_to_enterprise"
```

Container spin-up dominates when scope is narrow. Running the whole file when you want one method throws away most of the win.

✅ DO: Pass a fully-qualified dotted path or nodeid (`app.tests.module.Class.method` or `path::Class::method`).
❌ DON'T: Pass a directory, module, or class when you can name the exact method.

### 3. Regression probes first (test-first for reported bugs)

When a bug is reported or an architectural issue surfaces (N+1 leak, timezone error, permission hole):

1. Write a test that reproduces the bug.
2. Run it in isolation — **verify it fails**.
3. Fix the code.
4. Rerun the same test — watch it flip green.

Only then consider broader exercise. A probe that doesn't fail before the fix is worthless — you haven't actually characterised the bug, and you have no evidence the fix addresses it.

✅ DO: Confirm the probe fails *before* touching the fix.
❌ DON'T: Write probe + fix together, run once, assume both work.

### 4. Complementary pytest levers

Useful alongside fully-qualified paths when pytest is the runner:

| Flag                  | Use for                                                                               |
| --------------------- | ------------------------------------------------------------------------------------- |
| `-x`                  | Stop at first failure — avoid reading 30 stack traces when the root cause is obvious. |
| `--lf`                | Last-failed — rerun only what failed last run. Cheap iteration while debugging.       |
| `--ff`                | Failed-first — run prior failures before the rest (broader scope, fast feedback).     |
| `-k "expr"`           | Keyword-select — substring match over nodeids when you can't recall the full path.    |
| `-n auto`             | pytest-xdist parallel across cores — for the *rare* broader run.                      |
| `-n 8 --dist loadscope` | Physical-core parallel + class-scoped distribution for TenantTestCase suites.       |
| `-s`                  | No capture — see `print()` / logging output while iterating.                          |
| `-p no:cacheprovider` | Disable cache — when debugging test-selection issues or running in CI.                |

**Multi-tenant suites with schema pooling**: projects with django-tenants + an env-gated pool fixture (e.g. `<PROJECT>_POOLING=1`) can stack a pool fixture on top of xdist for another ~15-20% wall-clock reduction — but pool mode is for full-suite runs, not surgical iteration. When a surgical run fails only under pooling, the test is exposing latent fragility (see `django/references/TESTING.md` "Parallel Execution" section for debugging flow).

### 5. Handle schema / DB state strategically

Repeated runs against a dirty database can trigger cascading isolation errors that look like real failures but are fixture residue. Use the project's fresh-DB command when touching:

- Unique constraints
- Schema migrations
- Tenant bootstrap (in multi-tenant projects)

**pytest-django:** `pytest --create-db` (force recreate) or `--reuse-db` (default, faster).

> *Example (django-tenants):* the Makefile exposes `make test-fresh ARGS="..."` which drops and recreates the tenant schema before running. Use it when tests interact with unique constraints or schema shape.

### 6. Don't dismiss "unrelated" failures

If you surgically run a single file (e.g. `auth.tests.test_views`) to verify one fix, and an *ostensibly unrelated* test in that same file fails, one of two things is true:

- **(a) You broke a shared abstraction** — base `Permission` class, `Model.save()` override, signal handler, middleware.
- **(b) The test was brittle** — order-dependent, global-state-dependent, or leaking a fixture.

Either way: halt. Investigate. Either fix the shared abstraction or document the flakiness in the tracker. Dismissing "probably unrelated" failures as noise is how bugs ship.

## When NOT to use these patterns

- **Small repo** where the full suite runs in \<30 s — no iteration-speed benefit.
- **First-contribution exploration** — you don't yet know which test names to target; run broader to learn the layout.
- **Flaky-test triage** — use `pytest-repeat` (`--count=50`) or parallel runs (`-n auto`) to surface the intermittency; surgical single-runs hide it.
- **Coverage measurement** — cumulative coverage needs broader scope; don't try to stitch surgical runs together.

### When to escalate to broader scope

Even with surgical-TDD as the default, zoom out for:

- Touching a mixin, abstract base class, `save()` override, middleware, or signal handler.
- Changing a permission class or authentication hook.
- After a migration or model-field change.
- **Before pushing** — run at least the app-level test file (not the whole suite, but broader than one method). CI is the net for whole-suite regression; don't reimplement it locally, but don't expect it to catch shared-abstraction fallout that a 10-second app-level run would have.

## End-to-end example

> *Illustrative (Django + django-tenants):*

```bash
# Bug reported: billing upgrade fails on org with annual plan.

# 1. Locate likely test surface
rg -n "upgrade.*plan" web/billing/tests/

# 2. Write a probe in test_models.py:
#    class BillingPlanTest(TenantTestCase):
#        def test_upgrade_annual_plan_preserves_remaining_period(self):
#            ...reproduce the bug...

# 3. Run the probe — must fail
make test-fresh ARGS="billing.tests.test_models.BillingPlanTest.test_upgrade_annual_plan_preserves_remaining_period"

# 4. Fix the offending logic in billing/services.py

# 5. Rerun — same command — now green
make test-fresh ARGS="billing.tests.test_models.BillingPlanTest.test_upgrade_annual_plan_preserves_remaining_period"

# 6. Before pushing: run the whole app file, not just the one test
make test ARGS="billing.tests.test_models"
```

## References

- [pytest — test selection](https://docs.pytest.org/en/stable/how-to/usage.html)
- [pytest-django](https://pytest-django.readthedocs.io/)
- [pytest-xdist](https://pytest-xdist.readthedocs.io/) — parallel runs for the rare broader scope
- [Django test runner](https://docs.djangoproject.com/en/stable/topics/testing/tools/)
- [skill-writer](../skill-writer/SKILL.md) — the conventions this skill follows
- [django skill](../django/SKILL.md) — Django-specific testing patterns

**Last Updated**: 2026-04-17
