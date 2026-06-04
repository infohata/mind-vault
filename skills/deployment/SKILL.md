---
name: deployment
description: Deploy Docker Compose web applications across any project — branch strategy, change-aware scripts, database backup + rollback safety, screen-session remote execution, Let's Encrypt SSL, health checks, and CI/CD wiring.
license: Apache-2.0
metadata:
  author: mind-vault
  version: '2.0'
---

# deployment

Production deployment pattern for containerised web applications using Docker Compose. Prioritises **safety** (automatic backups before destructive steps, rollback-ready state, mandatory screen sessions for remote runs) over raw speed. **This is not a zero-downtime pattern** — it's a stop/rebuild/start cycle with health verification. Brief outages (5–30 s) are expected on updates.

**This skill covers:**

- Branch strategy and release management
- Change-aware deploy scripts (migrations, dependencies, static assets)
- Database safety (pre-change backups, rollback procedures)
- Remote SSH deployment with mandatory screen sessions
- Let's Encrypt SSL via certbot + nginx
- Health checks and deployment verification
- Environment management and `.env` handling
- Makefile targets for common operations

## When to use

**TRIGGER when:** preparing or executing a production deploy for a Docker Compose application; setting up the initial `deploy.sh` + `backup_db.sh` + `verify_deployment.sh` toolchain; wiring a CI/CD pipeline that invokes the deploy scripts; handling rollback after a failed deploy.

**SKIP for:** local dev-container startup (`docker compose up`), single-container toy apps, Kubernetes-based deploys (different contract — use Helm/ArgoCD), PaaS targets (Heroku/Fly/Railway — they own their own deploy verb and these scripts will conflict).

## Pattern

### Branch strategy

Separate production from development:

- Use a `deployment` (or `production`) branch for releases.
- Merge stable commits from `main` into `deployment` explicitly — no auto-fast-forward.
- Branch protection on `deployment`: require review, disallow force-push.
- A clear commit boundary on the release branch = a clean rollback target.

```bash
git checkout deployment
git merge <stable-sha>
git push origin deployment
```

### Service architecture

Typical Docker Compose stack:

| Service          | Role                                                |
| ---------------- | --------------------------------------------------- |
| `web`            | Application container (Django, Rails, Node, …)      |
| `nginx`          | Reverse proxy, SSL termination, static file serving |
| `db`             | PostgreSQL / MySQL                                  |
| `cache`          | Redis / Memcached                                   |
| `worker`         | Background jobs (Celery / Sidekiq / BullMQ)         |
| `certbot`        | Let's Encrypt renewals                              |
| `storage` (opt.) | MinIO / S3-compatible object store                  |

Principles:

- Services communicate via internal Docker network only (no public ports except nginx).
- Persistent data on named volumes.
- All configuration via environment variables (no baked-in secrets).
- Each service declares healthchecks and dependencies.

### Deploy scripts

Canonical toolchain lives in `scripts/` (or `tools/`) at the repo root:

- `deploy.sh` — auto-detecting wrapper (first-time vs update)
- `deploy_first_time.sh` — initial deploy + data seed
- `deploy_update.sh` — change-aware update
- `backup_db.sh` — database snapshot
- `restore_db.sh` — counterpart restore
- `verify_deployment.sh` — post-deploy health checks

Reference implementations live in this skill's [`scripts/`](scripts/) directory — copy them into your project and customise.

**Auto-detecting wrapper:**

```bash
#!/bin/bash
# scripts/deploy.sh
SERVICES_RUNNING=$(docker compose ps | grep -qE "Up|running" && echo true || echo false)

if [ "$SERVICES_RUNNING" = "true" ]; then
    exec ./scripts/deploy_update.sh "$@"
else
    exec ./scripts/deploy_first_time.sh "$@"
fi
```

**Project-root detection** (survives symlinks and arbitrary cwd):

```bash
if [ -n "$PROJECT_ROOT" ]; then
    cd "$PROJECT_ROOT"
elif git rev-parse --git-dir > /dev/null 2>&1; then
    cd "$(git rev-parse --show-toplevel)"
else
    echo "Warning: using current directory as project root"
fi
```

### Non-interactive mode

Deploy scripts must support non-interactive invocation for CI and screen sessions:

```bash
DEPLOY_NON_INTERACTIVE=1 ./tools/deploy.sh
# or
./tools/deploy.sh --yes
```

**Why:** screen allocates a TTY, so `[ -t 0 ]` returns true inside the session. A prompt in the deploy script then blocks forever with no stdin attached. Explicit non-interactive mode forces safe defaults regardless of TTY presence. CI runners have the same problem.

### Change detection

The update script decides what work is needed by diffing current and previous deploy:

```bash
PREVIOUS=$(git rev-parse HEAD@{1} 2>/dev/null || echo "")

if [ -n "$PREVIOUS" ]; then
    HAS_MIGRATIONS=$(git diff "$PREVIOUS" HEAD --name-only | grep -q "migrations/" && echo true || echo false)
    HAS_DEPENDENCIES=$(git diff "$PREVIOUS" HEAD --name-only | grep -qE "requirements.*\.txt|Dockerfile|package(-lock)?\.json|Gemfile(\.lock)?" && echo true || echo false)
    HAS_STATIC=$(git diff "$PREVIOUS" HEAD --name-only | grep -qE "\.(css|js|scss|png|jpg|svg)" && echo true || echo false)
fi

# Dependency rebuild may touch static assets the grep missed — force a static rebuild.
[ "$HAS_DEPENDENCIES" = "true" ] && HAS_STATIC=true
```

#### Two layers: file diff + config fingerprint for expensive ops

File-diff change detection is **necessary but not sufficient** when an expensive post-deploy operation (full corpus reindex, CDN purge, search-engine wipe-and-rebuild, vector-index rebuild, ML-model warm-up) depends on a *subset* of the files that flip the diff. The first layer answers "did anything in this area change?"; you need a second layer to answer "did the thing the expensive op actually depends on change?"

Pattern:

1. Identify the inputs the expensive op truly depends on — usually env vars and a small set of config knobs, **not** the source files of the subsystem implementing it.
2. Compute a deterministic fingerprint over those inputs at deploy time (sourced from `.env` already in scope).
3. Persist the fingerprint to a marker file (`.deploy_<topic>_shape`) **after** the op succeeds.
4. On next deploy, compare current vs. stored fingerprint. If unchanged → skip the expensive op. If changed → run it. **If marker is missing → run it** (treat first-time / lost-marker as "run", since silently skipping is much worse than running unnecessarily).
5. Provide a `FORCE_<TOPIC>=1` env override for the operator-driven cases the gate can't predict (env-only fixes, manual recovery).

```bash
SHAPE_FILE="$PROJECT_ROOT/.deploy_embedding_shape"
compute_embedding_shape() {
    # Fingerprint the inputs the expensive op depends on — provider, model,
    # dimension, API base, index version. Empty values included verbatim so
    # unset → set transitions register as a change.
    printf '%s|%s|%s|%s|%s|%s\n' \
        "${EMBEDDING_PROVIDER:-}" "${EMBEDDING_DIMENSION:-}" \
        "${EMBEDDING_MODEL_NAME:-}" "${GEMINI_EMBEDDING_MODEL:-}" \
        "${EMBEDDING_API_BASE_URL:-}" "${INDEX_VERSION:-}"
}

CURRENT=$(compute_embedding_shape)
PREVIOUS=$([ -f "$SHAPE_FILE" ] && cat "$SHAPE_FILE" || echo "")

if [ "$FORCE_REINDEX" = "1" ] || [ -z "$PREVIOUS" ] || [ "$CURRENT" != "$PREVIOUS" ]; then
    # Gate the marker write on the op's exit status so a failed reindex
    # leaves the PREVIOUS marker intact — next deploy retries. Without
    # explicit gating (or `set -e`), `echo > $SHAPE_FILE` on the next
    # line would run unconditionally and silently mask the failure.
    if run_expensive_reindex; then
        echo "$CURRENT" > "$SHAPE_FILE"
    else
        echo "❌ reindex failed — marker NOT written; next deploy will retry." >&2
        exit 1
    fi
else
    echo "🔍 Shape unchanged — skipping reindex."
fi
```

**Anti-pattern this teaches against**: gating an expensive post-deploy op on raw dependency-file diff (`grep -qE "<subsystem>/" diff`). The *subsystem* changed (new endpoint, refactor, test added) but the *thing the op depends on* didn't. Running anyway burns whatever the op costs — for a vector-index rebuild against a pay-per-token embedding API, that can be a rate-limit cliff and a real bill. The gate moves the decision from "did any file in the subsystem change?" to "did the op's actual contract change?", which is a much smaller surface.

**Failure-mode discipline**: write the marker **only after** the op succeeds. The `if run_expensive_reindex; then ... fi` shape above does this explicitly — without it (`run_expensive_reindex; echo "$CURRENT" > "$SHAPE_FILE"`), a failed reindex would still write the marker, and the next deploy would skip the retry, silently masking the failure. If the op is non-atomic (multi-stage), wrap only the final stage in the `if` so partial-success doesn't poison the marker.

### Backup strategy

Database backup is **mandatory** before any schema change:

```bash
if [ "$HAS_MIGRATIONS" = "true" ]; then
    ./scripts/backup_db.sh   # pre-migration snapshot
fi

docker compose exec -T web python manage.py migrate

./scripts/backup_db.sh       # post-migration snapshot (clean rollback point)
```

**Backup naming convention:**

```text
data/db_backup_YYYYMMDD_HHMMSS_<commit-sha>.sql.tar.gz
```

The commit sha in the filename lets you pair any backup with the exact code that produced the schema — critical for restore-plus-revert.

### Remote deployment — mandatory screen

Remote deploys **must** run inside a screen session so they survive SSH disconnects, network blips, and terminal closures.

**Canonical form:**

```bash
ssh user@production.com << 'EOF'
cd /opt/myapp
SESSION="myapp-deploy-$(date -u +%Y%m%d-%H%M%S)"
LOG="deploy-$(date -u +%Y%m%d-%H%M%S).log"
screen -dmS "$SESSION" bash -c \
  "DEPLOY_NON_INTERACTIVE=1 ./tools/deploy.sh 2>&1 | tee $LOG"
echo "Session: $SESSION | Log: $LOG"
sleep 3 && tail -n 50 "$LOG"
EOF
```

Full recipe book — naming conventions, monitoring, attaching/detaching, cleanup, long-rebuild handling, troubleshooting — is in [references/SCREEN_SESSIONS.md](references/SCREEN_SESSIONS.md).

**Host-key verification:** never use `-o StrictHostKeyChecking=no` in automated paths. A MITM can then silently substitute for the deploy target and steal the deploy key. Populate `known_hosts` in advance (`ssh-keyscan -H host >> ~/.ssh/known_hosts`), or pin the expected fingerprint as a secret and verify it before connecting.

### Deployment session tracking

Record each production deploy in the repo for later forensics:

- **Path:** `docs/deployment/sessions/{host}_yyyymmdd-hhmm.md` (e.g. `myapp_com_20260417-1415.md`)
- **One file per deploy run, covering the whole lifecycle** — pre-rollout plan, execution record, post-deploy verification, rollback target. Create the file with `status: PENDING` before the run and flip to ✅ / ❌ at the end. **Do not fork the plan into a separate `ROLLOUT_PLAN_*.md`** — the session file is the single artefact and the PENDING status handles the pre-rollout phase. A plan-doc-plus-session-file split produces the two-narrative drift every release; the single file stays in sync by construction.
- **Template:** maintain `docs/deployment/sessions/_template.md` with `PENDING` / `SUCCESSFUL` / `FAILED` status slots; copy per run.

This is the paper trail humans need when something goes wrong three months later and they're reconstructing the release timeline.

### Environment management

All configuration comes from environment variables loaded from `.env`:

```bash
set -a
source .env
set +a
```

When `.env` changes, force-recreate containers that consume it:

```bash
docker compose up -d --force-recreate web worker
```

**`.env` is never committed.** Provide `.env.example` with all keys and safe defaults. Rotate secrets on staff changes.

### SSL certificates — Let's Encrypt

`docker-compose.yml`:

```yaml
certbot:
  image: certbot/certbot
  command: >
    certonly --webroot --webroot-path=/var/www/certbot
    --email $$CERTBOT_EMAIL --agree-tos --no-eff-email -d $$DOMAIN
  volumes:
    - certbot-etc:/etc/letsencrypt
    - certbot-var:/var/lib/letsencrypt
    - ./nginx/www:/var/www/certbot
```

`nginx` vhost:

```nginx
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    # proxy configuration…
}
```

Renewal runs on a cron/timer or via `docker compose run --rm certbot renew` — do not couple renewal to the main deploy flow.

### Health checks and verification

After every deploy, verify. `HEALTH_URL` below is a project-supplied variable that points at a cheap JSON health endpoint when one exists (`/api/health`, `/healthz`, etc.) and falls back to `/` (landing page 200) when the project doesn't expose a dedicated probe. Never hard-code `/api/health` into a project's verify script without confirming the endpoint actually exists — a 404 from the liveness probe masks real signal.

```bash
docker compose ps                                       # containers healthy
curl -fsI https://${DOMAIN}                             # external HTTPS reachable
curl -fsS https://${DOMAIN}${HEALTH_URL:-/}             # project health endpoint (JSON if available; else landing page)
docker compose exec -T web python manage.py check       # framework-level sanity
```

Wrap these in `verify_deployment.sh` with a **retry loop** — services routinely take 10–30 s after container start to accept traffic, and failing on the first curl produces false-alarm rollbacks.

### Rollback procedures

> ⚠️ **Human-operated only.** Rollback involves destructive git operations (`reset --hard`, force-push) and potentially destructive database operations (restoring a backup over live data). Per [`RULE_git-safety`](../../rules/RULE_git-safety.md), AI agents **must not** execute these steps. Agents prepare the commands, show them, and wait for the human to run them.

**Code rollback** (requires temporarily relaxed branch protection on `deployment`):

```bash
git checkout deployment
git reset --hard <last-good-sha>
git push origin deployment --force-with-lease   # human-initiated only
```

`--force-with-lease` refuses to overwrite remote changes the operator hasn't seen, which is the minimum safety net on a destructive push.

**Redeploy from rolled-back state:**

```bash
git pull origin deployment
./scripts/deploy.sh
```

**Database rollback:**

```bash
./scripts/restore_db.sh data/db_backup_YYYYMMDD_HHMMSS_<sha>.sql.tar.gz
docker compose restart web worker
```

**Paired rollback** (code and data together): restore the DB backup whose `<sha>` suffix matches the code you're reverting to. Mismatched pairs cause schema drift and the app will fail in surprising ways.

### Makefile targets

```makefile
.PHONY: deploy deploy-first deploy-update backup-db restore-db
.PHONY: start stop restart logs health-check

deploy:          ## Auto-detect and run appropriate deploy
	./tools/deploy.sh

deploy-first:    ## First-time deploy + seeding
	./tools/deploy_first_time.sh

deploy-update:   ## Update existing deploy (change-aware)
	./tools/deploy_update.sh

backup-db:       ## Snapshot database
	./tools/backup_db.sh

restore-db:      ## Restore from backup: make restore-db FILE=...
	@test -n "$(FILE)" || { echo "Usage: make restore-db FILE=backup.tar.gz"; exit 1; }
	./tools/restore_db.sh "$(FILE)"

start:           ## Start all services
	docker compose up -d

stop:            ## Stop all services
	docker compose down

restart:         ## Restart all services
	docker compose restart

logs:            ## Tail logs
	docker compose logs -f

health-check:    ## Run verification suite
	./tools/verify_deployment.sh
```

### CI/CD integration

For automated pipelines (GitHub Actions, GitLab CI), see [references/CICD.md](references/CICD.md). Short rules:

- CI **wraps** `deploy.sh` — it does not reimplement the logic.
- Production deploys are **manual-trigger only** — never auto-deploy on `main` push.
- Database backup step runs before the deploy step if change-detection sees a `migrations/` diff.
- SSH host keys are **pinned** via `known_hosts`, not bypassed with `StrictHostKeyChecking=no`.
- Rollback is **not** auto-triggered on pipeline failure — human-in-the-loop only.

## When NOT to use these patterns

- **Zero-downtime required** — this pattern restarts services; brief outages are expected. Use blue/green or rolling deploys via Kubernetes, Nomad, or ECS.
- **Horizontal scaling across hosts** — single-host Docker Compose doesn't scale past one node. Graduate to an orchestrator.
- **Stateless apps without a DB** — the backup/rollback machinery is overhead; a simpler `docker compose pull && up -d` suffices.
- **PaaS deploys** — Heroku/Fly/Railway own the deploy verb; these scripts will conflict with the platform's model.

## Troubleshooting

### Database connection fails on start

- `docker compose ps db` — is the container up and healthy?
- Env vars in the web container match the db container?
- Network reachable: `docker compose exec web nc -zv db 5432`
- DB logs: `docker compose logs db`

### Migration fails mid-deploy

- Inspect the failing migration file for logic errors.
- Check prior migrations all applied cleanly: `docker compose exec web python manage.py showmigrations`.
- Verify the DB user has DDL permission.
- Restore the pre-migration backup and investigate in a separate environment — never debug migrations on live data.

### SSL certificate errors

- `docker compose logs certbot` — renewal output.
- Domain DNS points here: `dig +short $DOMAIN`.
- Ports 80/443 open at the host firewall (UFW) and cloud security group.
- Rate-limited? `certbot certificates` shows expiry; Let's Encrypt enforces renewal limits.

### Permission errors during deploy

- Deploy user has write on the project directory: `ls -la /opt/myapp`.
- SSH key perms: `chmod 600 ~/.ssh/id_rsa`.
- Migrations created by Docker as `root`? Apply the ownership-bypass pattern from the [django skill](../django/SKILL.md) (`chown` from inside the container using the host UID/GID).

### Health check fails post-deploy

- Service logs: `docker compose logs <service>`.
- App reachable from inside the container network? `docker compose exec web curl -f localhost:8000${HEALTH_URL:-/}`.
- OOM? `docker stats` and `dmesg | tail` on the host.

### `.env` changes don't take effect

Containers cache env vars at start. After editing `.env`:

```bash
docker compose up -d --force-recreate <service>
```

Plain `restart` does not reload the environment.

## Why it's generic

Applies to any Docker Compose web application because the pattern is rooted in:

- Container orchestration primitives (services, volumes, networks, healthchecks)
- Database safety during schema change (snapshot + restore, same for every RDBMS)
- Infrastructure automation via shell (no framework dependency)
- Change detection via `git diff` (language-agnostic)

The deploy shape is identical for Django, Rails, Express, FastAPI, Phoenix — only the service names in `docker-compose.yml` and the test/migration commands differ.

## Example use cases

> _Framework-specific notes below are illustrative, not prescriptive._

**Django** — `web` (Daphne ASGI) + `db` (Postgres) + `redis` + `celery` + `certbot`. Migration safety and static collection are the high-risk steps; both are covered by change detection. See [references/DJANGO_DEPLOYMENT.md](references/DJANGO_DEPLOYMENT.md) for specifics.

**Rails** — `web` (Puma) + `db` (Postgres) + `redis` + `sidekiq` + `certbot`. `rails db:migrate` replaces `manage.py migrate`; the asset pipeline runs on dependency change.

**Node.js / Next.js** — `web` (node process manager) + `db` + `certbot`. Build step (`npm run build`) runs on dependency change; static output served via nginx.

## References

- [`scripts/`](scripts/) — reference implementations (`deploy.sh`, `backup_db.sh`, `verify_deployment.sh`, `setup_server.sh`, `harden_server.sh`)
- [`scripts/README.md`](scripts/README.md) — per-script usage and customisation
- [references/SCREEN_SESSIONS.md](references/SCREEN_SESSIONS.md) — mandatory reading for remote deploys; full screen recipes, monitoring, cleanup
- [references/CICD.md](references/CICD.md) — GitHub Actions, GitLab CI, secrets, approval gates
- [references/BARE_METAL_ATOMIC_RELEASES.md](references/BARE_METAL_ATOMIC_RELEASES.md) — the *non-containerised* shape: Ansible + PHP-FPM atomic releases (`current` symlink) on a shared/managed host. `mv -Tf` self-healing swap, symlink-depth/exclude model, host PHP-version mismatch, managed-DB backup without `RELOAD`, ansible-core/target-Python pinning, per-play connection user. Read when the target is bare `/var/www`, not Docker.
- [references/MONITORING.md](references/MONITORING.md) — Prometheus, Grafana, ELK
- [references/DJANGO_DEPLOYMENT.md](references/DJANGO_DEPLOYMENT.md) — Django-specific optimisations (migrations, collectstatic, ASGI)
- [references/HARDENING.md](references/HARDENING.md) — SSH, UFW, fail2ban, unattended upgrades (run before first deploy)
- [references/CONTAINER_DNS_NSS.md](references/CONTAINER_DNS_NSS.md) — `getaddrinfo` shadowing public DNS inside containers; anchor case: `sync_domains` silent drop on fresh Debian VPS when hostname matches domain
- [references/LOCAL_DOCKER_DEV_GOTCHAS.md](references/LOCAL_DOCKER_DEV_GOTCHAS.md) — local dev-stack traps: `.dev` HSTS → `.test`, single-file bind-mount stale-inode, `docker-credential-*` PATH, dev-proxy `default_server` prod-backend footgun
- [references/SHELL_INSTALLERS.md](references/SHELL_INSTALLERS.md) — authoring + review patterns for `tools/install-*.sh`; 15 patterns (pipefail family, chown, marker blocks, opt-out sweep, case-vs-grep security validation, etc.) distilled from review-loop cycles across PRs #55/#58/#59
- [django skill](../django/SKILL.md) — backend patterns that interact with deploy (migrations, collectstatic, ASGI)
- [RULE_git-safety](../../rules/RULE_git-safety.md) — rollback is a human-operated procedure
- [Docker Compose docs](https://docs.docker.com/compose/)
