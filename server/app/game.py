"""Game service: loads a profile, runs the shared rules in a worker, saves the result.

The server is the authority: the client sends intents (action + args), the
rules decide. Randomness lives in the profile's RNG, which never leaves the
server (stripped from responses).
"""
from __future__ import annotations

import asyncio
import datetime as dt
import secrets
import time
import weakref

from sqlalchemy import case, func, select, update

from . import db
from .config import Settings
from .worker import WorkerPool

LOCAL_ACTIONS = {"set_rotation", "move_party", "equip", "unequip", "sell", "hire", "fire", "replace", "fuse", "set_name",
                 "talent_up", "talent_reset", "set_threshold", "set_cosmetic", "switch_hero"}
AUTHORITY_ACTIONS = {"reroll", "open_box", "open_pack", "start", "collect", "stop",
                     "gather_start", "gather_claim", "gather_cancel", "craft_start", "craft_claim", "use_item",
                     "fake_purchase", "buy_cosmetic", "rush", "buy_boost", "upgrade_item", "buy_hero_slot", "create_hero"}
CLIENT_ACTIONS = LOCAL_ACTIONS | AUTHORITY_ACTIONS


class GameError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def today(now: float | None = None) -> str:
    return dt.datetime.fromtimestamp(now or time.time(), dt.timezone.utc).strftime("%Y-%m-%d")


def client_profile(p: dict) -> dict:
    """Profile as the client may see it (no RNG state: outcomes stay unpredictable)."""
    return {k: v for k, v in p.items() if k not in ("rng", "reports")}


class GameService:
    def __init__(self, pool: WorkerPool, settings: Settings):
        self.pool = pool
        self.s = settings
        self._locks: weakref.WeakValueDictionary[str, asyncio.Lock] = weakref.WeakValueDictionary()
        self.clock = time.time  # replaceable in tests

    def _lock(self, account_id: str) -> asyncio.Lock:
        lock = self._locks.get(account_id)
        if lock is None:
            lock = asyncio.Lock()
            self._locks[account_id] = lock
        return lock

    # ------------------------------------------------------------------ accounts

    async def create_guest(self, name: str) -> tuple[str, str, dict]:
        name = (name or "Герой").strip()[:16] or "Герой"
        account_id = secrets.token_hex(8)
        token = secrets.token_urlsafe(32)
        now = self.clock()
        async with db.Session() as s, s.begin():
            pool = await self._real_pool(s, account_id, 1)
            res = await self.pool.call("new_profile", seed=secrets.randbits(31), now=now, name=name,
                                       ctx={"account": account_id, "real_pool": pool})
            s.add(db.Account(id=account_id, name=name, token_hash=hash_token(token)))
            s.add(db.Profile(account_id=account_id, data=res["profile"], version=1))
            await self._upsert_snapshot(s, account_id, res)
        return account_id, token, self._view(res, {}, [], now)

    async def account_by_token(self, token: str) -> db.Account | None:
        async with db.Session() as s, s.begin():
            acc = (await s.execute(select(db.Account).where(db.Account.token_hash == hash_token(token)))).scalar_one_or_none()
            if acc is not None:
                acc.last_seen = db.utcnow()
            return acc

    # ------------------------------------------------------------------ game

    async def me(self, account_id: str) -> dict:
        return await self._run(account_id, None, {})

    async def action(self, account_id: str, action: str, args: dict) -> dict:
        if action not in CLIENT_ACTIONS:
            raise GameError(400, "unknown action")
        if action == "fake_purchase" and not self.s.allow_fake_purchases:
            raise GameError(403, "test purchases are disabled")
        return await self._run(account_id, action, args or {})

    async def _run(self, account_id: str, action: str | None, args: dict) -> dict:
        now = self.clock()
        async with self._lock(account_id):
            async with db.Session() as s, s.begin():
                row = await s.get(db.Profile, account_id, with_for_update=True)
                if row is None:
                    raise GameError(404, "no profile")
                p = row.data
                gold_before = int(p.get("gold", 0))
                level = int(p["hero"]["level"])
                need_pool = action is None or action in AUTHORITY_ACTIONS
                ctx = {"account": account_id,
                       "real_pool": await self._real_pool(s, account_id, level) if need_pool else []}
                p = await self._claim_assists(s, account_id, p, now)
                if action is None:
                    res = await self.pool.call("tick", profile=p, now=now, ctx=ctx)
                else:
                    res = await self.pool.call("apply", profile=p, action=action, args=args, now=now, ctx=ctx)
                if not res.get("ok"):
                    raise GameError(400, res.get("error", "rejected"))
                result = res.get("result") or {}
                p = res["profile"]
                reports = list(p.get("reports", [])) + list(res["tick"].get("reports", []))
                p["reports"] = []
                assists = list(result.pop("assists", []) or []) + list(res["tick"].get("assists", []) or [])
                hires = []
                if action in ("hire", "replace") and result.get("ok"):
                    new_id = args.get("id") if action == "hire" else args.get("new")
                    if isinstance(new_id, str) and new_id.startswith("p"):
                        hires.append(new_id[1:])
                await self._record_assists(s, account_id, assists, hires, now)
                row.data = p
                row.version = row.version + 1
                await self._upsert_snapshot(s, account_id, res)
                if action == "set_name" and result.get("ok"):
                    await s.execute(update(db.Account).where(db.Account.id == account_id).values(name=p["name"]))
                if action in AUTHORITY_ACTIONS or reports:
                    s.add(db.ActionLog(account_id=account_id, action=action or "tick", ok=bool(result.get("ok", True)),
                                       gold_before=gold_before, gold_after=int(p.get("gold", 0)),
                                       info={"args": args, "reports": [r.get("type") for r in reports]}))
        return self._view(res, result, reports, now)

    def _view(self, res: dict, result: dict, reports: list, now: float) -> dict:
        return {
            "ok": bool(result.get("ok", True)),
            "error": result.get("error"),
            "result": result,
            "reports": reports,
            "profile": client_profile(res["profile"]),
            "pending": res.get("pending"),
            "server_time": now,
        }

    # ------------------------------------------------------------------ mercenaries

    async def _real_pool(self, s, account_id: str, level: int) -> list[dict]:
        """Snapshots of other players near this level; least hired today first (exposure balancing)."""
        cutoff = db.utcnow() - dt.timedelta(days=self.s.snapshot_max_age_days)
        r = self.s.pool_level_range
        day = today(self.clock())
        hired_today = case((db.Snapshot.hires_day == day, db.Snapshot.hires_today), else_=0)
        q = (select(db.Snapshot.data)
             .where(db.Snapshot.account_id != account_id,
                    db.Snapshot.level.between(level - r, level + r),
                    db.Snapshot.updated_at >= cutoff)
             .order_by(hired_today, func.random())
             .limit(self.s.pool_size))
        return [row[0] for row in (await s.execute(q)).all()]

    async def _upsert_snapshot(self, s, account_id: str, res: dict) -> None:
        snap = res["snapshot"]
        row = await s.get(db.Snapshot, account_id)
        if row is None:
            row = db.Snapshot(account_id=account_id, hires_total=0, hires_today=0, hires_day="", assist_gold_total=0)
            s.add(row)
        row.name = str(snap.get("name", ""))[:32]
        row.level = int(res["hero_level"])
        row.closed_level = int(res["closed_level"])
        row.power = int(snap.get("power", 0))
        row.role = str(snap.get("role", ""))
        row.data = snap
        row.updated_at = db.utcnow()

    async def _record_assists(self, s, hirer_id: str, assists: list[dict], hire_owners: list[str], now: float) -> None:
        """Owners of hired heroes get 5% of the gold (system-created, not taken from the hirer),
        limited per owner per day and per owner/hirer pair (anti account-farming)."""
        day = today(now)
        events: dict[str, dict] = {}
        for a in assists:
            owner = str(a.get("owner", ""))
            if owner and owner != hirer_id:
                events.setdefault(owner, {"gold": 0, "hires": 0})["gold"] += max(0, int(a.get("gold", 0)))
        for owner in hire_owners:
            if owner and owner != hirer_id:
                events.setdefault(owner, {"gold": 0, "hires": 0})["hires"] += 1
        for owner, ev in events.items():
            pair = (await s.execute(select(func.count()).select_from(db.Assist).where(
                db.Assist.owner_id == owner, db.Assist.hirer_id == hirer_id, db.Assist.day == day))).scalar_one()
            if pair >= self.s.assist_pair_daily_events:
                continue
            got = (await s.execute(select(func.coalesce(func.sum(db.Assist.gold), 0)).where(
                db.Assist.owner_id == owner, db.Assist.day == day))).scalar_one()
            gold = max(0, min(ev["gold"], self.s.assist_daily_gold_cap - int(got)))
            if gold == 0 and ev["hires"] == 0:
                continue
            s.add(db.Assist(owner_id=owner, hirer_id=hirer_id, gold=gold, hires=ev["hires"], day=day))
            snap = await s.get(db.Snapshot, owner)
            if snap is not None:
                if snap.hires_day != day:
                    snap.hires_day = day
                    snap.hires_today = 0
                snap.hires_today += ev["hires"]
                snap.hires_total += ev["hires"]
                snap.assist_gold_total += gold

    async def _claim_assists(self, s, account_id: str, p: dict, now: float) -> dict:
        rows = (await s.execute(select(db.Assist).where(db.Assist.owner_id == account_id, db.Assist.claimed.is_(False))
                                .with_for_update())).scalars().all()
        gold = sum(r.gold for r in rows)
        hires = sum(r.hires for r in rows)
        if not rows:
            return p
        for r in rows:
            r.claimed = True
        if gold <= 0 and hires <= 0:
            return p
        res = await self.pool.call("apply", profile=p, action="grant_assists", args={"gold": gold, "hires": hires},
                                   now=now, internal=True, ctx={"account": account_id})
        return res["profile"] if res.get("ok") else p

    # ------------------------------------------------------------------ public info

    async def leaderboard(self) -> dict:
        async with db.Session() as s:
            top = (await s.execute(select(db.Snapshot.name, db.Snapshot.closed_level, db.Snapshot.level, db.Snapshot.power)
                                   .order_by(db.Snapshot.closed_level.desc(), db.Snapshot.level.desc(), db.Snapshot.power.desc())
                                   .limit(20))).all()
            hired = (await s.execute(select(db.Snapshot.name, db.Snapshot.hires_total, db.Snapshot.role)
                                     .where(db.Snapshot.hires_total > 0)
                                     .order_by(db.Snapshot.hires_total.desc()).limit(10))).all()
            players = (await s.execute(select(func.count()).select_from(db.Account))).scalar_one()
        return {
            "players": players,
            "campaign": [{"name": n, "closed_level": c, "level": l, "power": pw} for n, c, l, pw in top],
            "most_hired": [{"name": n, "hires": h, "role": r} for n, h, r in hired],
        }


def hash_token(token: str) -> str:
    import hashlib
    return hashlib.sha256(token.encode()).hexdigest()
