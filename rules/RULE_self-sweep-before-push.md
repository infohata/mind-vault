# RULE_self-sweep-before-push

Before `git commit` on any cycle that touches Python or JS source — **or makes substantial doc/markdown changes** — run a brief self-sweep on every file edited this cycle. The sweep catches the same trivial findings any review bot will catch — 1 second locally vs a 3-10 min (billed) bot round-trip.

Grep recipes, full Why-This-Matters discussion, edge cases, the Pyflakes Pipe Pattern, and the **Pipeline Exit-Code Discipline** (gate on the upstream's exit, not a downstream `tee`/`grep`/`jq`) live in [`../docs/rules/RULE_self-sweep-before-push-rationale.md`](../docs/rules/RULE_self-sweep-before-push-rationale.md). Load on first encounter or when adjudicating an edge case.

## The Five Sweep Triggers

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

**A guard that *skips* or *discards* rows is itself a data-shape claim — validate it against the producer's REAL data, not a mock.** Adding `if not looks_valid(x): skip` (e.g. `int(id)` with a skip-on-failure, a regex filter, a type check) encodes an assumption about what the producer actually emits. If that assumption is wrong, the guard silently drops *every* row — often a worse failure than the bug it was meant to prevent (empty result vs loud error). Mocks are dangerous here: a unit test you wrote feeds the guard *your* assumed shape, so it passes; an architecture review reads the same assumption and nods. Only the producer's real, seeded data exposes the mismatch. Before shipping a discard/skip guard: grep the producer's write site for the field's actual shape, and check whether a sibling reader already decodes it (copy that, don't reinvent). If the data is composite/encoded, decode — don't reject. Pairs with [`RULE_rename-before-drop`](RULE_rename-before-drop.md) (partial-state left behind at phase boundaries).

### 4. Touched-suite sweep (when you run a test suite)

When `make test` reports pre-existing failures unrelated to your change, fix them in the SAME PR. Do not file as "out-of-scope". Habituation, bisect-poisoning, and reviewer-confusion costs → rationale doc.

### 5. Doc-consistency sweep (doc-heavy commits)

When a commit carries substantial doc/markdown changes (IDEA files, ideas index, plan docs, devlogs) — **even alongside code** — sweep the consistency class bots flag one-nit-per-cycle: (1) frontmatter `related`/`depends_on`/`supersedes` ↔ body prose symmetry, every id and every edge; (2) every id in an ordering/recap block has an index-table row; (3) count/range claims match the listed set; (4) domain-terminology precision (e.g. shared-schema vs per-tenant); (5) PR-description ↔ final-diff drift; (6) frontmatter formatting matches repo convention. Grep recipes + detail → rationale doc.

## When This Applies

- Every commit on a feature branch that touches `.py` or `.js` source.
- Every commit that is **doc-heavy** (substantial IDEA / index / plan / devlog markdown), even when it also carries code — trigger 5.
- Mandatory before push if a review bot (code or doc) is wired up to the PR — saves an entire billed bot cycle per trivial finding.
- Especially valuable inside `review-loop` skills: between Phase 2 (apply edits) and Phase 3 (commit + push + retrigger).
