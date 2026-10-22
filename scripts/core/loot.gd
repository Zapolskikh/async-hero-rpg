class_name Loot
extends RefCounted
## Gear generation: slot, rarity, random affixes with quality rolls (concept 6).
## Weapons also have a type (sword, greatsword, shield, staff, bow) with base
## damage, attack speed and the stat the basic attack scales from.

## Slots combat loot drops into. Head, hands, legs and feet are crafted.
const SLOTS := ["weapon", "offhand", "armor", "trinket"]
const SLOT_NAMES := {"weapon": "Оружие", "offhand": "Левая рука", "armor": "Тело", "trinket": "Амулет",
	"head": "Голова", "hands": "Руки", "legs": "Ноги", "feet": "Ступни"}
## All equipment slots of a character.
const ALL_SLOTS := ["weapon", "offhand", "head", "armor", "hands", "legs", "feet", "trinket"]
## Drop weights per slot (offhand = shields only; swords for the left hand drop as weapons).
## Head, hands, legs and feet are mostly crafted, but drop now and then too.
const SLOT_WEIGHTS := {"weapon": 3.0, "offhand": 1.0, "armor": 2.0, "trinket": 2.0,
	"head": 0.12, "hands": 0.12, "legs": 0.12, "feet": 0.12}

## Weapon types.
##   hands: 1 = one-handed (a sword also fits the left hand), 2 = takes both hands
##   stat / coef: the basic attack hits for stat x coef + weapon damage
##   dmg: weapon damage per (item level + 1) for a perfect roll
##   speed: seconds between basic attacks
##   implicit: [stat, value per item level] every item of this type has
const WEAPON_TYPES := {
	"sword":      {"name": "Меч", "hands": 1, "stat": "str", "coef": 0.81, "dmg": 1.63, "speed": 1.3,
		"implicit": ["str", 1.2], "names": ["Меч", "Клинок", "Палаш", "Сабля"],
		"affixes": ["str", "crit", "haste", "hp"]},
	"greatsword": {"name": "Двуручный меч", "hands": 2, "stat": "str", "coef": 1.73, "dmg": 4.15, "speed": 3.0,
		"implicit": ["str", 2.4], "names": ["Двуручник", "Цвайхандер", "Секира", "Молот"],
		"affixes": ["str", "crit", "hp", "armor"]},
	"shield":     {"name": "Щит", "hands": 1, "offhand": true, "stat": "", "coef": 0.0, "dmg": 0.0, "speed": 0.0,
		"implicit": ["armor", 3.0], "names": ["Щит", "Баклер", "Павеза", "Эгида"],
		"affixes": ["hp", "armor", "str", "power"]},
	"staff":      {"name": "Посох", "hands": 2, "no_attack": true, "stat": "power", "coef": 0.0, "dmg": 0.0, "speed": 0.0,
		"implicit": ["power", 3.8], "names": ["Посох", "Жезл", "Скипетр", "Шест"],
		"affixes": ["power", "haste", "crit", "hp"]},
	"bow":        {"name": "Лук", "hands": 2, "stat": "agi", "coef": 1.61, "dmg": 3.36, "speed": 2.8,
		"implicit": ["agi", 2.4], "names": ["Лук", "Длинный лук", "Самострел", "Рекурсив"],
		"affixes": ["agi", "crit", "haste", "hp"]},
}
const WEAPON_WEIGHTS := {"sword": 3.0, "greatsword": 2.0, "staff": 2.0, "bow": 2.0}
## A sword in the left hand adds this share of its own damage to every basic attack.
const OFFHAND_SWORD_SHARE := 0.4
## Basic attack without a weapon: strength x coef, every BattleUnit.ATTACK_INTERVAL.
const UNARMED := {"stat": "str", "coef": 1.0, "speed": 1.6}

const BASE_NAMES := {
	"armor": ["Кираса", "Мантия", "Кольчуга", "Доспех", "Куртка"],
	"trinket": ["Амулет", "Кольцо", "Талисман", "Оберег", "Печать"],
	"head": ["Шлем", "Капюшон", "Венец"],
	"hands": ["Перчатки", "Наручи", "Рукавицы"],
	"legs": ["Поножи", "Штаны", "Набедренник"],
	"feet": ["Сапоги", "Ботинки", "Туфли"],
}
const AFFIXES := {
	"armor": ["hp", "armor", "power", "crit"],
	"trinket": ["haste", "crit", "power", "hp", "str", "agi"],
	"head": ["hp", "armor", "power", "crit"],
	"hands": ["str", "agi", "armor", "crit"],
	"legs": ["hp", "armor", "str", "agi"],
	"feet": ["haste", "armor", "hp", "agi"],
}
const STAT_NAMES := {"hp": "Здоровье", "str": "Сила", "agi": "Ловкость", "power": "Сила заклинаний",
	"armor": "Броня", "haste": "Скорость", "crit": "Крит", "atk": "Атака"}
# value of a perfect roll per item level
const STAT_PER_ILVL := {"hp": 28.0, "str": 2.6, "agi": 2.6, "atk": 2.6, "power": 2.6, "armor": 3.0}
const FLAT_STATS := {"haste": 0.05, "crit": 0.04}  # do not scale with ilvl

static func _pick_weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var x := rng.randf() * total
	for k in weights:
		x -= float(weights[k])
		if x <= 0.0:
			return k
	return weights.keys()[0]

static func _roll_affix(rng: RandomNumberGenerator, stat: String, ilvl: int, rarity: int) -> Dictionary:
	var q := rng.randf_range(0.85, 1.0) if rarity == 3 else rng.randf_range(0.6, 1.0)
	var mult := 1.25 if rarity == 3 else 1.0
	var value: float
	if FLAT_STATS.has(stat):
		value = snappedf(FLAT_STATS[stat] * q * mult, 0.001)
	else:
		value = round(STAT_PER_ILVL[stat] * ilvl * q * mult)
	return {"stat": stat, "value": value, "q": snappedf(q, 0.01)}

## rarity_bonus shifts the roll towards better rarities (bosses, first clears).
## force_slot picks the slot; force_type picks the weapon type ("" = random).
static func roll_gear(rng: RandomNumberGenerator, ilvl: int, rarity_bonus: float = 0.0, force_slot: String = "", force_type: String = "") -> Dictionary:
	var r := rng.randf() + rarity_bonus
	var rarity := 0
	if r > 0.985:
		rarity = 3
	elif r > 0.88:
		rarity = 2
	elif r > 0.6:
		rarity = 1
	var slot: String = force_slot if force_slot != "" else _pick_weighted(rng, SLOT_WEIGHTS)
	if force_type != "":
		slot = "weapon"  # the weapon branch below sets the real slot from the type
	var n_affixes: int = [1, 2, 3, 3][rarity]
	var item := {
		"id": "i%08x%08x" % [rng.randi(), rng.randi()],  # deterministic: same seed -> same item
		"slot": slot, "rarity": rarity, "ilvl": ilvl, "affixes": [],
	}
	var pool: Array
	if slot == "weapon" or slot == "offhand":
		var wtype: String = force_type
		if wtype == "":
			wtype = "shield" if slot == "offhand" else _pick_weighted(rng, WEAPON_WEIGHTS)
		var wt: Dictionary = WEAPON_TYPES[wtype]
		item["slot"] = "offhand" if wt.get("offhand", false) else "weapon"
		item["wtype"] = wtype
		var names: Array = wt["names"]
		item["name"] = names[rng.randi_range(0, names.size() - 1)]
		if wt["dmg"] > 0.0:
			var q := rng.randf_range(0.8, 1.0) * (1.15 if rarity == 3 else 1.0) * (1.0 + 0.04 * rarity)
			item["dmg"] = round(wt["dmg"] * (ilvl + 1) * q)
		# implicit stat of the type (does not count towards the affix number)
		var imp := _roll_affix(rng, wt["implicit"][0], ilvl, rarity)
		imp["value"] = round(imp["value"] / STAT_PER_ILVL[imp["stat"]] * wt["implicit"][1])
		imp["imp"] = true
		item["affixes"].append(imp)
		pool = (wt["affixes"] as Array).duplicate()
	else:
		var names: Array = BASE_NAMES[slot]
		item["name"] = names[rng.randi_range(0, names.size() - 1)]
		pool = (AFFIXES[slot] as Array).duplicate()
	for i in n_affixes:
		if pool.is_empty():
			break
		var stat: String = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(stat)
		item["affixes"].append(_roll_affix(rng, stat, ilvl, rarity))
	return item

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
	return {"atk": round(hit), "atk_speed": speed}

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
	var s := float(item.get("dmg", 0.0)) * 1.5
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
	return max(1, int((5 + item["ilvl"] * 3) * [1, 3, 8, 25][item["rarity"]] * Db.GOLD_MULT))

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
