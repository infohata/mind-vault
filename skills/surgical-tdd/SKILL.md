---
name: surgical-tdd
description: Debug failing tests quickly across any massive Python monolith by surgically specifying and running targeted test paths instead of running full, slow test suites locally.
---

# Surgical TDD (Test-Driven Development)

When working on mature projects (e.g. Django SaaS apps, multi-tenant monoliths) that contain over 2,000+ tests and take nearly an hour to run full regression, running the entire suite on every local iteration completely destroys the developer Flow State.

"Surgical TDD" enforces writing and executing tests in precise isolation before hitting the CI pipeline.

## The Core Principles

### 1. Never Run the Full Suite Locally
In large repositories, executing `make test` or `pytest` over the entire repository is explicitly forbidden during local feature development. The cloud CI/CD pipeline handles broad regression testing. Locally, you must only run tests matching the architectural boundaries you are actively touching.

### 2. Isolate with Fully Qualified Paths
When iterating, always provide the full, precise dotted path to the exact test function or class you are trying to bend.
- **Bad:** `make test args="teisutis_billing/tests/"`
- **Good:** `make test args="teisutis_billing.tests.test_models.BillingPlanTest.test_upgrade_pro_to_enterprise"`
By limiting execution down to a single method or class, your feedback loop goes from minutes to microseconds.

### 3. Verify Exact Names Before Assuming
Never guess what a test class or file is named. Use `grep-search` or equivalent structural searches before launching execution. 
- Example: Look up `ShortcutTest` vs `ShortcutsModuleTest`. Missing the correct execution string wastes container spin-up time and gives false "passed" impressions if nothing was selected.

### 4. Write Regression Probes First
If a feature is reported broken or an architectural bug is found (e.g. N+1 leak, timezone error), write the surgically-targeted regression test *first*. Run it via an explicit path, verify it fails, patch the codebase, and watch the exact test flip to green. 

### 5. Handle Schema State ("Fresh DB") Strategically
In multi-tenant schemas (like `django-tenants`), executing the same test repeatedly on a dirty database container can trigger cascading schema isolation errors between tests.
If your local test harness supports a fresh-db command (e.g., `make test-fresh`), use it specifically when testing changes that interact extensively with unique constraints, database state, or schema migrations.

### 6. Do Not Ignore "Unrelated" Failures
If you surgically execute an entire file (e.g. `auth.tests.test_views`) to verify your one targeted fix, and an ostensibly unrelated test within that same file fails, **do not dismiss it**. 
Either:
a) You broke a fundamental shared abstraction (like a base permission probe or a Model `.save()` override).
b) The test itself was brittle and dependent on previously dirty execution order state. 
You must halt, fix or document the cause.

## Execution Example (Django/Teisutis standard):
When writing or updating logic, execute tests via precise targeting argument injections:
```bash
make test-fresh ARGS="teisutis_ai.tests.ShortcutsModuleTest.test_summarizing_function"
```
