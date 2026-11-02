"""Analytics: what players do and which builds win, for balance changes at the end of a season.

Events (table `events`) are written by the server itself — it sees every action — plus a
small whitelist of client events (screens, session start). No names or e-mails: only the
account id. Kinds:

  action    every client action: {a, ok, lvl, cl, dg (gold change), dc (crystals change)}
  attempt   a push or Mythic+ run as it starts; the outcome is already in its timeline:
            {mode, level, won, waves, total, t, closed, party: [member...], gear: {slot: rarity}}
  farm      a farm run started: {level, party}
  report    a report shown to the player: {type, level, mode}
  level_up  hero level changed: {from, to}
  client    from the game client: {e: "screen" | "session" | ..., ...}

`report(...)` turns them into the season summary (see app/report_cli.py and /v1/admin/report).
"""
from __future__ import annotations

import statistics
import time
from collections import Counter, defaultdict

from sqlalchemy import delete, select

from . import db

CLIENT_EVENTS = {"session", "screen", "popup", "watch", "tutorial_skip"}
MAX_CLIENT_BATCH = 50


def member(snap: dict) -> dict:
    """Build of one party member, small enough to keep for every attempt."""
    out = {
        "hero": bool(snap.get("is_hero")),
        "npc": bool(snap.get("npc")),
        "spec": snap.get("spec", ""),
        "lvl": int(snap.get("level", 0) or 0),
        "w": list(snap.get("weapons", [])),
        "sp": [[s.get("id"), int(s.get("lvl", 1))] for s in snap.get("spells", [])],
        "tal": {k: int(v) for k, v in (snap.get("talents") or {}).items() if int(v) > 0},
        "fx": list(snap.get("effects", [])),
    }
    st = snap.get("stats") or {}
    out["hp"] = int(st.get("hp", 0) or 0)
    return out


def gear_rarity(p: dict) -> dict:
    return {slot: int(it["rarity"]) for slot, it in (p["hero"].get("equipped") or {}).items() if it}


def events_for(action: str | None, args: dict, before: dict, after: dict, result: dict, reports: list, now: float) -> list[dict]:
    """Analytics events of one request. `before` / `after` are the profile around it."""
    out: list[dict] = []
    dg = int(after.get("gold", 0)) - int(before.get("gold", 0))
    dc = int(after.get("crystals", 0)) - int(before.get("crystals", 0))
    if action is None and (dg or dc):
        # a plain refresh paid something (a finished push, hire rewards, season places)
        out.append({"kind": "action", "data": {"a": "tick", "ok": True, "lvl": int(after["hero"]["level"]),
                                               "cl": int(after.get("closed_level", 0)), "dg": dg, "dc": dc}})
    if action is not None:
        out.append({"kind": "action", "data": {
            "a": action, "ok": bool(result.get("ok", True)),
            "lvl": int(after["hero"]["level"]), "cl": int(after.get("closed_level", 0)),
            "dg": int(after.get("gold", 0)) - int(before.get("gold", 0)),
            "dc": int(after.get("crystals", 0)) - int(before.get("crystals", 0)),
            **({"step": args.get("step"), "hint": args.get("hint")} if action == "tutorial" else {}),
        }})
    if action == "start" and result.get("ok", True) and after.get("expedition"):
        ex = after["expedition"]
        party = [member(m) for m in ex.get("party", [])]
        if ex["mode"] in ("push", "mythic"):
            tl = ex["tl"]
            out.append({"kind": "attempt", "data": {
                "mode": ex["mode"], "level": int(ex["level"]), "won": bool(tl.get("won")),
                "waves": int(tl.get("waves", 0)), "total": int(tl.get("total", 0)), "t": float(tl.get("t_end", 0.0)),
                "closed": bool(tl.get("closed")), "party": party, "gear": gear_rarity(after)}})
        else:
            out.append({"kind": "farm", "data": {"level": int(ex["level"]), "party": party}})
    for r in reports:
        out.append({"kind": "report", "data": {"type": r.get("type"), "level": r.get("level"), "mode": r.get("mode")}})
    if int(after["hero"]["level"]) != int(before["hero"]["level"]):
        out.append({"kind": "level_up", "data": {"from": int(before["hero"]["level"]), "to": int(after["hero"]["level"])}})
    return out


def client_events(batch: list, now: float) -> list[dict]:
    """Whitelisted client events, clipped in size; times come from the server clock."""
    out = []
    for e in (batch or [])[:MAX_CLIENT_BATCH]:
        if not isinstance(e, dict) or e.get("e") not in CLIENT_EVENTS:
            continue
        data = {k: (v[:64] if isinstance(v, str) else v) for k, v in list(e.items())[:8]
                if isinstance(v, (str, int, float, bool))}
        out.append({"kind": "client", "data": data})
    return out


async def prune(keep_days: int) -> None:
    async with db.Session() as s, s.begin():
        await s.execute(delete(db.Event).where(db.Event.at < time.time() - keep_days * 86400))


# ---------------------------------------------------------------------- report

def _rate(won: int, n: int) -> float:
    return round(100.0 * won / n, 1) if n else 0.0


async def report(since_days: float = 90, now: float | None = None) -> dict:
    """Season summary: players, retention, progression, builds and economy."""
    now = now or time.time()
    since = now - since_days * 86400
    async with db.Session() as s:
        events = (await s.execute(select(db.Event).where(db.Event.at >= since).order_by(db.Event.at))).scalars().all()
        accounts = (await s.execute(select(db.Account.id, db.Account.created_at, db.Account.last_seen))).all()
        profiles = (await s.execute(select(db.Profile.account_id, db.Profile.data))).all()
        log = (await s.execute(select(db.ActionLog.account_id, db.ActionLog.action, db.ActionLog.gold_before,
                                      db.ActionLog.gold_after, db.ActionLog.at))).all()

    by_acc = defaultdict(list)
    for e in events:
        by_acc[e.account_id].append(e)

    # players and retention (days between creation and last activity)
    created = {a.id: a.created_at.timestamp() for a in accounts}
    last_act = {acc: evs[-1].at for acc, evs in by_acc.items()}
    retention = {}
    for d in (1, 7, 30):
        old = [a for a, c in created.items() if now - c >= d * 86400]
        back = [a for a in old if last_act.get(a, 0) - created[a] >= d * 86400]
        retention["d%d" % d] = {"cohort": len(old), "returned": len(back), "pct": _rate(len(back), len(old))}
    active = {d: sum(1 for t in last_act.values() if now - t < d * 86400) for d in (1, 7, 30)}

    # sessions: a gap of 30 minutes starts a new one
    lengths = []
    for evs in by_acc.values():
        start = prev = evs[0].at
        for e in evs[1:]:
            if e.at - prev > 1800:
                lengths.append(prev - start)
                start = e.at
            prev = e.at
        lengths.append(prev - start)

    # progression: attempts and wins per level, time from account creation to clearing it
    per_level = defaultdict(lambda: {"attempts": 0, "wins": 0, "players": set(), "first_clear_h": []})
    mythic = []
    spells = defaultdict(lambda: [0, 0])     # id -> [uses, wins] in pushes of heroes
    talents = defaultdict(lambda: [0, 0, 0])  # id -> [builds, wins, ranks]
    effects = defaultdict(lambda: [0, 0])
    weapons = defaultdict(lambda: [0, 0])
    specs = defaultdict(lambda: [0, 0])
    for acc, evs in by_acc.items():
        cleared = set()
        for e in evs:
            if e.kind != "attempt":
                continue
            d = e.data
            won = bool(d.get("won"))
            if d.get("mode") == "mythic":
                hero = next((m for m in d.get("party", []) if m.get("hero")), None)
                mythic.append({"key": d.get("level"), "won": won, "t": d.get("t"),
                               "build": "+".join(sorted(m.get("spec") or ("hero" if m.get("hero") else "merc") for m in d.get("party", []))),
                               "hero_w": "+".join(hero["w"]) if hero else ""})
                continue
            lv = per_level[int(d.get("level", 0))]
            lv["attempts"] += 1
            lv["wins"] += int(won)
            lv["players"].add(acc)
            if d.get("closed") and d.get("level") not in cleared and acc in created:
                cleared.add(d.get("level"))
                lv["first_clear_h"].append((e.at - created[acc]) / 3600.0)
            for m in d.get("party", []):
                if m.get("npc"):
                    specs[m.get("spec") or "hybrid"][0] += 1
                    specs[m.get("spec") or "hybrid"][1] += int(won)
                    continue
                if not m.get("hero"):
                    continue
                for sid, _lvl in m.get("sp", []):
                    spells[sid][0] += 1
                    spells[sid][1] += int(won)
                for tid, rank in m.get("tal", {}).items():
                    talents[tid][0] += 1
                    talents[tid][1] += int(won)
                    talents[tid][2] += int(rank)
                for fx in m.get("fx", []):
                    effects[fx][0] += 1
                    effects[fx][1] += int(won)
                key = "+".join(m.get("w", [])) or "без оружия"
                weapons[key][0] += 1
                weapons[key][1] += int(won)

    levels = []
    for lvl in sorted(per_level):
        v = per_level[lvl]
        levels.append({"level": lvl, "attempts": v["attempts"], "wins": v["wins"], "win_pct": _rate(v["wins"], v["attempts"]),
                       "players": len(v["players"]),
                       "median_hours_to_clear": round(statistics.median(v["first_clear_h"]), 1) if v["first_clear_h"] else None})

    def table(d: dict, extra: bool = False) -> list:
        rows = []
        for k, v in d.items():
            row = {"id": k, "uses": v[0], "wins": v[1], "win_pct": _rate(v[1], v[0])}
            if extra:
                row["avg_rank"] = round(v[2] / v[0], 2) if v[0] else 0
            rows.append(row)
        return sorted(rows, key=lambda r: -r["uses"])

    # tutorial funnel: highest step each player reached
    reached = Counter()
    skipped = 0
    for evs in by_acc.values():
        top = -1
        for e in evs:
            if e.kind == "action" and e.data.get("a") == "tutorial" and e.data.get("step") is not None:
                top = max(top, int(e.data["step"]))
            if e.kind == "client" and e.data.get("e") == "tutorial_skip":
                skipped += 1
        if top >= 0:
            reached[top] += 1
    funnel = [{"step": st, "players": sum(n for t, n in reached.items() if t >= st)} for st in range(0, 9)]

    # economy: gold in and out by action, crystals
    gold = defaultdict(lambda: [0, 0])
    crystals = 0
    for e in events:
        if e.kind == "action":
            dg = int(e.data.get("dg", 0))
            gold[e.data.get("a")][0 if dg >= 0 else 1] += abs(dg)
            crystals += int(e.data.get("dc", 0))
    economy = sorted(({"action": a, "gold_in": v[0], "gold_out": v[1]} for a, v in gold.items()), key=lambda r: -(r["gold_in"] + r["gold_out"]))

    # anomalies: gold per hour of activity far above everyone else, many rejected actions
    gold_rate = {}
    for acc, evs in by_acc.items():
        span = max(3600.0, evs[-1].at - evs[0].at)
        gained = sum(max(0, int(e.data.get("dg", 0))) for e in evs if e.kind == "action")
        gold_rate[acc] = gained / (span / 3600.0)
    rates = sorted(gold_rate.values())
    p90 = rates[int(len(rates) * 0.9)] if rates else 0
    rejected = Counter(e.account_id for e in events if e.kind == "action" and not e.data.get("ok", True))
    anomalies = [{"account": a, "gold_per_hour": round(r), "reason": "gold per hour > 3x the 90th percentile"}
                 for a, r in gold_rate.items() if p90 > 0 and r > 3 * p90]
    anomalies += [{"account": a, "rejected": n, "reason": "many actions rejected by the rules"} for a, n in rejected.items() if n >= 50]

    best_closed = Counter(int(p.get("closed_level", 0)) for _a, p in profiles)
    hero_levels = Counter(int(p["hero"]["level"]) for _a, p in profiles)
    return {
        "generated_at": now, "since_days": since_days,
        "players": {"accounts": len(accounts), "active_1d": active[1], "active_7d": active[7], "active_30d": active[30],
                    "sessions": len(lengths), "median_session_min": round(statistics.median(lengths) / 60.0, 1) if lengths else 0},
        "retention": retention,
        "closed_levels": dict(sorted(best_closed.items())),
        "hero_levels": dict(sorted(hero_levels.items())),
        "levels": levels,
        "spells": table(spells), "talents": table(talents, True), "accessories_and_effects": table(effects),
        "hero_weapons": table(weapons), "mercenary_specs": table(specs),
        "mythic": {"runs": len(mythic), "best_key": max((m["key"] for m in mythic if m["won"]), default=0),
                   "by_party": table({k: v for k, v in _group(mythic).items()})},
        "tutorial": {"funnel": funnel, "skipped": skipped},
        "economy": {"gold_by_action": economy, "crystals_net": crystals, "audit_log_rows": len(log)},
        "anomalies": anomalies,
    }


def _group(runs: list) -> dict:
    out = defaultdict(lambda: [0, 0])
    for m in runs:
        out[m["build"]][0] += 1
        out[m["build"]][1] += int(m["won"])
    return out


def render_html(r: dict) -> str:
    """The report as one page (tables), for a browser or a file."""
    import html

    def tbl(rows: list, cols: list, limit: int = 40) -> str:
        if not rows:
            return "<p class=muted>нет данных</p>"
        head = "".join("<th>%s</th>" % html.escape(c[1]) for c in cols)
        body = "".join("<tr>%s</tr>" % "".join("<td>%s</td>" % html.escape(str(row.get(c[0], ""))) for c in cols)
                       for row in rows[:limit])
        return "<table><tr>%s</tr>%s</table>" % (head, body)

    p = r["players"]
    ret = r["retention"]
    use = [("id", ""), ("uses", "раз"), ("wins", "побед"), ("win_pct", "% побед")]
    parts = [
        "<h1>Async Hero RPG — отчёт за %d дн.</h1>" % r["since_days"],
        "<p>Аккаунтов: <b>%d</b> · активны за день %d, неделю %d, месяц %d · сессий %d, медиана %s мин</p>" % (
            p["accounts"], p["active_1d"], p["active_7d"], p["active_30d"], p["sessions"], p["median_session_min"]),
        "<p>Удержание: день 1 — %s%% (%d из %d), день 7 — %s%% (%d из %d), день 30 — %s%% (%d из %d)</p>" % tuple(
            x for d in ("d1", "d7", "d30") for x in (ret[d]["pct"], ret[d]["returned"], ret[d]["cohort"])),
        "<h2>Уровни кампании</h2>", tbl(r["levels"], [("level", "уровень"), ("players", "игроков"), ("attempts", "штурмов"),
                                                    ("win_pct", "% побед"), ("median_hours_to_clear", "часов до прохождения (медиана)")], 60),
        "<h2>Заклинания героев</h2>", tbl(r["spells"], use),
        "<h2>Таланты</h2>", tbl(r["talents"], use + [("avg_rank", "средний ранг")]),
        "<h2>Аксессуары и эффекты</h2>", tbl(r["accessories_and_effects"], use),
        "<h2>Оружие героя</h2>", tbl(r["hero_weapons"], use),
        "<h2>Наёмники по профилю</h2>", tbl(r["mercenary_specs"], use),
        "<h2>Мифик+</h2><p>Забегов %d, лучший пройденный ключ +%d</p>" % (r["mythic"]["runs"], r["mythic"]["best_key"]),
        tbl(r["mythic"]["by_party"], [("id", "состав"), ("uses", "забегов"), ("win_pct", "% побед")]),
        "<h2>Обучение</h2><p>Пропустили: %d</p>" % r["tutorial"]["skipped"],
        tbl(r["tutorial"]["funnel"], [("step", "дошли до шага"), ("players", "игроков")]),
        "<h2>Экономика</h2><p>Кристаллы (чистый приток): %d</p>" % r["economy"]["crystals_net"],
        tbl(r["economy"]["gold_by_action"], [("action", "действие"), ("gold_in", "золото +"), ("gold_out", "золото −")]),
        "<h2>Подозрительное</h2>", tbl(r["anomalies"], [("account", "аккаунт"), ("reason", "причина"),
                                                      ("gold_per_hour", "золото/час"), ("rejected", "отказов")]),
    ]
    style = ("body{font:14px/1.45 system-ui,sans-serif;margin:24px;max-width:1100px;color:#1d2230}"
             "table{border-collapse:collapse;margin:8px 0 20px}td,th{border:1px solid #d5d9e2;padding:4px 10px;text-align:left}"
             "th{background:#eef1f6}.muted{color:#778}h2{margin-top:28px}")
    return "<!doctype html><meta charset=utf-8><title>Отчёт Async Hero</title><style>%s</style>%s" % (style, "".join(parts))
