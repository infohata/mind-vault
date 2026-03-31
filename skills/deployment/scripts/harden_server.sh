#!/bin/bash
# Server Hardening Script
# Disables root login, enforces SSH key auth, applies security best practices
# 
# Usage:
#   sudo $0 [hostname]
#
# Arguments:
#   hostname  Server hostname or address for SSH test hints (default: localhost)
#
# Steps when running on a remote server:
#   1. scp harden_server.sh user@your-server:~/
#   2. ssh user@your-server
#   3. chmod +x ~/harden_server.sh
#   4. sudo ~/harden_server.sh your-server   # or omit for localhost
#
# When running on the same machine (e.g. local VM): sudo ~/harden_server.sh

set -e

# Hostname for SSH hints (default: localhost)
HOSTNAME="${1:-localhost}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Server Hardening Script ===${NC}"
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ This script must be run with sudo${NC}"
    echo "Usage: sudo $0 [hostname]"
    exit 1
fi

# Get the actual user (not root when using sudo)
ACTUAL_USER="${SUDO_USER:-$USER}"
if [ "$ACTUAL_USER" = "root" ]; then
    echo -e "${RED}❌ This script should be run via sudo, not as root directly${NC}"
    echo "Log in as your regular user (not root) and run: sudo $0"
    exit 1
fi

echo -e "${YELLOW}⚠️  This script will:${NC}"
echo "  1. Disable root password login via SSH"
echo "  2. Disable password authentication (SSH keys only)"
echo "  3. Configure SSH security settings"
echo "  4. Enable UFW firewall (allow SSH, HTTP, HTTPS)"
echo "  5. Set up automatic security updates"
echo "  6. Configure fail2ban for SSH protection"
echo ""
echo -e "${YELLOW}⚠️  CRITICAL: Ensure you have SSH key access before continuing!${NC}"
echo "  Current user: $ACTUAL_USER"
echo "  Hostname (for SSH hints): $HOSTNAME"
echo ""

# Check if current user has SSH keys
AUTHORIZED_KEYS="/home/$ACTUAL_USER/.ssh/authorized_keys"
if [ ! -f "$AUTHORIZED_KEYS" ] || [ ! -s "$AUTHORIZED_KEYS" ]; then
    echo -e "${RED}❌ WARNING: No SSH authorized_keys found for $ACTUAL_USER${NC}"
    echo "   File: $AUTHORIZED_KEYS"
    echo ""
    echo "You MUST set up SSH key authentication first!"
    echo "On your local machine, run:"
    echo "  ssh-copy-id $ACTUAL_USER@$HOSTNAME"
    echo ""
    read -p "Do you have SSH key access and want to continue anyway? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        echo "Aborted. Set up SSH keys first."
        exit 1
    fi
else
    echo -e "${GREEN}✅ SSH authorized_keys found for $ACTUAL_USER${NC}"
    echo "   Keys: $(grep -c "^ssh-" "$AUTHORIZED_KEYS" 2>/dev/null || echo "0")"
fi

echo ""
read -p "Continue with hardening? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "Aborted by user"
    exit 0
fi

echo ""
echo -e "${BLUE}Starting hardening process...${NC}"
echo ""

# Backup original SSH config
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_DIR="/root/ssh_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp "$SSHD_CONFIG" "$BACKUP_DIR/sshd_config.backup"
echo -e "${GREEN}✅ Backed up SSH config to $BACKUP_DIR${NC}"

# 1. Configure SSH hardening
echo -e "${BLUE}[1/6] Configuring SSH security...${NC}"

# Create a clean SSH config with hardening
cat > /etc/ssh/sshd_config.d/99-hardening.conf << 'EOF'
# SSH Hardening Configuration
# Applied by harden_server.sh

# Disable root login
PermitRootLogin no

# Disable password authentication (SSH keys only)
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# Enable public key authentication
PubkeyAuthentication yes

# Disable unused authentication methods
KerberosAuthentication no
GSSAPIAuthentication no

# Security settings
Protocol 2
X11Forwarding no
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30

# Only allow specific users (uncomment and customize if needed)
# AllowUsers <username> <other-user>

# Use strong ciphers only
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
EOF

echo -e "${GREEN}✅ SSH hardening configuration created${NC}"

# Test SSH config before restarting
echo "Testing SSH configuration..."
if sshd -t; then
    echo -e "${GREEN}✅ SSH configuration is valid${NC}"
else
    echo -e "${RED}❌ SSH configuration has errors!${NC}"
    echo "Restoring backup..."
    cp "$BACKUP_DIR/sshd_config.backup" "$SSHD_CONFIG"
    exit 1
fi

# 2. Install and configure fail2ban
echo -e "${BLUE}[2/6] Installing fail2ban...${NC}"
apt-get update -qq
apt-get install -y fail2ban

# Configure fail2ban for SSH
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
EOF

systemctl enable fail2ban
systemctl restart fail2ban
echo -e "${GREEN}✅ fail2ban configured and started${NC}"

# 3. Configure UFW firewall
echo -e "${BLUE}[3/6] Configuring UFW firewall...${NC}"

# Install UFW if not present
apt-get install -y ufw

# Default policies
ufw --force default deny incoming
ufw --force default allow outgoing

# Allow essential services
ufw --force allow ssh
ufw --force allow http
ufw --force allow https

# Allow Docker Swarm ports if needed (uncomment if using Docker Swarm)
# ufw --force allow 2377/tcp
# ufw --force allow 7946/tcp
# ufw --force allow 7946/udp
# ufw --force allow 4789/udp

# Enable UFW
ufw --force enable
echo -e "${GREEN}✅ UFW firewall configured and enabled${NC}"

# 4. Set up automatic security updates
echo -e "${BLUE}[4/6] Configuring automatic security updates...${NC}"
apt-get install -y unattended-upgrades apt-listchanges

# Configure automatic updates
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

echo -e "${GREEN}✅ Automatic security updates configured${NC}"

# 5. Additional security settings
echo -e "${BLUE}[5/6] Applying additional security settings...${NC}"

# Disable IPv6 if not used (optional - uncomment if needed)
# echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
# echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf

# Protect against IP spoofing
cat >> /etc/sysctl.conf << 'EOF'

# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Log Martians
net.ipv4.conf.all.log_martians = 1
EOF

sysctl -p > /dev/null 2>&1
echo -e "${GREEN}✅ Kernel security parameters applied${NC}"

# 6. Restart SSH service
echo -e "${BLUE}[6/6] Restarting SSH service...${NC}"
echo ""
echo -e "${YELLOW}⚠️  CRITICAL: About to restart SSH service${NC}"
echo "   Your current SSH connection will remain active"
echo "   Test new connection in ANOTHER terminal before closing this one"
echo ""
read -p "Restart SSH now? (yes/no): " -r
if [[ $REPLY =~ ^[Yy]es$ ]]; then
    systemctl restart sshd
    echo -e "${GREEN}✅ SSH service restarted${NC}"
else
    echo -e "${YELLOW}⚠️  SSH service NOT restarted${NC}"
    echo "   Run manually: sudo systemctl restart sshd"
fi

# Summary
echo ""
echo -e "${GREEN}=== Hardening Complete! ===${NC}"
echo ""
echo "Changes applied:"
echo "  ✅ Root login disabled (PermitRootLogin no)"
echo "  ✅ Password authentication disabled (SSH keys only)"
echo "  ✅ SSH security settings hardened"
echo "  ✅ fail2ban installed and configured"
echo "  ✅ UFW firewall enabled (SSH, HTTP, HTTPS allowed)"
echo "  ✅ Automatic security updates enabled"
echo "  ✅ Kernel security parameters applied"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT NEXT STEPS:${NC}"
echo "  1. Test SSH connection in a NEW terminal:"
echo "     ssh $ACTUAL_USER@$HOSTNAME"
echo "  2. Verify you can connect with SSH key authentication"
echo "  3. Only after successful test, close this terminal"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "To check firewall status: sudo ufw status verbose"
echo "To check fail2ban status: sudo fail2ban-client status sshd"
echo "To view SSH config: cat /etc/ssh/sshd_config.d/99-hardening.conf"
echo ""
echo -e "${GREEN}Server hardening complete!${NC}"
