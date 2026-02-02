"""Shim module that forwards to the real backend FastAPI app."""

from backend.app.main import app

__all__ = ["app"]
