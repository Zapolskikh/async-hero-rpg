class_name Roster
extends RefCounted
## Builds combat snapshots for the hero and guild mercenaries (concept 8-9).

const HERO_COLOR := "#3fa7d6"
const MERC_COLORS := ["#e0a458", "#7bc96f", "#d36fa3", "#6fb3d3", "#c9c95b", "#9d8cff"]
const MERC_STAT_FACTOR := 0.92   # NPCs are decent, but a good real build should beat them

## Quality tiers of guild mercenaries. Same level, very different strength:
## gear rarity, number of items, spell levels and how sensible the rotation is.
const TIERS := [
	{"name": "Слабый",  "chance": 0.20, "rarity_bonus": -0.45, "items": [1, 2], "stat": 0.88, "spell": -1, "shuffle": 0.5},
	{"name": "Обычный", "chance": 0.55, "rarity_bonus": -0.15, "items": [2, 3], "stat": 0.93, "spell": 0, "shuffle": 0.15},
	{"name": "Сильный", "chance": 0.20, "rarity_bonus": 0.15,  "items": [3, 3], "stat": 1.0,  "spell": 0, "shuffle": 0.0},
	{"name": "Элитный", "chance": 0.05, "rarity_bonus": 0.45,  "items": [3, 3], "stat": 1.05, "spell": 1, "shuffle": 0.0},
]

static func roll_tier(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	for i in TIERS.size():
		r -= TIERS[i]["chance"]
		if r <= 0.0:
			return i
	return 1

## Adds gear affixes on top of base stats.
static func apply_gear(base: Dictionary, gear: Dictionary) -> Dictionary:
	var st := base.duplicate()
	for slot in gear.keys():
		var item = gear[slot]
		if item == null:
			continue
		for a in item["affixes"]:
			st[a["stat"]] = st.get(a["stat"], 0.0) + a["value"]
	return st

static func empty_gear() -> Dictionary:
	var g := {}
	for slot in Loot.SLOTS:
		g[slot] = null
	return g

static func spell_best_level(collection: Dictionary, sid: String) -> int:
	if not collection.has(sid):
		return 0
	return int(collection[sid].get("lvl", 0))

## Final stats: base + gear affixes + basic attack from the weapon (atk, atk_speed).
static func combat_stats(base: Dictionary, gear: Dictionary) -> Dictionary:
	var st := apply_gear(base, gear)
	st.merge(Loot.attack_of(st, gear), true)
	return st

static func hero_stats(hero: Dictionary) -> Dictionary:
	var gear: Dictionary = hero["equipped"]
	var talents: Dictionary = hero.get("talents", {})
	var weapons := Loot.weapon_types(gear)
	var st := apply_gear(Db.hero_base_stats(hero["level"]), gear)
	Talents.apply_stats(st, talents, weapons)
	st.merge(Loot.attack_of(st, gear), true)
	st["atk"] = round(st["atk"] * Talents.attack_mult(talents, weapons))
	return st

static func hero_snapshot(hero: Dictionary, collection: Dictionary) -> Dictionary:
	var spells := []
	for sid in hero["rotation"]:
		spells.append({"id": sid, "lvl": max(1, spell_best_level(collection, sid))})
	return {
		"name": hero["name"], "color": HERO_COLOR, "npc": false, "is_hero": true,
		"role": "Герой", "level": hero["level"], "sprite": "hero", "ranged": "bow" in Loot.weapon_types(hero["equipped"]),
		"stats": hero_stats(hero), "spells": spells, "target": "front",
		"weapons": Loot.weapon_types(hero["equipped"]),
	}

static func make_merc(rng: RandomNumberGenerator, template_idx: int, level: int, tier: int = -1) -> Dictionary:
	var t: Dictionary = Db.MERC_TEMPLATES[template_idx]
	if tier < 0:
		tier = roll_tier(rng)
	var tr: Dictionary = TIERS[tier]
	var base := Db.hero_base_stats(level)
	for k in ["hp", "str", "agi", "power", "armor"]:
		base[k] = round(base[k] * t["stat"].get(k, 1.0) * MERC_STAT_FACTOR * tr["stat"] * rng.randf_range(0.95, 1.05))
	base["crit"] = 0.05
	# gear: some slots may stay empty for weak mercenaries; weapons follow the template
	var gear := empty_gear()
	var wts: Array = t.get("weapons", [])
	var slots: Array = ["weapon", "armor", "trinket"]
	if wts.size() > 1:
		slots.insert(1, "offhand")
	var n_items := rng.randi_range(tr["items"][0], tr["items"][1]) + (1 if wts.size() > 1 else 0)
	for i in range(slots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = slots[i]
		slots[i] = slots[j]
		slots[j] = tmp
	for i in min(n_items, slots.size()):
		var slot: String = slots[i]
		var wtype := ""
		if slot == "weapon" and wts.size() > 0:
			wtype = wts[0]
		elif slot == "offhand":
			wtype = wts[1]
		gear[slot] = Loot.roll_gear(rng, level, tr["rarity_bonus"], slot, wtype)
	# spells: levels vary, weak ones sometimes have a clumsy rotation order
	var spell_lvl := baseline_spell_level(level) + int(tr["spell"])
	var spells := []
	for sid in t["spells"]:
		spells.append({"id": sid, "lvl": max(1, spell_lvl - rng.randi_range(0, 1))})
	if rng.randf() < tr["shuffle"]:
		spells.reverse()
	return {
		"name": Db.MERC_NAMES[rng.randi_range(0, Db.MERC_NAMES.size() - 1)],
		"color": MERC_COLORS[rng.randi_range(0, MERC_COLORS.size() - 1)],
		"npc": true, "role": t["role"], "level": level, "tier": tier,
		"base_stats": base, "gear": gear, "stats": combat_stats(base, gear),
		"weapons": Loot.weapon_types(gear),
		"spells": spells, "target": "front",
		"id": "m%d" % rng.randi(), "template": template_idx,
		"sprite": t.get("sprite", ""), "ranged": t.get("ranged", false),
	}

## Guild mercenaries on the board grow with the hero (same build, new gear).
static func relevel(rng: RandomNumberGenerator, merc: Dictionary, level: int) -> Dictionary:
	var fresh := make_merc(rng, int(merc.get("template", 0)), level, int(merc.get("tier", 1)))
	for k in ["name", "color", "id"]:
		fresh[k] = merc[k]
	return fresh

## Fills fields for mercenaries saved by older versions.
static func ensure_merc(m: Dictionary) -> void:
	ensure_visuals(m)
	m["level"] = int(m["level"])
	m["tier"] = int(m.get("tier", 1))
	if not m.has("gear") or typeof(m["gear"]) != TYPE_DICTIONARY:
		m["gear"] = empty_gear()
	if not m.has("base_stats"):
		m["base_stats"] = m["stats"]
	if not m["gear"].has("offhand"):
		m["gear"]["offhand"] = null
	for slot in m["gear"]:
		var it = m["gear"][slot]
		if it != null:
			it["rarity"] = int(it["rarity"])
			it["ilvl"] = int(it["ilvl"])
			Loot.upgrade_item(it)
	# v5: strength and agility replace the flat attack stat
	var b: Dictionary = m["base_stats"]
	if not b.has("str"):
		var a: float = float(b.get("atk", b.get("power", 15.0)))
		b["str"] = a
		b["agi"] = a
		b.erase("atk")
		m["stats"] = combat_stats(b, m["gear"])
	if not m.has("weapons"):
		m["weapons"] = Loot.weapon_types(m["gear"])
	for sp in m["spells"]:
		sp["lvl"] = int(sp["lvl"])

## Spell level a typical character of this hero level has (fusion progress).
static func baseline_spell_level(level: int) -> int:
	return min(8, 1 + int(level / 4))

## Power a typical (normal tier, no gear) mercenary of this level would have.
static func expected_power(level: int) -> float:
	var st := Db.hero_base_stats(level)
	var spell_lvl := baseline_spell_level(level)
	return st["hp"] / 8.0 + st["str"] * 2.0 + st["power"] * 2.5 + st["armor"] * 1.5 + st["crit"] * 300.0 + 30.0 * spell_lvl

const ROLE_SPRITES := {"Герой": "hero", "Танк": "tank", "Лекарь": "healer", "Пиромант": "pyromancer",
	"Ядовик": "poisoner_ally", "Боец": "fighter", "Страж": "guard", "Паладин": "paladin", "Охотник": "hunter"}
const RANGED_ROLES := ["Лекарь", "Пиромант", "Охотник"]

## Fills visual fields for snapshots saved before sprites existed.
static func ensure_visuals(snap: Dictionary) -> void:
	if not snap.has("sprite") or snap["sprite"] == "":
		snap["sprite"] = ROLE_SPRITES.get(snap.get("role", ""), "hero")
	if not snap.has("ranged"):
		snap["ranged"] = snap.get("role", "") in RANGED_ROLES

## Single "Power" number shown in UI. Deliberately crude: the concept says
## success depends on composition, not just Power.
static func power_score(snap: Dictionary) -> int:
	var st: Dictionary = snap["stats"]
	var spell_bonus := 0.0
	for s in snap["spells"]:
		spell_bonus += 10.0 * s["lvl"]
	var atk_rate: float = float(st.get("atk", 0.0)) * 1.6 / max(0.5, float(st.get("atk_speed", 1.6)))
	return int(st["hp"] / 8.0 + atk_rate * 2.0 + st["power"] * 2.5 + st.get("armor", 0) * 1.5
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
	return ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][clamp(n, 0, 10)]
