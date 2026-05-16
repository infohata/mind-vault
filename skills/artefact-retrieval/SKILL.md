---
name: artefact-retrieval
description: Search outside the project (in IDE plans, AI agent workspaces, or temporary storage) and retrieve standalone artefacts, research, or validation logs to bring them inside the project repository.
---

# SKILL_artefact-retrieval

## Overview

IDE-agnostic pattern for retrieving valuable artefacts (plans, analyses, validation reports, research notes) that AI coding assistants generate _outside_ the project tree, and importing them into the project's `docs/artefacts/` taxonomy for permanent retention and cross-session reuse.

## Host Environments

This skill works identically whether the agent is invoked from:

- **Claude Code** (CLI, IDE extension, or Desktop app)
- **Antigravity** (Gemini brain workspace)
- **Cursor** (Plan Mode, Composer, or Agent)
- **Any combination** — same project, multiple assistants across sessions

The retrieval logic is source-agnostic: each IDE/assistant writes its artefacts to a known location outside the repo, and this skill catalogues those locations so any agent can sweep them into the project artefact tree.

### ⚠️ Claude Code auto-memory: consult, don't copy

`~/.claude/projects/*/memory/` is **personal memory**, not an artefact store — memory files stay where they are and are never copied into `docs/artefacts/`.

But memory _informs_ retrieval. Before sweeping IDE locations, skim:

- `MEMORY.md` and any `project_*.md` entries for the active project — they often name current initiatives, IDEA numbers, modules, stakeholders, and deadlines. Use these to seed `PROJECT_KEYWORDS` for the discovery sweep (§2) and the unsaved-artefacts audit (§5).
- `user_*.md` / `feedback_*.md` for signals about which assistant (Cursor / Antigravity / Claude Code) the user has been using recently — narrows where to look first.

The same consult-don't-copy rule applies to `~/.claude/CLAUDE.md` and private user config. `~/.gemini/` / `~/.cursor/` _config_, credentials, and session metadata remain fully off limits — only **generated work product** (plans, analyses, walkthroughs) from those workspaces is a retrieval candidate.

## When to Use

- 🆕 Starting a new project and looking for validated knowledge from prior work
- 🔍 Researching proven patterns before implementing a solution
- ✅ Validating assumptions against documented findings
- 🧹 Periodic sweep for completed plans and analyses that still live outside the repo
- 🔄 Ensuring consistency across agents (Claude Code / Antigravity / Cursor all see the same canonical knowledge)

## Artefact Sources (Complete Reference)

| Source                         | Location                                                               | Format                      |
| ------------------------------ | ---------------------------------------------------------------------- | --------------------------- |
| In-repo agent outputs          | `docs/artefacts/by-agent/`                                             | Markdown                    |
| In-repo research / validations | `docs/artefacts/by-type/`                                              | Markdown                    |
| In-repo topic cross-refs       | `docs/artefacts/by-topic/`                                             | Symlinks                    |
| Cursor plans                   | `~/.cursor/plans/*.plan.md`                                            | YAML frontmatter + Markdown |
| Cursor agent transcripts       | `~/.cursor/projects/<project>/agent-transcripts/`                      | JSONL                       |
| Antigravity/Gemini artefacts   | `~/.gemini/antigravity/brain/<id>/artifacts/`                          | Markdown                    |
| Antigravity/Gemini transcripts | `~/.gemini/antigravity/brain/<id>/.system_generated/logs/overview.txt` | Text                        |
| Claude Code transcripts        | `~/.claude/projects/<project-slug>/*.jsonl`                            | JSONL (session logs)        |
| Temp scratch                   | `/tmp/*.md`, `/tmp/artefacts/`                                         | Markdown                    |

### Excluded from copying (consult-only or fully off-limits)

- 📖 `~/.claude/projects/*/memory/` — personal agent memory; **consult** project-type entries for keywords and scope, but never copy into `docs/artefacts/`
- ❌ Any `.env`, credentials, session tokens — fully off-limits
- ❌ Raw transcripts — search them for artefact references, but don't copy wholesale

## Pattern

### 1. Pick the source

Figure out which assistant generated the artefact. If unsure, sweep all known locations (§2).

### 2. Discovery — list and filter

```bash
# Cursor plans — newest first
ls -lt ~/.cursor/plans/*.plan.md 2>/dev/null

# Antigravity/Gemini brains — newest first
ls -lt ~/.gemini/antigravity/brain/ 2>/dev/null

# Show names + status at a glance for Cursor plans
for f in ~/.cursor/plans/*.plan.md; do
    name=$(grep "^name:" "$f" | head -1 | sed 's/name: //')
    echo "$f → $name"
done

# Find plans/artefacts matching a project keyword across all sources
KEYWORDS="myproject|IDEA-|ai_service|dashboard"
grep -rlE "$KEYWORDS" \
    ~/.cursor/plans/ \
    ~/.gemini/antigravity/brain/ \
    2>/dev/null
```

### 3. Assess relevance before copying

Open the artefact. Ask:

- Is the work **complete** (Cursor: all todos `status: completed`; Antigravity: final draft)?
- Does it document a **non-trivial** architectural decision or reusable pattern?
- Could it **inform future work** — not just describe what the agent did?
- Does it match the **current project context** (framework, stack, production state)?

Low-value ephemera (single-file bug fixes, debug logs, one-shot refactors) usually doesn't need saving — the git history already captures the change.

### 4. Import into the project taxonomy

Ensure the taxonomy exists (first-time setup):

```bash
mkdir -p docs/artefacts/by-type/{plans,analyses,validations,research,reports}
mkdir -p docs/artefacts/by-topic/{architecture,deployment,security,frontend,backend}
mkdir -p docs/artefacts/by-agent
```

Copy the artefact and symlink into topic cross-refs:

```bash
# Example: Cursor plan for text file preview feature
cp ~/.cursor/plans/idea-057_text_file_preview_52778d48.plan.md \
   docs/artefacts/by-type/plans/IDEA-057-text-file-preview.plan.md

ln -sf ../../by-type/plans/IDEA-057-text-file-preview.plan.md \
   docs/artefacts/by-topic/frontend/IDEA-057-text-file-preview.plan.md

# Example: Antigravity analysis
cp ~/.gemini/antigravity/brain/<conversation-id>/artifacts/devlog_analysis.md \
   docs/artefacts/by-type/analyses/devlog_analysis.md

ln -sf ../../by-type/analyses/devlog_analysis.md \
   docs/artefacts/by-topic/security/devlog_analysis.md
```

### 5. Unsaved-artefacts audit (run periodically)

```bash
#!/bin/bash
# Find IDE-generated artefacts not yet imported into the project tree.
# Adjust PROJECT_KEYWORDS to match IDEA numbers, feature names, modules from AGENTS.md/CLAUDE.md.
PROJECT_KEYWORDS="${1:-myproject|IDEA-|ai_service|dashboard}"

echo "=== 🔍 IDE artefacts potentially related to this project ==="

check_source() {
    local label="$1"
    local pattern="$2"
    for f in $pattern; do
        [ -f "$f" ] || continue
        if grep -qiE "$PROJECT_KEYWORDS" "$f"; then
            basename=$(basename "$f")
            # Heuristic: is a file with a similar name already under docs/artefacts/?
            if ! find docs/artefacts/ -name "*${basename%.*}*" 2>/dev/null | grep -q .; then
                echo "  [$label] NOT SAVED: $basename"
            fi
        fi
    done
}

check_source "Cursor"      "$HOME/.cursor/plans/*.plan.md"
check_source "Antigravity" "$HOME/.gemini/antigravity/brain/*/artifacts/*.md"
```

### 6. Retrieve from the project tree (for downstream work)

Once imported, artefacts are discoverable via simple path queries:

```bash
# By agent
find docs/artefacts/by-agent/researcher/ -name "*.md"

# By type
find docs/artefacts/by-type/validations/ -name "*DJANGO*"

# By topic
find docs/artefacts/by-topic/django-architecture/ -name "*.md"

# Full-text
grep -rli "multi-tenant" docs/artefacts/
```

## Taxonomy Reference

```
docs/artefacts/
├── by-agent/              # who generated it
│   ├── researcher/
│   ├── test-engineer/
│   └── architect/
├── by-type/               # what kind of artefact
│   ├── plans/             # completed IDE plans (Cursor Plan Mode etc.)
│   ├── analyses/          # exploratory analysis / walkthroughs
│   ├── validations/       # test / validation reports
│   ├── research/          # background research notes
│   └── reports/           # status / audit reports
└── by-topic/              # cross-cutting concern (symlinks into by-type/)
    ├── architecture/
    ├── deployment/
    ├── security/
    ├── frontend/
    └── backend/
```

`by-type/` is the canonical store. `by-topic/` holds symlinks for discovery. `by-agent/` is optional; skip it if your project doesn't track per-agent provenance.

## Example Use Cases

### 🎯 Project onboarding

New agent session starts, checks `docs/artefacts/by-topic/architecture/` for validated patterns before proposing new designs.

### 🔄 Cross-IDE continuity

Cursor plan for IDEA-057 was generated yesterday; today a Claude Code session picks it up from `docs/artefacts/by-type/plans/` and implements against it.

### 🧪 Production readiness

Before deployment, sweep `docs/artefacts/by-type/validations/` for prior sign-offs on related components.

### 🧹 Periodic cleanup

Weekly run of the unsaved-artefacts audit (§5) captures anything new from Cursor / Antigravity workspaces.

## Why This Is Generic

- **Assistant-agnostic**: Cursor, Claude Code, Antigravity, and future assistants all drop generated work into predictable host locations.
- **Project-agnostic**: any project can adopt the `docs/artefacts/` taxonomy with a single `mkdir -p`.
- **Format-agnostic**: Markdown with YAML frontmatter is universally readable; symlinks are universally resolvable.
- **Knowledge preservation**: artefacts outlive individual agent sessions and IDE workspaces.
- **No lock-in**: plain files in the repo, no special tooling required to read them.

## References

- [Agent Artefacts Knowledge Base](../../docs/artefacts/README.md)
- [Multi-dimensional Taxonomy](../../docs/artefacts/taxonomy.md)
- [Git Workflow Rule](../../rules/RULE_git-safety.md)
