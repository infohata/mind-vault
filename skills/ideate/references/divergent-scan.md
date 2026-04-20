# Divergent scan — per-axis prompts and recipes

Concrete generation prompts for each axis in `/ideate` step 2. Load on demand. Pick the subset applicable to the scoped area; never run every axis on every scope.

## The "good candidate" shape

Every candidate should be specific enough to become a valid `IDEA-NNN-<slug>.md` entry after the filter. That means:

- **Title** is 3–10 words, declarative (not a question).
- **Summary** is one sentence, actionable, names a concrete artifact (file / module / behaviour).
- **Priority signal** is tentative (high / medium / low) — the filter may revise.
- **Effort estimate** is rough (XS ≈ hour, S ≈ half-day, M ≈ day, L ≈ week+).

Reject candidates at generation time if they'd still be vague at filter time. "Improve performance" is not a candidate; "Add `select_related` to the `OrderListView` queryset in `orders/views.py:OrderListView:45`" is.

## Axis 1 — Bugs & correctness

Recipes:

```bash
# TODO/FIXME/XXX/HACK comments with nearby code context
rg -nw 'TODO|FIXME|XXX|HACK' --type py --type html --type js | head -50

# Low-coverage files (if coverage report exists)
rg -l 'coverage: \d\d%' coverage-reports/ 2>/dev/null

# Flaky tests (if run history exists)
grep -r 'RerunPolicy\|@pytest.mark.flaky\|FLAKY' tests/
```

Generation prompt to self:

- Which 3 files have the most TODO comments that haven't been addressed in ≥6 months?
- Which tests have been marked skip / xfail / flaky without a resolution plan?
- Which `docs/solutions/` entries describe a fix that was only half-applied — the other half is still broken?

## Axis 2 — Tech debt

Recipes:

```bash
# Files with highest churn (candidates for refactor)
git log --pretty=format: --name-only --since='3 months ago' | sort | uniq -c | sort -rn | head -20

# Large files (often god-objects)
find . -name '*.py' -not -path './.git/*' | xargs wc -l | sort -rn | head -10

# Hand-rolled cookie / url / json parsers
rg -n "document\.cookie\.split|split\(';'\)|split\(', '\)"
```

Generation prompt to self:

- Which file has grown 3× since it was introduced and now spans multiple concerns?
- Is there a utility function that exists in two places with near-identical code? Name the locations.
- Any model's `__str__` / `get_absolute_url` / `Meta` that's been copy-pasted across five entities instead of inheriting from a `BaseModel`?

## Axis 3 — New features

Recipes:

```bash
# Commented-out feature blocks
rg -n '^\s*# *[Dd]isabled|^\s*# *[Tt]odo:|\{% comment %\}[\s\S]+?\{% endcomment %\}'

# Half-shipped work
rg -n 'TODO\(phase|TODO\(v2|TODO\(next'

# Integration points with external services (stub implementations)
rg -n 'raise NotImplementedError|pass  # TODO'
```

Generation prompt to self:

- What feature did the last 5 PRs get close to but not finish?
- What does the user manually work around because the UI doesn't expose a thing the backend already supports?
- Any "coming soon" label in a template that's been there >3 months?

## Axis 4 — Refactors

Generation prompt to self:

- Pick the module with the most imports. Can it be split by concern?
- Any class with >10 public methods and no clear single responsibility?
- Naming: are there two terms used for the same concept, or one term for two concepts?
- Any abstraction that requires the caller to know internal state to use it correctly?

Refactor candidates should ALWAYS come with a "what breaks when I ship this" note, or they fail the filter.

## Axis 5 — Tooling

Generation prompt to self:

- What command does the user type more than 3 times per week? Candidate for a Makefile target.
- What setup step does a new contributor hit on first clone that isn't in the README?
- What manual dance happens after every deployment that could be automated?
- Any CLI tool that requires >3 flags in the same order every time? Candidate for a shell alias or wrapper.

Recipes:

```bash
# Makefile target coverage
cat Makefile 2>/dev/null | grep -E '^[a-z-]+:' | wc -l

# Shell history patterns (if ~/.bash_history accessible)
# Don't read directly — ask the user what they type often.
```

## Axis 6 — Docs

Generation prompt to self:

- When was README last updated vs. last feature ship? Drift check.
- Is there an ONBOARDING.md? If not, what's the first-hour friction?
- Architecture diagram: does one exist, and does it match the current structure?
- Any convention the user has documented in a PR comment that should live in a rule or skill instead?

Recipes:

```bash
# README drift — compare file mtime to recent commits touching other files
find . -name 'README.md' -not -path './.git/*' -exec ls -la {} \;
git log --oneline --since='6 months ago' | wc -l
```

## Axis 7 — Observability

Generation prompt to self:

- Are there critical paths (payment, auth, data mutation) without explicit logging?
- Any `except:` or `except Exception:` that swallows without logging?
- Metrics on known-slow endpoints?
- Alerting: when something breaks, how does anyone know?

## Axis 8 — Process

Generation prompt to self:

- What CI checks are missing that would have caught the last production incident?
- Is there a PR template? Does it ask the right questions?
- Merge discipline — any branches older than 30 days? Any fix that had to land on 3 different branches because of divergence?

## Picking the axis subset

Scope drives axis selection, not the other way around:

| Scoped area | Priority axes |
| --- | --- |
| Test suite health | Bugs, tech debt, tooling, process |
| A specific app | Bugs, new features, refactors, tech debt |
| Deploy pipeline | Tooling, observability, process |
| Codebase landscape / next sprint | All axes (budget 15–25 candidates, filter hard) |
| Docs tree | Docs, onboarding, process |

## The generation checklist before handing off to the filter

- [ ] Each candidate has a specific artifact reference (file path, module, endpoint, command).
- [ ] Each candidate has a one-sentence actionable summary.
- [ ] Priority band tentatively assigned.
- [ ] Effort estimate rough but present.
- [ ] Nothing is duplicated between candidates (the filter will catch cross-duplicates with prior art).
- [ ] The candidate count is within the right-sizing budget (see `SKILL.md`).

Move to the adversarial filter.

---

**Last Updated**: 2026-04-19
