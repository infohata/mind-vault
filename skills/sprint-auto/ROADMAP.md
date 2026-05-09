# Sprint-auto roadmap — browser-test automation (Direction 1)

**Status**: design plan, not yet implemented. Direction 2 (`auto_safe_with_eval_gate` mode) shipped first; this is the planned uplift that shrinks Direction 2's manual-walk surface.

**Date opened**: 2026-05-05 · **Revised**: 2026-05-09 (architect + OSS-research pass)

## Why this exists

`auto_safe_with_eval_gate` (Direction 2) unblocks UX-overhaul / a11y-heavy IDEAs from sprint-auto by emitting a per-IDEA manual-evaluation checklist that the human walks at integration-PR-merge time. Cheap to build, cheap to run, but every IDEA still costs reviewer time per merge gate. As the cohort grows, this cost grows linearly.

Direction 1 — Playwright-driven browser automation in the dev image — *shrinks* the manual-walk surface by automating what *can* be automated: visual regression, focus-trap behavioural checks, keyboard navigation, z-index hit-testing, animation timing, axe-core a11y rule scans, HTMX swap assertions, Alpine state snapshots. The residue left for the eval-checklist becomes the genuinely-HITL stuff: screen-reader experience, mobile gesture nuance, "does this feel right" — items where automation is technically possible but the value-per-effort is poor.

Composability with Direction 2 is the point: per-surface Playwright tests land alongside that surface's IDEA, and the IDEA's eval-checklist correspondingly drops the now-automated rows. Eval-gate doesn't disappear; it adapts surface-by-surface.

## What headless Playwright covers

Two distinct buckets — both useful, but the OSS world (and mind-vault's first user, teisutis) recurrently conflates them:

**Static rule scans** (axe-core via `axe-playwright-python`):
- WCAG 2.1 AA mappable issues — contrast ratio, ARIA roles, label associations, heading order, landmark usage, alt-text presence.
- Runs after page load; one assertion per surface; fast.

**Behavioural assertions** (Playwright primitives, authored per surface):
- **Focus traps** — `page.keyboard.press('Tab')` × N + `page.evaluate(() => document.activeElement)` assertion. Axe-core does **not** cover this; each focus-trap scenario is its own test.
- **Keyboard navigation paths** — skip-link reach, Esc-to-close, arrow-key menus.
- **Z-index hit-testing** — `page.locator('button').click()` natively fails when a higher-stacked element intercepts. Free regression test for layering bugs.
- **HTMX swap assertions** — wait for `hx-target` to mutate (see § Stack notes for the canonical wait recipe), assert resulting DOM. Replaces "click button, hope HTMX swaps correctly" with deterministic checks.
- **Alpine state probes** — `page.evaluate(() => window.Alpine.$data(el).flag)` from a known DOM node. Catches `x-data` desync, `x-show` regressions.
- **Animation timing** — `page.wait_for_function(() => getComputedStyle(...).opacity === '1', timeout=2000)`. Catches stuck-mid-transition bugs.
- **Visual regression** — `expect(page).to_have_screenshot('name.png')` against committed baselines. Stable within a single image build (see § Visual-baseline stability).

**Out of scope, stays HITL:**
- Screen-reader *experience* — axe-core checks the markup; only NVDA/VoiceOver verifies the read-out makes sense.
- Mobile gesture nuance — swipe-to-dismiss feel, pull-to-refresh momentum, touch-target ergonomics under glove/wet finger.
- Subjective polish — easing curves, micro-interaction copy, brand voice in tooltips.

## Approach — headless, in-container, no X11

Playwright runs headless on Linux containers with no display server. Microsoft ships official Docker images preloaded with Chromium + Firefox + WebKit (`mcr.microsoft.com/playwright:v<X>-jammy` — pin Ubuntu 22.04 base; Alpine breaks on musl/glibc). Two integration options per project — pick the lighter one that fits:

1. **Pip-install into existing `web` image** — simplest when the project already has a Python `web` service. Adds `playwright` + `pytest-playwright` + `axe-playwright-python` + `pytest-playwright-visual-snapshot` to `requirements-dev.txt`; `playwright install --with-deps chromium` runs at image build. No new docker service.
2. **Separate `playwright` service** — when the `web` image is intentionally minimal (production parity is tight) or build-time matters. Pulls the official MS image; bind-mounts source + test results.

Option 1 is the default unless the project explicitly objects. Both options route through the **project-side bootstrap script** below — humans don't hand-write the Dockerfile delta.

## Project-side bootstrap script

The first concrete deliverable mind-vault ships for Direction 1 is `tools/setup_playwright.sh` (project-local; project copies it from a mind-vault asset under `skills/sprint-auto/assets/setup_playwright.sh.template`). Idempotent — re-running on an already-set-up project is a no-op.

What it detects + writes:

| Detected | Action |
|---|---|
| `docker-compose.yml` exists with a `web` service running Python | Option 1 — pip-install path. Append Playwright deps to `requirements-dev.txt` (or project equivalent), write a Dockerfile delta (multi-stage `RUN playwright install --with-deps chromium` after pip), regenerate the image layer. |
| `docker-compose.yml` has no `web` service or web is non-Python | Option 2 — add a `playwright` service block to a new `docker-compose.playwright.yml` overlay (loaded with `-f`). |
| `Makefile` exists | Add `make playwright-test`, `make playwright-snapshots-refresh` (gated behind explicit env-var flag), `make playwright-trace-clean` targets. |
| `pyproject.toml` / `pytest.ini` / `setup.cfg` | Append `pytest-playwright` config block + `addopts = --tracing retain-on-failure` + project-relative `testpaths`. |
| `.github/workflows/` exists | Write `playwright.yml` workflow stub: matrix on Python version + browser, retry-on-failure, artifact upload of traces + visual-diff HTML. |
| `.gitlab-ci.yml` exists | Append a `playwright` job stage. |
| `.gitignore` exists | Append `__snapshots__/*.actual.png`, `__snapshots__/*.diff.png`, `playwright-traces/`, `playwright-report/`. |
| Project has `django-tenants` in deps | Provision a `conftest.py` skeleton with a `tenant_session` fixture stub (per-tenant schema swap + `storage_state` JSON cache under `tests/playwright/auth/<tenant>-<role>.json`). |
| Project has `LANGUAGES` in `settings.py` with > 1 entry | Provision a `browser_context_args` fixture that pins `locale` + `Accept-Language` from a `PLAYWRIGHT_LOCALE` env var (default = project's `LANGUAGE_CODE`). |
| Project has multilingual locales beyond Latin-1 | Append `fonts-noto fonts-noto-cjk fonts-liberation` + `fc-cache -fv` to the Dockerfile's apt step. |

The script doesn't author tests — it provisions the runtime so tests can be authored. Its output is reviewable as a normal PR.

**Why a script and not a sprint-auto-able IDEA**: the bootstrap touches Dockerfile, CI workflows, and dependency manifests — files where a wrong move costs an image rebuild or a CI flake. Concentrating the touches into one reviewable script (rather than spreading them across an IDEA's commits) keeps the human-judgement surface minimal and reviewable.

## IDEA-level Playwright-availability gate (noop semantics)

The bootstrap script answers "how does the project get Playwright". The gate answers "what if it doesn't yet?" — without the gate, every Playwright-mentioning IDEA would block on infra readiness, defeating the whole sprint-auto-able-backfill premise.

**Frontmatter flag**: an IDEA that wants Playwright coverage adds `requires_playwright: true` to its frontmatter alongside its existing opt-in fields.

**Probe** (run by `/plan`'s architect pass + by `/work`'s S2 verification): inside the project's web container, `make playwright-test --version` (or equivalent) exits 0 → infra present. Anything else → infra absent.

**Branching at /plan time**:
- Infra **present** + `requires_playwright: true` → plan author writes Playwright tests into the Verification section. Eval-checklist rows for covered scenarios get pre-filled (see § Composability).
- Infra **absent** + `requires_playwright: true` → plan author writes ONLY the manual-eval-checklist rows for those scenarios. The frontmatter flag is preserved as a backref ("when Playwright lands, a follow-up backfill IDEA can author tests for these scenarios"). The IDEA itself ships through sprint-auto with eval-gate as today.
- `requires_playwright` not set → IDEA proceeds independent of Playwright state. (Most IDEAs.)

**Branching at /work time** (defence-in-depth — covers the case where infra was uninstalled between /plan and /work):
- If S2 expected Playwright tests but the probe fails, S2 logs a `playwright_unavailable` warning to the auto-run log, skips the Playwright tests, and continues. The IDEA still ships; the manual-eval rows the plan would have pre-filled stay un-pre-filled.

**Bootstrap-circularity solution**: the **only** IDEA whose `requires_playwright` is false but whose deliverable provisions the infra is the project's first "set up Playwright" IDEA. It runs the bootstrap script (as a manual operator step, since image builds are non-sprint-auto-able), opens the PR for review, merges. After merge, every downstream IDEA's probe finds the infra and the gate flips to "present". Before merge, every downstream IDEA's probe finds the infra absent and the gate falls back to manual-eval rows. **No IDEA is ever blocked on Playwright readiness — only the test-authoring effort is gated.**

## Stack notes — Cotton + Alpine + HTMX (no TypeScript)

The first user (teisutis) ships server-rendered Django Cotton components with Alpine.js for client state and HTMX for partial swaps. No TypeScript. So:

- Tests are **Python** (`pytest-playwright` sync API), not TS — keeps the dev surface uniform with the rest of the project's tests. Async API only when the app itself is async (Daphne+ASGI on every endpoint); for HTMX-driven Django, **stay sync**.
- Live-server fixture: `pytest-django`'s `live_server` is the canonical answer; no separate `django-playwright` package needed. Microsoft's `mxschmitt/python-django-playwright` repo is the reference example.
- **HTMX wait recipe** (canonical, from htmx upstream discussion #2360):
  ```python
  await expect(page.locator(
      '.htmx-request, .htmx-settling, .htmx-swapping, .htmx-added'
  )).to_have_count(0)
  ```
  Avoid `document.body.classList.contains('htmx-settled')` — that's not an HTMX-built-in class; would hang on any project that hasn't wired the hook.
- **Alpine probe**: `page.evaluate("() => window.Alpine.$data(document.querySelector('[x-data]'))")`. Pair with `page.wait_for_function('window.Alpine !== undefined')` after each navigation since Alpine boots after DOM ready.
- **HTMX-during-Alpine-init race** (per `skills/django-frontend/references/ALPINE_HTMX_GOTCHAS.md` gotcha 5): pages with `hx-trigger="load"` on initial mount need a `page.wait_for_load_state('networkidle')` *in addition to* the `window.Alpine` check before any state assertion — the simple Alpine-ready check passes during a partially-initialised DOM if a `load`-triggered swap is mid-flight.
- Cotton components render server-side, so visual baselines reflect the rendered HTML — no client-only-rendered components to worry about. (Pixel stability across image rebuilds is a separate issue — see § Visual-baseline stability.)
- Pair with `RULE_parallel-worktree-docker`'s container-image discipline: visual baselines must be captured in the same image they assert against (font rendering varies by Linux distro). Baselines committed to repo; CI re-captures on `--update-snapshots` only behind explicit user direction.

For projects with different stacks (React/Vue, TS), the same headless Playwright approach applies — only the test language and the framework-state probes change.

## Visual-baseline stability — what's actually stable, what's not

Server-side rendering stabilises *content*, not *pixels*. Drift sources:

- **Font rasteriser version** — Chromium minor-version bumps shift glyph rendering at sub-pixel scale. Inevitable over time.
- **Static asset fingerprints** — `STATIC_URL` hash changes from `collectstatic` reconfiguration → CSS `<link>` refetch path differs → small font / spacing shifts even when the CSS body is unchanged.
- **Locale-dependent layouts** — Lithuanian word lengths ≠ English word lengths; same component renders to different pixel dimensions per locale.

Mitigations:

- **Pin font packages explicitly**: `fonts-noto` (Latin Extended + Cyrillic), `fonts-noto-cjk` (only if CJK locales ship), `fonts-liberation` (fallback) + `fc-cache -fv`. Bootstrap script handles this (see above).
- **Default-locale baselines + structural-only locale assertions** — capture pixel baselines in one canonical locale; for other locales, assert DOM structure (presence, hierarchy, attributes) without screenshots. Per-locale baselines balloon to N× count and rarely catch real regressions.
- **Pixelmatch default (0.1 threshold) for first cut**; per-surface upgrade to `mode='ssim'` for surfaces that flake on anti-aliasing.
- **Triage protocol on baseline failure**: visual diff that's >80% in text glyphs → suspect font rendering or asset-path drift; visual diff localised to one component → real regression. Bake into the `make playwright-test` failure output.

Genuine novelty mind-vault ships here: [`rules/RULE_visual-baseline-bumps.md`](../../rules/RULE_visual-baseline-bumps.md) codifies "AI agents never auto-`--update-snapshots`; baseline regen requires explicit human invocation". OSS tools either auto-accept or require SaaS click-through; mind-vault's discipline is the right shape for AI-orchestrator workflows.

## Composability with Direction 2 (eval-gate)

Per-surface Playwright tests land alongside that surface's IDEA. The IDEA's `auto_safe_with_eval_gate: true` flag stays set; the eval-checklist that `/wrap` Step 7 emits is correspondingly trimmed.

**Cross-reference contract** (specifies how `/wrap` knows what to pre-fill):

The plan doc at `docs/archive/<idea>/YYYY-MM-DD-<slug>-plan.md` includes a machine-readable `playwright_test_coverage` block in its Verification section:

```yaml
# In the plan doc's Verification section:
playwright_test_coverage:
  - scenario: "Modal opens with focus trapped on first input"
    test: "tests/playwright/test_modal.py::test_focus_trap_first_input"
  - scenario: "Esc closes modal and restores focus to trigger"
    test: "tests/playwright/test_modal.py::test_esc_close_focus_restore"
```

`/wrap` Step 7 reads this block when emitting the manual-eval checklist; for each scenario row in `manual-evaluation-template.md`, if a matching entry exists, the row is pre-filled with `**Walked**: [x] (covered by tests/playwright/test_modal.py::test_focus_trap_first_input)`. Rows without a match stay un-pre-filled and remain HITL.

When a Playwright test gets renamed or deleted in a later IDEA, the corresponding row's pre-fill rots. Solution: `make playwright-test --collect-only` listing in the plan's `playwright_test_coverage` is verified-against by `/wrap` Step 7 at emit time; missing tests downgrade the row to "manual" with a one-line warning. No silent rot.

Over time, well-tested surfaces shrink toward "no manual walk needed"; new surfaces start with most of their checklist still manual. The eval-gate stays the safety net while automation catches up surface-by-surface.

## Sprint-auto integration — v3.1 routing

Two natural touch points in sprint-auto's existing flow — neither needs new state machinery, but both need the **right routing** under v3.1's per-IDEA-worktree-without-stack model:

- **S2 verification** — per-IDEA worktrees have NO docker stack in v3.1. Targeted tests (including Playwright) route to the integration worktree via `SPRINT_AUTO_INTEGRATION_WORKTREE` (see `references/integration-stage.md` § fix-verification routing). The integration worktree's docker stack runs Playwright; test source lives in the per-IDEA branch and is bind-mounted or fetched.
- **S11.8 union-of-target-tests + S11.9 full-suite** (integration-state validation). Playwright tests run as part of the suite — same `cap_exceeded` discipline as any other test, **plus** a Playwright-specific re-run-once-on-flake retry policy (visual baselines are inherently more flake-prone than unit assertions; one retry catches transient font / network jitter without legitimising real regressions).

**S(-1) preflight** (sprint-auto bootstrap): the integration worktree's stack must have Playwright present. Add a one-liner to `tools/sprint-auto-bootstrap.sh`:

```bash
docker compose exec -T web playwright --version || \
    echo "WARN: Playwright not in integration stack; IDEAs with requires_playwright will gate to manual-eval-only."
```

Non-fatal. The IDEA-level gate handles the absence per § IDEA-level Playwright-availability gate.

**Memory budget**: realistic resident set per Playwright worker is **400–700 MB peak** under real navigation (login, multi-page session, Cotton + Alpine + HTMX rendered) — not the "~150 MB" the earlier draft cited. Plan **2 GB RSS budget per worker** when sizing the sprint-auto VPS. Serial-by-default; parallel only after first-batch calibration shows headroom.

## Implementation sketch (per project, ordered)

1. **Run `tools/setup_playwright.sh`** (the bootstrap script — see § Project-side bootstrap script). Reviewable PR. Merges to main. **This IDEA does NOT carry `requires_playwright: true`** — it provisions the gate's "present" state but doesn't depend on it.
2. **First-IDEA pilot** — pick a surface that's *both* eval-gate today AND has high-value automatable scenarios. Concrete candidates from teisutis: IDEA-141 modal primitives focus traps, IDEA-146 article-shell preview-stack URL round-tripping, IDEA-160 per-pane scroll containment. Set `requires_playwright: true` on the pilot IDEA's frontmatter; author 3-5 Playwright tests covering the highest-value scenarios; verify the per-scenario `Walked: [x] (covered by ...)` pre-fill works in the eval-checklist.
3. **Sweep follow-up** — once the pattern is proven, file backfill IDEAs to add Playwright coverage for previously-shipped UX surfaces. Each backfill IDEA ships with `requires_playwright: true` + `auto_safe: true` (no eval-gate needed — the surface is already shipped + walked once; the test is regression-only). **Test-quality gate**: backfill IDEAs require at least one human-eyes pass on each new test asserting it actually exercises the failure path it claims to (checking against the original IDEA's eval-checklist) — without this, "walked once" becomes a cargo-cult gate.

Test layout (provisioned by bootstrap):

- `web/<app>/tests/playwright/test_<surface>.py` per app
- `web/<app>/tests/playwright/__snapshots__/<test>/<scenario>.png` for visual baselines
- `tests/playwright/auth/<tenant>-<role>.json` for storage_state caches (multi-tenant)
- `tests/playwright/conftest.py` for live_server + tenant_session + locale fixtures

## Open questions — decided (research-resolved)

These were open in the prior draft; the OSS landscape converged on answers, fold them in at /plan time without further deliberation:

- **Cross-browser**: chromium-only for v1; add Firefox + WebKit only if a real bug ships that they would have caught.
- **Visual-diff threshold**: pixelmatch default (0.1); per-surface upgrade to `mode='ssim'` for anti-aliasing-prone surfaces.
- **Baseline storage**: in-repo until ~500 baselines or ~50 MB; revisit (git-lfs or reg-suit + S3) only past that.
- **a11y rule scope**: WCAG 2.1 AA + per-test allowlist with `# reason: <why>` comments that age out.
- **Test parallelism**: serial-by-default; parallel only after empirical first-batch headroom check.
- **a11y wrapper choice**: `axe-playwright-python` (Pamela Fox's wrapper). Replace earlier "axe-core-python" reference.
- **Visual-snapshot package**: `pytest-playwright-visual-snapshot` (iloveitaly, v0.5.1+) as a dependency — superset of native Playwright snapshot, ships the explicit-`--update-snapshots` HITL gate the discipline requires.
- **Sync vs async API**: sync (consensus for Django+HTMX shops in 2025–2026).

## Open questions — still unresolved (lock at /plan time)

- **Trace-file retention**: how long do failed-test trace artifacts live in CI / locally? They grow to 50–200 MB per failed test. `retain-on-failure` is the capture policy; the *retention* policy is project-specific.
- **Baseline-bump approval ritual under sprint-auto**: when sprint-auto runs unattended overnight and a real visual regression triggers, the run halts. The CI signal for "this IDEA needs a snapshot bump before merging" is undefined. Auto-emit a manual-walk row? Block the integration PR?
- **Cotton-component-level vs page-level baseline scope**: per-component baselines are more surgical but slow + brittle; per-page baselines are fast but bulk-fail on minor changes. No community benchmark. Decide per-project.
- **Multi-tenant storage_state cache invalidation**: when a project's user model schema changes, all cached storage_state JSONs are stale. Detection and invalidation policy unclear.

## Missing pieces — to expand at /plan time

These need explicit treatment in the implementation IDEA's plan; the bootstrap script provides skeleton fixtures but the discipline rules need authoring:

- **i18n locale pinning** — `browser_context_args` fixture overriding `locale` + `Accept-Language` from `PLAYWRIGHT_LOCALE` env. Default-locale baselines + structural-only locale assertions for other locales. Bootstrap script provisions the fixture; IDEA needs to document the discipline (which surfaces get per-locale baselines vs structural-only).
- **Multi-tenant authentication** — `storage_state` + `browser_context_args` per tenant + per role. For `django-tenants`: tenant schema swap before login, dump storage_state to `tests/playwright/auth/<tenant>-<role>.json`. **Researcher's strongest novelty finding**: zero published examples in the OSS world for this combo. The architectural patterns are codified in [`../django-frontend/references/MULTI_TENANT_PLAYWRIGHT.md`](../django-frontend/references/MULTI_TENANT_PLAYWRIGHT.md); the project-specific tenant list, role matrix, and storage_state cache TTL still need IDEA-level decisions.
- **Test data reset** — within an IDEA's Playwright suite, tests are sequential. Either each test is idempotent (uses `page.goto` from a known DB state) or the suite uses transaction rollback between tests. Specify the discipline.
- **Chromium version migration** — when the dev image's Chromium bumps (security patch, dep update), some baselines red-shift. Triage protocol: glyph-only diff → font drift, refresh allowed; layout diff → real regression, investigate. Codified in [`../../rules/RULE_visual-baseline-bumps.md`](../../rules/RULE_visual-baseline-bumps.md) § "The Chromium-bump cliff".
- **HTMX + Alpine + Cotton wait-discipline as a packaged pattern** — the four-step recipe (`window.Alpine` ready → trigger → htmx-settled predicate → state probe) is codified in [`../django-frontend/references/HTMX_ALPINE_WAITS.md`](../django-frontend/references/HTMX_ALPINE_WAITS.md) and ready for reuse across projects.

## Related references

- [`safety-gates.md`](references/safety-gates.md) — Mode A / Mode B opt-in **plus** the Playwright-availability gate (`requires_playwright` flag) — three-branch routing matrix, never a disqualifier.
- [`integration-stage.md`](references/integration-stage.md) — § Per-IDEA evaluation checklists (S11.10 PR body aggregation, shipped) + § fix-verification routing (v3.1 worktree model).
- [`../wrap/SKILL.md`](../wrap/SKILL.md) — § Step 7 (eval-checklist emission) + Playwright-coverage pre-fill from the plan's `playwright_test_coverage` block.
- [`../wrap/assets/manual-evaluation-template.md`](../wrap/assets/manual-evaluation-template.md) — the template Step 7 emits; HTML comment under Scenarios documents the three pre-fill states.
- [`assets/setup_playwright.sh.template`](assets/setup_playwright.sh.template) — the project-side bootstrap script that provisions Playwright into a target project's stack.
- [`../../agents/AGENT_architect.md`](../../agents/AGENT_architect.md) § "/plan-time project probes" — the architect's role in deciding whether an IDEA wants `requires_playwright: true` based on its surface.
- [`../../rules/RULE_visual-baseline-bumps.md`](../../rules/RULE_visual-baseline-bumps.md) — AI-never-auto-regen discipline for visual baselines.
- [`../../rules/RULE_parallel-worktree-docker.md`](../../rules/RULE_parallel-worktree-docker.md) — image-discipline rules that govern visual-baseline stability across container hosts.
- [`../django-frontend/references/HTMX_ALPINE_WAITS.md`](../django-frontend/references/HTMX_ALPINE_WAITS.md) — Playwright wait recipes for HTMX + Alpine + Cotton surfaces.
- [`../django-frontend/references/MULTI_TENANT_PLAYWRIGHT.md`](../django-frontend/references/MULTI_TENANT_PLAYWRIGHT.md) — django-tenants fixtures (Host header, schema seeding, storage_state cookie pre-baking).
- [`../django-frontend/references/ALPINE_HTMX_GOTCHAS.md`](../django-frontend/references/ALPINE_HTMX_GOTCHAS.md) — gotcha 5 (HTMX-during-Alpine-init race) is the wait-discipline upstream constraint.

## OSS components mind-vault depends on (named, not bundled)

| Project | Role |
|---|---|
| `playwright` + `pytest-playwright` | Browser automation core |
| `pytest-playwright-visual-snapshot` (iloveitaly) | Visual snapshot UX + explicit `--update-snapshots` HITL gate |
| `axe-playwright-python` (Pamela Fox) | a11y rule scanning |
| `pytest-django` | `live_server` fixture |
| `mxschmitt/python-django-playwright` | Reference example for the Django+Playwright Makefile + fixtures shape |
| `mcr.microsoft.com/playwright:v<X>-jammy` | Optional alternative to baking browsers into the project image |

## What this roadmap IS NOT

- Not a binding spec — when the implementation IDEA opens, refine based on what the project's stack actually supports.
- Not a sprint-auto-able task itself — the bootstrap script run is human-operator-driven (Dockerfile + CI workflow changes). **Subsequent backfill IDEAs that just author Playwright tests for already-shipped surfaces are sprint-auto-able** with `requires_playwright: true` + `auto_safe: true`.

**Last Updated**: 2026-05-09
