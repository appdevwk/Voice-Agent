#!/bin/bash
# ============================================
# OpenClaw Voice Agents — Start All
# ============================================
# Starts the token server + all 8 voice agents
# 
# Prerequisites:
#   1. pip install -r requirements.txt
#   2. Each agent: cd agents/<name> && uv sync
#   3. Set LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET in .env
#
# Usage:
#   chmod +x start_all_agents.sh
#   ./start_all_agents.sh
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS_DIR="$SCRIPT_DIR/agents"
LOG_DIR="$SCRIPT_DIR/logs"

# Load environment
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
fi
if [ -f "$SCRIPT_DIR/.env.local" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env.local" | xargs)
fi

# Create log directory
mkdir -p "$LOG_DIR"

echo "============================================"
echo " OpenClaw Voice Agent Network"
echo "============================================"
echo ""

# Check for required env vars
if [ -z "$LIVEKIT_URL" ] || [ -z "$LIVEKIT_API_KEY" ] || [ -z "$LIVEKIT_API_SECRET" ]; then
    echo "ERROR: Missing LiveKit credentials."
    echo "Set LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET in .env or .env.local"
    exit 1
fi

echo "LiveKit URL: $LIVEKIT_URL"
echo ""

# Cleanup function
PIDS=()
cleanup() {
    echo ""
    echo "Shutting down all agents..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null
    echo "All agents stopped."
}
trap cleanup EXIT INT TERM

# Start token server
echo "[1/9] Starting token server on port 8080..."
cd "$SCRIPT_DIR"
python token_server.py > "$LOG_DIR/token-server.log" 2>&1 &
PIDS+=($!)
sleep 2

echo "  Token server: http://localhost:8080"
echo ""

# Start each agent
AGENT_NUM=2
for AGENT_DIR in "$AGENTS_DIR"/*/; do
    if [ ! -f "$AGENT_DIR/src/agent.py" ]; then
        continue
    fi
    
    AGENT_NAME=$(basename "$AGENT_DIR")
    echo "[$AGENT_NUM/9] Starting agent: $AGENT_NAME..."
    
    cd "$AGENT_DIR"
    
    # Copy .env.local if it doesn't exist
    if [ ! -f ".env.local" ]; then
        cat > .env.local << EOF
LIVEKIT_URL=$LIVEKIT_URL
LIVEKIT_API_KEY=$LIVEKIT_API_KEY
LIVEKIT_API_SECRET=$LIVEKIT_API_SECRET
EOF
    fi
    
    # Start agent in dev mode
    if command -v uv &> /dev/null; then
        uv run python src/agent.py dev > "$LOG_DIR/$AGENT_NAME.log" 2>&1 &
    else
        python src/agent.py dev > "$LOG_DIR/$AGENT_NAME.log" 2>&1 &
    fi
    PIDS+=($!)
    
    AGENT_NUM=$((AGENT_NUM + 1))
done

echo ""
echo "============================================"
echo " All agents running!"
echo "============================================"
echo ""
echo " Frontend:  http://localhost:8080"
echo " Logs:      $LOG_DIR/"
echo ""
echo " Agents:"
for AGENT_DIR in "$AGENTS_DIR"/*/; do
    AGENT_NAME=$(basename "$AGENT_DIR")
    echo "   - $AGENT_NAME"
done
echo ""
echo " Press Ctrl+C to stop all agents"
echo ""

# Wait for all background processes
wait
