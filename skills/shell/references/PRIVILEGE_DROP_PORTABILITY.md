# Privilege-drop portability: unqualified `runuser` dies off-PATH — use `setpriv` or `su`

A root script that needs to run a command **as another (usually service) account** — e.g. clone a
repo as the `docker` service user during setup — commonly reaches for `runuser -u <user> -- <cmd>`.
The trap is **PATH, not packaging**: Debian ships `runuser` in **`/usr/sbin`** (util-linux, since
at least buster), and `/usr/sbin` is NOT on the default PATH for non-root users and many
non-login / sanitized-PATH contexts (cron, CI runners, `su` without `-l`, `sudo -u <svc>` with
`secure_path` variants). An unqualified `runuser` there dies `runuser: command not found` — reading
as "Debian doesn't have it" when the binary is installed all along — and inside `set -e` it aborts
mid-setup.

Confirmed on Debian 13 and Debian 12 hosts: `/usr/sbin/runuser` present (shipped by `util-linux`),
but `command -v runuser` fails from a non-root shell whose PATH omits `/usr/sbin`; `setpriv` and
`su` live in **`/usr/bin`** — on PATH in every context.

## Robust choices (`/usr/bin`, on PATH everywhere)

### `setpriv` — the clean `runuser` equivalent (preferred in scripts)

```bash
# args passed DIRECTLY to the target — no shell re-parse, so no quoting fragility.
# (Don't name the variables UID/GID: in bash, UID is a READONLY builtin holding the
# CALLER's uid — as root that's 0, a silent root→root no-drop — and GID is a zsh-ism,
# unset in bash, so --regid "" errors.)
setpriv --reuid "$TARGET_UID" --regid "$TARGET_GID" --init-groups -- <cmd> <args...>
```

- Passes argv straight through (unlike `su -c "<string>"`), so a value containing spaces / `!` / `=`
  (e.g. a `git -c credential.https://…helper=!/path …` config) stays **one argument** — no nested
  quoting to get wrong.
- Inherits the **caller's environment untouched** (no PAM session, unlike `su`/`runuser`) — the
  target still sees root's `HOME=/root`, `XDG_RUNTIME_DIR`, etc. If the command reads `$HOME` (git
  global config) or needs a runtime dir, override with `env`:
  `setpriv --reuid U --regid G --init-groups -- env HOME=/home/svc <cmd>`.
- Requires root (needs `CAP_SETUID`/`CAP_SETGID`) — which the break-glass setup context already has.
- `--reuid`/`--regid` accept names on modern util-linux (≥2.33); numeric uid/gid is the safest.

### `su` — always present, but mind the quoting/env

```bash
su -s /bin/bash <user> -c '<command string>'
```

- The command is a **single string re-parsed by a shell** → embedding a value with spaces/specials
  needs careful nested quoting (the classic foot-gun). Prefer absolute paths and avoid inline
  `$HOME` expansion ambiguity.
- `su <user> -c` (no `-`/`-l`) on util-linux sets `HOME`/`SHELL`/`USER`/`LOGNAME` to the target by
  default; `su -` / `su -l` gives a full login environment. `su` from **root** needs no password;
  `su` from a non-root user prompts for the *target's* password (which fails for a locked service
  account — a frequent "why is it asking for a password?" during setup run in the wrong context).

## Rule of thumb

In scripts that must run across distros and execution contexts, **do not rely on an unqualified
`runuser`** — it's sbin-homed and off-PATH exactly in the automated contexts setup scripts run in.
Either invoke it by absolute path (`/usr/sbin/runuser`), or prefer `setpriv … -- env HOME=… <cmd>`
for a clean argv-preserving drop / `su -s /bin/bash <user> -c '…'` when you accept the shell-string
form — both `/usr/bin`-homed. Whichever you choose, add it to the script's dependency preflight so
a missing or unreachable binary fails loudly and early, not mid-run.
