# Mind-Vault Tools

This directory contains utility scripts and tools for maintaining the mind-vault repository.

## Available Tools

### install-emoji-support.sh
**Purpose**: Install a color emoji font on Linux so terminals render emojis in color instead of monochrome / tofu.

**Problem Solved**:
- Many Linux installs ship only monochrome emoji fonts (e.g. Symbola) — color emojis show as boxes or B&W glyphs
- Common on fresh Debian/Ubuntu/Fedora/Arch installs
- Fixing it manually means knowing your distro's package name + refreshing fontconfig

**Usage**:
```bash
# From repo root
./tools/install-emoji-support.sh           # installs
./tools/install-emoji-support.sh --check   # reports current state only
```

**Features**:
- ✅ Multi-distro: auto-detects apt / dnf / pacman / zypper
- ✅ Idempotent: skips install if a color emoji font is already present
- ✅ `--check` flag for a dry run
- ✅ Verifies via `fc-list` after install
- ✅ Lists terminal emulators known to support color emoji

**Terminal compatibility**:
- ✅ kitty, wezterm, gnome-terminal, konsole, foot
- ⚠️  xfce4-terminal (version-dependent)
- ❌ xterm, urxvt (monochrome only — terminal limitation)

### install-docker.sh
**Purpose**: Install Docker Engine + `docker compose` plugin on a fresh Debian/Ubuntu host from Docker's official apt repo (not `get.docker.com`).

**Problem Solved**:
- `RULE_parallel-worktree-docker` and the `/sprint-auto` / `/deployment` workflows assume Docker + compose v2 on the host
- Fresh VPS images rarely ship with Docker; distro-packaged `docker.io` is usually too old for compose-v2's `!override` syntax
- Manual apt-repo + GPG setup is error-prone to copy-paste each time

**Usage**:
```bash
# From repo root (requires sudo)
sudo ./tools/install-docker.sh              # full install + add $SUDO_USER to docker group + hello-world smoke test
sudo ./tools/install-docker.sh --check      # reports current state only, no writes
sudo ./tools/install-docker.sh --no-group   # install only, skip usermod -aG docker
sudo ./tools/install-docker.sh --no-test-run  # skip the hello-world smoke test
```

**Features**:
- ✅ Idempotent: exits early if Docker + compose plugin already work
- ✅ `--check` flag for a dry run
- ✅ Detects conflicting distro packages (`docker.io`, `podman-docker`, etc.) and removes them
- ✅ Installs the official Docker apt repo with GPG-verified keyring
- ✅ Installs `docker-ce` + `docker-ce-cli` + `containerd.io` + `docker-buildx-plugin` + `docker-compose-plugin`
- ✅ Auto-adds `$SUDO_USER` to `docker` group; opt out with `--no-group`
- ✅ Smoke tests via `docker run --rm hello-world`; opt out with `--no-test-run`
- ✅ Clear post-install hints (log out / `newgrp docker`, verify with `docker ps`)

**Supported**: Debian 12+ (bookworm, trixie), Ubuntu 22.04+ (jammy, noble, later).
**Not supported**: RHEL / Fedora / Arch (each needs a different repo path — left for a later PR).

### install-oh-my-posh.sh
**Purpose**: Install [Oh My Posh](https://ohmyposh.dev) (prompt theme engine) for the current user and wire it into the shell rc. Idempotent, user-scope (no sudo), defaults to the `atomic` theme.

**Problem Solved**:
- Fresh VPS shells are grey and informationless; Oh My Posh fixes that with minimal setup
- The getting-started docs assume you'll copy-paste three things: `curl -s ... | bash -s`, a theme download, and an init line in your rc file — easy to half-do and end up with a broken prompt
- Re-running manual installs tends to append duplicate init lines to `~/.bashrc`; this script uses BEGIN/END markers so re-runs overwrite cleanly

**Usage**:
```bash
# Default: install, download atomic theme, wire the detected shell's rc
./tools/install-oh-my-posh.sh

# Non-interactive with a specific theme
./tools/install-oh-my-posh.sh --theme tokyonight_storm

# Interactive menu — pick from a curated 10-theme list
./tools/install-oh-my-posh.sh --interactive

# Check state only — no writes
./tools/install-oh-my-posh.sh --check

# Install the binary but don't touch the shell rc
./tools/install-oh-my-posh.sh --no-rc-edit
```

**Features**:
- ✅ Idempotent: detects existing binary + existing rc wiring, re-applies theme without duplicating
- ✅ `--check` reports install state with exit code (0 = fully installed, 1 = partial/missing)
- ✅ Auto-detects shell from `$SHELL` (bash / zsh / pwsh); `--shell X` forces it
- ✅ Default theme `atomic`; `--theme NAME` for non-interactive; `--interactive` for numbered menu
- ✅ User-scope install to `~/.local/bin` by default (override with `--install-dir`); no sudo needed
- ✅ Warns if no Nerd Font is installed (prompt glyphs render as tofu without one), but doesn't block
- ✅ Wraps the rc edit in `# BEGIN oh-my-posh (managed by install-oh-my-posh.sh)` / `# END` markers — re-run removes and re-adds, never appends

**Interactive menu** (current curated list):
`atomic` (default), `jandedobbeleer`, `agnoster`, `paradox`, `powerlevel10k_classic`, `powerlevel10k_lean`, `robbyrussell`, `star`, `tokyonight_storm`, `zash`. Any theme name from the [official theme gallery](https://ohmyposh.dev/docs/themes) also works via `--theme NAME`.

### cleanup-contamination.sh
**Purpose**: Detect and remove grok-code-fast-1 tool response contamination from files

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
```
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

### sprint-auto-bootstrap.sh

**Purpose**: Canonical, project-agnostic worktree bootstrap called by the `/sprint-auto` skill. Brings up an isolated docker-compose stack in a git worktree with sentinel-`.env` + port-offset override, then dispatches to optional project-local hooks for post-up init and smoke-test.

**How projects consume it**: via a ~30-LOC wrapper committed at `<project>/tools/sprint-auto-bootstrap.sh` that locates this canonical script and execs into it. Wrappers fail gracefully when mind-vault is missing (clear error + remediation); symlinks don't. Template: [`skills/sprint-auto/assets/sprint-auto-bootstrap.sh.wrapper`](../skills/sprint-auto/assets/sprint-auto-bootstrap.sh.wrapper).

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

**Project-local hooks** (optional, copy + edit): [`skills/sprint-auto/assets/sprint-auto-hooks.sh.example`](../skills/sprint-auto/assets/sprint-auto-hooks.sh.example) — declare `post_up_init()` (migrations, MinIO bucket setup, seed fixtures) and/or `smoke_test()` (HTTP health check, `pg_isready`, etc.).

**Full contract**: [`skills/sprint-auto/references/worktree-lifecycle.md`](../skills/sprint-auto/references/worktree-lifecycle.md).

## Adding New Tools

**Guidelines**:
1. Place scripts in this directory
2. Make them executable (`chmod +x`)
3. Add documentation to this README
4. Include usage examples
5. Follow naming: `[purpose]-[action].sh`

**Template for new tools**:
```bash
#!/bin/bash
# Description: What this tool does
# Usage: How to run it
# Author: Who wrote it
# Date: When it was created

set -e  # Exit on error

# Your script here
```

## Maintenance

- **Regular runs**: Run cleanup script after intensive AI agent work
- **Backup management**: Review and remove old .backup files periodically
- **Version control**: Commit tool improvements and new scripts

---

**Tools Directory**: `mind-vault/tools/`
**Last Updated**: 2026-01-27
