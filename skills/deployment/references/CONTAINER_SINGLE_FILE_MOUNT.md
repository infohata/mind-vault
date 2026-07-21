# Mounting ONE file into a container — the inode trap, the shadow trap, and how to test it

When a sidecar/renderer writes a config file that another container consumes (a proxy hot-reloading a
rendered routing fragment, a generator feeding an agent, any "process A writes, process B watches"
across a container boundary), you usually want to deliver **one file** into a directory the consumer
already has — without disturbing the directory's other, committed static files. Two Docker mount
behaviours make the obvious approaches fail **silently**, and the failure never shows at startup — it
shows on the *next* delivery (the second write, or the next image rebuild). Test accordingly.

## 1. A single-file (or `volume.subpath`) mount is INODE-bound

A bind mount of a single file (`-v /host/f:/ctr/f`) — and equally a `type: volume` mount with
`volume.subpath: f` — resolves to the target file's **inode at container-create time**. The kernel
mounts *that inode*, not the path. So:

- **An atomic-rename writer breaks it.** The safe-write idiom `write tmp; fsync; rename(tmp, f)` (what
  `os.CreateTemp`+`os.Rename`, most editors, and most "atomic config write" helpers do) creates a
  **new inode** and points the *name* at it. The container's mount still holds the **original** inode →
  the consumer is pinned to the first-ever content and **never sees an update**. No error anywhere; the
  writer reports success, the file on the host is correct, the container just silently serves stale.
- Startup works, updates don't — which is exactly why a startup-only smoke test passes it (§3).

**Fix — keep the inode stable, OR mount the directory:**

- **In-place write** into the mounted file: `open(f, O_WRONLY|O_CREATE|O_TRUNC)` then write (truncate +
  overwrite reuses the same inode). Lose the atomic-rename crash-safety for this one file — an
  interrupted write can leave a partial file, so pair it with a consumer that tolerates/re-reads on
  parse failure, or a confirm-then-commit protocol. For a hot-reloaded config the reader re-reads on
  the next change anyway.
- **Mount the parent directory** instead of the file. A directory mount tracks by **path**, so a
  renamed file inside it propagates normally. Costs you §2 (the mount replaces whatever the image
  committed at that path), so it only works when you own the whole directory.

## 2. A volume-at-a-directory SHADOWS committed content — and copy-up happens ONCE

The tempting way to drop one rendered file into a directory of committed static files is "mount a
volume at the directory." **The mount replaces the directory** — everything the image committed at
that path is hidden behind it. A *named volume* makes this worse by *looking* like it works: on FIRST
use of an empty volume, Docker copies the image's content into it (copy-up) — so the committed files
appear, then silently freeze at that first-use snapshot. A rebuilt image's updated files never reach
the volume; for a proxy whose routing is split across several committed files plus one rendered file,
the committed routes fossilise (or, with a host bind over the directory, vanish outright) — an
estate-wide outage from a mount-layout mistake. (Nested *explicit* binds, by contrast, DO compose:
Docker sorts mounts by destination path, so `-v /host/a:/ctr/dir/a` overlays a parent mount as
expected — the classic named-volume-at-`node_modules` pattern depends on exactly this.)

**Fix — overlay ONE file over a committed mountpoint:** keep the directory itself as ONE canonical
source (the image's committed content, or a single normal directory mount — no volume layered over
it), commit a valid **empty-but-parseable placeholder** at the target path (the mountpoint the
overlay lands on), and overlay just that one file via a single-file / `volume.subpath` mount. The
pattern stands on its own merits: no copy-up staleness, and overlaying an *existing* file needs no
create, so it works even under a read-only parent mount. (Then you're back in §1's world for that one
file — so the renderer must write in place.)

## 3. Isolation-test the WRITE CYCLE, not just container startup

Both traps above are invisible to the reflex test ("bring the stack up, does the consumer load the
file?"). Startup reads the mounted inode **once** — it's correct, so the test is green. The bug is that
the **second** delivery (the running writer's first re-render) never reaches the consumer. A load-only
isolation test certifies a delivery mechanism that is fundamentally broken for updates.

**The test must exercise the real writer's update path against a real consumer**, on the actual daemon:

1. Bring the consumer up on the committed placeholder; confirm it loads (baseline).
2. Have the **writer** render a change through its real code — not a shell `echo`/`cp` stand-in:
   those truncate in place, so they'd *pass* a propagation check the real atomic-rename writer fails.
3. Confirm the **consumer reflects the change** (hot-reload observed, new value served) — this is the
   assertion that catches the inode pin.
4. Assert the inode is stable across the write if you rely on §1's in-place fix
   (`stat -c %i` before/after must match).

A one-line operator-run script that does drop → render → re-read and tees the result to a file the agent
reads back is enough; the point is that the *rename-vs-truncate* behaviour only ever surfaces when a
genuine second write goes through the genuine mount (and §2's copy-up freeze only on the next image
rebuild — check that path too when routing files move into the image).

Pairs with [ROOTLESS_DOCKER.md](ROOTLESS_DOCKER.md) (verify on the box, an on-host check can be fooled)
and [TRAEFIK_EDGE_HARDENING.md](TRAEFIK_EDGE_HARDENING.md) (the file-provider edge that most often
consumes a single rendered fragment — and note its empty-config abort, a *different* silent-outage trap
in the same render-and-deliver pipeline).
