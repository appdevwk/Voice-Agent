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
#    3D Talking Avatar — Installation & Management System
#    ─────────────────────────────────────────────────────
#    Voice Agent Network with Three.js 3D Avatars & ARKit Lip Sync
#
#    Usage:
#      ./3d-avatar-installclaw.sh install   [zip_path]   # Unzip + full install
#      ./3d-avatar-installclaw.sh check                  # Health check everything
#      ./3d-avatar-installclaw.sh start                  # Launch all services
#      ./3d-avatar-installclaw.sh stop                   # Graceful shutdown + save state
#      ./3d-avatar-installclaw.sh restart                # Stop + Start
#      ./3d-avatar-installclaw.sh status                 # Show running services
#      ./3d-avatar-installclaw.sh backup                 # Manual memory snapshot
#      ./3d-avatar-installclaw.sh logs [agent|all]       # Tail logs
#      ./3d-avatar-installclaw.sh uninstall              # Remove everything
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ──────────────────────────────────────────────────────────────────────────────
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly VERSION="2.0.0"

# Default installation target
INSTALL_DIR="${OPENCLAW_HOME:-$HOME/openclaw-voice}"

# Directories
LOG_DIR="$INSTALL_DIR/logs"
PID_DIR="$INSTALL_DIR/.pids"
MEMORY_DIR="$INSTALL_DIR/.memory"
BACKUP_DIR="$INSTALL_DIR/.backups"
STATE_FILE="$INSTALL_DIR/.memory/cluster_state.json"

# OpenClaw Gateway
GATEWAY_HOST="${OPENCLAW_GATEWAY_HOST:-127.0.0.1}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
GATEWAY_URL="http://${GATEWAY_HOST}:${GATEWAY_PORT}/v1/responses"

# Token server
TOKEN_SERVER_PORT="${TOKEN_SERVER_PORT:-8081}"

# Agent list (loaded from config, fallback hardcoded)
AGENT_IDS=(sentinel oracle phantom cipher aegis nexus specter vanguard)

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Agent colors mapped to names (for display)
declare -A AGENT_COLORS=(
  [sentinel]="${GREEN}"
  [oracle]='\033[38;5;208m'
  [phantom]="${MAGENTA}"
  [cipher]="${CYAN}"
  [aegis]="${YELLOW}"
  [nexus]='\033[38;5;205m'
  [specter]="${DIM}"
  [vanguard]="${RED}"
)

declare -A AGENT_NAMES=(
  [sentinel]="Sentinel"
  [oracle]="Oracle"
  [phantom]="Phantom"
  [cipher]="Cipher"
  [aegis]="Aegis"
  [nexus]="Nexus"
  [specter]="Specter"
  [vanguard]="Vanguard"
)

declare -A AGENT_ROLES=(
  [sentinel]="OSINT Intelligence Analyst"
  [oracle]="Data Pattern Analyst"
  [phantom]="Network Recon Specialist"
  [cipher]="Crypto & Comms Analyst"
  [aegis]="Defensive Security Coord"
  [nexus]="Multi-Source Intel Aggregator"
  [specter]="Dark Web Monitor"
  [vanguard]="Mission Commander"
)

# ──────────────────────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
# ──────────────────────────────────────────────────────────────────────────────

banner() {
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║${NC}  ${WHITE}${BOLD}OpenClaw 3D Voice Agent Network${NC}  ${DIM}v${VERSION}${NC}                       ${GREEN}║${NC}"
  echo -e "${GREEN}║${NC}  ${DIM}Three.js Avatars · ARKit Lip Sync · LiveKit WebRTC${NC}         ${GREEN}║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

log_info() {
  echo -e "  ${BLUE}ℹ${NC}  $1"
}

log_ok() {
  echo -e "  ${GREEN}✓${NC}  $1"
}

log_warn() {
  echo -e "  ${YELLOW}⚠${NC}  $1"
}

log_error() {
  echo -e "  ${RED}✗${NC}  $1"
}

log_step() {
  echo -e "\n  ${WHITE}${BOLD}[$1]${NC} $2"
  echo -e "  ${DIM}$(printf '%.0s─' {1..56})${NC}"
}

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

timestamp_file() {
  date +"%Y%m%d_%H%M%S"
}

ensure_dirs() {
  mkdir -p "$LOG_DIR" "$PID_DIR" "$MEMORY_DIR" "$BACKUP_DIR"
}

# Check if a port is in use
port_in_use() {
  local port="$1"
  if command -v lsof &>/dev/null; then
    lsof -i :"$port" -sTCP:LISTEN &>/dev/null
  elif command -v ss &>/dev/null; then
    ss -tlnp | grep -q ":${port} "
  elif command -v netstat &>/dev/null; then
    netstat -tlnp 2>/dev/null | grep -q ":${port} "
  else
    # Fallback: try connecting
    (echo >/dev/tcp/127.0.0.1/"$port") 2>/dev/null
  fi
}

# Get PID of process on a port
pid_on_port() {
  local port="$1"
  if command -v lsof &>/dev/null; then
    lsof -ti :"$port" -sTCP:LISTEN 2>/dev/null | head -1
  else
    echo ""
  fi
}

# Wait for a port to start listening
wait_for_port() {
  local port="$1"
  local label="$2"
  local timeout="${3:-30}"
  local elapsed=0
  while ! port_in_use "$port"; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [ "$elapsed" -ge "$timeout" ]; then
      log_error "$label failed to start within ${timeout}s"
      return 1
    fi
  done
  return 0
}

# ──────────────────────────────────────────────────────────────────────────────
# HEALTH CHECKS
# ──────────────────────────────────────────────────────────────────────────────

check_python() {
  if command -v python3 &>/dev/null; then
    local pyver
    pyver=$(python3 --version 2>&1 | awk '{print $2}')
    local major minor
    major=$(echo "$pyver" | cut -d. -f1)
    minor=$(echo "$pyver" | cut -d. -f2)
    if [ "$major" -ge 3 ] && [ "$minor" -ge 10 ]; then
      log_ok "Python ${pyver}"
      return 0
    else
      log_error "Python 3.10+ required (found ${pyver})"
      return 1
    fi
  else
    log_error "Python 3 not found"
    return 1
  fi
}

check_uv() {
  if command -v uv &>/dev/null; then
    local uvver
    uvver=$(uv --version 2>&1 | head -1)
    log_ok "uv: ${uvver}"
    return 0
  else
    log_warn "uv not found — will install"
    return 1
  fi
}

check_gateway() {
  log_info "Checking OpenClaw Gateway at ${GATEWAY_URL}..."

  # First check if the port is open
  if port_in_use "$GATEWAY_PORT"; then
    log_ok "Gateway port ${GATEWAY_PORT} is open"
  else
    log_warn "Gateway port ${GATEWAY_PORT} not listening"
    log_info "The gateway at ${GATEWAY_URL} must be running before agents can process requests"
    log_info "Agents will still start and queue for gateway connection"
    return 1
  fi

  # Try a health probe
  if command -v curl &>/dev/null; then
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
      --connect-timeout 5 --max-time 10 \
      -X POST "${GATEWAY_URL}" \
      -H "Content-Type: application/json" \
      -d '{"input":"ping","model":"gpt-4.1-mini"}' 2>/dev/null || echo "000")

    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
      log_ok "Gateway healthy (HTTP ${http_code})"
      return 0
    elif [ "$http_code" = "000" ]; then
      log_warn "Gateway not responding (connection failed)"
      return 1
    else
      log_warn "Gateway returned HTTP ${http_code} (may still be starting)"
      return 0
    fi
  else
    log_warn "curl not available — cannot verify gateway health"
    return 1
  fi
}

check_livekit_creds() {
  # Load env if available
  local env_file="$INSTALL_DIR/.env"
  local env_local="$INSTALL_DIR/.env.local"

  if [ -f "$env_local" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$env_local" 2>/dev/null || true
    set +a
  elif [ -f "$env_file" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$env_file" 2>/dev/null || true
    set +a
  fi

  local ok=true
  if [ -z "${LIVEKIT_URL:-}" ]; then
    log_error "LIVEKIT_URL not set"
    ok=false
  else
    log_ok "LIVEKIT_URL: ${LIVEKIT_URL}"
  fi

  if [ -z "${LIVEKIT_API_KEY:-}" ]; then
    log_error "LIVEKIT_API_KEY not set"
    ok=false
  else
    log_ok "LIVEKIT_API_KEY: ${LIVEKIT_API_KEY:0:8}..."
  fi

  if [ -z "${LIVEKIT_API_SECRET:-}" ]; then
    log_error "LIVEKIT_API_SECRET not set"
    ok=false
  else
    log_ok "LIVEKIT_API_SECRET: ****${LIVEKIT_API_SECRET: -4}"
  fi

  $ok && return 0 || return 1
}

check_install_dir() {
  if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/token_server.py" ]; then
    log_ok "Install directory: $INSTALL_DIR"
    return 0
  else
    log_error "OpenClaw not installed at $INSTALL_DIR"
    log_info "Run: $SCRIPT_NAME install [zip_path]"
    return 1
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# MEMORY PERSISTENCE
# ──────────────────────────────────────────────────────────────────────────────

# Save cluster state — PIDs, uptime, timestamps, agent status
save_cluster_state() {
  ensure_dirs
  local ts
  ts=$(timestamp)

  cat > "$STATE_FILE" << STATEJSON
{
  "cluster": "openclaw-3d-avatar",
  "version": "${VERSION}",
  "saved_at": "${ts}",
  "install_dir": "${INSTALL_DIR}",
  "gateway_url": "${GATEWAY_URL}",
  "token_server_port": ${TOKEN_SERVER_PORT},
  "agents": {
$(
  local first=true
  for agent_id in "${AGENT_IDS[@]}"; do
    local pid_file="$PID_DIR/${agent_id}.pid"
    local agent_pid=""
    local running=false
    if [ -f "$pid_file" ]; then
      agent_pid=$(cat "$pid_file")
      if kill -0 "$agent_pid" 2>/dev/null; then
        running=true
      fi
    fi
    if [ "$first" = true ]; then
      first=false
    else
      echo ","
    fi
    printf '    "%s": {"pid": "%s", "running": %s, "name": "%s", "role": "%s"}' \
      "$agent_id" "$agent_pid" "$running" "${AGENT_NAMES[$agent_id]}" "${AGENT_ROLES[$agent_id]}"
  done
)
  },
  "token_server": {
$(
    local ts_pid=""
    local ts_running=false
    if [ -f "$PID_DIR/token-server.pid" ]; then
      ts_pid=$(cat "$PID_DIR/token-server.pid")
      if kill -0 "$ts_pid" 2>/dev/null; then
        ts_running=true
      fi
    fi
    printf '    "pid": "%s", "running": %s, "port": %d' "$ts_pid" "$ts_running" "$TOKEN_SERVER_PORT"
)
  }
}
STATEJSON

  log_ok "Cluster state saved to ${STATE_FILE}"
}

# Save conversation transcripts and logs for memory persistence
save_memory_snapshot() {
  ensure_dirs
  local snapshot_dir="$MEMORY_DIR/snapshots/$(timestamp_file)"
  mkdir -p "$snapshot_dir"

  log_info "Creating memory snapshot at ${snapshot_dir}..."

  # Copy current logs
  if [ -d "$LOG_DIR" ] && [ "$(ls -A "$LOG_DIR" 2>/dev/null)" ]; then
    cp -r "$LOG_DIR"/*.log "$snapshot_dir/" 2>/dev/null || true
    log_ok "Agent logs archived"
  fi

  # Save current config state
  if [ -f "$INSTALL_DIR/agents_config.json" ]; then
    cp "$INSTALL_DIR/agents_config.json" "$snapshot_dir/agents_config.json"
    log_ok "Agent configuration archived"
  fi

  # Save cluster state
  if [ -f "$STATE_FILE" ]; then
    cp "$STATE_FILE" "$snapshot_dir/cluster_state.json"
  fi

  # Save any agent-local memory/state files
  for agent_id in "${AGENT_IDS[@]}"; do
    local agent_dir="$INSTALL_DIR/agents/${agent_id}"
    if [ -d "$agent_dir" ]; then
      # Capture any .json state files agents may have created
      find "$agent_dir" -maxdepth 2 -name "*.json" -newer "$agent_dir/pyproject.toml" \
        -exec cp {} "$snapshot_dir/" \; 2>/dev/null || true
      # Capture any conversation/memory files
      find "$agent_dir" -maxdepth 2 \( -name "*memory*" -o -name "*state*" -o -name "*history*" -o -name "*transcript*" \) \
        -exec cp {} "$snapshot_dir/" \; 2>/dev/null || true
    fi
  done

  # Create snapshot manifest
  local running_count
  running_count=$(pgrep -c -f "agent.py" 2>/dev/null || true)
  running_count=${running_count:-0}
  local snap_size_kb
  snap_size_kb=$(du -sk "$snapshot_dir" 2>/dev/null | cut -f1 || true)
  snap_size_kb=${snap_size_kb:-0}
  local file_list
  file_list=$(find "$snapshot_dir" -type f \( -name "*.log" -o -name "*.json" \) | sort | \
    sed 's|.*/||' | awk 'BEGIN{first=1} {if(!first) printf ",\n"; printf "    \"%s\"",$0; first=0}')

  cat > "$snapshot_dir/manifest.json" << MANIFEST
{
  "snapshot_time": "$(timestamp)",
  "version": "${VERSION}",
  "agents_running": ${running_count},
  "total_log_size_kb": ${snap_size_kb},
  "files": [
${file_list}
  ]
}
MANIFEST

  log_ok "Memory snapshot complete: $(find "$snapshot_dir" -type f | wc -l) files saved"
  echo -e "       ${DIM}Location: ${snapshot_dir}${NC}"
}

# Rotate old snapshots — keep last N
rotate_snapshots() {
  local keep="${1:-20}"
  local snapshot_base="$MEMORY_DIR/snapshots"
  if [ -d "$snapshot_base" ]; then
    local count
    count=$(find "$snapshot_base" -mindepth 1 -maxdepth 1 -type d | wc -l)
    if [ "$count" -gt "$keep" ]; then
      local to_remove=$((count - keep))
      find "$snapshot_base" -mindepth 1 -maxdepth 1 -type d | sort | head -n "$to_remove" | \
        xargs rm -rf
      log_info "Rotated ${to_remove} old snapshots (keeping last ${keep})"
    fi
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# INSTALL
# ──────────────────────────────────────────────────────────────────────────────

cmd_install() {
  local zip_path="${1:-}"
  banner

  log_step "1/7" "Pre-flight checks"

  check_python || {
    log_error "Cannot proceed without Python 3.10+"
    exit 1
  }

  # Install uv if missing
  if ! check_uv; then
    log_info "Installing uv package manager..."
    curl -LsSf https://astral.sh/uv/install.sh | sh 2>/dev/null
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    if command -v uv &>/dev/null; then
      log_ok "uv installed successfully"
    else
      log_error "Failed to install uv — install manually: https://docs.astral.sh/uv/"
      exit 1
    fi
  fi

  # ── Unzip if path provided ──
  log_step "2/7" "Extracting project files"

  if [ -n "$zip_path" ]; then
    if [ ! -f "$zip_path" ]; then
      log_error "Zip file not found: $zip_path"
      exit 1
    fi

    # Determine install location
    if [ -d "$INSTALL_DIR" ]; then
      log_warn "Existing installation found at $INSTALL_DIR"
      log_info "Creating backup before overwrite..."
      if [ -d "$MEMORY_DIR" ]; then
        save_memory_snapshot 2>/dev/null || true
      fi
    fi

    mkdir -p "$INSTALL_DIR"

    # Unzip — handle both flat and nested zip structures
    log_info "Extracting ${zip_path} to ${INSTALL_DIR}..."
    local temp_extract
    temp_extract=$(mktemp -d)

    unzip -qo "$zip_path" -d "$temp_extract"

    # Check if zip has a single root directory or is flat
    local item_count
    item_count=$(find "$temp_extract" -mindepth 1 -maxdepth 1 | wc -l)
    local first_item
    first_item=$(find "$temp_extract" -mindepth 1 -maxdepth 1 | head -1)

    if [ "$item_count" -eq 1 ] && [ -d "$first_item" ]; then
      # Single root directory — move its contents
      cp -a "$first_item"/. "$INSTALL_DIR/"
    else
      # Flat structure — copy as-is
      cp -a "$temp_extract"/. "$INSTALL_DIR/"
    fi

    rm -rf "$temp_extract"
    log_ok "Extracted to $INSTALL_DIR"
  else
    # No zip — check if already installed or install from current directory
    if [ -f "$INSTALL_DIR/token_server.py" ]; then
      log_ok "Using existing installation at $INSTALL_DIR"
    elif [ -f "$SCRIPT_DIR/token_server.py" ]; then
      INSTALL_DIR="$SCRIPT_DIR"
      log_ok "Using source directory: $INSTALL_DIR"
    else
      log_error "No zip file provided and no existing installation found"
      log_info "Usage: $SCRIPT_NAME install /path/to/openclaw-voice.zip"
      log_info "  Or set OPENCLAW_HOME to an existing installation"
      exit 1
    fi
  fi

  # Update derived paths
  LOG_DIR="$INSTALL_DIR/logs"
  PID_DIR="$INSTALL_DIR/.pids"
  MEMORY_DIR="$INSTALL_DIR/.memory"
  BACKUP_DIR="$INSTALL_DIR/.backups"
  STATE_FILE="$MEMORY_DIR/cluster_state.json"

  # ── Create directory structure ──
  log_step "3/7" "Creating directory structure"

  ensure_dirs
  mkdir -p "$INSTALL_DIR/static"

  log_ok "logs/          — Runtime logs for all agents"
  log_ok ".pids/         — PID tracking for graceful shutdown"
  log_ok ".memory/       — Persistent agent memory & state"
  log_ok ".backups/      — Pre-upgrade backups"
  log_ok ".memory/snapshots/ — Timestamped state snapshots"

  # ── Environment setup ──
  log_step "4/7" "Environment configuration"

  # ── Lexi-Claw LiveKit credentials ──
  # Reads from environment or prompts user
  local LK_URL="${LIVEKIT_URL:-wss://lexi-claw-s7tmu0rh.livekit.cloud}"
  local LK_KEY="${LIVEKIT_API_KEY:-}"
  local LK_SECRET="${LIVEKIT_API_SECRET:-}"

  if [ -z "$LK_KEY" ] || [ -z "$LK_SECRET" ]; then
    log_warn "LiveKit API credentials not found in environment"
    echo ""
    echo -e "  ${YELLOW}Enter your LiveKit credentials (from https://cloud.livekit.io/):${NC}"
    read -rp "  LIVEKIT_API_KEY: " LK_KEY
    read -rsp "  LIVEKIT_API_SECRET: " LK_SECRET
    echo ""
    echo ""
  fi

  # Write .env with credentials
  cat > "$INSTALL_DIR/.env" << ENVFILE
# OpenClaw Voice Agent Network — Environment Configuration
# ─────────────────────────────────────────────────────────
# Lexi-Claw LiveKit Cloud credentials
LIVEKIT_URL=${LK_URL}
LIVEKIT_API_KEY=${LK_KEY}
LIVEKIT_API_SECRET=${LK_SECRET}

# Token server port (8081 to avoid conflict with Nomad on 8080)
TOKEN_SERVER_PORT=8081
ENVFILE
  log_ok "Created .env with LiveKit credentials (port 8081)"

  # ── Install Python dependencies ──
  log_step "5/7" "Installing Python dependencies"

  cd "$INSTALL_DIR"

  # Token server dependencies
  log_info "Installing token server dependencies..."
  if [ -f "requirements.txt" ]; then
    pip install -q -r requirements.txt 2>/dev/null && \
      log_ok "Token server: fastapi, uvicorn, livekit-api, python-dotenv" || \
      log_warn "pip install had warnings — check manually"
  fi

  # ── Generate agent directories ──
  log_step "6/7" "Generating agent directories"

  if [ -f "generate_agents.py" ]; then
    # Only regenerate if agents dir is missing or empty
    if [ ! -d "agents/sentinel/src" ]; then
      log_info "Running agent generator..."
      python3 generate_agents.py 2>&1 | while IFS= read -r line; do
        echo -e "    ${DIM}${line}${NC}"
      done
      log_ok "8 agent directories generated"
    else
      log_ok "Agent directories already exist"
    fi
  else
    log_warn "generate_agents.py not found — agents may not be configured"
  fi

  # ── Sync agent dependencies ──
  log_step "7/7" "Syncing agent dependencies"

  local agent_count=0
  for agent_id in "${AGENT_IDS[@]}"; do
    local agent_dir="$INSTALL_DIR/agents/${agent_id}"
    if [ -d "$agent_dir" ] && [ -f "$agent_dir/pyproject.toml" ]; then
      echo -ne "  ${DIM}  Syncing ${AGENT_NAMES[$agent_id]}...${NC}"
      cd "$agent_dir"

      # Create .env.local for agent if not exists
      if [ ! -f ".env.local" ] && [ -f "$INSTALL_DIR/.env" ]; then
        cp "$INSTALL_DIR/.env" ".env.local"
      fi

      if uv sync --quiet 2>/dev/null; then
        echo -e "\r  ${GREEN}✓${NC}  ${AGENT_COLORS[$agent_id]}${AGENT_NAMES[$agent_id]}${NC}  ${DIM}— ${AGENT_ROLES[$agent_id]}${NC}  "
        agent_count=$((agent_count + 1))
      else
        echo -e "\r  ${YELLOW}⚠${NC}  ${AGENT_NAMES[$agent_id]}  ${DIM}— sync had warnings${NC}  "
        agent_count=$((agent_count + 1))
      fi

      cd "$INSTALL_DIR"
    fi
  done

  log_ok "${agent_count}/8 agents synced"

  # ── Save initial state ──
  save_cluster_state

  # ── Summary ──
  echo ""
  echo -e "  ${GREEN}${BOLD}═══════════════════════════════════════════════════════${NC}"
  echo -e "  ${GREEN}${BOLD}  Installation Complete${NC}"
  echo -e "  ${GREEN}${BOLD}═══════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${WHITE}Install directory:${NC}  $INSTALL_DIR"
  echo -e "  ${WHITE}Agents installed:${NC}  ${agent_count}/8"
  echo -e "  ${WHITE}Frontend:${NC}          3D Three.js + ARKit Lip Sync"
  echo ""
  echo -e "  ${WHITE}Next steps:${NC}"
  echo -e "    1. Edit ${CYAN}${INSTALL_DIR}/.env${NC} with LiveKit credentials"
  echo -e "    2. Ensure OpenClaw gateway is running on port ${GATEWAY_PORT}"
  echo -e "    3. Run: ${GREEN}${SCRIPT_NAME} start${NC}"
  echo ""
}

# ──────────────────────────────────────────────────────────────────────────────
# CHECK
# ──────────────────────────────────────────────────────────────────────────────

cmd_check() {
  banner
  log_step "1/5" "System requirements"
  check_python || true
  check_uv || true

  log_step "2/5" "Installation"
  check_install_dir || true

  log_step "3/5" "LiveKit credentials"
  check_livekit_creds || true

  log_step "4/5" "OpenClaw Gateway"
  check_gateway || true

  log_step "5/5" "Port availability"
  if port_in_use "$TOKEN_SERVER_PORT"; then
    local existing_pid
    existing_pid=$(pid_on_port "$TOKEN_SERVER_PORT")
    log_warn "Port ${TOKEN_SERVER_PORT} already in use (PID ${existing_pid:-unknown})"
  else
    log_ok "Port ${TOKEN_SERVER_PORT} available for token server"
  fi

  echo ""
}

# ──────────────────────────────────────────────────────────────────────────────
# START
# ──────────────────────────────────────────────────────────────────────────────

cmd_start() {
  banner
  ensure_dirs

  # Verify installation
  if [ ! -f "$INSTALL_DIR/token_server.py" ]; then
    # Try script directory
    if [ -f "$SCRIPT_DIR/token_server.py" ]; then
      INSTALL_DIR="$SCRIPT_DIR"
      LOG_DIR="$INSTALL_DIR/logs"
      PID_DIR="$INSTALL_DIR/.pids"
      MEMORY_DIR="$INSTALL_DIR/.memory"
      STATE_FILE="$MEMORY_DIR/cluster_state.json"
      ensure_dirs
    else
      log_error "OpenClaw not installed. Run: $SCRIPT_NAME install"
      exit 1
    fi
  fi

  # Load environment
  if [ -f "$INSTALL_DIR/.env.local" ]; then
    set -a; source "$INSTALL_DIR/.env.local" 2>/dev/null || true; set +a
  elif [ -f "$INSTALL_DIR/.env" ]; then
    set -a; source "$INSTALL_DIR/.env" 2>/dev/null || true; set +a
  fi

  # Check if already running
  if [ -f "$PID_DIR/token-server.pid" ]; then
    local existing_pid
    existing_pid=$(cat "$PID_DIR/token-server.pid")
    if kill -0 "$existing_pid" 2>/dev/null; then
      log_warn "OpenClaw appears to be already running (token server PID: ${existing_pid})"
      log_info "Use '${SCRIPT_NAME} status' to check, or '${SCRIPT_NAME} restart' to restart"
      exit 0
    fi
  fi

  # ── Pre-flight checks ──
  log_step "1/4" "Pre-flight health checks"

  local creds_ok=true
  if [ -z "${LIVEKIT_URL:-}" ] || [ -z "${LIVEKIT_API_KEY:-}" ] || [ -z "${LIVEKIT_API_SECRET:-}" ]; then
    log_error "LiveKit credentials not configured"
    log_info "Edit ${INSTALL_DIR}/.env and set LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET"
    creds_ok=false
  else
    log_ok "LiveKit credentials loaded"
  fi

  # Check gateway — warn but don't block
  if check_gateway 2>/dev/null; then
    log_ok "OpenClaw Gateway reachable"
  else
    log_warn "OpenClaw Gateway not reachable — agents will queue for connection"
  fi

  if [ "$creds_ok" = false ]; then
    log_error "Cannot start without LiveKit credentials"
    exit 1
  fi

  # ── Start token server ──
  log_step "2/4" "Starting token server"

  # Kill anything on port if stale
  if port_in_use "$TOKEN_SERVER_PORT"; then
    local stale_pid
    stale_pid=$(pid_on_port "$TOKEN_SERVER_PORT")
    if [ -n "$stale_pid" ]; then
      log_warn "Killing stale process on port ${TOKEN_SERVER_PORT} (PID ${stale_pid})"
      kill "$stale_pid" 2>/dev/null || true
      sleep 1
    fi
  fi

  cd "$INSTALL_DIR"
  python3 token_server.py > "$LOG_DIR/token-server.log" 2>&1 &
  local ts_pid=$!
  echo "$ts_pid" > "$PID_DIR/token-server.pid"

  if wait_for_port "$TOKEN_SERVER_PORT" "Token server" 15; then
    log_ok "Token server running on port ${TOKEN_SERVER_PORT} (PID ${ts_pid})"
    log_ok "Frontend: ${CYAN}http://localhost:${TOKEN_SERVER_PORT}${NC}"
  else
    log_error "Token server failed to start — check $LOG_DIR/token-server.log"
    cat "$LOG_DIR/token-server.log" 2>/dev/null | tail -5 | while IFS= read -r line; do
      echo -e "    ${DIM}${line}${NC}"
    done
    exit 1
  fi

  # ── Start agents ──
  log_step "3/4" "Launching voice agents"

  local started=0
  local failed=0

  for agent_id in "${AGENT_IDS[@]}"; do
    local agent_dir="$INSTALL_DIR/agents/${agent_id}"
    local agent_src="$agent_dir/src/agent.py"

    if [ ! -f "$agent_src" ]; then
      log_warn "Agent ${agent_id}: source not found, skipping"
      failed=$((failed + 1))
      continue
    fi

    cd "$agent_dir"

    # Ensure agent has credentials
    if [ ! -f ".env.local" ]; then
      cat > ".env.local" << AGENTENV
LIVEKIT_URL=${LIVEKIT_URL}
LIVEKIT_API_KEY=${LIVEKIT_API_KEY}
LIVEKIT_API_SECRET=${LIVEKIT_API_SECRET}
AGENTENV
    fi

    # Start agent
    if command -v uv &>/dev/null; then
      uv run python src/agent.py dev > "$LOG_DIR/${agent_id}.log" 2>&1 &
    else
      python3 src/agent.py dev > "$LOG_DIR/${agent_id}.log" 2>&1 &
    fi

    local agent_pid=$!
    echo "$agent_pid" > "$PID_DIR/${agent_id}.pid"

    # Brief pause to avoid thundering herd
    sleep 0.5

    # Verify process is still alive
    if kill -0 "$agent_pid" 2>/dev/null; then
      echo -e "  ${GREEN}✓${NC}  ${AGENT_COLORS[$agent_id]}${AGENT_NAMES[$agent_id]}${NC}  ${DIM}PID ${agent_pid} — ${AGENT_ROLES[$agent_id]}${NC}"
      started=$((started + 1))
    else
      log_warn "${AGENT_NAMES[$agent_id]} exited immediately — check $LOG_DIR/${agent_id}.log"
      failed=$((failed + 1))
    fi

    cd "$INSTALL_DIR"
  done

  # ── Save state and report ──
  log_step "4/4" "System status"

  save_cluster_state

  echo ""
  echo -e "  ${GREEN}${BOLD}═══════════════════════════════════════════════════════${NC}"
  echo -e "  ${GREEN}${BOLD}  OpenClaw 3D Avatar Network — ONLINE${NC}"
  echo -e "  ${GREEN}${BOLD}═══════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${WHITE}Agents running:${NC}    ${started}/8"
  [ "$failed" -gt 0 ] && echo -e "  ${RED}Agents failed:${NC}     ${failed}/8"
  echo -e "  ${WHITE}Token server:${NC}      PID $(cat "$PID_DIR/token-server.pid")"
  echo -e "  ${WHITE}Frontend:${NC}          ${CYAN}http://localhost:${TOKEN_SERVER_PORT}${NC}"
  echo -e "  ${WHITE}Logs:${NC}              ${LOG_DIR}/"
  echo -e "  ${WHITE}Memory:${NC}            ${MEMORY_DIR}/"
  echo ""
  echo -e "  ${DIM}Stop gracefully:${NC}   ${SCRIPT_NAME} stop"
  echo -e "  ${DIM}View status:${NC}       ${SCRIPT_NAME} status"
  echo -e "  ${DIM}Tail logs:${NC}         ${SCRIPT_NAME} logs [agent_name|all]"
  echo ""
}

# ──────────────────────────────────────────────────────────────────────────────
# STOP — Graceful shutdown with memory persistence
# ──────────────────────────────────────────────────────────────────────────────

cmd_stop() {
  banner

  if [ -f "$SCRIPT_DIR/token_server.py" ] && [ ! -f "$INSTALL_DIR/token_server.py" ]; then
    INSTALL_DIR="$SCRIPT_DIR"
    LOG_DIR="$INSTALL_DIR/logs"
    PID_DIR="$INSTALL_DIR/.pids"
    MEMORY_DIR="$INSTALL_DIR/.memory"
    STATE_FILE="$MEMORY_DIR/cluster_state.json"
  fi

  ensure_dirs

  log_step "1/3" "Saving agent memory and state"

  # Take a memory snapshot before shutdown
  save_memory_snapshot

  # Rotate old snapshots
  rotate_snapshots 20

  log_step "2/3" "Graceful agent shutdown"

  local stopped=0

  # Stop agents first (reverse order — commander last)
  local reverse_agents=(vanguard specter nexus aegis cipher phantom oracle sentinel)

  for agent_id in "${reverse_agents[@]}"; do
    local pid_file="$PID_DIR/${agent_id}.pid"
    if [ -f "$pid_file" ]; then
      local agent_pid
      agent_pid=$(cat "$pid_file")
      if kill -0 "$agent_pid" 2>/dev/null; then
        # Send SIGTERM for graceful shutdown
        kill -TERM "$agent_pid" 2>/dev/null || true
        echo -e "  ${YELLOW}↓${NC}  ${AGENT_COLORS[$agent_id]}${AGENT_NAMES[$agent_id]}${NC}  ${DIM}PID ${agent_pid} — SIGTERM sent${NC}"
        stopped=$((stopped + 1))
      fi
      rm -f "$pid_file"
    fi
  done

  # Wait for agents to exit gracefully (up to 10 seconds)
  if [ "$stopped" -gt 0 ]; then
    log_info "Waiting for ${stopped} agents to shut down gracefully..."
    local wait_count=0
    while [ "$wait_count" -lt 10 ]; do
      local still_running=0
      for agent_id in "${AGENT_IDS[@]}"; do
        local pid_file="$PID_DIR/${agent_id}.pid"
        if [ -f "$pid_file" ]; then
          local agent_pid
          agent_pid=$(cat "$pid_file")
          if kill -0 "$agent_pid" 2>/dev/null; then
            still_running=$((still_running + 1))
          fi
        fi
      done
      if [ "$still_running" -eq 0 ]; then
        break
      fi
      sleep 1
      wait_count=$((wait_count + 1))
    done

    # Force-kill any remaining
    for agent_id in "${AGENT_IDS[@]}"; do
      local pid_file="$PID_DIR/${agent_id}.pid"
      if [ -f "$pid_file" ]; then
        local agent_pid
        agent_pid=$(cat "$pid_file")
        if kill -0 "$agent_pid" 2>/dev/null; then
          kill -9 "$agent_pid" 2>/dev/null || true
          log_warn "${AGENT_NAMES[$agent_id]} force-killed (PID ${agent_pid})"
        fi
        rm -f "$pid_file"
      fi
    done
  fi

  # Stop token server
  if [ -f "$PID_DIR/token-server.pid" ]; then
    local ts_pid
    ts_pid=$(cat "$PID_DIR/token-server.pid")
    if kill -0 "$ts_pid" 2>/dev/null; then
      kill -TERM "$ts_pid" 2>/dev/null || true
      sleep 2
      if kill -0 "$ts_pid" 2>/dev/null; then
        kill -9 "$ts_pid" 2>/dev/null || true
      fi
      log_ok "Token server stopped (PID ${ts_pid})"
    fi
    rm -f "$PID_DIR/token-server.pid"
  fi

  # Also cleanup any orphaned processes
  pkill -f "token_server.py" 2>/dev/null || true
  pkill -f "agent.py dev" 2>/dev/null || true

  log_step "3/3" "Final state"

  # Save final cluster state
  save_cluster_state

  echo ""
  echo -e "  ${GREEN}${BOLD}═══════════════════════════════════════════════════════${NC}"
  echo -e "  ${GREEN}${BOLD}  OpenClaw Network — OFFLINE${NC}"
  echo -e "  ${GREEN}${BOLD}═══════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${WHITE}Agents stopped:${NC}    ${stopped}"
  echo -e "  ${WHITE}Memory saved:${NC}      ${MEMORY_DIR}/snapshots/"
  echo -e "  ${WHITE}State persisted:${NC}   ${STATE_FILE}"
  echo ""
  echo -e "  ${DIM}All agent memory, transcripts, and logs have been preserved.${NC}"
  echo -e "  ${DIM}Resume with:${NC} ${GREEN}${SCRIPT_NAME} start${NC}"
  echo ""
}

# ──────────────────────────────────────────────────────────────────────────────
# RESTART
# ──────────────────────────────────────────────────────────────────────────────

cmd_restart() {
  log_info "Restarting OpenClaw network..."
  cmd_stop
  sleep 2
  cmd_start
}

# ──────────────────────────────────────────────────────────────────────────────
# STATUS
# ──────────────────────────────────────────────────────────────────────────────

cmd_status() {
  banner

  if [ -f "$SCRIPT_DIR/token_server.py" ] && [ ! -f "$INSTALL_DIR/token_server.py" ]; then
    INSTALL_DIR="$SCRIPT_DIR"
    PID_DIR="$INSTALL_DIR/.pids"
    MEMORY_DIR="$INSTALL_DIR/.memory"
    STATE_FILE="$MEMORY_DIR/cluster_state.json"
  fi

  echo -e "  ${WHITE}${BOLD}Service Status${NC}"
  echo -e "  ${DIM}$(printf '%.0s─' {1..56})${NC}"

  # Token server
  local ts_status="${RED}OFFLINE${NC}"
  local ts_pid=""
  if [ -f "$PID_DIR/token-server.pid" ]; then
    ts_pid=$(cat "$PID_DIR/token-server.pid")
    if kill -0 "$ts_pid" 2>/dev/null; then
      ts_status="${GREEN}ONLINE${NC}"
    fi
  fi
  printf "  %-20s %b  %s\n" "Token Server" "$ts_status" "${ts_pid:+PID ${ts_pid}}"

  # Gateway
  local gw_status="${RED}OFFLINE${NC}"
  if port_in_use "$GATEWAY_PORT"; then
    gw_status="${GREEN}ONLINE${NC}"
  fi
  printf "  %-20s %b  %s\n" "OpenClaw Gateway" "$gw_status" "port ${GATEWAY_PORT}"

  echo ""
  echo -e "  ${WHITE}${BOLD}Agent Roster${NC}"
  echo -e "  ${DIM}$(printf '%.0s─' {1..56})${NC}"

  local online=0
  local offline=0

  for agent_id in "${AGENT_IDS[@]}"; do
    local status="${RED}OFFLINE${NC}"
    local pid_info=""
    local pid_file="$PID_DIR/${agent_id}.pid"

    if [ -f "$pid_file" ]; then
      local agent_pid
      agent_pid=$(cat "$pid_file")
      if kill -0 "$agent_pid" 2>/dev/null; then
        status="${GREEN}ONLINE${NC}"
        pid_info="PID ${agent_pid}"

        # Get memory usage if possible
        if command -v ps &>/dev/null; then
          local mem_kb
          mem_kb=$(ps -o rss= -p "$agent_pid" 2>/dev/null || echo "0")
          if [ "${mem_kb:-0}" -gt 0 ]; then
            local mem_mb=$((mem_kb / 1024))
            pid_info="${pid_info} · ${mem_mb}MB"
          fi
        fi

        online=$((online + 1))
      else
        offline=$((offline + 1))
      fi
    else
      offline=$((offline + 1))
    fi

    echo -e "  ${AGENT_COLORS[$agent_id]}$(printf '%-12s' "${AGENT_NAMES[$agent_id]}")${NC} ${DIM}$(printf '%-28s' "${AGENT_ROLES[$agent_id]}")${NC} $status  ${DIM}${pid_info}${NC}"
  done

  echo ""
  echo -e "  ${DIM}$(printf '%.0s─' {1..56})${NC}"
  echo -e "  ${WHITE}Online:${NC} ${GREEN}${online}${NC}  ${WHITE}Offline:${NC} ${RED}${offline}${NC}  ${WHITE}Total:${NC} 8"

  # Memory info
  echo ""
  echo -e "  ${WHITE}${BOLD}Memory & State${NC}"
  echo -e "  ${DIM}$(printf '%.0s─' {1..56})${NC}"

  if [ -f "$STATE_FILE" ]; then
    local saved_at
    saved_at=$(python3 -c "import json; print(json.load(open('${STATE_FILE}'))['saved_at'])" 2>/dev/null || echo "unknown")
    log_ok "Last state save: ${saved_at}"
  fi

  if [ -d "$MEMORY_DIR/snapshots" ]; then
    local snap_count
    snap_count=$(find "$MEMORY_DIR/snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    local snap_size
    snap_size=$(du -sh "$MEMORY_DIR/snapshots" 2>/dev/null | cut -f1 || echo "0")
    log_ok "Memory snapshots: ${snap_count} (${snap_size})"
  fi

  echo ""
}

# ──────────────────────────────────────────────────────────────────────────────
# BACKUP — Manual memory snapshot
# ──────────────────────────────────────────────────────────────────────────────

cmd_backup() {
  banner

  if [ -f "$SCRIPT_DIR/token_server.py" ] && [ ! -f "$INSTALL_DIR/token_server.py" ]; then
    INSTALL_DIR="$SCRIPT_DIR"
    LOG_DIR="$INSTALL_DIR/logs"
    PID_DIR="$INSTALL_DIR/.pids"
    MEMORY_DIR="$INSTALL_DIR/.memory"
    STATE_FILE="$MEMORY_DIR/cluster_state.json"
  fi

  ensure_dirs

  log_step "1/2" "Saving current state"
  save_cluster_state

  log_step "2/2" "Creating memory snapshot"
  save_memory_snapshot

  echo ""
  echo -e "  ${GREEN}Backup complete.${NC} Agents continue running undisturbed."
  echo ""
}

# ──────────────────────────────────────────────────────────────────────────────
# LOGS — Tail agent logs
# ──────────────────────────────────────────────────────────────────────────────

cmd_logs() {
  local target="${1:-all}"

  if [ -f "$SCRIPT_DIR/token_server.py" ] && [ ! -f "$INSTALL_DIR/token_server.py" ]; then
    INSTALL_DIR="$SCRIPT_DIR"
    LOG_DIR="$INSTALL_DIR/logs"
  fi

  if [ ! -d "$LOG_DIR" ]; then
    log_error "No logs directory found at $LOG_DIR"
    exit 1
  fi

  if [ "$target" = "all" ]; then
    echo -e "${DIM}Tailing all logs from ${LOG_DIR}/ — Ctrl+C to stop${NC}"
    echo ""
    tail -f "$LOG_DIR"/*.log 2>/dev/null || {
      log_error "No log files found"
      exit 1
    }
  elif [ "$target" = "server" ] || [ "$target" = "token-server" ]; then
    echo -e "${DIM}Tailing token server log — Ctrl+C to stop${NC}"
    tail -f "$LOG_DIR/token-server.log" 2>/dev/null || {
      log_error "Token server log not found"
      exit 1
    }
  else
    # Check if it's a valid agent name
    local found=false
    for agent_id in "${AGENT_IDS[@]}"; do
      if [ "$target" = "$agent_id" ] || [ "$target" = "${AGENT_NAMES[$agent_id]}" ]; then
        echo -e "${DIM}Tailing ${AGENT_NAMES[$agent_id]} log — Ctrl+C to stop${NC}"
        tail -f "$LOG_DIR/${agent_id}.log" 2>/dev/null || {
          log_error "Log not found for ${agent_id}"
          exit 1
        }
        found=true
        break
      fi
    done

    if [ "$found" = false ]; then
      log_error "Unknown agent: ${target}"
      echo -e "  ${DIM}Valid agents: ${AGENT_IDS[*]}${NC}"
      echo -e "  ${DIM}Or use: all, server${NC}"
      exit 1
    fi
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# UNINSTALL
# ──────────────────────────────────────────────────────────────────────────────

cmd_uninstall() {
  banner

  if [ -f "$SCRIPT_DIR/token_server.py" ] && [ ! -f "$INSTALL_DIR/token_server.py" ]; then
    INSTALL_DIR="$SCRIPT_DIR"
    PID_DIR="$INSTALL_DIR/.pids"
    MEMORY_DIR="$INSTALL_DIR/.memory"
  fi

  echo -e "  ${RED}${BOLD}WARNING: This will remove the OpenClaw installation.${NC}"
  echo -e "  ${WHITE}Directory: ${INSTALL_DIR}${NC}"
  echo ""

  # Check for running processes first
  local running=false
  if [ -d "$PID_DIR" ]; then
    for pid_file in "$PID_DIR"/*.pid; do
      [ -f "$pid_file" ] || continue
      local pid
      pid=$(cat "$pid_file")
      if kill -0 "$pid" 2>/dev/null; then
        running=true
        break
      fi
    done
  fi

  if [ "$running" = true ]; then
    log_warn "OpenClaw is currently running"
    read -rp "  Stop all services first? [Y/n] " confirm
    if [ "${confirm:-Y}" != "n" ] && [ "${confirm:-Y}" != "N" ]; then
      cmd_stop
    else
      log_error "Cannot uninstall while services are running"
      exit 1
    fi
  fi

  # Offer to save final backup
  read -rp "  Save final memory backup before removal? [Y/n] " backup_confirm
  if [ "${backup_confirm:-Y}" != "n" ] && [ "${backup_confirm:-Y}" != "N" ]; then
    local final_backup="$HOME/openclaw-final-backup-$(timestamp_file)"
    mkdir -p "$final_backup"
    if [ -d "$MEMORY_DIR" ]; then
      cp -r "$MEMORY_DIR" "$final_backup/"
      log_ok "Memory saved to ${final_backup}"
    fi
    if [ -d "$INSTALL_DIR/logs" ]; then
      cp -r "$INSTALL_DIR/logs" "$final_backup/"
      log_ok "Logs saved to ${final_backup}"
    fi
  fi

  read -rp "  Remove ${INSTALL_DIR}? This cannot be undone. [y/N] " remove_confirm
  if [ "${remove_confirm}" = "y" ] || [ "${remove_confirm}" = "Y" ]; then
    rm -rf "$INSTALL_DIR"
    log_ok "OpenClaw removed from ${INSTALL_DIR}"
  else
    log_info "Uninstall cancelled"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# HELP
# ──────────────────────────────────────────────────────────────────────────────

cmd_help() {
  banner
  echo -e "  ${WHITE}${BOLD}Commands${NC}"
  echo -e "  ${DIM}$(printf '%.0s─' {1..56})${NC}"
  echo ""
  echo -e "  ${GREEN}install${NC} [zip_path]    Unzip, create dirs, install deps, generate agents"
  echo -e "  ${GREEN}check${NC}                Health check: Python, uv, gateway, creds, ports"
  echo -e "  ${GREEN}start${NC}                Launch token server + all 8 agents"
  echo -e "  ${GREEN}stop${NC}                 Graceful shutdown with memory persistence"
  echo -e "  ${GREEN}restart${NC}              Stop + start (preserves memory)"
  echo -e "  ${GREEN}status${NC}               Show running services, PIDs, memory usage"
  echo -e "  ${GREEN}backup${NC}               Manual memory/state snapshot (no downtime)"
  echo -e "  ${GREEN}logs${NC} [agent|all]     Tail logs for specific agent or all"
  echo -e "  ${GREEN}uninstall${NC}            Remove everything (with backup option)"
  echo ""
  echo -e "  ${WHITE}${BOLD}Environment Variables${NC}"
  echo -e "  ${DIM}$(printf '%.0s─' {1..56})${NC}"
  echo ""
  echo -e "  ${CYAN}OPENCLAW_HOME${NC}          Install directory (default: ~/openclaw-voice)"
  echo -e "  ${CYAN}OPENCLAW_GATEWAY_HOST${NC}  Gateway host (default: 127.0.0.1)"
  echo -e "  ${CYAN}OPENCLAW_GATEWAY_PORT${NC}  Gateway port (default: 18789)"
  echo -e "  ${CYAN}TOKEN_SERVER_PORT${NC}      Frontend port (default: 8081)"
  echo ""
  echo -e "  ${WHITE}${BOLD}Memory Persistence${NC}"
  echo -e "  ${DIM}$(printf '%.0s─' {1..56})${NC}"
  echo ""
  echo -e "  Every ${GREEN}stop${NC} automatically saves:"
  echo -e "    • Agent runtime logs"
  echo -e "    • Conversation transcripts"
  echo -e "    • Cluster state (PIDs, uptime, config)"
  echo -e "    • Agent-local memory/history files"
  echo ""
  echo -e "  Snapshots are stored in ${CYAN}.memory/snapshots/${NC}"
  echo -e "  Last 20 snapshots are retained (older auto-rotated)"
  echo ""
  echo -e "  ${WHITE}${BOLD}Examples${NC}"
  echo -e "  ${DIM}$(printf '%.0s─' {1..56})${NC}"
  echo ""
  echo -e "  ${DIM}# Fresh install from zip${NC}"
  echo -e "  ./${SCRIPT_NAME} install openclaw-voice.zip"
  echo ""
  echo -e "  ${DIM}# Install in current directory (if sources exist here)${NC}"
  echo -e "  ./${SCRIPT_NAME} install"
  echo ""
  echo -e "  ${DIM}# Check everything, then start${NC}"
  echo -e "  ./${SCRIPT_NAME} check && ./${SCRIPT_NAME} start"
  echo ""
  echo -e "  ${DIM}# Graceful shutdown preserving all state${NC}"
  echo -e "  ./${SCRIPT_NAME} stop"
  echo ""
  echo -e "  ${DIM}# Watch Sentinel's logs${NC}"
  echo -e "  ./${SCRIPT_NAME} logs sentinel"
  echo ""
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN DISPATCHER
# ──────────────────────────────────────────────────────────────────────────────

main() {
  local command="${1:-help}"
  shift || true

  case "$command" in
    install)   cmd_install "$@" ;;
    check)     cmd_check "$@" ;;
    start)     cmd_start "$@" ;;
    stop)      cmd_stop "$@" ;;
    restart)   cmd_restart "$@" ;;
    status)    cmd_status "$@" ;;
    backup)    cmd_backup "$@" ;;
    logs)      cmd_logs "$@" ;;
    uninstall) cmd_uninstall "$@" ;;
    help|-h|--help) cmd_help ;;
    *)
      log_error "Unknown command: ${command}"
      echo -e "  Run ${GREEN}${SCRIPT_NAME} help${NC} for usage"
      exit 1
      ;;
  esac
}

main "$@"
