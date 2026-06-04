# Deployment Skill

**Quick-start guide for `skills/deployment/`**

Production-ready deployment patterns for Docker Compose web applications. Prioritises safety (pre-change backups, rollback-ready state, mandatory screen sessions for remote runs) over raw speed. **Not a zero-downtime pattern** — a stop/rebuild/start cycle with health verification; 5–30 s outages on update are expected.

## Structure

```text
skills/deployment/
├── SKILL.md              # Main pattern body
├── README.md             # This overview
├── scripts/              # Deployment automation toolkit
│   ├── deploy.sh             # Auto-detecting wrapper (first-time vs update)
│   ├── deploy_first_time.sh  # Initial deploy + data seed
│   ├── deploy_update.sh      # Change-aware update
│   ├── backup_db.sh          # Database snapshot
│   ├── verify_deployment.sh  # Post-deploy health checks
│   ├── setup_server.sh       # Initial host setup (Docker, pyenv, etc.)
│   └── harden_server.sh      # SSH / UFW / fail2ban hardening
└── references/           # On-demand references (linked from SKILL.md ## References)
    ├── SCREEN_SESSIONS.md    # Mandatory remote-deploy screen recipes
    ├── CICD.md               # GitHub Actions, GitLab CI, secrets, approval gates
    ├── MONITORING.md         # Prometheus, Grafana, ELK
    ├── DJANGO_DEPLOYMENT.md  # Django-specific optimisations
    └── HARDENING.md          # Server hardening before first deploy
```

## Getting started

1. **Copy the scripts** from [`scripts/`](scripts/) into your project's `scripts/` (or `tools/`) directory.

2. **Customise** `docker-compose.yml` for your services.

3. **Configure environment** variables in `.env` (provide a committed `.env.example`).

4. **Initial deploy:**

   ```bash
   ./scripts/deploy_first_time.sh
   ```

5. **Subsequent updates:**

   ```bash
   ./scripts/deploy.sh   # auto-detects first-time vs update
   ```

## Key features

- **Change detection** — diffs git history to decide whether migrations, dependencies, or static assets need rebuilding.
- **Database safety** — automated snapshots before schema change; paired code + DB rollback points (commit sha embedded in backup filename).
- **Service restarts with health checks** — not zero-downtime; wrap health checks in a retry loop since services take 10–30 s to accept traffic.
- **Multi-database support** — PostgreSQL, MySQL, SQLite backup strategies.
- **SSL automation** — Let's Encrypt via certbot + nginx.
- **Remote deployment** — SSH-based with mandatory screen sessions for connection-independence.
- **CI/CD integration** — GitHub Actions / GitLab CI, manual approval gates, pinned host keys.

## Extensions

Load on demand when the pattern applies:

- [`references/SCREEN_SESSIONS.md`](references/SCREEN_SESSIONS.md) — remote deploy mechanics (mandatory reading if you run remote deploys)
- [`references/CICD.md`](references/CICD.md) — pipeline wiring
- [`references/MONITORING.md`](references/MONITORING.md) — Prometheus metrics, Grafana dashboards, ELK logging
- [`references/DJANGO_DEPLOYMENT.md`](references/DJANGO_DEPLOYMENT.md) — Django migrations, static files, multi-tenant
- [`references/HARDENING.md`](references/HARDENING.md) — SSH key-only auth, UFW, fail2ban, unattended security updates

## Framework support

Core patterns work with any Docker Compose application; service names differ, the deploy shape does not.

- **Django** — pairs with the [django skill](../django/SKILL.md) for migration safety and ASGI/WebSocket handling.
- **Rails** — Puma + nginx, asset pipeline on dependency change.
- **Node.js / Next.js** — build step runs on dependency change, static output served via nginx.
- **Any framework** — generic patterns for containerised web apps.

## Safety model

- Automatic backups before destructive operations.
- Health checks with retry loops after each deploy step.
- **Rollback is human-operated** — destructive git (`reset --hard`, `--force-with-lease`) and DB-restore operations are never auto-executed by agents (see [`RULE_git-safety`](../../rules/RULE_git-safety.md)).
- Confirmation prompts on interactive runs; `DEPLOY_NON_INTERACTIVE=1` skips them for CI and screen sessions.

## Documentation

- [`SKILL.md`](SKILL.md) — complete pattern
- [`scripts/README.md`](scripts/README.md) — per-script usage and customisation
- [`rules/RULE_git-safety.md`](../../rules/RULE_git-safety.md) — rollback procedure authority

**Version**: 2.0
