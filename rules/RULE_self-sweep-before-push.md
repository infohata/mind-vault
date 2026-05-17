# RULE_self-sweep-before-push

Before `git commit` on any cycle that touches Python or JS source, run a brief self-sweep on every file edited this cycle. The sweep catches the same trivial findings any code-review bot will catch — at zero cycle-cost, instead of the 5-10 minute round-trip of "push → review → fix-comment → push → re-review".

## The Hard Rule

For every file edited in the current commit's working set:

1. **Imports block** — every `import X, Y, Z` and `from X import A, B, C`: are A/B/C all referenced in the file? If not, drop them.
2. **Dead conditionals** — any `if foo:` followed by code that's overwritten unconditionally a few lines later? Same for ternaries with both branches reaching the same effective state.
3. **Unused locals** — `var = something()` that's never read. Either drop the assignment (keep the side-effect call: `something()`) or rename to `_` to signal intent.
4. **Stale comment vs code** — does the comment still describe what the code does, or did the last edit invalidate it?

For Python files, `python -m pyflakes <path>` (already in dev-image for most projects) catches #1 and #3 mechanically in ~1 second. For JS, eyeball at minimum.

## When This Applies

- Every commit on a feature branch that touches `.py` or `.js` source.
- Mandatory before push if a bugbot-equivalent code-review bot is wired up to the PR — the self-sweep saves an entire bugbot cycle (review + commit + retrigger + re-review) per trivial finding.
- Especially valuable inside `bugbot-loop` skills: between Phase 2 (apply edits) and Phase 3 (commit + push + retrigger), so trivial issues never reach bugbot.

## The Pyflakes Pipe Pattern

Most projects don't ship `pyflakes` in the production image. Two clean ways to run it on demand:

**Project Makefile target** (one-time setup, durable):

```make
self-sweep:
	@docker compose exec -T web pip install --quiet pyflakes 2>/dev/null
	@docker compose exec -T web python -m pyflakes $(PATHS)
```

**One-shot pip install + run** (when no Makefile target exists):

```bash
docker compose exec -T web pip install --quiet pyflakes
docker compose exec -T web python -m pyflakes <changed-files>
```

The pip install is idempotent (no-op if already installed) and free in any reasonable dev image — the marginal cost is ~50ms after the first run.

## Contract-Change Sweep: When You Modify a Shared Helper's Return Type or Signature

Distinct discipline from the touched-files sweep, applies on a different trigger: **whenever you change a public-facing function's return type, parameter signature, or thrown exceptions, grep for ALL callers in the SAME commit.** Not just the most-prominent caller, not just the one you remembered, not just the one a test happened to cover. Every caller.

The single most common "wasted bugbot cycle" pattern this rule prevents: a helper changes its contract, you patch the obvious caller, ship it. Bugbot reviews the diff, spots a second caller — often in the SAME file — that wasn't updated. You fix that one, ship it. Bugbot reviews again, spots a third caller in another file. By the time you're clean, you've burned three cycles on what was one self-contained refactor.

### The grep that catches it

For the typical refactor where a JS helper or Python function changes:

```bash
# Inside a docker compose container or repo root:
grep -rn '\bfunctionName(' --include="*.js" --include="*.ts" --include="*.py"
```

For Python specifically, when the change is to a method on a class:

```bash
grep -rn '\.methodName(' --include="*.py"
```

Both should be run from the project root, not the file's directory — bugbot will catch any caller anywhere in the repo, so the sweep needs the same scope.

### What counts as a contract change worth sweeping

- **Return type changes**: `return undefined` → `return Promise.reject(...)` (any sync→async return). Callers without `.catch()` now leak unhandled rejections. Callers without `await` see different behaviour.
- **Throwing where the caller didn't expect**: a previously infallible function now raises. Wrap-checking callers crash in production.
- **Default parameter changes**: a previously optional positional now required. All call sites without explicit pass-through silently regress.
- **Async-ifying a sync function**: callers that ignored the return value now silently complete out-of-order, races appear in tests intermittently.
- **Removing a side effect**: callers that depended on the side effect (DOM mutation, log emission, cache invalidation) silently degrade.

### What does NOT need the sweep

- Pure additions: a new optional kwarg, a new return field on an existing dict-shaped return. Callers ignoring the new surface are unaffected.
- Internal refactors that don't cross the function boundary: renaming a local variable, changing the implementation while keeping the signature + return type identical.
- Adding logging / metrics that don't alter return value or exception shape.

### When the sweep finds many callers

If grep returns >5 callers and they're all in the project, judgement call:

- **All in one file or one tight cluster**: handle in the same commit as the contract change. One reviewable diff, atomic semantics.
- **Spread across many files / apps**: ship the contract change in commit N with a backwards-compat shim (the helper returns BOTH the old shape AND the new shape, callers on the old path keep working); ship the per-caller updates in commits N+1...N+M; remove the shim in commit N+M+1. The shim window prevents an N-file PR from blocking on per-file review feedback.

## Defensive-Code Sweep: Verify Against the Producer's Write Site, Not the Read Site

Sibling to the Contract-Change Sweep, fires on a different trigger: **whenever you add a defensive code path that reads a field, method, or attribute, grep for the WRITE site of that field in the producer code BEFORE shipping the defense.** If grep returns zero writes, the field doesn't exist — your defensive code is a phantom-field guard whose condition is permanently `undefined`.

The failure mode: a defensive `if (state.someField)` or `try { state.someField.method() }` reads a field that was renamed, never existed, or lives on a different object than the author assumed. The guard appears to work — the field is always falsy, so the defensive branch always fires. Its "recovery" action (reload, retry, fallback) then masks any deeper bug that would otherwise have surfaced. The phantom-field typo is invisible during manual smoke (the recovery hides it), and the masked underlying bug surfaces only when the defense is later investigated for retirement — at which point both findings land together and look causally connected when they're independent.

### The grep that catches it

```bash
# Whatever field your defensive code reads — grep the producer's source for the WRITE site.
grep -rn '\b<fieldName>\s*=' <producer-module>/   # JS / Python assignment
grep -rn '\b<fieldName>\b' <producer-module>/     # widen if assignment uses computed keys
```

For object properties on a JS module-level store / Alpine store / class instance, search for the constructor / initialiser that creates the object literal:

```bash
grep -B 2 -A 20 'Alpine.store(.<storeName>' <module>/static/<module>/js/
```

Read every key in the literal. If the field your defense reads isn't there (and isn't ASSIGNED in any code path), the field doesn't exist — either find the correct key (the actual one in the producer's literal) or remove the defense if no real failure mode requires it.

### When this sweep especially matters

- Adding any `try` / `catch` whose `try` body reads a field you didn't author (the catch silently swallows `TypeError: Cannot read property X of undefined`).
- Adding any `if (obj.field)` guard where `obj` comes from a different module / store / library.
- Refactoring a producer that renames internal fields — every consumer's defensive guard now reads a stale name. The rename-before-drop discipline catches the call sites; this rule catches the field accesses.
- Diagnostic logging that reads state from another module (`console.log('frames:', store.frames)` — if `frames` was renamed to `stack`, the log always prints `frames: undefined` and the diagnostic appears to confirm that "frames is empty" when actually the field doesn't exist).

## Touched-Suite Sweep: Fix Pre-Existing Failures in Suites You Run

Sibling to the dead-imports sweep, applies to a different artefact: **whenever you run a test suite (full or partial) for any reason and observe a pre-existing failure that's unrelated to your current change, FIX IT in the same PR.** Do not file it as "out-of-scope" or "pre-existing — not my problem". The cost calculus is identical to the dead-imports sweep: a test failure that's known but not fixed becomes either (a) a habituation point where the team learns to ignore failures, or (b) a noise-floor that masks real regressions on the next PR.

### When this fires

- Running `make test` to verify YOUR change doesn't break anything, and the report shows N failures, of which M were already failing on the parent branch BEFORE your change.
- The forward-merge of an upstream branch surfaces failures that weren't visible when the upstream PR landed (the upstream PR's test pass was on a pre-merge branch state; post-merge state combines with your branch and reveals the gap).
- A bugbot review reports findings on tests that were already failing — bugbot doesn't distinguish "your fault" from "pre-existing" and neither should you.

### The rule

If the suite reports M pre-existing failures and N new failures from your change:

1. Triage all M+N failures together. Don't draw a "mine vs theirs" boundary.
2. For each pre-existing failure, identify the actual cause (look at the source, the test, the commit that introduced the change that broke the test).
3. Fix or update each test in the SAME PR as your work. If the test is broken because its EXPECTED constant was never updated after a related refactor, update the EXPECTED constant. If the test's contract is genuinely obsolete (the behaviour it asserts was intentionally retired), delete the test with a one-line commit message explaining why.
4. The commit message for the test fixes should attribute the introducing change ("Pre-existing failures from IDEA-XXX refactor — EXPECTED constants weren't updated alongside the source change") so future readers understand the recovery story.

### Why this matters

- **Habituation**: a known-failing test that ships green-on-PR-because-CI-doesn't-run-it (or red-but-ignored) trains the team to ignore red. The next genuine regression hides behind the same dismissal.
- **Bisect-poisoning**: if you ship code while pre-existing tests are red, `git bisect` against a future regression can't distinguish "this commit introduced the failure" from "the failure existed all along".
- **Reviewer confusion**: a reviewer who sees N failures on a PR's CI run can't tell which N-K are your responsibility. The reviewer either approves blind or asks you to attribute, neither of which scales.
- **Compound interest**: every PR shipped with M pre-existing failures grows the noise floor by M (unless someone happens to fix the failure as a one-off). The dominant strategy if everyone follows this discipline is to monotonically decrease the failure count.

### Anti-pattern

❌ "These 4 failures are pre-existing — I'll file a follow-up issue and continue with my work."

This is the noise-floor growth path. The follow-up issue rarely ships because it's not attached to a feature delivery cycle. Other engineers see the same failures on their PRs and apply the same dismissal. Six months later the test suite has 40 known-failing tests that nobody trusts.

The correct response, even when the failures are genuinely unrelated to your work: triage and fix in your PR, attributed to the introducing change in the commit message. The cost is bounded (typically 5-30 minutes per pre-existing failure once the diagnosis is in hand); the benefit compounds.

## Scope: Touched Files, Not Just New Edits

When pyflakes flags pre-existing dead imports / unused locals in a file you're editing, **clean them up in the same commit** (or a separate `chore(tests):` commit if the diff would otherwise be confusing). Pre-existing findings in touched files are in scope, not out of scope.

The reasoning: leaving known dead code in a file you just touched is a "loose end". The cost is one more pyflakes sweep + a small commit; the win is the file being clean for the next person who opens it. Side effect: makes the file behave with `--sweep` / `--unused-import-strict` linting modes that future projects might enable.

**Threshold**: ≤ ~10 mechanical edits → roll into the current PR. > 10 → separate cleanup PR (don't balloon the current PR's diff with unrelated cleanup).

## Why This Matters

### The bugbot-cycle math

Bugbot (or any equivalent code-review bot) takes 3-10 minutes per review cycle: comment posted → fetch via API → triage → apply fix → push → bot re-reviews. A 1-second pyflakes sweep that catches the same finding eliminates that cycle entirely.

For a multi-cycle bugbot loop on a single PR, every avoided cycle compounds: each saved cycle reduces wall-clock time by 3-10 min AND reduces context-window cost AND avoids billing the code-review bot.

### Trivial findings dominate the no-progress-loop budget

The bugbot-loop's no-progress detector treats every category-attempt as a budget hit. A trivial dead-import finding consumes the same per-category counter as a substantive bug. Pre-sweeping trivial findings keeps the budget free for the actual subtle bugs bugbot catches.

### "Is this commit obviously sloppy" — not "is this commit perfectly clean"

Don't go deeper than this — full ruff / mypy passes are PR-time / CI-time concerns, not per-commit. The sweep is the minimum bar for "nothing obviously broken"; anything beyond is the reviewer's / CI's job.

## Anti-Patterns

- ❌ "It'll get caught in CI / by bugbot eventually" — yes, and each catch is a 3-10 minute cycle. The sweep is 1 second.
- ❌ Skip-on-pre-existing — if the file has 5 dead imports and you add a 6th, fixing only the 6th leaves the file in the same state. Sweep all 6.
- ❌ Run pyflakes from inside an IDE that lints on save — sometimes works, sometimes doesn't, depends on Python interpreter resolution + venv config. The container-side run is authoritative because it matches what bugbot's review will see.
- ❌ Suppress with `# noqa: F401` when the import is actually dead — that's masking the issue, not fixing it. Suppress only when the import has a side effect (e.g. registers a Django app's signal handlers via import-time code).

## Relationship to Other Rules

- [`RULE_git-safety`](RULE_git-safety.md) — the sweep runs on the feature branch before push; doesn't change branch policy.
- [`RULE_rename-before-drop`](RULE_rename-before-drop.md) — sweeps also catch leftover imports after a rename (the dropped symbol's import stays, pyflakes flags it).
- The bugbot-loop skill (where it exists) should run pyflakes self-sweep between Phase 2 and Phase 3 as a built-in step.

---

**Last Updated**: 2026-05-16
