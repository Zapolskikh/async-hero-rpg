class_name Loot
extends RefCounted
## Gear generation: slot, rarity, random affixes with quality rolls (concept 6).

const SLOTS := ["weapon", "armor", "trinket"]
const SLOT_NAMES := {"weapon": "Оружие", "armor": "Тело", "trinket": "Амулет",
	"head": "Голова", "hands": "Руки", "legs": "Ноги", "feet": "Ступни"}
## All equipment slots of a character. Combat loot only drops SLOTS; the rest is crafted.
const ALL_SLOTS := ["weapon", "head", "armor", "hands", "legs", "feet", "trinket"]
const BASE_NAMES := {
	"weapon": ["Клинок", "Посох", "Секира", "Жезл", "Молот"],
	"armor": ["Кираса", "Мантия", "Кольчуга", "Доспех", "Куртка"],
	"trinket": ["Амулет", "Кольцо", "Талисман", "Оберег", "Печать"],
}
const AFFIXES := {
	"weapon": ["power", "atk", "crit", "haste"],
	"armor": ["hp", "armor", "power", "crit"],
	"trinket": ["haste", "crit", "power", "hp"],
}
const STAT_NAMES := {"hp": "Здоровье", "atk": "Атака", "power": "Сила заклинаний",
	"armor": "Броня", "haste": "Скорость", "crit": "Крит"}
# value of a perfect roll per item level
const STAT_PER_ILVL := {"hp": 28.0, "atk": 2.6, "power": 2.6, "armor": 3.0}
const FLAT_STATS := {"haste": 0.05, "crit": 0.04}  # do not scale with ilvl

## rarity_bonus shifts the roll towards better rarities (bosses, first clears).
static func roll_gear(rng: RandomNumberGenerator, ilvl: int, rarity_bonus: float = 0.0, force_slot: String = "") -> Dictionary:
	var r := rng.randf() + rarity_bonus
	var rarity := 0
	if r > 0.985:
		rarity = 3
	elif r > 0.88:
		rarity = 2
	elif r > 0.6:
		rarity = 1
	var slot: String = force_slot if force_slot != "" else SLOTS[rng.randi_range(0, SLOTS.size() - 1)]
	var n_affixes: int = [1, 2, 3, 3][rarity]
	var pool: Array = AFFIXES[slot].duplicate()
	var affixes := []
	for i in n_affixes:
		var stat: String = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(stat)
		var q := rng.randf_range(0.85, 1.0) if rarity == 3 else rng.randf_range(0.6, 1.0)
		var mult := 1.25 if rarity == 3 else 1.0
		var value: float
		if FLAT_STATS.has(stat):
			value = snappedf(FLAT_STATS[stat] * q * mult, 0.001)
		else:
			value = round(STAT_PER_ILVL[stat] * ilvl * q * mult)
		affixes.append({"stat": stat, "value": value, "q": snappedf(q, 0.01)})
	var names: Array = BASE_NAMES[slot]
	return {
		"id": "i%08x%08x" % [rng.randi(), rng.randi()],  # deterministic: same seed -> same item
		"slot": slot,
		"name": names[rng.randi_range(0, names.size() - 1)],
		"rarity": rarity,
		"ilvl": ilvl,
		"affixes": affixes,
	}

static func affix_text(a: Dictionary) -> String:
	var stat: String = a["stat"]
	if FLAT_STATS.has(stat):
		return "+%d%% %s" % [roundi(a["value"] * 100.0), STAT_NAMES[stat]]
	return "+%d %s" % [int(a["value"]), STAT_NAMES[stat]]

static func item_score(item: Dictionary) -> float:
	var s := 0.0
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
	return int((5 + item["ilvl"] * 3) * [1, 3, 8, 25][item["rarity"]])
