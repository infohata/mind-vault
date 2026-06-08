# Amended by IDEA-017 (2026-06-08)

`agents/SKILL_CONTRACT.md` — created by IDEA-014 Phase 1 as the stack-agnostic
agent↔skill contract interface — was **relocated to
`skills/work/references/SKILL_CONTRACT.md`** by IDEA-017 (commit `6aa4bb9`,
[PR #190](https://github.com/infohata/mind-vault/pull/190)).

**Why:** IDEA-017 packages mind-vault as a Claude Code plugin, where every
`agents/*.md` is auto-loaded as a subagent. A non-agent file in `agents/` would
load as a bogus agent, so `agents/` must hold exactly the 8 real `AGENT_*.md`.
The contract doc moved beside `persona-dispatch.md` (the other
agent-orchestration reference) in `skills/work/references/`. All ~13 referrers
— including every `AGENT_*.md` `## Stack adapter` link — were repointed
per-depth; both verification gates passed (no stale `agents/SKILL_CONTRACT`
path, every link resolves to the moved file). This also fixed the same latent
bug on the symlink path, where `mv_link_tree agents` had been symlinking the
non-agent file into `~/.claude/agents/`.

No behavioural change to the contract itself — purely a relocation for
plugin-agent-discovery hygiene.
