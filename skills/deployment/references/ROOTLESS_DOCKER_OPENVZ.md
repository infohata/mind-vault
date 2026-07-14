# Rootless Docker on a stripped OpenVZ container — the system-unit recipe

Getting rootless Docker to *run at all* on an OpenVZ VPS is a separate problem from
getting a deploy shell to *find its socket* (that's [ROOTLESS_DOCKER.md](ROOTLESS_DOCKER.md)).
On a **stripped cgroup-v1-only OpenVZ container** — the kind of budget VPS that withholds
per-user systemd, delegated cgroups, the FUSE module, and a persistent `/dev/net/tun` — the
standard rootless install (`dockerd-rootless-setuptool.sh install` under `systemctl --user`
+ linger) never starts: `Failed to allocate manager object: Permission denied`, and
`/run/user/<uid>` never appears. The daemon isn't the problem; the node is lying about what
a normal Linux box provides.

The fix is a **root-owned system unit running the same rootless dockerd** (not the per-user
manager), plus five small compensations, each earning its keep against one specific,
reproducible error. Security is identical to standard rootless: the daemon runs as a
non-root service account, a container escape lands as an unprivileged uid, and there is no
`sudo docker` root hatch.

## Detect first — don't apply the heavy path everywhere

Only stripped nodes need this. The discriminator: can a per-user systemd manager start?

```bash
# as the target service user, with linger enabled:
systemctl --user show-environment >/dev/null 2>&1 && echo "user-manager OK" || echo "STRIPPED → system-unit path"
```

Modern cgroup-v2 OpenVZ and bare-metal boxes take the normal `systemctl --user` path.
Reserve the recipe below for boxes that fail that probe.

## The six layers (system-unit mode)

1. **Root-owned system unit instead of the per-user manager.** `docker-rootless.service`
   with `User=<docker-user>` and a systemd `RuntimeDirectory=docker-rootless`, so
   `/run/docker-rootless` stands in for the `/run/user/<uid>` the node won't create. This is
   what replaces `systemctl --user` + linger. Everything below is carried by this unit's
   ExecStart wrapper.

2. **A current static `crun` + a `crun --cgroup-manager=disabled` wrapper.** Distro `crun`
   (e.g. Ubuntu's 1.14.1) is too old → container-create fails with *"unknown version
   specified"*; and stock `runc` insists on creating a freezer cgroup → `EPERM` on the
   read-only v1 tree. Fetch a static crun ≥ 1.14.3 and point Docker at a wrapper that passes
   `--cgroup-manager=disabled` so it never tries to manage cgroups.

3. **A `dockerd-cgroupless` wrapper that stacks an empty tmpfs over `/sys/fs/cgroup`** inside
   rootlesskit's mount namespace. Without it, container-create `EPERM`s on the v1 cgroup
   *mount* — each controller bind-mount is refused on the read-only tree. Overmounting a
   fresh empty tmpfs inside the (private) rootlesskit ns hides the un-writable host cgroup fs
   from the container runtime without touching the host.

4. **`vfs` storage driver.** No `overlay2`-in-userns and no FUSE module on this box, so
   `fuse-overlayfs` isn't available either. `vfs` is slow and disk-hungry but always works;
   it's the correct trade on a node this stripped. Set `storage-driver: vfs` in the rootless
   `daemon.json`.

5. **`/dev/net/tun` persistence via tmpfiles.** The device node is absent in the container at
   boot and rootless networking (`slirp4netns`) needs it. A `tmpfiles.d` entry recreates it
   on every boot: `c! /dev/net/tun … 10:200 -` (plus a boot-time `mknod` for the current
   session).

6. **The usual usability layer, unchanged.** Socket **and runtime-dir** ACLs to a `docker-ops`
   group (two `ExecStartPost setfacl` grants, re-applied each daemon start so they survive
   reboots — see the mask trap below), `/etc/profile.d` pointing
   `DOCKER_HOST` at the socket for group members (so `docker compose up` needs no sudo), and a
   *run-as-the-docker-user* (NOT root) sudoers for daemon management
   (`sudo -u <docker-user> systemctl …`).

## The socket ACL survives reboots — but the *directory* ACL's mask silently doesn't

Layer 6 grants `docker-ops` via **two** `ExecStartPost setfacl` lines — one on the socket, one on its
parent runtime dir (`/run/docker-rootless`, a `0700` dir the daemon owns). The socket grant survives
every restart; the **directory** grant silently doesn't, and the daemon goes unreachable to the whole
`docker-ops` group *after each restart/reboot*:

```text
$ getfacl /run/docker-rootless
group:docker-ops:r-x    #effective:---     ← the grant is present…
mask::---                                   ← …but the mask caps it to nothing
$ namei -l /run/docker-rootless/docker.sock
drwx------ docker docker docker-rootless    ← 0700; no group traverse → sock unreachable
```

Cause: the daemon `chmod`s that runtime dir to `0700` **after** `ExecStartPost` runs, and a `chmod` of
the group bits **rewrites the POSIX ACL mask to `---`**, which caps every *named* ACL entry to nothing
(`#effective:---`). The socket's own ACL is perfect — you just can't `x` into the directory holding it →
`docker info` → `Cannot connect to the Docker daemon … permission denied`. It reads like a dropped
grant; it's a **masked** one. The socket line escapes this only because it `[ -S <sock> ]`-**waits** for
the socket before its `setfacl`, landing *after* the daemon's chmod.

Fix — merge both grants into one `ExecStartPost` that (a) waits for the socket (as the socket line
already did) and (b) sets the mask explicitly so a later chmod can't neuter it. Note the paths: in a
*system* unit `%t` is `/run` (the runtime-directory *root*), so the `RuntimeDirectory=docker-rootless`
subdir must be spelled out:

```ini
ExecStartPost=/bin/sh -c 'for _ in $(seq 1 50); do [ -S %t/docker-rootless/docker.sock ] && break; sleep 0.1; done; \
  /usr/bin/setfacl -m g:docker-ops:rx -m m::rx %t/docker-rootless && \
  /usr/bin/setfacl -m g:docker-ops:rw -m m::rw %t/docker-rootless/docker.sock'
```

One-shot repair on a live box (no restart): `setfacl -m g:docker-ops:rx -m m::rx /run/docker-rootless`.
General rule: **an ACL entry on a mode-0700 object is a trap — any `chmod` rewrites the mask to its
group bits, so a `0700` re-assert resets it to `---` and silences every named entry. Set `m::`
alongside the named entry, and re-assert both after anything that chmods.**

## Ports below 1024

Rootless can't bind `<1024` unless `net.ipv4.ip_unprivileged_port_start` is lowered, and
OpenVZ often locks that sysctl. Try to set it (`sysctl -w net.ipv4.ip_unprivileged_port_start=80`);
if the kernel refuses, **don't fight it** — serve 80/443 from a thin rootful nginx (or a
central edge) that proxies to the rootless app on a high port. Lowering the start to 80 is
enough for a web tier; you don't need it at 0.

## Gotchas that look like other bugs

- **"Works on the rehearsal box, fails on the real one."** The rehearsal box was probably a
  cgroup-v2 node that took the user-manager path; the target is stripped cgroup-v1. Probe
  cgroup version + per-user-manager availability per box, not once for the fleet.
- **Non-fatal `mknod`/tmpfiles noise at boot** is expected on some nodes — the tmpfiles entry
  is the persistent fix; the boot `mknod` just covers the current session.
- **Container stuck in `Created`, `compose up` hangs, `slirp4netns` spins?** That is NOT an OpenVZ
  quirk — it is the generic rootlesskit **dual-port-publish wedge** (same host port on two IPs). It
  just tends to surface here first, because stripped boxes force the slirp4netns/builtin driver combo.
  See [ROOTLESS_DOCKER.md](ROOTLESS_DOCKER.md).
- **After restarting the daemon here** (system-unit mode: `systemctl restart <your-unit>`, not
  `systemctl --user restart docker`), re-check `docker ps -a` — containers exiting non-zero on SIGTERM
  stay down despite `restart: unless-stopped`. Generic Docker behaviour, documented in
  [ROOTLESS_DOCKER.md](ROOTLESS_DOCKER.md); it bites harder here because the system-unit path makes
  daemon restarts a routine part of the recipe.
- Kernel version alone is NOT the discriminator — a 4.19 OpenVZ box and a 6.x one can *both*
  need this recipe or *both* not; unprivileged user namespaces being enabled is necessary but
  the withheld pieces (per-user manager, cgroup delegation, FUSE, tun) are what decide. Gate
  on the symptom probe, not on `uname -r`.

## Checklist

- [ ] Probe: does `systemctl --user` start for the service user? If yes, use the standard
      rootless path, not this one.
- [ ] Static `crun` ≥ 1.14.3 installed; Docker pointed at a `--cgroup-manager=disabled` wrapper.
- [ ] `dockerd-cgroupless` wrapper overmounts an empty tmpfs on `/sys/fs/cgroup` in the rootlesskit ns.
- [ ] `daemon.json`: `storage-driver: vfs`.
- [ ] `tmpfiles.d` recreates `/dev/net/tun` on boot.
- [ ] `docker-rootless.service` (root-owned, `User=<docker-user>`, `RuntimeDirectory`); **both** the
      socket AND its parent-dir ACL re-applied by `ExecStartPost` — each *waiting for the socket* and
      setting `m::` explicitly (a 0700 dir's ACL mask is clobbered by the daemon's chmod otherwise).
- [ ] Port strategy decided (`ip_unprivileged_port_start` lowered, or rootful/edge proxy for 80/443).

Related: [ROOTLESS_DOCKER.md](ROOTLESS_DOCKER.md) (the deploy-shell socket-resolution trap that
bites *after* the daemon is up), [HARDENING.md](HARDENING.md) (the non-root daemon / docker-group
removal this builds on).
