"""HTTP API of the game server.

  POST /v1/auth/guest   {"name": "..."}           -> {"account_id", "token", ...profile view}
  GET  /v1/me                                      -> profile view (finishes pushes, pays assist rewards)
  POST /v1/action       {"action": "...", "args": {...}} -> profile view + result
  GET  /v1/leaderboard                             -> top players, most hired heroes
  GET  /health                                     -> liveness

Auth: "Authorization: Bearer <token>" (guest token from /v1/auth/guest).
Profile view: {ok, error, result, reports, profile, pending, server_time}.
"""
from __future__ import annotations

import logging
import time
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from . import db
from .config import settings
from .game import GameError, GameService
from .worker import WorkerError, WorkerPool

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("server")


@asynccontextmanager
async def lifespan(app: FastAPI):
    await db.init_db(settings.database_url)
    pool = WorkerPool(settings.godot_bin, settings.project_dir, settings.workers, settings.worker_timeout)
    await pool.start()
    app.state.game = GameService(pool, settings)
    app.state.buckets = {}
    log.info("server ready: %d rules workers, db=%s", settings.workers, settings.database_url.split("@")[-1])
    yield
    await pool.stop()
    await db.close_db()


app = FastAPI(title="Async Hero RPG", version="0.1", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins, allow_methods=["*"], allow_headers=["*"])


@app.exception_handler(GameError)
async def game_error(_: Request, e: GameError):
    return JSONResponse(status_code=e.status, content={"ok": False, "error": e.message})


@app.exception_handler(WorkerError)
async def worker_error(_: Request, e: WorkerError):
    log.error("worker error: %s", e)
    return JSONResponse(status_code=503, content={"ok": False, "error": "rules worker unavailable"})


class GuestIn(BaseModel):
    name: str = Field(default="Герой", max_length=16)


class ActionIn(BaseModel):
    action: str = Field(max_length=32)
    args: dict = Field(default_factory=dict)


def game(request: Request) -> GameService:
    return request.app.state.game


async def current_account(request: Request, authorization: str = Header(default="")) -> str:
    if not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "missing token")
    acc = await game(request).account_by_token(authorization[7:].strip())
    if acc is None or acc.banned:
        raise HTTPException(401, "bad token")
    _rate_limit(request, acc.id)
    return acc.id


def _rate_limit(request: Request, account_id: str) -> None:
    """Token bucket per account (in-process; move to Redis when running several API instances)."""
    buckets = request.app.state.buckets
    now = time.monotonic()
    tokens, last = buckets.get(account_id, (float(settings.rate_burst), now))
    tokens = min(float(settings.rate_burst), tokens + (now - last) * settings.rate_per_sec)
    if tokens < 1.0:
        raise HTTPException(429, "too many requests")
    buckets[account_id] = (tokens - 1.0, now)


@app.get("/health")
async def health():
    return {"ok": True, "time": time.time()}


@app.post("/v1/auth/guest")
async def guest(body: GuestIn, request: Request):
    account_id, token, view = await game(request).create_guest(body.name)
    return {"account_id": account_id, "token": token, **view}


@app.get("/v1/me")
async def me(request: Request, account_id: str = Depends(current_account)):
    return await game(request).me(account_id)


@app.post("/v1/action")
async def action(body: ActionIn, request: Request, account_id: str = Depends(current_account)):
    return await game(request).action(account_id, body.action, body.args)


@app.get("/v1/leaderboard")
async def leaderboard(request: Request):
    return await game(request).leaderboard()
