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

## Operator-owned config ↔ `sudo -u docker` don't mix — pick one identity for the whole stack

A subtler fork in the scoped model: **who owns the compose files, `.env`, and config the daemon
mounts?** Two coherent choices, and mixing them wedges you:

- **Run-as-service-account:** config lives under `~<docker-user>/` (service-account-owned), driven via
  `sudo -u docker … docker compose …`. The account reads its own config and reaches its own daemon.
  Clean, but every config edit is a `sudo -u docker`/root write.
- **Operator-as-self:** config lives in the *operator's* checkout, driven **as the operator** — reaching
  the daemon through the shared-socket ACL (`DOCKER_HOST` + `docker-ops`, no `sudo`). The operator reads
  its own checkout; the daemon (service account) does the container ops.

The trap is `sudo -u docker docker compose` while the config is **operator-owned**: the service account
**cannot traverse the operator's `0700`/`0750` home** to read the compose file or `.env` →
`stat /home/<operator>/…/.env: permission denied`, and compose never starts. So don't `sudo -u docker`
against an operator-owned checkout — either move config under `~<docker-user>/` (fully
run-as-service-account) or drive compose as the operator via the socket ACL. Config the daemon mounts
from an operator-owned path also needs a privileged copy step (`sudo rsync` into the mount root), since
the operator can't write under a service-account-owned parent dir.

## Host-written, container-read files need the container's SUBUID, not its in-image uid

A file written **on the host** and read by an **unprivileged rootless container** is subject to the
userns remap: the container's in-image uid `N` is **not** host uid `N` — it maps to host
`subuid_base + N − 1` (`/etc/subuid`). So a secret placed `install -o 65534 -g 65534 -m 0600 …` (host uid
65534) is **"other"** to a container running as in-image `65534` (host `subuid_base+65533`) → `0600`
denies it → config-load **permission-denied crash** that looks like a bad file, not a uid one. Own it as
the **subuid** (read the live file's owner with `stat -c %u:%g`, or compute from `/etc/subuid`), keep
`0600`. This is the rootless twin of the ordinary "chown the bind mount to the container uid" rule — the
number is just remapped. A render step that re-`install`s the file every deploy must **preserve the
subuid owner** (`stat` the live file), not re-hardcode the in-image uid.

## Publishing the SAME host port on TWO IPs WEDGES the daemon (rootlesskit builtin port driver)

Rootless Docker cannot publish one container port on two host IPs. This:

```yaml
ports:
  - "127.0.0.1:3100:3100"      # operator convenience
  - "${VLAN_IP}:3100:3100"     # the one clients actually need
```

**deadlocks rootlesskit's builtin port driver** (`--net=slirp4netns --port-driver=builtin`). Each
publish ALONE is fine; the pair is fatal.

**Symptoms** — none of which point at ports, which is why this costs hours:
- the container sits in **`Created`** forever and never starts (so it has **no logs** — nothing ran);
- `docker logs` / `inspect` / `rm -f` **on that container hang** (the daemon holds its lock) while
  `docker ps`, `docker volume inspect`, and other containers are perfectly responsive;
- `docker compose up` blocks indefinitely; `slirp4netns` spins at 100% CPU.

**Diagnose in 30s** with a throwaway — this is the whole test:

```bash
docker run -d --rm -p 127.0.0.1:13199:80 busybox sleep 60              # fine
docker run -d --rm -p 10.0.0.5:13198:80  busybox sleep 60              # fine
docker run -d --rm -p 127.0.0.1:13197:80 -p 10.0.0.5:13197:80 busybox sleep 60   # WEDGES
```

**Fix:** publish ONE IP. If the host needs local access, reach the service on the same non-loopback
address it already publishes — the host can always talk to its own IP. Drop the loopback line.

**Recovery:** only a daemon restart clears the lock (`systemctl restart docker-rootless`), then
`docker rm -f` the `Created` husk. See the restart trap below before you do it.

## A rootless daemon restart can silently leave services DOWN (`unless-stopped` is not a guarantee)

After `systemctl restart docker-rootless`, containers that exit **0** on SIGTERM are restarted by
Docker; containers that exit **non-zero** (observed: **255**) are **left stopped** — even with
`restart: unless-stopped`. Observed on a monitoring stack: Prometheus + Grafana came back, while
**Alertmanager + blackbox_exporter stayed down**, so alerting died silently while the dashboards
looked healthy.

**Always `docker ps -a` after restarting the daemon** and start what didn't return:

```bash
systemctl restart docker-rootless
docker ps -a --format '{{.Names}}\t{{.Status}}'        # look for Exited, not just Up
docker start <the ones that stayed down>                # no compose needed
```

Restarting the daemon to clear a wedge (above) is exactly when this bites: you fix one container and
take down two others without noticing. Prefer `docker start` over `compose up` here — if the wedge
came from a bad compose file, `up` re-triggers it.

## Published ports MASQUERADE the client source IP (silently breaks per-IP anything)

Rootless Docker's **default port driver** (rootlesskit "builtin") source-NATs inbound connections to
published ports: the app behind the port sees the **bridge gateway** (`172.18.0.1`-style) as the
client, **not the real remote IP**. So a reverse proxy behind a rootless-published `:443` sees
**every external client as one address**, and:

- **per-IP rate-limiting collapses to global** — one shared bucket for the whole internet; one abuser
  throttles everyone, and legit aggregate traffic shares one budget.
- **access logs / geo rules / IP allow-deny lists are blind** — everything reads the gateway IP.

This bites **only under real external traffic** and is invisible on a single-client test — surface it
by **load-testing and reading what the backend echoes** (a `whoami`-style backend's `X-Forwarded-For` /
`X-Real-Ip` will show the gateway IP, not your public IP). The proxy's `sourceCriterion`/`RemoteAddr`
config is **correct**; the fix is below it, in the host's rootless networking:

- Switch to a driver combo that **preserves source IP**: port driver **`slirp4netns`**
  (`DOCKERD_ROOTLESS_ROOTLESSKIT_PORT_DRIVER=slirp4netns` — throughput cost vs `builtin`), or the
  newer **`pasta` *network* driver** (`DOCKERD_ROOTLESS_ROOTLESSKIT_NET=pasta` + port driver
  `implicit` — faster, still experimental). On Docker ≥ v29.5 (RootlessKit v3.0) the default
  `builtin` port driver propagates **TCP** source IPs when the daemon sets
  `{"userland-proxy": false}`. All are **daemon-config changes** (systemd override on the rootless
  daemon unit), not app config; weigh throughput vs. correctness for an edge.
- **Blast radius — know which hosts the change even reaches.** A net-stack env change applies to only
  one of the installer's two run modes: *user-manager* mode (full-kernel box, cgroup-v2, daemon under
  the user's `systemd --user`) — where the override lands and the fix takes — versus *system-unit* mode
  (container-guest box, e.g. OpenVZ with a read-only cgroup-v1, daemon from a root-owned
  `docker-rootless.service`), a bespoke fragile net stack that must be **carved out** of a rollout
  unless separately proven (see [ROOTLESS_DOCKER_OPENVZ.md](ROOTLESS_DOCKER_OPENVZ.md)). "Switch the
  fleet to `pasta`" really means "switch the user-manager hosts" — enumerate each host's mode **before**
  claiming coverage.
- **Verify BOTH directions — a net-stack swap can silently kill EGRESS.** Changing the rootless net
  stack re-plumbs the container's *outbound* path too, and it can break egress while inbound still
  serves (rootlesskit #434-class). For a TLS edge this is a delayed-action failure: **ACME renewal is
  outbound HTTPS to the CA and isn't attempted until ~30 days pre-expiry**, so broken egress **passes
  every inbound smoke test** (`:443` serves, source IP correct, rate-limit per-IP) and then **expires
  the cert weeks later → edge down**. Inbound liveness ≠ egress health — gate the rollout on an
  **active outbound probe from inside the container**, e.g.
  `docker exec <proxy> wget -qO- https://acme-v02.api.letsencrypt.org/directory`, returning the
  CA directory JSON (no pipe after it — without `pipefail` a pipe masks `wget`'s exit code and the
  gate fails open; with `pipefail`, a `| head` can SIGPIPE a healthy fetch into a false alarm).
  Then confirm inbound: a request from a known external IP shows **that IP** in the
  backend echo, and a per-IP limit throttles one client without touching a second — and **read the
  source IP from an external host**, since a box curling its own public IP hairpins and won't
  round-trip HTTP (the TLS handshake can still complete, masking it).

## Driving `systemctl --user` for the service account FROM root — `su`, not `--machine`

To trigger a `systemd --user` unit owned by the (lingering) service account as **root** (break-glass,
when the scoped `SETENV:` grant isn't in place):

- `systemctl --machine=<user>@ --user start|status <unit>` **works** for start/status, BUT
  **`journalctl --machine=<user>@ --user`** commonly **FAILS** — `org.freedesktop.machine1 … No route
  to host` — it needs `systemd-machined`'s journal path, absent on many minimal hosts.
- **Robust, machined-independent path (use uniformly):**
  ```bash
  u=$(id -u <svcuser>)
  su -s /bin/bash <svcuser> -c "XDG_RUNTIME_DIR=/run/user/$u systemctl --user start <unit>"
  su -s /bin/bash <svcuser> -c "XDG_RUNTIME_DIR=/run/user/$u journalctl --user -u <unit> -n 60 --no-pager"
  ```
  `su` makes the uid the service account, so `systemctl/journalctl --user` reach that account's user
  manager via `XDG_RUNTIME_DIR` with no machined dependency. A `Type=oneshot` `start` **blocks until
  done** → verify the **outcome** (unit's effect), since a completed oneshot shows `inactive (dead)`.

Related: [SCREEN_SESSIONS.md](SCREEN_SESSIONS.md) (non-login `screen … bash -c` is the most common trigger), [HARDENING.md](HARDENING.md) (the rootless migration + docker-group removal that creates this state), [ROOTLESS_DOCKER_OPENVZ.md](ROOTLESS_DOCKER_OPENVZ.md) (getting the daemon to *run at all* on a stripped cgroup-v1 OpenVZ node — a separate problem from this socket-resolution trap), [../../shell/references/SUDOERS_WHITELIST_FENCES.md](../../shell/references/SUDOERS_WHITELIST_FENCES.md) (sudoers whitelist hygiene), [../../shell/references/PRIVILEGE_DROP_PORTABILITY.md](../../shell/references/PRIVILEGE_DROP_PORTABILITY.md) (`setpriv`/`su` for dropping to the service account).
