# Mind-Vault Tools

Two genres of script, by design, not by accident:

1. **Runtime skill helpers** — invoked **by skills** while they run. The
   review-loop engine adapters (`find_*_comments.sh`, `*_retrigger.sh`),
   `validate-skills.sh`, `sprint-auto-bootstrap.sh`, and `statusline-command.sh`.
2. **Repo-maintenance utilities** — one-shot dev tooling a human runs by hand.
   `cleanup-contamination.sh` is the lone example today.

`cleanup-contamination.sh` is **not** a runtime helper — zero skills invoke it.
It lives here because it's repo dev tooling and there's no purer home for a single
maintenance script. The honest label for `tools/` is therefore "skill machinery +
dev/maintenance utilities," not "runtime helpers only."

What `tools/` is **not**: machine provisioning (`install/`) or host config-wiring
(`scripts/`). If you're putting binaries on a box, that's `install/`; if you're
symlinking mind-vault into an agent host, that's `scripts/`.

## Review-loop engine adapters

The `/review-loop` skill drives PR review across multiple engines (bugbot, claude,
copilot). For each engine there's a **finder** (scrape the engine's review
comments off a PR) and a **retrigger** (ask the engine to re-review the new HEAD):

| Script | Role |
| --- | --- |
| `find_bugbot_comments.sh` | Scrape Bugbot review comments for a PR |
| `find_claude_comments.sh` | Scrape Claude review comments for a PR |
| `find_copilot_comments.sh` | Scrape Copilot review comments for a PR |
| `bugbot_retrigger.sh` | Re-request a Bugbot review on the current HEAD |
| `claude_retrigger.sh` | Re-request a Claude review on the current HEAD |
| `copilot_retrigger.sh` | Re-request a Copilot review on the current HEAD |

The finder/retrigger **contract** (output schema, exit codes, the per-engine
quirks each adapter normalizes) is documented in depth under
[`../skills/review-loop/references/`](../skills/review-loop/references/) — see
`engine-adapter-contract.md` and the per-engine `engine-*.md` files. This README
deliberately does not duplicate that contract; treat the scripts as the
review-loop skill's private machinery.

## Other runtime helpers

### validate-skills.sh

**Purpose**: Lint every skill in `skills/` for structural conformance (frontmatter,
required sections, budget). Run by skill-authoring workflows and in the IDEA-016
verification gate.

**Usage**:

```bash
# From repo root
./tools/validate-skills.sh --all     # validate every skill
./tools/validate-skills.sh <skill>   # validate one skill by name
```

### statusline-command.sh

**Purpose**: The Claude Code status line — a six-segment readout rendered under the
prompt: `topic | ctx% | turn-tokens | 5h-rate | 7d-rate | effort` (plus a vim-mode
segment when vim mode is on).

**Dependency**: `jq` only. If `jq` is missing, it degrades to a single
`jq missing` segment so Claude Code keeps rendering instead of erroring.

**How it's wired in**: it is **not** invoked directly — Claude Code calls it per the
`statusLine` entry in `~/.claude/settings.json`. It reaches `~/.claude` via the
symlink that [`../scripts/setup-claude-code-symlinks.sh`](../scripts/setup-claude-code-symlinks.sh)
creates (`~/.claude/statusline-command.sh -> mind-vault/tools/statusline-command.sh`),
so edits here propagate without re-copying.

**Usage**:

```bash
# Claude Code invokes it; settings.json snippet:
#   "statusLine": { "type": "command", "command": "bash ~/.claude/statusline-command.sh" }
# To eyeball output by hand, feed it the JSON Claude Code would pipe in:
echo '{}' | ./tools/statusline-command.sh
```

### sprint-auto-bootstrap.sh

**Purpose**: Canonical, project-agnostic worktree bootstrap called by the `/sprint-auto` skill. Brings up an isolated docker-compose stack in a git worktree with sentinel-`.env` + port-offset override, then dispatches to optional project-local hooks for post-up init and smoke-test.

**How projects consume it**: via a ~30-LOC wrapper committed at `<project>/tools/sprint-auto-bootstrap.sh` that locates this canonical script and execs into it. Wrappers fail gracefully when mind-vault is missing (clear error + remediation); symlinks don't. Template: [`../skills/sprint-auto/assets/sprint-auto-bootstrap.sh.wrapper`](../skills/sprint-auto/assets/sprint-auto-bootstrap.sh.wrapper).

**Usage** (called by the `/sprint-auto` skill inside the worktree, not usually by hand):

```bash
./tools/sprint-auto-bootstrap.sh <slug> <idea_number>
# exits 0 when the stack is up, services running, smoke test passed
```

**What it does**:

1. Preflight: docker + jq present, `.env.template` exists, `.env` / `docker-compose.override.yml` absent.
2. Generate sentinel `.env` from `.env.template` — regex-replaces `*_KEY` / `*_SECRET` / `*_TOKEN` / `*_PASSWORD` / `*_PASS` / `*_PWD` / `*_CREDENTIAL` with `test-not-a-real-key`; fresh random `SECRET_KEY` and `*_SALT` / `*_HMAC`; neutralises `user:pass@host` patterns in `*_URL`.
3. Parse `docker compose config --format json` to discover every service with host-port bindings; emit `docker-compose.override.yml` with ports shifted by `10000 + (idea_number % 100) * 100`.
4. `docker compose up -d --wait`.
5. Source optional `tools/sprint-auto-hooks.sh`; call `post_up_init` + `smoke_test` if declared.
6. Default smoke: all configured services must be in running state.

**Dependencies**: `docker`, `docker compose` plugin, `jq`, `openssl` (falls back to `date+sha256sum` for random bytes).

**Project-local hooks** (optional, copy + edit): [`../skills/sprint-auto/assets/sprint-auto-hooks.sh.example`](../skills/sprint-auto/assets/sprint-auto-hooks.sh.example) — declare `post_up_init()` (migrations, MinIO bucket setup, seed fixtures) and/or `smoke_test()` (HTTP health check, `pg_isready`, etc.).

**Full contract**: [`../skills/sprint-auto/references/worktree-lifecycle.md`](../skills/sprint-auto/references/worktree-lifecycle.md).

## Repo-maintenance utilities

### cleanup-contamination.sh

**Purpose**: Detect and remove grok-code-fast-1 tool response contamination from files.
One-shot repo-repair utility — a human runs it after a contaminated agent session;
**no skill invokes it.**

**Problem Solved**:

- grok-code-fast-1 model has a bug where `write` tool operations sometimes include tool response format in generated content
- This results in files containing: `</content><parameter name="filePath">`, `(End of file`, `</file>`

**Usage**:

```bash
# From repo root
./tools/cleanup-contamination.sh

# Interactive mode - scans all files, shows contaminated ones, asks for confirmation
# Creates .backup files for safety
```

**Features**:

- ✅ Scans entire repository (excluding .git/, node_modules/, etc.)
- ✅ Detects multiple contamination patterns
- ✅ Interactive confirmation before making changes
- ✅ Creates backup files (.backup extension)
- ✅ Safe - only removes known contamination patterns
- ✅ Colored output for better readability

**Contamination Patterns Detected**:

- `</content>` at end of lines
- `<parameter name="filePath">` lines
- `(End of file - total X lines)` lines
- `</file>` lines

**Example Output**:

```text
🔍 Scanning for grok-code-fast-1 tool response contamination...
Repository: /path/to/mind-vault

⚠️  Found 3 contaminated files:
  - docs/artefacts/README.md
  - docs/artefacts/taxonomy.md
  - docs/DJANGO_ARCHITECTURE_VALIDATION_REPORT.md

Do you want to clean up these files? (y/N) y

🧹 Cleaning up contaminated files...
Processing: docs/artefacts/README.md ... CLEANED
Processing: docs/artefacts/taxonomy.md ... CLEANED
Processing: docs/DJANGO_ARCHITECTURE_VALIDATION_REPORT.md ... CLEANED

🎉 Cleanup complete!
Files processed: 3
Files cleaned: 3
Backups saved: *.backup (for cleaned files only)
```

## Adding New Tools

**Guidelines**:

1. Place the script in this directory **only if** it's a runtime skill helper or a
   repo-maintenance utility. Machine provisioners go in [`../install/`](../install/README.md);
   host config-wiring (symlink setup) goes in [`../scripts/`](../scripts/README.md).
2. Make it executable (`chmod +x`).
3. Add documentation to this README under the matching genre heading.
4. Include usage examples with the real invocation path.
5. Follow naming: `[purpose]-[action].sh`.

**Authoring an `install-*` provisioner?** The installer conventions (the 15-pattern
trap catalog, `set -eo pipefail`, marker blocks, etc.) moved to
[`../install/README.md`](../install/README.md) along with the scripts. Read that
before writing a new installer.

## Maintenance

- **`cleanup-contamination.sh` runs**: after intensive AI agent work on a grok-code-fast-1 session.
- **Backup management**: review and remove old `.backup` files periodically.
- **Version control**: commit tool improvements and new scripts.

---

**Tools Directory**: `mind-vault/tools/`
