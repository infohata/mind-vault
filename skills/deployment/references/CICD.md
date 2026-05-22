# CI/CD Integration

Companion reference to [`../SKILL.md`](../SKILL.md). Covers automated deployment pipelines (GitHub Actions, GitLab CI) that wrap the `deploy.sh` toolchain, plus change-detection, secrets, approval gates, and notifications.

**Principle:** CI **wraps** `deploy.sh`; it does not reimplement the logic. The same script runs locally, remotely, and from CI — one code path, one set of bugs.

## GitHub Actions

`.github/workflows/deploy.yml`:

```yaml
name: Deploy

on:
  push:
    branches: [deployment]
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        default: 'staging'
        type: choice
        options: [staging, production]

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment || 'staging' }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0          # full history for change detection

      - name: Setup SSH
        uses: webfactory/ssh-agent@v0.9.0
        with:
          ssh-private-key: ${{ secrets.SSH_PRIVATE_KEY }}

      - name: Pin host key
        run: |
          mkdir -p ~/.ssh
          ssh-keyscan -H ${{ secrets.DEPLOY_HOST }} >> ~/.ssh/known_hosts

      - name: Deploy
        run: |
          ssh ${{ secrets.DEPLOY_USER }}@${{ secrets.DEPLOY_HOST }} \
            "cd ${{ secrets.DEPLOY_DIR }} && \
             DEPLOY_NON_INTERACTIVE=1 ./tools/deploy.sh"
```

**Host-key verification is non-negotiable.** Never use `-o StrictHostKeyChecking=no`: a MITM (or a compromised network at the runner) can silently substitute a controlled host for the deploy target, exfiltrate the deploy key, or inject malicious commands. `ssh-keyscan -H <host>` on first setup, or — better — pin the expected fingerprint in a secret and verify it before the scan.

## GitLab CI

`.gitlab-ci.yml`:

```yaml
stages: [test, deploy]

.deploy_template: &deploy
  stage: deploy
  before_script:
    - mkdir -p ~/.ssh && chmod 700 ~/.ssh
    - echo "$SSH_PRIVATE_KEY"  > ~/.ssh/id_rsa     && chmod 600 ~/.ssh/id_rsa
    - echo "$SSH_KNOWN_HOSTS" > ~/.ssh/known_hosts && chmod 644 ~/.ssh/known_hosts
  script:
    - ssh $USER@$HOST "cd $DIR && DEPLOY_NON_INTERACTIVE=1 ./tools/deploy.sh"

deploy_staging:
  <<: *deploy
  variables: { USER: $STAGING_USER, HOST: $STAGING_HOST, DIR: $STAGING_DIR }
  environment: { name: staging, url: https://staging.example.com }
  only: [develop]

deploy_production:
  <<: *deploy
  variables: { USER: $PRODUCTION_USER, HOST: $PRODUCTION_HOST, DIR: $PRODUCTION_DIR }
  environment: { name: production, url: https://example.com }
  when: manual
  only: [main]
```

## Automated change detection

Pre-deploy, decide whether a DB backup is required:

```yaml
- name: Detect migrations
  id: migrations
  run: |
    if git diff --name-only \
         ${{ github.event.before }} ${{ github.sha }} | grep -q "migrations/"; then
      echo "has_migrations=true" >> $GITHUB_OUTPUT
    fi

- name: Backup database (if migrations detected)
  if: steps.migrations.outputs.has_migrations == 'true'
  run: |
    ssh $DEPLOY_USER@$DEPLOY_HOST \
      "cd $DEPLOY_DIR && ./scripts/backup_db.sh"
```

The local `deploy.sh` performs the same detection; CI just hoists the backup step ahead of the deploy so a failed backup blocks the run.

## Secrets

Minimum set for SSH-based deployment:

| Secret                                       | Purpose                                                |
| -------------------------------------------- | ------------------------------------------------------ |
| `SSH_PRIVATE_KEY`                            | Deploy-user private key (ed25519 recommended)          |
| `SSH_KNOWN_HOSTS`                            | Pinned server fingerprints (GitLab) — pre-scanned once |
| `DEPLOY_USER` / `DEPLOY_HOST` / `DEPLOY_DIR` | Target                                                 |
| `CERTBOT_EMAIL`                              | Let's Encrypt registration                             |
| `DOMAIN`                                     | Certificate subject                                    |
| `SLACK_WEBHOOK_URL`                          | Optional, for deploy notifications                     |

**Rotation:**

- Rotate the deploy key on every staff change.
- Use a dedicated deploy-only account on the server — not a developer account, not `root`.
- Consider restricting the shell to `rrsync` or a wrapper that only accepts `./tools/deploy.sh`, to bound blast radius if the key leaks.

## Approval gates

### GitHub Actions — manual approval for production

```yaml
jobs:
  deploy_production:
    environment:
      name: production      # Configure "required reviewers" in GitHub → Settings → Environments
      url: https://example.com
    # ... steps
```

### GitLab CI — manual trigger

```yaml
deploy_production:
  when: manual
  only: { refs: [main] }
```

### Branch protection

`deployment` (or `production`) branch must require:

- PR review
- Up-to-date with `main`
- Status checks passing
- **No force-push** (the rollback-via-force-push pattern is a human, local-branch operation; CI should never push-force to protected branches)

## Notifications

Slack on deploy result:

```yaml
- uses: 8398a7/action-slack@v3
  if: always()
  with:
    status: ${{ job.status }}
    text: "Deploy to ${{ inputs.environment }} ${{ job.status }}"
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

## Security checklist

- [ ] Dedicated deploy key (not a developer SSH key)
- [ ] Host fingerprints pinned via `known_hosts` — never `StrictHostKeyChecking=no`
- [ ] Staging and production secrets separated at the environment level
- [ ] Required reviews on `deployment` branch merges
- [ ] Deploy logs retained ≥90 days (CI provides this by default)
- [ ] Rollback is **not** auto-triggered on pipeline failure — human-in-the-loop only (DB rollback is destructive; code rollback may require branch-protection bypass)
- [ ] Secret rotation schedule (quarterly minimum, or on any staff change)

## Anti-patterns

- ❌ Reimplementing deploy logic inside the pipeline — drift from `deploy.sh` guarantees CI behaviour diverges from local behaviour.
- ❌ Auto-deploy on `main` push — production deploys should always be deliberate.
- ❌ Embedding the deploy key in the repo (even encrypted) — use the CI secret store.
- ❌ Silent rollback on failure — leaves the human unaware the state changed.
- ❌ `chmod 777` anywhere in the pipeline — if permissions are wrong, fix the cause.
