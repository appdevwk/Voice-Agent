# OpenClaw 3D Voice Agent Network

8 specialized AI voice agents with Three.js 3D avatars, ARKit viseme lip sync, and LiveKit WebRTC — deployed to the cloud so your local machine stays free.

![LiveKit](./.github/assets/livekit-mark.png)

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Browser Client  │────▶│  Token Server     │────▶│  LiveKit Cloud   │
│  (3D Avatars)    │     │  (FastAPI :8081)  │     │  (Lexi-Claw)    │
└─────────────────┘     └──────────────────┘     └────────┬────────┘
                                                          │
                              ┌────────────────────────────┤
                              ▼                            ▼
                        ┌──────────┐              ┌──────────────┐
                        │ 8 Voice  │──────────────▶│  OpenClaw     │
                        │ Agents   │              │  Gateway      │
                        └──────────┘              └──────────────┘
```

## Agents

| Agent | Role | Voice | Color |
|-------|------|-------|-------|
| Sentinel | OSINT Intelligence Analyst | Charon | `#00ff88` |
| Oracle | Data Pattern Analyst | Kore | `#ff6b35` |
| Phantom | Network Recon Specialist | Puck | `#8b5cf6` |
| Cipher | Crypto & Comms Analyst | Ara | `#06b6d4` |
| Aegis | Defensive Security Coordinator | Zephyr | `#eab308` |
| Nexus | Multi-Source Intel Aggregator | Charon | `#ec4899` |
| Specter | Dark Web Monitor | Puck | `#64748b` |
| Vanguard | Mission Commander | Ara | `#dc2626` |

## Quick Start (Cloud / Docker)

### 1. Clone & configure

```bash
git clone https://github.com/appdevwk/Voice-Agent.git
cd Voice-Agent
git checkout openclaw-3d

cp .env.example .env
# Edit .env with your LiveKit credentials
```

### 2. Deploy with Docker Compose

```bash
docker compose up --build -d
```

Frontend: `http://<your-server>:8081`

### 3. Management

```bash
# View logs
docker compose logs -f

# Status
docker compose ps

# Stop (memory persisted in Docker volume)
docker compose down

# Restart
docker compose up -d
```

## Quick Start (Local — Install Script)

For local deployment (requires sufficient RAM for 8 agents):

```bash
chmod +x 3d-avatar-installclaw.sh
./3d-avatar-installclaw.sh install
./3d-avatar-installclaw.sh start
```

See `./3d-avatar-installclaw.sh help` for all commands.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LIVEKIT_URL` | LiveKit Cloud WebSocket URL | — |
| `LIVEKIT_API_KEY` | LiveKit API key | — |
| `LIVEKIT_API_SECRET` | LiveKit API secret | — |
| `TOKEN_SERVER_PORT` | Frontend server port | `8081` |
| `OPENCLAW_GATEWAY_HOST` | OpenClaw gateway host | `127.0.0.1` |
| `OPENCLAW_GATEWAY_PORT` | OpenClaw gateway port | `18789` |

## 3D Frontend Features

- **Three.js WebGL** rendering with bloom post-processing
- **ReadyPlayer.me GLTF** avatar loading (with procedural wireframe fallback)
- **ARKit viseme lip sync** — 14 viseme blend shapes driven by Web Audio FFT
- **Idle animations** — blinking, breathing, head sway, eye micro-look
- **Per-agent visual differentiation** — unique lighting, particles, and colors
- **Mobile responsive** with touch support

## Tech Stack

- **Frontend**: Three.js v0.162.0, Web Audio API, LiveKit Client SDK
- **Backend**: FastAPI (Python), LiveKit Server SDK
- **Agents**: Python LiveKit Agents with OpenClaw gateway
- **Deployment**: Docker Compose, LiveKit Cloud (Lexi-Claw)

## License

See [LICENSE](LICENSE).
