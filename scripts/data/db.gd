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
#   self_shield (shield on the caster)
# Fields: kind, mult (x caster stat), cast (sec, 0 = instant), interruptible,
#   dur (status duration), min_targets, threshold (hp fraction), rarity (0-3),
#   cd (own cooldown in seconds; a spell on cooldown is skipped like an invalid one),
#   stat (what it scales from: power (default), str, agi),
#   req (weapon types, any of them is needed; without one the spell is skipped),
#   bonus ({w: weapon type or "dual" for two swords, mult}: stronger with that weapon)
const SPELLS := {
	# --- Player spells ---
	"strike":       {"name": "Мощный удар",     "kind": "damage",     "mult": 1.8, "cast": 0.0, "cd": 0.0, "rarity": 0, "tags": ["dps"],
					 "stat": "str", "bonus": {"w": "sword", "mult": 1.2},
					 "desc": "Удар по цели. Срабатывает всегда."},
	"fireball":     {"name": "Огненный шар",    "kind": "damage",     "mult": 2.8, "cast": 1.2, "cd": 0.0, "rarity": 0, "tags": ["dps"],
					 "bonus": {"w": "staff", "mult": 1.2},
					 "desc": "Каст 1.2 с, сильный урон по цели."},
	"cleave":       {"name": "Рассечение",      "kind": "aoe_damage", "mult": 1.0, "cast": 0.0, "cd": 5.0, "rarity": 1, "min_targets": 2, "tags": ["aoe"],
					 "stat": "str", "bonus": {"w": "greatsword", "mult": 1.3},
					 "desc": "Урон по всем врагам. Только если врагов 2+."},
	"chain_lightning": {"name": "Цепная молния", "kind": "aoe_damage", "mult": 1.4, "cast": 1.5, "cd": 7.0, "rarity": 2, "min_targets": 3, "tags": ["aoe"],
					 "bonus": {"w": "staff", "mult": 1.2},
					 "desc": "Каст 1.5 с, урон по всем. Только если врагов 3+."},
	"ignite":       {"name": "Поджог",          "kind": "dot",        "mult": 0.55, "cast": 0.0, "cd": 0.0, "dur": 6.0, "rarity": 0, "tags": ["dot"],
					 "desc": "Горение 6 с на цели без горения."},
	"poison_cloud": {"name": "Ядовитое облако", "kind": "aoe_dot",    "mult": 0.35, "cast": 0.0, "cd": 0.0, "dur": 6.0, "rarity": 1, "min_targets": 2, "tags": ["dot", "aoe"],
					 "desc": "Яд на всех врагах. Только если врагов 2+."},
	"execute":      {"name": "Казнь",           "kind": "execute",    "mult": 4.5, "cast": 0.0, "cd": 4.0, "threshold": 0.3, "rarity": 1, "tags": ["dps"],
					 "stat": "str", "bonus": {"w": "greatsword", "mult": 1.25},
					 "desc": "Огромный урон по врагу ниже 30% HP."},
	"kick":         {"name": "Пинок",           "kind": "interrupt",  "mult": 0.8, "cast": 0.0, "cd": 5.0, "rarity": 0, "tags": ["interrupt"],
					 "stat": "str",
					 "desc": "Сбивает вражеский каст. Только если враг кастует."},
	"bash":         {"name": "Оглушение",       "kind": "stun",       "mult": 0.6, "cast": 0.0, "cd": 10.0, "dur": 2.0, "rarity": 1, "tags": ["control"],
					 "stat": "str", "bonus": {"w": "shield", "mult": 1.3},
					 "desc": "Оглушает цель на 2 с и сбивает каст. Боссы невосприимчивы."},
	"drain":        {"name": "Похищение жизни", "kind": "drain",      "mult": 1.6, "cast": 0.0, "cd": 6.0, "rarity": 2, "tags": ["dps", "sustain"],
					 "desc": "Урон по цели, лечит себя на нанесённый урон."},
	"heal":         {"name": "Исцеление",       "kind": "heal",       "mult": 3.0, "cast": 1.0, "cd": 0.0, "threshold": 0.7, "rarity": 0, "tags": ["heal"],
					 "bonus": {"w": "staff", "mult": 1.2},
					 "desc": "Каст 1 с, лечит самого раненого союзника ниже 70%."},
	"renew":        {"name": "Обновление",      "kind": "hot_all",    "mult": 0.45, "cast": 0.0, "cd": 10.0, "dur": 6.0, "threshold": 0.9, "rarity": 1, "tags": ["heal"],
					 "bonus": {"w": "staff", "mult": 1.2},
					 "desc": "Лечение со временем на всю группу, если кто-то ниже 90%."},
	"barrier":      {"name": "Барьер",          "kind": "shield",     "mult": 3.0, "cast": 0.0, "cd": 7.0, "dur": 10.0, "rarity": 0, "tags": ["shield"],
					 "bonus": {"w": "shield", "mult": 1.3},
					 "desc": "Щит на переднего союзника без щита."},
	"taunt":        {"name": "Провокация",      "kind": "taunt",      "mult": 1.5, "cast": 0.0, "cd": 12.0, "dur": 6.0, "rarity": 0, "tags": ["tank"],
					 "bonus": {"w": "shield", "mult": 1.5},
					 "desc": "Враги бьют только вас 6 с, плюс небольшой щит."},
	"cleanse":      {"name": "Очищение",        "kind": "cleanse",    "mult": 1.0, "cast": 0.0, "cd": 6.0, "rarity": 1, "tags": ["cleanse", "heal"],
					 "desc": "Снимает яд/горение/оглушение с союзника и подлечивает."},

	# --- Weapon spells: only usable with the required weapon (req = any of these) ---
	"twin_strike":  {"name": "Двойной удар",    "kind": "damage",     "mult": 2.2, "cast": 0.0, "cd": 0.0, "rarity": 0, "tags": ["dps"],
					 "stat": "str", "req": ["sword"], "bonus": {"w": "dual", "mult": 1.4},
					 "desc": "Нужен меч. Два быстрых удара по цели; с мечом в каждой руке сильнее."},
	"mortal_strike": {"name": "Сокрушительный удар", "kind": "damage", "mult": 3.4, "cast": 0.0, "cd": 6.0, "rarity": 0, "tags": ["dps"],
					 "stat": "str", "req": ["greatsword"],
					 "desc": "Нужен двуручный меч. Тяжёлый удар по цели."},
	"whirlwind":    {"name": "Вихрь клинка",    "kind": "aoe_damage", "mult": 1.4, "cast": 0.0, "cd": 6.0, "rarity": 1, "min_targets": 2, "tags": ["aoe"],
					 "stat": "str", "req": ["greatsword"],
					 "desc": "Нужен двуручный меч. Урон по всем врагам, если их 2+."},
	"shield_slam":  {"name": "Удар щитом",      "kind": "stun",       "mult": 1.0, "cast": 0.0, "cd": 9.0, "dur": 1.5, "rarity": 1, "tags": ["control"],
					 "stat": "str", "req": ["shield"],
					 "desc": "Нужен щит. Оглушает цель на 1.5 с и сбивает каст. Боссы невосприимчивы."},
	"shield_wall":  {"name": "Стена щитов",     "kind": "self_shield", "mult": 4.0, "cast": 0.0, "cd": 10.0, "dur": 8.0, "rarity": 0, "tags": ["tank"],
					 "stat": "str", "req": ["shield"],
					 "desc": "Нужен щит. Большой щит на себя, если своего щита нет."},
	"aimed_shot":   {"name": "Прицельный выстрел", "kind": "damage",  "mult": 3.6, "cast": 1.5, "cd": 0.0, "rarity": 0, "tags": ["dps"],
					 "stat": "agi", "req": ["bow"],
					 "desc": "Нужен лук. Каст 1.5 с, сильный выстрел по цели."},
	"arrow_rain":   {"name": "Дождь стрел",     "kind": "aoe_damage", "mult": 1.2, "cast": 0.0, "cd": 8.0, "rarity": 1, "min_targets": 2, "tags": ["aoe"],
					 "stat": "agi", "req": ["bow"],
					 "desc": "Нужен лук. Урон по всем врагам, если их 2+."},
	"arcane_bolt":  {"name": "Чародейская стрела", "kind": "damage",  "mult": 2.2, "cast": 0.0, "cd": 0.0, "rarity": 0, "tags": ["dps"],
					 "req": ["staff"],
					 "desc": "Нужен посох. Мгновенный магический удар по цели."},

	# --- Enemy spells ---
	"e_smash":      {"name": "Сокрушение",      "kind": "damage",     "mult": 2.6, "cast": 1.6, "interruptible": true, "enemy": true},
	"e_bolt":       {"name": "Тёмная стрела",   "kind": "damage",     "mult": 3.2, "cast": 2.4, "interruptible": true, "enemy": true},
	"e_mend":       {"name": "Заживление",      "kind": "heal",       "mult": 3.2, "cast": 2.0, "threshold": 0.75, "interruptible": true, "enemy": true},
	"e_guard":      {"name": "Защита",          "kind": "shield",     "mult": 2.2, "cast": 0.0, "cd": 8.0, "dur": 8.0, "enemy": true},
	"e_volley":     {"name": "Залп",            "kind": "aoe_damage", "mult": 0.9, "cast": 1.0, "min_targets": 1, "interruptible": true, "enemy": true},
	"e_backstab":   {"name": "Удар в спину",    "kind": "damage",     "mult": 2.4, "cast": 0.0, "enemy": true},
	"e_venom":      {"name": "Отравление",      "kind": "aoe_dot",    "mult": 0.35, "cast": 0.0, "dur": 8.0, "min_targets": 1, "enemy": true},
	"e_cataclysm":  {"name": "Катаклизм",       "kind": "aoe_damage", "mult": 2.2, "cast": 3.0, "min_targets": 1, "interruptible": false, "enemy": true},
	"e_crush":      {"name": "Раскол",          "kind": "damage",     "mult": 2.4, "cast": 0.0, "enemy": true},
	"e_dark_mend":  {"name": "Тёмное лечение",  "kind": "heal",       "mult": 5.0, "cast": 2.5, "threshold": 0.6, "interruptible": true, "enemy": true},
	"e_cleave":     {"name": "Вихрь топоров",   "kind": "aoe_damage", "mult": 1.1, "cast": 0.0, "cd": 6.0, "min_targets": 1, "enemy": true},
	"e_quake":      {"name": "Землетрясение",   "kind": "aoe_damage", "mult": 1.7, "cast": 2.5, "min_targets": 1, "interruptible": false, "enemy": true},
	"e_curse":      {"name": "Проклятие",       "kind": "dot",        "mult": 0.55, "cast": 0.0, "dur": 8.0, "enemy": true},
	"e_rejuv":      {"name": "Благословение",   "kind": "hot_all",    "mult": 0.4, "cast": 0.0, "cd": 8.0, "dur": 6.0, "threshold": 0.9, "enemy": true},
	"e_breath":     {"name": "Огненное дыхание", "kind": "aoe_damage", "mult": 1.9, "cast": 2.5, "min_targets": 1, "interruptible": false, "enemy": true},
	"e_burn":       {"name": "Пепел",           "kind": "aoe_dot",    "mult": 0.45, "cast": 0.0, "cd": 8.0, "dur": 6.0, "min_targets": 1, "enemy": true},
	"e_warcry":     {"name": "Боевой клич",     "kind": "shield",     "mult": 3.0, "cast": 0.0, "cd": 10.0, "dur": 8.0, "enemy": true},
}

const STARTER_SPELLS := ["strike", "fireball", "heal", "barrier", "kick"]

# Enemy archetypes. Stats are for campaign level 1; Db.enemy_scale() multiplies them.
# target: front / back / random / lowest  (who basic attacks and damage spells hit)
const ENEMIES := {
	"brute":    {"name": "Громила",  "hp": 260, "atk": 15, "power": 12, "armor": 10, "haste": 0.0, "target": "front",
				 "spells": ["e_smash"], "color": "#c0533a", "sprite": "brute", "ranged": false, "role": "brute"},
	"caster":   {"name": "Колдун",   "hp": 150, "atk": 8,  "power": 16, "armor": 0,  "haste": 0.0, "target": "random",
				 "spells": ["e_bolt"], "color": "#8a4fd8", "sprite": "caster", "ranged": true, "role": "caster"},
	"healer":   {"name": "Знахарь",  "hp": 170, "atk": 7,  "power": 14, "armor": 5,  "haste": 0.0, "target": "front",
				 "spells": ["e_mend"], "color": "#4fbf6a", "sprite": "e_healer", "ranged": true, "role": "healer"},
	"tank":     {"name": "Страж",    "hp": 420, "atk": 9,  "power": 10, "armor": 45, "haste": 0.0, "target": "front",
				 "spells": ["e_guard"], "color": "#7f8c99", "sprite": "e_tank", "ranged": false, "role": "tank"},
	"ranged":   {"name": "Лучник",   "hp": 160, "atk": 12, "power": 9,  "armor": 5,  "haste": 0.1, "target": "random",
				 "spells": ["e_volley"], "color": "#c9a23a", "sprite": "ranged", "ranged": true, "role": "ranged"},
	"assassin": {"name": "Убийца",   "hp": 170, "atk": 12, "power": 13, "armor": 5,  "haste": 0.2, "target": "back",
				 "spells": ["e_backstab"], "color": "#3a3f4f", "sprite": "assassin", "ranged": false, "role": "assassin"},
	"poisoner": {"name": "Отравитель", "hp": 160, "atk": 8, "power": 11, "armor": 5,  "haste": 0.0, "target": "random",
				 "spells": ["e_venom"], "color": "#6c9a2a", "sprite": "poisoner", "ranged": true, "role": "disruptor"},
	"berserker": {"name": "Берсерк", "hp": 220, "atk": 13, "power": 12, "armor": 5,  "haste": 0.4, "target": "front",
				 "spells": ["e_cleave"], "color": "#8a3a2a", "sprite": "berserker", "ranged": false, "role": "brute",
				 "hint": "Быстрые берсерки: нужен танк"},
	"golem":    {"name": "Голем", "hp": 650, "atk": 18, "power": 12, "armor": 70, "haste": -0.35, "target": "front",
				 "spells": ["e_quake"], "color": "#6f6a62", "sprite": "golem", "ranged": false, "role": "tank",
				 "hint": "Големы: броня и землетрясения"},
	"warlock":  {"name": "Чернокнижник", "hp": 170, "atk": 8, "power": 14, "armor": 5, "haste": 0.0, "target": "random",
				 "spells": ["e_curse", "e_bolt"], "color": "#3a1f3f", "sprite": "warlock", "ranged": true, "role": "caster",
				 "hint": "Проклятия: очищение и interrupt"},
	"priest":   {"name": "Жрица", "hp": 180, "atk": 7, "power": 13, "armor": 5, "haste": 0.0, "target": "front",
				 "spells": ["e_rejuv", "e_mend"], "color": "#d8c8f0", "sprite": "priest", "ranged": true, "role": "healer",
				 "hint": "Жрицы лечат всех врагов: AoE"},
	"boss_ogre":  {"name": "Вождь огров", "hp": 1500, "atk": 22, "power": 16, "armor": 20, "haste": 0.0, "target": "front",
				 "spells": ["e_crush", "e_smash"], "color": "#9c2f2f", "sprite": "boss_ogre", "ranged": false, "role": "boss", "boss": true},
	"boss_lich":  {"name": "Лич", "hp": 1100, "atk": 14, "power": 18, "armor": 15, "haste": 0.0, "target": "random",
				 "spells": ["e_cataclysm", "e_bolt", "e_dark_mend"], "color": "#5a3fa0", "sprite": "boss_lich", "ranged": true, "role": "boss", "boss": true},
	"boss_warlord": {"name": "Полководец орды", "hp": 1700, "atk": 24, "power": 15, "armor": 30, "haste": 0.15, "target": "front",
				 "spells": ["e_warcry", "e_cleave", "e_crush"], "color": "#5a1f1f", "sprite": "boss_warlord", "ranged": false, "role": "boss", "boss": true},
	"boss_shadow":  {"name": "Владыка теней", "hp": 1050, "atk": 13, "power": 16, "armor": 15, "haste": 0.3, "target": "back",
				 "spells": ["e_backstab", "e_curse", "e_backstab"], "color": "#141420", "sprite": "boss_shadow", "ranged": false, "role": "boss", "boss": true,
				 "hint": "Босс бьёт по тылу"},
	"boss_drake":   {"name": "Драконид", "hp": 1600, "atk": 16, "power": 17, "armor": 25, "haste": 0.0, "target": "random",
				 "spells": ["e_breath", "e_burn", "e_crush"], "color": "#2f6a3a", "sprite": "boss_drake", "ranged": true, "role": "boss", "boss": true},
	"boss_archlich": {"name": "Архилич", "hp": 2900, "atk": 15, "power": 19, "armor": 20, "haste": 0.0, "target": "random",
				 "spells": ["e_cataclysm", "e_curse", "e_dark_mend", "e_bolt"], "color": "#0f3a3a", "sprite": "boss_archlich", "ranged": true, "role": "boss", "boss": true},
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
	# --- Chapter 2: northern wastes (berserkers, golems, priests) ---
	{"name": "Перевал берсерков", "waves": [["berserker"], ["berserker", "ranged"], ["berserker", "berserker", "ranged"], ["boss_ogre", "berserker"]]},
	{"name": "Ледяной лагерь",    "waves": [["tank", "berserker"], ["ranged", "ranged", "healer"], ["berserker", "berserker", "healer"], ["tank", "ranged", "ranged", "healer"]]},
	{"name": "Каменоломня",       "waves": [["golem"], ["golem", "ranged"], ["golem", "healer"], ["golem", "golem", "caster"]]},
	{"name": "Жертвенник",        "waves": [["priest", "brute"], ["priest", "berserker", "ranged"], ["priest", "priest", "tank"], ["brute", "brute", "priest", "caster"]]},
	{"name": "Ставка полководца", "waves": [["berserker", "berserker", "ranged"], ["tank", "priest", "ranged"], ["golem", "berserker", "healer"], ["boss_warlord", "berserker"]]},
	# --- Chapter 3: shadows and curses ---
	{"name": "Проклятый лес",     "waves": [["warlock"], ["warlock", "brute"], ["warlock", "warlock", "tank"], ["warlock", "poisoner", "assassin"]]},
	{"name": "Гнездо убийц",      "waves": [["assassin", "assassin"], ["assassin", "warlock", "ranged"], ["assassin", "assassin", "priest"], ["assassin", "assassin", "assassin", "healer"]]},
	{"name": "Чумной квартал",    "waves": [["poisoner", "poisoner", "brute"], ["warlock", "poisoner", "priest"], ["poisoner", "poisoner", "tank"], ["golem", "poisoner", "warlock"]]},
	{"name": "Зал зеркал",        "waves": [["caster", "caster", "caster"], ["warlock", "caster", "priest"], ["tank", "caster", "caster", "healer"], ["warlock", "warlock", "assassin", "priest"]]},
	{"name": "Трон теней",        "waves": [["assassin", "warlock", "priest"], ["berserker", "assassin", "poisoner", "ranged"], ["golem", "warlock", "warlock"], ["boss_shadow", "assassin", "priest"]]},
	# --- Chapter 4: dragon mountains ---
	{"name": "Предгорья",         "waves": [["golem", "berserker"], ["ranged", "ranged", "ranged"], ["golem", "priest", "ranged"], ["berserker", "berserker", "berserker", "healer"]]},
	{"name": "Пепельная долина",  "waves": [["poisoner", "warlock", "ranged"], ["golem", "golem", "healer"], ["berserker", "assassin", "priest", "caster"], ["tank", "tank", "priest", "priest"]]},
	{"name": "Кладбище драконов", "waves": [["warlock", "warlock", "priest"], ["golem", "berserker", "berserker"], ["caster", "caster", "poisoner", "priest"], ["boss_lich", "golem"]]},
	{"name": "Логово выводка",    "waves": [["berserker", "berserker", "ranged", "ranged"], ["tank", "warlock", "priest", "priest"], ["golem", "golem", "assassin"], ["assassin", "berserker", "warlock", "priest"]]},
	{"name": "Драконья вершина",  "waves": [["golem", "warlock", "priest"], ["berserker", "berserker", "poisoner", "ranged"], ["tank", "caster", "caster", "priest"], ["boss_drake", "priest"]]},
	# --- Chapter 5: the archlich's realm ---
	{"name": "Врата некрополя",   "waves": [["tank", "tank", "warlock", "priest"], ["assassin", "assassin", "poisoner"], ["golem", "golem", "priest"], ["boss_ogre", "berserker", "berserker"]]},
	{"name": "Костяные залы",     "waves": [["caster", "caster", "warlock", "priest"], ["berserker", "berserker", "priest"], ["golem", "assassin", "healer"], ["boss_lich", "warlock"]]},
	{"name": "Река душ",          "waves": [["poisoner", "poisoner", "warlock", "warlock"], ["tank", "golem", "priest", "priest"], ["assassin", "assassin", "berserker", "caster"], ["boss_shadow", "warlock", "priest"]]},
	{"name": "Последний рубеж",   "waves": [["golem", "golem", "golem"], ["berserker", "assassin", "warlock", "priest"], ["tank", "priest", "caster", "caster"], ["boss_drake", "boss_warlord"]]},
	{"name": "Цитадель архилича", "waves": [["warlock", "warlock", "priest", "priest"], ["golem", "berserker", "assassin", "poisoner"], ["tank", "tank", "caster", "priest"], ["boss_archlich", "priest", "warlock"]]},
]

const CHAPTERS := [
	{"from": 1, "name": "Пограничье"},
	{"from": 11, "name": "Северные пустоши"},
	{"from": 16, "name": "Тени и проклятия"},
	{"from": 21, "name": "Драконьи горы"},
	{"from": 26, "name": "Царство архилича"},
]

const LEVEL_SCALE := 1.25   # enemy stat growth per level for chapter 1 (levels 1-10)
const SCALE_BREAK := 10     # after this level enemies follow the party's expected growth
const HERO_AT_BREAK := 16.0 # hero level a typical player has when clearing SCALE_BREAK
const HERO_PER_LEVEL := 1.2 # expected hero levels per campaign level after the break
const LATE_TOUGHNESS := 1.0 # extra difficulty multiplier per level after the break (tuning knob)

static func level_count() -> int:
	return LEVELS.size()

static func chapter_of(level: int) -> Dictionary:
	var ch: Dictionary = CHAPTERS[0]
	for c in CHAPTERS:
		if level >= c["from"]:
			ch = c
	return ch

## Enemy stat multiplier. Chapter 1 grows exponentially (fast early power ramp);
## later the curve tracks how strong a typical party of the expected hero level
## is (sqrt of damage x survivability), so the time per new level stays flat
## instead of exploding.
static func enemy_scale(level: int) -> float:
	if level <= SCALE_BREAK:
		return pow(LEVEL_SCALE, level - 1)
	var base := pow(LEVEL_SCALE, SCALE_BREAK - 1)
	var h := HERO_AT_BREAK + HERO_PER_LEVEL * (level - SCALE_BREAK)
	return base * party_strength(h) / party_strength(HERO_AT_BREAK) * pow(LATE_TOUGHNESS, level - SCALE_BREAK)

## Rough strength of a character of hero level h: sqrt(damage x health).
static func party_strength(h: float) -> float:
	var st := hero_base_stats(int(round(h)))
	var spell_mult := spell_level_mult(1 + int(h / 4.0))
	return sqrt(st["power"] * spell_mult * st["hp"])

static func enemy_armor_mult(level: int) -> float:
	return 1.0 + 0.12 * (min(level, SCALE_BREAK) - 1) + 0.04 * max(0, level - SCALE_BREAK)

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
	var ids := {}
	for wave in LEVELS[level - 1]["waves"]:
		for e in wave:
			ids[e] = ids.get(e, 0) + 1
	for e in ids:
		var en: Dictionary = ENEMIES[e]
		if en.has("hint") and (ids[e] >= 2 or en.get("boss", false)):
			hints.append(en["hint"])
		if en.get("boss", false):
			for sp in en["spells"]:
				if not SPELLS[sp].get("interruptible", true) and not "Сильный урон босса" in hints:
					hints.append("Сильный урон босса")
	var bosses := 0
	for wave in LEVELS[level - 1]["waves"]:
		var nb := 0
		for e in wave:
			if ENEMIES[e].get("boss", false):
				nb += 1
		bosses = max(bosses, nb)
	if bosses >= 2:
		hints.append("Два босса разом")
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
		"str": 15 + 4 * l,
		"agi": 15 + 4 * l,
		"power": 15 + 4 * l,
		"armor": 10 + 2 * l,
		"haste": 0.0,
		"crit": 0.05,
	}

## XP rewards grow a bit faster than linearly so late levels do not drag.
static func xp_level_factor(level: int) -> float:
	return pow(level, 1.15)

## Levels 1-5 are quick; after that every level costs several times more
## (x2.3 at 6, x8.6 at 10, x28 at 20): progress needs a good build or hours of farm.
const XP_SLOWDOWN_FROM := 6
const XP_SLOWDOWN_POW := 1.2

static func xp_to_next(level: int) -> int:
	var base := 60.0 * pow(level, 1.4)
	if level >= XP_SLOWDOWN_FROM:
		base *= pow(level - XP_SLOWDOWN_FROM + 2, XP_SLOWDOWN_POW)
	return int(base)

static func spell_level_mult(spell_level: int) -> float:
	return 1.0 + 0.3 * (spell_level - 1)

const STAT_LABELS := {"power": "сила заклинаний", "str": "сила", "agi": "ловкость"}
const WEAPON_LABELS := {"sword": "меч", "greatsword": "двуручный меч", "shield": "щит", "staff": "посох",
	"bow": "лук", "dual": "меч в каждой руке"}

## The caster stat a spell scales from (enemies only have power and atk).
static func spell_stat_value(sid: String, stats: Dictionary) -> float:
	var stat: String = SPELLS[sid].get("stat", "power")
	if stats.has(stat):
		return float(stats[stat])
	return float(stats.get("atk", stats.get("power", 0.0))) if stat != "power" else float(stats.get("power", 0.0))

## True when the caster holds a weapon the spell needs (or it needs none).
static func spell_usable(sid: String, weapons: Array) -> bool:
	var req: Array = SPELLS[sid].get("req", [])
	if req.is_empty():
		return true
	for w in req:
		if w in weapons:
			return true
	return false

## Weapon bonus multiplier for this spell and these weapons (1.0 = no bonus).
static func spell_bonus(sid: String, weapons: Array) -> float:
	var b: Dictionary = SPELLS[sid].get("bonus", {})
	if b.is_empty():
		return 1.0
	if b["w"] == "dual":
		return float(b["mult"]) if weapons.count("sword") >= 2 else 1.0
	return float(b["mult"]) if b["w"] in weapons else 1.0

## Spell amount for a caster: mult x level x stat x weapon bonus.
static func spell_amount(sid: String, lvl: int, stats: Dictionary, weapons: Array) -> float:
	return SPELLS[sid]["mult"] * spell_level_mult(max(1, lvl)) * spell_stat_value(sid, stats) * spell_bonus(sid, weapons)

# Guild mercenary templates (concept 9: decent generic builds, clearly NPC).
const MERC_TEMPLATES := [
# weapons: [main hand, left hand] types the mercenary's gear is rolled with.
	{"sprite": "tank", "ranged": false, "role": "Танк",     "spells": ["taunt", "barrier", "strike"],     "stat": {"hp": 1.4, "armor": 1.8, "str": 0.8, "power": 0.8}, "weapons": ["sword", "shield"]},
	{"sprite": "healer", "ranged": true, "role": "Лекарь",   "spells": ["heal", "renew", "barrier"],       "stat": {"hp": 0.9, "power": 1.2}, "weapons": ["staff"]},
	{"sprite": "healer", "ranged": true, "role": "Лекарь",   "spells": ["heal", "cleanse", "strike"],      "stat": {"hp": 0.9, "power": 1.15}, "weapons": ["staff"]},
	{"sprite": "pyromancer", "ranged": true, "role": "Пиромант", "spells": ["ignite", "fireball", "strike"],   "stat": {"hp": 0.85, "power": 1.2}, "weapons": ["staff"]},
	{"sprite": "poisoner_ally", "ranged": false, "role": "Ядовик",   "spells": ["poison_cloud", "ignite", "twin_strike"], "stat": {"hp": 0.85, "power": 1.15}, "weapons": ["sword", "sword"]},
	{"sprite": "fighter", "ranged": false, "role": "Боец",     "spells": ["cleave", "mortal_strike", "execute"], "stat": {"hp": 1.1, "str": 1.2}, "weapons": ["greatsword"]},
	{"sprite": "guard", "ranged": false, "role": "Страж",    "spells": ["kick", "shield_slam", "strike"],  "stat": {"hp": 1.1, "str": 1.1, "armor": 1.3}, "weapons": ["sword", "shield"]},
	{"sprite": "paladin", "ranged": false, "role": "Паладин",  "spells": ["barrier", "heal", "strike"],      "stat": {"hp": 1.2, "armor": 1.3}, "weapons": ["sword", "shield"]},
	{"sprite": "hunter", "ranged": true, "role": "Охотник",  "spells": ["kick", "aimed_shot", "arrow_rain"], "stat": {"hp": 0.9, "power": 1.1, "agi": 1.2}, "weapons": ["bow"]},
]

const MERC_NAMES := ["Борис", "Ольга", "Тарас", "Мира", "Гордей", "Злата", "Яромир", "Вера", "Ратибор",
	"Лада", "Святослав", "Дана", "Велимир", "Ира", "Остап", "Нина", "Добрыня", "Ксена", "Ждан", "Рада"]
