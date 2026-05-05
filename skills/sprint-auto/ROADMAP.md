# Sprint-auto roadmap — browser-test automation (Direction 1)

**Status**: design plan, not yet implemented. Direction 2 (`auto_safe_with_eval_gate` mode) shipped first; this is the planned uplift that shrinks Direction 2's manual-walk surface.

**Date opened**: 2026-05-05

## Why this exists

`auto_safe_with_eval_gate` (Direction 2) unblocks UX-overhaul / a11y-heavy IDEAs from sprint-auto by emitting a per-IDEA manual-evaluation checklist that the human walks at integration-PR-merge time. Cheap to build, cheap to run, but every IDEA still costs reviewer time per merge gate. As the cohort grows, this cost grows linearly.

Direction 1 — Playwright-driven browser automation in the dev image — *shrinks* the manual-walk surface by automating what *can* be automated: visual regression, focus traps, keyboard navigation, z-index hit-testing, animation timing, axe-core a11y rule checks, HTMX swap assertions, Alpine state snapshots. The residue left for the eval-checklist becomes the genuinely-HITL stuff: screen-reader experience, mobile gesture nuance, "does this feel right" — items where automation is technically possible but the value-per-effort is poor.

Composability with Direction 2 is the point: per-surface Playwright tests land alongside that surface's IDEA, and the IDEA's eval-checklist correspondingly drops the now-automated rows. Eval-gate doesn't disappear; it adapts surface-by-surface.

## What headless Playwright covers

**Yes (build first):**
- Visual regression — `expect(page).to_have_screenshot('name.png')` against committed baselines.
- a11y rule checks — `@axe-core/playwright` or the Python wrapper; catches WCAG-mappable issues (contrast, ARIA roles, label associations, heading order).
- Keyboard navigation — `page.keyboard.press('Tab')`, assert `:focus` on expected element. Catches focus-trap regressions, skip-link breakage, tabindex drift.
- Z-index hit-testing — `page.locator('button').click()` natively fails when a higher-stacked element intercepts. Free regression test for layering bugs.
- HTMX swap assertions — wait for `hx-target` to mutate, assert resulting DOM. Replaces "click button, hope HTMX swaps correctly" with deterministic checks.
- Alpine state — read `page.evaluate(() => window.Alpine.$data(el).someFlag)` from a known DOM node. Catches `x-data` desync, `x-show` regressions.
- Animation timing — `page.wait_for_function(() => getComputedStyle(...).opacity === '1', timeout=2000)`. Catches stuck-mid-transition bugs.

**No (out of scope, stays HITL):**
- Screen-reader *experience* — axe-core checks the markup; only NVDA/VoiceOver verifies the read-out makes sense.
- Mobile gesture nuance — swipe-to-dismiss feel, pull-to-refresh momentum, touch-target ergonomics under glove/wet finger.
- Subjective polish — easing curves, micro-interaction copy, brand voice in tooltips.

## Approach — headless, in-container, no X11

Playwright runs headless on Linux containers with no display server. Microsoft ships official Docker images preloaded with Chromium + Firefox + WebKit (`mcr.microsoft.com/playwright:v<X>-jammy`). Two integration options per project — pick the lighter one that fits:

1. **Pip-install into existing `web` image** — simplest when the project already has a Python `web` service. Adds `playwright` + `pytest-playwright` + `axe-core-python` to `requirements-dev.txt`, `playwright install` in the Makefile target. No new docker service.
2. **Separate `playwright` service** — when the `web` image is intentionally minimal (production parity is tight) or build-time matters. Pulls the official MS image; bind-mounts source + test results.

Option 1 is the default unless the project explicitly objects.

## Stack notes — Cotton + Alpine + HTMX (no TypeScript)

The first user (teisutis) ships server-rendered Django Cotton components with Alpine.js for client state and HTMX for partial swaps. No TypeScript. So:

- Tests are **Python** (`pytest-playwright`), not TS — keeps the dev surface uniform with the rest of the project's tests.
- `page.evaluate('() => window.Alpine.$data(el).flag')` is the Alpine-state probe; pair with `await page.wait_for_function('window.Alpine')` after each navigation since Alpine boots after DOM ready.
- HTMX swaps fire `htmx:afterSettle`; tests `await page.wait_for_function("document.body.classList.contains('htmx-settled')")` *(or a project-local marker hook)* between trigger and assertion. Without this, race conditions pop up where the assertion runs before the swap completes.
- Cotton components render server-side, so visual baselines reflect the rendered HTML — no client-only-rendered components to worry about. Baselines are stable across deploys.
- Pair with `RULE_parallel-worktree-docker`'s container-image discipline: visual baselines must be captured in the same image they assert against (font rendering varies by Linux distro). Baselines committed to repo; CI re-captures on `--update-snapshots` only behind explicit user direction.

For projects with different stacks (React/Vue, TS), the same headless Playwright approach applies — only the test language and the framework-state probes change.

## Composability with Direction 2 (eval-gate)

Per-surface Playwright tests land alongside that surface's IDEA. The IDEA's `auto_safe_with_eval_gate: true` flag stays set; the eval-checklist that S5 emits is correspondingly trimmed:

- Plan author writes the IDEA's eval-checklist scenarios.
- For each scenario the Playwright suite covers, the scenario row in the manual-evaluation template gets pre-filled with `**Walked**: [x] (covered by `tests/playwright/test_<surface>.py::test_<scenario>`)`.
- The remaining un-covered scenarios are what the integration-PR reviewer actually walks.

Over time, well-tested surfaces shrink toward "no manual walk needed"; new surfaces start with most of their checklist still manual. The eval-gate stays the safety net while automation catches up surface-by-surface.

## Sprint-auto integration

Two natural touch points (both already exist, neither needs new state machinery):

- **S2 verification** (`/work` runs targeted tests against the integration worktree). Add Playwright tests to the project's targeted-test paths. Sprint-auto's existing routing handles them as another pytest invocation.
- **S11.8 union-of-target-tests** + **S11.9 full-suite** (integration-state validation). Playwright tests run as part of the suite — same `cap_exceeded` discipline as any other test.

The dev image needs the Playwright + browser bytes baked in once. Sprint-auto's `tools/sprint-auto-bootstrap.sh` already runs `post_up_init`; project-local hook adds `playwright install --with-deps chromium` to that init step.

## Implementation sketch (per project)

1. **Add Playwright to dev deps** — `requirements-dev.txt` (or project equivalent) grows `playwright`, `pytest-playwright`, `axe-core-python` (or whichever a11y harness fits the project's Python version).
2. **Bake browsers into the dev image** — Dockerfile gets `RUN playwright install --with-deps chromium` (chromium-only is enough for v1; add Firefox/WebKit later if cross-browser regression matters).
3. **Test layout** — `web/<app>/tests/playwright/test_<surface>.py`. Matches the project's existing `tests/` layout per app.
4. **Baseline image storage** — `web/<app>/tests/playwright/__snapshots__/<test>/<scenario>.png`. Committed to repo; `pytest --update-snapshots` regenerates after intentional UI changes (gated behind explicit user direction, never auto-fired).
5. **Makefile target** — `make playwright-test` (project-equivalent). Mirrors `make test` semantics but scoped to the playwright dir. Used by sprint-auto's S2 routing for IDEAs that include Playwright tests in their plan's Verification section.
6. **First-IDEA pilot** — pick a surface that's *both* eval-gate today AND has clear automation wins (e.g. a modal primitive's focus-trap test). Land the test alongside any new IDEA touching that surface; verify the per-scenario `Walked: [x] (covered by ...)` pattern works in the eval-checklist.
7. **Sweep follow-up** — once the pattern is proven, file IDEAs to backfill Playwright coverage for previously-shipped UX surfaces. Each backfill IDEA ships with `auto_safe: true` (no eval-gate needed — the surface is already shipped + walked once; the test is regression-only).

## Open questions to lock at /plan time

- **Cross-browser**: chromium-only for v1, or Firefox + WebKit too? Cost: 3x browser bytes in image, 3x test runtime. Benefit: catches CSS / JS engine drift. Recommendation: chromium-only initially, add the other two if a real bug ships that they would have caught.
- **Visual-diff tolerance**: pixelmatch threshold (default 0.1 → catches ~10% pixel changes). Tightening reduces false negatives but raises flake rate; loosening hides genuine regressions. Recommend starting at default, tighten per-surface as needed.
- **Baseline-image management**: regenerate on every CI run from the integration worktree's stack, or commit to repo? Repo-committed is more robust (immutable history) but requires explicit refresh ritual. Recommend repo-committed with a `make playwright-snapshots-refresh` target gated behind explicit user invocation.
- **a11y rule scope**: every WCAG 2.1 AA rule, or a curated subset? Some rules are noisy on partial-render Cotton components. Recommend full WCAG 2.1 AA for shipped surfaces, with a per-test allowlist for known-acceptable violations (each allowlist entry needs a `# reason: <why>` comment that ages out).
- **Test parallelism**: Playwright supports `pytest-xdist` for parallel browser instances. Headless chromium is ~150 MB resident per worker. Recommend serial-by-default; parallel only after first-batch calibration shows headroom.

## Related references

- [`safety-gates.md`](references/safety-gates.md) — Mode A / Mode B opt-in (Direction 2, shipped).
- [`integration-stage.md`](references/integration-stage.md) — § Per-IDEA evaluation checklists (S11.10 PR body aggregation, shipped).
- [`../wrap/SKILL.md`](../wrap/SKILL.md) — § Step 7 (eval-checklist emission, shipped).
- [`../wrap/assets/manual-evaluation-template.md`](../wrap/assets/manual-evaluation-template.md) — the template Step 7 emits (shipped).
- [`RULE_parallel-worktree-docker`](../../rules/RULE_parallel-worktree-docker.md) — image-discipline rules that govern visual-baseline stability across container hosts.

## What this roadmap IS NOT

- Not a binding spec — when the implementation IDEA opens, refine based on what the project's stack actually supports.
- Not a sprint-auto-able task itself — building the test infrastructure (image baking, baseline-management Makefile target, first-pilot test) needs human design judgement and is too cross-cutting for unattended overnight execution. **Subsequent backfill IDEAs that just author Playwright tests for already-shipped surfaces are sprint-auto-able** with `auto_safe: true`.
