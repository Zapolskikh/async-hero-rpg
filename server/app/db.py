"""Database schema (SQLAlchemy 2, async). PostgreSQL in production, SQLite for quick local runs.

Tables
  accounts   - guest accounts (token stored as sha256)
  profiles   - full game profile as JSON (server is the source of truth)
  snapshots  - public copy of each hero for other players' mercenary boards
  assists    - rewards owed to owners of hired heroes (5% of gold), claimed on next login
  action_log - audit trail of authority actions (concept 12: anti-exploit)
  mythic_records - best Mythic+ key per account and season (leaderboard)
  season_rewards - places granted when a season closes, paid into the profile on next login
  sessions   - extra device tokens of an account (login by e-mail, transfer code, Google)
  credentials - ways to log in: e-mail + password hash, Google / Apple subject
  transfer_codes - one-time codes to move an account to another device
"""
from __future__ import annotations

import datetime as dt

from sqlalchemy import JSON, BigInteger, Boolean, DateTime, Float, Index, Integer, String, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.asyncio import AsyncEngine, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

JsonType = JSON().with_variant(JSONB(), "postgresql")


def utcnow() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


class Base(DeclarativeBase):
    pass


class Account(Base):
    __tablename__ = "accounts"
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    name: Mapped[str] = mapped_column(String(32))
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    last_seen: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    banned: Mapped[bool] = mapped_column(Boolean, default=False)


class Profile(Base):
    __tablename__ = "profiles"
    account_id: Mapped[str] = mapped_column(String(32), primary_key=True)
    data: Mapped[dict] = mapped_column(JsonType)
    version: Mapped[int] = mapped_column(Integer, default=1)
    updated_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)


class Snapshot(Base):
    __tablename__ = "snapshots"
    account_id: Mapped[str] = mapped_column(String(32), primary_key=True)
    name: Mapped[str] = mapped_column(String(32))
    level: Mapped[int] = mapped_column(Integer, index=True)
    closed_level: Mapped[int] = mapped_column(Integer, default=0)
    power: Mapped[int] = mapped_column(Integer, default=0)
    role: Mapped[str] = mapped_column(String(32), default="")
    data: Mapped[dict] = mapped_column(JsonType)
    updated_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)
    hires_total: Mapped[int] = mapped_column(Integer, default=0)
    hires_day: Mapped[str] = mapped_column(String(10), default="")
    hires_today: Mapped[int] = mapped_column(Integer, default=0)
    assist_gold_total: Mapped[int] = mapped_column(BigInteger, default=0)


class Assist(Base):
    __tablename__ = "assists"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    owner_id: Mapped[str] = mapped_column(String(32), index=True)
    hirer_id: Mapped[str] = mapped_column(String(32))
    gold: Mapped[int] = mapped_column(Integer, default=0)
    hires: Mapped[int] = mapped_column(Integer, default=0)
    day: Mapped[str] = mapped_column(String(10), index=True)
    claimed: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    __table_args__ = (Index("ix_assists_pair_day", "owner_id", "hirer_id", "day"),)


class ActionLog(Base):
    __tablename__ = "action_log"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    account_id: Mapped[str] = mapped_column(String(32), index=True)
    action: Mapped[str] = mapped_column(String(32))
    ok: Mapped[bool] = mapped_column(Boolean)
    gold_before: Mapped[int] = mapped_column(BigInteger, default=0)
    gold_after: Mapped[int] = mapped_column(BigInteger, default=0)
    info: Mapped[dict] = mapped_column(JsonType, default=dict)
    at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class MythicRecord(Base):
    __tablename__ = "mythic_records"
    season: Mapped[int] = mapped_column(Integer, primary_key=True)
    account_id: Mapped[str] = mapped_column(String(32), primary_key=True)
    name: Mapped[str] = mapped_column(String(32), default="")
    level: Mapped[int] = mapped_column(Integer, default=0)
    time: Mapped[float] = mapped_column(Float, default=0.0)   # battle seconds of the best clear
    updated_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    __table_args__ = (Index("ix_mythic_rank", "season", "level", "time"),)


class SeasonReward(Base):
    __tablename__ = "season_rewards"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    season: Mapped[int] = mapped_column(Integer, index=True)
    account_id: Mapped[str] = mapped_column(String(32), index=True)
    rank: Mapped[int] = mapped_column(Integer)
    claimed: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    __table_args__ = (UniqueConstraint("season", "account_id", name="uq_season_reward"),)


class DeviceSession(Base):
    __tablename__ = "sessions"
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    account_id: Mapped[str] = mapped_column(String(32), index=True)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    last_seen: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Credential(Base):
    __tablename__ = "credentials"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    account_id: Mapped[str] = mapped_column(String(32), index=True)
    kind: Mapped[str] = mapped_column(String(16))          # email | google | apple
    subject: Mapped[str] = mapped_column(String(320))      # lower-case e-mail or provider user id
    secret: Mapped[str] = mapped_column(String(256), default="")   # password hash for e-mail
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    __table_args__ = (UniqueConstraint("kind", "subject", name="uq_credential"),
                      UniqueConstraint("account_id", "kind", name="uq_credential_kind"))


class TransferCode(Base):
    __tablename__ = "transfer_codes"
    code_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    account_id: Mapped[str] = mapped_column(String(32), index=True)
    expires_at: Mapped[float] = mapped_column(Float)
    used: Mapped[bool] = mapped_column(Boolean, default=False)


engine: AsyncEngine | None = None
Session: async_sessionmaker | None = None


async def init_db(url: str) -> None:
    global engine, Session
    kwargs = {}
    if url.startswith("postgresql"):
        kwargs = {"pool_size": 10, "max_overflow": 20, "pool_pre_ping": True}
    engine = create_async_engine(url, **kwargs)
    Session = async_sessionmaker(engine, expire_on_commit=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def close_db() -> None:
    if engine is not None:
        await engine.dispose()
