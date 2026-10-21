class_name Db
extends RefCounted
## Static game data: spells, enemies, campaign levels, mercenary templates.
## Everything here is plain data so the battle simulation can run without any
## scene tree (headless tests, offline AFK calculation, a future server port).

const RARITY_NAMES := ["Обычный", "Редкий", "Эпический", "Легендарный"]
const RARITY_COLORS := [Color("#b8b8b8"), Color("#4da3ff"), Color("#b36bff"), Color("#ff9d2e")]

# Spell kinds understood by BattleSim:
#   damage, aoe_damage, dot, aoe_dot, execute, interrupt, stun, drain,
#   heal, hot_all, shield, taunt, cleanse
# Fields: kind, mult (x power), cast (sec, 0 = instant), interruptible,
#   dur (status duration), min_targets, threshold (hp fraction), rarity (0-3)
const SPELLS := {
	# --- Player spells ---
	"strike":       {"name": "Мощный удар",     "kind": "damage",     "mult": 1.8, "cast": 0.0, "rarity": 0, "tags": ["dps"],
					 "desc": "Удар по цели. Срабатывает всегда."},
	"fireball":     {"name": "Огненный шар",    "kind": "damage",     "mult": 2.8, "cast": 1.2, "rarity": 0, "tags": ["dps"],
					 "desc": "Каст 1.2 с, сильный урон по цели."},
	"cleave":       {"name": "Рассечение",      "kind": "aoe_damage", "mult": 1.0, "cast": 0.0, "rarity": 1, "min_targets": 2, "tags": ["aoe"],
					 "desc": "Урон по всем врагам. Только если врагов 2+."},
	"chain_lightning": {"name": "Цепная молния", "kind": "aoe_damage", "mult": 1.4, "cast": 1.5, "rarity": 2, "min_targets": 3, "tags": ["aoe"],
					 "desc": "Каст 1.5 с, урон по всем. Только если врагов 3+."},
	"ignite":       {"name": "Поджог",          "kind": "dot",        "mult": 0.55, "cast": 0.0, "dur": 6.0, "rarity": 0, "tags": ["dot"],
					 "desc": "Горение 6 с на цели без горения."},
	"poison_cloud": {"name": "Ядовитое облако", "kind": "aoe_dot",    "mult": 0.35, "cast": 0.0, "dur": 6.0, "rarity": 1, "min_targets": 2, "tags": ["dot", "aoe"],
					 "desc": "Яд на всех врагах. Только если врагов 2+."},
	"execute":      {"name": "Казнь",           "kind": "execute",    "mult": 4.5, "cast": 0.0, "threshold": 0.3, "rarity": 1, "tags": ["dps"],
					 "desc": "Огромный урон по врагу ниже 30% HP."},
	"kick":         {"name": "Пинок",           "kind": "interrupt",  "mult": 0.8, "cast": 0.0, "rarity": 0, "tags": ["interrupt"],
					 "desc": "Сбивает вражеский каст. Только если враг кастует."},
	"bash":         {"name": "Оглушение",       "kind": "stun",       "mult": 0.6, "cast": 0.0, "dur": 2.0, "rarity": 1, "tags": ["control"],
					 "desc": "Оглушает цель на 2 с и сбивает каст. Боссы невосприимчивы."},
	"drain":        {"name": "Похищение жизни", "kind": "drain",      "mult": 1.6, "cast": 0.0, "rarity": 2, "tags": ["dps", "sustain"],
					 "desc": "Урон по цели, лечит себя на нанесённый урон."},
	"heal":         {"name": "Исцеление",       "kind": "heal",       "mult": 3.0, "cast": 1.0, "threshold": 0.7, "rarity": 0, "tags": ["heal"],
					 "desc": "Каст 1 с, лечит самого раненого союзника ниже 70%."},
	"renew":        {"name": "Обновление",      "kind": "hot_all",    "mult": 0.45, "cast": 0.0, "dur": 6.0, "threshold": 0.9, "rarity": 1, "tags": ["heal"],
					 "desc": "Лечение со временем на всю группу, если кто-то ниже 90%."},
	"barrier":      {"name": "Барьер",          "kind": "shield",     "mult": 3.0, "cast": 0.0, "dur": 10.0, "rarity": 0, "tags": ["shield"],
					 "desc": "Щит на переднего союзника без щита."},
	"taunt":        {"name": "Провокация",      "kind": "taunt",      "mult": 1.5, "cast": 0.0, "dur": 6.0, "rarity": 0, "tags": ["tank"],
					 "desc": "Враги бьют только вас 6 с, плюс небольшой щит."},
	"cleanse":      {"name": "Очищение",        "kind": "cleanse",    "mult": 1.0, "cast": 0.0, "rarity": 1, "tags": ["cleanse", "heal"],
					 "desc": "Снимает яд/горение/оглушение с союзника и подлечивает."},

	# --- Enemy spells ---
	"e_smash":      {"name": "Сокрушение",      "kind": "damage",     "mult": 2.6, "cast": 1.6, "interruptible": true, "enemy": true},
	"e_bolt":       {"name": "Тёмная стрела",   "kind": "damage",     "mult": 3.2, "cast": 2.4, "interruptible": true, "enemy": true},
	"e_mend":       {"name": "Заживление",      "kind": "heal",       "mult": 3.2, "cast": 2.0, "threshold": 0.75, "interruptible": true, "enemy": true},
	"e_guard":      {"name": "Защита",          "kind": "shield",     "mult": 2.2, "cast": 0.0, "dur": 8.0, "enemy": true},
	"e_volley":     {"name": "Залп",            "kind": "aoe_damage", "mult": 0.9, "cast": 1.0, "min_targets": 1, "interruptible": true, "enemy": true},
	"e_backstab":   {"name": "Удар в спину",    "kind": "damage",     "mult": 2.4, "cast": 0.0, "enemy": true},
	"e_venom":      {"name": "Отравление",      "kind": "aoe_dot",    "mult": 0.35, "cast": 0.0, "dur": 8.0, "min_targets": 1, "enemy": true},
	"e_cataclysm":  {"name": "Катаклизм",       "kind": "aoe_damage", "mult": 2.2, "cast": 3.0, "min_targets": 1, "interruptible": false, "enemy": true},
	"e_crush":      {"name": "Раскол",          "kind": "damage",     "mult": 2.4, "cast": 0.0, "enemy": true},
	"e_dark_mend":  {"name": "Тёмное лечение",  "kind": "heal",       "mult": 5.0, "cast": 2.5, "threshold": 0.6, "interruptible": true, "enemy": true},
}

const STARTER_SPELLS := ["strike", "fireball", "heal", "barrier", "kick"]

# Enemy archetypes. Stats are for campaign level 1; Db.enemy_scale() multiplies them.
# target: front / back / random / lowest  (who basic attacks and damage spells hit)
const ENEMIES := {
	"brute":    {"name": "Громила",  "hp": 260, "atk": 15, "power": 12, "armor": 10, "haste": 0.0, "target": "front",
				 "spells": ["e_smash"], "color": "#c0533a", "role": "brute"},
	"caster":   {"name": "Колдун",   "hp": 150, "atk": 8,  "power": 16, "armor": 0,  "haste": 0.0, "target": "random",
				 "spells": ["e_bolt"], "color": "#8a4fd8", "role": "caster"},
	"healer":   {"name": "Знахарь",  "hp": 170, "atk": 7,  "power": 14, "armor": 5,  "haste": 0.0, "target": "front",
				 "spells": ["e_mend"], "color": "#4fbf6a", "role": "healer"},
	"tank":     {"name": "Страж",    "hp": 420, "atk": 9,  "power": 10, "armor": 45, "haste": 0.0, "target": "front",
				 "spells": ["e_guard"], "color": "#7f8c99", "role": "tank"},
	"ranged":   {"name": "Лучник",   "hp": 160, "atk": 12, "power": 9,  "armor": 5,  "haste": 0.1, "target": "random",
				 "spells": ["e_volley"], "color": "#c9a23a", "role": "ranged"},
	"assassin": {"name": "Убийца",   "hp": 170, "atk": 12, "power": 13, "armor": 5,  "haste": 0.2, "target": "back",
				 "spells": ["e_backstab"], "color": "#3a3f4f", "role": "assassin"},
	"poisoner": {"name": "Отравитель", "hp": 160, "atk": 8, "power": 11, "armor": 5,  "haste": 0.0, "target": "random",
				 "spells": ["e_venom"], "color": "#6c9a2a", "role": "disruptor"},
	"boss_ogre":  {"name": "Вождь огров", "hp": 1500, "atk": 22, "power": 16, "armor": 20, "haste": 0.0, "target": "front",
				 "spells": ["e_crush", "e_smash"], "color": "#9c2f2f", "role": "boss", "boss": true},
	"boss_lich":  {"name": "Лич", "hp": 1100, "atk": 14, "power": 18, "armor": 15, "haste": 0.0, "target": "random",
				 "spells": ["e_cataclysm", "e_bolt", "e_dark_mend"], "color": "#5a3fa0", "role": "boss", "boss": true},
}

# Campaign: each level is a list of waves; each wave is 1-4 enemy ids.
# Levels 1-10 are hand-made to teach one mechanic each; scale grows per level.
const LEVELS := [
	{"name": "Опушка",            "waves": [["brute"], ["brute", "brute"], ["brute", "ranged"], ["boss_ogre"]]},
	{"name": "Лагерь лучников",   "waves": [["ranged", "ranged"], ["brute", "ranged", "ranged"], ["brute", "brute", "ranged"], ["boss_ogre", "ranged"]]},
	{"name": "Тёмная роща",       "waves": [["caster"], ["brute", "caster"], ["caster", "caster", "ranged"], ["brute", "caster", "caster"], ["boss_ogre", "caster"]]},
	{"name": "Шаманий круг",      "waves": [["brute", "healer"], ["tank", "healer"], ["brute", "brute", "healer"], ["caster", "healer", "ranged"], ["boss_ogre", "healer"]]},
	{"name": "Логово вождя",      "waves": [["brute", "brute", "brute"], ["tank", "brute", "ranged"], ["brute", "caster", "healer"], ["boss_ogre", "brute", "healer"]]},
	{"name": "Тени",              "waves": [["assassin"], ["assassin", "brute"], ["assassin", "assassin", "ranged"], ["tank", "assassin", "caster"], ["boss_ogre", "assassin", "assassin"]]},
	{"name": "Ядовитые топи",     "waves": [["poisoner", "brute"], ["poisoner", "poisoner"], ["poisoner", "tank", "ranged"], ["poisoner", "poisoner", "brute", "healer"], ["boss_ogre", "poisoner", "poisoner"]]},
	{"name": "Крепость стражей",  "waves": [["tank", "healer"], ["tank", "tank", "healer"], ["tank", "healer", "healer", "caster"], ["tank", "tank", "ranged", "ranged"], ["boss_ogre", "tank", "healer"]]},
	{"name": "Перекрёсток",       "waves": [["brute", "caster", "assassin"], ["poisoner", "healer", "ranged", "brute"], ["tank", "caster", "caster", "healer"], ["assassin", "assassin", "poisoner", "ranged"], ["boss_lich", "caster"]]},
	{"name": "Склеп лича",        "waves": [["caster", "caster", "healer"], ["tank", "poisoner", "assassin", "caster"], ["brute", "brute", "healer", "healer"], ["boss_lich", "healer", "tank"]]},
]

const LEVEL_SCALE := 1.25   # enemy stat growth per campaign level

static func level_count() -> int:
	return LEVELS.size()

static func enemy_scale(level: int) -> float:
	return pow(LEVEL_SCALE, level - 1)

## Qualitative preview hints for a level (concept 7.2: no exact income forecast).
static func level_hints(level: int) -> Array:
	var counts := {}
	var max_wave := 0
	for wave in LEVELS[level - 1]["waves"]:
		max_wave = max(max_wave, wave.size())
		for e in wave:
			var role: String = ENEMIES[e]["role"]
			counts[role] = counts.get(role, 0) + 1
	var hints := []
	if max_wave >= 3:
		hints.append("Полезен AoE")
	if counts.get("caster", 0) >= 2:
		hints.append("Касты: нужен interrupt")
	if counts.get("healer", 0) >= 2:
		hints.append("Вражеские лекари")
	if counts.get("assassin", 0) >= 2:
		hints.append("Опасность для тыла")
	if counts.get("disruptor", 0) >= 2:
		hints.append("Яды: нужно очищение")
	if counts.get("tank", 0) >= 3:
		hints.append("Броня: затяжной бой")
	for wave in LEVELS[level - 1]["waves"]:
		for e in wave:
			if e == "boss_lich":
				hints.append("Сильный урон босса")
	if counts.get("brute", 0) >= 4:
		hints.append("Тяжёлые удары: щиты")
	return hints

static func boss_of(level: int) -> String:
	for wave in LEVELS[level - 1]["waves"]:
		for e in wave:
			if ENEMIES[e].get("boss", false):
				return ENEMIES[e]["name"]
	return ""

# ---------- Heroes and mercenaries ----------

static func hero_base_stats(level: int) -> Dictionary:
	var l := level - 1
	return {
		"hp": 300 + 55 * l,
		"atk": 15 + 4 * l,
		"power": 15 + 4 * l,
		"armor": 10 + 2 * l,
		"haste": 0.0,
		"crit": 0.05,
	}

static func xp_to_next(level: int) -> int:
	return int(60 * pow(level, 1.5))

static func spell_level_mult(spell_level: int) -> float:
	return 1.0 + 0.3 * (spell_level - 1)

# Guild mercenary templates (concept 9: decent generic builds, clearly NPC).
const MERC_TEMPLATES := [
	{"role": "Танк",     "spells": ["taunt", "barrier", "strike"],     "stat": {"hp": 1.4, "armor": 1.8, "atk": 0.8, "power": 0.8}},
	{"role": "Лекарь",   "spells": ["heal", "renew", "barrier"],       "stat": {"hp": 0.9, "power": 1.2}},
	{"role": "Лекарь",   "spells": ["heal", "cleanse", "strike"],      "stat": {"hp": 0.9, "power": 1.15}},
	{"role": "Пиромант", "spells": ["ignite", "fireball", "strike"],   "stat": {"hp": 0.85, "power": 1.2}},
	{"role": "Ядовик",   "spells": ["poison_cloud", "ignite", "strike"], "stat": {"hp": 0.85, "power": 1.15}},
	{"role": "Боец",     "spells": ["cleave", "strike", "execute"],    "stat": {"hp": 1.1, "atk": 1.2}},
	{"role": "Страж",    "spells": ["kick", "bash", "strike"],         "stat": {"hp": 1.1, "atk": 1.1, "armor": 1.3}},
	{"role": "Паладин",  "spells": ["barrier", "heal", "strike"],      "stat": {"hp": 1.2, "armor": 1.3}},
	{"role": "Охотник",  "spells": ["kick", "fireball", "strike"],     "stat": {"hp": 0.9, "power": 1.1, "atk": 1.1}},
]

const MERC_NAMES := ["Борис", "Ольга", "Тарас", "Мира", "Гордей", "Злата", "Яромир", "Вера", "Ратибор",
	"Лада", "Святослав", "Дана", "Велимир", "Ира", "Остап", "Нина", "Добрыня", "Ксена", "Ждан", "Рада"]
