class_name Prof
extends RefCounted
## Professions data (spec: Professions & Resource Activities). Everything here is
## tunable data: durations, yields, XP, recipe costs, drop chances. Rules reads it,
## no numbers live in the logic.
##
## Gathering (AFK, solo): mining, herbalism, skinning.
## Crafting: blacksmithing, tailoring, alchemy. A hero practises one of them (craft_prof in the profile).
## Cloth and special materials do NOT come from gathering: they drop in combat.

const MAX_LEVEL := 10
## Hidden roll of crafted gear, on all its bonus stats and damage.
const CRAFT_ROLL := [0.8, 1.3]
const CRAFT_ROLE := {"str": "melee", "agi": "ranged", "power": "caster"}
const CRAFT_HP_SHARE := 0.375   # of the budget of rare and epic gear
const CRAFT_ANY_STATS := ["hp", "armor", "crit", "haste"]   # with the main stat: the pool of random stats
## Random stats by quality.
const CRAFT_RANDOM_STATS := [0, 0, 1, 1, 2, 0]
## The first choice of a crafting profession is free, changing it costs this much gold.
const CRAFT_CHANGE_GOLD := 3000
## XP needed to go from level i+1 to i+2 (index 0 = level 1 -> 2).
const XP_TO_NEXT := [100, 160, 240, 340, 460, 600, 760, 940, 1140]

const PROFESSIONS := {
	"mining":        {"name": "Горное дело",   "type": "gathering", "icon": "prof_mining"},
	"herbalism":     {"name": "Травничество",  "type": "gathering", "icon": "prof_herbalism"},
	"skinning":      {"name": "Свежевание",    "type": "gathering", "icon": "prof_skinning"},
	"blacksmithing": {"name": "Кузнечное дело", "type": "crafting", "icon": "prof_blacksmithing",
		"desc": "Латы на силу и почти всё оружие: мечи, двуручники, посохи, щиты."},
	"tailoring":     {"name": "Портняжное дело", "type": "crafting", "icon": "prof_tailoring",
		"desc": "Ткань на силу заклинаний, кожа на ловкость и луки. Для магов, лекарей и стрелков."},
	"alchemy":       {"name": "Алхимия",        "type": "crafting", "icon": "prof_alchemy",
		"desc": "Зелья на всю группу: урон, лечение, здоровье. Подходит любому герою."},
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
	"strength_potion":         {"name": "Зелье силы",                "cat": "alchemy", "tier": 1},
	"recovery_potion":         {"name": "Зелье восстановления",      "cat": "alchemy", "tier": 1},
	"minor_fortitude_potion":  {"name": "Малое зелье стойкости",     "cat": "alchemy", "tier": 0},
	"fortitude_potion":        {"name": "Зелье стойкости",           "cat": "alchemy", "tier": 2},
	"titan_flask":             {"name": "Настой титанов",            "cat": "alchemy", "tier": 2},
	"elixir_bull": {"name": "Эликсир быка", "cat": "alchemy", "tier": 0},
	"greater_elixir_bull": {"name": "Большой эликсир быка", "cat": "alchemy", "tier": 1},
	"elixir_cat": {"name": "Эликсир кошки", "cat": "alchemy", "tier": 0},
	"greater_elixir_cat": {"name": "Большой эликсир кошки", "cat": "alchemy", "tier": 1},
	"elixir_mind": {"name": "Эликсир разума", "cat": "alchemy", "tier": 0},
	"greater_elixir_mind": {"name": "Большой эликсир разума", "cat": "alchemy", "tier": 1},
	"elixir_stone": {"name": "Эликсир камня", "cat": "alchemy", "tier": 0},
	"greater_elixir_stone": {"name": "Большой эликсир камня", "cat": "alchemy", "tier": 1},
	"elixir_life": {"name": "Эликсир жизни", "cat": "alchemy", "tier": 0},
	"greater_elixir_life": {"name": "Большой эликсир жизни", "cat": "alchemy", "tier": 1},
	"elixir_eagle": {"name": "Эликсир орла", "cat": "alchemy", "tier": 0},
	"greater_elixir_eagle": {"name": "Большой эликсир орла", "cat": "alchemy", "tier": 1},
	"elixir_wind": {"name": "Эликсир ветра", "cat": "alchemy", "tier": 0},
	"greater_elixir_wind": {"name": "Большой эликсир ветра", "cat": "alchemy", "tier": 1},
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
	"abandoned_quarry": {"name": "Заброшенный карьер", "prof": "mining", "req": 1, "xp_per_hour": 60,
		"yields": {"copper_ore": 14, "iron_ore": 10}, "rare": {}},
	"iron_hills": {"name": "Железные холмы", "prof": "mining", "req": 3, "xp_per_hour": 78,
		"yields": {"iron_ore": 14, "coal": 5, "silver_ore": 3}, "rare": {}},
	"old_mountain_mine": {"name": "Старая горная шахта", "prof": "mining", "req": 6, "xp_per_hour": 102,
		"yields": {"iron_ore": 12, "silver_ore": 6}, "rare": {"mithril_fragment": 0.6}},
	"green_meadow": {"name": "Зелёный луг", "prof": "herbalism", "req": 1, "xp_per_hour": 60,
		"yields": {"greenleaf": 14, "bitterroot": 9}, "rare": {}},
	"misty_forest": {"name": "Туманный лес", "prof": "herbalism", "req": 3, "xp_per_hour": 78,
		"yields": {"greenleaf": 10, "moonflower": 5, "redthorn": 5}, "rare": {}},
	"moonlit_grove": {"name": "Лунная роща", "prof": "herbalism", "req": 6, "xp_per_hour": 102,
		"yields": {"moonflower": 8, "redthorn": 8}, "rare": {"spirit_bloom": 0.6}},
	"wild_plains": {"name": "Дикие равнины", "prof": "skinning", "req": 1, "xp_per_hour": 60,
		"yields": {"light_hide": 12, "raw_leather": 10}, "rare": {}},
	"wolf_woods": {"name": "Волчий лес", "prof": "skinning", "req": 3, "xp_per_hour": 78,
		"yields": {"raw_leather": 12, "thick_hide": 6}, "rare": {}},
	"ancient_hunting_grounds": {"name": "Древние охотничьи угодья", "prof": "skinning", "req": 6, "xp_per_hour": 102,
		"yields": {"thick_hide": 9, "tough_leather": 6}, "rare": {"pristine_hide": 0.6}},
}

# ---------------------------------------------------------------- crafting

## "rarity" is the quality of the result: common and uncommon recipes are cheap, rare and epic
## ones take a high profession level, many materials, gold and hours. See make_item for stats:
## "ilvl" and "affixes" count only on drop_only recipes.
## drop_only recipes come from clears: "clear" is the level whose first clear teaches the
## recipe, the rest of the time they are a rare boss drop.
const RECIPES := {
	# --- Blacksmithing
	"plain_helm": {"name": "Простой шлем", "prof": "blacksmithing", "req": 1, "gold": 15, "time": 120, "xp": 40,
		"ingredients": {"copper_ore": 4},
		"item": {"slot": "head", "atype": "plate", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_cuirass": {"name": "Простые латы", "prof": "blacksmithing", "req": 1, "gold": 25, "time": 120, "xp": 40,
		"ingredients": {"copper_ore": 7},
		"item": {"slot": "armor", "atype": "plate", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_gauntlets": {"name": "Простые рукавицы", "prof": "blacksmithing", "req": 1, "gold": 12, "time": 120, "xp": 40,
		"ingredients": {"copper_ore": 3},
		"item": {"slot": "hands", "atype": "plate", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_greaves": {"name": "Простые поножи", "prof": "blacksmithing", "req": 1, "gold": 20, "time": 120, "xp": 40,
		"ingredients": {"copper_ore": 5},
		"item": {"slot": "legs", "atype": "plate", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_sabatons": {"name": "Простые латные сапоги", "prof": "blacksmithing", "req": 1, "gold": 12, "time": 120, "xp": 40,
		"ingredients": {"copper_ore": 3},
		"item": {"slot": "feet", "atype": "plate", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_sword": {"name": "Простой меч", "prof": "blacksmithing", "req": 1, "gold": 20, "time": 120, "xp": 40,
		"ingredients": {"copper_ore": 5},
		"item": {"wtype": "sword", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_greatsword": {"name": "Простой двуручник", "prof": "blacksmithing", "req": 1, "gold": 30, "time": 120, "xp": 40,
		"ingredients": {"copper_ore": 8},
		"item": {"wtype": "greatsword", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_shield": {"name": "Простой щит", "prof": "blacksmithing", "req": 1, "gold": 20, "time": 120, "xp": 40,
		"ingredients": {"copper_ore": 5},
		"item": {"wtype": "shield", "rarity": 1, "ilvl": 1, "affixes": []}},
	"simple_iron_helmet": {"name": "Простой железный шлем", "prof": "blacksmithing", "req": 1, "gold": 60, "time": 300, "xp": 80,
		"ingredients": {"iron_ore": 10, "raw_leather": 2},
		"item": {"slot": "head", "rarity": 2, "ilvl": 6, "affixes": [["armor", 1.0], ["hp", 0.7]]}},
	"iron_gauntlets": {"name": "Железные рукавицы", "prof": "blacksmithing", "req": 2, "gold": 80, "time": 420, "xp": 100,
		"ingredients": {"copper_ore": 12, "iron_ore": 4, "light_hide": 3},
		"item": {"slot": "hands", "rarity": 2, "ilvl": 10, "affixes": [["armor", 0.8], ["str", 0.8]]}},
	"iron_chestguard": {"name": "Железный нагрудник", "prof": "blacksmithing", "req": 5, "gold": 600, "time": 7200, "xp": 320,
		"ingredients": {"iron_ore": 40, "raw_leather": 8},
		"item": {"slot": "armor", "rarity": 3, "ilvl": 16, "affixes": [["armor", 1.0], ["hp", 1.0]]}},
	"reinforced_greaves": {"name": "Укреплённые поножи", "prof": "blacksmithing", "req": 5, "gold": 600, "time": 7200, "xp": 280,
		"ingredients": {"iron_ore": 28, "coal": 6},
		"item": {"slot": "legs", "rarity": 3, "ilvl": 16, "affixes": [["armor", 1.0], ["hp", 0.8]]}},
	"copper_boots": {"name": "Медные сапоги", "prof": "blacksmithing", "req": 5, "gold": 600, "time": 7200, "xp": 320,
		"ingredients": {"copper_ore": 32, "thick_hide": 6},
		"item": {"slot": "feet", "rarity": 3, "ilvl": 20, "affixes": [["armor", 0.9], ["haste", 0.8]]}},
	"boss_forged_chestguard": {"name": "Нагрудник, кованный в ядре", "prof": "blacksmithing", "req": 8, "gold": 3000, "time": 28800, "xp": 880, "drop_only": true, "clear": 15,
		"ingredients": {"iron_ore": 90, "silver_ore": 15, "boss_core": 1},
		"item": {"slot": "armor", "rarity": 4, "ilvl": 38, "affixes": [["armor", 1.0], ["hp", 1.0], ["str", 0.8]]}},
	"iron_sword": {"name": "Железный меч", "prof": "blacksmithing", "req": 2, "gold": 90, "time": 480, "xp": 110,
		"ingredients": {"iron_ore": 12, "raw_leather": 2},
		"item": {"wtype": "sword", "rarity": 2, "ilvl": 12, "affixes": [["str", 0.8]]}},
	"iron_shield": {"name": "Железный щит", "prof": "blacksmithing", "req": 5, "gold": 600, "time": 7200, "xp": 280,
		"ingredients": {"iron_ore": 32, "light_hide": 8},
		"item": {"wtype": "shield", "rarity": 3, "ilvl": 18, "affixes": [["hp", 0.8]]}},
	"steel_greatsword": {"name": "Стальной двуручник", "prof": "blacksmithing", "req": 5, "gold": 780, "time": 7200, "xp": 480,
		"ingredients": {"iron_ore": 48, "coal": 12, "tough_leather": 4},
		"item": {"wtype": "greatsword", "rarity": 3, "ilvl": 26, "affixes": [["crit", 0.7]]}},
	"core_blade": {"name": "Клинок из ядра", "prof": "blacksmithing", "req": 8, "gold": 4500, "time": 28800, "xp": 1040, "drop_only": true, "clear": 20,
		"ingredients": {"silver_ore": 30, "mithril_fragment": 9, "boss_core": 1},
		"item": {"wtype": "sword", "rarity": 4, "ilvl": 44, "affixes": [["str", 1.0], ["crit", 0.8]]}},
	"mithril_helm": {"name": "Мифриловый шлем", "prof": "blacksmithing", "req": 8, "gold": 4500, "time": 28800, "xp": 1040, "drop_only": true, "clear": 25,
		"ingredients": {"mithril_fragment": 18, "silver_ore": 12, "tough_leather": 9, "boss_core": 1},
		"item": {"slot": "head", "rarity": 4, "ilvl": 48, "affixes": [["armor", 1.0], ["hp", 1.0], ["crit", 0.8]]}},
	"steel_helm": {"name": "Стальной шлем", "prof": "blacksmithing", "req": 5, "gold": 720, "time": 7200, "xp": 440,
		"ingredients": {"iron_ore": 40, "coal": 10, "tough_leather": 2},
		"item": {"slot": "head", "rarity": 3, "ilvl": 28, "affixes": [["armor", 1.0], ["str", 0.8]]}},
	"steel_gauntlets": {"name": "Стальные перчатки", "prof": "blacksmithing", "req": 8, "gold": 2500, "time": 28800, "xp": 600,
		"ingredients": {"iron_ore": 66, "silver_ore": 12, "tough_leather": 6},
		"item": {"slot": "hands", "rarity": 4, "ilvl": 34, "affixes": [["armor", 1.0], ["str", 1.0], ["crit", 0.7]]}},
	"tower_shield": {"name": "Башенный щит", "prof": "blacksmithing", "req": 8, "gold": 2500, "time": 28800, "xp": 640,
		"ingredients": {"iron_ore": 78, "silver_ore": 15, "thick_hide": 12},
		"item": {"wtype": "shield", "rarity": 4, "ilvl": 36, "affixes": [["hp", 1.0], ["str", 0.8]]}},
	"runed_sabatons": {"name": "Рунные сапоги", "prof": "blacksmithing", "req": 8, "gold": 2600, "time": 28800, "xp": 800,
		"ingredients": {"silver_ore": 30, "coal": 24, "tough_leather": 9},
		"item": {"slot": "feet", "rarity": 4, "ilvl": 38, "affixes": [["armor", 1.0], ["haste", 1.0], ["str", 0.8]]}},
	"mithril_greaves": {"name": "Мифриловые поножи", "prof": "blacksmithing", "req": 8, "gold": 3800, "time": 28800, "xp": 960,
		"ingredients": {"mithril_fragment": 12, "silver_ore": 24, "tough_leather": 9},
		"item": {"slot": "legs", "rarity": 4, "ilvl": 44, "affixes": [["armor", 1.0], ["hp", 1.0], ["str", 0.8]]}},
	"mithril_greatsword": {"name": "Мифриловый двуручник", "prof": "blacksmithing", "req": 9, "gold": 5000, "time": 28800, "xp": 1120, "drop_only": true, "clear": 28,
		"ingredients": {"mithril_fragment": 24, "silver_ore": 30, "boss_core": 1},
		"item": {"wtype": "greatsword", "rarity": 4, "ilvl": 50, "affixes": [["str", 1.0], ["crit", 0.9]]}},
	"plain_staff": {"name": "Простой посох", "prof": "blacksmithing", "req": 1, "gold": 20, "time": 120, "xp": 40,
		"ingredients": {"copper_ore": 5},
		"item": {"wtype": "staff", "rarity": 1, "ilvl": 1, "affixes": []}},
	"apprentice_staff": {"name": "Посох ученика", "prof": "blacksmithing", "req": 5, "gold": 600, "time": 7200, "xp": 280,
		"ingredients": {"iron_ore": 16, "greenleaf": 12},
		"item": {"wtype": "staff", "rarity": 3, "ilvl": 18, "affixes": [["haste", 0.6]]}},
	"moonweave_staff": {"name": "Посох лунного плетения", "prof": "blacksmithing", "req": 8, "gold": 4500, "time": 28800, "xp": 1040, "drop_only": true, "clear": 20,
		"ingredients": {"silver_ore": 30, "moonflower": 18, "enchanted_thread": 1},
		"item": {"wtype": "staff", "rarity": 4, "ilvl": 44, "affixes": [["power", 1.0], ["haste", 0.8]]}},
	# --- Tailoring (cloth comes from combat)
	"plain_hood": {"name": "Простой капюшон", "prof": "tailoring", "req": 1, "gold": 12, "time": 120, "xp": 40,
		"ingredients": {"rough_cloth": 3},
		"item": {"slot": "head", "atype": "cloth", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_robe": {"name": "Простая роба", "prof": "tailoring", "req": 1, "gold": 20, "time": 120, "xp": 40,
		"ingredients": {"rough_cloth": 6},
		"item": {"slot": "armor", "atype": "cloth", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_gloves": {"name": "Простые перчатки", "prof": "tailoring", "req": 1, "gold": 10, "time": 120, "xp": 40,
		"ingredients": {"rough_cloth": 2},
		"item": {"slot": "hands", "atype": "cloth", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_trousers": {"name": "Простые штаны", "prof": "tailoring", "req": 1, "gold": 15, "time": 120, "xp": 40,
		"ingredients": {"rough_cloth": 4},
		"item": {"slot": "legs", "atype": "cloth", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_shoes": {"name": "Простые башмаки", "prof": "tailoring", "req": 1, "gold": 10, "time": 120, "xp": 40,
		"ingredients": {"rough_cloth": 2},
		"item": {"slot": "feet", "atype": "cloth", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_cap": {"name": "Кожаная шапка", "prof": "tailoring", "req": 1, "gold": 12, "time": 120, "xp": 40,
		"ingredients": {"light_hide": 3},
		"item": {"slot": "head", "atype": "leather", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_jerkin": {"name": "Кожаная куртка", "prof": "tailoring", "req": 1, "gold": 20, "time": 120, "xp": 40,
		"ingredients": {"light_hide": 6},
		"item": {"slot": "armor", "atype": "leather", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_mitts": {"name": "Кожаные перчатки", "prof": "tailoring", "req": 1, "gold": 10, "time": 120, "xp": 40,
		"ingredients": {"light_hide": 2},
		"item": {"slot": "hands", "atype": "leather", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_breeches": {"name": "Кожаные штаны", "prof": "tailoring", "req": 1, "gold": 15, "time": 120, "xp": 40,
		"ingredients": {"light_hide": 4},
		"item": {"slot": "legs", "atype": "leather", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_boots": {"name": "Кожаные сапоги", "prof": "tailoring", "req": 1, "gold": 10, "time": 120, "xp": 40,
		"ingredients": {"light_hide": 2},
		"item": {"slot": "feet", "atype": "leather", "rarity": 1, "ilvl": 1, "affixes": []}},
	"plain_bow": {"name": "Простой лук", "prof": "tailoring", "req": 1, "gold": 20, "time": 120, "xp": 40,
		"ingredients": {"light_hide": 5},
		"item": {"wtype": "bow", "rarity": 1, "ilvl": 1, "affixes": []}},
	"rough_cloth_hood": {"name": "Капюшон из грубой ткани", "prof": "tailoring", "req": 1, "gold": 50, "time": 300, "xp": 80,
		"ingredients": {"rough_cloth": 10},
		"item": {"slot": "head", "rarity": 2, "ilvl": 6, "affixes": [["power", 1.0], ["hp", 0.5]]}},
	"rough_cloth_shoes": {"name": "Тканые башмаки", "prof": "tailoring", "req": 2, "gold": 70, "time": 420, "xp": 100,
		"ingredients": {"rough_cloth": 12, "light_hide": 2},
		"item": {"slot": "feet", "rarity": 2, "ilvl": 10, "affixes": [["power", 0.8], ["haste", 0.6]]}},
	"linen_tunic": {"name": "Льняная туника", "prof": "tailoring", "req": 5, "gold": 600, "time": 7200, "xp": 320,
		"ingredients": {"linen_cloth": 32, "raw_leather": 4},
		"item": {"slot": "armor", "rarity": 3, "ilvl": 18, "affixes": [["power", 1.0], ["hp", 0.8]]}},
	"linen_trousers": {"name": "Льняные штаны", "prof": "tailoring", "req": 5, "gold": 600, "time": 7200, "xp": 340,
		"ingredients": {"linen_cloth": 28, "greenleaf": 8},
		"item": {"slot": "legs", "rarity": 3, "ilvl": 20, "affixes": [["power", 1.0], ["crit", 0.6]]}},
	"fine_bracers": {"name": "Тонкие наручи", "prof": "tailoring", "req": 5, "gold": 660, "time": 7200, "xp": 440,
		"ingredients": {"fine_cloth": 16, "moonflower": 4},
		"item": {"slot": "hands", "rarity": 3, "ilvl": 28, "affixes": [["power", 1.0], ["haste", 0.8]]}},
	"pristine_slippers": {"name": "Туфли из безупречной кожи", "prof": "tailoring", "req": 8, "gold": 2500, "time": 28800, "xp": 640,
		"ingredients": {"fine_cloth": 18, "pristine_hide": 6, "thick_hide": 12},
		"item": {"slot": "feet", "rarity": 4, "ilvl": 34, "affixes": [["power", 1.0], ["haste", 1.0], ["hp", 0.6]]}},
	"hunting_bow": {"name": "Охотничий лук", "prof": "tailoring", "req": 2, "gold": 90, "time": 480, "xp": 110,
		"ingredients": {"raw_leather": 6, "rough_cloth": 6},
		"item": {"wtype": "bow", "rarity": 2, "ilvl": 12, "affixes": [["agi", 0.8]]}},
	"pristine_longbow": {"name": "Безупречный длинный лук", "prof": "tailoring", "req": 8, "gold": 3500, "time": 28800, "xp": 880, "drop_only": true, "clear": 15,
		"ingredients": {"pristine_hide": 18, "fine_cloth": 12},
		"item": {"wtype": "bow", "rarity": 4, "ilvl": 38, "affixes": [["agi", 1.0], ["crit", 0.8]]}},
	"enchanted_robe": {"name": "Зачарованная мантия", "prof": "tailoring", "req": 8, "gold": 3500, "time": 28800, "xp": 960, "drop_only": true, "clear": 25,
		"ingredients": {"fine_cloth": 72, "enchanted_thread": 1},
		"item": {"slot": "armor", "rarity": 4, "ilvl": 42, "affixes": [["power", 1.0], ["hp", 1.0], ["crit", 0.8]]}},
	"mooncloth_hood": {"name": "Капюшон лунной ткани", "prof": "tailoring", "req": 5, "gold": 720, "time": 7200, "xp": 440,
		"ingredients": {"linen_cloth": 28, "fine_cloth": 8, "moonflower": 6},
		"item": {"slot": "head", "rarity": 3, "ilvl": 28, "affixes": [["power", 1.0], ["hp", 0.8]]}},
	"ranger_cowl": {"name": "Капюшон следопыта", "prof": "tailoring", "req": 5, "gold": 720, "time": 7200, "xp": 440,
		"ingredients": {"tough_leather": 10, "thick_hide": 12, "linen_cloth": 8},
		"item": {"slot": "head", "rarity": 3, "ilvl": 28, "affixes": [["agi", 1.0], ["crit", 0.8]]}},
	"ranger_gloves": {"name": "Перчатки следопыта", "prof": "tailoring", "req": 5, "gold": 660, "time": 7200, "xp": 440,
		"ingredients": {"tough_leather": 8, "thick_hide": 10},
		"item": {"slot": "hands", "rarity": 3, "ilvl": 28, "affixes": [["agi", 1.0], ["haste", 0.8]]}},
	"ranger_boots": {"name": "Сапоги следопыта", "prof": "tailoring", "req": 8, "gold": 2500, "time": 28800, "xp": 640,
		"ingredients": {"tough_leather": 21, "pristine_hide": 3, "thick_hide": 18},
		"item": {"slot": "feet", "rarity": 4, "ilvl": 34, "affixes": [["agi", 1.0], ["haste", 1.0], ["hp", 0.6]]}},
	"ranger_leggings": {"name": "Поножи следопыта", "prof": "tailoring", "req": 8, "gold": 2800, "time": 28800, "xp": 800,
		"ingredients": {"tough_leather": 27, "pristine_hide": 6, "fine_cloth": 18},
		"item": {"slot": "legs", "rarity": 4, "ilvl": 40, "affixes": [["agi", 1.0], ["hp", 1.0], ["crit", 0.7]]}},
	"mooncloth_leggings": {"name": "Штаны лунной ткани", "prof": "tailoring", "req": 8, "gold": 2800, "time": 28800, "xp": 800,
		"ingredients": {"fine_cloth": 48, "moonflower": 18, "spirit_bloom": 3},
		"item": {"slot": "legs", "rarity": 4, "ilvl": 40, "affixes": [["power", 1.0], ["hp", 1.0], ["crit", 0.7]]}},
	"starweave_cowl": {"name": "Звёздный капюшон", "prof": "tailoring", "req": 8, "gold": 3800, "time": 28800, "xp": 960, "drop_only": true, "clear": 28,
		"ingredients": {"fine_cloth": 60, "enchanted_thread": 1},
		"item": {"slot": "head", "rarity": 4, "ilvl": 46, "affixes": [["power", 1.0], ["crit", 0.9], ["hp", 0.8]]}},
	"shadowhide_hood": {"name": "Капюшон из тени", "prof": "tailoring", "req": 8, "gold": 3800, "time": 28800, "xp": 960, "drop_only": true, "clear": 28,
		"ingredients": {"pristine_hide": 15, "tough_leather": 24, "enchanted_thread": 1},
		"item": {"slot": "head", "rarity": 4, "ilvl": 46, "affixes": [["agi", 1.0], ["crit", 0.9], ["hp", 0.8]]}},
	# --- Alchemy (consumables)
	"minor_strength_potion": {"name": "Малое зелье силы", "prof": "alchemy", "req": 1, "gold": 30, "time": 180, "xp": 60,
		"ingredients": {"greenleaf": 4, "bitterroot": 2}, "output": {"minor_strength_potion": 2}},
	"minor_recovery_potion": {"name": "Малое зелье восстановления", "prof": "alchemy", "req": 2, "gold": 30, "time": 180, "xp": 70,
		"ingredients": {"greenleaf": 2, "bitterroot": 4}, "output": {"minor_recovery_potion": 2}},
	"gatherers_tonic": {"name": "Тоник собирателя", "prof": "alchemy", "req": 3, "gold": 60, "time": 300, "xp": 100,
		"ingredients": {"moonflower": 2, "greenleaf": 3}, "output": {"gatherers_tonic": 1}},
	"elixir_bull": {"name": "Эликсир быка", "prof": "alchemy", "req": 2, "gold": 40, "time": 180, "xp": 80,
		"ingredients": {"bitterroot": 4, "greenleaf": 2}, "output": {"elixir_bull": 3}},
	"greater_elixir_bull": {"name": "Большой эликсир быка", "prof": "alchemy", "req": 6, "gold": 120, "time": 360, "xp": 170,
		"ingredients": {"redthorn": 4, "bitterroot": 3}, "output": {"greater_elixir_bull": 3}},
	"elixir_cat": {"name": "Эликсир кошки", "prof": "alchemy", "req": 2, "gold": 40, "time": 180, "xp": 80,
		"ingredients": {"greenleaf": 4, "bitterroot": 2}, "output": {"elixir_cat": 3}},
	"greater_elixir_cat": {"name": "Большой эликсир кошки", "prof": "alchemy", "req": 6, "gold": 120, "time": 360, "xp": 170,
		"ingredients": {"redthorn": 3, "moonflower": 2}, "output": {"greater_elixir_cat": 3}},
	"elixir_mind": {"name": "Эликсир разума", "prof": "alchemy", "req": 2, "gold": 40, "time": 180, "xp": 80,
		"ingredients": {"greenleaf": 5, "bitterroot": 1}, "output": {"elixir_mind": 3}},
	"greater_elixir_mind": {"name": "Большой эликсир разума", "prof": "alchemy", "req": 6, "gold": 120, "time": 360, "xp": 170,
		"ingredients": {"moonflower": 4, "greenleaf": 3}, "output": {"greater_elixir_mind": 3}},
	"elixir_stone": {"name": "Эликсир камня", "prof": "alchemy", "req": 3, "gold": 40, "time": 180, "xp": 80,
		"ingredients": {"bitterroot": 5, "greenleaf": 1}, "output": {"elixir_stone": 3}},
	"greater_elixir_stone": {"name": "Большой эликсир камня", "prof": "alchemy", "req": 7, "gold": 120, "time": 360, "xp": 170,
		"ingredients": {"bitterroot": 6, "moonflower": 3}, "output": {"greater_elixir_stone": 3}},
	"elixir_life": {"name": "Эликсир жизни", "prof": "alchemy", "req": 3, "gold": 40, "time": 180, "xp": 80,
		"ingredients": {"greenleaf": 3, "bitterroot": 3}, "output": {"elixir_life": 3}},
	"greater_elixir_life": {"name": "Большой эликсир жизни", "prof": "alchemy", "req": 7, "gold": 120, "time": 360, "xp": 170,
		"ingredients": {"redthorn": 3, "greenleaf": 5}, "output": {"greater_elixir_life": 3}},
	"elixir_eagle": {"name": "Эликсир орла", "prof": "alchemy", "req": 4, "gold": 40, "time": 180, "xp": 80,
		"ingredients": {"moonflower": 2, "greenleaf": 3}, "output": {"elixir_eagle": 3}},
	"greater_elixir_eagle": {"name": "Большой эликсир орла", "prof": "alchemy", "req": 8, "gold": 120, "time": 360, "xp": 170,
		"ingredients": {"moonflower": 4, "spirit_bloom": 1}, "output": {"greater_elixir_eagle": 3}},
	"elixir_wind": {"name": "Эликсир ветра", "prof": "alchemy", "req": 4, "gold": 40, "time": 180, "xp": 80,
		"ingredients": {"redthorn": 2, "greenleaf": 3}, "output": {"elixir_wind": 3}},
	"greater_elixir_wind": {"name": "Большой эликсир ветра", "prof": "alchemy", "req": 8, "gold": 120, "time": 360, "xp": 170,
		"ingredients": {"redthorn": 4, "spirit_bloom": 1}, "output": {"greater_elixir_wind": 3}},
	"minor_fortitude_potion": {"name": "Малое зелье стойкости", "prof": "alchemy", "req": 3, "gold": 50, "time": 240, "xp": 100,
		"ingredients": {"bitterroot": 6, "redthorn": 1}, "output": {"minor_fortitude_potion": 2}},
	"strength_potion": {"name": "Зелье силы", "prof": "alchemy", "req": 4, "gold": 90, "time": 300, "xp": 130,
		"ingredients": {"redthorn": 3, "greenleaf": 4}, "output": {"strength_potion": 2}},
	"recovery_potion": {"name": "Зелье восстановления", "prof": "alchemy", "req": 5, "gold": 110, "time": 360, "xp": 160,
		"ingredients": {"moonflower": 3, "bitterroot": 4}, "output": {"recovery_potion": 2}},
	"fortitude_potion": {"name": "Зелье стойкости", "prof": "alchemy", "req": 6, "gold": 150, "time": 420, "xp": 200,
		"ingredients": {"redthorn": 3, "moonflower": 3}, "output": {"fortitude_potion": 2}},
	"greater_strength_potion": {"name": "Большое зелье силы", "prof": "alchemy", "req": 7, "gold": 200, "time": 600, "xp": 240,
		"ingredients": {"spirit_bloom": 1, "redthorn": 4}, "output": {"greater_strength_potion": 2}},
	"titan_flask": {"name": "Настой титанов", "prof": "alchemy", "req": 9, "gold": 400, "time": 900, "xp": 360, "drop_only": true, "clear": 25,
		"ingredients": {"spirit_bloom": 2, "redthorn": 6, "boss_core": 1}, "output": {"titan_flask": 3}},
}

## Consumable effects. Buffs apply to expeditions started while they are active. Only one
## potion works at a time, a new one replaces it; the gathering tonic does not count.
##   dmg_mult  - all damage of the party
##   heal_mult - all healing of the party
##   hp_mult   - maximum health of the party
##   hero_stat - one stat of the hero: a share of it, or flat for haste and crit
##   gather_yield - next gathering expedition (one charge)
const CONSUMABLES := {
	"minor_strength_potion":   {"effect": "dmg_mult", "value": 1.10, "duration": 7200, "desc": "+10% урона группы на 2 ч"},
	"minor_recovery_potion":   {"effect": "heal_mult", "value": 1.15, "duration": 7200, "desc": "+15% лечения группы на 2 ч"},
	"strength_potion":         {"effect": "dmg_mult", "value": 1.15, "duration": 7200, "desc": "+15% урона группы на 2 ч"},
	"greater_strength_potion": {"effect": "dmg_mult", "value": 1.20, "duration": 7200, "desc": "+20% урона группы на 2 ч"},
	"titan_flask":             {"effect": "dmg_mult", "value": 1.30, "duration": 7200, "desc": "+30% урона группы на 2 ч"},
	"recovery_potion":         {"effect": "heal_mult", "value": 1.30, "duration": 7200, "desc": "+30% лечения группы на 2 ч"},
	"elixir_bull": {"effect": "hero_stat", "stat": "str", "value": 0.10, "duration": 7200, "desc": "+10% силы героя на 2 ч"},
	"greater_elixir_bull": {"effect": "hero_stat", "stat": "str", "value": 0.20, "duration": 7200, "desc": "+20% силы героя на 2 ч"},
	"elixir_cat": {"effect": "hero_stat", "stat": "agi", "value": 0.10, "duration": 7200, "desc": "+10% ловкости героя на 2 ч"},
	"greater_elixir_cat": {"effect": "hero_stat", "stat": "agi", "value": 0.20, "duration": 7200, "desc": "+20% ловкости героя на 2 ч"},
	"elixir_mind": {"effect": "hero_stat", "stat": "power", "value": 0.10, "duration": 7200, "desc": "+10% силы заклинаний героя на 2 ч"},
	"greater_elixir_mind": {"effect": "hero_stat", "stat": "power", "value": 0.20, "duration": 7200, "desc": "+20% силы заклинаний героя на 2 ч"},
	"elixir_stone": {"effect": "hero_stat", "stat": "armor", "value": 0.25, "duration": 7200, "desc": "+25% брони героя на 2 ч"},
	"greater_elixir_stone": {"effect": "hero_stat", "stat": "armor", "value": 0.50, "duration": 7200, "desc": "+50% брони героя на 2 ч"},
	"elixir_life": {"effect": "hero_stat", "stat": "hp", "value": 0.10, "duration": 7200, "desc": "+10% здоровья героя на 2 ч"},
	"greater_elixir_life": {"effect": "hero_stat", "stat": "hp", "value": 0.20, "duration": 7200, "desc": "+20% здоровья героя на 2 ч"},
	"elixir_eagle": {"effect": "hero_stat", "stat": "crit", "value": 0.05, "duration": 7200, "desc": "+5% крита героя на 2 ч"},
	"greater_elixir_eagle": {"effect": "hero_stat", "stat": "crit", "value": 0.10, "duration": 7200, "desc": "+10% крита героя на 2 ч"},
	"elixir_wind": {"effect": "hero_stat", "stat": "haste", "value": 0.05, "duration": 7200, "desc": "+5% скорости героя на 2 ч"},
	"greater_elixir_wind": {"effect": "hero_stat", "stat": "haste", "value": 0.10, "duration": 7200, "desc": "+10% скорости героя на 2 ч"},
	"minor_fortitude_potion":  {"effect": "hp_mult", "value": 1.10, "duration": 7200, "desc": "+10% здоровья группы на 2 ч"},
	"fortitude_potion":        {"effect": "hp_mult", "value": 1.20, "duration": 7200, "desc": "+20% здоровья группы на 2 ч"},
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
	"boss_titan":      {"boss_core": 0.06, "enchanted_thread": 0.03},
	"boss_plague":     {"enchanted_thread": 0.06, "boss_core": 0.05},
	"boss_hierophant": {"enchanted_thread": 0.07, "boss_core": 0.05},
	"boss_wraith":     {"enchanted_thread": 0.07, "boss_core": 0.06},
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

## What a crafted item carries on top of its armor, by quality:
##   common: nothing; uncommon: one random stat
##   rare: health, the main stat and one random stat; epic: the same with two random stats
## Random stats come on top of the budget, each on its own line, even if the item already
## has that stat. A hidden roll scales the result. Gear is made at the crafter's level.
## drop_only recipes are the exception: a known item with known stats. Without rng: a typical result.
static func make_item(recipe_id: String, item_id: String, ilvl: int, rng: RandomNumberGenerator = null) -> Dictionary:
	var r: Dictionary = RECIPES[recipe_id]
	var spec: Dictionary = r["item"]
	var quality := int(spec["rarity"])
	var fixed: bool = r.get("drop_only", false)
	var wtype: String = spec.get("wtype", "")
	var slot: String = spec.get("slot", "")
	if wtype != "":
		slot = "offhand" if Loot.WEAPON_TYPES[wtype].get("offhand", false) else "weapon"
	var atype: String = spec.get("atype", "")
	if atype == "" and wtype == "":
		atype = ("leather" if _has_stat(spec, "agi") else "cloth") if r["prof"] == "tailoring" else "plate"
	var main := _main_stat(wtype, atype)
	var shares := {}
	if fixed:
		ilvl = int(spec["ilvl"])
		var total := 0.0
		for a in spec["affixes"]:
			total += float(a[1])
		for a in spec["affixes"]:
			shares[a[0]] = float(a[1]) / total
	elif quality >= Items.RARE:
		shares = {main: 1.0 - CRAFT_HP_SHARE, "hp": CRAFT_HP_SHARE}
	elif quality == Items.UNCOMMON and rng == null:
		shares = {main: 1.0}
	var tier := Items.tier_of(ilvl) + 1
	var look: String = "crafted_" + recipe_id
	if quality == Items.COMMON:
		look = "%s_t%d" % [wtype, tier] if wtype != "" else "%s_%s_t%d" % [atype, slot, tier]
	var it := Items.assemble(item_id, r["name"], slot, wtype, atype, CRAFT_ROLE[main], quality, ilvl, shares, look)
	if rng != null and not fixed and quality >= Items.UNCOMMON:
		for i in CRAFT_RANDOM_STATS[quality]:
			var pool: Array = [main] + CRAFT_ANY_STATS
			var stat: String = pool[rng.randi_range(0, pool.size() - 1)]
			var share := rng.randf_range(0.7, 1.0) if quality == Items.UNCOMMON else rng.randf_range(0.3, 0.5)
			it["affixes"].append({"stat": stat, "value": Items.stat_value(stat, share, quality, slot, ilvl)})
		var roll := rng.randf_range(CRAFT_ROLL[0], CRAFT_ROLL[1])
		for a in it["affixes"]:
			if not a.get("imp", false):
				a["value"] = snappedf(a["value"] * roll, 0.001) if Loot.FLAT_STATS.has(a["stat"]) else round(a["value"] * roll)
		if it.has("dmg"):
			it["dmg"] = round(it["dmg"] * roll)
	it["crafted"] = true
	return it

static func _has_stat(spec: Dictionary, stat: String) -> bool:
	return spec["affixes"].any(func(a): return a[0] == stat)

## Blacksmiths work for strength, tailors for agility or spell power; a staff is a smith's work.
static func _main_stat(wtype: String, atype: String) -> String:
	if wtype != "":
		return {"bow": "agi", "staff": "power"}.get(wtype, "str")
	return {"leather": "agi", "cloth": "power"}.get(atype, "str")

# ---------------------------------------------------------------- rare drops

## Per kill: a gathering resource of the level's tier (small chance), and a
## drop-only recipe (very small; bosses more often). Recipes travel through the
## materials of a timeline as "rcp_<recipe id>" and are learned when collected.
const RES_DROP_CHANCE := 0.012
const RES_DROP_AMOUNT := [1, 3]
const RECIPE_DROP_CHANCE := 0.0015
const RECIPE_DROP_CHANCE_BOSS := 0.04

## Recipes a hero of this crafting profession can find ("" = not chosen yet: all of them).
static func drop_recipes(prof: String = "") -> Array:
	var out := []
	for id in RECIPES:
		if RECIPES[id].get("drop_only", false) and (prof == "" or RECIPES[id]["prof"] == prof):
			out.append(id)
	return out

## Gathering resources that can drop at this campaign level (tier by level).
static func drop_resources(level: int) -> Array:
	var tier := 0 if level < 8 else (1 if level < 18 else 2)
	var out := []
	for id in RESOURCES:
		var r: Dictionary = RESOURCES[id]
		if r["cat"] in ["ore", "herb", "leather"] and int(r["tier"]) <= tier:
			out.append(id)
	return out
