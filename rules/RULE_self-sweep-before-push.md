# RULE_self-sweep-before-push

Before `git commit` on any cycle that touches Python or JS source — **or makes substantial doc/markdown changes** — run a brief self-sweep on every file edited this cycle. The sweep catches the same trivial findings any review bot will catch — 1 second locally vs a 3-10 min (billed) bot round-trip.

Grep recipes, full Why-This-Matters discussion, edge cases, and the Pyflakes Pipe Pattern live in [`../docs/rules/RULE_self-sweep-before-push-rationale.md`](../docs/rules/RULE_self-sweep-before-push-rationale.md). Load on first encounter or when adjudicating an edge case.

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

**A guard that *selects* rows to hand to a downstream consumer must replicate the consumer's FULL acceptance predicate — not the subset a plan or architect review named.** When you write a resolver/filter that picks "valid"/"openable"/"eligible" rows for some consumer (a view, a redirect target, a handler), the selection predicate is a claim about *everything the consumer will accept*. If the consumer rejects on conditions your selector didn't replicate, it bounces the row — and when that bounce re-feeds your selector (redirect back, retry, re-query), you get an **infinite loop or a silent drop**, not a clean error. The trap: a design doc or architect pass names *some* of the consumer's conditions (e.g. "exclude null foreign keys"), you encode exactly those, tests pass, the review nods — but the consumer's real code also requires, say, an `is_enabled`/`is_active`/status check the doc never enumerated. **Validate the selector against the consumer's actual acceptance code, not the plan's prose summary of it**: open the consumer, read every branch that can reject/redirect the row, and mirror all of them. A reviewer (bot or human) reading the consumer's source — not the plan — is what catches this; happy-path tests where every row satisfies every condition cannot.

### 4. Touched-suite sweep (when you run a test suite)

When `make test` reports pre-existing failures unrelated to your change, fix them in the SAME PR. Do not file as "out-of-scope". Habituation, bisect-poisoning, and reviewer-confusion costs → rationale doc.

### 5. Doc-consistency sweep (doc-heavy commits)

When a commit carries substantial doc/markdown changes (IDEA files, ideas index, plan docs, devlogs) — **even alongside code** — sweep the consistency class bots flag one-nit-per-cycle: (1) frontmatter `related`/`depends_on`/`supersedes` ↔ body prose symmetry, every id and every edge; (2) every id in an ordering/recap block has an index-table row; (3) count/range claims match the listed set; (4) domain-terminology precision (e.g. shared-schema vs per-tenant); (5) PR-description ↔ final-diff drift; (6) frontmatter formatting matches repo convention; (7) US-English spelling and metric/SI units in anything newly written, per [`skills/skill-writer/references/LANGUAGE_CONVENTIONS.md`](../skills/skill-writer/references/LANGUAGE_CONVENTIONS.md) — fix drift only in files this change already touches, never released CHANGELOG sections or archived docs. Grep recipes + detail → rationale doc.

### 5a. Anchor sweep — an "insert before X" written as a string replace DELETES X

Editing docs programmatically, `content.replace(ANCHOR, NEW)` inserts before the anchor **only if
`NEW` ends with `ANCHOR`**. Omit that and the heading is consumed: its body survives, reads as a
trailing continuation of whatever was inserted, and the document renders perfectly. Nothing errors,
no link breaks, and the section is gone. Measured — a compound that added a numbered item swallowed
the `## Stance` heading below it; a review caught it, the sweep had not.

⚠️ It is the mistake most likely to be made by someone being careful, because the anchor is chosen
precisely for being a stable landmark, i.e. a heading. And it hides in a diff: the removed line sits
at the top of a large green block.

Mechanical check, cheap enough to run on every doc-heavy commit — compare the heading set, don't
eyeball the diff:

```bash
git diff --name-only origin/main...HEAD -- '*.md' | while read -r f; do
  git show "origin/main:$f" 2>/dev/null | grep '^#' | sort > /tmp/h-before
  grep '^#' "$f" | sort > /tmp/h-after
  lost=$(comm -23 /tmp/h-before /tmp/h-after)
  [ -n "$lost" ] && printf '%s DROPPED:\n%s\n' "$f" "$lost"
done
```

A dropped heading is almost never intended; when it is, it shows up here and you confirm it once.

### 5b. Reversal sweep — when a 🔴 becomes ✅, the WIN is what goes unswept

Closing a gap is a correction like any other, but it does not feel like one, so nobody greps for the
old claim. Measured: a certificate store gained an off-box backup; the documents open at the time
were corrected and nothing else was. **Four days later two live guides still stated the gap as
present** — including, under a red heading as the *first named gap*, the page a person reads **while
the system is broken**. That is the worst possible carrier: it invites someone mid-incident to go
build a thing that already exists, or to read a solved problem as the cause of the outage.

When a status flips to resolved, grep the **old vocabulary** — the words the gap was described in,
not the words of the fix — and sweep in this order:

1. **`guides/` and every `.html`** first. These are the read-under-pressure surfaces and the least
   likely to be open in the editor when the fact changes.
2. Live reference/index docs.
3. Standing reminders inside archives — a 🔔 marker is a live imperative wearing an archive's clothes.
4. Auto-memory: the note recording the win frequently still carries the pre-win claim in its own
   body. Both halves are in one file and only one of them gets updated.

⛔ **Correct in place with a strikethrough; do not delete.** The reader needs to see that the claim
changed, and dated archives keep their snapshot. And carry the half that is *still* true — "backed
up, restore never drilled" is the sentence those guides should have had all along; deleting the
warning outright would have lost it.

## Sweep integrity — an `--include` allow-list makes a sweep silently under-report

When a sweep's job is to prove **absence** or **completeness** — "no references remain", "exactly N sites corrected", "nothing else calls this" — do **not** filter by file extension. `grep -rn "PATTERN" --include='*.py' --include='*.md' .` answers *"hits in the files I thought to look at"* and presents that as zero. Config templates (`.env.*.example`), dotfiles, extensionless scripts, CI YAML under an unexpected name, and generated manifests match no source-code glob. Exclude **directories** instead — a false positive from `vendor/` costs a glance; a false negative ships:

```bash
grep -rn "PATTERN" --binary-files=without-match \
  --exclude-dir=vendor --exclude-dir=node_modules --exclude-dir=.git .
```

Observed: a dead-file removal swept with an extension allow-list, concluded "exactly five live references", and wrote that count into four documents. Two more lived in `.env.*.example` templates. A review bot found them — precisely the billed cycle this rule exists to prevent, and trigger 5's count-claim check (3) could not have caught it, because the count *did* match the (under-reported) listed set.

The general form: **a negative result is a claim about your search, not about the repo.** Before writing "none remain" or a specific count, ask what the search could not see.

### The check must not inherit the edit's blind spot

The sharpest form of that: when you verify a bulk edit, **the verification must not be built from the same assumption as the edit**. A case-sensitive replace-all followed by a case-sensitive `grep` re-runs one blind spot twice — the survivors are invisible to both, so the check reports success *because* it missed the same thing. Observed: a UK→US spelling fix replaced every `organisation`, verified with `grep -n 'organi'`, and shipped an untouched `ORGANISATION` in an emphasized rule line; the reviewer found it one cycle later. Same shape for a whole-word `\b` pattern over hyphenated compounds, and for a fixed-string `grep -F` over text the edit reflowed.

So verify **wider than you edited**: `grep -rniE` (case-insensitive, extended) for the stem, over the whole directory rather than the touched file. Widening costs a few false positives to read; sharing the edit's blind spot costs a billed review cycle and a false "done".

Related: fixing the instance a reviewer reported without re-running a check that spans the whole **class** leaves the siblings for the next cycle. When a finding names a defect your own edit pattern produced (a stranded line-wrap, a half-renamed term), assume there are more and sweep for the pattern before pushing.

**The scoping trap this rule walks into by construction:** a sweep script that derives its file list from `git diff --name-only <base>...HEAD` sees **committed work only**. This is a *pre-commit* rule, so at the moment it runs, the very changes it exists to check are usually still unstaged — and the sweep prints a tidy "clean" for files it never opened. Measured: a sweep written this way listed two touched files and passed, while two more sat edited in the working tree. Scope a pre-commit sweep to `git diff --name-only <base>` (two-dot, working tree included) or `git status --porcelain`, and sanity-check the printed file list against what you know you edited before believing any "clean" it reports. The file list is part of the output, not scaffolding: a sweep that cannot show you the right files has not swept.

## When This Applies

- Every commit on a feature branch that touches `.py` or `.js` source.
- Any commit whose message, PR body, or docs assert **absence or a count** ("no remaining callers", "all N sites updated") — the sweep behind the claim must not be extension-filtered.
- Every commit that is **doc-heavy** (substantial IDEA / index / plan / devlog markdown), even when it also carries code — trigger 5.
- Mandatory before push if a review bot (code or doc) is wired up to the PR — saves an entire billed bot cycle per trivial finding.
- Especially valuable inside `review-loop` skills: between Phase 2 (apply edits) and Phase 3 (commit + push + retrigger).
