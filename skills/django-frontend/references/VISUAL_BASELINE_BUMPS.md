# Visual baseline bumps — AI never auto-`--update-snapshots`

Baseline regen is a deliberate human act.

Visual-regression tests assert that a rendered surface still matches a committed pixel baseline (`pytest-playwright-visual-snapshot`, `pytest-playwright`'s `expect(page).to_have_screenshot(...)`, or equivalent). When the assertion fails, two interpretations are equally consistent with the failure signal:

1. **The code regressed** — a real visual bug landed; the diff is what users would see.
2. **The baseline drifted** — fonts changed, the image was rebuilt, the locale rendered wider, the asset hash shifted.

Only a human can distinguish (1) from (2) by *looking at the diff*. Auto-running `--update-snapshots` collapses both into "accept the new pixels" and ships regressions as if they were intended changes.

## The Hard Rules

1. **AI agents NEVER pass `--update-snapshots` (or `pytest --update-snapshots`, or `playwright test --update-snapshots`, or any other regen-baseline flag) without an explicit, in-conversation human directive that names the surface(s) being regenerated.** "Run the tests" does NOT authorise regen. "Fix the failing visual tests" does NOT authorise regen. "Update the baselines" DOES — when it's typed by the human, naming what to update.

2. **Baseline regen and code change ship in separate commits.** A commit that mixes "I changed the button's padding" with "I regenerated 12 baselines" is unreviewable — the reviewer cannot tell which baselines moved because of the padding change versus which moved because of unrelated drift. Sequence: code-change commit → human eyeballs the visual diff → baseline-regen commit if intended → push.

3. **The regen commit's message names every surface and the reason.** Format:

   ```
   test(visual): regen baselines — <surface-list> (<reason>)

   - Surface A: pad regression accepted (intended IDEA-NNN scope)
   - Surface B: font drift, Chromium 124 → 125 in image rebuild
   - Surface C: locale-lt re-rendered after kb_articles word-length change
   ```

   No "regen all" without per-surface justification. If the list is too long to enumerate, the regen is too coarse — split it.

4. **Default-locale baselines only. Other locales get structural assertions, not pixel baselines.** Locale-dependent layout produces N× baseline count for ~zero additional regression-catching power. Pixel baselines in `lt`, `ru`, `de`, etc. are pure maintenance cost.

5. **Baselines live in the repo, captured in the same image they assert against.** Font rendering varies across Linux distros; a baseline captured on a developer host's macOS Chromium and asserted against in a `mcr.microsoft.com/playwright:vX-jammy` CI container will diff every time. Bootstrap script (`setup_playwright.sh.template`) handles font pinning; baselines must originate from the canonical container.

## When This Applies

Any project that uses Playwright (or equivalent) visual-regression assertions:

- `pytest-playwright-visual-snapshot` — `expect(page).to_have_screenshot('name.png')`
- `pytest-playwright` baseline mode
- `playwright test` JS / TS suites with `toMatchSnapshot()`
- Any other framework where a committed image file is the assertion target

Does **not** apply to:

- DOM-structure assertions (`.locator(...).to_be_visible()`, `.to_have_text(...)`, etc.) — no baseline pixels to regen.
- axe-core a11y checks — rule violations, not baselines.
- Behavioural Playwright tests (focus traps, keyboard navigation, HTMX swap completion) — assertion targets are state, not pixels.

## Why This Matters

### The auto-regen failure mode

A visual-regression test fails on CI because an unrelated dependency bump regenerated the image layer with a newer Chromium. An AI agent following "fix the failing tests" reflex passes `--update-snapshots`, the new pixels become the baseline, the agent commits + pushes. Two cycles later, a genuine padding regression lands — the test fails. The agent runs `--update-snapshots` again. The padding regression is now "the baseline", indistinguishable from the legitimate Chromium-bump diff that came before.

The pattern repeats; baselines become the agent's view of "whatever the code currently renders", and visual regression stops catching anything. By the time a human looks at a UI and notices something is off, the regression is months deep and unbisectable.

### Why this rule is mind-vault-specific

OSS visual-regression tools either:

- **Auto-accept** on the first failure (some local-dev defaults) — wrong in CI, dangerous with AI agents.
- **Require SaaS click-through** (Percy, Chromatic) — costs a SaaS bill plus a human-in-the-loop click that the AI agent can't make.

Mind-vault's discipline — *AI agents never regen, period* — is the right shape for AI-orchestrator workflows. The human looks at the diff (the SaaS-equivalent click) by running the test locally with `--update-snapshots` themselves; the agent stages the regenerated PNGs and commits per Hard Rule 3.

### The Chromium-bump cliff

When the project's Playwright base image bumps Chromium minor versions (e.g. `playwright:v1.40-jammy` → `v1.41-jammy`), font rasterisation shifts at sub-pixel scale; nearly every baseline diffs. This is a one-time event and the right response IS to regen — under human direction, naming the bump in the commit message:

```
test(visual): regen baselines — Chromium 124 → 125 image bump

All 47 surfaces drifted from font rasterisation. Spot-checked 6 random
surfaces; no functional regressions. Re-baselined under operator
direction following the IDEA-NNN image bump.
```

That's a clean baseline-regen story. What's NOT clean: 47 baselines drifted alongside a behavioural change to one component, and the agent regenerated all 47 without distinguishing.

## How To Apply

1. **AI agents on visual-test failure**: report the failure with `pytest-playwright-visual-snapshot`'s diff PNG path or the equivalent `playwright test` output dir. Do NOT regen. Hand back to the human for inspection. Wait for explicit "regen <surface>" direction.

2. **Humans regenerating baselines**: run the regen locally (or in the canonical container — see Hard Rule 5), inspect each diff, decide accept-or-reject per surface, then commit per Hard Rule 3. Do not lump the regen into a code-change commit (Hard Rule 2).

3. **Bootstrap script** (`setup_playwright.sh.template`) wires this discipline into the project's `Makefile` / `package.json` / equivalent task runner: `make playwright-test` runs without regen flags by default; `make playwright-update-baselines` is a separate target that the human invokes deliberately. AI agents do NOT call the latter target.

4. **CI pipeline** never passes `--update-snapshots`. CI is a check, not a regen mechanism. A failing visual test in CI either reflects a real regression (fix the code) or unrelated drift (regen locally, push regen commit, CI passes on next run).

## Anti-Patterns

- ❌ "The test failed; let me regen the baseline." (No — the human looks at the diff first.)
- ❌ Mixing regen + code change in one commit ("I refactored the button and regenerated its baseline").
- ❌ Regenerating "all baselines" without per-surface justification.
- ❌ Per-locale pixel baselines (`screenshot('button-en.png')`, `screenshot('button-lt.png')`, ...). Default-locale only; structural assertions for the rest.
- ❌ Capturing baselines on the developer host instead of the canonical container — every CI run will diff.
- ❌ Storing baselines outside the repo (S3 bucket, SaaS) — they need to bisect-cleanly with the code that asserts them.

## Relationship To Other Rules / Skills

- [`RULE_git-safety`](../../../rules/RULE_git-safety.md) — baseline regen still happens on a feature branch; protected-branch rules are unchanged.
- [`PARALLEL_WORKTREE_DOCKER`](../../sprint-auto/references/PARALLEL_WORKTREE_DOCKER.md) — § "Docker as privileged-fileops escape hatch" is occasionally needed when baselines are written by the container as root and the host user can't unlink them; same `docker run --rm -v <path>:/work alpine chown -R "$(id -u):$(id -g)" /work` recipe applies.
- [`skills/sprint-auto/SKILL.md`](../../sprint-auto/SKILL.md) — sprint-auto preflight + per-IDEA gate behaviour treats `--update-snapshots` as out-of-bounds for unattended runs.
- [`skills/sprint-auto/assets/setup_playwright.sh.template`](../../sprint-auto/assets/setup_playwright.sh.template) — wires `make playwright-test` and `make playwright-update-baselines` as separate targets per § "How To Apply" #3.
