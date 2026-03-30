---
description: Mandatory instructional meta-skill triggered during ANY AI skill creation or skill modification task to enforce strict IDE-agnostic formatting and YAML protocols.
---

# SKILL_Skill_Writer

## Overview
An instructional meta-skill that dictates how AI agents must construct, format, and phrase new `.md` skills and repository rules. This skill is fully IDE-agnostic (designed for Claude, Copilot, Antigravity, OpenClaw, Cursor, etc.). It ensures all authored skills adhere to universal probabilistic trigger optimization, strict YAML configurations, and context-window-lean formatting regardless of the underlying LLM platform.

## When to Use
Trigger this skill whenever the user requests to "create a new skill", "extract a pattern into mind-vault", or "formalize an AI codebase rule".

## Pattern
When an AI agent is instructed to create or refactor a skill within `mind-vault` or `camper-aurora`, it MUST enforce the following structural constraints:

### 1. The Universal YAML Trigger Protocol
- All AI skills must place a `description` field in the frontmatter.
- The description MUST be a hyper-specific, one-line trigger under 200 characters loaded with domain-specific nouns (e.g., "Enforce robust anchor store bounding box triggers...").
- Do NOT use generic language like "A skill for helping write frontend code." 

### 2. The Additive-Only Instruction Rule
- The markdown body must skip generic programming advice (e.g., "use `git commit` to commit code"). LLM platforms already know the basics.
- Focus strictly on framework deviations, custom architectural rules, and project-specific constraints that an AI would not native-guess.

### 3. The Negative Space Matrix (✅ DO vs ❌ DON'T)
- Every significant piece of coding instruction MUST include a negative counter-example. Provide explicit matrix definitions to bound the AI's imagination.
- Example: 
  ✅ DO: Return `Result {ok: bool, error: string}`.
  ❌ DON'T: Throw silent Javascript `Error` exceptions.

### 4. Progressive Disclosure via References
- Forbid copying massive external documentation or multi-hundred-line templates directly into the root `SKILL.md`.
- Force the new skill to specify that the executing agent must dynamically load external references (e.g., instructing the agent to invoke tools to read an adjacent `references/` or `assets/` subdirectory) to protect the immediate context window.

## Why It's Generic
This is a pure meta-framework designed to govern the probabilistic construction of all future rules and skills across the user's multi-repository ecosystem, completely decoupled from any specific IDE or AI toolchain.

## Example Use Cases
- Generating a new skill for standardizing Django migrations.
- Extracting a hard-fought debugging session into a reusable Three.js skill.
- Migrating legacy, platform-specific AI rules into this universal, IDE-agnostic `.md` format.

## References
- `AGENTS.md` (Project Rules)
- Universal AI Agent `SKILL.md` specification formats.
