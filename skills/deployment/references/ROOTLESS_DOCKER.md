# Rootless Docker: deploy shells must resolve the rootless socket

After migrating a host from rootful to **rootless Docker** (daemon runs as the
deploy user, socket at `unix:///run/user/<uid>/docker.sock`, deploy user dropped
from the `docker` group), the **first automated deploy can fail in a way that
looks like a fresh install** — and the cause is shell environment, not code.

## The trap

`docker` / `docker compose` pick which daemon to talk to in this order:

1. the `DOCKER_HOST` env var, else
2. the active **docker CLI context** (`~/.docker/config.json` — a *file*), else
3. the default `/var/run/docker.sock` (the rootful socket — dead/inaccessible
   after a rootless migration).

A deploy commonly runs in a **non-login, non-interactive shell** — `screen … bash -c "…"`, a cron job, a systemd unit. Such a shell **does not source `~/.bashrc`/`~/.profile`**, so any `DOCKER_HOST` exported there is absent. If the host *also* has no rootless docker context set, the CLI falls through to the dead rootful socket → `permission denied while trying to connect to the docker API at unix:///var/run/docker.sock`.

The nasty part: an idempotent deploy script that branches on *"are services already running?"* via `docker compose ps | grep -q Up` reads **empty** (wrong socket) and concludes **"first-time deployment"** — then tries to build/recreate everything against a daemon it can't reach. The running stack is untouched (the script never reaches it), but the deploy is blocked.

This bites **only on real automated/remote runs**, never in an interactive SSH session (which *does* source the profile and sees `DOCKER_HOST`) — so it survives local testing and surfaces on the first production rollout.

## Two fixes (use both; #1 is the root fix)

### 1. Server-side — set the rootless context (shell-independent, recommended)

One-time, as the deploy user on the host:
```bash
docker context use rootless
docker context ls   # confirm: rootless *  ->  unix:///run/user/<uid>/docker.sock
```
The context lives in `~/.docker/config.json` (a **file**, read by every shell — login, non-login, cron, systemd), so it resolves the rootless daemon **without any env var**. A host with this set never hits the trap; a host relying only on a profile `DOCKER_HOST` does. This asymmetry is the usual "works on the rehearsal box, fails on the real one" discriminator — the rehearsal box had `docker context use rootless` run during setup; the production box didn't.

### 2. In-repo — self-correcting deploy scripts (defense-in-depth)

Source a tiny helper **early in the deploy entrypoint, before any `docker`/`docker compose` call** (and in any sub-script that can be invoked directly):

```bash
# ensure_docker_host.sh — export DOCKER_HOST to the rootless socket only when
# the default socket is unreachable AND a rootless socket exists.
if [ -z "${DOCKER_HOST:-}" ]; then
    _sock="/run/user/$(id -u)/docker.sock"
    if [ -S "$_sock" ] && ! docker info >/dev/null 2>&1; then
        export DOCKER_HOST="unix://$_sock"
    fi
    unset _sock
fi
```

Why the `! docker info` guard (not "switch whenever a rootless socket exists"):
it fires **only** when nothing else already resolves a working daemon — so it
auto-corrects the broken case, **no-ops on genuine rootful hosts** (default
socket answers), and **no-ops where the context already works** (fix #1 makes
`docker info` succeed). The two fixes compose: once the context is set the helper
never switches. `export` propagates to a script `exec`'d from the entrypoint.

## Checklist when adopting rootless Docker on a deploy target

- [ ] `docker context use rootless` run as the deploy user (verify `docker context ls`).
- [ ] Deploy entrypoint sources a `DOCKER_HOST` auto-detect helper before its first docker call.
- [ ] Any remote-deploy one-liner that uses `screen … bash -c` / cron / systemd exports `DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock` **inside** the non-login shell (belt; redundant once the context is set).
- [ ] Runbook does **not** claim "the profile exports DOCKER_HOST so it just works" — true only for interactive shells; automated deploys are non-login.
- [ ] Old rootful `/var/lib/docker` purge is a *separate, deferred* step (kept as the soak-window rollback), not part of the deploy.

## The scoped-sudoers operator model (no host-root hatch)

When the rootless daemon runs as a neutral **service account** (e.g. `docker`) and operators are a
group (e.g. `docker-ops`) who manage it via `sudo -u docker …` — **not** the `docker` unix group
(which is a host-root backdoor) — two traps follow from what that scoped sudoers does and does *not*
grant. A typical grant is only:

```text
%docker-ops ALL=(docker) /usr/bin/systemctl --user *, (docker) /usr/bin/docker *
```

- **`systemctl --user` via `sudo -u` needs `SETENV:` for `XDG_RUNTIME_DIR`.** `systemctl --user`
  must be told which user-manager to reach via `XDG_RUNTIME_DIR=/run/user/<uid>`, but sudo's
  `env_reset` refuses a caller-set env var unless the command is tagged `SETENV:`:
  `sudo: sorry, you are not allowed to set the following environment variables: XDG_RUNTIME_DIR`.
  Fix — scope `SETENV:` to the systemctl grant only (list `docker` first so the tag doesn't carry):
  ```text
  %docker-ops ALL=(docker) /usr/bin/docker *, (docker) SETENV: /usr/bin/systemctl --user *
  ```
  Then `sudo -u docker XDG_RUNTIME_DIR=/run/user/$(id -u docker) systemctl --user start <unit>`
  works. Without it, triggering a `systemd --user` deploy unit is impossible for operators.

- **First-time setup that runs *as* the service account needs break-glass ROOT, not scoped sudo.**
  The scoped grant permits `(docker) docker` and `(docker) systemctl --user` — **not** `git`, a
  login shell, or arbitrary file placement. So the one-time bootstrap (clone the repo as `docker`,
  place `~docker/.config/<app>/app.pem`, install the user unit) **cannot** be done via scoped sudo;
  it's a root/break-glass action (`su`/`setpriv` from root — see
  [../../shell/references/PRIVILEGE_DROP_PORTABILITY.md](../../shell/references/PRIVILEGE_DROP_PORTABILITY.md)).
  Routine ops afterward (`docker compose up -d`, `systemctl --user start`) *are* scoped-sudo. Design
  the runbook to separate the two: "one-time, root" vs "routine, scoped-sudo".

Related: [SCREEN_SESSIONS.md](SCREEN_SESSIONS.md) (non-login `screen … bash -c` is the most common trigger), [HARDENING.md](HARDENING.md) (the rootless migration + docker-group removal that creates this state), [ROOTLESS_DOCKER_OPENVZ.md](ROOTLESS_DOCKER_OPENVZ.md) (getting the daemon to *run at all* on a stripped cgroup-v1 OpenVZ node — a separate problem from this socket-resolution trap), [../../shell/references/SUDOERS_WHITELIST_FENCES.md](../../shell/references/SUDOERS_WHITELIST_FENCES.md) (sudoers whitelist hygiene), [../../shell/references/PRIVILEGE_DROP_PORTABILITY.md](../../shell/references/PRIVILEGE_DROP_PORTABILITY.md) (`setpriv`/`su` for dropping to the service account).
