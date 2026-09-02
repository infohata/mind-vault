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
- The repo still contains substantial pre-existing UK spelling. That is a known, dateless
  inconsistency — note it, leave it, and pick up a repo-wide sweep deliberately as its own PR,
  never as a tail-end addition to unrelated work.

### Which half of that rule applies: count both forms first

The two bullets above pull opposite ways on the same finding — "fix drift in files you touched"
against "leave the pre-existing pile" — and a reviewer flagging a UK spelling in a file you just
edited lands exactly on the seam. **Decide by counting both forms repo-wide, not by which
language the word is in:**

- **US form already dominates** ⇒ the UK spellings are genuine drift against a settled majority.
  Fix them in the file you touched. (Measured: `organisation` 5 vs `organization` 21 — and 3 of
  the 5 sat in one touched file, one of them inside prose that change had authored.)
- **UK form dominates** ⇒ this is the known pile, not drift. Leave it. (Measured: `artefact` 237
  vs `artifact` 79; `behaviour` 173 vs `behavior` 74; `catalogue` 68 — and `artefact` is
  load-bearing in paths like `skills/artefact-retrieval/`, so it is a rename, not a spell-fix.)

The count is the whole test, and it is two `grep -roc` runs. Without it the call is a coin-flip
you have to re-argue with every reviewer: a review engine correctly observing "two variants in
one document" is right about the observation and cannot know which direction resolves it — in a
UK-dominant term it will ask you to regress correct new text, which is how the pile grows.
**New prose is always US-spelled regardless** (rule 1); dominance decides only whether you also
move the *old* text around it.

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
