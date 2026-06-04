# Bare-metal atomic-release deploys (Ansible + PHP-FPM, shared host)

Companion reference to [`../SKILL.md`](../SKILL.md). The SKILL body covers the **containerised** Docker-Compose pattern. This file covers the *other* common production shape: a **non-containerised, bare-metal site** under `/var/www`, served by an already-installed PHP-FPM + Nginx, deployed via **Ansible** using **atomic releases** (timestamped dir + a `current` symlink). It's the dominant pattern for Laravel/PHP on shared/managed hosting where Docker isn't on the table.

Most of what follows is framework-agnostic (atomic-swap, symlink depth, connection-user precedence, ansible-core pinning); the Laravel-flavoured items (`artisan`, `storage:link`) call out the framework explicitly.

## The meta-lesson: local/CI green ≠ host green

The single most important thing to internalise before authoring a bare-metal deploy playbook: **a first deploy against a real shared host surfaces a cascade of environment-mismatch bugs that no amount of local or CI testing catches.** The local controller, the CI runner, and the target host disagree about PHP version, available DB privileges, installed Composer packages, Python floor, and filesystem state — and every one of those disagreements is invisible until the playbook runs against the real host for the first time.

Budget for it. The first end-to-end deploy is not "run the playbook and it works" — it's "run the playbook, read the first failure, fix the environment assumption, re-run, repeat." A clean local `ansible-playbook --syntax-check` and a green CI lint tell you nothing about whether `php` resolves to the right version on the host or whether the DB user has `RELOAD`. Expect a short hotfix series, and capture each fix so the *next* project's first deploy starts above the floor.

The traps below are that series, generalised. They cluster into four buckets: **atomic-swap mechanics**, **the symlink/shared-state model**, **host environment mismatches**, and **the Ansible controller/target contract**.

## Atomic-swap mechanics

### `ln -sfn` nests inside a real directory — use `mv -Tf`

The naïve atomic swap is `ln -sfn releases/<ts> current`. It works only while `current` is already a symlink (or absent). **If `current` is a real directory, `ln -sfn` silently creates the link *inside* it** (`current/<ts>`) instead of replacing it — so the server keeps serving the stale directory and every subsequent deploy nests another link, never swapping.

How `current` becomes a real directory on a cold host: a bootstrap step runs *before* the first release exists and creates it. The anchor case was cold-start TLS issuance — `acme.sh -w .../current/public` created `current/` (with a `public/` webroot) as the ACME challenge root, so the site served the leftover webroot ("mock page") and no deploy ever dislodged it.

Self-healing swap:

```bash
# If `current` is a real directory (not a symlink), move it aside first so the
# link can't nest. Non-destructive — keeps the dir as current.predeploy-<ts>.
if [ -d current ] && [ ! -L current ]; then
    mv current "current.predeploy-$(date -u +%Y%m%d%H%M%S)"
fi
ln -sfn "releases/<ts>" current.new
mv -Tf current.new current
```

`mv -Tf` (`--no-target-directory`, `--force`) replaces a symlink **atomically** and **refuses to clobber a directory** — so the swap is both atomic and self-healing: a stray real `current` gets moved aside instead of nested into. Document the cold-start cause wherever the deploy is described, because the symptom (stale page, deploys "succeed" but nothing changes) points nowhere near the cause.

## The symlink / shared-state model

Atomic releases share mutable state (`.env`, `storage`, framework caches) across releases via symlinks from each release dir into a sibling `shared/` tree. Three traps live here, all about getting the symlink topology right.

### Exclude symlink *targets* from the release sync

The release step rsyncs the build artifact into `releases/<ts>/`, then symlinks shared paths (`.env`, `storage`, `bootstrap/cache`) into it. **Any path you intend to symlink must be excluded from the rsync** — otherwise the synced files land first and Ansible's `state: link` refuses to convert a non-empty directory:

```
the directory .../bootstrap/cache is not empty, refusing to convert it
```

`.env` and `storage` "just work" precisely *because* they're already in the exclude list; a fourth shared path that someone forgets to exclude breaks. The build artifact's prune list and the deploy's `rsync_excludes` must agree — keep them in sync (the build job pruning a path it claims the deploy excludes is a comment that drifts silently). The trigger here was Composer's `package:discover` output (`packages.php`/`services.php`) landing in `bootstrap/cache` during the build.

### Relative symlink depth — count the levels

A relative symlink's `../` depth must match the *nesting of the link itself*, not just the release root. `.env` and `storage` live at the release root, so `../../shared/...` reaches `deploy_path/shared`. But a nested target like `bootstrap/cache` is one level deeper, so the *same* `../../shared` resolves to `deploy_path/releases/shared` — which doesn't exist (a dangling link). The framework follows it and reports the directory "must be present and writable."

Add a level for each directory of nesting: `bootstrap/cache → ../../../shared/bootstrap/cache`. Verify on the host that the link resolves (`readlink -f`, or `ls -l` the target) rather than trusting the relative arithmetic.

### Laravel: `storage:link --relative` needs `symfony/filesystem`

`php artisan storage:link --relative` fails on prod with *"To enable support for relative links, please install the symfony/filesystem package"* when that package isn't in `composer.lock`. It often works **locally** only because dev tooling happened to pull `symfony/filesystem` in transitively — prod with `--no-dev` doesn't have it. Drop `--relative` and use the default absolute link. Safe in the atomic-release model because `storage:link` re-runs every release, so `public/storage` always points at the dir that becomes `current` and resolves through `storage → shared/storage` identically.

## Host environment mismatches

### bare `php` on a shared host is the *wrong* PHP

On a shared host with multiple PHP versions installed, bare `php` resolves to the host's *default* CLI (e.g. php8.0), not the version your app needs. Getting the Nginx `fastcgi_pass` socket right (`php8.3-fpm.sock`) fixes the **web** path but leaves the **CLI** path on the wrong version — so `artisan` commands fail with *"Your Composer dependencies require PHP >= 8.2.0. You are running 8.0.19."*

Route every CLI invocation through a single explicit-version variable (`php_cli`, default `php8.3`, overridable) — `storage:link`, the config/route/view cache loop, `migrate --force`, any `php -S` smoke check. Mirror whatever single-knob pattern the FPM socket already uses so the CLI version and the FPM version are set in one place.

### managed DB: no global privileges → no `--single-transaction`

A managed-database user typically has `ALL PRIVILEGES` on the *app* database but only `USAGE` globally — **no `RELOAD`**. `mysqldump --single-transaction` issues `FLUSH TABLES`, which needs `RELOAD`/`FLUSH_TABLES`, so the pre-migrate backup dies with *"Access denied; you need RELOAD or FLUSH_TABLES (1227)."*

For a pre-migrate safety dump of small framework tables, you don't need a consistent snapshot lock:

```bash
MYSQL_PWD="$db_pass" mysqldump \
    --skip-lock-tables \
    --set-gtid-purged=OFF \
    -h "$db_host" -u "$db_user" "$db_name" <tables...> > backup.sql
```

- `--skip-lock-tables` replaces `--single-transaction` — no `RELOAD`/`LOCK` privilege needed.
- `--set-gtid-purged=OFF` keeps the dump restorable on a managed, GTID-enabled server.
- `MYSQL_PWD` passes the password out of `argv` (the `-p<pass>` form is visible in `ps`).
- **Skip the dump entirely when the target tables don't exist yet** — on the first deploy the migration *creates* them, and `mysqldump` errors on a missing table. Detect-then-dump, don't dump-and-hope.

(Watch shell-module arg-splitting: an apostrophe in a task `name:`/comment can trip Ansible's argument splitter — rephrase rather than escaping.)

## The Ansible controller / target contract

### Pin `ansible-core` to the target's Python floor

An unpinned `pip install ansible-core` on the CI runner grabs the latest release, and recent ansible-core drops managed-node support for old Python. Against an Ubuntu 20.04 target (`/usr/bin/python3` = 3.8) the deploy reaches *Gathering Facts* then fails: *"Ansible requires Python 3.9 or newer on the target. Current version: 3.8.10."* It worked from a local Mac only because that controller happened to be an older ansible-core with a lower target floor.

Pin the CI job to the **validated** controller environment — explicit `actions/setup-python` version + `ansible-core ~=2.15.0` (controller py3.9–3.11, managed-node py3.6+) — so CI reproduces the working local controller exactly. The durable fix is upgrading the target off the EOL OS so the controller can float forward; the pin is what unblocks the deploy now.

### Use core-native callbacks, not `community.general`

Collections churn faster than ansible-core. `community.general` v12.0.0 *removed* the `yaml` stdout callback, so a CI step that installs the latest collection and sets `stdout_callback = community.general.yaml` errors with *"... has been removed."* The core-native replacement (since core 2.13) needs no collection at all:

```ini
# ansible.cfg
[defaults]
stdout_callback = default
callback_result_format = yaml
```

Drop the `community.general` install if nothing else needs it (`ansible.posix` covers `synchronize` + `authorized_key`). Prefer core-native config over a collection dependency for anything core can do — one fewer moving part to break on a version bump.

### Connection-user precedence: set `remote_user` per-play, not in inventory

Host-level `ansible_user` in the inventory has the **highest** connection-user precedence — higher than `-u` on the command line. So `ansible_user: github` pinned at host level **silently overrides** an operator's `ansible-playbook -u root provision.yml`, and the cold-host provision connects as the wrong (possibly non-existent, non-sudo) user. The symptom is subtle: rendered artifacts (e.g. a `sudoers.d` drop-in) end up scoped to the wrong account because the play ran under the wrong user context.

Decouple the connection user *per play* instead of pinning it globally:

- Inventory: keep `ansible_host`, **drop** host-level `ansible_user`.
- Deploy play: `remote_user: "{{ deploy_user }}"` (CI connects as the unprivileged deploy account).
- Provision play: `remote_user: "{{ provision_user | default('root') }}"` (operator connects as root; overridable via `-e provision_user=...`).

This keeps `-u` working for the provision run while the deploy run still defaults to the right account — the two plays have genuinely different connection needs and inventory-level pinning conflates them.

## Checklist for a first bare-metal deploy

Before the first end-to-end run against a real host, walk these — each is a thing local/CI cannot tell you:

1. Does `current`'s swap survive `current` being a real directory? (`mv -Tf`, not `ln -sfn`.)
2. Are **all** shared-symlink targets in the rsync exclude list *and* the build prune list?
3. Does each relative symlink's `../` depth match the link's own nesting?
4. Does every CLI `php`/`artisan` call go through an explicit-version variable?
5. Does the DB user actually have the privileges your backup flags assume? (`--skip-lock-tables` if no `RELOAD`.)
6. Does the backup skip cleanly when its target tables don't exist yet (first deploy)?
7. Is `ansible-core` pinned to a version that still supports the target's Python?
8. Are callbacks core-native, or do they depend on a collection that might drop them?
9. Is the connection user set per-play, so `-u` isn't silently overridden by inventory?
