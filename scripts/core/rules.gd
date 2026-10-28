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

const VERSION := 9
const OFFLINE_CAP := 12.0 * 3600.0
const BOX_PRICE := 300
const BOX_PACK := 10
const BOX_PACK_PRICE := 2700
## Spell boxes bought for gold per day (packs count as 10). Crystals have no limit.
const GOLD_BOXES_PER_DAY := 10
## Spell Box odds by spell rarity (common, rare, epic, legendary), per spell.
const BOX_RARITY_WEIGHTS := [10.0, 3.0, 0.8, 0.25]
## Board reroll: price follows the hero level (10 + 3 per level), grows only a little per reroll in a day.
const REROLL_BASE := 10
const REROLL_PER_LEVEL := 3
const REROLL_GROWTH := 1.1
const MAX_HIRED := 3
const SPELL_MAX_LEVEL := 10
## Spare copies (duplicates from boxes) eaten by each upgrade: I->II, II->III, ... IX->X.
const FUSE_COST := [4, 5, 6, 7, 8, 9, 10, 11, 12]
const ASSIST_SHARE := 0.05       # owner of a hired real character gets 5% of the gold (concept 8.1)
const MAX_ITEMS_PER_COLLECT := 30
const REAL_SLOTS := 3            # up to 3 of 6 board places go to real players

## Actions without randomness: the client may apply them locally right away.
const LOCAL_ACTIONS := ["set_rotation", "move_party", "equip", "unequip", "sell", "hire", "fire", "replace", "fuse", "set_name",
	"talent_up", "talent_reset", "set_threshold", "set_cosmetic", "set_appearance"]
## Actions with randomness or rewards: only the authority (server or offline client) runs them.
const AUTHORITY_ACTIONS := ["reroll", "open_box", "open_pack", "start", "collect", "stop",
	"gather_start", "gather_claim", "gather_cancel", "craft_start", "craft_claim", "use_item",
	"fake_purchase", "buy_cosmetic", "rush", "buy_boost", "upgrade_item", "merge_items"]
## Server-internal actions, never accepted from a client.
const INTERNAL_ACTIONS := ["grant_assists"]

# =====================================================================
# Profile lifecycle
# =====================================================================

static func new_profile(seed_value: int, now: float, name: String = "Герой") -> Dictionary:
	var p := {
		"v": VERSION, "name": name, "created": now,
		"gold": 100, "boxes": 1, "closed_level": 0,
		"hero": {"name": name, "level": 1, "xp": 0, "rotation": ["kick", "fireball", "strike"], "talents": {}, "spell_settings": {}, "cosmetics": {},
			"equipped": _empty_equipment(), "appearance": CharacterAppearance.normalize({})},
		"collection": {}, "inventory": [], "board": [], "hired": [], "party_order": [],
		"rerolls_today": 0, "reroll_day": "", "free_box_day": "",
		"expedition": null, "reports": [], "stats": {"hired_total": 0, "assist_gold_total": 0},
		"resources": {}, "recipes_known": [], "crystals": 0, "cosmetics_owned": [], "gold_box_day": "", "gold_boxes_today": 0, "professions": _fresh_professions(), "gathering": null, "crafting": {}, "buffs": {},
		"rng": {"seed": str(seed_value), "state": ""},
	}
	var r := _rng(p)
	var sword := Loot.roll_gear(r, 1, -1.0, "weapon", "sword")
	sword["name"] = "Учебный меч"
	p["hero"]["equipped"]["weapon"] = sword
	for sid in Db.STARTER_SPELLS:
		p["collection"][sid] = {"lvl": 1, "copies": 0}
	p["board"] = Roster.roll_board(r, 1)
	_auto_party(p)
	p["board"] = Roster.roll_board(r, 1)
	_save_rng(p, r)
	return p

## Brings any older or JSON-parsed profile to the current shape (ints restored).
static func migrate(p: Dictionary, now: float) -> void:
	var old_combat := int(p.get("v",0)) < 9
	_drop_extra_heroes(p)
	# v6: priority rotation; the old default order would never use strike and kick
	if int(p.get("v", 0)) < 6 and p.has("hero") and p["hero"].get("rotation", []) == ["fireball", "strike", "kick"]:
		p["hero"]["rotation"] = ["kick", "fireball", "strike"]
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
	_migrate_spells(p)
	if int(p.get("v", 0)) < 9:
		_migrate_combat(p)
	var hero: Dictionary = p["hero"]
	hero["appearance"] = CharacterAppearance.normalize(hero.get("appearance"))
	hero["level"] = int(hero["level"])
	if typeof(hero.get("talents")) != TYPE_DICTIONARY:
		hero["talents"] = {}
	if typeof(hero.get("spell_settings")) != TYPE_DICTIONARY:
		hero["spell_settings"] = {}
	if typeof(p.get("recipes_known")) != TYPE_ARRAY:
		p["recipes_known"] = []
	p["crystals"] = int(p.get("crystals", 0))
	p["gold_boxes_today"] = int(p.get("gold_boxes_today", 0))
	p["gold_box_day"] = str(p.get("gold_box_day", ""))
	if typeof(p.get("cosmetics_owned")) != TYPE_ARRAY:
		p["cosmetics_owned"] = []
	if typeof(p["hero"].get("cosmetics")) != TYPE_DICTIONARY:
		p["hero"]["cosmetics"] = {}
	for k in hero["talents"].keys():
		hero["talents"][k] = int(hero["talents"][k])
	hero["xp"] = int(hero["xp"])
	for slot in hero["equipped"]:
		_fix_item(hero["equipped"][slot])
	# v5: a two-handed weapon and something in the left hand cannot be held together
	if Loot.is_two_handed(hero["equipped"].get("weapon")) and hero["equipped"].get("offhand") != null:
		p["inventory"].append(hero["equipped"]["offhand"])
		hero["equipped"]["offhand"] = null
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
	if old_combat and p.get("expedition") != null and p["expedition"].has("tl") and not p["expedition"]["tl"].has("combat_version"):
		# Settle already-earned old rewards once, then restart farming with new rules.
		var previous: Dictionary = p["expedition"]
		var random := _rng(p)
		var settled := _collect(p,random,now,{},true)
		if settled.get("ok",false):
			p["reports"].append(settled["report"])
		if previous["mode"] == "farm":
			p["expedition"] = _make_expedition(int(previous["level"]),"farm",party_snapshots(p),int(previous["seed"]),false,now)
		_save_rng(p,random)
	p.erase("time")
	p.erase("v")
	p["v"] = VERSION

static func _empty_equipment() -> Dictionary:
	var e := {}
	for slot in Loot.ALL_SLOTS:
		e[slot] = null
	return e

## v4: a spell is {"lvl", "copies"} (one level + spare duplicates) instead of
## copies per level. Old copies are converted to level-I equivalents (a level-k
## copy was worth 5^(k-1)), the best level is kept, the rest become spare copies.
static func _migrate_spells(p: Dictionary) -> void:
	var col: Dictionary = p["collection"]
	for sid in col.keys():
		var c: Dictionary = col[sid]
		if c.has("lvl"):
			c["lvl"] = int(c["lvl"])
			c["copies"] = int(c.get("copies", 0))
			continue
		var best := 0
		var total := 0
		for k in c.keys():
			var n := int(c[k])
			if n > 0:
				best = max(best, int(k))
				total += n * int(pow(5, int(k) - 1))
		if best == 0:
			col.erase(sid)
			continue
		best = min(best, SPELL_MAX_LEVEL)
		var spare := total - 1
		for l in range(1, best):
			spare -= fuse_cost(l)
		col[sid] = {"lvl": best, "copies": max(0, spare)}

## v8: several heroes were tried (v7) and removed. Keep the account's first hero
## (with his professions, gathering and crafting), drop the others, refund the slots.
static func _drop_extra_heroes(p: Dictionary) -> void:
	if not p.has("heroes_other") and not p.has("hero_slots"):
		return
	var others: Array = p.get("heroes_other", []) if typeof(p.get("heroes_other")) == TYPE_ARRAY else []
	if p.has("hero") and str(p["hero"].get("id", "h0")) != "h0":
		for b in others:
			if str(b["hero"].get("id", "")) == "h0":
				p["hero"] = b["hero"]
				for k in ["professions", "gathering", "crafting"]:
					p[k] = b.get(k, p.get(k))
	var slots := int(p.get("hero_slots", 1))
	if slots > 1:
		p["crystals"] = int(p.get("crystals", 0)) + (slots - 1) * 500
	var ex = p.get("expedition")
	if typeof(ex) == TYPE_DICTIONARY:
		ex.erase("hero_id")
	if p.has("hero"):
		p["hero"].erase("id")
	p.erase("heroes_other")
	p.erase("hero_slots")

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
	Loot.upgrade_item(it)

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
	var base: float = REROLL_BASE + REROLL_PER_LEVEL * int(p["hero"]["level"])
	return int(max(5, round(base * pow(REROLL_GROWTH, n) / 5.0) * 5))

static func free_box_available(p: Dictionary, now: float) -> bool:
	return p["free_box_day"] != day_of(now)

## Spare copies needed to raise a spell from `lvl` to `lvl + 1` (0 at max level).
static func fuse_cost(lvl: int) -> int:
	if lvl < 1 or lvl >= SPELL_MAX_LEVEL:
		return 0
	return int(FUSE_COST[lvl - 1])

static func can_fuse(p: Dictionary, sid: String) -> bool:
	var c: Dictionary = p["collection"].get(sid, {})
	var lvl := int(c.get("lvl", 0))
	return lvl >= 1 and lvl < SPELL_MAX_LEVEL and int(c.get("copies", 0)) >= fuse_cost(lvl)

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
		"equip": res = _equip(p, str(args.get("id", "")), str(args.get("to", "")))
		"unequip": res = _unequip(p, str(args.get("slot", "")))
		"sell": res = _sell(p, str(args.get("id", "")))
		"hire": res = _hire(p, str(args.get("id", "")))
		"fire": res = _fire(p, str(args.get("id", "")))
		"replace": res = _replace(p, str(args.get("old", "")), str(args.get("new", "")))
		"fuse": res = _fuse(p, str(args.get("sid", "")))
		"talent_up": res = _talent_up(p, str(args.get("id", "")))
		"talent_reset": res = _talent_reset(p)
		"set_threshold": res = _set_threshold(p, str(args.get("sid", "")), float(args.get("value", 0.0)))
		"set_cosmetic": res = _set_cosmetic(p, str(args.get("slot", "")), str(args.get("id", "")))
		"set_appearance": res = _set_appearance(p, args)
		"fake_purchase": res = _fake_purchase(p, str(args.get("pack", "")))
		"buy_cosmetic": res = _buy_cosmetic(p, str(args.get("id", "")))
		"rush": res = _rush(p, str(args.get("what", "")), str(args.get("prof", "")), now)
		"buy_boost": res = _buy_boost(p, now)
		"upgrade_item": res = _upgrade_item(p, str(args.get("id", "")), str(args.get("pay", "gold")))
		"merge_items": res = _merge_items(p, r, int(args.get("rarity", -1)))
		"set_name": res = _set_name(p, str(args.get("name", "")))
		"reroll": res = _reroll(p, r, now, ctx)
		"open_box": res = _open_box(p, r, str(args.get("use", "")), now)
		"open_pack": res = _open_pack(p, r, str(args.get("use", "")), now)
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

## Puts an item on. `to` = "offhand" sends a one-handed sword to the left hand.
## A two-handed weapon takes both hands: whatever is in the left hand goes to the bag,
## and anything put in the left hand pushes a two-handed weapon out.
static func _equip(p: Dictionary, id: String, to: String = "") -> Dictionary:
	for it in p["inventory"]:
		if it["id"] == id:
			var slot: String = it["slot"]
			if to == "offhand":
				if not Loot.fits_offhand(it):
					return _err("not an offhand item")
				slot = "offhand"
			p["inventory"].erase(it)
			p["inventory"].append_array(place_item(p["hero"]["equipped"], it, slot))
			return _ok()
	return _err("no such item")

## Puts `it` into `slot` of an equipment dict; returns the items that come off.
## Also used by the UI to preview a change.
static func place_item(eq: Dictionary, it: Dictionary, slot: String) -> Array:
	var removed := []
	if eq.get(slot) != null:
		removed.append(eq[slot])
	eq[slot] = it
	if slot == "weapon" and Loot.is_two_handed(it) and eq.get("offhand") != null:
		removed.append(eq["offhand"])
		eq["offhand"] = null
	if slot == "offhand" and Loot.is_two_handed(eq.get("weapon")):
		removed.append(eq["weapon"])
		eq["weapon"] = null
	return removed

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

static func _talent_up(p: Dictionary, id: String) -> Dictionary:
	if not Talents.TALENTS.has(id):
		return _err("no such talent")
	var hero: Dictionary = p["hero"]
	var t: Dictionary = hero["talents"]
	if int(t.get(id, 0)) >= Talents.TALENTS[id]["ranks"]:
		return _err("max rank")
	if not Talents.unlocked(id, t):
		return _err("tier locked")
	if Talents.points_free(hero) < Talents.rank_cost(int(t.get(id, 0))):
		return _err("no talent points")
	t[id] = int(t.get(id, 0)) + 1
	return _ok()

## Player-chosen hp threshold for a healing spell (Db.THRESHOLD_OPTIONS).
static func _set_threshold(p: Dictionary, sid: String, value: float) -> Dictionary:
	if not Db.SPELLS.has(sid) or not Db.SPELLS[sid]["kind"] in Db.THRESHOLD_KINDS:
		return _err("spell has no threshold")
	var ok := false
	for o in Db.THRESHOLD_OPTIONS:
		if absf(float(o) - value) < 0.001:
			ok = true
	if not ok:
		return _err("bad threshold")
	var st: Dictionary = p["hero"]["spell_settings"]
	if not st.has(sid):
		st[sid] = {}
	st[sid]["threshold"] = value
	return _ok()

# ---------------- crystals ----------------

## Share of the real-time span [t0, t1] covered by the farm boost.
static func _boost_share(p: Dictionary, t0: float, t1: float) -> float:
	var b = p.get("buffs", {}).get("farm_x2")
	if b == null or t1 <= t0:
		return 0.0
	var overlap: float = min(t1, float(b["until"])) - max(t0, float(b["from"]))
	return clamp(overlap / (t1 - t0), 0.0, 1.0)

static func _fake_purchase(p: Dictionary, pack: String) -> Dictionary:
	for pk in Shop.PACKS:
		if pk["id"] == pack:
			p["crystals"] = int(p["crystals"]) + int(pk["crystals"])
			return _ok({"crystals": pk["crystals"]})
	return _err("no such pack")

static func _spend_crystals(p: Dictionary, n: int) -> bool:
	if int(p["crystals"]) < n:
		return false
	p["crystals"] = int(p["crystals"]) - n
	return true

static func _buy_cosmetic(p: Dictionary, id: String) -> Dictionary:
	if not Shop.COSMETICS.has(id):
		return _err("no such cosmetic")
	if id in p["cosmetics_owned"]:
		return _err("already owned")
	if not _spend_crystals(p, int(Shop.COSMETICS[id]["price"])):
		return _err("not enough crystals")
	p["cosmetics_owned"].append(id)
	p["hero"]["cosmetics"][Shop.COSMETICS[id]["slot"]] = id
	return _ok()

## id "" takes the cosmetic off.
static func _set_cosmetic(p: Dictionary, slot: String, id: String) -> Dictionary:
	if not Shop.COSMETIC_SLOTS.has(slot):
		return _err("bad slot")
	if id == "":
		p["hero"]["cosmetics"].erase(slot)
		return _ok()
	if not id in p["cosmetics_owned"] or Shop.COSMETICS[id]["slot"] != slot:
		return _err("not owned")
	p["hero"]["cosmetics"][slot] = id
	return _ok()

static func _set_appearance(p: Dictionary, args: Dictionary) -> Dictionary:
	var sex := str(args.get("sex", ""))
	var hair := str(args.get("hair", ""))
	if not CharacterAppearance.valid(sex, hair):
		return _err("invalid appearance")
	p["hero"]["appearance"] = {"sex": sex, "hair": hair}
	if p.get("expedition") != null:
		for snapshot in p["expedition"]["party"]:
			if snapshot.get("is_hero", false) and not snapshot.has("owner"):
				snapshot["appearance"] = p["hero"]["appearance"].duplicate()
	return _ok()

## Finish the current gathering ("gather") or a profession's craft ("craft") now.
static func _rush(p: Dictionary, what: String, prof: String, now: float) -> Dictionary:
	var job = p.get("gathering") if what == "gather" else p["crafting"].get(prof)
	if job == null:
		return _err("nothing to rush")
	var left: float = float(job["ends_at"]) - now
	if left <= 0.0:
		return _err("already done")
	if not _spend_crystals(p, Shop.rush_cost(left)):
		return _err("not enough crystals")
	job["ends_at"] = now
	return _ok()

static func _buy_boost(p: Dictionary, now: float) -> Dictionary:
	if not _spend_crystals(p, Shop.BOOST_PRICE):
		return _err("not enough crystals")
	var b = p["buffs"].get("farm_x2")
	if b != null and float(b["until"]) > now:
		b["until"] = float(b["until"]) + Shop.BOOST_SECONDS   # stacks: extends the running boost
	else:
		p["buffs"]["farm_x2"] = {"from": now, "until": now + Shop.BOOST_SECONDS, "value": Shop.BOOST_MULT}
	return _ok()

## Raises an item (bag or worn) to the hero's level. pay: "gold" (gold + ore) or "crystals".
static func _upgrade_item(p: Dictionary, id: String, pay: String) -> Dictionary:
	var it = null
	for x in p["inventory"]:
		if x["id"] == id:
			it = x
	for slot in p["hero"]["equipped"]:
		var e = p["hero"]["equipped"][slot]
		if e != null and e["id"] == id:
			it = e
	if it == null:
		return _err("no such item")
	var to: int = int(p["hero"]["level"])
	var cost := Shop.upgrade_cost(it, to)
	if cost.is_empty():
		return _err("already at hero level")
	if pay == "crystals":
		if not _spend_crystals(p, int(cost["crystals"])):
			return _err("not enough crystals")
	else:
		if int(p["gold"]) < int(cost["gold"]):
			return _err("not enough gold")
		if res_count(p, cost["ore"]) < int(cost["ore_n"]):
			return _err("missing " + str(cost["ore"]))
		p["gold"] -= int(cost["gold"])
		_add_res(p, cost["ore"], -int(cost["ore_n"]))
	Loot.rescale(it, to)
	return _ok({"ilvl": to})

## Item merge: MERGE_COUNT bag items of one rarity -> one random item of the next
## rarity at the highest item level of the three. The weakest ones are used.
const MERGE_COUNT := 3
const MERGE_GOLD := [60, 200, 600]

static func merge_candidates(p: Dictionary, rarity: int) -> Array:
	var list := []
	for it in p["inventory"]:
		if int(it["rarity"]) == rarity:
			list.append(it)
	list.sort_custom(func(a, b): return Loot.item_score(a) < Loot.item_score(b))
	return list.slice(0, MERGE_COUNT) if list.size() >= MERGE_COUNT else []

static func _merge_items(p: Dictionary, r: RandomNumberGenerator, rarity: int) -> Dictionary:
	if rarity < 0 or rarity > 2:
		return _err("bad rarity")
	var used := merge_candidates(p, rarity)
	if used.is_empty():
		return _err("not enough items")
	if int(p["gold"]) < int(MERGE_GOLD[rarity]):
		return _err("not enough gold")
	p["gold"] -= int(MERGE_GOLD[rarity])
	var ilvl := 1
	for it in used:
		ilvl = max(ilvl, int(it["ilvl"]))
		p["inventory"].erase(it)
	var out := Loot.roll_gear(r, ilvl, 0.0, "", "", [], rarity + 1)
	p["inventory"].append(out)
	return _ok({"item": out})

static func _talent_reset(p: Dictionary) -> Dictionary:
	p["hero"]["talents"] = {}
	return _ok()

static func _fuse(p: Dictionary, sid: String) -> Dictionary:
	if not p["collection"].has(sid):
		return _err("spell not owned")
	var c: Dictionary = p["collection"][sid]
	if int(c["lvl"]) >= SPELL_MAX_LEVEL:
		return _err("max level")
	if not can_fuse(p, sid):
		return _err("not enough copies")
	c["copies"] = int(c["copies"]) - fuse_cost(int(c["lvl"]))
	c["lvl"] = int(c["lvl"]) + 1
	return _ok({"lvl": c["lvl"]})

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
			if gold_boxes_left(p, now) < 1:
				return _err("gold box limit")
			if int(p["gold"]) < BOX_PRICE:
				return _err("not enough gold")
			p["gold"] -= BOX_PRICE
			_count_gold_boxes(p, now, 1)
		"crystals":
			if int(p["crystals"]) < Shop.BOX_CRYSTALS:
				return _err("not enough crystals")
			p["crystals"] -= Shop.BOX_CRYSTALS
		_:
			return _err("bad box source")
	return _ok({"boxes": [_roll_box(p, r)]})

static func gold_boxes_left(p: Dictionary, now: float) -> int:
	var used: int = int(p.get("gold_boxes_today", 0)) if p.get("gold_box_day", "") == day_of(now) else 0
	return max(0, GOLD_BOXES_PER_DAY - used)

static func _count_gold_boxes(p: Dictionary, now: float, n: int) -> void:
	if p.get("gold_box_day", "") != day_of(now):
		p["gold_box_day"] = day_of(now)
		p["gold_boxes_today"] = 0
	p["gold_boxes_today"] = int(p["gold_boxes_today"]) + n

static func _open_pack(p: Dictionary, r: RandomNumberGenerator, use: String, now: float) -> Dictionary:
	var n := 0
	match use:
		"gold":
			if gold_boxes_left(p, now) < BOX_PACK:
				return _err("gold box limit")
			if int(p["gold"]) < BOX_PACK_PRICE:
				return _err("not enough gold")
			p["gold"] -= BOX_PACK_PRICE
			_count_gold_boxes(p, now, BOX_PACK)
			n = BOX_PACK
		"crystals":
			if int(p["crystals"]) < Shop.BOX_PACK_CRYSTALS:
				return _err("not enough crystals")
			p["crystals"] -= Shop.BOX_PACK_CRYSTALS
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
	var weights := BOX_RARITY_WEIGHTS
	var pool := []
	var total := 0.0
	for sid in Db.SPELLS:
		if Db.SPELLS[sid].get("enemy", false) or Db.SPELLS[sid].get("hidden", false):
			continue
		if Roster.spell_best_level(p["collection"], sid) >= SPELL_MAX_LEVEL:
			continue   # maxed spells no longer drop, so the rest come more often
		pool.append(sid)
		total += weights[Db.SPELLS[sid]["rarity"]]
	if pool.is_empty():
		pool.append("strike")
		total = 1.0
	var x := r.randf() * total
	var pick: String = pool[0]
	for sid in pool:
		x -= weights[Db.SPELLS[sid]["rarity"]]
		if x <= 0.0:
			pick = sid
			break
	var was_new := Roster.spell_best_level(p["collection"], pick) == 0
	if not p["collection"].has(pick):
		p["collection"][pick] = {"lvl": 1, "copies": 0}
	else:
		p["collection"][pick]["copies"] = int(p["collection"][pick]["copies"]) + 1
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
	tl["combat_version"] = 9
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
	if ex["mode"] == "farm":
		var frac := _boost_share(p, float(ex["started_at"]) + float(c[0]), float(ex["started_at"]) + t)
		if frac > 0.0:
			rep["boost_gold"] = int(round(rep["gold"] * frac * (Shop.BOOST_MULT - 1.0)))
			rep["boost_xp"] = int(round(rep["xp"] * frac * (Shop.BOOST_MULT - 1.0)))
			rep["gold"] += rep["boost_gold"]
			rep["xp"] += rep["boost_xp"]
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
		if int(rep["level"]) % Shop.CRYSTALS_FIRST_CLEAR_EVERY == 0:
			p["crystals"] = int(p["crystals"]) + Shop.CRYSTALS_FIRST_CLEAR
			rep["crystals"] = Shop.CRYSTALS_FIRST_CLEAR
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
	if res.begins_with("rcp_"):   # a recipe drop: learn it (duplicates do nothing)
		var rid := res.substr(4)
		if Prof.RECIPES.has(rid) and n > 0 and not rid in p["recipes_known"]:
			p["recipes_known"].append(rid)
		return
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
	if r.get("drop_only", false) and not recipe_id in p.get("recipes_known", []):
		return {"ok": false, "error": "recipe not learned"}
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

## Refund old talents; preserve the value of spell upgrades when replacing IDs.
static func _migrate_combat(p: Dictionary) -> void:
	p["hero"]["talents"] = {}
	var aliases := {"poison_cloud":"living_bomb", "drain":"haunt", "twin_strike":"strike", "renew":"wild_growth"}
	var settings: Dictionary = p["hero"].get("spell_settings",{})
	for old in aliases:
		if settings.has(old):
			settings[aliases[old]] = settings[old]
			settings.erase(old)
	p["hero"]["spell_settings"] = settings
	var col: Dictionary = p["collection"]
	for old in aliases:
		var replacement: String = aliases[old]
		if col.has(old):
			var previous: Dictionary = col[old]
			if col.has(replacement):
				var existing: Dictionary = col[replacement]
				var best := maxi(int(existing["lvl"]), int(previous["lvl"]))
				var value := int(existing.get("copies",0)) + int(previous.get("copies",0)) + 1
				for rank in range(1, mini(int(existing["lvl"]), int(previous["lvl"]))):
					value += fuse_cost(rank)
				col[replacement] = {"lvl":best,"copies":value}
			else:
				col[replacement] = previous.duplicate()
			col.erase(old)
	for i in p["hero"]["rotation"].size():
		var id: String = p["hero"]["rotation"][i]
		p["hero"]["rotation"][i] = aliases.get(id,id)
	var unique := []
	for id in p["hero"]["rotation"]:
		if not unique.has(id):
			unique.append(id)
	p["hero"]["rotation"] = unique
	for m in p["board"] + p["hired"]:
		m.erase("tier")
		m["talents"] = {}
		for e in m["spells"]:
			e["id"] = aliases.get(e["id"],e["id"])
	# Existing offline timelines retain their original earned rewards. Future runs
	# use the migrated snapshots; old IDs remain readable for an in-flight run.
