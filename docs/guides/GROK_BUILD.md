# Grok Build on mind-vault

How this repository uses [Grok Build](https://docs.x.ai/build) (xAI `grok` CLI) alongside Claude Code and Cursor — without replacing either.

## What you get

1. **Interactive agent** — `grok` in a checkout, with project `.grok/config.toml` and native `.grok/agents` + `.grok/skills`. Prefer the **plugin marketplace** install (below); symlink wiring is legacy/optional.
2. **CI PR review** — `.github/workflows/grok-code-review.yml` posts a sticky `<!-- grok-code-review -->` comment (parallel to Claude Code Review; Claude workflows stay).
3. **review-loop engine** — `grok` in `/review-loop` (`tools/find_grok_comments.sh` + `tools/grok_retrigger.sh`). Reachability-probed: absent workflow → self-excludes from the default engine set.

## Auth

| Surface                 | Credential                      | Notes                                                                                        |
| ----------------------- | ------------------------------- | -------------------------------------------------------------------------------------------- |
| Interactive TUI / login | **SuperGrok** or **X Premium+** | Browser/session login. Folder trust prompts apply when opening a new workspace.              |
| CI / headless           | Repo secret **`XAI_API_KEY`**   | Metered xAI API. Set under Settings → Secrets and variables → Actions. Never commit the key. |

Install the CLI:

```bash
curl -fsSL https://x.ai/cli/install.sh | bash
```

## Install channels (plugin preferred)

Grok Build has a **plugin + marketplace** system similar to Claude Code. Prefer it for consumer machines:

```bash
grok plugin marketplace add infohata/mind-vault
grok plugin install mv --trust
# fallback if the short name is not yet indexed:
#   grok plugin install infohata/mind-vault --trust
```

Marketplace installs clone the repo’s **default branch** (`main`) into a pinned snapshot — not your feature-branch working tree. So this channel only picks up new releases after they land on `main` (then `grok plugin update`).

Grok accepts Claude’s plugin manifests: `.claude-plugin/plugin.json` validates as-is, and `.grok-plugin/marketplace.json` is a **git symlink** to `.claude-plugin/marketplace.json` so `marketplace add` + `install mv` resolves the catalog short name without a second copy.

**Symlink channel is legacy / optional** and may stay for authoring or hosts that already use `scripts/setup-*-symlinks.sh`:

```bash
./scripts/setup-grok-symlinks.sh   # wires ~/.grok/{skills,commands,agents,rules,docs/rules}
```

Pick **one channel per machine** (plugin *or* symlinks) — both at once double-loads skills/commands/agents. Project-level `.grok/{config.toml,agents,skills}` in a checkout still applies when you `grok` inside that repo regardless of channel.

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

Do **not** put `Bash(git push*)` in the project `deny` list — interactive Grok needs to push feature branches. This project config is for interactive sessions only; CI never applies it.

**CI review is read-only and set entirely by command-line flags.** The PR body and diff are attacker-controllable prompt input, and `XAI_API_KEY` has to sit in grok's environment, so `grok-code-review.yml` runs:

```bash
grok -p "$PROMPT" --output-format plain \
  --permission-mode dontAsk \
  --allow 'Read' --allow 'Grep' \
  --deny 'Bash' --deny 'Edit' --deny 'Write' --deny 'WebFetch' \
  --deny 'Read(/proc/**)' --deny 'Grep(/proc/**)' \
  --disallowed-tools Agent --disable-web-search \
  --sandbox strict --max-turns 15
```

- `dontAsk` runs only allowlisted tools, and deny beats allow. There's no Bash, so there's no `curl`. The `/proc` denies block the obvious way to read the key (`/proc/self/environ`).
- `--sandbox strict` blocks network access for child processes and limits reads to the working directory plus system paths. The review context therefore lives in `.grok-review/` inside the workspace, not in `/tmp`. If a built-in profile fails to apply, Grok only warns and keeps running, so the workflow surfaces any sandbox warning in the run log.
- **No `--trust`.** The checkout is the PR head, so a trusted project config could add `[mcp_servers]`, which means running arbitrary code next to the key.
- Checkout uses `persist-credentials: false`, so no GitHub token stays in `.git/config`.
- Before posting, the output is scanned for the key written out verbatim; an encoded key would slip past, which is why the `/proc` denies matter. A match replaces the sticky with a "withheld" notice, then fails the run (rotate the key).
- The sticky lookup matches `github-actions[bot]` *and* the marker, the same rule `tools/find_grok_comments.sh` uses, so a human comment quoting the marker is never overwritten.
- The PR number reaches shell via `env:`, validated as numeric. `${{ }}` is text substitution into the script, not an argument.

The sticky `<!-- grok-code-review -->` output shape is required by `tools/find_grok_comments.sh` (not optional fluff).

## User-level symlinks (legacy)

Kept for authoring / already-wired machines. Prefer [Install channels](#install-channels-plugin-preferred) for new setups.

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

|                   | Claude Code Review                                    | Grok Code Review                                           |
| ----------------- | ----------------------------------------------------- | ---------------------------------------------------------- |
| Workflow          | `claude-code-review.yml` (+ interactive `claude.yml`) | `grok-code-review.yml`                                     |
| Secret            | `CLAUDE_CODE_OAUTH_TOKEN`                             | `XAI_API_KEY`                                              |
| review-loop       | `claude` (primary comment-anchored engine today)      | `grok` (parallel / fallback)                               |
| Sticky / identity | `claude[bot]` summary + `github-actions[bot]` inlines | `github-actions[bot]` sticky + `<!-- grok-code-review -->` |

Both may run on the same PR. `/review-loop` defaults include both when each workflow is installed; either self-excludes via `*_NOT_INSTALLED` when missing.

## Bugbot vs Grok Build

|                    | **Cursor Bugbot**                     | **Grok Build**                                                                       |
| ------------------ | ------------------------------------- | ------------------------------------------------------------------------------------ |
| What it is         | Cursor **paid** automated PR reviewer | Subscription **interactive** agent (SuperGrok / X Premium+) + **metered API** for CI |
| In review-loop     | `bugbot` — check-run / request-driven | `grok` — auto-trigger / comment-anchored                                             |
| mind-vault posture | Optional third engine                 | Parallel/fallback to Claude; does not replace Bugbot or Claude                       |

**Summary:** Bugbot = Cursor's paid reviewer product. Grok Build = xAI's agent CLI (interactive login via SuperGrok/X Premium+; CI via `XAI_API_KEY`). This repo already uses Claude as a review-loop engine; Grok is additive.

## Folder trust

On first open of a directory, Grok may prompt to trust the folder (same class of workspace trust as other agent hosts). Trust the mind-vault checkout (and any project you review) before expecting skills/agents to load.

## Quick checklist

- [ ] `curl -fsSL https://x.ai/cli/install.sh | bash`
- [ ] Interactive: SuperGrok or X Premium+ login; trust the folder
- [ ] Prefer: `grok plugin marketplace add infohata/mind-vault` then `grok plugin install mv --trust` (tracks `main`; after each release run `grok plugin update`)
- [ ] Legacy/optional: `./scripts/setup-grok-symlinks.sh`
- [ ] CI: add `XAI_API_KEY` repo secret; merge `grok-code-review.yml` to default branch
- [ ] Verify: `grok inspect`; on a PR, wait for sticky or run `./tools/grok_retrigger.sh <PR>`
- [ ] review-loop: `/review-loop <PR> grok` or include `grok` in the engine list

See also: [`skills/review-loop/references/engine-grok.md`](../skills/review-loop/references/engine-grok.md).
