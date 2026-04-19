# Emitted templates — cross-project portability of relative paths

Rules for skills that emit markdown templates which get written into consuming projects. Load on demand when authoring or reviewing any skill whose `assets/*.md` includes relative links that the agent will substitute into an output file.

## The rule

**When a skill supports multiple source-file locations, never hardcode relative paths in the template the skill emits. Compute the path from the source's actual location at emit time, parameterise the template with a placeholder, and document a worked-examples table covering the common cases.**

A hardcoded path works for exactly one source location. Every other supported location — root-level, nested deeper, different parent directory — produces a broken link in the emitted file.

## Why this matters

Skills like `/ingest-backlog` operate on source files whose location varies per project. Step 1 of a well-designed skill explicitly enumerates the supported locations (repo root, `docs/`, `docs/execution/`, `docs/planning/`, etc.). Later steps that write stub files, index entries, or cross-reference pointers inherit the same location ambiguity. If the skill's template uses `../foo/` or `./bar/`, the link resolves correctly in only one of the enumerated locations.

The failure mode is silent: the emitted file is valid markdown, the skill reports success, but when a human or another agent follows the link they land outside the project root or on a nonexistent sibling directory. The bug surfaces only when someone clicks through, often long after the emit happened.

## ✅ DO — parameterise + derive + document

Pattern: skill defines placeholders in the template, documents how to compute them, and shows worked examples.

```markdown
Stub template (substitute `<IDEAS_REL>` + `<INDEX_REL>` + `<ORIGINAL_FILENAME>`):

\`\`\`markdown
# <ORIGINAL_FILENAME>

This file was split into per-idea files under [`docs/ideas/`](<IDEAS_REL>).
See [`docs/ideas/README.md`](<INDEX_REL>) for the index.
\`\`\`

Derivation rule:
- `<IDEAS_REL>` = `os.path.relpath(<project>/docs/ideas, dirname(source_file))`
- `<INDEX_REL>` = `<IDEAS_REL>/README.md`

Worked examples:

| Source file | `<IDEAS_REL>` | `<INDEX_REL>` |
| --- | --- | --- |
| `IDEAS.md` (repo root) | `docs/ideas/` | `docs/ideas/README.md` |
| `docs/IDEAS.md` | `ideas/` | `ideas/README.md` |
| `docs/execution/IDEAS.md` | `../ideas/` | `../ideas/README.md` |
```

## ❌ DON'T — hardcoded relative path

```markdown
Stub template:

\`\`\`markdown
# IDEAS.md

This file was split into per-idea files under [`docs/ideas/`](../ideas/).
See [`docs/ideas/README.md`](../ideas/README.md) for the index.
\`\`\`
```

Problems:

- `../ideas/` resolves outside the project root when source is `IDEAS.md` at repo root.
- `../ideas/` points to a sibling `ideas/` (not `docs/ideas/`) when source is `docs/IDEAS.md`.
- Only works when source is exactly `docs/<anything>/IDEAS.md` — a narrow subset of the skill's supported inputs.

## Checklist before committing a skill that emits templates

Before merging a skill whose `assets/*.md` contains relative links:

- [ ] Does the skill's step 1 enumerate multiple source-file locations? (If yes, continue; if no, this rule doesn't apply.)
- [ ] Are all relative paths in emitted templates written as placeholders (`<NAME_REL>` or `{{name_rel}}`)?
- [ ] Does the skill body document the derivation rule for each placeholder (e.g. "compute as relative path from source's directory to the target")?
- [ ] Is there a worked-examples table covering at least the three most common source locations (root, `docs/`, `docs/<subdir>/`)?
- [ ] For the identified most common case, does the example match what a human would manually write?

Miss any box → fix before merging.

## Origin

Captured from mind-vault PR #42 bugbot finding F1 (2026-04-19) on `skills/ingest-backlog/SKILL.md:103`. The original template hardcoded `../ideas/`, which worked for teisutis's `docs/execution/IDEAS.md` but would have broken the first non-teisutis brownfield takeover.

Promoted into skill-writer via `/compound` because the underlying lesson is broader than the one skill that triggered it: any future skill with emitted templates faces the same ambiguity, and the skill-authoring meta-standard is the right place to prevent the next instance.

---

**Last Updated**: 2026-04-19
