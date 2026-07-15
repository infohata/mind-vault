# Server Hardening Guide

Reference for hardening a new server before deployment: SSH, firewall, fail2ban, automatic updates. Use with `scripts/harden_server.sh`.

## Quick Start

### 1. Copy script to server
```bash
# From local machine (script lives in mind-vault)
scp skills/deployment/scripts/harden_server.sh user@your-server.com:~/
```

### 2. Run hardening script
```bash
# SSH to server
ssh user@your-server.com

# Make executable and run with sudo
# Pass hostname so the script can show correct ssh/test hints (optional; defaults to localhost)
chmod +x ~/harden_server.sh
sudo ~/harden_server.sh your-server.com
```

### 3. Test new SSH connection
**CRITICAL**: Before closing your current SSH session, test in a NEW terminal:
```bash
# In a NEW terminal window
ssh user@your-server.com
```

If connection works, the hardening is successful!

## What the Script Does

### Security Changes
1. **Disables root login** - `PermitRootLogin no`
2. **Disables password authentication** - SSH keys only
3. **Hardens SSH configuration** - Strong ciphers, limited auth attempts
4. **Installs fail2ban** - Automatic IP banning after failed login attempts
5. **Enables UFW firewall** - Allows only SSH (22), HTTP (80), HTTPS (443)
6. **Automatic security updates** - Unattended upgrades for security patches
7. **Kernel security parameters** - IP spoofing protection, ICMP hardening

### Pre-requisites
- **SSH key authentication must be working** before running this script
- User must have sudo privileges
- Script will check for `~/.ssh/authorized_keys` and warn if missing

## Safety Features

### Backup Before Changes
- Backs up original SSH config to `/root/ssh_backup_YYYYMMDD_HHMMSS/`
- Tests SSH configuration before applying
- Rolls back if configuration is invalid

### Confirmation Prompts
Script asks for confirmation before:
- Starting hardening process
- Restarting SSH service

### Safe Testing
- Your current SSH connection stays active during SSH restart
- You can test new connection before closing current one

## Verification Commands

### Check SSH Configuration
```bash
# View hardening config
sudo cat /etc/ssh/sshd_config.d/99-hardening.conf

# Test SSH config syntax
sudo sshd -t

# Check SSH service status
sudo systemctl status sshd
```

### Check Firewall
```bash
# Firewall status
sudo ufw status verbose

# List all rules
sudo ufw status numbered
```

### Check fail2ban
```bash
# fail2ban status
sudo systemctl status fail2ban

# SSH jail status
sudo fail2ban-client status sshd

# View banned IPs
sudo fail2ban-client status sshd | grep "Banned IP"
```

### Check Automatic Updates
```bash
# View unattended upgrades config
cat /etc/apt/apt.conf.d/50unattended-upgrades

# Check update logs
cat /var/log/unattended-upgrades/unattended-upgrades.log
```

## Rollback Procedure

If something goes wrong:

### 1. Restore SSH Config
```bash
# Find backup
ls -la /root/ssh_backup_*/

# Restore original config
sudo cp /root/ssh_backup_YYYYMMDD_HHMMSS/sshd_config.backup /etc/ssh/sshd_config

# Remove hardening config
sudo rm /etc/ssh/sshd_config.d/99-hardening.conf

# Restart SSH
sudo systemctl restart sshd
```

### 2. Disable Firewall (if needed)
```bash
sudo ufw disable
```

### 3. Stop fail2ban (if needed)
```bash
sudo systemctl stop fail2ban
sudo systemctl disable fail2ban
```

## Additional Hardening (Optional)

### Limit SSH to Specific Users
Edit `/etc/ssh/sshd_config.d/99-hardening.conf`:
```bash
# Uncomment and customize
AllowUsers youruser deploy
```

Then restart SSH:
```bash
sudo systemctl restart sshd
```

### Change SSH Port (if desired)
Add to `/etc/ssh/sshd_config.d/99-hardening.conf`:
```bash
Port 2222  # Or any port above 1024
```

Update firewall:
```bash
sudo ufw allow 2222/tcp
sudo ufw delete allow ssh
sudo systemctl restart sshd
```

### Monitor Failed Login Attempts
```bash
# View auth log
sudo tail -f /var/log/auth.log

# Count failed attempts
sudo grep "Failed password" /var/log/auth.log | wc -l

# Show banned IPs
sudo fail2ban-client status sshd
```

## Troubleshooting

### Can't Connect After Hardening

**Symptom**: SSH connection refused or authentication fails

**Solutions**:
1. Check if you have SSH key in `~/.ssh/authorized_keys` on server
2. From another session (if available), restore SSH config:
   ```bash
   sudo cp /root/ssh_backup_*/sshd_config.backup /etc/ssh/sshd_config
   sudo rm /etc/ssh/sshd_config.d/99-hardening.conf
   sudo systemctl restart sshd
   ```
3. If completely locked out, use server console access (via hosting provider)

### Firewall Blocking Connections

**Symptom**: Can't access web application after hardening

**Check allowed ports**:
```bash
sudo ufw status verbose
```

**Allow additional ports**:
```bash
# Example: Allow custom port
sudo ufw allow 8080/tcp
```

### fail2ban Banning Your IP

**Check if your IP is banned**:
```bash
sudo fail2ban-client status sshd
```

**Unban your IP**:
```bash
sudo fail2ban-client set sshd unbanip YOUR.IP.ADDRESS.HERE
```

**Whitelist your IP** (permanent):
```bash
# Edit fail2ban config
sudo nano /etc/fail2ban/jail.local

# Add under [DEFAULT]
ignoreip = 127.0.0.1/8 YOUR.IP.ADDRESS.HERE

# Restart fail2ban
sudo systemctl restart fail2ban
```

## Server State Checklist

Document your server before and after hardening:

### Before hardening
- [ ] Root login enabled?
- [ ] Password authentication enabled?
- [ ] fail2ban installed?
- [ ] Firewall configured?

### After hardening (target)
- [ ] Root login disabled
- [ ] SSH key authentication only
- [ ] fail2ban protecting SSH
- [ ] UFW firewall (SSH, HTTP, HTTPS)
- [ ] Automatic security updates

## systemd unit sandboxing — gate on the CAPABILITY, never on a proxy for it

Sandbox directives (`ProtectSystem`, `SystemCallFilter`, `RestrictNamespaces`, …) are the cheapest
blast-radius reduction available for a service account. Two traps make them silently harmful.

### `SystemCallFilter=@system-service` requires systemd >= 240 — older systemd does not REJECT it

It **silently** resolves the filter to a ~40-syscall allowlist with **no `openat`/`read`/`mmap`/`socket`**.
`execve` *is* permitted, so the process starts, and then the dynamic loader is denied `openat`. With
`SystemCallErrorNumber=EPERM` set — as hardening drop-ins typically do — the denial returns an errno,
the loader gives up, and the service dies with **`status=127`**. (Default filter action instead kills
with SIGSYS → `signal=SYS` (31), which at least points at seccomp.)

That `status=127` signature is maximally misleading:

- **127 is the LOADER**, not systemd — systemd's own sandbox failures are **226/228/203**, so the
  exit code points away from the sandbox.
- the binary **runs fine by hand** (no seccomp outside the unit),
- the **identical unit works** on a newer box.

Confirm what systemd actually *parsed*, rather than what you wrote:

```bash
systemctl show <unit> -p SystemCallFilter    # a ~40-entry list == the set didn't resolve
```

**Unknown DIRECTIVES degrade gracefully** (systemd warns and skips: `ProtectProc` 247, `ProtectClock`
245, `ProtectKernelLogs` 244, `RestrictSUIDSGID` 242). **An unknown SET inside `SystemCallFilter`
does not.** Check "Added in version" in `systemd.exec(5)` against the **oldest** host in the roster —
not your dev box.

### Gate on the capability, not on the box's flavour

A drop-in gated on `systemd-detect-virt = kvm` is gating on a **proxy** for "modern enough to
sandbox". Proxies break: an estate can span **systemd 229 (Ubuntu 16.04) → 257 (Debian 13)** with virt
type telling you nothing about it. Evaluate the *real* precondition on the target:

```bash
# BOTH gates, evaluated on the target; anything unmet -> portable baseline, never a crash-loop
sdv="$(systemctl --version 2>/dev/null | head -1 | awk '{print $2}' | tr -cd '0-9')"; [ -n "$sdv" ] || sdv=0
virt="$(systemd-detect-virt 2>/dev/null || echo other)"
[ "$virt" = kvm ] && [ "$sdv" -ge 240 ] && install_dropin || rm -f "$dropin"
```

Fail **safe in both directions**, and make the un-gated path `rm -f` the drop-in — so a re-deploy
*repairs* a host that got it under an older, wronger gate instead of needing manual surgery.

Pick the floor by what actually breaks: `>=240` (the `@system-service` floor) keeps a real sandbox on
242–246 hosts at the cost of one silently-ignored `ProtectProc`; a `>=247` floor would strip the
sandbox from those hosts to dodge one ignored line.

*Provenance: br-docs IDEA-029 — a `virt=kvm`-only gate crash-looped promtail on an Ubuntu 18.04 /
systemd 237 host while the identical config ran on systemd 255.*

## Related Files

- **Script**: `scripts/harden_server.sh` (in this skill)
- **Server setup**: `scripts/setup_server.sh`
- **Deployment**: `scripts/deploy.sh`

## References

- [OpenSSH Security Best Practices](https://www.openssh.com/security.html)
- [fail2ban Documentation](https://github.com/fail2ban/fail2ban)
- [UFW Ubuntu Documentation](https://help.ubuntu.com/community/UFW)
