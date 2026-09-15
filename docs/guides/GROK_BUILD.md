# Grok Build on mind-vault

How this repository uses [Grok Build](https://docs.x.ai/build) (xAI `grok` CLI) alongside Claude Code and Cursor — without replacing either.

## What you get

1. **Interactive agent** — `grok` in a checkout, with project `.grok/config.toml`, native `.grok/agents` + `.grok/skills` symlinks, and optional user-level wiring via `scripts/setup-grok-symlinks.sh`.
2. **CI PR review** — `.github/workflows/grok-code-review.yml` posts a sticky `<!-- grok-code-review -->` comment (parallel to Claude Code Review; Claude workflows stay).
3. **review-loop engine** — `grok` in `/review-loop` (`tools/find_grok_comments.sh` + `tools/grok_retrigger.sh`). Reachability-probed: absent workflow → self-excludes from the default engine set.

## Auth

| Surface | Credential | Notes |
|---|---|---|
| Interactive TUI / login | **SuperGrok** or **X Premium+** | Browser/session login. Folder trust prompts apply when opening a new workspace. |
| CI / headless | Repo secret **`XAI_API_KEY`** | Metered xAI API. Set under Settings → Secrets and variables → Actions. Never commit the key. |

Install the CLI:

```bash
curl -fsSL https://x.ai/cli/install.sh | bash
```

## Project layout

```
.grok/
  config.toml          # project [permission] (compact allow/deny string arrays)
  agents/AGENT_*.md    # symlinks → ../../agents/…
  skills/<name>/       # symlinks → ../../skills/…
```

**Why native `.grok/agents`?** Grok's Cursor-compat scanner loads `.cursor/skills` and `.cursor/rules` but **not** `.cursor/agents` (verified with `grok inspect`). Agents and skills are therefore committed under `.grok/` so project sessions see them without relying on compat cells.

Permission rules use the compact form (see [permissions reference](https://docs.x.ai/build/settings/reference)):

```toml
[permission]
allow = ["Read(**)", "Grep(**)", "Bash(git *)", "Bash(gh *)"]
```

Do **not** put `Bash(git push*)` in the project `deny` list — interactive Grok needs to push feature branches. CI review invokes `grok -p "…" --output-format plain --yolo` (or `--always-approve`) and adds `--deny` for Write/Edit/`Bash(git push*)` only in the workflow. The sticky `<!-- grok-code-review -->` output shape is required by `tools/find_grok_comments.sh` (not optional fluff).

## User-level symlinks

```bash
# From mind-vault root (or set MIND_VAULT=…)
./scripts/setup-grok-symlinks.sh
```

Wires `~/.grok/{skills,commands,agents,rules,docs/rules}` the same way `setup-cursor-symlinks.sh` wires `~/.cursor/`, using `scripts/_symlink-lib.sh`. Safe to re-run.

## CI review workflow

- **File:** `.github/workflows/grok-code-review.yml`
- **Triggers:** non-draft same-repo `pull_request` (opened / synchronize / ready_for_review / reopened); `issue_comment` containing `grok review` (OWNER/MEMBER/COLLABORATOR); `workflow_dispatch`
- **Install:** `curl -fsSL https://x.ai/cli/install.sh | bash`
- **Auth:** `secrets.XAI_API_KEY`
- **Output:** sticky PR comment with marker `<!-- grok-code-review -->` (create-or-update)
- **Does not** remove or alter `claude-code-review.yml` / `claude.yml`

Retrigger without Actions:write on a PAT:

```bash
./tools/grok_retrigger.sh <PR>   # posts hard-coded "grok review"
```

## Coexistence with Claude

| | Claude Code Review | Grok Code Review |
|---|---|---|
| Workflow | `claude-code-review.yml` (+ interactive `claude.yml`) | `grok-code-review.yml` |
| Secret | `CLAUDE_CODE_OAUTH_TOKEN` | `XAI_API_KEY` |
| review-loop | `claude` (primary comment-anchored engine today) | `grok` (parallel / fallback) |
| Sticky / identity | `claude[bot]` summary + `github-actions[bot]` inlines | `github-actions[bot]` sticky + `<!-- grok-code-review -->` |

Both may run on the same PR. `/review-loop` defaults include both when each workflow is installed; either self-excludes via `*_NOT_INSTALLED` when missing.

## Bugbot vs Grok Build

| | **Cursor Bugbot** | **Grok Build** |
|---|---|---|
| What it is | Cursor **paid** automated PR reviewer | Subscription **interactive** agent (SuperGrok / X Premium+) + **metered API** for CI |
| In review-loop | `bugbot` — check-run / request-driven | `grok` — auto-trigger / comment-anchored |
| mind-vault posture | Optional third engine | Parallel/fallback to Claude; does not replace Bugbot or Claude |

**Summary:** Bugbot = Cursor's paid reviewer product. Grok Build = xAI's agent CLI (interactive login via SuperGrok/X Premium+; CI via `XAI_API_KEY`). This repo already uses Claude as a review-loop engine; Grok is additive.

## Folder trust

On first open of a directory, Grok may prompt to trust the folder (same class of workspace trust as other agent hosts). Trust the mind-vault checkout (and any project you review) before expecting skills/agents to load.

## Quick checklist

- [ ] `curl -fsSL https://x.ai/cli/install.sh | bash`
- [ ] Interactive: SuperGrok or X Premium+ login; trust the folder
- [ ] Optional: `./scripts/setup-grok-symlinks.sh`
- [ ] CI: add `XAI_API_KEY` repo secret; merge `grok-code-review.yml` to default branch
- [ ] Verify: `grok inspect`; on a PR, wait for sticky or run `./tools/grok_retrigger.sh <PR>`
- [ ] review-loop: `/review-loop <PR> grok` or include `grok` in the engine list

See also: [`skills/review-loop/references/engine-grok.md`](../skills/review-loop/references/engine-grok.md).
