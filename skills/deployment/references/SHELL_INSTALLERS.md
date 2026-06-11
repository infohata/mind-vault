# Shell Installer Conventions (`install/install-*.sh`)

Canonical reference for authoring and reviewing shell installer scripts under `install/install-*.sh`. Consolidates patterns surfaced across PR reviews of PRs #55 (install-gcloud-cli), #58 (wrap skill chown fallback), and #59 (install-mosh-tmux) — and the meta-disciplines that would have prevented most of them.

**When to consult:** before authoring a new `install-X.sh`, and when reviewing one (your own drill or the configured PR-review bot). This file is both the author-side checklist and the review-side pattern catalog — kept in one place so the two sides can't drift apart.

**Why a reference, not a rule:** rules always load into context. These patterns are deep devops-y edge cases that don't need to be in the agent's brain for every Django refactor. Loading on-demand when the `deployment` skill fires is the right cost/benefit.

## The meta-discipline: sweep, don't point-fix

> When you fix any one of the patterns below, `grep` the entire script for other sites with the same shape and fix them in the same commit. Point-fixes are the single most common way these issues leak into follow-up review cycles — each pattern tends to appear 2–5 times in a file of this size.

Cautionary example: PR #59 cycle 9 fixed one `ufw status | head -1` site for the SIGPIPE race. That commit didn't `grep` for other `| head -N` pipelines, so cycle 10 surfaced the second instance (`mosh-server --version | head -1` in the verify section) — one entire wasted review cycle because the fix was localised instead of swept.

Applies across all patterns below. When in doubt, `grep` first, fix second.

**Layering note:** the language-general entries below (1–3, 5, 8, 10, 11) are owned by the base [`shell`](../../shell/SKILL.md) layer — each keeps a stub here so the installer catalog numbering stays stable, with the full pattern one link down.

## Pattern catalog

### 1. `set -eo pipefail` — always, never bare `set -e`

Installers invariably have `curl | gpg`, `curl | bash`, `… | jq` pipelines; bare `set -e` only sees the last element's rc (failed curl → empty keyring → confusing downstream GPG error). Full hazard: [`shell` STRICT_MODE_HAZARDS.md §0](../../shell/references/STRICT_MODE_HAZARDS.md). *Provenance: PR #55 cycle 1 (install-gcloud-cli).*

### 2. `set -eo pipefail` + pipeline-in-assignment — silent abort

`VAR=$(getent … | cut …)` dies under pipefail *before* the friendly-error `if` below it runs; pre-validate the precondition (`id -u "$TARGET_USER"`) first. Full hazard + alternatives: [`shell` STRICT_MODE_HAZARDS.md §1](../../shell/references/STRICT_MODE_HAZARDS.md). *Provenance: PR #59 cycle 7.*

### 3. `set -eo pipefail` + `head -N` — SIGPIPE race

`head -1` closes stdin early; the producer exits 141; pipefail propagates it, falsifying the `if` or firing the `||` mask. Drop redundant `head` (an anchored regex already selects one line) or take the first line via parameter expansion. Full hazard: [`shell` STRICT_MODE_HAZARDS.md §2](../../shell/references/STRICT_MODE_HAZARDS.md). *Provenance: PR #59 cycles 9 & 10.*

### 4. `chown 'user:'`, not `'user:user'`

**Bad:**

```bash
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.bashrc"
```

This specifies the group by name, assuming `<user>:<user>` exists. Debian's `useradd -U` creates a per-user group by that name by default, but:
- RHEL/Fedora's `useradd -N` does not (falls back to `users` group).
- Directory-managed accounts (LDAP, sssd) commonly use a shared group.
- A hand-created user with `useradd -g users kestas` will fail `chown "kestas:kestas"`.

**Good:**

```bash
chown "$TARGET_USER:" "$TARGET_HOME/.bashrc"
```

Trailing colon instructs `chown` to use the user's primary group from `/etc/passwd`. Portable, unambiguous, works on every POSIX system.

*Provenance: PR #58 wrap SKILL fallback (compounded), PR #59 cycle 2 (4 leaked sites in install-mosh-tmux despite the prior fix) — the recurring leak is what motivated the sweep-don't-point-fix discipline at the top of this file.*

### 5. Arg validation before consuming `$2`

`--flag` run with no value makes `shift 2` eat the next flag; check `[ -z "${2:-}" ]` → friendly error before consuming. Canonical in-repo example: `install-gcloud-cli.sh` `--with-components`. Full pattern + the getopts-vs-manual decision: [`shell` QUOTING_AND_INPUT_HYGIENE.md](../../shell/references/QUOTING_AND_INPUT_HYGIENE.md). *Provenance: PR #59 cycle 2 drill.*

### 6. Idempotency check must respect user-requested flags

**Bad:**

```bash
if command -v gcloud >/dev/null 2>&1; then
    echo "✅ gcloud already installed."
    exit 0
fi
# ... later, the --with-components installation block
if [ -n "$EXTRA_COMPONENTS" ]; then
    apt-get install -y google-cloud-cli-*
fi
```

If the user runs `install-gcloud-cli.sh --with-components X` on a box that already has gcloud, the early exit fires and the component install is silently skipped. Exit 0 signals success but nothing was done.

**Good:**

```bash
if command -v gcloud >/dev/null 2>&1; then
    if [ -z "$EXTRA_COMPONENTS" ]; then
        echo "✅ gcloud already installed. Nothing to install."
        exit 0
    fi
    echo "ℹ️  gcloud present; installing requested components: $EXTRA_COMPONENTS"
    # fall through to component install
fi
```

Early-exit branches must check every flag that requests additional work. *Provenance: PR #55 HIGH.*

### 7. Marker blocks: fixed-string grep + escaped sed

**Bad:**

```bash
BEGIN_MARK="# BEGIN mind-vault-foo (managed by install-foo.sh)"
END_MARK="# END mind-vault-foo"

# Plain grep — regex mode:
if grep -q "$BEGIN_MARK" "$HOME/.bashrc"; then ...
# Plain sed — regex mode:
sed -i "/$BEGIN_MARK/,/$END_MARK/d" "$HOME/.bashrc"
```

The markers contain `.` (in `install-foo.sh`) and `(`, `)` — BRE/ERE metacharacters. On any edit that changes the marker text, the match semantics can shift unexpectedly. Worse: `sed /BEGIN/,/END/d` with a missing END line silently deletes from BEGIN to EOF, wiping unrelated user content.

**Good:**

```bash
# Fixed-string grep (literal match, no regex interpretation):
grep -qF "$BEGIN_MARK" "$HOME/.bashrc"

# Pre-compute BRE-escaped versions for sed address patterns:
BEGIN_MARK_RE=$(printf '%s' "$BEGIN_MARK" | sed -e 's/[][\/.*^$]/\\&/g')
END_MARK_RE=$(printf '%s' "$END_MARK" | sed -e 's/[][\/.*^$]/\\&/g')

# Explicit orphan detection — refuse early if BEGIN exists without END:
if grep -qF "$BEGIN_MARK" "$HOME/.bashrc" && ! grep -qF "$END_MARK" "$HOME/.bashrc"; then
    echo "❌ Orphan managed block: BEGIN marker without END marker." >&2
    echo "   Restore the '$END_MARK' line or delete the block by hand, then re-run." >&2
    exit 1
fi

# Now safe to range-delete:
if grep -qF "$BEGIN_MARK" "$HOME/.bashrc" && grep -qF "$END_MARK" "$HOME/.bashrc"; then
    sed -i "/$BEGIN_MARK_RE/,/$END_MARK_RE/d" "$HOME/.bashrc"
fi
```

*Provenance: PR #59 cycles 4, 5, 8 (three related findings, all rooted in one class).*

### 8. Security-sensitive input — `case`, not `grep -E`

`grep` matches per-line: `$'main\nmalicious'` passes an anchored regex on its first line while the newline still injects a second line into the target file. `case` matches the full string atomically. Full pattern + snippet: [`shell` QUOTING_AND_INPUT_HYGIENE.md](../../shell/references/QUOTING_AND_INPUT_HYGIENE.md). *Provenance: PR #59 cycle 6 (SESSION_NAME bashrc code injection via unquoted HEREDOC).*

### 9. Opt-out flag consistency — end-to-end sweep

When a script adds `--no-X`, **every** reference to feature X needs the `[ "$DO_X" = "1" ]` gate:

| Code section | Guard needed? |
|---|---|
| State check (is X installed/wired?) | Yes — state is only relevant if X is in scope |
| State display (✅/❌/n/a?) | Yes — show "n/a" when opted out, not "❌" |
| `--check` exit-code logic | Yes — a missing opted-out piece is not a failure |
| Orphan/precondition refusal | Yes — don't refuse on X's state if X won't be touched |
| Install/write block | Yes (usually already gated) |
| Verify summary after install | Yes — don't say "auto-attach wired" if `--no-autoattach` |
| Post-install-hints trailer | Yes — don't tell user to "edit ~/.bashrc" if untouched |

Adding a flag at one site and moving on is the most common way incomplete opt-outs leak into review. **Grep the file for every reference to the feature name before committing the flag addition.**

*Provenance: PR #59 cycles 4, 5, 6, 8 — five incomplete spots across four review cycles, all rooted in point-fix mindset when the class is cross-cutting.*

### 10. HEREDOC quoting — document your choice

Quoted `<<'EOF'` = zero expansion; unquoted = script-time vars expand (escape runtime ones as `\$VAR`); the comment above the heredoc must match the code. Full discipline: [`shell` QUOTING_AND_INPUT_HYGIENE.md](../../shell/references/QUOTING_AND_INPUT_HYGIENE.md). *Provenance: PR #59 cycle 2 drill.*

### 11. Substring traps in status checks

`grep -qi "active"` fires on "inactive" — anchor both ends (`^Status:[[:space:]]+active[[:space:]]*$`) for any token that is a substring of its own negation. Full pattern: [`shell` QUOTING_AND_INPUT_HYGIENE.md](../../shell/references/QUOTING_AND_INPUT_HYGIENE.md). *Provenance: PR #59 cycle 3 (HIGH).*

### 12. `.bashrc` blank-line accumulation (idempotency over time)

**Bad:**

```bash
cat >> "$BASHRC" <<BASHRCBLOCK

$BEGIN_MARK
# auto-attach logic
$END_MARK
BASHRCBLOCK
```

The leading blank line is OUTSIDE the `BEGIN/END` range. On re-run, sed strips only what's between the markers. The blank survives, and the next `cat >>` adds another blank ahead of the fresh block. Each re-run leaks one blank.

**Good — move the blank INSIDE the managed range:**

```bash
cat >> "$BASHRC" <<BASHRCBLOCK
$BEGIN_MARK

# auto-attach logic
$END_MARK
BASHRCBLOCK
```

Now sed reclaims the blank on re-run. Idempotency preserved. *Provenance: PR #59 cycle 5 (LOW).*

### 13. Target-user resolution

Under `sudo`, honour `$SUDO_USER` and write to that user's `$HOME`. Fall back to `$USER` only when not under sudo. `getent passwd "$user"` is the portable lookup. **Warn, don't silently proceed,** if resolution lands on root when a non-root user was intended.

```bash
if [ -z "$TARGET_USER" ]; then
    TARGET_USER="${SUDO_USER:-$USER}"
fi
if [ "$TARGET_USER" = "root" ]; then
    echo "⚠️  Target user resolved to root; rc file edits will land in /root."
    echo "    If you meant a non-root user, pass --target-user NAME."
fi
# Pre-validate existence BEFORE any pipeline-in-assignment:
if ! id -u "$TARGET_USER" >/dev/null 2>&1; then
    echo "❌ User '$TARGET_USER' does not exist on this system." >&2
    exit 1
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
```

### 14. Managed blocks over append-only

Configuration the installer touches goes inside `# BEGIN mind-vault-NAME (managed by install-NAME.sh)` / `# END mind-vault-NAME` markers. Re-runs strip the block and re-append, never append-duplicate. See pattern 7 for the grep/sed shape and orphan-detection discipline.

### 15. Installer effects require full session restart

Locale generation, new terminfo entries, updated `$PATH` from `.bashrc` edits — none of these take effect in shells that were already running when the installer ran. Post-install output should explicitly tell the user: **close every SSH/mosh session and `tmux kill-server` before the changes apply**. `source ~/.bashrc` is not enough; `tmux` caches terminfo at server start.

*Provenance: learned during PR #59 end-to-end testing on live remote — the script worked but the user's existing session didn't pick up the new locale/terminfo until a full disconnect.*

## Worked examples in-repo

The following scripts implement this reference correctly (most recent first — later scripts have the densest coverage):

- **`install/install-mosh-tmux.sh`** — covers patterns 1-14 after 11 review cycles on PR #59. The most complete example of what this reference is distilled from.
- **`install/install-gcloud-cli.sh`** — canonical `--with-components` arg validation (pattern 5), early-exit respects flags (pattern 6), `curl | gpg` with pipefail (pattern 1).
- **`install/install-docker.sh`** — canonical `id -u` pre-validation (patterns 2, 13), conflict-package removal, clean prerequisite install.
- **`install/install-oh-my-posh.sh`** — managed-block idempotency (pattern 14), target-user resolution (pattern 13), user-scope install (no sudo required).

When authoring a new `install-X.sh`, start by copying the closest existing installer and swapping out the product-specific install steps. The pattern coverage comes for free.

## Template for new tools

```bash
#!/bin/bash
# Description: What this tool does (one line — shown by --help).
# Usage: sudo ./install/install-X.sh [--check] [--flag VALUE]
# Supports: Debian 11+, Ubuntu 20.04+

set -euo pipefail   # new scripts take -u (see shell STRICT_MODE_HAZARDS.md § set -u edges)

CHECK_ONLY=0
# … default flag values …

while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK_ONLY=1; shift ;;
        --flag-with-value)
            if [ -z "${2:-}" ]; then
                echo "❌ --flag-with-value requires a value." >&2
                exit 1
            fi
            FLAG_VAL="$2"
            shift 2
            ;;
        -h|--help)
            awk 'NR==1 && /^#!/ { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
            exit 0
            ;;
        *)
            echo "❌ Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# … target-user resolution if the script touches user config …
# … validate security-sensitive flag values via `case`, not grep …

# State check (respect opt-out flags throughout):
# … $X_OK detection for each managed piece …
# … display with ✅/❌/"n/a" matching the exit-code logic …

if [ "$CHECK_ONLY" = "1" ]; then
    CHECK_FAIL=0
    [ "$DO_PIECE_X" = "1" ] && [ $X_OK -eq 0 ] && CHECK_FAIL=1
    # … one line per opt-out-gated piece …
    [ $CHECK_FAIL -eq 0 ] && exit 0
    exit 1
fi

# OS detection. Root check (if needed). Install. Verify.
# Post-install hints honour opt-out flags too. Remind the user to
# fully disconnect and reconnect for locale / terminfo / rc changes.
```

## Related

- [`skills/shell/SKILL.md`](../../shell/SKILL.md) — the base shell-language layer beneath this catalog; owns the hoisted language-general entries (1–3, 5, 8, 10, 11) plus cleanup traps, locking, and the live-host ops machinery.
- [`skills/review-loop/references/common-review-findings.md`](../../review-loop/references/common-review-findings.md) #15 — review-side pointer to this reference (drill discipline stays in the shared catalogue so the review loop knows where to look).
- `tools/README.md` "Adding New Tools" — author-side pointer to this reference.
- `../../sprint-auto/references/PARALLEL_WORKTREE_DOCKER.md` — when writing an installer that runs INSIDE a parallel-worktree stack, the gotchas there apply in addition.
