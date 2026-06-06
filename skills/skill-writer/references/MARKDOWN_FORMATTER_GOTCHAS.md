# Markdown formatter gotchas

Auto-formatters (mdformat for skill/reference repos, markdownlint-cli2 `--fix` for doc-heavy repos — never prettier, it corrupts code spans) reflow markdown to a canonical shape. Most of the time that's a no-op improvement. A few constructs get *silently rewritten in a way that changes meaning* — these are the ones to author defensively against, because the corruption passes the formatter's own idempotency check and only a human (or a review bot) notices the broken render.

## A literal `+` / `-` / `*` at the start of a wrapped prose line becomes a list item

The trap, surfaced on a real PR: a soft-wrapped sentence had a continuation line beginning with `+ explicit ...`:

```text
... one-commit shims (`from app.x import *`
+ explicit re-export of any cross-module privates) so every old path resolves.
```

The `+ ` (also `- ` or `* `) at column 0 is a CommonMark **list marker**. mdformat "canonicalised" it into a real list item — inserting a blank line and converting `+` → `-` — which split the parenthetical mid-sentence and broke the render:

```text
... one-commit shims (`from app.x import *`

- explicit re-export of any cross-module privates) so every old path resolves.
```

It survives a second formatter pass (now-valid list), so idempotency-checking the formatter output does NOT catch it.

**Author defensively:** never let a wrapped prose line *start* with `+`, `-`, or `*` followed by a space. Reword (`+ explicit` → `plus explicit`), join the wrap so the marker isn't at column 0, or escape it (`\+`). The reword is cleanest — it reads identically and is immune to any CommonMark formatter.

**When this bites in `/compound` and `/wrap`:** both run mdformat over touched markdown. Run the formatter, then *read the diff* (or re-render) on any file with inline `+`/`-`/`*` characters in prose — don't trust the "formatted: clean" exit code, which only means the output is now self-consistent, not that it preserved your meaning.
