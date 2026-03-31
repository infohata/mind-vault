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

## Related Files

- **Script**: `scripts/harden_server.sh` (in this skill)
- **Server setup**: `scripts/setup_server.sh`
- **Deployment**: `scripts/deploy.sh`

## References

- [OpenSSH Security Best Practices](https://www.openssh.com/security.html)
- [fail2ban Documentation](https://github.com/fail2ban/fail2ban)
- [UFW Ubuntu Documentation](https://help.ubuntu.com/community/UFW)
