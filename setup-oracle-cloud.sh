#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#
#     ██████╗ ██████╗ ███████╗███╗   ██╗ ██████╗██╗      █████╗ ██╗    ██╗
#    ██╔═══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██║     ██╔══██╗██║    ██║
#    ██║   ██║██████╔╝█████╗  ██╔██╗ ██║██║     ██║     ███████║██║ █╗ ██║
#    ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║██║     ██║     ██╔══██║██║███╗██║
#    ╚██████╔╝██║     ███████╗██║ ╚████║╚██████╗███████╗██║  ██║╚███╔███╔╝
#     ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝
#
#    Oracle Cloud VM Setup — Self-Hosted LiveKit + 3D Voice Agents
#    ──────────────────────────────────────────────────────────────
#    Run this ONCE on a fresh Oracle Cloud ARM64 VM (Ubuntu 22.04+)
#
#    Usage:
#      sudo bash setup-oracle-cloud.sh
#
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

log_ok()    { echo -e "  ${GREEN}✓${NC}  $1"; }
log_warn()  { echo -e "  ${YELLOW}⚠${NC}  $1"; }
log_error() { echo -e "  ${RED}✗${NC}  $1"; }
log_info()  { echo -e "  ${CYAN}ℹ${NC}  $1"; }
log_step()  { echo -e "\n  ${BOLD}[$1]${NC} ${CYAN}$2${NC}"; echo -e "  $(printf '%.0s─' {1..56})"; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║${NC}  ${CYAN}OpenClaw 3D Voice Agents — Oracle Cloud Setup${NC}              ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}  Self-Hosted LiveKit · Unlimited Streaming · Free Tier     ${BOLD}║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Check root ──
if [ "$EUID" -ne 0 ]; then
  log_error "This script must be run as root (sudo)"
  exit 1
fi

# ── Detect architecture ──
ARCH=$(uname -m)
log_info "Architecture: ${ARCH}"
if [[ "$ARCH" != "aarch64" && "$ARCH" != "x86_64" ]]; then
  log_warn "Unexpected architecture: ${ARCH} — proceeding anyway"
fi

# ═══════════════════════════════════════════════════════════════
log_step "1/5" "System updates & dependencies"
# ═══════════════════════════════════════════════════════════════

apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git \
  ufw \
  jq \
  unzip

log_ok "System packages installed"

# ═══════════════════════════════════════════════════════════════
log_step "2/5" "Installing Docker Engine"
# ═══════════════════════════════════════════════════════════════

if command -v docker &>/dev/null; then
  log_ok "Docker already installed: $(docker --version)"
else
  # Add Docker's official GPG key
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  # Add Docker repository
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Enable Docker for the calling user
  CALLING_USER="${SUDO_USER:-ubuntu}"
  usermod -aG docker "$CALLING_USER" 2>/dev/null || true

  systemctl enable docker
  systemctl start docker

  log_ok "Docker installed: $(docker --version)"
  log_ok "Docker Compose: $(docker compose version)"
  log_info "User '${CALLING_USER}' added to docker group"
fi

# ═══════════════════════════════════════════════════════════════
log_step "3/5" "Configuring firewall (iptables + Oracle Cloud)"
# ═══════════════════════════════════════════════════════════════

# Oracle Cloud VMs use iptables by default
# Also open ports via ufw if enabled

# Required ports:
#   80/tcp    - HTTP (Let's Encrypt + redirect)
#   443/tcp   - HTTPS (Caddy → frontend + LiveKit WSS)
#   443/udp   - HTTP/3 QUIC
#   7881/tcp  - LiveKit WebRTC TCP fallback
#   3478/udp  - TURN UDP
#   5349/tcp  - TURN TLS
#   50000-60000/udp - WebRTC media (ICE)

# iptables rules (Oracle Cloud default firewall)
iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
iptables -I INPUT 1 -p udp --dport 443 -j ACCEPT 2>/dev/null || true
iptables -I INPUT 1 -p tcp --dport 7881 -j ACCEPT 2>/dev/null || true
iptables -I INPUT 1 -p udp --dport 3478 -j ACCEPT 2>/dev/null || true
iptables -I INPUT 1 -p tcp --dport 5349 -j ACCEPT 2>/dev/null || true
iptables -I INPUT 1 -p udp --dport 50000:60000 -j ACCEPT 2>/dev/null || true
iptables -I INPUT 1 -p tcp --dport 8081 -j ACCEPT 2>/dev/null || true

# Save iptables rules (persist across reboot)
if command -v netfilter-persistent &>/dev/null; then
  netfilter-persistent save 2>/dev/null || true
else
  apt-get install -y -qq iptables-persistent
  netfilter-persistent save 2>/dev/null || true
fi

log_ok "iptables rules configured"

# UFW (if active)
if ufw status 2>/dev/null | grep -q "active"; then
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 443/udp
  ufw allow 7881/tcp
  ufw allow 3478/udp
  ufw allow 5349/tcp
  ufw allow 50000:60000/udp
  ufw allow 8081/tcp
  ufw reload
  log_ok "UFW rules added"
fi

echo ""
log_warn "IMPORTANT: You must also open these ports in the Oracle Cloud Console:"
log_info "VCN → Subnet → Security List → Add Ingress Rules:"
echo ""
echo -e "    ${CYAN}Port 80/tcp${NC}          — HTTP (Let's Encrypt)"
echo -e "    ${CYAN}Port 443/tcp+udp${NC}     — HTTPS + HTTP/3"
echo -e "    ${CYAN}Port 7881/tcp${NC}        — WebRTC TCP fallback"
echo -e "    ${CYAN}Port 3478/udp${NC}        — TURN UDP"
echo -e "    ${CYAN}Port 5349/tcp${NC}        — TURN TLS"
echo -e "    ${CYAN}Port 50000-60000/udp${NC} — WebRTC media"
echo ""

# ═══════════════════════════════════════════════════════════════
log_step "4/5" "Cloning Voice-Agent repository"
# ═══════════════════════════════════════════════════════════════

CALLING_USER="${SUDO_USER:-ubuntu}"
INSTALL_DIR="/home/${CALLING_USER}/Voice-Agent"

if [ -d "$INSTALL_DIR" ]; then
  log_warn "Directory exists: ${INSTALL_DIR}"
  log_info "Pulling latest changes..."
  cd "$INSTALL_DIR"
  sudo -u "$CALLING_USER" git pull origin openclaw-3d 2>/dev/null || true
else
  cd "/home/${CALLING_USER}"
  sudo -u "$CALLING_USER" git clone https://github.com/appdevwk/Voice-Agent.git
  cd "$INSTALL_DIR"
  sudo -u "$CALLING_USER" git checkout openclaw-3d
fi

log_ok "Repository ready at ${INSTALL_DIR}"

# ── Detect public IP ──
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "UNKNOWN")
log_info "Detected public IP: ${PUBLIC_IP}"

# ═══════════════════════════════════════════════════════════════
log_step "5/5" "Environment configuration"
# ═══════════════════════════════════════════════════════════════

ENV_FILE="${INSTALL_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
  log_ok ".env file already exists"
  log_info "Edit with: nano ${ENV_FILE}"
else
  echo ""
  echo -e "  ${YELLOW}Let's configure your deployment:${NC}"
  echo ""

  read -rp "  Domain (e.g., voice.yourdomain.com): " USER_DOMAIN
  read -rp "  Email for SSL certificates: " USER_EMAIL
  read -rp "  LiveKit API Key [press Enter to generate]: " USER_KEY
  read -rsp "  LiveKit API Secret [press Enter to generate]: " USER_SECRET
  echo ""

  # Generate keys if not provided
  if [ -z "$USER_KEY" ] || [ -z "$USER_SECRET" ]; then
    log_info "Generating LiveKit API credentials..."
    GENERATED=$(docker run --rm livekit/livekit-server generate-keys 2>/dev/null || true)
    if [ -n "$GENERATED" ]; then
      USER_KEY=$(echo "$GENERATED" | grep "API Key" | awk '{print $NF}' || echo "")
      USER_SECRET=$(echo "$GENERATED" | grep "API Secret" | awk '{print $NF}' || echo "")
    fi
    # Fallback if docker generation fails
    if [ -z "$USER_KEY" ]; then
      USER_KEY="API$(openssl rand -hex 8)"
      USER_SECRET="$(openssl rand -base64 32)"
    fi
    log_ok "Generated API Key: ${USER_KEY}"
    log_ok "Generated API Secret: ****${USER_SECRET: -4}"
  fi

  cat > "$ENV_FILE" << EOF
# OpenClaw Voice Agents — Self-Hosted LiveKit
# Generated on $(date -u +"%Y-%m-%d %H:%M UTC")

DOMAIN=${USER_DOMAIN}
ACME_EMAIL=${USER_EMAIL}
NODE_IP=${PUBLIC_IP}

LIVEKIT_API_KEY=${USER_KEY}
LIVEKIT_API_SECRET=${USER_SECRET}

TOKEN_SERVER_PORT=8081
EOF

  chown "$CALLING_USER":"$CALLING_USER" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  log_ok "Created ${ENV_FILE} (permissions: 600)"
fi

# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║${NC}  ${GREEN}Setup Complete${NC}                                             ${BOLD}║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Before deploying, set up DNS:${NC}"
echo ""
echo -e "    A record:  ${BOLD}${USER_DOMAIN:-\$DOMAIN}${NC}          → ${PUBLIC_IP}"
echo -e "    A record:  ${BOLD}livekit.${USER_DOMAIN:-\$DOMAIN}${NC}  → ${PUBLIC_IP}"
echo ""
echo -e "  ${CYAN}Then deploy:${NC}"
echo ""
echo -e "    cd ${INSTALL_DIR}"
echo -e "    docker compose up --build -d"
echo ""
echo -e "  ${CYAN}Check status:${NC}"
echo ""
echo -e "    docker compose ps"
echo -e "    docker compose logs -f"
echo ""
echo -e "  ${CYAN}Your 3D avatars will be at:${NC}"
echo ""
echo -e "    https://${USER_DOMAIN:-\$DOMAIN}"
echo ""
echo -e "  ${YELLOW}Remember to open ports in Oracle Cloud Console${NC}"
echo -e "  ${YELLOW}(VCN → Subnet → Security List → Ingress Rules)${NC}"
echo ""
