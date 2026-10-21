class_name Roster
extends RefCounted
## Builds combat snapshots for the hero and guild mercenaries (concept 8-9).

const HERO_COLOR := "#3fa7d6"
const MERC_COLORS := ["#e0a458", "#7bc96f", "#d36fa3", "#6fb3d3", "#c9c95b", "#9d8cff"]
const MERC_STAT_FACTOR := 0.95   # NPCs are decent, but a good real build should beat them

static func spell_best_level(collection: Dictionary, sid: String) -> int:
	var best := 0
	if collection.has(sid):
		for k in collection[sid].keys():
			if int(collection[sid][k]) > 0:
				best = max(best, int(k))
	return best

static func hero_stats(hero: Dictionary) -> Dictionary:
	var st := Db.hero_base_stats(hero["level"])
	for slot in hero["equipped"].keys():
		var item = hero["equipped"][slot]
		if item == null:
			continue
		for a in item["affixes"]:
			st[a["stat"]] = st.get(a["stat"], 0.0) + a["value"]
	return st

static func hero_snapshot(hero: Dictionary, collection: Dictionary) -> Dictionary:
	var spells := []
	for sid in hero["rotation"]:
		spells.append({"id": sid, "lvl": max(1, spell_best_level(collection, sid))})
	return {
		"name": hero["name"], "color": HERO_COLOR, "npc": false, "is_hero": true,
		"role": "Герой", "level": hero["level"],
		"stats": hero_stats(hero), "spells": spells, "target": "front",
	}

static func make_merc(rng: RandomNumberGenerator, template_idx: int, level: int) -> Dictionary:
	var t: Dictionary = Db.MERC_TEMPLATES[template_idx]
	var st := Db.hero_base_stats(level)
	for k in ["hp", "atk", "power", "armor"]:
		st[k] = round(st[k] * t["stat"].get(k, 1.0) * MERC_STAT_FACTOR * rng.randf_range(0.95, 1.05))
	st["crit"] = 0.05
	var spell_lvl := 1 + int(level / 4)
	var spells := []
	for sid in t["spells"]:
		spells.append({"id": sid, "lvl": max(1, spell_lvl - rng.randi_range(0, 1))})
	return {
		"name": Db.MERC_NAMES[rng.randi_range(0, Db.MERC_NAMES.size() - 1)],
		"color": MERC_COLORS[rng.randi_range(0, MERC_COLORS.size() - 1)],
		"npc": true, "role": t["role"], "level": level,
		"stats": st, "spells": spells, "target": "front",
		"id": "m%d" % rng.randi(),
	}

## Single "Power" number shown in UI. Deliberately crude: the concept says
## success depends on composition, not just Power.
static func power_score(snap: Dictionary) -> int:
	var st: Dictionary = snap["stats"]
	var spell_bonus := 0.0
	for s in snap["spells"]:
		spell_bonus += 10.0 * s["lvl"]
	return int(st["hp"] / 8.0 + st["atk"] * 2.0 + st["power"] * 2.5 + st.get("armor", 0) * 1.5
		+ st.get("haste", 0.0) * 300.0 + st.get("crit", 0.0) * 300.0 + spell_bonus)

## Mercenary Board: 6 candidates around the hero's level, always including at
## least one healer and one tank (concept 9: guaranteed role coverage).
static func roll_board(rng: RandomNumberGenerator, hero_level: int) -> Array:
	var board := []
	var healer_idx := [1, 2, 7]
	var tank_idx := [0, 6]
	board.append(make_merc(rng, tank_idx[rng.randi_range(0, tank_idx.size() - 1)], _merc_level(rng, hero_level)))
	board.append(make_merc(rng, healer_idx[rng.randi_range(0, healer_idx.size() - 1)], _merc_level(rng, hero_level)))
	for i in 4:
		board.append(make_merc(rng, rng.randi_range(0, Db.MERC_TEMPLATES.size() - 1), _merc_level(rng, hero_level)))
	# unique names on one board
	var used := {}
	for m in board:
		while used.has(m["name"]):
			m["name"] = Db.MERC_NAMES[rng.randi_range(0, Db.MERC_NAMES.size() - 1)]
		used[m["name"]] = true
	# shuffle deterministically
	for i in range(board.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = board[i]
		board[i] = board[j]
		board[j] = tmp
	return board

static func _merc_level(rng: RandomNumberGenerator, hero_level: int) -> int:
	return max(1, hero_level + rng.randi_range(-1, 1))

static func spell_tags_text(snap: Dictionary) -> String:
	var names := []
	for s in snap["spells"]:
		var d: Dictionary = Db.SPELLS[s["id"]]
		names.append("%s %s" % [d["name"], _roman(s["lvl"])])
	return ", ".join(names)

static func _roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI"][clamp(n, 0, 6)]
