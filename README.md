# OpenClaw 3D Voice Agent Network

8 specialized AI voice agents with Three.js 3D avatars, ARKit viseme lip sync, and self-hosted LiveKit — deployed to Oracle Cloud for **unlimited free streaming**.

## Architecture

```
┌─────────────────┐     ┌──────────┐     ┌──────────────────┐
│  Browser Client  │────▶│  Caddy   │────▶│  Token Server     │
│  (3D Avatars)    │     │  (SSL)   │     │  (FastAPI :8081)  │
└─────────────────┘     └────┬─────┘     └──────────────────┘
                             │
                             ▼
                      ┌──────────────┐     ┌──────────────┐
                      │  LiveKit SFU  │────▶│    Redis      │
                      │  (self-host)  │     │              │
                      └──────┬───────┘     └──────────────┘
                             │
               ┌─────────────┼─────────────┐
               ▼             ▼             ▼
          ┌─────────┐  ┌─────────┐  ┌─────────┐
          │Sentinel │  │ Oracle  │  │  ...x6  │
          │ Agent   │  │ Agent   │  │ Agents  │
          └─────────┘  └─────────┘  └─────────┘
                             │
                             ▼
                      ┌──────────────┐
                      │  OpenClaw    │
                      │  Gateway     │
                      └──────────────┘
```

**All services run inside Docker on a single Oracle Cloud ARM64 VM (4 OCPU, 24 GB RAM) — free forever.**

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

## Deploy to Oracle Cloud (Free Tier)

### 1. Create Oracle Cloud VM

1. Sign up at [oracle.com/cloud/free](https://www.oracle.com/cloud/free/)
2. Create a VM instance:
   - Shape: **VM.Standard.A1.Flex** (ARM)
   - OCPUs: **4**, Memory: **24 GB**
   - Image: **Ubuntu 22.04** (aarch64)
   - Add your SSH public key
3. Note the **public IP** of your instance

### 2. Configure DNS

Add two A records pointing to your VM's public IP:

```
voice.yourdomain.com      → YOUR_VM_IP
livekit.yourdomain.com    → YOUR_VM_IP
```

### 3. Open Ports in Oracle Cloud Console

Go to: **VCN → Subnet → Security List → Add Ingress Rules**

| Port | Protocol | Purpose |
|------|----------|---------|
| 80 | TCP | Let's Encrypt SSL |
| 443 | TCP + UDP | HTTPS + HTTP/3 |
| 7881 | TCP | WebRTC TCP fallback |
| 3478 | UDP | TURN UDP |
| 5349 | TCP | TURN TLS |
| 50000-60000 | UDP | WebRTC media |

### 4. SSH in and run setup

```bash
ssh ubuntu@YOUR_VM_IP
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/appdevwk/Voice-Agent/openclaw-3d/setup-oracle-cloud.sh)"
```

Or manually:

```bash
ssh ubuntu@YOUR_VM_IP
git clone https://github.com/appdevwk/Voice-Agent.git
cd Voice-Agent
git checkout openclaw-3d
sudo bash setup-oracle-cloud.sh
```

The script installs Docker, configures the firewall, and prompts for your domain and credentials.

### 5. Deploy

```bash
cd ~/Voice-Agent
docker compose up --build -d
```

Open **https://voice.yourdomain.com** — your 3D avatars are live.

## Management

```bash
# Status
docker compose ps

# Logs
docker compose logs -f
docker compose logs -f sentinel   # specific agent

# Restart
docker compose restart

# Stop
docker compose down

# Update
git pull origin openclaw-3d
docker compose up --build -d
```

## Local Development

For local testing without SSL (not recommended for production):

```bash
cp .env.example .env
# Edit .env — set DOMAIN=localhost, NODE_IP=127.0.0.1
docker compose up --build -d
```

Or use the install script directly:

```bash
chmod +x 3d-avatar-installclaw.sh
./3d-avatar-installclaw.sh install
./3d-avatar-installclaw.sh start
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DOMAIN` | Primary domain for SSL | — |
| `ACME_EMAIL` | Email for Let's Encrypt | — |
| `NODE_IP` | Server public IP (WebRTC ICE) | — |
| `LIVEKIT_API_KEY` | LiveKit API key | — |
| `LIVEKIT_API_SECRET` | LiveKit API secret | — |
| `TOKEN_SERVER_PORT` | Frontend server port | `8081` |

## 3D Frontend Features

- **Three.js WebGL** rendering with bloom post-processing
- **ReadyPlayer.me GLTF** avatar loading (with procedural wireframe fallback)
- **ARKit viseme lip sync** — 14 viseme blend shapes driven by Web Audio FFT
- **Idle animations** — blinking, breathing, head sway, eye micro-look
- **Per-agent visual differentiation** — unique lighting, particles, and colors
- **Mobile responsive** with touch support

## Why Self-Host?

| | LiveKit Cloud (Free) | Self-Hosted (Oracle Free) |
|---|---|---|
| Agent minutes | 1,000/month (hard cap) | **Unlimited** |
| WebRTC minutes | 5,000/month | **Unlimited** |
| Concurrent agents | 5 | **Unlimited** |
| Agent deployments | 1 | **8 (all of them)** |
| Monthly cost | $0 (with limits) | **$0 (no limits)** |

## License

See [LICENSE](LICENSE).
