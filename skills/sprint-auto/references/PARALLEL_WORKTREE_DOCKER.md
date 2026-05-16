# Parallel worktree + docker isolation

Discipline for parallel work streams in git worktrees with independent docker compose stacks.

### The Hard Rules

1. **One worktree per parallel work stream.** A git worktree gives each stream its own filesystem + branch; pair it with its own docker-compose project so stacks don't fight over host ports, container names, or DB volumes.
2. **Start Claude (or any AI agent) from the worktree directory itself**, not from the primary checkout reaching in via absolute paths. Working directory scope dictates permission prompts; starting outside forces a prompt on every cross-tree operation. This is the single biggest productivity lever in this workflow.
3. **Never copy `.env` from the primary checkout to a worktree.** Populate with test-safe sentinel values from `.env.template`. Real credentials must only exist in the primary checkout.
4. **Two stacks on the same daemon need distinct: host ports, subnet, per-service `ipv4_address` (if the parent compose pins them), and project name** (auto-derived from directory name, so a unique worktree dir name is usually enough).
5. **`docker-compose v2` merges list fields (`ports:`) additively.** Use `!override` to replace — otherwise both original and override bindings try to bind.
6. **`docker compose restart` does not pick up a new image** — use `docker compose up -d --force-recreate <svc>` (or the project's `make recreate-web` equivalent) after a rebuild.
7. **`docker build` aggressively caches pip layers.** If the `requirements*.txt` content hash matches a prior build, the existing pip layer is reused — the package you just added may not actually install. Force with `--no-cache` when adding deps, especially for plugins that pytest-style autoload (pytest-xdist, pytest-sugar) where silent absence surfaces as "why doesn't the flag work?".

### When This Applies

Any time two (or more) work streams must proceed concurrently without blocking each other on branch switches, container rebuilds, or DB migrations. Typical triggers:

- One PR is open and awaiting bugbot / human review; a second track depends on the first but can start in parallel.
- A long-running experiment (benchmark, parallel-test harness, migration replay) needs isolated state so it can't corrupt the primary dev loop.
- Two agents need to collaborate on the same sprint without stepping on each other's docker state.

### Worktree Bootstrap Recipe

From the primary checkout:

```bash
# 1. Create the worktree off the base branch (use the feature branch that
#    the new work builds on, not main, if there are unmerged prerequisite
#    commits the new work needs).
git worktree add ../<project>-<track> -b chore/<branch-name> <base-branch>

# 2. Inside the worktree, bootstrap the env (sentinel values only).
cd ../<project>-<track>
cp .env.template .env
# Replace secrets with safe sentinels:
#   - SECRET_KEY=test-$(openssl rand -hex 16)
#   - *_API_KEY / *_TOKEN / *_SECRET → test-not-a-real-key
#   - HMAC/fernet salts → test-$(openssl rand -hex 16)
# Optional: scope DB_NAME / CACHE_URL / etc. to a distinct namespace if the
# stack shares anything with the primary (rarely needed — separate compose
# project gives its own DB volume).

# 3. Write a docker-compose.override.yml that remaps what collides.
#    See "Override patterns" below.

# 4. Bring up the stack.
docker compose up -d

# 5. Run project-specific post-up bootstrap.
#    Worktree state starts empty — anything the primary stack initialised
#    out-of-band (MinIO buckets, ES indices, seed data, MinIO anonymous
#    policies) must be re-run against this worktree's containers.
#    Typical: ./tools/setup_minio.sh (or the equivalent project helper).
#    For S3-compatible bucket init specifically, you can also do it inside
#    the minio container when the host-side mc client is not available:
#      docker compose exec -T minio mc alias set local http://localhost:9000 "$USER" "$PASS"
#      docker compose exec -T minio mc mb local/<bucket> --ignore-existing
#      docker compose exec -T minio mc anonymous set public local/<bucket>
```

**Do not commit `docker-compose.override.yml`** unless it's a project-wide convention — it's worktree-local state. Leave it untracked; git will politely remind you it exists.

### Override Patterns

#### Host port remap (`+10000` offset is a safe starting point)

```yaml
services:
  web:
    ports: !override
      - "127.0.0.1:18000:8000"
      - "127.0.0.1:18001:8001"
  db:
    ports: !override
      - "127.0.0.1:15432:5432"
  elasticsearch:
    ports: !override
      - "127.0.0.1:19200:9200"
      - "127.0.0.1:19300:9300"
```

The `!override` tag is required — without it, compose v2 merges both port lists into a single `ports:` list and both tries to bind, producing `port is already allocated` when the original 5432 / 8000 is already held by the primary stack.

#### Subnet + static IP remap (only if the parent compose pins them)

```yaml
services:
  web:
    networks:
      project_network:
        ipv4_address: 172.30.0.10
  db:
    networks:
      project_network:
        ipv4_address: 172.30.0.60
  # ... one entry per service that had a fixed ipv4_address in the parent

networks:
  project_network:
    ipam:
      config:
        - subnet: 172.30.0.0/16
```

If the parent uses `172.20.0.0/16`, use a non-overlapping block like `172.30.0.0/16`. Docker rejects subnet overlap at network-create time with `invalid pool request: Pool overlaps with other one on this address space`.

### Common Gotchas

| Symptom | Root cause | Fix |
|---|---|---|
| `Bind for 127.0.0.1:5432 failed: port is already allocated` | Ports list was merged additively, both bindings tried | Use `ports: !override` in the override file |
| `invalid pool request: Pool overlaps with other one on this address space` | Parent's subnet collides with override | Pick non-overlapping subnet (e.g., 172.30.0.0/16 vs parent's 172.20.0.0/16) |
| `no configured subnet contains IP address 172.20.0.x` | Override changed subnet but left static `ipv4_address` entries unchanged | Re-map each service's `ipv4_address` to the new subnet range |
| `WARNING: Package(s) not found: pytest-xdist` after `make build` | Docker reused cached pip-install layer (requirements hash matched) | `docker compose build --no-cache <svc>` |
| Fresh image built but container still old behaviour | `docker compose restart` was used — doesn't recreate | `docker compose up -d --force-recreate <svc>` |
| `botocore.errorfactory.NoSuchBucket` flood when running tests in a fresh worktree | MinIO volume is empty; the primary checkout created the bucket once via `tools/setup_minio.sh` and never re-runs it. The worktree's MinIO container has never seen that script. | Run the project's MinIO setup script (or `mc mb` inside the container) as a post-up step — add to the Bootstrap Recipe. Tests that PutObject silently fail and cascade into hundreds of unrelated test failures (views that render image thumbnails, permission tests that seed attachments, etc.). Symptom is large failure count clustered in `test_views` / `test_api` / `test_permissions` in apps that use file storage. |
| `botocore.exceptions.ClientError: InvalidAccessKeyId` after the bucket is set up — different from NoSuchBucket | The `.env.template` ships **two different defaults** for the same logical credential: `MINIO_ROOT_USER=your-minio-root-user` and `AWS_ACCESS_KEY_ID=your-minio-access-key`. The MinIO container init reads `MINIO_ROOT_USER` to provision the admin user; Django's S3 client reads `AWS_ACCESS_KEY_ID`. If a sentinel-rewrite regex in the Bootstrap Recipe matches `*_API_KEY` / `*_TOKEN` / `*_SECRET` but **not** the literal string `_ACCESS_KEY_ID` (because it doesn't end in `_KEY`), AWS_ACCESS_KEY_ID stays at its template default while MINIO_ROOT_USER also stays at its (different) template default — the two names point at non-existent users on each other's side. | Bootstrap recipe: after sentinel-rewriting, **explicitly set `AWS_ACCESS_KEY_ID = $MINIO_ROOT_USER`** (or align both at sed-time). Then `docker compose up -d --force-recreate web celery` — `docker compose restart` is **insufficient** here because env vars are baked into the container at create time (same gotcha as the "fresh image" row above, applied to env). Verify with `docker compose exec web sh -c 'echo $AWS_ACCESS_KEY_ID'` — it must match `MINIO_ROOT_USER` exactly. Symptom appears identical to NoSuchBucket at first glance; distinguish by running `mc admin info local` from inside the minio container (works → bucket exists; cred mismatch is on the Django side). |
| Agent keeps prompting for permission on every cross-tree operation | Agent was started in the primary tree, reaching in via absolute paths | Start a fresh agent session from inside the worktree directory |
| `docker compose down` removed the **wrong** stack — primary instead of the worktree's | A chained bash command of the shape `cd "$WORKTREE_VAR" && docker compose down` fell through to the current directory because `$WORKTREE_VAR` was unset in that bash invocation (env vars don't carry between Claude Code Bash tool calls — only the working directory does). With cwd defaulting to the primary tree, `docker compose down` targeted the **primary** project. Witnessed during sprint-auto S11.13 teardown: `cd "$SPRINT_AUTO_INTEGRATION_WORKTREE" && docker compose down` was issued without re-sourcing the state file in that chain; the `cd` failed silently (bash's default for `cd` to empty string is a no-op, NOT a hard error), and the subsequent `down` removed the primary project's containers. Primary stack went down for ~30s before detection. | **Always `source` the state file (or re-export the var) BEFORE any chained `cd` to a worktree path.** Three concrete defences, each independently sufficient: (1) `source /tmp/<batch>-state.sh && cd "$WORKTREE" && docker compose down` — the `source` re-exports for the current bash invocation; (2) use the absolute path literally instead of a var when one chain is enough: `cd /home/kestas/projects/<project>-auto-integration-... && docker compose down`; (3) gate the `cd` with `: "${WORKTREE:?WORKTREE not set}"` so the chain fails fast instead of falling through. For sprint-auto specifically, write the state-file `source` line as the FIRST command in every chain that does any docker compose operation against a non-primary stack — no exceptions, even for "obvious" calls. The ~30s outage is recoverable; an outage during S(-1) bootstrap on a heavily-loaded daemon, or any down with `-v` (volume drop), would not be. |
| `git worktree remove` fails with `Permission denied` on teardown, but the files look gitignored | Container ran as root against the bind-mounted worktree dir, wrote `__pycache__/*.pyc` (or `.po` / `.mo` / pytest cache) owned by UID 0. Git treats them as gitignored so no warning; host user can't unlink them. | Chown the tree back before teardown. Use `docker run --rm -v <absolute-worktree-path>:/work alpine chown -R "$(id -u):$(id -g)" /work` when host sudo isn't available; the daemon's root UID maps through the bind mount. See the "Docker as privileged-fileops escape hatch" note below for security considerations before leaning on this. |

**Out of scope for this reference:** container DNS / NSS resolution anomalies (`getaddrinfo` returning loopback for public domains, `/etc/hosts` and `myhostname` NSS shadowing public DNS, cert-issuance silent drops on fresh VPS bootstrap) — those live in [`skills/deployment/references/CONTAINER_DNS_NSS.md`](../../deployment/references/CONTAINER_DNS_NSS.md). That reference loads on demand when the deployment skill activates; this one loads on parallel-worktree work.

### Docker as privileged-fileops escape hatch (use deliberately, don't build tools around it)

The docker-chown trick in the gotchas table above is a specific application of a more general pattern: when host sudo isn't available but the docker daemon is, any root-level filesystem operation can be done via a disposable container with the target path bind-mounted. Container root is host root for that mount.

Applications in the workflow:
- `chown -R <uid>:<gid>` to fix container-as-root residue (the motivating case)
- `rm -rf` a root-owned tree when `git worktree remove` can't reach it
- `tar -xf` into a restricted target dir (install-bundle scenarios)

Canonical shape:

```bash
docker run --rm \
    -v <absolute-host-path>:/work \
    alpine \
    <command> /work[/subpath...]
```

The image choice isn't meaningful — any minimal Linux image whose default user is root works (`alpine`, `busybox`, `debian:slim`). Alpine is the default here only because it's small and ubiquitous.

**Security considerations before using this pattern** — these are why it stays a documented technique, not a shipped helper script:

- Docker group membership is effectively **root-equivalent on the host filesystem**. A wrapper that takes arbitrary commands (`./docker-as-root.sh chown ...`) is one `docker-as-root.sh --image ubuntu -- rm -rf /etc` away from a footgun masquerading as a convenience tool. Keep the pattern as a recipe; type the flags each time.
- **Hardened setups deliberately prevent this**: rootless docker, user-namespace remapping (`userns-remap`), and SELinux/AppArmor labels on bind mounts all refuse the trick by design. A team that relied on a helper script would be blocked the day they adopted any of those — better to have the recipe in docs than a tool that silently stops working.
- **Audit trail is weaker than sudo**: sudo logs to syslog; `docker run` logs to the daemon's journal, which is both noisier and easier to filter out. In environments with compliance requirements, prefer sudo where available and treat this as a last resort.

When in doubt, prefer host sudo. The docker-chown pattern is a fresh-VPS-without-sudo escape hatch, not a blessed workflow — which is also why it lives in a Common Gotchas row, not a top-level bootstrap step.

### Dev-tool install + config placement in a worktree stack

Two recurring paper-cuts when adding developer-only tooling (linters, static analyzers, security scanners — anything not in the production image) that needs to run inside the worktree's container.

**Problem 1 — Installing dev-only pip deps on demand.** The production image's `requirements-web.txt` is baked in; `requirements-dev.txt` on the host is **not** bind-mounted into the standard compose services. A naïve Makefile target that `pip install -r requirements-dev.txt` inside `docker compose exec` fails with `No such file or directory`. The drift-prone "fix" is to inline the version pins in the Makefile — now the same versions live in two places and will diverge on the next bump.

Canonical shape (single source of truth, zero bind-mount gymnastics):

```make
security-scan:
	@docker compose exec -T web pip install --quiet -r /dev/stdin < requirements-dev.txt
	@docker compose exec -T web bandit -r . -c /tools/.bandit.yml ...
```

The `< requirements-dev.txt` reads the file from the host, the pipe becomes the container's stdin, and `pip install -r /dev/stdin` reads the pins from there. `requirements-dev.txt` stays the authoritative pin list for both host venvs and the docker-exec path.

**Problem 2 — Where to put the tool's config file.** Bandit and most Python linters look for config at the project root (`.bandit.yml`, `pyproject.toml`, `.flake8`, `mypy.ini`). But inside a worktree docker stack, the container's `/app` is typically `web/` (the Python source), not the project root. Project-root files aren't reachable from the container unless they're explicitly bind-mounted. `tools/` **is** commonly bind-mounted (`/tools/`), so config files that need to be read *by a container-resident tool* belong there, not at the project root:

```text
.bandit.yml          ← host convention, but unreachable from the container
tools/.bandit.yml    ← reachable as /tools/.bandit.yml, container can read it
```

Passing `-c /tools/.bandit.yml` to the tool makes the dependency explicit and survives worktree-project renames. The convention also keeps the project root clean of per-tool dotfiles that aren't actually used by host-side workflows.

**When this applies**: Any dev-only tool (bandit, pip-audit, ruff, mypy, pytest plugins, pre-commit hooks that shell out to Python scripts) that (a) isn't in the production image and (b) needs to read source code or a config file from inside a running worktree container. Baseline rules: pin once in `requirements-dev.txt`, install via stdin pipe from that file, park configs under `tools/` if a container-resident tool will read them.

### Coordination Across Parallel Streams

The only coordination seams between parallel worktrees are:

1. **Git**: when the earlier stream merges, the later stream rebases onto fresh main. Conflict likelihood correlates with file overlap, not with the existence of the parallel stream. Plan branches so overlapping files are minimised.
2. **Host resources**: CPU, disk I/O, memory. Parallel builds and parallel test runs contend. Not usually a problem for human pace; for agent-driven parallel builds, add a mutex by convention (e.g., "builds happen in whichever session started it first").
3. **Shared external services**: if both stacks talk to a real external system (SaaS API, shared DB), rate-limit or namespace by worktree name. For local-only sentinel stacks (test-not-a-real-key everywhere), not an issue.

Everything else — branch state, docker state, database state, redis state, filesystem — is independently isolated by the worktree + per-project compose pattern. That's what makes the pattern a performance lever: zero wait for branch-switch, zero collision on container state, zero context rot across sessions.

### Single-stack staging server: smoke-testing un-merged PRs in-place

Some projects designate the staging machine as a *single-stack* environment: the primary checkout is on `main` by default and serves real-ish traffic, but the operator (or AI agent) sometimes wants to test an un-merged PR against the same DB and the same external services. No second stack involved. This is **not** the parallel-worktree pattern above — it's a single-stack swap-and-revert workflow against shared state.

The hybrid bind-mount-vs-COPY layer split matters here. Many projects bind-mount the application source (so code changes propagate to the running container without a rebuild) but `COPY` other services' source at image-build time (microservices, sidecars, ML workers — wherever a slimmer image is desired). When a PR touches both layers, the smoke-test workflow has to update them differently:

- **Bind-mounted services** (typically the main Django/Rails/Node app): just `docker compose restart <svc>` after `git checkout` — the bind-mount carries the new code automatically.
- **COPY-baked services** (typically the smaller helper microservices): the running container's source was baked at last build time. Either rebuild the image (slow but clean), or `docker compose cp` the new file into the running container + restart (fast but leaves cp'd state that needs to be flushed on revert).

The full happy-path workflow:

```bash
# 1. Save current state assumptions: primary should be on main, clean tree.
cd ~/projects/<project>
git status --short                      # expect clean
git log --oneline -1                     # expect main HEAD

# 2. Detach to the un-merged PR's HEAD. --detach avoids claiming the branch
#    (so the PR's own worktree, if any, isn't affected; also avoids the
#    "already used by worktree at /path" error if a per-IDEA worktree exists).
git fetch origin
git checkout --detach origin/<feature-branch>
git log --oneline -1                     # confirm new HEAD

# 3. For each COPY-baked service the PR touches: cp the new source +
#    restart. This is fast (~5s) and avoids a full rebuild for a smoke test.
docker compose cp <service>/main.py <service>:/app/main.py
docker compose restart <service>

# 4. Apply any new migrations. The web container's bind-mounted /app
#    immediately sees the new migration files; `migrate_schemas` is a fresh
#    Python process so it picks up new models without needing a restart yet.
docker compose exec -T web python manage.py migrate_schemas

# 5. Restart bind-mounted services so the long-running daphne/gunicorn/
#    celery process loads the new code.
docker compose restart web celery

# 6. Run the smoke test (project-specific).
docker compose exec -T web python manage.py <smoke-command>
```

**Reverting cleanly back to main**:

```bash
# 1. Roll back any migrations applied during the test (if the PR added new
#    migrations and you want to leave the DB matching main's state). For
#    additive-only migrations, this is `migrate_schemas <app> <prev-num>`.
#    SKIP this step if the user explicitly said "don't roll back" — see
#    the migration-tracking gotcha below.
docker compose exec -T web python manage.py migrate_schemas <app> <prev-migration-number>

# 2. git checkout main.
git checkout main

# 3. Force-recreate COPY-baked services to discard the cp'd state. A plain
#    restart would NOT discard it — the cp'd file lives in the container's
#    filesystem layer and survives restart. Force-recreate spins up a new
#    container from the image, which has the original (main's) source.
docker compose up -d --force-recreate <service>

# 4. Restart bind-mounted services to drop any in-memory state that came
#    from the PR's code (cached imports, in-flight worker tasks, etc.).
docker compose restart web celery
```

**Migration tracking persists across code-tree changes — and `showmigrations` lies about it.** If the smoke-test session applies a migration (say `0038_*`) but then reverts to main without rolling back, the DB still has migration `0038` tracked in `django_migrations` AND the columns it added. But `showmigrations` only iterates files in the current code's `migrations/` directory — main doesn't have `0038_*.py`, so `showmigrations` won't show it at all (not as applied, not as unapplied — invisible). The DB state and Django's view of migrations diverge. The orthogonal additive columns sit unused on the tables (Django's ORM doesn't know about them, so writes don't include them) — benign while you wait for the PR to land, but worth knowing.

**Verifying actual DB-tracked migrations** when `showmigrations` is hiding things:

```python
# python manage.py shell
from django.db import connection
with connection.cursor() as c:
    c.execute("SELECT name, applied FROM <tenant_schema>.django_migrations "
              "WHERE app=%s ORDER BY id DESC LIMIT 5;", ["<app_name>"])
    for row in c.fetchall():
        print(row)
```

The `<tenant_schema>` is `public` for non-multi-tenant projects, or the per-tenant schema name for django-tenants setups. Multi-tenant projects: query BOTH `public.django_migrations` (shared apps) and `<tenant_schema>.django_migrations` (tenant apps) — they're separate tables with separate state.

**The state-mutating chain trap**: a single chained tool call like `migrate_schemas <prev> && git checkout main && docker compose up -d --force-recreate <svc> && docker compose restart web celery` can partially execute on user rejection (the harness blocks LATER links but EARLIER ones may have already run). Split state-mutating ops into separate tool calls so rejection has a clean intercept. See `~/.claude/projects/<project>/memory/feedback_chained_command_destructive_ops.md` for the full pattern.

### Referenced from

- Global `~/.claude/CLAUDE.md` — the `.env` worktree exception clause.
- Memory: `feedback_worktree_cwd.md` — "start Claude from worktree dir" enforcement reason.

### When Not to Use This

- Single-track work. The pattern adds ceremony; worth it only when two streams genuinely need to run concurrently.
- Small repos / no container stack. If the project is just a Python venv with no Docker, a simple second worktree with its own venv is enough.
- Repos whose compose project already sets `COMPOSE_PROJECT_NAME` explicitly and shares volumes by name — those override the directory-name defaults and the stacks may still collide.

---

**Last Updated**: 2026-04-29
