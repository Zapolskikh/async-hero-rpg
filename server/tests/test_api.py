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


def test_validation(client):
    set_clock(client, 0)
    d, h = guest(client, "Валидатор")
    full = act(client, h, "hire", id=d["profile"]["board"][0]["id"])
    assert full["ok"] is False and full["error"] == "group full"
    assert act(client, h, "open_pack", use="gold")["ok"] is False  # 100 gold < 1350
    r = client.post("/v1/action", json={"action": "grant_assists", "args": {"gold": 999999}}, headers=h)
    assert r.status_code == 400, "internal actions are not callable by clients"
    assert act(client, h, "start", level=5, mode="push")["ok"] is False


def test_push_farm_and_assists(client):
    set_clock(client, 0)
    owner, ho = guest(client, "Владелец")
    hirer, hh = guest(client, "Наниматель")
    # hirer rerolls until the owner's hero shows up on the board (same level 1)
    found = None
    for i in range(5):
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
    old = res["profile"]["hired"][2]["id"]
    assert act(client, hh, "replace", old=old, new=found)["ok"]
    # push level 1
    base = 86400 * 6
    set_clock(client, base)
    st = act(client, hh, "start", level=1, mode="push")
    assert st["ok"], st
    t_end = st["profile"]["expedition"]["tl"]["t_end"]
    set_clock(client, base + t_end + 1)
    me = client.get("/v1/me", headers=hh).json()
    assert any(r["type"] == "push_end" for r in me["reports"]), me["reports"]
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
