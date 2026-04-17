# Screen Sessions for Remote Deployments

Companion reference to [`../SKILL.md`](../SKILL.md). Covers mandatory screen-session usage for remote Docker Compose deployments: session naming, log persistence, monitoring, cleanup, and troubleshooting.

## Why screen is mandatory

Remote deployments must survive:

- SSH connection timeouts
- Network interruptions
- API / agent errors that disconnect the invoking client
- Terminal closures or laptop lid events mid-deploy

Without screen (or tmux), any of these kills the deploy partway through. With containers rebuilding, migrations running, or static assets collecting, a partial deploy leaves the system in an inconsistent state. Screen decouples the deploy process from the SSH session.

**Policy:**

| Context           | Screen requirement               |
| ----------------- | -------------------------------- |
| Remote deployment | **Mandatory** — no exceptions    |
| Local deployment  | Optional (user convenience only) |

## Session naming convention

```text
{project}-deploy-{YYYYMMDD-HHMMSS}
```

Example: `teisutis-deploy-20260417-012343`

Timestamping prevents collision when concurrent deploys overlap (e.g. staging + production).

## Canonical start command

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

**Why `DEPLOY_NON_INTERACTIVE=1`:** screen allocates a TTY, so `[ -t 0 ]` returns true inside the session. Prompts in the deploy script then block forever waiting for input that never arrives. Explicit non-interactive mode forces safe defaults regardless of TTY presence.

**Why `tee $LOG`:** screen scrollback is bounded and ephemeral; log files persist. Never rely on `screen -r` alone to retrieve deploy output — always also `tee` to a file.

**Why `date -u`:** UTC timestamps avoid off-by-one confusion when the server and operator are in different timezones.

## Monitoring progress

```bash
# Tail the log (recommended — works even after screen exits)
ssh user@production.com 'tail -f /opt/myapp/deploy-*.log'

# Attach to the screen session (live output, interactive)
ssh -t user@production.com 'screen -r myapp-deploy-20260417-012343'

# Detach from screen while attached: Ctrl+A, then D

# List all sessions on the server
ssh user@production.com 'screen -ls'

# Attach to the most recent deploy session
ssh -t user@production.com \
  'screen -r $(screen -ls | grep deploy | head -1 | cut -d. -f1)'
```

## Session cleanup

After verifying the deploy succeeded:

```bash
# Kill a specific session
ssh user@production.com 'screen -X -S myapp-deploy-20260417-012343 quit'

# Clean up all detached deploy sessions (use with caution — verify success first)
ssh user@production.com \
  'screen -ls | grep Detached | grep deploy | cut -d. -f1 | xargs -I{} screen -X -S {} quit'
```

## Handling long rebuilds (20–30+ minutes)

Screen protects against timeout, so you can safely:

- Close the terminal
- Disconnect VPN
- Switch networks
- Log out

Reconnect anytime with `tail -f` or `screen -r`.

## Best practices

- ✅ **Always screen on remote** — no exceptions, not even for "quick" deploys.
- ✅ **Always `tee` to a log file** — scrollback is ephemeral.
- ✅ **Always timestamped session names** — avoid collision with concurrent runs.
- ✅ **Always `DEPLOY_NON_INTERACTIVE=1`** — prompts inside screen hang forever.
- ✅ **Show initial output after starting** (`sleep 3 && tail -n 50`) — confirms the deploy actually started.
- ❌ **Never reuse session names** — use timestamps.
- ❌ **Never rely on scrollback alone** — it's bounded; log files aren't.
- ❌ **Never kill sessions until the deploy is verified** — you lose forensic state.

## Troubleshooting

### Screen not installed on the server

```bash
ssh user@production.com 'command -v screen || echo "Not installed"'

# Debian/Ubuntu
ssh user@production.com 'sudo apt-get install -y screen'

# RHEL/CentOS
ssh user@production.com 'sudo yum install -y screen'
```

### Can't find the session

```bash
ssh user@production.com 'screen -ls'
ssh user@production.com 'ls -lt /opt/myapp/deploy-*.log | head -5'
```

### Deploy finished, but screen is still active

Normal. Screen persists after the wrapped command completes. Safe to `screen -X -S <name> quit` once the deploy is verified successful (check logs, health-check output, `docker compose ps`).

### Multiple deploys running simultaneously

```bash
ssh user@production.com 'screen -ls | grep deploy'
ssh -t user@production.com 'screen -r <full-session-name>'
```

### Screen session died unexpectedly

Check the log file — screen may have exited because the wrapped command exited (success or failure).

```bash
ssh user@production.com 'tail -n 200 /opt/myapp/deploy-*.log'
```

**Last Updated**: 2026-04-17
