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

### install-gcloud-cli.sh
**Purpose**: Install [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (`gcloud`) on Debian/Ubuntu from Google's official apt repo (not the `curl | bash` convenience script).

**Problem Solved**:
- Projects talking to GCP (Cloud Storage, Pub/Sub, Cloud Run, Secret Manager, GKE, etc.) need `gcloud` on PATH
- The curl-bash installer drops an SDK into `$HOME` — poor fit for VPS / shared hosts where multiple users expect `gcloud` system-wide
- Google's own apt docs still show the deprecated `apt-key add` flow; copy-pasting it each time is error-prone

**Usage**:
```bash
# From repo root (requires sudo)
sudo ./tools/install-gcloud-cli.sh                                   # full install
sudo ./tools/install-gcloud-cli.sh --check                           # reports current state, no writes
sudo ./tools/install-gcloud-cli.sh --with-components gke-gcloud-auth-plugin
sudo ./tools/install-gcloud-cli.sh --with-components gke-gcloud-auth-plugin,cloud-sql-proxy
```

**Features**:
- ✅ Idempotent: exits early if `gcloud` is already installed and reports a version
- ✅ `--check` flag for a dry run (exit 0 if installed, 1 if missing)
- ✅ Uses dearmored keyring under `/usr/share/keyrings/` + `signed-by=` — no deprecated `apt-key`
- ✅ Arch-pinned repo line so multi-arch hosts don't try foreign arches
- ✅ `--with-components` auto-installs extra packages (`google-cloud-cli-<component>`) alongside the base CLI
- ✅ System-wide install; auto-upgrades via `apt upgrade`
- ✅ Clear post-install hints (`gcloud init`, `gcloud auth login`, `gcloud auth application-default login`)

**Supported**: Debian 11+ (bullseye, bookworm, trixie), Ubuntu 20.04+ (focal, jammy, noble, later).
**Not supported**: RHEL / Fedora / Arch (each needs a different repo — see the [official install matrix](https://cloud.google.com/sdk/docs/install)).

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

### install-mosh-tmux.sh
**Purpose**: Install and configure `mosh` + `tmux` for resilient SSH sessions on Debian/Ubuntu — survives spotty networks, laptop sleep, cell-tower handoffs, and long-running agentic CLI sessions (Claude Code, bugbot-loop's `ScheduleWakeup` cycles) without losing context.

**Problem Solved**:
- SSH over unstable links drops → shell + running CLI tool both die → re-login, lose context, re-orient. For long Claude Code sessions (sprint workflows, bugbot loops, plan/work/compound cycles) this happens repeatedly.
- Manual mosh + tmux setup is three orthogonal pieces (apt install, tmux.conf defaults, bashrc auto-attach snippet, firewall rule) — easy to half-do and end up with no auto-attach or a broken terminal inside tmux.
- Each piece alone is documented; the integration ("seamless" — drop into SSH, land in the same tmux pane you left yesterday) takes opinionated gluing.

**Usage**:
```bash
# Full install + config (needs sudo for apt + ufw)
sudo ./tools/install-mosh-tmux.sh

# Report current state — no writes (exit 1 if incomplete)
sudo ./tools/install-mosh-tmux.sh --check

# Custom session name (default: "main")
sudo ./tools/install-mosh-tmux.sh --session-name teisutis

# Skip pieces you handle differently
sudo ./tools/install-mosh-tmux.sh --no-ufw --no-tmux-config
```

**Features**:
- ✅ Idempotent: all three managed pieces (`~/.tmux.conf`, `~/.bashrc` snippet, ufw rule) use BEGIN/END markers or port-range pinning so re-runs overwrite instead of duplicate; existing unmanaged `~/.tmux.conf` is backed up before the first write.
- ✅ `--check` flag reports each piece independently (packages installed, tmux.conf managed, bashrc wired, ufw rule present).
- ✅ Targets the invoking user's home (`$SUDO_USER`), not root's — override with `--target-user`.
- ✅ Auto-attach is SSH-only (`$SSH_CONNECTION` + `-t 0` guards) so scp/rsync/cron aren't affected; skips if already inside tmux.
- ✅ UFW rule only fires if ufw is *active*; inactive ufw or missing ufw surfaces a reminder about cloud-provider firewalls instead.
- ✅ Prints client-side reminder that mosh needs a mosh-client on the laptop too.

**Tmux config defaults** (written inside BEGIN/END markers; your customisations outside the block survive re-runs):
- `mouse on` + scrollback 50000 lines
- `default-terminal "tmux-256color"` + truecolor overrides
- `escape-time 10ms` (default 500ms breaks vim-style navigation)
- `focus-events on`, pane/window indices from 1
- `Ctrl-b r` reloads config
- Minimal status bar: `[session] hostname · YYYY-MM-DD HH:MM`

**Bashrc snippet** (BEGIN/END marker-bounded):
```bash
if [ -z "$TMUX" ] && [ -n "$SSH_CONNECTION" ] && [ -t 0 ] && command -v tmux >/dev/null 2>&1; then
    _mv_session="${TMUX_DEFAULT_SESSION:-main}"
    tmux attach -t "$_mv_session" 2>/dev/null || tmux new-session -s "$_mv_session"
fi
```

**Why this combo (and not just one of them)**:
- `tmux` alone: survives server-side shell loss when SSH drops, but reconnecting still takes a new SSH handshake + `tmux attach` round-trip; fragile on very spotty links.
- `mosh` alone: survives connection drops transparently, but doesn't survive the server-side process dying (or explicit logout/reboot). No persistent session state.
- Both: network drops are invisible (mosh), server-side process keeps running (tmux), laptop sleep reconnects transparently. The bashrc snippet means every fresh login also ends up in the same tmux session — no typing `tmux attach` manually.

**Supported**: Debian 11+ (bullseye, bookworm, trixie), Ubuntu 20.04+ (focal, jammy, noble, later).
**Not supported**: RHEL / Fedora / Arch (each needs a different package manager — left for a later PR).

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

### Conventions for installer scripts (`install-*.sh`)

This class of script has a recurring set of traps that keep leaking into each new installer — bugbot or my own drill has had to re-flag the same issues across PRs #55 / #58 / #59. The `agents/AGENT_bugbot.md` §9 checklist codifies them for the drill side; **authoring side, the short list**:

- **Use `set -eo pipefail`, never bare `set -e`.** Installers pipe curl into gpg, jq, tee — a failing head of the pipe must abort the script, not write an empty / truncated file downstream.
- **`set -eo pipefail` interacts badly with pipeline-in-assignment.** `VAR=$(cmd | filter)` inherits the pipeline's exit status; a failing `cmd` kills the script *before* the `if [ -z "$VAR" ]` friendly-error block runs. Guard the precondition (`id -u "$USER" >/dev/null 2>&1`) before the pipeline, or split `VAR=$(cmd)` / `echo "$VAR" | filter` across two lines with explicit checks between. Symptom: script exits with no output when the user passes a bad `--target-user`.
- **`set -eo pipefail` + `head -N` closes the pipe early.** `producer | head -1 | grep …` in an `if` condition: if `producer` outputs many lines, `head` closes stdin after reading one, `producer` gets SIGPIPE on the next write, pipeline exit status becomes 141, pipefail treats the whole thing as failure, `if` is false even when grep matched. Often `head -N` is redundant with a downstream anchored regex — drop it. Otherwise split the pipeline (`VAR=$(producer); echo "$VAR" | head -1 | grep …`).
- **`chown` uses `user:` (trailing colon), not `user:user`.** The trailing colon asks chown to use the user's primary group from `/etc/passwd`; `user:user` assumes the group name equals the username, which is a Debian default but not a universal guarantee. `user:user` has now leaked into two PRs in a row — fix it once, write it right next time.
- **Validate args with required values before consuming.** `--flag VALUE` must `[ -z "${2:-}" ] && die` before `VAR="$2"; shift 2`; otherwise a dangling flag silently sets VAR to empty and `shift 2` misbehaves. See `install-gcloud-cli.sh` `--with-components` for the right shape.
- **Idempotency must respect all flags.** A "gcloud already installed → exit 0" check that ignores `--with-components` silently drops the user's request. Structure the early-exit to skip only when the additional flags are also absent.
- **Marker blocks use fixed-string matching.** `BEGIN mind-vault-foo (managed by install-foo.sh)` contains `(`, `)`, `.` — regex metacharacters. Grep it with `-qF`, not bare. Sed's `/MARK/,/MARK/d` still treats metacharacters as regex; either use fixed alt-delimiters (`\|MARK|,\|MARK|d`) or strip the metacharacters from the marker string. **Equally important**: gate the sed on BOTH BEGIN *and* END being present, and refuse early (clear error) if an orphan BEGIN-without-END is detected — otherwise `/BEGIN/,/END/d` opens an unclosed range and deletes from BEGIN to EOF, wiping unrelated user content.
- **Validate security-sensitive string input with `case`, not `grep -E`.** `grep` matches per-line; a newline-containing input passes anchored-regex validation because *some* line matches, yet the newline still injects. Use `case "$value" in *[!allowed-chars]*) fail ;; esac` to match the full string.
- **Opt-out flags cross-cut the whole script — sweep end-to-end.** When you add `--no-X`, every place that references feature X needs the `[ "$DO_X" = "1" ]` gate: state check (is it installed/wired?), state display (✅/❌/n/a?), `--check` exit code, orphan/precondition refusal, install block, verify summary after install, post-install-hints trailer. Adding a flag at one site and moving on is the most common way incomplete opt-outs leak into review. Grep the file for every reference to the feature name before committing the flag.
- **HEREDOC quoting is a minefield.** `<<TAG` expands `$`-refs in the body (script-time); `<<'TAG'` does not. When the body has both kinds (wants `$BEGIN_MARK` expanded, wants `$SSH_CONNECTION` kept literal), keep the tag unquoted and backslash-escape the runtime vars (`\$SSH_CONNECTION`). Whichever choice you make, document it — a comment that says "single-quoted" above an unquoted HEREDOC is worse than no comment.
- **Target-user resolution.** Under `sudo`, honour `$SUDO_USER` and write to that user's `$HOME`; fall back with care. `getent passwd "$user"` is the portable lookup. Warn (don't silently continue) if resolution lands on root when a non-root user was intended.
- **Managed blocks over append-only.** Configuration touched by the installer goes inside `# BEGIN mind-vault-NAME (managed by install-NAME.sh)` / `# END mind-vault-NAME` markers so re-runs replace cleanly instead of appending duplicates.

**Template for new tools** (follows the conventions above):

```bash
#!/bin/bash
# Description: What this tool does (one line — shown by --help)
# Usage: How to run it (sudo? flags?)
#
# Why: the 2–3 sentence rationale. Skip "author" and "date" — git blame
# has both and they rot when anyone else edits the file.

set -eo pipefail

# parse flags, resolve target user, check state, do work — see
# tools/install-gcloud-cli.sh or tools/install-mosh-tmux.sh for the
# shape.
```

## Maintenance

- **Regular runs**: Run cleanup script after intensive AI agent work
- **Backup management**: Review and remove old .backup files periodically
- **Version control**: Commit tool improvements and new scripts

---

**Tools Directory**: `mind-vault/tools/`
**Last Updated**: 2026-01-27
