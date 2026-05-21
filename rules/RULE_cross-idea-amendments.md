# RULE_cross-idea-amendments

## Shipped IDEAs are not stones — amend freely as conditions change

When a later IDEA's work needs to modify a shipped earlier IDEA's files (CSS, JS, templates, config, models, anything), **do it**. No size caps, no single-file rules, no "amend only if narrowly justified" gates. Shipped code is not immutable.

The only invariant: **bidirectional documentation** — the change must be discoverable from BOTH the amending IDEA's archive AND the amended IDEA's archive.

Concrete examples of when this fires, the "why" framing, and anti-patterns (re-opening original branch, filing supersedes, silent amendments) live in [`references/RULE_cross-idea-amendments-rationale.md`](references/RULE_cross-idea-amendments-rationale.md).

## When this rule applies

Any time a current IDEA's commit modifies a file whose primary author was a *shipped* IDEA (status: complete, merged into the protected branch). Does NOT apply to bug fixes within the original IDEA's PR cycle, or routine sustaining work (deps, security patches).

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
4. **Surface in `/compound`** if the amendment pattern is itself reusable (rare — most amendments are one-offs).
