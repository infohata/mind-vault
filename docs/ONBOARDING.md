# Onboarding — mind-vault in 30 minutes

> **You're reading the v4 onboarding** — multi-engine review + open-source release candidate.

A one-pager for someone landing on mind-vault for the first time and wanting to run a real sprint by the end of the session. Skim top-to-bottom; deep links point at the authoritative docs when you need them.

## 1. What mind-vault is

A **cross-host configuration library** for AI coding agents. Skills, subagent personas, slash commands, and always-on rules are authored once and symlinked into Claude Code, Cursor, OpenCode, Antigravity, or VS Code Copilot — no copy-paste drift between tools.

**Five building blocks** (see [README.md](../README.md) for the full inventory):

- **Skills** (`skills/`) — `SKILL.md` files with frontmatter `name` + `description`. The description is a probabilistic trigger: the agent decides on its own when to invoke a skill.
- **Agents** (`agents/`) — subagent personas (`AGENT_architect`, `AGENT_bugbot`, `AGENT_backend`, …) with prime directives, multi-pass workflows, structured verdict formats.
- **Commands** (`commands/`) — slash commands invoked as `/<name>` from any host that supports them.
- **Rules** (`rules/`) — always-on guardrails auto-loaded every session (e.g. `RULE_git-safety` blocks pushes to `main`).
- **Sprint workflow** — a compounding 5-stage loop (`/ideate → /idea → /plan → /work → /<engine>-loop → /wrap → /compound`, where `/<engine>-loop` is `/bugbot-loop` or `/copilot-loop` per project config) that makes the *next* sprint start with a higher floor via the final `/compound` stage. See [SPRINT_WORKFLOW.md](SPRINT_WORKFLOW.md).

**The workflow principle** — every sprint should make the next sprint cheaper. `/compound` is the lever: any recurring fix-up becomes a new skill / rule / agent improvement.

## 2. Workspace setup

### Claude Code (recommended)

```bash
# Install Claude Code CLI (Node 20+ required)
curl -fsSL https://claude.ai/install.sh | sh

# First-run auth (browser-based OAuth or API key)
claude
```

You'll be prompted to pick: Anthropic API key, Claude Pro/Max subscription, or AWS Bedrock / Google Vertex. Subscription auth is simplest if you already have Pro/Max.

### IDE choice

Mind-vault is host-agnostic. Pick one (or several — symlinks let them coexist):

| Host | Setup script |
| --- | --- |
| Claude Code | `scripts/setup-claude-code-symlinks.sh` |
| Cursor | `scripts/setup-cursor-symlinks.sh` |
| Antigravity | `scripts/setup-antigravity-symlinks.sh` |
| OpenCode | `scripts/setup-opencode-symlinks.sh` |
| VS Code Copilot | `scripts/setup-vscode-copilot-symlinks.sh` |

Cursor has the richest skills + subagents support; Claude Code is the most polished CLI experience. See [CURSOR_SETUP.md](CURSOR_SETUP.md) for Cursor specifics.

### API keys

Only needed if you went the API-key auth route (not subscription):

- `ANTHROPIC_API_KEY` — get one at [console.anthropic.com](https://console.anthropic.com). Set in your shell rc (`~/.bashrc` / `~/.zshrc`).
- For Bedrock/Vertex, follow [Claude Code's auth docs](https://docs.claude.com/en/docs/claude-code/setup#authentication).

**Never commit a key.** `.env` files are off-limits to the agent by default — keep them out of git.

## 3. Setting up a project

### Install mind-vault

```bash
git clone git@github.com:infohata/mind-vault.git ~/projects/mind-vault
cd ~/projects/mind-vault
./scripts/setup-claude-code-symlinks.sh   # or whichever host(s) you use
```

The symlink script wires `skills/`, `agents/`, `commands/`, `rules/` into your host's native config dir (`~/.claude/` for Claude Code). One source of truth, edited in `mind-vault/`, picked up by every host.

### Bootstrap your project repo

```bash
# Inside the project you want to work on
cd ~/projects/your-project
git init           # if not already a repo
git remote add origin git@github.com:you/your-project.git
```

Open the project in your IDE / launch `claude` in its root. The agent automatically picks up:

- Always-on **rules** from `~/.claude/rules/` (git safety, self-sweep, rename-before-drop, cross-idea-amendments).
- All **skills** as on-demand capabilities.
- Slash **commands** available via `/<name>`.

### Define project requirements

Create a `CLAUDE.md` (or `AGENTS.md` for host-agnostic) at the project root with:

- Stack summary (language, framework, Python / Node version, Docker, DB).
- Conventions the agent should follow (naming, test framework, lint rules).
- Hard guardrails (`.env` off-limits, never push to `main`, Makefile preference, etc.).

If the project already has a `BACKLOG.md` / `IDEAS.md` / `ROADMAP.md`, run `/ingest-backlog` once to atomise it into `docs/ideas/IDEA-NNN-<slug>.md` files matching the sprint-workflow schema.

### Pick a code-review engine (optional)

Stage 4 (review) supports three modes — pick whichever your repo has enabled. The choice only affects which review skill you invoke at Stage 4 and what `/sprint-auto` does in unattended mode; everything else in mind-vault is engine-agnostic.

| Mode | Command | What it needs | When to pick it |
| --- | --- | --- | --- |
| **Cursor Bugbot** | `/bugbot-loop` | Cursor Bugbot enabled on the GitHub org/repo | Strongest catches in our experience; paid via Cursor subscription |
| **GitHub Copilot** | `/copilot-loop` | Copilot enabled on the org; `gh` CLI ≥ 2.88 | Native to GitHub; consumes Actions minutes from June 1, 2026 |
| **Internal curator (default fallback)** | Invoke `AGENT_curator` directly before push | Nothing — local Claude review only | No external bot; cheapest; **weaker than the two above — known to miss edge cases** |

For `/sprint-auto` (unattended overnight runs), the review engine is declared per-project. Add this to your project's `CLAUDE.md` or a `.mind-vault.yml` at the repo root:

```yaml
# Optional — sprint-auto review engine selector. Default: none (curator only).
review_engine: bugbot     # or "copilot", or omit/none for curator-only
```

When `review_engine` is unset or `none`, `/sprint-auto` skips the external-review loop entirely and relies on `AGENT_curator`'s pre-commit pass. This is the lowest-friction default but the weakest gate — opt into bugbot or copilot for real PR work.

## 4. Running your first workflow

Open the project in Claude Code and walk through the five stages. Each stage is a slash command; each one hands off to the next.

### Stage 0 — discover (optional)

```text
/ideate
```

Divergent scan across bugs / tech debt / features / refactors / tooling / docs. Adversarial filter prunes weak candidates. You pick the survivors; the skill turns them into `IDEA-NNN-<slug>.md` files.

### Stage 1 — capture

```text
/idea add a per-user notification preferences panel
```

Creates `docs/ideas/IDEA-NNN-notification-prefs.md` with structured frontmatter (status, priority, supersedes, depends_on, related) and updates the per-priority index.

### Stage 2 — plan

```text
/plan IDEA-NNN-notification-prefs
```

Reads the IDEA file (or interactively brainstorms if input is thin), invokes `AGENT_architect` as a reviewer, emits a durable plan at `docs/archive/YYYY-MM-idea-NNN-<slug>/YYYY-MM-DD-<slug>-plan.md`. Aliased as `/brainstorm`.

### Stage 3 — execute

```text
/work docs/archive/2026-05-idea-NNN-notification-prefs/2026-05-17-notification-prefs-plan.md
```

Thin orchestrator: enforces `RULE_git-safety` + parallel-worktree-docker discipline, dispatches per-step to `AGENT_backend` / `AGENT_frontend` / `AGENT_devops` / `AGENT_test-engineer`, checks off plan items as commits land on a feature branch.

### Stage 4 — review

Pick the command matching the review engine your repo has enabled (see § "Pick a code-review engine" above):

```text
/bugbot-loop      # Cursor Bugbot — preferred where available
/copilot-loop     # GitHub Copilot — the native-to-GitHub alternative
# or no external bot: invoke AGENT_curator directly before opening the PR
```

Both `*-loop` commands are semi-autonomous review loops with bounded-autonomy policy: post a PR if needed, apply findings under the autonomy ladder (auto-fix / approve-then-fix / escalate), retrigger the bot, halt at the HITL merge gate. The phase structure, dual-signal enumeration, staleness rules, and hard bounds are identical between the two — only the bot user.login, trigger mechanism, and clean-signal phrase differ.

If your repo has no external review bot, run `AGENT_curator` against the local diff before opening the PR. It's a Claude-driven reviewer with the same six-pass workflow as `AGENT_bugbot` / `AGENT_copilot`, but it's known to miss edge cases the external bots catch — treat it as the cheapest gate, not the best one.

### Stage 4.5 — wrap

```text
/wrap
```

Post-merge sweep — flips IDEA frontmatter to `complete`, re-sorts the index, appends a devlog entry, tears down any per-IDEA worktree stack, scans project docs for stale references. Can run pre-merge on the feature branch so the merge lands the final docs state in one shot.

### Stage 5 — compound

```text
/compound
```

The novel piece. Routes a just-learned lesson to one of six destinations: project-local solution doc, mind-vault skill / rule / agent / command, or auto-memory. The hybrid narrative-probe + taxonomy-quiz router decides where the lesson belongs. **This is how the next sprint gets easier than this one.**

### Sprint-auto (later, once you trust it)

Once you've run a few sprints by hand and the workflow feels natural, `/sprint-auto` chains stages 2–5 unattended overnight for IDEAs you've opted in via frontmatter (`auto_safe: true`). It halts only at the HITL merge boundary. Project's `review_engine` declaration (see § "Pick a code-review engine" above) decides which `*-loop` runs during the deliverables and docs review passes; the default `none` skips both external-review passes and relies on `AGENT_curator`. See [`skills/sprint-auto/SKILL.md`](../skills/sprint-auto/SKILL.md).

## Where to go next

- [README.md](../README.md) — full inventory of skills, agents, commands, rules.
- [SPRINT_WORKFLOW.md](SPRINT_WORKFLOW.md) — authoritative stage-by-stage explainer + frontmatter schemas + compound routing table.
- [SKILL_SPECIFICATION.md](SKILL_SPECIFICATION.md) — when you're ready to author your own skill.
- [CHANGELOG.md](../CHANGELOG.md) — chronological log of skill / rule / agent evolution.

**One closing principle.** Mind-vault is meant to be *yours*. Every project surfaces patterns your skills don't yet cover; every review-bot finding that recurs is a missing rule; every plan that needed extra brainstorming is a skill that wants tightening. `/compound` is the lever — pull it every sprint.
