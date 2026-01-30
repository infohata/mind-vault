#!/bin/bash
set -e

echo "=== Server Setup Script for a fresh Ubuntu server ==="
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 1. Install pyenv dependencies and pyenv
echo -e "${BLUE}[1/3] Installing pyenv and Python 3.13...${NC}"
sudo apt-get update
sudo apt-get install -y build-essential libssl-dev zlib1g-dev libbz2-dev \
  libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils \
  tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

# Install pyenv if not already installed
if [ ! -d "$HOME/.pyenv" ]; then
  curl https://pyenv.run | bash
  
  # Add to ~/.bashrc if not already there
  if ! grep -q 'PYENV_ROOT' ~/.bashrc; then
    echo '' >> ~/.bashrc
    echo '# pyenv configuration' >> ~/.bashrc
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
    echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
    echo 'eval "$(pyenv init -)"' >> ~/.bashrc
  fi
  
  # Load pyenv for this script
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
else
  echo "pyenv already installed"
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
fi

# Install Python 3.13 (latest)
PYTHON_VERSION=$(pyenv install --list | grep -E '^\s*3\.13\.[0-9]+$' | tail -1 | tr -d ' ')
if [ -n "$PYTHON_VERSION" ]; then
  echo "Installing Python $PYTHON_VERSION"
  pyenv install -s "$PYTHON_VERSION"
  pyenv global "$PYTHON_VERSION"
  echo -e "${GREEN}Python $PYTHON_VERSION installed and set as global${NC}"
else
  echo "Could not find Python 3.13.x version"
  exit 1
fi

# 2. Install Docker Engine
echo -e "${BLUE}[2/3] Installing Docker Engine...${NC}"
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER
echo -e "${GREEN}Docker installed. You'll need to log out and back in for docker group to take effect${NC}"

# 3. Install Node.js 25.x
echo -e "${BLUE}[3/3] Installing Node.js 25.x...${NC}"
curl -fsSL https://deb.nodesource.com/setup_25.x | sudo -E bash -
sudo apt-get install -y nodejs

echo ""
echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo ""
echo "Installed versions:"
echo "  Python: $(pyenv version)"
echo "  Docker: $(docker --version)"
echo "  Node.js: $(node --version)"
echo "  npm: $(npm --version)"
echo ""
echo "IMPORTANT: Log out and back in for docker group permissions to take effect"
echo "Then you can run: docker run hello-world"
