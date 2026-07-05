# Privilege-drop portability: `runuser` is not on Debian — use `setpriv` or `su`

A root script that needs to run a command **as another (usually service) account** — e.g. clone a
repo as the `docker` service user during setup — commonly reaches for `runuser -u <user> -- <cmd>`.
**`runuser` is a Red-Hat/`util-linux`-on-Fedora convention that Debian/Ubuntu do not ship** (Debian's
`util-linux` omits it). On a Debian target the script dies with `runuser: command not found` — and if
it's inside `set -e` it aborts mid-setup.

Confirmed on a Debian 13 host: `runuser` NOT FOUND; `setpriv` and `su` present (both `util-linux`).

## Portable choices (both on Debian)

### `setpriv` — the clean `runuser` equivalent (preferred in scripts)

```bash
# args passed DIRECTLY to the target — no shell re-parse, so no quoting fragility:
setpriv --reuid "$UID" --regid "$GID" --init-groups -- <cmd> <args...>
```

- Passes argv straight through (unlike `su -c "<string>"`), so a value containing spaces / `!` / `=`
  (e.g. a `git -c credential.https://…helper=!/path …` config) stays **one argument** — no nested
  quoting to get wrong.
- Sets **no environment** by default. If the command reads `$HOME` (git global config) or needs a
  runtime dir, wrap with `env`: `setpriv --reuid U --regid G --init-groups -- env HOME=/home/svc <cmd>`.
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

In scripts that must be portable across distros, **do not use `runuser`**. Use `setpriv … -- env
HOME=… <cmd>` for a clean argv-preserving drop, or `su -s /bin/bash <user> -c '…'` when you accept the
shell-string form. Add the tool you chose to the script's dependency preflight so a missing binary
fails loudly and early, not mid-run.
