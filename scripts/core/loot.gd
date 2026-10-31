class_name Loot
extends RefCounted
## Gear generation: quality and slot of a drop (Items builds the item itself).
## Weapons have a type (sword, greatsword, shield, staff, bow) with base
## damage, attack speed and the stat the basic attack scales from.

## Slots of mercenary gear.
const SLOTS := ["weapon", "offhand", "armor", "trinket"]
const SLOT_NAMES := {"weapon": "Оружие", "offhand": "Левая рука", "armor": "Тело", "trinket": "Амулет",
	"head": "Голова", "hands": "Руки", "legs": "Ноги", "feet": "Ступни",
	"accessory": "Аксессуар", "accessory1": "Аксессуар", "accessory2": "Аксессуар"}
## All equipment slots of a character. An item of slot "accessory" fits both accessory slots.
const ALL_SLOTS := ["weapon", "offhand", "head", "armor", "hands", "legs", "feet", "trinket", "accessory1", "accessory2"]
## Drop weights per slot (offhand = shields only; swords for the left hand drop as weapons).
const SLOT_WEIGHTS := {"weapon": 2.5, "offhand": 0.7, "armor": 1.5, "trinket": 1.0, "accessory": 1.0,
	"head": 1.5, "hands": 1.5, "legs": 1.5, "feet": 1.5}

## Weapon types.
##   hands: 1 = one-handed (a sword also fits the left hand), 2 = takes both hands
##   stat / coef: the basic attack hits for stat x coef + weapon damage
##   dmg: weapon damage per (item level + 1) for a perfect roll
##   speed: seconds between basic attacks
##   implicit: [stat, value per item level] every item of this type has
const WEAPON_TYPES := {
	"sword":      {"name": "Меч", "hands": 1, "stat": "str", "coef": 0.81, "dmg": 1.63, "speed": 1.3,
		"implicit": ["str", 1.2], },
	"greatsword": {"name": "Двуручный меч", "hands": 2, "stat": "str", "coef": 1.73, "dmg": 4.15, "speed": 3.0,
		"implicit": ["str", 2.4], },
	"shield":     {"name": "Щит", "hands": 1, "offhand": true, "stat": "", "coef": 0.0, "dmg": 0.0, "speed": 0.0,
		"implicit": ["armor", 3.0], },
	"staff":      {"name": "Посох", "hands": 2, "no_attack": true, "stat": "power", "coef": 0.0, "dmg": 0.0, "speed": 0.0,
		"implicit": ["power", 3.8], },
	"bow":        {"name": "Лук", "hands": 2, "stat": "agi", "coef": 1.61, "dmg": 3.36, "speed": 2.8,
		"implicit": ["agi", 2.4], },
}
## A sword in the left hand adds this share of its own damage to every basic attack.
const OFFHAND_SWORD_SHARE := 0.4
## Basic attack without a weapon: strength x coef, every BattleUnit.ATTACK_INTERVAL.
const UNARMED := {"stat": "str", "coef": 1.0, "speed": 1.6}

const STAT_NAMES := {"hp": "Здоровье", "str": "Сила", "agi": "Ловкость", "power": "Сила заклинаний",
	"armor": "Броня", "haste": "Скорость", "crit": "Крит", "atk": "Атака"}
# value of a perfect roll per item level
const STAT_PER_ILVL := {"hp": 28.0, "str": 2.6, "agi": 2.6, "atk": 2.6, "power": 2.6, "armor": 3.0}
const FLAT_STATS := {"haste": 0.05, "crit": 0.04}  # do not scale with ilvl

## Rolls a drop. `table` is a quality table of Items, `role` limits the stats to one role.
static func roll_gear(rng: RandomNumberGenerator, ilvl: int, table: String = "drop", force_slot: String = "", force_type: String = "", role: String = "", force_rarity: int = -1) -> Dictionary:
	var quality := force_rarity if force_rarity >= 0 else _roll_quality(rng, table)
	var slot := force_slot
	if slot == "" and force_type == "":
		slot = _pick_slot(rng, quality)
	return Items.roll(rng, ilvl, quality, slot, force_type, role)

static func _roll_quality(rng: RandomNumberGenerator, table: String) -> int:
	var weights: Array = Items.TABLES[table]
	var total := 0.0
	for w in weights:
		total += float(w)
	var x := rng.randf() * total
	for q in weights.size():
		x -= float(weights[q])
		if x <= 0.0:
			return q
	return 0

## Accessories are rare or better, as trinkets are in Classic.
static func _pick_slot(rng: RandomNumberGenerator, quality: int) -> String:
	var weights := SLOT_WEIGHTS.duplicate()
	if quality < Items.RARE:
		weights.erase("accessory")
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var x := rng.randf() * total
	for k in weights:
		x -= float(weights[k])
		if x <= 0.0:
			return k
	return weights.keys()[0]

## Slot of a worn set this item goes to: a free accessory slot comes first.
static func wear_slot(gear: Dictionary, it: Dictionary) -> String:
	if it["slot"] != "accessory":
		return it["slot"]
	return "accessory2" if gear.get("accessory1") != null and gear.get("accessory2") == null else "accessory1"

static func is_two_handed(item) -> bool:
	return item != null and item.has("wtype") and int(WEAPON_TYPES[item["wtype"]]["hands"]) == 2

## Can this item go into the left hand? Shields and one-handed swords.
static func fits_offhand(item) -> bool:
	return item != null and item.get("wtype", "") in ["shield", "sword"]

## Weapon types a character holds, e.g. ["sword", "shield"]. Used by spell requirements.
static func weapon_types(gear: Dictionary) -> Array:
	var out := []
	for slot in ["weapon", "offhand"]:
		var it = gear.get(slot)
		if it != null and it.has("wtype"):
			out.append(it["wtype"])
	return out

## Basic attack of a character with these final stats and gear: {atk, atk_speed}.
static func attack_of(st: Dictionary, gear: Dictionary) -> Dictionary:
	var main = gear.get("weapon")
	var off = gear.get("offhand")
	var hit := 0.0
	var speed := float(UNARMED["speed"])
	if main != null and WEAPON_TYPES.get(main.get("wtype", ""), {}).get("no_attack", false):
		return {"atk": 0.0, "atk_speed": 0.0}   # staff: no basic attacks, it powers the spells
	if main != null and main.has("wtype") and float(WEAPON_TYPES[main["wtype"]]["dmg"]) > 0.0:
		var wt: Dictionary = WEAPON_TYPES[main["wtype"]]
		hit = float(st.get(wt["stat"], 0.0)) * float(wt["coef"]) + float(main.get("dmg", 0.0))
		speed = float(wt["speed"])
	else:
		hit = float(st.get(UNARMED["stat"], st.get("atk", 0.0))) * float(UNARMED["coef"])
	if off != null and off.get("wtype", "") == "sword":
		hit += OFFHAND_SWORD_SHARE * float(off.get("dmg", 0.0))
	return {"atk": round(hit), "atk_speed": speed, "offhand_atk": OFFHAND_SWORD_SHARE * float(off.get("dmg",0.0)) if off != null and off.get("wtype","") == "sword" else 0.0}

## Short weapon description: "Меч · урон 12 · 1.6 с".
static func weapon_text(item: Dictionary) -> String:
	if not item.has("wtype"):
		return ""
	var wt: Dictionary = WEAPON_TYPES[item["wtype"]]
	var parts := [wt["name"] + (" (двуручное)" if int(wt["hands"]) == 2 else "")]
	if wt.get("no_attack", false):
		parts.append("не атакует, усиливает заклинания")
	elif float(wt["dmg"]) > 0.0:
		parts.append("урон %d · удар раз в %.1f с" % [int(item.get("dmg", 0)), float(wt["speed"])])
		parts.append("растёт от %s" % {"str": "силы", "agi": "ловкости", "power": "силы заклинаний"}[wt["stat"]])
	return " · ".join(parts)

static func affix_text(a: Dictionary) -> String:
	var stat: String = a["stat"]
	if FLAT_STATS.has(stat):
		return "+%d%% %s" % [roundi(a["value"] * 100.0), STAT_NAMES[stat]]
	return "+%d %s" % [int(a["value"]), STAT_NAMES[stat]]

static func item_score(item: Dictionary) -> float:
	var s := float(item.get("dmg", 0.0)) * 1.5 + (40.0 if item.has("effect") else 0.0)
	for a in item["affixes"]:
		var stat: String = a["stat"]
		if FLAT_STATS.has(stat):
			s += a["value"] * 400.0
		elif stat == "hp":
			s += a["value"] / 10.0
		else:
			s += a["value"]
	return s

static func sell_price(item: Dictionary) -> int:
	return max(1, int((5 + item["ilvl"] * 3) * [1, 2, 3, 8, 25, 80][item["rarity"]] * Db.GOLD_MULT))

## Brings an item saved by an older version up to date (v5: weapon types, str instead of atk).
static func upgrade_item(it: Dictionary) -> void:
	for a in it["affixes"]:
		if a["stat"] == "atk":
			a["stat"] = "str"
	if it["slot"] == "weapon" and not it.has("wtype"):
		var by_name := {"Клинок": "sword", "Посох": "staff", "Секира": "greatsword", "Жезл": "staff", "Молот": "greatsword"}
		var wtype: String = by_name.get(str(it.get("name", "")), "sword")
		var wt: Dictionary = WEAPON_TYPES[wtype]
		it["wtype"] = wtype
		it["dmg"] = round(float(wt["dmg"]) * (int(it["ilvl"]) + 1) * 0.9)
