#!/usr/bin/env python3
"""
OpenClaw Voice Token Server

FastAPI backend that:
- Serves the HTML frontend on GET /
- Returns agent list on GET /api/agents
- Generates LiveKit JWT tokens on POST /api/token
"""

import json
import os
import time
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from livekit import api
from pydantic import BaseModel

load_dotenv()

SCRIPT_DIR = Path(__file__).parent.resolve()
CONFIG_PATH = SCRIPT_DIR / "agents_config.json"
STATIC_DIR = SCRIPT_DIR / "static"

app = FastAPI(title="OpenClaw Voice Token Server", version="1.0.0")

# CORS middleware for development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def load_config() -> dict:
    with open(CONFIG_PATH, "r") as f:
        return json.load(f)


class TokenRequest(BaseModel):
    room_name: str
    agent_name: str
    participant_name: str


@app.get("/health")
async def health_check():
    """Health check endpoint for Docker/cloud monitoring."""
    return JSONResponse(content={"status": "ok", "service": "openclaw-voice"})


@app.get("/")
async def serve_frontend():
    """Serve the main HTML frontend."""
    index_path = STATIC_DIR / "index.html"
    if not index_path.exists():
        raise HTTPException(status_code=404, detail="Frontend not found")
    return FileResponse(index_path, media_type="text/html")


@app.get("/api/agents")
async def get_agents():
    """Return the list of configured agents."""
    try:
        config = load_config()
        return JSONResponse(content={
            "agents": config["agents"],
            "livekit_url": config["livekit_url"],
        })
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/token")
async def create_token(request: TokenRequest):
    """Generate a LiveKit JWT token for a participant."""
    api_key = os.getenv("LIVEKIT_API_KEY")
    api_secret = os.getenv("LIVEKIT_API_SECRET")
    livekit_url = os.getenv("LIVEKIT_URL")

    if not api_key or not api_secret:
        raise HTTPException(
            status_code=500,
            detail="LIVEKIT_API_KEY and LIVEKIT_API_SECRET must be set in environment",
        )

    if not livekit_url:
        try:
            config = load_config()
            livekit_url = config.get("livekit_url", "")
        except Exception:
            livekit_url = ""

    # Create access token with video grants and agent dispatch
    token = (
        api.AccessToken(api_key, api_secret)
        .with_identity(request.participant_name)
        .with_name(request.participant_name)
        .with_grants(
            api.VideoGrants(
                room_join=True,
                room=request.room_name,
            )
        )
        .with_room_config(
            api.RoomConfiguration(
                agents=[
                    api.RoomAgentDispatch(
                        agent_name=request.agent_name,
                    )
                ],
            ),
        )
    )

    jwt_token = token.to_jwt()

    return JSONResponse(content={
        "token": jwt_token,
        "url": livekit_url,
    })


# Mount static files (CSS, JS, images) after API routes
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("TOKEN_SERVER_PORT", "8081"))
    uvicorn.run(app, host="0.0.0.0", port=port)
