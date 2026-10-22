class_name Prof
extends RefCounted
## Professions data (spec: Professions & Resource Activities). Everything here is
## tunable data: durations, yields, XP, recipe costs, drop chances. Rules reads it,
## no numbers live in the logic.
##
## Gathering (AFK, solo): mining, herbalism, skinning.
## Crafting: blacksmithing, tailoring, alchemy.
## Cloth and special materials do NOT come from gathering: they drop in combat.

const MAX_LEVEL := 10
## XP needed to go from level i+1 to i+2 (index 0 = level 1 -> 2).
const XP_TO_NEXT := [100, 160, 240, 340, 460, 600, 760, 940, 1140]

const PROFESSIONS := {
	"mining":        {"name": "Горное дело",   "type": "gathering", "icon": "prof_mining"},
	"herbalism":     {"name": "Травничество",  "type": "gathering", "icon": "prof_herbalism"},
	"skinning":      {"name": "Свежевание",    "type": "gathering", "icon": "prof_skinning"},
	"blacksmithing": {"name": "Кузнечное дело", "type": "crafting", "icon": "prof_blacksmithing"},
	"tailoring":     {"name": "Портняжное дело", "type": "crafting", "icon": "prof_tailoring"},
	"alchemy":       {"name": "Алхимия",        "type": "crafting", "icon": "prof_alchemy"},
}
const GATHERING := ["mining", "herbalism", "skinning"]
const CRAFTING := ["blacksmithing", "tailoring", "alchemy"]

## Resource categories for the materials inventory.
const CATEGORIES := [
	["ore", "Руда"], ["herb", "Травы"], ["leather", "Кожа"], ["cloth", "Ткань"],
	["special", "Особые"], ["alchemy", "Алхимия"],
]

## tier: 0 common, 1 uncommon, 2 rare (colour in UI)
const RESOURCES := {
	"copper_ore":       {"name": "Медная руда",       "cat": "ore", "tier": 0},
	"iron_ore":         {"name": "Железная руда",     "cat": "ore", "tier": 0},
	"silver_ore":       {"name": "Серебряная руда",   "cat": "ore", "tier": 1},
	"coal":             {"name": "Уголь",             "cat": "ore", "tier": 1},
	"mithril_fragment": {"name": "Осколок мифрила",   "cat": "ore", "tier": 2},
	"greenleaf":        {"name": "Зеленолист",        "cat": "herb", "tier": 0},
	"bitterroot":       {"name": "Горький корень",    "cat": "herb", "tier": 0},
	"moonflower":       {"name": "Лунный цветок",     "cat": "herb", "tier": 1},
	"redthorn":         {"name": "Красный шип",       "cat": "herb", "tier": 1},
	"spirit_bloom":     {"name": "Цветок духа",       "cat": "herb", "tier": 2},
	"light_hide":       {"name": "Лёгкая шкура",      "cat": "leather", "tier": 0},
	"raw_leather":      {"name": "Сыромятная кожа",   "cat": "leather", "tier": 0},
	"thick_hide":       {"name": "Толстая шкура",     "cat": "leather", "tier": 1},
	"tough_leather":    {"name": "Прочная кожа",      "cat": "leather", "tier": 1},
	"pristine_hide":    {"name": "Безупречная шкура", "cat": "leather", "tier": 2},
	"rough_cloth":      {"name": "Грубая ткань",      "cat": "cloth", "tier": 0},
	"linen_cloth":      {"name": "Льняная ткань",     "cat": "cloth", "tier": 1},
	"fine_cloth":       {"name": "Тонкая ткань",      "cat": "cloth", "tier": 2},
	"boss_core":        {"name": "Ядро босса",        "cat": "special", "tier": 2},
	"enchanted_thread": {"name": "Зачарованная нить", "cat": "special", "tier": 2},
	# consumables (crafted by alchemy, used from the materials screen)
	"minor_strength_potion":   {"name": "Малое зелье силы",          "cat": "alchemy", "tier": 0},
	"minor_recovery_potion":   {"name": "Малое зелье восстановления", "cat": "alchemy", "tier": 0},
	"gatherers_tonic":         {"name": "Тоник собирателя",          "cat": "alchemy", "tier": 1},
	"greater_strength_potion": {"name": "Большое зелье силы",        "cat": "alchemy", "tier": 2},
}

# ---------------------------------------------------------------- gathering

## Selectable durations (seconds) and efficiency (long trips give a bit less per hour,
## so checking in more often pays off slightly).
const DURATIONS := [
	{"sec": 900,   "label": "15 мин", "eff": 1.0},
	{"sec": 3600,  "label": "1 ч",    "eff": 1.0},
	{"sec": 14400, "label": "4 ч",    "eff": 0.9},
	{"sec": 28800, "label": "8 ч",    "eff": 0.85},
]
const LEVEL_YIELD_BONUS := 0.05   # +5% yield per profession level above the location requirement
const YIELD_SPREAD := 0.15        # ±15% random spread per resource

## per_hour: average units per hour; rare: chance per hour to find 1 unit
const LOCATIONS := {
	"abandoned_quarry": {"name": "Заброшенный карьер", "prof": "mining", "req": 1, "xp_per_hour": 100,
		"yields": {"copper_ore": 14, "iron_ore": 10}, "rare": {}},
	"iron_hills": {"name": "Железные холмы", "prof": "mining", "req": 3, "xp_per_hour": 130,
		"yields": {"iron_ore": 14, "coal": 5, "silver_ore": 3}, "rare": {}},
	"old_mountain_mine": {"name": "Старая горная шахта", "prof": "mining", "req": 6, "xp_per_hour": 170,
		"yields": {"iron_ore": 12, "silver_ore": 6}, "rare": {"mithril_fragment": 0.6}},
	"green_meadow": {"name": "Зелёный луг", "prof": "herbalism", "req": 1, "xp_per_hour": 100,
		"yields": {"greenleaf": 14, "bitterroot": 9}, "rare": {}},
	"misty_forest": {"name": "Туманный лес", "prof": "herbalism", "req": 3, "xp_per_hour": 130,
		"yields": {"greenleaf": 10, "moonflower": 5, "redthorn": 5}, "rare": {}},
	"moonlit_grove": {"name": "Лунная роща", "prof": "herbalism", "req": 6, "xp_per_hour": 170,
		"yields": {"moonflower": 8, "redthorn": 8}, "rare": {"spirit_bloom": 0.6}},
	"wild_plains": {"name": "Дикие равнины", "prof": "skinning", "req": 1, "xp_per_hour": 100,
		"yields": {"light_hide": 12, "raw_leather": 10}, "rare": {}},
	"wolf_woods": {"name": "Волчий лес", "prof": "skinning", "req": 3, "xp_per_hour": 130,
		"yields": {"raw_leather": 12, "thick_hide": 6}, "rare": {}},
	"ancient_hunting_grounds": {"name": "Древние охотничьи угодья", "prof": "skinning", "req": 6, "xp_per_hour": 170,
		"yields": {"thick_hide": 9, "tough_leather": 6}, "rare": {"pristine_hide": 0.6}},
}

# ---------------------------------------------------------------- crafting

## Equipment slots: combat loot covers weapon/armor/trinket, crafting covers the rest.
## Crafted gear has fixed stats (no quality RNG): value = Loot.STAT_PER_ILVL * ilvl * q.
const RECIPES := {
	# --- Blacksmithing
	"simple_iron_helmet": {"name": "Простой железный шлем", "prof": "blacksmithing", "req": 1, "gold": 60, "time": 300, "xp": 40,
		"ingredients": {"iron_ore": 10, "raw_leather": 2},
		"item": {"slot": "head", "rarity": 0, "ilvl": 4, "affixes": [["armor", 1.0], ["hp", 0.7]]}},
	"iron_gauntlets": {"name": "Железные рукавицы", "prof": "blacksmithing", "req": 2, "gold": 80, "time": 420, "xp": 50,
		"ingredients": {"copper_ore": 12, "iron_ore": 4, "light_hide": 3},
		"item": {"slot": "hands", "rarity": 0, "ilvl": 5, "affixes": [["armor", 0.8], ["atk", 0.8]]}},
	"iron_chestguard": {"name": "Железный нагрудник", "prof": "blacksmithing", "req": 3, "gold": 150, "time": 900, "xp": 80,
		"ingredients": {"iron_ore": 20, "raw_leather": 4},
		"item": {"slot": "armor", "rarity": 1, "ilvl": 8, "affixes": [["armor", 1.0], ["hp", 1.0]]}},
	"reinforced_greaves": {"name": "Укреплённые поножи", "prof": "blacksmithing", "req": 3, "gold": 120, "time": 600, "xp": 70,
		"ingredients": {"iron_ore": 14, "coal": 3},
		"item": {"slot": "legs", "rarity": 1, "ilvl": 8, "affixes": [["armor", 1.0], ["hp", 0.8]]}},
	"copper_boots": {"name": "Медные сапоги", "prof": "blacksmithing", "req": 4, "gold": 140, "time": 600, "xp": 80,
		"ingredients": {"copper_ore": 16, "thick_hide": 3},
		"item": {"slot": "feet", "rarity": 1, "ilvl": 10, "affixes": [["armor", 0.9], ["haste", 0.8]]}},
	"boss_forged_chestguard": {"name": "Нагрудник, кованный в ядре", "prof": "blacksmithing", "req": 6, "gold": 600, "time": 3600, "xp": 220,
		"ingredients": {"iron_ore": 30, "silver_ore": 5, "boss_core": 1},
		"item": {"slot": "armor", "rarity": 2, "ilvl": 18, "affixes": [["armor", 1.0], ["hp", 1.0], ["atk", 0.8]]}},
	"mithril_helm": {"name": "Мифриловый шлем", "prof": "blacksmithing", "req": 8, "gold": 900, "time": 3600, "xp": 260,
		"ingredients": {"mithril_fragment": 6, "silver_ore": 4, "tough_leather": 3, "boss_core": 1},
		"item": {"slot": "head", "rarity": 2, "ilvl": 24, "affixes": [["armor", 1.0], ["hp", 1.0], ["crit", 0.8]]}},
	# --- Tailoring (cloth comes from combat)
	"rough_cloth_hood": {"name": "Капюшон из грубой ткани", "prof": "tailoring", "req": 1, "gold": 50, "time": 300, "xp": 40,
		"ingredients": {"rough_cloth": 10},
		"item": {"slot": "head", "rarity": 0, "ilvl": 4, "affixes": [["power", 1.0], ["hp", 0.5]]}},
	"rough_cloth_shoes": {"name": "Тканые башмаки", "prof": "tailoring", "req": 2, "gold": 70, "time": 420, "xp": 50,
		"ingredients": {"rough_cloth": 12, "light_hide": 2},
		"item": {"slot": "feet", "rarity": 0, "ilvl": 5, "affixes": [["power", 0.8], ["haste", 0.6]]}},
	"linen_tunic": {"name": "Льняная туника", "prof": "tailoring", "req": 3, "gold": 140, "time": 900, "xp": 80,
		"ingredients": {"linen_cloth": 16, "raw_leather": 2},
		"item": {"slot": "armor", "rarity": 1, "ilvl": 9, "affixes": [["power", 1.0], ["hp", 0.8]]}},
	"linen_trousers": {"name": "Льняные штаны", "prof": "tailoring", "req": 4, "gold": 150, "time": 900, "xp": 85,
		"ingredients": {"linen_cloth": 14, "greenleaf": 4},
		"item": {"slot": "legs", "rarity": 1, "ilvl": 10, "affixes": [["power", 1.0], ["crit", 0.6]]}},
	"fine_bracers": {"name": "Тонкие наручи", "prof": "tailoring", "req": 5, "gold": 220, "time": 1200, "xp": 110,
		"ingredients": {"fine_cloth": 8, "moonflower": 2},
		"item": {"slot": "hands", "rarity": 1, "ilvl": 13, "affixes": [["power", 1.0], ["haste", 0.8]]}},
	"pristine_slippers": {"name": "Туфли из безупречной кожи", "prof": "tailoring", "req": 6, "gold": 400, "time": 1800, "xp": 160,
		"ingredients": {"fine_cloth": 6, "pristine_hide": 2, "thick_hide": 4},
		"item": {"slot": "feet", "rarity": 2, "ilvl": 16, "affixes": [["power", 1.0], ["haste", 1.0], ["hp", 0.6]]}},
	"enchanted_robe": {"name": "Зачарованная мантия", "prof": "tailoring", "req": 7, "gold": 700, "time": 3600, "xp": 240,
		"ingredients": {"fine_cloth": 24, "enchanted_thread": 1},
		"item": {"slot": "armor", "rarity": 2, "ilvl": 20, "affixes": [["power", 1.0], ["hp", 1.0], ["crit", 0.8]]}},
	# --- Alchemy (consumables)
	"minor_strength_potion": {"name": "Малое зелье силы", "prof": "alchemy", "req": 1, "gold": 30, "time": 180, "xp": 30,
		"ingredients": {"greenleaf": 4, "bitterroot": 2}, "output": {"minor_strength_potion": 2}},
	"minor_recovery_potion": {"name": "Малое зелье восстановления", "prof": "alchemy", "req": 2, "gold": 30, "time": 180, "xp": 35,
		"ingredients": {"greenleaf": 2, "bitterroot": 4}, "output": {"minor_recovery_potion": 2}},
	"gatherers_tonic": {"name": "Тоник собирателя", "prof": "alchemy", "req": 3, "gold": 60, "time": 300, "xp": 50,
		"ingredients": {"moonflower": 2, "greenleaf": 3}, "output": {"gatherers_tonic": 1}},
	"greater_strength_potion": {"name": "Большое зелье силы", "prof": "alchemy", "req": 7, "gold": 200, "time": 600, "xp": 120,
		"ingredients": {"spirit_bloom": 1, "redthorn": 4, "boss_core": 1}, "output": {"greater_strength_potion": 2}},
}

## Consumable effects. Buffs apply to expeditions started while they are active.
##   dmg_mult  - all damage of the party
##   heal_mult - all healing of the party
##   gather_yield - next gathering expedition (one charge)
const CONSUMABLES := {
	"minor_strength_potion":   {"effect": "dmg_mult", "value": 1.10, "duration": 7200, "desc": "+10% урона группы на 2 ч"},
	"minor_recovery_potion":   {"effect": "heal_mult", "value": 1.15, "duration": 7200, "desc": "+15% лечения группы на 2 ч"},
	"greater_strength_potion": {"effect": "dmg_mult", "value": 1.20, "duration": 7200, "desc": "+20% урона группы на 2 ч"},
	"gatherers_tonic":         {"effect": "gather_yield", "value": 1.30, "charges": 1, "desc": "+30% ресурсов в следующем сборе"},
}

# ---------------------------------------------------------------- combat drops

## Cloth from normal combat by campaign level: [level_from, resource, chance per kill]
## Tuned so a farm gives roughly 25-35 cloth per hour (a basic tailoring recipe = ~20 min of farming).
const CLOTH_BY_LEVEL := [
	[1,  {"rough_cloth": 0.06}],
	[8,  {"rough_cloth": 0.04, "linen_cloth": 0.05}],
	[18, {"linen_cloth": 0.05, "fine_cloth": 0.05}],
]
const CLOTH_PER_DROP := [1, 1]          # min, max units per successful roll
const CLOTH_ON_CLEAR := 3               # extra cloth of the best tier for clearing a level on push

## Special materials from bosses (never from gathering). Chance per boss kill on farm;
## on the first clear of a level its boss always drops the first entry.
const BOSS_DROPS := {
	"boss_ogre":     {"boss_core": 0.03},
	"boss_lich":     {"boss_core": 0.04, "enchanted_thread": 0.04},
	"boss_warlord":  {"boss_core": 0.05, "enchanted_thread": 0.03},
	"boss_shadow":   {"enchanted_thread": 0.06, "boss_core": 0.04},
	"boss_drake":    {"boss_core": 0.06, "enchanted_thread": 0.04},
	"boss_archlich": {"enchanted_thread": 0.08, "boss_core": 0.08},
}

# ---------------------------------------------------------------- helpers

static func cloth_table(level: int) -> Dictionary:
	var t: Dictionary = CLOTH_BY_LEVEL[0][1]
	for row in CLOTH_BY_LEVEL:
		if level >= row[0]:
			t = row[1]
	return t

static func xp_to_next(level: int) -> int:
	if level >= MAX_LEVEL:
		return 0
	return XP_TO_NEXT[level - 1]

static func duration(sec: int) -> Dictionary:
	for d in DURATIONS:
		if int(d["sec"]) == sec:
			return d
	return {}

static func locations_of(prof: String) -> Array:
	var out := []
	for id in LOCATIONS:
		if LOCATIONS[id]["prof"] == prof:
			out.append(id)
	out.sort_custom(func(a, b): return LOCATIONS[a]["req"] < LOCATIONS[b]["req"])
	return out

static func recipes_of(prof: String) -> Array:
	var out := []
	for id in RECIPES:
		if RECIPES[id]["prof"] == prof:
			out.append(id)
	out.sort_custom(func(a, b): return RECIPES[a]["req"] < RECIPES[b]["req"])
	return out

## Expected units for a gathering trip (UI estimate; the server rolls the real amount).
static func expected_yield(loc_id: String, sec: int, prof_level: int, tonic: bool = false) -> Dictionary:
	var loc: Dictionary = LOCATIONS[loc_id]
	var mult := _yield_mult(loc, sec, prof_level, tonic)
	var out := {}
	for res in loc["yields"]:
		out[res] = int(round(float(loc["yields"][res]) * mult))
	for res in loc["rare"]:
		out[res] = snappedf(float(loc["rare"][res]) * sec / 3600.0, 0.1)
	return out

static func _yield_mult(loc: Dictionary, sec: int, prof_level: int, tonic: bool) -> float:
	var d := duration(sec)
	var hours := sec / 3600.0
	var lvl_bonus: float = 1.0 + LEVEL_YIELD_BONUS * max(0, prof_level - int(loc["req"]))
	return hours * float(d.get("eff", 1.0)) * lvl_bonus * (float(CONSUMABLES["gatherers_tonic"]["value"]) if tonic else 1.0)

static func gather_xp(loc_id: String, sec: int) -> int:
	var d := duration(sec)
	return max(5, int(round(float(LOCATIONS[loc_id]["xp_per_hour"]) * sec / 3600.0 * float(d.get("eff", 1.0)))))

## Crafted equipment item (deterministic stats, only the id is random).
static func make_item(recipe_id: String, item_id: String) -> Dictionary:
	var r: Dictionary = RECIPES[recipe_id]
	var spec: Dictionary = r["item"]
	var affixes := []
	for a in spec["affixes"]:
		var stat: String = a[0]
		var q: float = a[1]
		var value: float
		if Loot.FLAT_STATS.has(stat):
			value = snappedf(Loot.FLAT_STATS[stat] * q, 0.001)
		else:
			value = round(Loot.STAT_PER_ILVL[stat] * int(spec["ilvl"]) * q)
		affixes.append({"stat": stat, "value": value, "q": q})
	return {"id": item_id, "slot": spec["slot"], "name": r["name"], "rarity": int(spec["rarity"]),
		"ilvl": int(spec["ilvl"]), "affixes": affixes, "crafted": true}
