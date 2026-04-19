# Bugbot-finding ingest

Parsing rules for `/bugbot-loop` output when it's supplied as the `/compound` input source. Load on demand when step 1 selects a bugbot file as input.

## Source file shape

`/bugbot-loop` writes its run artifact to a project-local location (typical: `<project>/.bugbot-loop/<run-id>/findings.md` or a similar path — projects may vary). Check `commands/bugbot-loop.md` in mind-vault for the exact convention.

Typical findings file structure:

```markdown
# Bugbot loop run <run-id>

## Findings

### Finding 1
- **Category:** N+1 query / security / architecture / testing / ...
- **Severity:** critical | major | minor
- **File:** <repo-relative-path>:<line>
- **Description:** <one-line summary of the issue>
- **Fix applied:** <commit SHA + one-line summary>
- **Reviewer verdict:** cleared | deferred | rejected

### Finding 2
...
```

Not every bugbot-loop writes in this exact shape — be tolerant of minor variants. Grep for `### Finding`, `Category:`, `Severity:`, `Fix applied:` heuristically.

## What makes a finding compound-worthy

Compound-worthy findings generally meet ≥ 2 of these:

- **Recurring category.** The finding category (N+1, tenant leakage, format-html migration drift, etc.) has appeared in prior bugbot runs on this project, OR in `docs/solutions/` on any project.
- **Cross-project applicability.** The cause is not a one-off — it's a pattern any Django / Celery / HTMX project could hit.
- **Non-obvious.** A careful implementer might reasonably miss it the first time.
- **High-severity.** Critical or major findings have higher compound value than minor.

Not compound-worthy:

- Typos in comments.
- Pure style issues already caught by linters.
- Fixes that are obvious from the error message.
- One-time data migrations with no reusable lesson.

## De-duplication against prior compound output

Before routing a finding, grep:

```bash
# Check project-local solutions
rg -l "<keyword>" <project>/docs/solutions/

# Check mind-vault — where the learning might already live
rg -l "<keyword>" ~/projects/mind-vault/skills ~/projects/mind-vault/rules ~/projects/mind-vault/agents
```

If a prior match exists:

- **Extend it** — add the new finding's variant as a bullet under the existing entry, rather than writing a fresh solution doc.
- **Promote it** — if the same finding is captured in ≥ 3 project-local solution docs with no mind-vault entry, that IS the promotion trigger. Write a mind-vault skill/rule/agent update referencing all three prior solutions.

## Grouping related findings

Bugbot often produces multiple findings that share a root cause. Group them:

- Same file + same category + same session → one compound entry with all findings listed.
- Different files, same pattern (e.g. three N+1 queries in three different ViewSets) → one compound entry noting "appeared in X, Y, Z — pattern: …".
- Distinct root causes → separate compound invocations.

The grouping is mechanical: re-read each finding's Category and Description, group those that share at least the Category.

## Routing findings through Shape-C

For each compound-worthy finding (or group):

1. **Narrative probe** as normal — most bugbot findings route to mind-vault agent passes or skill updates because bugbot's reviewer persona caught them. That's the pattern's natural home.
2. **Taxonomy quiz** fallback as normal.
3. **Cite the finding** in the destination file's provenance section: "Captured from bugbot-loop run `<run-id>` on PR #<n>."

## Ingest mode invocation

The skill can be invoked specifically for bugbot ingest:

```text
/compound --bugbot-file <path>
/compound from PR #123 bugbot review
```

In ingest mode:

- Skip step 1's interactive prompt ("what did you learn?"); read the file directly.
- Walk each finding; apply the compound-worthy filter.
- Route each finding (or group) through the Shape-C probe individually.
- One commit per routed finding (not per invocation). Several findings may land in one `/compound` session as several commits on the same branch.

## When bugbot output is unavailable

If the findings file is missing or malformed:

1. Ask the user to point at the correct path.
2. Fall back to interactive mode (step 1's "what did you learn?" prompt).
3. Never try to reconstruct findings from git log — that's an anti-pattern; the findings file is the authority.

---

**Last Updated**: 2026-04-19
