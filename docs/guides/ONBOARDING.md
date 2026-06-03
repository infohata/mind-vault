# Onboarding — mind-vault in 30 minutes

> **mind-vault v4 — multi-engine review · open-source release.** See [`CHANGELOG.md`](../../CHANGELOG.md) for per-version detail.

A one-pager for someone landing on mind-vault for the first time and wanting to run a real sprint by the end of the session. Skim top-to-bottom; deep links point at the authoritative docs when you need them.

**Contents**

1. [What mind-vault is](#1-what-mind-vault-is)
2. [AI concepts — rules vs skills vs agents vs commands](#2-ai-concepts--rules-vs-skills-vs-agents-vs-commands)
3. [Workspace setup](#3-workspace-setup)
4. [Setting up a project](#4-setting-up-a-project)
5. [Useful Claude Code commands](#5-useful-claude-code-commands)
6. [The sprint workflow](#6-the-sprint-workflow)
7. [Deep dives — companion guides](#7-deep-dives--companion-guides)
8. [Where to go next](#where-to-go-next)

## 1. What mind-vault is

A **cross-host configuration library** for AI coding agents. Skills, subagent personas, slash commands, and always-on rules are authored once and symlinked into Claude Code, Cursor, OpenCode, Antigravity, or VS Code Copilot — no copy-paste drift between tools.

**Five building blocks** (see [README.md](../../README.md) for the full inventory):

- **Skills** (`skills/`) — `SKILL.md` files with frontmatter `name` + `description`. The description is a probabilistic trigger: the agent decides on its own when to invoke a skill.
- **Agents** (`agents/`) — subagent personas (`AGENT_architect`, `AGENT_backend`, `AGENT_curator`, …) with prime directives, multi-pass workflows, structured verdict formats.
- **Commands** (`commands/`) — slash commands invoked as `/<name>` from any host that supports them.
- **Rules** (`rules/`) — always-on guardrails auto-loaded every session (e.g. `RULE_git-safety` blocks pushes to `main`).
- **Sprint workflow** — a compounding 5-stage loop (`/ideate → /idea → /plan → /work → /review-loop (deliverables) → /wrap → /review-loop (docs) → /compound`, where `/review-loop` carries the configured engine(s) — `bugbot`, `copilot`, `claude`, or any subset per project config) that makes the *next* sprint start with a higher floor via the final `/compound` stage. See [SPRINT_WORKFLOW.md](SPRINT_WORKFLOW.md).

**The workflow principle** — every sprint should make the next sprint cheaper. `/compound` is the lever: any recurring fix-up becomes a new skill / rule / agent improvement.

## 2. AI concepts — rules vs skills vs agents vs commands

The four artefact types in mind-vault answer four different questions. Internalising the distinction up front makes the rest of the system click.

| Artefact | Loaded when? | Decided by? | Cost | Example |
| --- | --- | --- | --- | --- |
| **Rule** (`rules/RULE_*.md`) | Every session, unconditionally | Auto-loaded by harness | Permanent context budget | `RULE_git-safety` blocks pushes to `main` on every conversation |
| **Skill** (`skills/<name>/SKILL.md`) | On demand, when description matches the task | The agent (probabilistic match against `description` field) | Per-invocation | `/wrap` for the pre-merge doc-finalization sweep; `django` skill loads when editing Django code |
| **Agent profile** (`agents/AGENT_*.md`) | When dispatched as a subagent | The orchestrating agent (you or another skill) | Per-dispatch, runs in isolated context window | `AGENT_architect` invoked by `/plan`; `AGENT_curator` invoked by `/review-loop` |
| **Slash command** (`commands/*.md`) | Explicit user invocation | The human typing `/<name>` | Per-invocation | `/idea`, `/work`, `/sprint-auto` |

**Mental shortcuts:**

- **Always true** → rule. (Examples: never push to `main`; never touch `.env`; always run pyflakes before push.)
- **Sometimes useful, agent decides** → skill. (Examples: Django ORM patterns; post-merge wrap discipline; multi-engine review loop.)
- **A persona/role to delegate work to** → agent. (Examples: an architect that reviews plans; a curator that pre-sweeps PRs.)
- **A user-triggered action** → slash command. (Examples: kick off the sprint workflow stages.)

Rules are the most expensive (always loaded) so be miserly. Skills are cheap (load-on-demand) — most domain knowledge should live there. See [`skills/idea/references/`](../../skills/idea/references/) and [`rules/`](../../rules/) for canonical examples of each.

## 3. Workspace setup

### Windows: switch to WSL first

Mind-vault is Linux/macOS-native. Windows users should work inside WSL2 (Ubuntu or your distro of choice) — all the symlink scripts assume a POSIX filesystem. A bootstrap helper is included for fresh Windows 10 / 11 installs:

```powershell
# Elevated PowerShell on the Windows host (one-time):
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\install-wsl.ps1
```

It checks Windows build + virtualization, enables the WSL + VirtualMachinePlatform optional features, installs the WSL2 kernel where needed, and lets you pick a distro interactively or via `-Distro <name>`. Once WSL is up, run everything below from inside WSL.

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

## 4. Setting up a project

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

A brownfield codebase? Run `/init` once — it analyses the repo structure and proposes a starter `CLAUDE.md`. Then edit by hand to tighten the guardrails.

If the project already has a `BACKLOG.md` / `IDEAS.md` / `ROADMAP.md`, run `/ingest-backlog` once to atomise it into `docs/ideas/IDEA-NNN-<slug>.md` files matching the sprint-workflow schema.

### Pick a code-review engine (optional)

Stage 4 (review) supports several modes — pick whichever your repo has enabled (and combine the external engines freely). The choice only affects which engine(s) you pass to `/review-loop` at Stage 4 and what `/sprint-auto` does in unattended mode; everything else in mind-vault is engine-agnostic.

| Mode | Command | What it needs | When to pick it |
| --- | --- | --- | --- |
| **Cursor Bugbot** | `/review-loop <PR> bugbot` | Cursor Bugbot enabled on the GitHub org/repo | Strongest catches in our experience; paid via Cursor subscription |
| **GitHub Copilot** | `/review-loop <PR> copilot` | Copilot enabled on the org; `gh` CLI ≥ 2.88 | Native to GitHub; consumes Actions minutes from June 1, 2026 |
| **Claude Code Review** | `/review-loop <PR> claude` | `claude-code-action@v1` installed via `/install-github-app` (drops `claude-code-review.yml` + wires `CLAUDE_CODE_OAUTH_TOKEN`) | Dogfoods our own stack, `CLAUDE.md`-convention-aware, OAuth/subscription-billed (no per-review SKU). Push-triggered + comment-anchored — NOT the managed Code Review App |
| **Multiple engines** | `/review-loop <PR> bugbot,copilot,claude` (any subset) | Each engine's prerequisites above | High-stakes PRs; the engines have complementary blind spots. The loop syncs them per cycle |
| **Internal curator (default fallback)** | Invoke `AGENT_curator` directly before push | Nothing — local Claude review only | No external bot; cheapest; **weaker than the above — known to miss edge cases** |

For `/sprint-auto` (unattended overnight runs), the review engine is declared per-project. Add this to your project's `CLAUDE.md` or a `.mind-vault.yml` at the repo root:

```yaml
# Optional — sprint-auto review engine selector. Default: none (curator only).
review_engine: bugbot     # or "copilot", "claude", a subset like "bugbot,copilot,claude", or omit/none for curator-only
```

When `review_engine` is unset or `none`, `/sprint-auto` skips the external-review loop entirely and relies on `AGENT_curator`'s pre-commit pass. This is the lowest-friction default but the weakest gate — opt into bugbot, copilot, claude (or a combination) for real PR work.

## 5. Useful Claude Code commands

Claude Code ships a set of built-in `/commands` for managing the session itself (distinct from mind-vault's workflow commands like `/idea` and `/wrap`). Knowing these makes long sessions cheaper and more productive.

| Command | Purpose | When to reach for it |
| --- | --- | --- |
| `/context` | Show context-window usage breakdown by category (system prompt, tools, memory, skills, messages, free space) | Diagnose "why is the model slow / expensive?" — long-running sessions, before deciding whether to `/compact` |
| `/usage` | Show your subscription quota / token-spend telemetry | Check how much of your daily/weekly Claude Pro/Max budget you've burned |
| `/effort` | Set Sonnet's reasoning effort — `low` / `medium` / `high` | Trivial edits: `low`. Architecture decisions: `high`. Default is fine for everything in between |
| `/compact` | Summarise the conversation so far, freeing context for continued work | When the bar hits ~70% and you want to keep going on the same task without losing the thread |
| `/new` (or `Ctrl-C` then re-launch) | Start a fresh session with empty context | When the current task is **done** and the next task is unrelated — never `/compact` across topic shifts |
| `/resume` | Pick up a previous session by id | Continue work from a session you left yesterday/last week |
| `/init` | Bootstrap a `CLAUDE.md` for the current project | First contact with a brownfield codebase — gives you a starter; edit by hand to tighten |
| `/help` | List all commands available in the current host | Always |

**`/compact` vs `/new` — the trap that costs you context budget:**

- `/compact` collapses the conversation to a summary + carries forward. Use mid-task when the work is the same but the chat history is long.
- `/new` discards everything. Use when you switch to an unrelated task — same project, different feature; or a different project altogether.

Most context budget is wasted by *not* `/new`-ing at topic boundaries — a 200K-token chat about authentication is dead weight when you pivot to debugging a migration.

### Context window vs subscription limits — not the same thing

These are two independent budgets and conflating them leads to wrong instincts:

- **Context window** (visible in `/context`) — the model's working memory for a single conversation. Hard cap: 200K for Sonnet 4.6 / Haiku 4.5; 1M for Opus 4.7 with the `[1m]` flag. Spent by every message, tool result, skill body, and memory file loaded into the chat. `/compact` and `/new` are the levers.
- **Subscription usage** (visible in `/usage`) — your daily/weekly token quota on Pro/Max plans, or your dollar spend on API. Spent across **all** your conversations + every tool call billed by token in/out.

A near-full context window does **not** mean you're near your subscription limit (you might be at 1% of weekly quota with a 95%-full context). A near-empty context **does not** mean usage is cheap (a fresh session firing huge tool results burns quota fast). Watch both — they're different problems with different fixes.

## 6. The sprint workflow

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
/review-loop <PR> bugbot,copilot,claude   # multi-engine canonical entry, cycle-level sync
/review-loop <PR> bugbot                   # Cursor Bugbot only
/review-loop <PR> copilot                  # GitHub Copilot only
/review-loop <PR> claude                   # Claude Code Review only (push-triggered)
# or no external bot: invoke AGENT_curator directly before opening the PR
```

`/review-loop` is a semi-autonomous review loop with bounded-autonomy policy: post a PR if needed, apply findings under the autonomy ladder (auto-fix / approve-then-fix / escalate), retrigger the engine(s), halt at the HITL merge gate. The phase structure, dual-signal enumeration, staleness rules, and hard bounds are identical across engines — only the bot identity, trigger mechanism (claude is push-triggered, not retriggered), review-state source (claude reads a GitHub Actions job, the others a named check-run), and clean signal differ per engine.

If your repo has no external review bot, run `AGENT_curator` against the local diff before opening the PR. It's a Claude-driven reviewer with the same workflow the `/review-loop` engines run, but it's known to miss edge cases the external bots catch — treat it as the cheapest gate, not the best one.

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

Once you've run a few sprints by hand and the workflow feels natural, `/sprint-auto` chains stages 2–5 unattended overnight for IDEAs you've opted in via frontmatter (`auto_safe: true`). It halts only at the HITL merge boundary. Project's `review_engine` declaration (see § "Pick a code-review engine" above) decides which `*-loop` runs during the deliverables and docs review passes; the default `none` skips both external-review passes and relies on `AGENT_curator`. See [`skills/sprint-auto/SKILL.md`](../../skills/sprint-auto/SKILL.md).

## 7. Deep dives — companion guides

The topics below outgrow a one-pager. Each links to a dedicated companion doc you can read once and refer back to. Don't try to absorb all four on day one — skim, then come back when the workflow surfaces a question.

- [**Git workflow**](GIT_WORKFLOW.md) — branch-per-IDEA discipline, PR basing, integration branches for multi-PR cohorts, multi-engine review (Bugbot + Copilot + Claude), force-push hygiene, the HITL merge gate.
- [**Parallel worktrees**](WORKTREE_PRACTICES.md) — when to use `git worktree`, port-offset discipline for parallel docker stacks, `.env` isolation, sprint-auto's integration-worktree pattern, teardown discipline.
- [**Skill authoring walkthrough**](SKILL_AUTHORING_WALKTHROUGH.md) — process HOWTO that anchors on [SKILL_SPECIFICATION.md](SKILL_SPECIFICATION.md). When does a pattern earn its own skill vs become a rule? Anatomy walkthrough. Common anti-patterns. The `/compound` route from lesson → skill.
- [**Memory management**](MEMORY_MANAGEMENT.md) — auto-memory vs `CLAUDE.md` vs project doc vs skill — when each is the right destination. Periodic pruning. What rots and how to spot it.

## Where to go next

- [README.md](../../README.md) — full inventory of skills, agents, commands, rules.
- [SPRINT_WORKFLOW.md](SPRINT_WORKFLOW.md) — authoritative stage-by-stage explainer + frontmatter schemas + compound routing table.
- [SKILL_SPECIFICATION.md](SKILL_SPECIFICATION.md) — when you're ready to author your own skill.
- [CHANGELOG.md](../../CHANGELOG.md) — chronological log of skill / rule / agent evolution.

**One closing principle.** Mind-vault is meant to be *yours*. Every project surfaces patterns your skills don't yet cover; every review-bot finding that recurs is a missing rule; every plan that needed extra brainstorming is a skill that wants tightening. `/compound` is the lever — pull it every sprint.
