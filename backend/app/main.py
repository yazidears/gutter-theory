from __future__ import annotations

from datetime import datetime, timezone
import os
from typing import Optional
from uuid import UUID

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect

from .models import (
    ErrorPayload,
    JoinRequest,
    JoinResponse,
    LeaveRequest,
    LobbyCreateRequest,
    LobbyCreateResponse,
    LobbyState,
    PresencePayload,
    ShotPayload,
)
from .state import ConnectionManager, LobbyStore
from .discovery import start_discovery, stop_discovery
from .utils import bearing_deg, haversine_m, heading_delta

app = FastAPI(title="GutterTheory Backend", version="0.1.0")
store = LobbyStore()
manager = ConnectionManager()
_discovery_handle = None


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "time": datetime.now(timezone.utc).isoformat()}


@app.on_event("startup")
async def on_startup() -> None:
    global _discovery_handle
    port = int(os.environ.get("PORT", "8000"))
    _discovery_handle = start_discovery(port)


@app.on_event("shutdown")
async def on_shutdown() -> None:
    global _discovery_handle
    stop_discovery(_discovery_handle)
    _discovery_handle = None


@app.post("/v1/lobbies", response_model=LobbyCreateResponse)
async def create_lobby(payload: LobbyCreateRequest) -> LobbyCreateResponse:
    lobby = await store.create_lobby(payload.name, payload.mode, payload.host_id, payload.host_name)
    return LobbyCreateResponse(lobby_id=lobby.id, code=lobby.code, name=lobby.name, mode=lobby.mode)


@app.post("/v1/lobbies/{code}/join", response_model=JoinResponse)
async def join_lobby(code: str, payload: JoinRequest) -> JoinResponse:
    try:
        lobby = await store.join_lobby(code, payload.player_id, payload.name)
    except ValueError as exc:
        if str(exc) == "lobby_full":
            raise HTTPException(status_code=409, detail="Lobby full")
        raise
    if lobby is None:
        raise HTTPException(status_code=404, detail="Lobby not found")
    await manager.broadcast(
        code,
        {"type": "join", "payload": {"player_id": str(payload.player_id), "name": payload.name}},
    )
    return JoinResponse(lobby_id=lobby.id, code=lobby.code, name=lobby.name, mode=lobby.mode)


@app.post("/v1/lobbies/{code}/leave")
async def leave_lobby(code: str, payload: LeaveRequest) -> dict:
    lobby = await store.leave_lobby(code, payload.player_id)
    if lobby is None:
        raise HTTPException(status_code=404, detail="Lobby not found")
    await manager.broadcast(
        code,
        {"type": "leave", "payload": {"player_id": str(payload.player_id)}},
    )
    return {"ok": True}


@app.get("/v1/lobbies/{code}", response_model=LobbyState)
async def lobby_state(code: str) -> LobbyState:
    lobby = await store.get_lobby(code)
    if lobby is None:
        raise HTTPException(status_code=404, detail="Lobby not found")
    players = await store.list_players(code)
    return LobbyState(
        lobby_id=lobby.id,
        code=lobby.code,
        name=lobby.name,
        mode=lobby.mode,
        players=players,
    )


@app.websocket("/v1/ws/{code}")
async def websocket_endpoint(websocket: WebSocket, code: str, player_id: str, name: str) -> None:
    await websocket.accept()
    try:
        player_uuid = UUID(player_id)
    except ValueError:
        await websocket.send_json({"type": "error", "payload": ErrorPayload(message="bad_player_id").model_dump()})
        await websocket.close(code=1008)
        return

    lobby = await store.get_lobby(code)
    if lobby is None:
        await websocket.send_json({"type": "error", "payload": ErrorPayload(message="lobby_not_found").model_dump()})
        await websocket.close(code=1008)
        return

    await manager.connect(code, player_uuid, websocket)
    await manager.broadcast(code, {"type": "join", "payload": {"player_id": player_id, "name": name}}, exclude=player_uuid)
    players = await store.list_players(code)
    await manager.send_to(
        code,
        player_uuid,
        {
            "type": "state",
            "payload": {"players": [player.model_dump() for player in players]},
        },
    )

    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type")
            payload = data.get("payload", {})

            if msg_type == "presence":
                presence = PresencePayload.model_validate(payload)
                updated = await store.upsert_presence(
                    code,
                    presence.player_id,
                    presence.name,
                    presence.lat,
                    presence.lon,
                    presence.heading,
                    presence.zone_key,
                    presence.zone_label,
                )
                if updated:
                    await manager.broadcast(
                        code,
                        {"type": "presence", "payload": updated.model_dump()},
                        exclude=None,
                    )

            elif msg_type == "shot":
                shot = ShotPayload.model_validate(payload)
                players = await store.list_players(code)
                shooter = next((p for p in players if p.id == shot.from_id), None)
                if not shooter:
                    await manager.send_to(
                        code,
                        player_uuid,
                        {"type": "error", "payload": ErrorPayload(message="shooter_not_found").model_dump()},
                    )
                    continue
                hit = _resolve_hit(shooter, players, shot.heading, shot.range_m, shot.target_id)
                await manager.broadcast(
                    code,
                    {
                        "type": "shot",
                        "payload": {
                            "from_id": str(shot.from_id),
                            "heading": shot.heading,
                            "range_m": shot.range_m,
                            "ts": shot.ts.isoformat(),
                        },
                    },
                )
                if hit:
                    await manager.broadcast(
                        code,
                        {
                            "type": "hit",
                            "payload": {
                                "from_id": str(shot.from_id),
                                "to_id": str(hit[0]),
                                "distance_m": hit[1],
                                "ts": datetime.now(timezone.utc).isoformat(),
                            },
                        },
                    )

            elif msg_type == "ping":
                await manager.send_to(
                    code,
                    player_uuid,
                    {"type": "pong", "payload": {"ts": datetime.now(timezone.utc).isoformat()}},
                )

            else:
                await manager.send_to(
                    code,
                    player_uuid,
                    {"type": "error", "payload": ErrorPayload(message="unknown_message_type").model_dump()},
                )

    except WebSocketDisconnect:
        await manager.disconnect(code, player_uuid)
        await store.leave_lobby(code, player_uuid)
        await manager.broadcast(code, {"type": "leave", "payload": {"player_id": player_id}})
    except Exception:
        await manager.disconnect(code, player_uuid)


def _resolve_hit(
    shooter,
    players,
    heading: float,
    range_m: float,
    target_id: Optional[UUID],
) -> Optional[tuple[UUID, float]]:
    lock_angle = 18
    candidates = []
    for player in players:
        if player.id == shooter.id:
            continue
        if target_id and player.id != target_id:
            continue
        distance = haversine_m(shooter.lat, shooter.lon, player.lat, player.lon)
        if distance > range_m:
            continue
        bearing = bearing_deg(shooter.lat, shooter.lon, player.lat, player.lon)
        if heading_delta(heading, bearing) <= lock_angle:
            candidates.append((player.id, distance))
    if not candidates:
        return None
    candidates.sort(key=lambda item: item[1])
    return candidates[0]
