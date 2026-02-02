from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional
from uuid import UUID

from pydantic import BaseModel, Field


class LobbyCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=40)
    mode: str = Field(min_length=1, max_length=40)
    host_id: UUID
    host_name: str = Field(min_length=1, max_length=32)


class LobbyCreateResponse(BaseModel):
    lobby_id: UUID
    code: str
    name: str
    mode: str


class JoinRequest(BaseModel):
    player_id: UUID
    name: str = Field(min_length=1, max_length=32)


class JoinResponse(BaseModel):
    lobby_id: UUID
    code: str
    name: str
    mode: str


class LeaveRequest(BaseModel):
    player_id: UUID


class PlayerState(BaseModel):
    id: UUID
    name: str
    lat: float
    lon: float
    heading: float
    zone_key: Optional[str] = None
    zone_label: Optional[str] = None
    last_seen: datetime


class LobbyState(BaseModel):
    lobby_id: UUID
    code: str
    name: str
    mode: str
    players: list[PlayerState]


class PresencePayload(BaseModel):
    player_id: UUID
    name: str
    lat: float
    lon: float
    heading: float
    zone_key: Optional[str] = None
    zone_label: Optional[str] = None
    ts: datetime


class ShotPayload(BaseModel):
    from_id: UUID
    heading: float
    range_m: float = 40
    target_id: Optional[UUID] = None
    ts: datetime


class HitPayload(BaseModel):
    from_id: UUID
    to_id: UUID
    distance_m: float
    ts: datetime


class ErrorPayload(BaseModel):
    message: str
    code: str = "bad_request"


class ServerEvent(BaseModel):
    type: Literal[
        "state",
        "presence",
        "join",
        "leave",
        "shot",
        "hit",
        "error",
        "pong",
    ]
    payload: dict
