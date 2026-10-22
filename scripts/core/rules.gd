class_name Rules
extends RefCounted
## All game rules as pure functions over a JSON-safe profile Dictionary.
## The same code runs in the client (offline mode, prediction) and on the
## server (Godot headless worker), so client and server never disagree.
##
##   apply(p, action, args, now, ctx) -> {ok, error, ...}   mutates p
##   tick(p, now, ctx)                -> {reports, assists}  finishes pushes
##   pending(p, now)                  -> rewards earned but not collected yet
##
## `now` is unix time in seconds. Randomness comes from p["rng"] (seed + state),
## so a server keeps it secret by stripping it before sending the profile.
## `ctx` (server only): {"account": id, "real_pool": [public snapshots of other players]}

const VERSION := 3
const OFFLINE_CAP := 12.0 * 3600.0
const BOX_PRICE := 150
const BOX_PACK := 10
const BOX_PACK_PRICE := 1350
const REROLL_BASE := 20
const REROLL_GROWTH := 1.5
const MAX_HIRED := 3
const FUSE_COUNT := 5
const ASSIST_SHARE := 0.05       # owner of a hired real character gets 5% of the gold (concept 8.1)
const MAX_ITEMS_PER_COLLECT := 30
const REAL_SLOTS := 3            # up to 3 of 6 board places go to real players

## Actions without randomness: the client may apply them locally right away.
const LOCAL_ACTIONS := ["set_rotation", "move_party", "equip", "unequip", "sell", "hire", "fire", "replace", "fuse", "set_name"]
## Actions with randomness or rewards: only the authority (server or offline client) runs them.
const AUTHORITY_ACTIONS := ["reroll", "open_box", "open_pack", "start", "collect", "stop",
	"gather_start", "gather_claim", "gather_cancel", "craft_start", "craft_claim", "use_item"]
## Server-internal actions, never accepted from a client.
const INTERNAL_ACTIONS := ["grant_assists"]

# =====================================================================
# Profile lifecycle
# =====================================================================

static func new_profile(seed_value: int, now: float, name: String = "Герой") -> Dictionary:
	var p := {
		"v": VERSION, "name": name, "created": now,
		"gold": 100, "boxes": 1, "closed_level": 0,
		"hero": {"name": name, "level": 1, "xp": 0, "rotation": ["fireball", "strike", "kick"],
			"equipped": _empty_equipment()},
		"collection": {}, "inventory": [], "board": [], "hired": [], "party_order": [],
		"rerolls_today": 0, "reroll_day": "", "free_box_day": "",
		"expedition": null, "reports": [], "stats": {"hired_total": 0, "assist_gold_total": 0},
		"resources": {}, "professions": _fresh_professions(), "gathering": null, "crafting": {}, "buffs": {},
		"rng": {"seed": str(seed_value), "state": ""},
	}
	var r := _rng(p)
	for sid in Db.STARTER_SPELLS:
		p["collection"][sid] = {"1": 1}
	p["board"] = Roster.roll_board(r, 1)
	_auto_party(p)
	p["board"] = Roster.roll_board(r, 1)
	_save_rng(p, r)
	return p

## Brings any older or JSON-parsed profile to the current shape (ints restored).
static func migrate(p: Dictionary, now: float) -> void:
	if not p.has("rng"):
		p["rng"] = {"seed": str(randi()), "state": ""}
	for k in ["gold", "boxes", "closed_level", "rerolls_today"]:
		p[k] = int(p.get(k, 0))
	for k in ["reroll_day", "free_box_day"]:
		p[k] = str(p.get(k, ""))
	if not p.has("name"):
		p["name"] = str(p["hero"].get("name", "Герой"))
	if not p.has("reports"):
		p["reports"] = []
	if not p.has("stats"):
		p["stats"] = {"hired_total": 0, "assist_gold_total": 0}
	if not p.has("hired"):
		p["hired"] = []
	_migrate_professions(p)
	var hero: Dictionary = p["hero"]
	hero["level"] = int(hero["level"])
	hero["xp"] = int(hero["xp"])
	for slot in hero["equipped"]:
		_fix_item(hero["equipped"][slot])
	for it in p["inventory"]:
		_fix_item(it)
	for m in p["board"] + p["hired"]:
		Roster.ensure_merc(m)
	# v1 expedition (live object state) -> restart as a timeline from the save time
	var ex = p.get("expedition")
	if ex != null and typeof(ex) == TYPE_DICTIONARY and not ex.has("tl"):
		p["gold"] += int(ex.get("gold", 0))
		var party: Array = ex["party"]
		for m in party:
			if m.get("npc", false):
				Roster.ensure_merc(m)
			else:
				Roster.ensure_visuals(m)
		var started: float = float(p.get("time", now))
		p["expedition"] = _make_expedition(int(ex["level"]), str(ex["mode"]), party, int(ex["seed"]), bool(ex["first"]), started)
	elif ex != null and typeof(ex) == TYPE_DICTIONARY:
		_fix_expedition(ex)
	p.erase("time")
	p.erase("v")
	p["v"] = VERSION

static func _empty_equipment() -> Dictionary:
	var e := {}
	for slot in Loot.ALL_SLOTS:
		e[slot] = null
	return e

static func _fresh_professions() -> Dictionary:
	var d := {}
	for id in Prof.PROFESSIONS:
		d[id] = {"level": 1, "xp": 0}
	return d

## v3: professions, resources, crafting, buffs, more equipment slots, materials in timelines.
static func _migrate_professions(p: Dictionary) -> void:
	for slot in Loot.ALL_SLOTS:
		if not p["hero"]["equipped"].has(slot):
			p["hero"]["equipped"][slot] = null
	if typeof(p.get("resources")) != TYPE_DICTIONARY:
		p["resources"] = {}
	for res in p["resources"].keys():
		p["resources"][res] = int(p["resources"][res])
	if typeof(p.get("professions")) != TYPE_DICTIONARY:
		p["professions"] = {}
	for id in Prof.PROFESSIONS:
		if not p["professions"].has(id):
			p["professions"][id] = {"level": 1, "xp": 0}
		p["professions"][id]["level"] = int(p["professions"][id]["level"])
		p["professions"][id]["xp"] = int(p["professions"][id]["xp"])
	if not p.has("gathering"):
		p["gathering"] = null
	if p["gathering"] != null:
		p["gathering"]["sec"] = int(p["gathering"]["sec"])
	if typeof(p.get("crafting")) != TYPE_DICTIONARY:
		p["crafting"] = {}
	if typeof(p.get("buffs")) != TYPE_DICTIONARY:
		p["buffs"] = {}
	if p["buffs"].has("gather_yield"):
		p["buffs"]["gather_yield"]["charges"] = int(p["buffs"]["gather_yield"]["charges"])

static func _fix_point(pt: Array) -> void:
	for i in range(1, min(pt.size(), Expedition.P_MATS)):
		pt[i] = int(pt[i])
	if pt.size() <= Expedition.P_MATS:
		pt.append({})
	var m: Dictionary = pt[Expedition.P_MATS]
	for res in m.keys():
		m[res] = int(m[res])

static func _fix_item(it) -> void:
	if it == null:
		return
	it["rarity"] = int(it["rarity"])
	it["ilvl"] = int(it["ilvl"])

static func _fix_expedition(ex: Dictionary) -> void:
	ex["level"] = int(ex["level"])
	ex["seed"] = int(ex["seed"])
	var tl: Dictionary = ex["tl"]
	tl["level"] = int(tl["level"])
	tl["seed"] = int(tl["seed"])
	for pt in tl["pts"]:
		_fix_point(pt)
	_fix_point(ex["collected"])
	if tl.has("rate") and tl["rate"].size() <= Expedition.P_MATS:
		tl["rate"].append({})
	for it in tl["items"]:
		_fix_item(it)
	for m in ex["party"]:
		if m.get("npc", false):
			Roster.ensure_merc(m)
		else:
			for s in m["spells"]:
				s["lvl"] = int(s["lvl"])

## Public copy of the hero that other players can hire (concept 8: snapshots).
static func public_snapshot(p: Dictionary, account: String) -> Dictionary:
	var snap := hero_snapshot(p)
	snap["npc"] = false
	snap["owner"] = account
	snap["id"] = "p" + account
	snap["name"] = str(p["name"])
	snap["role"] = role_from_spells(p["hero"]["rotation"])
	snap["gear"] = p["hero"]["equipped"].duplicate(true)
	snap["base_stats"] = Db.hero_base_stats(int(p["hero"]["level"]))
	var ratio: float = Roster.power_score(snap) / max(1.0, Roster.expected_power(int(p["hero"]["level"])))
	snap["tier"] = 0 if ratio < 0.85 else (1 if ratio < 1.1 else (2 if ratio < 1.35 else 3))
	snap["power"] = Roster.power_score(snap)
	return snap

static func role_from_spells(rotation: Array) -> String:
	var tags := {}
	for sid in rotation:
		for t in Db.SPELLS[sid].get("tags", []):
			tags[t] = tags.get(t, 0) + 1
	if tags.has("tank"):
		return "Танк"
	if tags.has("heal"):
		return "Лекарь"
	if tags.has("interrupt") or tags.has("control"):
		return "Страж"
	if tags.has("dot"):
		return "Ядовик"
	return "Боец"

# =====================================================================
# Queries
# =====================================================================

static func hero_snapshot(p: Dictionary) -> Dictionary:
	return Roster.hero_snapshot(p["hero"], p["collection"])

static func merc_by_id(p: Dictionary, id: String):
	for m in p["hired"]:
		if m["id"] == id:
			return m
	for m in p["board"]:
		if m["id"] == id:
			return m
	return null

static func is_hired(p: Dictionary, id: String) -> bool:
	for m in p["hired"]:
		if m["id"] == id:
			return true
	return false

static func party_snapshots(p: Dictionary) -> Array:
	var out := []
	for id in p["party_order"]:
		if id == "hero":
			out.append(hero_snapshot(p))
		else:
			var m = merc_by_id(p, id)
			if m != null:
				out.append(m)
	return out

static func party_ready(p: Dictionary) -> bool:
	return party_snapshots(p).size() == 4

static func level_unlocked(p: Dictionary, level: int) -> bool:
	return level <= int(p["closed_level"]) + 1 and level <= Db.level_count()

static func day_of(now: float) -> String:
	return Time.get_date_string_from_unix_time(int(now))

static func reroll_cost(p: Dictionary, now: float) -> int:
	var n: int = int(p["rerolls_today"]) if p["reroll_day"] == day_of(now) else 0
	return int(round(REROLL_BASE * pow(REROLL_GROWTH, n) / 5.0) * 5)

static func free_box_available(p: Dictionary, now: float) -> bool:
	return p["free_box_day"] != day_of(now)

static func can_fuse(p: Dictionary, sid: String, lvl: int) -> bool:
	return int(p["collection"].get(sid, {}).get(str(lvl), 0)) >= FUSE_COUNT

## Expedition time used for rewards: real elapsed, farm capped 12 h after the last collect.
static func expedition_time(ex: Dictionary, now: float) -> float:
	var t: float = max(0.0, now - float(ex["started_at"]))
	if ex["mode"] == "farm":
		t = min(t, float(ex["collected"][Expedition.P_T]) + OFFLINE_CAP)
	elif t > float(ex["tl"]["t_end"]):
		t = float(ex["tl"]["t_end"])
	return t

## Rewards earned and not yet collected.
static func pending(p: Dictionary, now: float) -> Dictionary:
	var ex = p.get("expedition")
	if ex == null:
		return {"gold": 0, "xp": 0, "kills": 0, "items": 0, "boxes": 0, "won": 0, "lost": 0, "t": 0.0, "mats": {}}
	var t := expedition_time(ex, now)
	var tot := Expedition.rewards_at(ex["tl"], t)
	var c: Array = ex["collected"]
	return {"gold": tot[1] - c[1], "xp": tot[2] - c[2], "kills": tot[3] - c[3], "items": tot[4] - c[4],
		"boxes": tot[5] - c[5], "won": tot[6] - c[6], "lost": tot[7] - c[7], "t": t, "wave": tot[8],
		"mats": Expedition.mats_diff(tot[Expedition.P_MATS], c[Expedition.P_MATS] if c.size() > Expedition.P_MATS else {})}

static func push_finished(p: Dictionary, now: float) -> bool:
	var ex = p.get("expedition")
	return ex != null and ex["mode"] == "push" and now - float(ex["started_at"]) >= float(ex["tl"]["t_end"])

# =====================================================================
# Actions
# =====================================================================

static func apply(p: Dictionary, action: String, args: Dictionary, now: float, ctx: Dictionary = {}) -> Dictionary:
	var r := _rng(p)
	var res: Dictionary
	match action:
		"set_rotation": res = _set_rotation(p, args)
		"move_party": res = _move_party(p, int(args.get("index", 0)), int(args.get("dir", 0)))
		"equip": res = _equip(p, str(args.get("id", "")))
		"unequip": res = _unequip(p, str(args.get("slot", "")))
		"sell": res = _sell(p, str(args.get("id", "")))
		"hire": res = _hire(p, str(args.get("id", "")))
		"fire": res = _fire(p, str(args.get("id", "")))
		"replace": res = _replace(p, str(args.get("old", "")), str(args.get("new", "")))
		"fuse": res = _fuse(p, str(args.get("sid", "")), int(args.get("lvl", 1)))
		"set_name": res = _set_name(p, str(args.get("name", "")))
		"reroll": res = _reroll(p, r, now, ctx)
		"open_box": res = _open_box(p, r, str(args.get("use", "")), now)
		"open_pack": res = _open_pack(p, r, str(args.get("use", "")))
		"start": res = _start(p, r, int(args.get("level", 0)), str(args.get("mode", "")), now, ctx)
		"collect": res = _collect(p, r, now, ctx, false)
		"stop": res = _collect(p, r, now, ctx, true)
		"grant_assists": res = _grant_assists(p, int(args.get("gold", 0)), int(args.get("hires", 0)))
		"gather_start": res = _gather_start(p, str(args.get("prof", "")), str(args.get("loc", "")), int(args.get("sec", 0)), now)
		"gather_claim": res = _gather_claim(p, r, now)
		"gather_cancel": res = _gather_cancel(p)
		"craft_start": res = _craft_start(p, str(args.get("recipe", "")), now)
		"craft_claim": res = _craft_claim(p, r, str(args.get("prof", "")), now)
		"use_item": res = _use_item(p, str(args.get("res", "")), now)
		_: res = _err("unknown action")
	_save_rng(p, r)
	return res

## Finishes a push whose time is over (call before showing the profile).
static func tick(p: Dictionary, now: float, ctx: Dictionary = {}) -> Dictionary:
	var out := {"reports": [], "assists": []}
	if push_finished(p, now):
		var r := _rng(p)
		var res := _collect(p, r, now, ctx, true)
		_save_rng(p, r)
		out["reports"].append(res["report"])
		out["assists"] = res.get("assists", [])
	return out

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}

static func _ok(extra: Dictionary = {}) -> Dictionary:
	var d := {"ok": true}
	d.merge(extra)
	return d

static func _set_rotation(p: Dictionary, args: Dictionary) -> Dictionary:
	var rot: Array = args.get("rotation", [])
	if rot.size() > 3:
		return _err("too many spells")
	var seen := {}
	for sid in rot:
		if not Db.SPELLS.has(sid) or Db.SPELLS[sid].get("enemy", false):
			return _err("bad spell")
		if Roster.spell_best_level(p["collection"], sid) == 0:
			return _err("spell not owned")
		if seen.has(sid):
			return _err("duplicate spell")
		seen[sid] = true
	p["hero"]["rotation"] = rot.duplicate()
	return _ok()

static func _move_party(p: Dictionary, index: int, dir: int) -> Dictionary:
	var order: Array = p["party_order"]
	var j := index + dir
	if abs(dir) != 1 or index < 0 or index >= order.size() or j < 0 or j >= order.size():
		return _err("bad move")
	var tmp = order[index]
	order[index] = order[j]
	order[j] = tmp
	return _ok()

static func _equip(p: Dictionary, id: String) -> Dictionary:
	for it in p["inventory"]:
		if it["id"] == id:
			var slot: String = it["slot"]
			var old = p["hero"]["equipped"][slot]
			p["hero"]["equipped"][slot] = it
			p["inventory"].erase(it)
			if old != null:
				p["inventory"].append(old)
			return _ok()
	return _err("no such item")

static func _unequip(p: Dictionary, slot: String) -> Dictionary:
	if not p["hero"]["equipped"].has(slot) or p["hero"]["equipped"][slot] == null:
		return _err("slot empty")
	p["inventory"].append(p["hero"]["equipped"][slot])
	p["hero"]["equipped"][slot] = null
	return _ok()

static func _sell(p: Dictionary, id: String) -> Dictionary:
	for it in p["inventory"]:
		if it["id"] == id:
			var price := Loot.sell_price(it)
			p["gold"] += price
			p["inventory"].erase(it)
			return _ok({"gold": price})
	return _err("no such item")

static func _hire(p: Dictionary, id: String) -> Dictionary:
	if p["hired"].size() >= MAX_HIRED:
		return _err("group full")
	for m in p["board"]:
		if m["id"] == id:
			p["board"].erase(m)
			p["hired"].append(m)
			p["party_order"].append(id)
			return _ok()
	return _err("no such candidate")

static func _fire(p: Dictionary, id: String) -> Dictionary:
	for m in p["hired"]:
		if m["id"] == id:
			p["hired"].erase(m)
			p["party_order"].erase(id)
			return _ok()
	return _err("not hired")

static func _replace(p: Dictionary, old_id: String, new_id: String) -> Dictionary:
	var newcomer = null
	for m in p["board"]:
		if m["id"] == new_id:
			newcomer = m
	if newcomer == null or not is_hired(p, old_id):
		return _err("bad replace")
	p["board"].erase(newcomer)
	for i in p["hired"].size():
		if p["hired"][i]["id"] == old_id:
			p["hired"][i] = newcomer
	var pos: int = p["party_order"].find(old_id)
	p["party_order"][pos] = new_id
	return _ok()

static func _fuse(p: Dictionary, sid: String, lvl: int) -> Dictionary:
	if not can_fuse(p, sid, lvl):
		return _err("not enough copies")
	var c: Dictionary = p["collection"][sid]
	c[str(lvl)] = int(c[str(lvl)]) - FUSE_COUNT
	c[str(lvl + 1)] = int(c.get(str(lvl + 1), 0)) + 1
	return _ok()

static func _set_name(p: Dictionary, name: String) -> Dictionary:
	name = name.strip_edges()
	if name.length() < 2 or name.length() > 16:
		return _err("name length 2-16")
	p["name"] = name
	p["hero"]["name"] = name
	return _ok()

static func _reroll(p: Dictionary, r: RandomNumberGenerator, now: float, ctx: Dictionary) -> Dictionary:
	var cost := reroll_cost(p, now)
	if int(p["gold"]) < cost:
		return _err("not enough gold")
	p["gold"] -= cost
	if p["reroll_day"] != day_of(now):
		p["reroll_day"] = day_of(now)
		p["rerolls_today"] = 0
	p["rerolls_today"] += 1
	p["board"] = roll_board(p, r, ctx)
	return _ok({"cost": cost})

static func _open_box(p: Dictionary, r: RandomNumberGenerator, use: String, now: float) -> Dictionary:
	match use:
		"free":
			if not free_box_available(p, now):
				return _err("already taken today")
			p["free_box_day"] = day_of(now)
		"token":
			if int(p["boxes"]) <= 0:
				return _err("no boxes")
			p["boxes"] -= 1
		"gold":
			if int(p["gold"]) < BOX_PRICE:
				return _err("not enough gold")
			p["gold"] -= BOX_PRICE
		_:
			return _err("bad box source")
	return _ok({"boxes": [_roll_box(p, r)]})

static func _open_pack(p: Dictionary, r: RandomNumberGenerator, use: String) -> Dictionary:
	var n := 0
	match use:
		"gold":
			if int(p["gold"]) < BOX_PACK_PRICE:
				return _err("not enough gold")
			p["gold"] -= BOX_PACK_PRICE
			n = BOX_PACK
		"token":
			n = min(int(p["boxes"]), BOX_PACK)
			if n <= 0:
				return _err("no boxes")
			p["boxes"] -= n
		_:
			return _err("bad box source")
	var out := []
	for i in n:
		out.append(_roll_box(p, r))
	return _ok({"boxes": out})

static func _roll_box(p: Dictionary, r: RandomNumberGenerator) -> Dictionary:
	var weights := [10.0, 5.0, 2.0, 0.7]
	var pool := []
	var total := 0.0
	for sid in Db.SPELLS:
		if Db.SPELLS[sid].get("enemy", false):
			continue
		pool.append(sid)
		total += weights[Db.SPELLS[sid]["rarity"]]
	var x := r.randf() * total
	var pick: String = pool[0]
	for sid in pool:
		x -= weights[Db.SPELLS[sid]["rarity"]]
		if x <= 0.0:
			pick = sid
			break
	var was_new := Roster.spell_best_level(p["collection"], pick) == 0
	if not p["collection"].has(pick):
		p["collection"][pick] = {}
	p["collection"][pick]["1"] = int(p["collection"][pick].get("1", 0)) + 1
	return {"spell": pick, "new": was_new}

static func _start(p: Dictionary, r: RandomNumberGenerator, level: int, mode: String, now: float, ctx: Dictionary) -> Dictionary:
	if not mode in ["push", "farm"]:
		return _err("bad mode")
	if not party_ready(p):
		return _err("party not ready")
	if not level_unlocked(p, level):
		return _err("level locked")
	if mode == "farm" and level > int(p["closed_level"]):
		return _err("farm only on cleared levels")
	if mode == "push" and level <= int(p["closed_level"]):
		return _err("level already cleared")
	var prev := {}
	if p.get("expedition") != null:
		prev = _collect(p, r, now, ctx, true)
	var party := party_snapshots(p).duplicate(true)
	var buffs := active_buffs(p, now)
	for m in party:
		for eff in ["dmg_mult", "heal_mult"]:
			if buffs.has(eff):
				m["stats"][eff] = float(buffs[eff]["value"])
	p["expedition"] = _make_expedition(level, mode, party, r.randi(), level > int(p["closed_level"]), now)
	var out := _ok({"expedition": p["expedition"]["id"]})
	if not prev.is_empty():
		out["previous"] = prev.get("report", {})
		out["assists"] = prev.get("assists", [])
	return out

static func _make_expedition(level: int, mode: String, party: Array, seed_value: int, first: bool, now: float) -> Dictionary:
	var tl := Expedition.build_timeline(level, mode, party, seed_value, first)
	return {"id": "%d_%d" % [seed_value, int(now)], "level": level, "mode": mode, "seed": seed_value, "first": first,
		"party": party, "started_at": now, "tl": tl, "collected": Expedition.zero_point()}

## Collects pending rewards. With `finish` the expedition ends (stop / push over).
static func _collect(p: Dictionary, r: RandomNumberGenerator, now: float, ctx: Dictionary, finish: bool) -> Dictionary:
	var ex = p.get("expedition")
	if ex == null:
		return _err("no expedition")
	var t := expedition_time(ex, now)
	var tot := Expedition.rewards_at(ex["tl"], t)
	var c: Array = ex["collected"]
	var rep := {"type": "rewards", "level": ex["level"], "mode": ex["mode"],
		"gold": tot[1] - c[1], "xp": tot[2] - c[2], "kills": tot[3] - c[3], "boxes": tot[5] - c[5],
		"won": tot[6] - c[6], "lost": tot[7] - c[7], "items": [], "auto_sold": 0, "auto_sold_gold": 0,
		"mats": Expedition.mats_diff(tot[Expedition.P_MATS], c[Expedition.P_MATS] if c.size() > Expedition.P_MATS else {})}
	for i in range(int(c[4]), int(tot[4])):
		var it := Expedition.item_at(ex["tl"], i)
		if rep["items"].size() < MAX_ITEMS_PER_COLLECT:
			rep["items"].append(it)
		else:
			rep["auto_sold"] += 1
			rep["auto_sold_gold"] += Loot.sell_price(it)
	var push_over: bool = ex["mode"] == "push" and t >= float(ex["tl"]["t_end"])
	if ex["mode"] == "push":
		rep["closed"] = push_over and bool(ex["tl"]["closed"])
		if push_over:
			rep["type"] = "push_end"
			rep["reason"] = ex["tl"]["reason"]
			rep["waves"] = ex["tl"]["waves"]
			rep["total_waves"] = ex["tl"]["total"]
		else:
			rep["type"] = "push_abort" if finish else "rewards"
	else:
		rep["closed"] = false
	ex["collected"] = tot
	_apply_rewards(p, r, rep, ctx)
	var assists := []
	if rep["gold"] > 0:
		for m in ex["party"]:
			if not m.get("npc", true) and m.has("owner"):
				assists.append({"owner": m["owner"], "gold": max(1, int(rep["gold"] * ASSIST_SHARE)), "name": m["name"]})
	if finish or push_over:
		p["expedition"] = null
	return _ok({"report": rep, "assists": assists})

static func _apply_rewards(p: Dictionary, r: RandomNumberGenerator, rep: Dictionary, ctx: Dictionary) -> void:
	p["gold"] += int(rep["gold"]) + int(rep["auto_sold_gold"])
	p["boxes"] += int(rep["boxes"])
	rep["level_ups"] = _add_xp(p, int(rep["xp"]))
	for it in rep["items"]:
		p["inventory"].append(it)
	for res in rep.get("mats", {}):
		_add_res(p, res, int(rep["mats"][res]))
	rep["board_refreshed"] = false
	if rep.get("closed", false) and int(rep["level"]) > int(p["closed_level"]):
		p["closed_level"] = int(rep["level"])
		p["board"] = roll_board(p, r, ctx)
		rep["board_refreshed"] = true
	elif rep["level_ups"] > 0:
		var lvl: int = p["hero"]["level"]
		for i in p["board"].size():
			var m: Dictionary = p["board"][i]
			if m.get("npc", true) and int(m["level"]) < lvl - 1:
				p["board"][i] = Roster.relevel(r, m, lvl)

static func _add_xp(p: Dictionary, amount: int) -> int:
	var hero: Dictionary = p["hero"]
	var ups := 0
	hero["xp"] = int(hero["xp"]) + amount
	while int(hero["xp"]) >= Db.xp_to_next(int(hero["level"])):
		hero["xp"] = int(hero["xp"]) - Db.xp_to_next(int(hero["level"]))
		hero["level"] = int(hero["level"]) + 1
		ups += 1
	return ups

static func _grant_assists(p: Dictionary, gold: int, hires: int) -> Dictionary:
	if gold <= 0 and hires <= 0:
		return _err("nothing to grant")
	p["gold"] += gold
	p["stats"]["hired_total"] = int(p["stats"].get("hired_total", 0)) + hires
	p["stats"]["assist_gold_total"] = int(p["stats"].get("assist_gold_total", 0)) + gold
	p["reports"].append({"type": "assists", "gold": gold, "hires": hires})
	return _ok()

# =====================================================================
# Professions: gathering, crafting, consumables (Prof data)
# All timers use the authority's clock; claims are idempotent: the activity is
# removed when its reward is granted, so a second claim finds nothing.
# =====================================================================

static func prof_level(p: Dictionary, prof: String) -> int:
	return int(p["professions"].get(prof, {}).get("level", 1))

static func res_count(p: Dictionary, res: String) -> int:
	return int(p["resources"].get(res, 0))

static func _add_res(p: Dictionary, res: String, n: int) -> void:
	p["resources"][res] = res_count(p, res) + n
	if int(p["resources"][res]) <= 0:
		p["resources"].erase(res)

static func _add_prof_xp(p: Dictionary, prof: String, amount: int) -> int:
	var pr: Dictionary = p["professions"][prof]
	var ups := 0
	if int(pr["level"]) >= Prof.MAX_LEVEL:
		return 0
	pr["xp"] = int(pr["xp"]) + amount
	while int(pr["level"]) < Prof.MAX_LEVEL and int(pr["xp"]) >= Prof.xp_to_next(int(pr["level"])):
		pr["xp"] = int(pr["xp"]) - Prof.xp_to_next(int(pr["level"]))
		pr["level"] = int(pr["level"]) + 1
		ups += 1
	if int(pr["level"]) >= Prof.MAX_LEVEL:
		pr["xp"] = 0
	return ups

## Buffs that are active right now: effect -> {value, until | charges}
static func active_buffs(p: Dictionary, now: float) -> Dictionary:
	var out := {}
	for eff in p.get("buffs", {}):
		var b: Dictionary = p["buffs"][eff]
		if b.has("until") and float(b["until"]) > now:
			out[eff] = b
		elif b.has("charges") and int(b["charges"]) > 0:
			out[eff] = b
	return out

static func can_craft(p: Dictionary, recipe_id: String) -> Dictionary:
	if not Prof.RECIPES.has(recipe_id):
		return {"ok": false, "error": "no such recipe"}
	var r: Dictionary = Prof.RECIPES[recipe_id]
	if prof_level(p, r["prof"]) < int(r["req"]):
		return {"ok": false, "error": "profession level too low"}
	if p["crafting"].has(r["prof"]):
		return {"ok": false, "error": "already crafting"}
	if int(p["gold"]) < int(r["gold"]):
		return {"ok": false, "error": "not enough gold"}
	for res in r["ingredients"]:
		if res_count(p, res) < int(r["ingredients"][res]):
			return {"ok": false, "error": "missing " + res}
	return {"ok": true}

static func _gather_start(p: Dictionary, prof: String, loc: String, sec: int, now: float) -> Dictionary:
	if not prof in Prof.GATHERING:
		return _err("not a gathering profession")
	if not Prof.LOCATIONS.has(loc) or Prof.LOCATIONS[loc]["prof"] != prof:
		return _err("bad location")
	if prof_level(p, prof) < int(Prof.LOCATIONS[loc]["req"]):
		return _err("profession level too low")
	if Prof.duration(sec).is_empty():
		return _err("bad duration")
	if p["gathering"] != null:
		return _err("already gathering")
	var tonic := false
	var b = p["buffs"].get("gather_yield")
	if b != null and int(b.get("charges", 0)) > 0:
		tonic = true
		b["charges"] = int(b["charges"]) - 1
		if b["charges"] <= 0:
			p["buffs"].erase("gather_yield")
	p["gathering"] = {"prof": prof, "loc": loc, "sec": sec, "started_at": now, "ends_at": now + sec, "tonic": tonic}
	return _ok({"ends_at": now + sec})

static func _gather_claim(p: Dictionary, r: RandomNumberGenerator, now: float) -> Dictionary:
	var g = p.get("gathering")
	if g == null:
		return _err("nothing to claim")
	if now < float(g["ends_at"]):
		return _err("not finished")
	var loc: Dictionary = Prof.LOCATIONS[g["loc"]]
	var sec: int = int(g["sec"])
	var mult := Prof._yield_mult(loc, sec, prof_level(p, g["prof"]), bool(g.get("tonic", false)))
	var got := {}
	for res in loc["yields"]:
		var n := int(round(float(loc["yields"][res]) * mult * r.randf_range(1.0 - Prof.YIELD_SPREAD, 1.0 + Prof.YIELD_SPREAD)))
		if n > 0:
			got[res] = n
	for res in loc["rare"]:
		var expect := float(loc["rare"][res]) * sec / 3600.0 * (float(Prof.CONSUMABLES["gatherers_tonic"]["value"]) if g.get("tonic", false) else 1.0)
		var n := int(floor(expect)) + (1 if r.randf() < expect - floor(expect) else 0)
		if n > 0:
			got[res] = n
	for res in got:
		_add_res(p, res, got[res])
	var xp := Prof.gather_xp(g["loc"], sec)
	var ups := _add_prof_xp(p, g["prof"], xp)
	p["gathering"] = null
	return _ok({"report": {"type": "gather", "prof": g["prof"], "loc": g["loc"], "res": got, "xp": xp, "level_ups": ups,
		"tonic": g.get("tonic", false)}})

static func _gather_cancel(p: Dictionary) -> Dictionary:
	if p.get("gathering") == null:
		return _err("nothing to cancel")
	p["gathering"] = null
	return _ok()

static func _craft_start(p: Dictionary, recipe_id: String, now: float) -> Dictionary:
	var chk := can_craft(p, recipe_id)
	if not chk["ok"]:
		return chk
	var r: Dictionary = Prof.RECIPES[recipe_id]
	p["gold"] -= int(r["gold"])
	for res in r["ingredients"]:
		_add_res(p, res, -int(r["ingredients"][res]))
	p["crafting"][r["prof"]] = {"recipe": recipe_id, "started_at": now, "ends_at": now + float(r["time"])}
	return _ok({"ends_at": now + float(r["time"])})

static func _craft_claim(p: Dictionary, rng: RandomNumberGenerator, prof: String, now: float) -> Dictionary:
	var c = p["crafting"].get(prof)
	if c == null:
		return _err("nothing to claim")
	if now < float(c["ends_at"]):
		return _err("not finished")
	var r: Dictionary = Prof.RECIPES[c["recipe"]]
	var rep := {"type": "craft", "prof": prof, "recipe": c["recipe"], "items": [], "res": {}}
	if r.has("item"):
		var it := Prof.make_item(c["recipe"], "c%08x%08x" % [rng.randi(), rng.randi()])
		p["inventory"].append(it)
		rep["items"].append(it)
	for res in r.get("output", {}):
		_add_res(p, res, int(r["output"][res]))
		rep["res"][res] = int(r["output"][res])
	rep["xp"] = int(r["xp"])
	rep["level_ups"] = _add_prof_xp(p, prof, int(r["xp"]))
	p["crafting"].erase(prof)
	return _ok({"report": rep})

static func _use_item(p: Dictionary, res: String, now: float) -> Dictionary:
	if not Prof.CONSUMABLES.has(res):
		return _err("not usable")
	if res_count(p, res) <= 0:
		return _err("none left")
	var c: Dictionary = Prof.CONSUMABLES[res]
	_add_res(p, res, -1)
	if c.has("duration"):
		p["buffs"][c["effect"]] = {"value": float(c["value"]), "until": now + float(c["duration"]), "res": res}
	else:
		var b: Dictionary = p["buffs"].get(c["effect"], {"value": float(c["value"]), "charges": 0, "res": res})
		b["charges"] = int(b.get("charges", 0)) + int(c.get("charges", 1))
		p["buffs"][c["effect"]] = b
	return _ok({"buff": c["effect"]})

# =====================================================================
# Board
# =====================================================================

## 6 candidates: up to REAL_SLOTS real players near your level (server), the rest
## guild NPCs; a tank and a healer are always present (concept 9).
static func roll_board(p: Dictionary, r: RandomNumberGenerator, ctx: Dictionary) -> Array:
	var lvl: int = p["hero"]["level"]
	var npcs := Roster.roll_board(r, lvl)
	var pool: Array = ctx.get("real_pool", [])
	var reals := []
	var hired_ids := {}
	for m in p["hired"]:
		hired_ids[m["id"]] = true
	var cands := []
	for s in pool:
		if str(s.get("owner", "")) != str(ctx.get("account", "")) and not hired_ids.has(s["id"]):
			cands.append(s)
	for i in range(cands.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp = cands[i]
		cands[i] = cands[j]
		cands[j] = tmp
	for s in cands.slice(0, REAL_SLOTS):
		var m: Dictionary = s.duplicate(true)
		Roster.ensure_merc(m)
		reals.append(m)
	var tank = null
	var healer = null
	var others := []
	for m in npcs:
		if tank == null and m["role"] == "Танк":
			tank = m
		elif healer == null and m["role"] == "Лекарь":
			healer = m
		else:
			others.append(m)
	var board := reals.duplicate()
	var has_tank := false
	var has_healer := false
	for m in reals:
		has_tank = has_tank or m["role"] == "Танк"
		has_healer = has_healer or m["role"] == "Лекарь"
	if not has_tank and tank != null:
		board.append(tank)
	if not has_healer and healer != null:
		board.append(healer)
	for m in others:
		if board.size() >= 6:
			break
		board.append(m)
	board = board.slice(0, 6)
	for i in range(board.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp = board[i]
		board[i] = board[j]
		board[j] = tmp
	return board

static func _auto_party(p: Dictionary) -> void:
	var board: Array = p["board"]
	var picks := []
	for role in ["Танк", "Лекарь"]:
		for m in board:
			if m["role"] == role and not picks.has(m):
				picks.append(m)
				break
	for m in board:
		if picks.size() >= MAX_HIRED:
			break
		if not picks.has(m) and not m["role"] in ["Танк", "Лекарь"]:
			picks.append(m)
	for m in board:
		if picks.size() >= MAX_HIRED:
			break
		if not picks.has(m):
			picks.append(m)
	p["hired"] = picks
	p["party_order"] = [picks[0]["id"], "hero", picks[2]["id"], picks[1]["id"]]

# =====================================================================
# RNG stored in the profile
# =====================================================================

static func _rng(p: Dictionary) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = str(p["rng"]["seed"]).to_int()
	var st := str(p["rng"].get("state", ""))
	if st != "":
		r.state = st.to_int()
	return r

static func _save_rng(p: Dictionary, r: RandomNumberGenerator) -> void:
	p["rng"]["state"] = str(r.state)
