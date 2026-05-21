# RULE_self-sweep-before-push

Before `git commit` on any cycle that touches Python or JS source, run a brief self-sweep on every file edited this cycle. The sweep catches the same trivial findings any code-review bot will catch — 1 second locally vs a 3-10 min bot round-trip.

Grep recipes, full Why-This-Matters discussion, edge cases, and the Pyflakes Pipe Pattern live in [`../docs/rules/RULE_self-sweep-before-push-rationale.md`](../docs/rules/RULE_self-sweep-before-push-rationale.md). Load on first encounter or when adjudicating an edge case.

## The Four Sweep Triggers

### 1. Touched-files sweep (every commit)

For every file edited in the current commit's working set, check:

1. **Imports block** — every `import X` and `from X import A, B`: is each name referenced? If not, drop.
2. **Dead conditionals** — `if foo:` followed by code overwritten unconditionally a few lines later.
3. **Unused locals** — `var = something()` never read. Drop, or rename to `_` if the side effect matters.
4. **Stale comment vs code** — does the comment still describe what the code does?

Python: `python -m pyflakes <path>` catches #1 and #3 mechanically. In a docker-first project where the image lacks pyflakes, run as a one-shot:

```bash
docker compose exec -T web pip install --quiet pyflakes && docker compose exec -T web python -m pyflakes <changed-files>
```

For JS, eyeball at minimum. Scope is **touched files entirely**, not just the new diff — pre-existing dead imports in a file you just edited are in scope (threshold ~10 mechanical edits before splitting to a separate PR).

### 2. Contract-change sweep (when changing a public function's signature)

When you change a function's return type, parameter signature, or thrown exceptions, grep ALL callers in the SAME commit. The most common wasted-bot-cycle pattern is missing a sibling caller in the same file. Recipes + "what counts as a contract change" → rationale doc.

### 3. Defensive-code sweep (when adding a defensive read of someone else's field)

When you add code that reads a field on an object you didn't author (`if (state.foo)`, `try { state.foo.method() }`), grep the producer's source for the WRITE site of that field FIRST. Zero writes = phantom-field guard whose condition is permanently `undefined`. Failure-mode walkthrough + grep patterns → rationale doc.

### 4. Touched-suite sweep (when you run a test suite)

When `make test` reports pre-existing failures unrelated to your change, fix them in the SAME PR. Do not file as "out-of-scope". Habituation, bisect-poisoning, and reviewer-confusion costs → rationale doc.

## When This Applies

- Every commit on a feature branch that touches `.py` or `.js` source.
- Mandatory before push if a code-review bot is wired up to the PR — saves an entire bot cycle per trivial finding.
- Especially valuable inside `review-loop` skills: between Phase 2 (apply edits) and Phase 3 (commit + push + retrigger).
