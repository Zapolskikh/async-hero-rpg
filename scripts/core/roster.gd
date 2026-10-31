class_name Roster
extends RefCounted
## Builds combat snapshots for the hero and guild mercenaries (concept 8-9).

const HERO_COLOR := "#3fa7d6"
const MERC_COLORS := ["#e0a458", "#7bc96f", "#d36fa3", "#6fb3d3", "#c9c95b", "#9d8cff"]
const MERC_STAT_FACTOR := 0.92   # NPCs are decent, but a good real build should beat them

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

## Paper doll: tint of an item layer by rarity (layers are drawn in greys).
## Slots whose art CharacterRig draws on the body.
const GEAR_LAYERS := ["head", "armor", "hands", "legs", "feet", "weapon", "offhand"]
const LOOK_TINTS := ["#8f96a3", "#c9cdd4", "#5fc46a", "#5b9be8", "#b06ef0", "#f0aa40"]

## Layers drawn over doll_body for this gear, back to front: [[layer, tint or ""], ...].
static func look(gear: Dictionary) -> Array:
	var out := []
	var off = gear.get("offhand")
	var main = gear.get("weapon")
	if off != null and off.get("wtype", "") == "sword":
		out.append(["offhand_sword", ""])
	out.append(["body", ""])
	for slot in ["legs", "feet", "armor", "trinket", "head", "hands"]:
		var it = gear.get(slot)
		if it != null:
			out.append([slot, LOOK_TINTS[clamp(int(it["rarity"]), 0, 5)]])
	if main != null and main.has("wtype"):
		out.append(["w_" + str(main["wtype"]), ""])
	if off != null and off.get("wtype", "") == "shield":
		out.append(["shield", LOOK_TINTS[clamp(int(off["rarity"]), 0, 5)]])
	for slot in GEAR_LAYERS:
		var it = gear.get(slot)
		if it != null and it.has("look"):
			out.append(["gear:" + slot, it["look"]])
	return out

## Worn cosmetics as colours for the views: {"glow": "#hex", "aura": "#hex"}.
static func cosmetic_colors(cos: Dictionary) -> Dictionary:
	var out := {}
	for slot in cos:
		if Shop.COSMETICS.has(cos[slot]):
			out[slot] = Shop.COSMETICS[cos[slot]]["color"]
	return out

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

static func hero_stats(hero: Dictionary, potion: Dictionary = {}) -> Dictionary:
	var gear: Dictionary = hero["equipped"]
	var talents: Dictionary = hero.get("talents", {})
	var weapons := Loot.weapon_types(gear)
	var st := apply_gear(Db.hero_base_stats(hero["level"]), gear)
	if potion.has("stat"):
		var stat: String = potion["stat"]
		st[stat] = float(st.get(stat, 0.0)) + float(potion["value"]) if Loot.FLAT_STATS.has(stat) else float(st[stat]) * (1.0 + float(potion["value"]))
	Talents.apply_stats(st, talents, weapons)
	st.merge(Loot.attack_of(st, gear), true)
	st["atk"] = round(st["atk"] * Talents.attack_mult(talents, weapons))
	return st

static func hero_snapshot(hero: Dictionary, collection: Dictionary) -> Dictionary:
	var spells := []
	var settings: Dictionary = hero.get("spell_settings", {})
	for sid in hero["rotation"]:
		var e := {"id": sid, "lvl": max(1, spell_best_level(collection, sid))}
		if settings.has(sid) and settings[sid].has("threshold"):
			e["threshold"] = float(settings[sid]["threshold"])
		spells.append(e)
	return {
		"name": hero["name"], "color": HERO_COLOR, "npc": false, "is_hero": true,
		"role": "Герой", "level": hero["level"], "sprite": "hero", "ranged": "bow" in Loot.weapon_types(hero["equipped"]),
		"stats": hero_stats(hero), "spells": spells, "target": "front",
		"weapons": Loot.weapon_types(hero["equipped"]),
		"talents": hero.get("talents", {}).duplicate(),
		"effects": Items.effects_of(hero["equipped"]),
		"look": look(hero["equipped"]),
		"cosmetics": cosmetic_colors(hero.get("cosmetics", {})),
		"appearance": CharacterAppearance.normalize(hero.get("appearance")),
	}

static func make_merc(rng: RandomNumberGenerator, _template_idx: int, level: int, _tier: int = -1) -> Dictionary:
	return MercGenerator.make(rng, level)

## Guild mercenaries on the board grow with the hero (same build, new gear).
static func relevel(rng: RandomNumberGenerator, merc: Dictionary, level: int) -> Dictionary:
	var fresh := MercGenerator.make(rng, level, merc.get("weapons",[]))
	fresh["spells"] = merc["spells"].duplicate(true)
	for entry in fresh["spells"]:
		entry["lvl"] = maxi(int(entry["lvl"]),baseline_spell_level(level))
	for k in ["name", "color", "id", "appearance"]:
		if not merc.has(k):
			continue
		fresh[k] = merc[k]
	return fresh

## Fills fields for mercenaries saved by older versions.
static func ensure_merc(m: Dictionary) -> void:
	ensure_visuals(m)
	m["level"] = int(m["level"])
	m.erase("tier")
	if not m.has("talents"):
		m["talents"] = {}
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
	st["atk"] = st["str"]
	return _power_value(st, st["power"], POWER_SPELL_WEIGHT, 3 * baseline_spell_level(level), 0)

const POWER_SPELL_WEIGHT := 2.5 # Doubled for a staff: it has no basic attack, all damage is spells.
const POWER_PER_EFFECT := 0.06  # A unique effect has no stats, it is priced as a share of the total.
const ROLE_SPRITES := {"Герой": "hero", "Танк": "tank", "Лекарь": "healer", "Пиромант": "pyromancer",
	"Ядовик": "poisoner_ally", "Боец": "fighter", "Страж": "guard", "Паладин": "paladin", "Охотник": "hunter"}
const RANGED_ROLES := ["Лекарь", "Пиромант", "Охотник"]

## Fills visual fields for snapshots saved before sprites existed.
static func ensure_visuals(snap: Dictionary) -> void:
	snap["appearance"] = CharacterAppearance.normalize(snap.get("appearance", CharacterAppearance.for_identity(str(snap.get("id", snap.get("name", "")))) if snap.get("npc", false) else {}))
	if not snap.has("sprite") or snap["sprite"] == "":
		snap["sprite"] = ROLE_SPRITES.get(snap.get("role", ""), "hero")
	if not snap.has("ranged"):
		snap["ranged"] = snap.get("role", "") in RANGED_ROLES

## Single "Power" number shown in UI and used to compare items. It follows combat: damage
## comes from what this build really hits with, crit and haste multiply it, armor multiplies
## health. Still an estimate: the concept says success depends on composition, not just Power.
static func power_score(snap: Dictionary) -> int:
	var weapons: Array = snap.get("weapons", [])
	var talents: Dictionary = snap.get("talents", {})
	var st: Dictionary = snap["stats"]
	var stat_sum := 0.0
	var scaled := 0
	var spell_levels := 0
	for s in snap["spells"]:
		if not Db.spell_usable(s["id"], weapons, talents):
			continue
		spell_levels += int(s["lvl"])
		var d: Dictionary = Db.SPELLS[s["id"]]
		if float(d.get("mult", 0.0)) > 0.0 or d.has("tick_mult"):
			stat_sum += Db.spell_stat_value(s["id"], st)
			scaled += 1
	var spell_stat: float = stat_sum / scaled if scaled > 0 else float(st["power"])
	var weight: float = POWER_SPELL_WEIGHT * 2.0 if "staff" in weapons else (POWER_SPELL_WEIGHT if scaled > 0 else 0.0)
	return _power_value(st, spell_stat, weight, spell_levels, snap.get("effects", []).size())

## spell_stat: what the spells scale from, weight: what it is worth for this build.
static func _power_value(st: Dictionary, spell_stat: float, weight: float, spell_levels: int, effects: int) -> int:
	var attack: float = float(st.get("atk", 0.0)) * 1.6 / max(0.5, float(st.get("atk_speed", 1.6)))
	var damage: float = attack * 2.0 + spell_stat * weight
	var offense: float = damage * (1.0 + float(st.get("crit", 0.0))) * (1.0 + float(st.get("haste", 0.0)))
	var toughness: float = float(st["hp"]) * (1.0 + float(st.get("armor", 0.0)) / 100.0) / 12.0
	return int((offense + toughness + 10.0 * spell_levels) * (1.0 + POWER_PER_EFFECT * effects))

## Six independent random candidates near the hero level.
static func roll_board(rng: RandomNumberGenerator, hero_level: int) -> Array:
	var board := []
	var names := {}
	for i in 6:
		var m := MercGenerator.make(rng, _merc_level(rng, hero_level))
		while names.has(m["name"]):
			m["name"] = Db.MERC_NAMES[rng.randi_range(0, Db.MERC_NAMES.size()-1)]
		names[m["name"]] = true
		board.append(m)
	return board

static func starter_party(rng: RandomNumberGenerator) -> Array:
	var party := []
	var names := {}
	for s in MercGenerator.STARTERS:
		var m := MercGenerator.make(rng, 1, s["weapons"], s["talents"], s["spells"])
		while names.has(m["name"]):
			m["name"] = Db.MERC_NAMES[rng.randi_range(0, Db.MERC_NAMES.size()-1)]
		names[m["name"]] = true
		party.append(m)
	return party

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
