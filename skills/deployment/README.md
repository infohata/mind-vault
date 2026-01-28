# Deployment Skill

**Quick Start Guide**

This skill provides production-ready deployment patterns for web applications using Docker Compose. It emphasizes safety, automation, and zero-downtime deployments.

## Structure

```
skills/deployment/
├── SKILL.md              # Main deployment patterns and architecture
├── README.md             # This overview guide
├── scripts/              # Deployment automation toolkit
│   ├── deploy.sh         # Smart deployment wrapper (auto-detects changes)
│   ├── deploy_first_time.sh  # Initial setup with data seeding
│   ├── deploy_update.sh  # Change-aware updates
│   ├── backup_db.sh      # Multi-database backup utility
│   └── verify_deployment.sh  # Health checks and verification
└── references/           # Optional extensions (load on-demand)
    ├── MONITORING.md     # Production monitoring with Prometheus/Grafana/ELK
    └── DJANGO_DEPLOYMENT.md  # Django-specific deployment optimizations
```

## Getting Started

1. **Copy the scripts** to your project's `scripts/` directory
2. **Customize** `docker-compose.yml` for your services
3. **Configure environment** variables for your target environment
4. **Run initial deployment**:
   ```bash
   ./scripts/deploy_first_time.sh
   ```
5. **Deploy updates**:
   ```bash
   ./scripts/deploy.sh  # Auto-detects and handles changes safely
   ```

## Key Features

- **Change Detection**: Automatically detects migrations, new services, config changes
- **Database Safety**: Automated backups before schema changes, rollback on failure
- **Zero Downtime**: Service-by-service updates with health checks
- **Multi-Database Support**: PostgreSQL, MySQL, SQLite with appropriate backup strategies
- **SSL Automation**: Let's Encrypt certificates with nginx
- **Remote Deployment**: SSH-based deployment with safety confirmations
- **CI/CD Integration**: GitHub Actions and GitLab CI examples

## Extensions

**Load these on-demand for specific needs:**

- **[Monitoring Integration](references/MONITORING.md)**: Add Prometheus metrics, Grafana dashboards, ELK logging, and alerting
- **[Django Deployment](references/DJANGO_DEPLOYMENT.md)**: Django-specific optimizations for migrations, static files, and multi-tenant support

## Framework Support

The core patterns work with any Docker Compose application:

- **Django**: Full support with migration safety and WebSocket handling
- **Rails**: Puma/nginx setup with asset compilation
- **Node.js**: Express/Next.js with PM2 process management
- **Any Framework**: Generic patterns for containerized web apps

## Safety First

All scripts include safety measures:
- Automatic backups before destructive operations
- Health checks after each deployment step
- Rollback procedures for failed deployments
- Confirmation prompts for production environments

## Integration with Django Skill

This deployment skill integrates seamlessly with the [Django skill](../django/SKILL.md) for comprehensive Django application deployment.

## Documentation

- **[Main Skill](SKILL.md)**: Complete deployment patterns and architecture
- **[Scripts README](scripts/README.md)**: Detailed script usage and customization
- **[Artefacts](../../docs/artefacts/)**: Research, design, and validation documentation

---

**Last Updated**: 2026-01-28