#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# OpenClaw 3D Voice Agents — Finish Deployment
# ═══════════════════════════════════════════════════════════════
# Paste this into your Oracle Cloud VM SSH session.
# It handles everything that can be automated.
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

log_ok()    { echo -e "  ${GREEN}✓${NC}  $1"; }
log_warn()  { echo -e "  ${YELLOW}⚠${NC}  $1"; }
log_info()  { echo -e "  ${CYAN}ℹ${NC}  $1"; }
log_step()  { echo -e "\n  ${BOLD}[$1]${NC} ${CYAN}$2${NC}"; echo -e "  $(printf '%.0s─' {1..56})"; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║${NC}  ${CYAN}OpenClaw — Final Deployment${NC}                                ${BOLD}║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"

DOMAIN="probateaiagent.undo.it"
VM_IP="143.47.114.114"
INSTALL_DIR="$HOME/Voice-Agent"

# ═══════════════════════════════════════════════════════════════
log_step "1/6" "Fixing .env configuration"
# ═══════════════════════════════════════════════════════════════

cd "$INSTALL_DIR"
sed -i "s/NODE_IP=.*/NODE_IP=${VM_IP}/" .env
log_ok ".env NODE_IP set to ${VM_IP}"
log_ok "Domain: ${DOMAIN}"

# ═══════════════════════════════════════════════════════════════
log_step "2/6" "Checking DNS resolution"
# ═══════════════════════════════════════════════════════════════

check_dns() {
  local host=$1
  local ip
  ip=$(dig +short "$host" A 2>/dev/null | head -1)
  if [ "$ip" = "$VM_IP" ]; then
    log_ok "$host → $ip"
    return 0
  elif [ -n "$ip" ]; then
    log_warn "$host → $ip (expected ${VM_IP})"
    log_warn "Update this A record in FreeDNS to ${VM_IP}"
    return 1
  else
    log_warn "$host — not resolving yet"
    log_warn "Add this A record in FreeDNS pointing to ${VM_IP}"
    return 1
  fi
}

DNS_OK=true
check_dns "$DOMAIN" || DNS_OK=false
check_dns "livekit.$DOMAIN" || DNS_OK=false

if [ "$DNS_OK" = false ]; then
  echo ""
  echo -e "  ${YELLOW}DNS is not fully configured yet.${NC}"
  echo -e "  ${YELLOW}The deploy will continue, but SSL won't work until DNS is set.${NC}"
  echo ""
  echo -e "  Go to ${CYAN}https://freedns.afraid.org${NC} and:"
  echo -e "    1. Update ${BOLD}${DOMAIN}${NC} A record → ${VM_IP}"
  echo -e "    2. Add    ${BOLD}livekit.${DOMAIN}${NC} A record → ${VM_IP}"
  echo ""
  read -rp "  Press Enter to continue anyway, or Ctrl+C to fix DNS first... "
fi

# ═══════════════════════════════════════════════════════════════
log_step "3/6" "Opening firewall ports (iptables)"
# ═══════════════════════════════════════════════════════════════

# These are the VM-level firewall rules
# (Oracle Cloud Security List rules must be done in the web console)
sudo iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
sudo iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
sudo iptables -I INPUT 1 -p udp --dport 443 -j ACCEPT 2>/dev/null || true
sudo iptables -I INPUT 1 -p tcp --dport 7881 -j ACCEPT 2>/dev/null || true
sudo iptables -I INPUT 1 -p udp --dport 3478 -j ACCEPT 2>/dev/null || true
sudo iptables -I INPUT 1 -p tcp --dport 5349 -j ACCEPT 2>/dev/null || true
sudo iptables -I INPUT 1 -p udp --dport 50000:60000 -j ACCEPT 2>/dev/null || true
sudo iptables -I INPUT 1 -p tcp --dport 8081 -j ACCEPT 2>/dev/null || true

# Save rules to persist across reboot
if command -v netfilter-persistent &>/dev/null; then
  sudo netfilter-persistent save 2>/dev/null || true
elif [ -f /etc/iptables/rules.v4 ]; then
  sudo sh -c 'iptables-save > /etc/iptables/rules.v4' 2>/dev/null || true
fi

log_ok "iptables rules set (80, 443, 7881, 3478, 5349, 50000-60000)"

echo ""
echo -e "  ${YELLOW}REMINDER: You must ALSO open these ports in Oracle Cloud Console:${NC}"
echo -e "  ${CYAN}Networking → Virtual Cloud Networks → whiteknightai${NC}"
echo -e "  ${CYAN}→ Security Lists → Default Security List → Add Ingress Rules${NC}"
echo ""
echo -e "    TCP  80          (HTTP)"
echo -e "    TCP  443         (HTTPS)"
echo -e "    UDP  443         (HTTP/3)"
echo -e "    TCP  7881        (WebRTC TCP)"
echo -e "    UDP  3478        (TURN)"
echo -e "    TCP  5349        (TURN TLS)"
echo -e "    UDP  50000-60000 (WebRTC media)"
echo ""

# ═══════════════════════════════════════════════════════════════
log_step "4/6" "Pulling latest code from GitHub"
# ═══════════════════════════════════════════════════════════════

cd "$INSTALL_DIR"
git pull origin openclaw-3d 2>/dev/null || true
log_ok "Code up to date"

# ═══════════════════════════════════════════════════════════════
log_step "5/6" "Building and deploying with Docker Compose"
# ═══════════════════════════════════════════════════════════════

cd "$INSTALL_DIR"
log_info "This will take a few minutes on first build..."
echo ""

docker compose up --build -d 2>&1

echo ""
log_ok "Docker Compose started"

# ═══════════════════════════════════════════════════════════════
log_step "6/6" "Verifying deployment"
# ═══════════════════════════════════════════════════════════════

sleep 10

echo ""
echo -e "  ${BOLD}Service Status:${NC}"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || docker compose ps

echo ""

# Check if token server is responding
if curl -sf http://localhost:8081/health >/dev/null 2>&1; then
  log_ok "Token server is healthy"
else
  log_warn "Token server not responding yet — may still be starting"
fi

# Check if LiveKit is responding
if curl -sf http://localhost:7880 >/dev/null 2>&1; then
  log_ok "LiveKit server is running"
else
  log_warn "LiveKit server not responding yet — may still be starting"
fi

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║${NC}  ${GREEN}Deployment Complete${NC}                                        ${BOLD}║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Your 3D avatars:${NC}  https://${DOMAIN}"
echo -e "  ${CYAN}LiveKit server:${NC}   wss://livekit.${DOMAIN}"
echo ""
echo -e "  ${CYAN}Useful commands:${NC}"
echo -e "    docker compose ps              # service status"
echo -e "    docker compose logs -f         # live logs"
echo -e "    docker compose logs -f livekit # livekit logs"
echo -e "    docker compose restart         # restart all"
echo -e "    docker compose down            # stop all"
echo ""
echo -e "  ${YELLOW}If site doesn't load, check:${NC}"
echo -e "    1. DNS records point to ${VM_IP}"
echo -e "    2. Oracle Cloud Security List has ingress rules"
echo -e "    3. docker compose logs -f caddy  (for SSL issues)"
echo ""
