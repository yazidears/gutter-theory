# GutterTheory Backend

Real-time FastAPI backend for lobbies, presence, and laser-tag hit validation.

## Run locally

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -e .
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Endpoints

- `GET /health`
- `POST /v1/lobbies`
- `POST /v1/lobbies/{code}/join`
- `POST /v1/lobbies/{code}/leave`
- `GET /v1/lobbies/{code}`
- `WS /v1/ws/{code}?player_id=...&name=...`

## Message types

WebSocket events include `state`, `presence`, `join`, `leave`, `shot`, `hit`, `pong`, `error`.
