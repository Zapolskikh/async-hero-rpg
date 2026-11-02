"""End-to-end API tests: real Godot rules workers + real database."""
import concurrent.futures as cf
import time

T0 = time.time()


def set_clock(client, offset):
    client.app.state.game.clock = lambda: T0 + offset


def guest(client, name):
    r = client.post("/v1/auth/guest", json={"name": name})
    assert r.status_code == 200, r.text
    d = r.json()
    return d, {"Authorization": "Bearer " + d["token"]}


def act(client, h, action, **args):
    r = client.post("/v1/action", json={"action": action, "args": args}, headers=h)
    assert r.status_code in (200, 400), r.text
    return r.json()


def test_guest_and_auth(client):
    set_clock(client, 0)
    d, h = guest(client, "Олег")
    p = d["profile"]
    assert len(p["board"]) == 6 and len(p["hired"]) == 3
    assert "rng" not in p, "RNG state must stay on the server"
    assert client.get("/v1/me").status_code == 401
    assert client.get("/v1/me", headers={"Authorization": "Bearer nope"}).status_code == 401
    assert client.get("/v1/me", headers=h).json()["profile"]["name"] == "Олег"


def test_client_build_check(client):
    from app.config import settings
    set_clock(client, 0)
    d, h = guest(client, "Сборка")
    old = settings.game_build
    settings.game_build = "abc1234"
    try:
        assert client.get("/v1/me", headers={**h, "X-Client-Build": "abc1234"}).status_code == 200
        r = client.get("/v1/me", headers={**h, "X-Client-Build": "0000000"})
        assert r.status_code == 426 and r.json()["build"] == "abc1234", "a client of another build must update"
        assert client.get("/v1/me", headers=h).status_code == 200, "clients without a build header pass"
        assert client.get("/health").json()["build"] == "abc1234"
    finally:
        settings.game_build = old


def test_fake_purchases_can_be_disabled(client):
    from app.config import settings
    set_clock(client, 0)
    d, h = guest(client, "Магазин")
    old = settings.allow_fake_purchases
    settings.allow_fake_purchases = False
    try:
        r = client.post("/v1/action", json={"action": "fake_purchase", "args": {"pack": "small"}}, headers=h)
        assert r.status_code == 403
    finally:
        settings.allow_fake_purchases = old


def test_account_linking(client):
    set_clock(client, 0)
    d, h = guest(client, "Связка")
    info = client.get("/v1/account", headers=h).json()
    assert info["guest"] and info["linked"]["email"] is None and info["providers"]["google"] is False
    r = client.post("/v1/account/email", json={"email": "Oleg@Example.com", "password": "short"}, headers=h)
    assert r.status_code == 400, "passwords need 8+ characters"
    r = client.post("/v1/account/email", json={"email": "Oleg@Example.com", "password": "correct horse"}, headers=h)
    assert r.status_code == 200 and r.json()["linked"]["email"] == "o***@example.com"
    other, h2 = guest(client, "Другой")
    r = client.post("/v1/account/email", json={"email": "oleg@example.com", "password": "another one"}, headers=h2)
    assert r.status_code == 409, "an e-mail belongs to one account"
    assert client.post("/v1/auth/login", json={"email": "oleg@example.com", "password": "wrong pass"}).status_code == 401
    r = client.post("/v1/auth/login", json={"email": " OLEG@example.com ", "password": "correct horse"})
    assert r.status_code == 200 and r.json()["account_id"] == d["account_id"]
    h_new = {"Authorization": "Bearer " + r.json()["token"]}
    assert client.get("/v1/me", headers=h_new).json()["profile"]["name"] == "Связка", "a second device opens the same profile"
    # transfer code: one use, then gone
    code = client.post("/v1/account/transfer-code", headers=h2).json()["code"]
    r = client.post("/v1/auth/transfer", json={"code": code.lower()})
    assert r.status_code == 200 and r.json()["account_id"] == other["account_id"]
    assert client.post("/v1/auth/transfer", json={"code": code}).status_code == 404, "a code works once"
    # password change logs other devices out, this one stays
    r = client.post("/v1/account/password", json={"old": "correct horse", "new": "battery staple"}, headers=h_new)
    assert r.status_code == 200
    assert client.get("/v1/me", headers=h_new).status_code == 200
    assert client.get("/v1/me", headers=h).status_code == 401, "the old guest token stops working"
    assert client.post("/v1/auth/login", json={"email": "oleg@example.com", "password": "battery staple"}).status_code == 200
    # Google is off until GOOGLE_CLIENT_ID is set
    r = client.post("/v1/auth/provider", json={"provider": "google", "id_token": "x"})
    assert r.status_code == 501
    assert client.post("/v1/auth/logout", headers=h_new).json()["ok"]
    assert client.get("/v1/me", headers=h_new).status_code == 401


def test_login_attempts_are_limited(client):
    for i in range(8):
        client.post("/v1/auth/login", json={"email": "nobody@example.com", "password": "guess %d" % i})
    r = client.post("/v1/auth/login", json={"email": "nobody@example.com", "password": "guess 9"})
    assert r.status_code == 429


def test_validation(client):
    set_clock(client, 0)
    d, h = guest(client, "Валидатор")
    full = act(client, h, "hire", id=d["profile"]["board"][0]["id"])
    assert full["ok"] is False and full["error"] == "group full"
    assert act(client, h, "open_pack", use="gold")["ok"] is False  # 100 gold < 1350
    r = client.post("/v1/action", json={"action": "grant_assists", "args": {"gold": 999999}}, headers=h)
    assert r.status_code == 400, "internal actions are not callable by clients"
    assert act(client, h, "start", level=5, mode="push")["ok"] is False


def test_character_appearance(client):
    set_clock(client, 0)
    _, headers = guest(client, "Внешность")
    result = act(client, headers, "set_appearance", sex="female", hair="f05")
    assert result["ok"], result
    saved = client.get("/v1/me", headers=headers).json()["profile"]["hero"]["appearance"]
    assert saved == {"sex": "female", "hair": "f05"}
    assert act(client, headers, "set_appearance", sex="female", hair="m01")["ok"] is False
    assert client.get("/v1/me", headers=headers).json()["profile"]["hero"]["appearance"] == saved


def test_push_farm_and_assists(client):
    set_clock(client, 0)
    owner, ho = guest(client, "Владелец")
    hirer, hh = guest(client, "Наниматель")
    # hirer rerolls until the owner's hero shows up on the board (same level 1)
    found = None
    for i in range(40):   # the pool is a random pick among all level 1 players of the test run
        res = act(client, hh, "reroll")
        assert res["ok"], res
        ids = [m["id"] for m in res["profile"]["board"]]
        if "p" + owner["account_id"] in ids:
            found = "p" + owner["account_id"]
            break
        set_clock(client, 86400 * (i + 1))  # next day: reroll price resets
    assert found, "real player appears on the board"
    board_ids = [m["id"] for m in res["profile"]["board"]]
    assert "p" + hirer["account_id"] not in board_ids, "never yourself"
    old = res["profile"]["hired"][1]["id"]  # the archer: the party keeps its tank and healer
    assert act(client, hh, "replace", old=old, new=found)["ok"]
    # push level 1
    base = 86400 * 45   # after any reroll day above
    set_clock(client, base)
    for attempt in range(5):  # a random party can lose level 1 now and then
        set_clock(client, base)
        st = act(client, hh, "start", level=1, mode="push")
        assert st["ok"], st
        t_end = st["profile"]["expedition"]["tl"]["t_end"]
        set_clock(client, base + t_end + 1)
        me = client.get("/v1/me", headers=hh).json()
        assert any(r["type"] == "push_end" for r in me["reports"]), me["reports"]
        if me["profile"]["closed_level"] == 1:
            break
        base += int(t_end) + 2
    assert me["profile"]["closed_level"] == 1
    # farm and collect -> owner earns 5% (if the owner is still hired after the board refresh)
    assert act(client, hh, "start", level=1, mode="farm")["ok"]
    set_clock(client, base + t_end + 1 + 1800)
    col = act(client, hh, "collect")
    assert col["ok"] and col["result"]["report"]["gold"] > 0
    om = client.get("/v1/me", headers=ho).json()
    types = [r["type"] for r in om["reports"]]
    assert "assists" in types, om["reports"]
    rep = [r for r in om["reports"] if r["type"] == "assists"][0]
    assert rep["hires"] >= 1 and rep["gold"] > 0
    assert om["profile"]["stats"]["hired_total"] >= 1
    again = client.get("/v1/me", headers=ho).json()
    assert not any(r["type"] == "assists" for r in again["reports"]), "assists are paid once"
    lb = client.get("/v1/leaderboard").json()
    assert lb["players"] >= 2 and any(x["name"] == "Владелец" for x in lb["most_hired"])


def test_concurrent_requests_are_serialized(client):
    set_clock(client, 0)
    d, h = guest(client, "Спешащий")
    order = d["profile"]["party_order"]

    def move(_):
        return act(client, h, "move_party", index=0, dir=1)

    with cf.ThreadPoolExecutor(8) as ex:
        results = list(ex.map(move, range(10)))
    assert all(r["ok"] for r in results)
    final = client.get("/v1/me", headers=h).json()["profile"]["party_order"]
    # 10 swaps of positions 0 and 1 -> back to the start
    assert final == order


def test_boxes_are_server_random(client):
    set_clock(client, 0)
    d, h = guest(client, "Удачливый")
    r = act(client, h, "open_box", use="free")
    assert r["ok"] and len(r["result"]["boxes"]) == 1
    assert act(client, h, "open_box", use="free")["ok"] is False


def test_professions_are_server_timed(client):
    set_clock(client, 0)
    d, h = guest(client, "Травник")
    # gathering: timestamps come from the server clock, not the client
    r = act(client, h, "gather_start", prof="herbalism", loc="green_meadow", sec=3600)
    assert r["ok"], r
    g = r["profile"]["gathering"]
    assert g["ends_at"] - g["started_at"] == 3600
    assert act(client, h, "gather_start", prof="mining", loc="abandoned_quarry", sec=900)["ok"] is False
    set_clock(client, 1800)
    early = act(client, h, "gather_claim")
    assert early["ok"] is False and early["error"] == "not finished"
    set_clock(client, 3601)
    got = act(client, h, "gather_claim")
    assert got["ok"], got
    res = got["profile"]["resources"]
    assert res.get("greenleaf", 0) >= 4 and res.get("bitterroot", 0) >= 2
    assert got["profile"]["professions"]["herbalism"]["xp"] > 0
    again = act(client, h, "gather_claim")
    assert again["ok"] is False and again["error"] == "nothing to claim"
    assert again["profile"]["resources"] == res, "a double claim must not pay twice"
    # crafting runs next to gathering and the AFK farm
    assert act(client, h, "gather_start", prof="mining", loc="abandoned_quarry", sec=900)["ok"]
    assert act(client, h, "craft_start", recipe="minor_strength_potion")["error"] == "not your craft"
    assert act(client, h, "prof_choose", prof="alchemy")["ok"]
    c = act(client, h, "craft_start", recipe="minor_strength_potion")
    assert c["ok"], c
    p = c["profile"]
    assert p["resources"]["greenleaf"] == res["greenleaf"] - 4
    assert act(client, h, "craft_claim", prof="alchemy")["error"] == "not finished"
    set_clock(client, 3601 + 181)
    done = act(client, h, "craft_claim", prof="alchemy")
    assert done["ok"], done
    assert done["profile"]["resources"]["minor_strength_potion"] == 2
    assert act(client, h, "craft_claim", prof="alchemy")["error"] == "nothing to claim"
    used = act(client, h, "use_item", res="minor_strength_potion")
    assert used["ok"], used
    assert used["profile"]["buffs"], "buff must be active"
    # state survives a reload from the database
    me = client.get("/v1/me", headers=h).json()["profile"]
    assert me["resources"]["minor_strength_potion"] == 1
    assert me["gathering"]["loc"] == "abandoned_quarry"


def _edit_profile(account_id, fn):
    """Changes a stored profile directly (test setup only)."""
    import asyncio
    import copy
    import os
    from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
    from app import db

    async def run():
        eng = create_async_engine(os.environ["DATABASE_URL"])
        async with async_sessionmaker(eng)() as s, s.begin():
            row = await s.get(db.Profile, account_id)
            data = copy.deepcopy(row.data)   # a new object, so the JSON column is saved
            fn(data)
            row.data = data
        await eng.dispose()
    asyncio.run(run())


def test_mythic_season(client):
    set_clock(client, 0)
    d, h = guest(client, "Мификер")
    st = act(client, h, "start", mode="mythic")
    assert not st["ok"] and "30" in st["error"], "Mythic+ opens at hero level 30"

    def level_30(p):
        p["hero"]["level"] = 30
        p["resources"] = dict(p["resources"], mythic_key=2)
    _edit_profile(d["account_id"], level_30)
    st = act(client, h, "start", mode="mythic")
    assert st["ok"], st
    ex = st["profile"]["expedition"]
    assert ex["mode"] == "mythic" and ex["level"] == 1 and st["profile"]["resources"]["mythic_key"] == 1
    set_clock(client, ex["tl"]["t_end"] + 1)
    me = client.get("/v1/me", headers=h).json()
    assert any(r["type"] == "mythic_end" for r in me["reports"]), me["reports"]

    def record(p):
        p["mythic"].update(best=4, best_time=321.5, level=5)
    _edit_profile(d["account_id"], record)
    client.get("/v1/me", headers=h)
    lb = client.get("/v1/leaderboard").json()
    assert lb["season"] >= 1 and {"name": "Мификер", "level": 4, "time": 321.5} in lb["mythic"], lb["mythic"]

    from app.config import settings
    settings.admin_token = "secret"
    assert client.post("/v1/admin/season/close", json={"season": lb["season"]}).status_code == 403
    r = client.post("/v1/admin/season/close", json={"season": lb["season"]}, headers={"X-Admin-Token": "secret"})
    assert r.status_code == 200 and r.json()["rewarded"] >= 1, r.text
    again = client.post("/v1/admin/season/close", json={"season": lb["season"]}, headers={"X-Admin-Token": "secret"})
    assert again.status_code == 409, "a season is paid once"
    crystals = me["profile"]["crystals"]
    me = client.get("/v1/me", headers=h).json()
    rewards = [x for x in me["reports"] if x["type"] == "season_reward"]
    assert rewards and rewards[0]["rank"] >= 1 and me["profile"]["crystals"] > crystals, me["reports"]
    assert not any(x["type"] == "season_reward" for x in client.get("/v1/me", headers=h).json()["reports"])
