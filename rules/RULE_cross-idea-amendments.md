# RULE_cross-idea-amendments

## Shipped IDEAs are not stones — amend freely as conditions change

When a later IDEA's work needs to modify a shipped earlier IDEA's files (CSS, JS, templates, config, models, anything), **do it**. Don't bound the amendment with size caps, single-file rules, or "amend only if narrowly justified" gates. Don't treat shipped code as immutable.

The only invariant: **bidirectional documentation** — the change must be discoverable from BOTH the amending IDEA's archive AND the amended IDEA's archive.

## Why this rule exists

The cost of preserving a shipped decision past its useful life is higher than the cost of revising it cleanly. A sprint cohort with multiple foundation-tier IDEAs (toast surface, modal primitives, drawer system, etc.) inevitably surfaces relationships that weren't visible when each IDEA shipped in isolation. Forcing every cross-IDEA touch through a separate "supersede + new IDEA" cycle adds ceremony that discourages real improvements.

The flexibility-first framing preserves the *learning loop* — when a downstream IDEA discovers that an upstream IDEA's choice no longer fits, the right response is to amend the upstream choice, not to layer workarounds on top of it. The bidirectional documentation rule keeps the trail honest so future readers can reconstruct *why* the upstream changed.

## When this rule applies

Any time a current IDEA's commit modifies a file whose primary author was a *shipped* IDEA (status: complete, merged into the protected branch). Examples:

- A modal-primitives IDEA bumps the z-index in the toast IDEA's `_toast.scss` — the relationship between the two overlays only becomes clear once both are designed together.
- A new-table-component IDEA tightens a constraint in the row-renderer IDEA's template — performance regression caught only at integration time.
- A new-translation-flow IDEA renames a translation-map function originally defined in the i18n-extraction IDEA — naming evolved as the surface grew.

Does *not* apply to:

- Bug fixes inside the original IDEA's files made by the original IDEA's author within the original PR cycle. That's normal in-PR iteration.
- Routine sustaining work (dependency upgrades, security patches) that rolls through every file regardless of which IDEA originally authored it.

## The bidirectional-documentation contract

When amending another IDEA's shipped files in scope of a current IDEA's work, ALL FOUR steps:

1. **Tag the commit message** with the amending direction:
   ```
   feat(area): IDEA-NNN — <change description>

   Amends IDEA-MMM <file:line> to support <reason>.
   ```
2. **Refresh the amended file's inline comment** to point at the amending IDEA. If the original file had a comment like `// Phase 2 — IDEA-MMM`, update it to `// Phase 2 — IDEA-MMM (amended IDEA-NNN: <one-line reason>)`. Future readers grepping the file see the amendment without leaving the source.
3. **On `/wrap` of the amending IDEA**, append a one-line backref to the amended IDEA's archive directory (its README or devlog footer if no README exists). Format:
   ```
   <file> amended <X> → <Y> by IDEA-NNN (commit <sha>) — <reason>.
   ```
   Or for a longer note, create a `YYYY-MM-DD-amended-by-idea-NNN.md` file in the amended IDEA's archive dir with a one-paragraph summary + the commit sha + a link to the amending PR.
4. **Surface in `/compound`** if the amendment pattern is itself reusable (rare — most amendments are one-offs). The cross-IDEA-amendments rule itself is the meta-pattern.

## Anti-patterns

- ❌ **Re-opening the original IDEA's branch** to make the change. The original IDEA is shipped; the change belongs in the current IDEA's commits.
- ❌ **Filing a "supersede" relationship** on the original IDEA. Amendments aren't supersessions — the original IDEA's main work is still the canonical implementation; the amendment is a tweak.
- ❌ **Spinning up a new "fix the upstream IDEA" IDEA**. That defers the fix indefinitely (small docs/refactor IDEAs rarely ship). The right place is the IDEA whose work *needed* the upstream change.
- ❌ **Silent amendments** with no commit-message tag, no inline comment refresh, no archive backref. The next reader has no way to discover the amendment exists.
- ❌ **Size caps** ("≤ N lines", "single file only"). The original draft of this rule had bounded the precedent — explicitly retired per user direction (2026-05-05): "implemented ideas are not stones".

**Last Updated**: 2026-05-05
