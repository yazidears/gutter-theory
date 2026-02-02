from __future__ import annotations

import asyncio
import random
import string
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Dict, Optional
from uuid import UUID, uuid4

from fastapi import WebSocket

from .models import PlayerState
from .utils import zone_key, zone_label


MAX_PLAYERS = 16
STALE_AFTER = timedelta(seconds=10)


@dataclass
class Player:
    id: UUID
    name: str
    lat: float
    lon: float
    heading: float
    zone_key: Optional[str]
    zone_label: Optional[str]
    last_seen: datetime

    def to_state(self) -> PlayerState:
        return PlayerState(
            id=self.id,
            name=self.name,
            lat=self.lat,
            lon=self.lon,
            heading=self.heading,
            zone_key=self.zone_key,
            zone_label=self.zone_label,
            last_seen=self.last_seen,
        )


@dataclass
class Lobby:
    id: UUID
    code: str
    name: str
    mode: str
    players: Dict[UUID, Player] = field(default_factory=dict)


class LobbyStore:
    def __init__(self) -> None:
        self._lobbies: Dict[str, Lobby] = {}
        self._lock = asyncio.Lock()

    async def create_lobby(self, name: str, mode: str, host_id: UUID, host_name: str) -> Lobby:
        async with self._lock:
            code = self._generate_code()
            lobby = Lobby(id=uuid4(), code=code, name=name, mode=mode)
            lobby.players[host_id] = Player(
                id=host_id,
                name=host_name,
                lat=0.0,
                lon=0.0,
                heading=0.0,
                zone_key=None,
                zone_label=None,
                last_seen=datetime.now(timezone.utc),
            )
            self._lobbies[code] = lobby
            return lobby

    async def get_lobby(self, code: str) -> Optional[Lobby]:
        async with self._lock:
            return self._lobbies.get(code)

    async def list_players(self, code: str) -> list[PlayerState]:
        async with self._lock:
            lobby = self._lobbies.get(code)
            if not lobby:
                return []
            self._prune_stale_locked(lobby)
            return [player.to_state() for player in lobby.players.values()]

    async def join_lobby(self, code: str, player_id: UUID, name: str) -> Optional[Lobby]:
        async with self._lock:
            lobby = self._lobbies.get(code)
            if not lobby:
                return None
            if len(lobby.players) >= MAX_PLAYERS:
                raise ValueError("lobby_full")
            lobby.players[player_id] = Player(
                id=player_id,
                name=name,
                lat=0.0,
                lon=0.0,
                heading=0.0,
                zone_key=None,
                zone_label=None,
                last_seen=datetime.now(timezone.utc),
            )
            return lobby

    async def leave_lobby(self, code: str, player_id: UUID) -> Optional[Lobby]:
        async with self._lock:
            lobby = self._lobbies.get(code)
            if not lobby:
                return None
            lobby.players.pop(player_id, None)
            return lobby

    async def upsert_presence(
        self,
        code: str,
        player_id: UUID,
        name: str,
        lat: float,
        lon: float,
        heading: float,
        zone_key_value: Optional[str],
        zone_label_value: Optional[str],
    ) -> Optional[PlayerState]:
        async with self._lock:
            lobby = self._lobbies.get(code)
            if not lobby:
                return None
            resolved_zone_key = zone_key_value or zone_key(lat, lon)
            resolved_zone_label = zone_label_value or zone_label(lat, lon)
            lobby.players[player_id] = Player(
                id=player_id,
                name=name,
                lat=lat,
                lon=lon,
                heading=heading,
                zone_key=resolved_zone_key,
                zone_label=resolved_zone_label,
                last_seen=datetime.now(timezone.utc),
            )
            self._prune_stale_locked(lobby)
            return lobby.players[player_id].to_state()

    def _generate_code(self) -> str:
        while True:
            code = "".join(random.choices(string.ascii_uppercase + string.digits, k=4))
            if code not in self._lobbies:
                return code

    def _prune_stale_locked(self, lobby: Lobby) -> None:
        now = datetime.now(timezone.utc)
        stale = [pid for pid, player in lobby.players.items() if now - player.last_seen > STALE_AFTER]
        for pid in stale:
            lobby.players.pop(pid, None)


class ConnectionManager:
    def __init__(self) -> None:
        self._connections: Dict[str, Dict[UUID, WebSocket]] = {}
        self._lock = asyncio.Lock()

    async def connect(self, code: str, player_id: UUID, socket: WebSocket) -> None:
        async with self._lock:
            room = self._connections.setdefault(code, {})
            room[player_id] = socket

    async def disconnect(self, code: str, player_id: UUID) -> None:
        async with self._lock:
            room = self._connections.get(code)
            if not room:
                return
            room.pop(player_id, None)

    async def broadcast(self, code: str, message: dict, exclude: Optional[UUID] = None) -> None:
        async with self._lock:
            room = dict(self._connections.get(code, {}))
        if not room:
            return
        for pid, socket in room.items():
            if exclude and pid == exclude:
                continue
            try:
                await socket.send_json(message)
            except Exception:
                pass

    async def send_to(self, code: str, player_id: UUID, message: dict) -> None:
        async with self._lock:
            socket = self._connections.get(code, {}).get(player_id)
        if not socket:
            return
        try:
            await socket.send_json(message)
        except Exception:
            return
