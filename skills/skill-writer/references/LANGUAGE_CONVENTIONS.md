# Language conventions — US English spelling, metric measurement

The house register for everything authored **inside mind-vault**: skills, rules, references, agent
profiles, commands, CHANGELOG entries, IDEA and plan docs, PR bodies.

## The two rules

1. **Spelling: US English.** `behavior`, `color`, `flavor`, `favor`, `honor`, `defense`, `gray`;
   `-ize`/`-ization` for the verb family (`organize`, `serialize`, `normalize`, `optimize`,
   `initialize`, `generalize`, `recognize`, `categorize`); `while` not `whilst`, `among` not
   `amongst`.
2. **Measurement: metric / SI, temperature in Celsius.** Metres, kilograms, litres, kilometres,
   °C. Never convert a metric source figure to imperial for the reader's benefit; if a source is
   imperial (a vendor spec, a third-party API field), quote it as given and put the metric
   equivalent alongside rather than silently converting.

They are independent axes and the combination is deliberate — American spelling is the register
technical writing is *read* in, metric is the system the work is *done* in. Neither implies the
other.

## Why US spelling specifically

The ecosystem's own identifiers are already US-spelled: `serialize`, `initialize`, `color`,
`normalize`, `behavior` appear as API names, CSS properties, and config keys across every stack
these skills cover. Prose that spells them the other way puts two spellings of the same word on
one page — the drift a review engine eventually flags, which is how this convention got written
down. Matching the identifiers removes the split.

## Scope, and what NOT to rewrite

- **Applies to** content authored in this repo, going forward.
- **Does not apply to** content a skill generates *for a consuming project* — follow that
  project's existing convention there; a skill that imposes mind-vault's house style on someone
  else's codebase is a bug.
- **Never rewrite historical records to match**: released `CHANGELOG.md` version sections,
  archived IDEA/plan docs, and merged devlog entries record what was written at the time. Fix
  drift only in files the current change already touches.
- **A term quoted from an untouched file moves with that file, not with the pointer.** When a
  touched file's drift is a domain term it is echoing from a reference you did not touch (a
  References one-liner naming the target's own vocabulary), leave both alone. Changing only the
  pointer desyncs it from its source; changing both drags an untouched file into an unrelated
  change. The term gets fixed when its owning file is next edited, and the pointer follows.

  **Establish the echo before invoking this — do not assume it.** Grep the target file for the
  exact spelling first. Target contains it ⇒ genuine echo, leave both. Target does not contain it
  (already fixed, or never used the term) ⇒ the pointer is quoting nothing, so it is ordinary
  drift in a file you touched and the rule above applies: fix it. Skipping this check turns a
  narrow exception into a blanket exemption for every UK-spelled References line.
- The repo still contains pre-existing UK spelling. That is a known inconsistency — note it,
  leave it, and pick up a repo-wide sweep deliberately as its own PR, never as a tail-end
  addition to unrelated work. **Status (2026-09-02):** the three biggest terms —
  `behaviour`, `catalogue`, and `artefact` used as a common noun — were swept in exactly such
  a PR; the live surface now reads `behavior` ~195 / `behaviour` ~4 and `catalog` ~93 /
  `catalogue` ~4, where every survivor is this file's own quoted examples. What is left is
  a **tail of ~20 smaller terms** (`centre` ~44, `normalis*` ~28, `honour` ~25, `recognis*`
  ~20, `cancelled` ~18, `initialis*` ~18, `serialis*` ~16, `defence` ~15, `optimis*` ~13, …),
  still governed by the leave-it default until their own PR.

### Which half of that rule applies: count both forms first

The two bullets above pull opposite ways on the same finding — "fix drift in files you touched"
against "leave the pre-existing pile" — and a reviewer flagging a UK spelling in a file you just
edited lands exactly on the seam. **Decide by counting both forms repo-wide, not by which
language the word is in:**

Count **occurrences, not matching lines** — `grep -c` (and `-rc`) reports one per line however
many hits that line holds, which undercounts dense reference prose and can flip a close call:

```bash
grep -roi 'artefact' --binary-files=without-match --exclude-dir=.git --exclude-dir=node_modules . | wc -l
grep -rci 'artefact' --binary-files=without-match --exclude-dir=.git --exclude-dir=node_modules . | awk -F: '{s+=$2} END {print s}'
# occurrences run ~18 ahead of matching lines here — that many lines carry the term twice
```

Three flags carry weight, and dropping any one skews the ratio in a way you cannot see:

- **`-i`** — headings, sentence starts and emphasized rule lines are Title- or UPPER-case.
  Case-sensitive counting misses ~18 `artefact` and, worse, **17 of ~44 `organization`** here.
  (This is § *The check must not inherit the edit's blind spot* pointed at a count.)
- **`-o`** — `-c` alone counts matching *lines*, so a line holding a term twice reports one.
- **`--exclude-dir`, never `--include='*.md'`** — this is a count, so § *Sweep integrity*
  applies; measured before the 2026-09-02 sweep, the extension allow-list under-reported
  `behaviour` 174 → 184 and `artifact` 83 → 85 once removed.

- **US form already dominates** ⇒ the UK spellings are genuine drift against a settled majority.
  Fix them in the file you touched. (`organisation` ~7 vs `organization` ~42 — when this call
  was actually made the split read 5 vs 21 under a case-sensitive count, with 3 of those in one
  touched file, one inside prose that change had authored. Same verdict, better numbers. Since
  the 2026-09-02 sweep, `behaviour` ~2 vs `behavior` ~194 and `catalogue` ~2 vs `catalog` ~89
  sit firmly on this side too.)
- **UK form dominates** ⇒ this is the known pile, not drift. Leave it, and let its own PR clear
  it. The tail listed in § *Scope* is what currently qualifies (`centre`, `honour`, `defence`,
  the `-is*` families).

**A term can be neither, because it is a name.** `artefact` reads UK-dominant (~170 on the live
surface) only because `skills/artefact-retrieval/` and `docs/artefacts/` are **directories** —
one of them a published slash command. Those are identifiers, so the identifier exemption above
already covers them, and no count decides them: renaming a shipped command is a compatibility
cliff needing [`RULE_rename-before-drop`](../../../rules/RULE_rename-before-drop.md), not a
spelling pass. The 2026-09-02 sweep therefore fixed `artefact` as a common noun everywhere else
and deliberately left those two trees internally consistent with their own names. **Before
counting, ask whether the term is a word or a name** — if a directory, command, or public
symbol carries it, the count is measuring the name and will point you at a rename you did not
intend to make.

Treat those figures as a dated snapshot, not a constant — they drift with every release, and the
**ratio** is the signal, not the absolute number. Re-run the count rather than trusting them.

Without the count the call is a coin-flip you have to re-argue with every reviewer: a review
engine correctly observing "two variants in one document" is right about the observation and
cannot know which direction resolves it — on a UK-dominant term it will ask you to regress
correct new text, which is how the pile grows. **New prose is always US-spelled regardless**
(rule 1); dominance decides only whether you also move the *old* text around it.

## Sweeping without breaking things

- `analysis` / `analyses` are correct US English — the single most common false positive in any
  `-ise`/`-yse` grep.
- **Check for code identifiers before replacing.** Prose hits are usually safe because the APIs
  are already US-spelled, but a UK spelling inside a code fence, a config key, a filename, or a
  quoted error string is content, not style — leave it.
- Prefer directory-excludes over an extension allow-list when proving a sweep is complete
  ([`RULE_self-sweep-before-push`](../../../rules/RULE_self-sweep-before-push.md) § sweep
  integrity) — a negative result is a claim about your search, not about the repo.

## Adjacent conventions already in force

- **Dates: ISO `YYYY-MM-DD`**, everywhere — frontmatter, CHANGELOG markers, archive directory
  names, devlog headings. Never locale-ordered forms; `03/04` is ambiguous across exactly the two
  audiences this repo spans.
- **Times: 24-hour**, UTC when a timestamp crosses machines (CI runs, review timestamps).
