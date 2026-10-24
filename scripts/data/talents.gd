class_name Talents
extends RefCounted
## Hero talents: POINTS_PER_LEVEL points per hero level from FIRST_LEVEL on.
## Each talent has up to MAX_RANK ranks; rank N costs N points (1, 2, 3, ...),
## so deep ranks are expensive and spreading points is a real choice.
## Effect fields:
##   stat + pct  -> stat x (1 + pct * rank)      (hp, str, agi, power, armor)
##   stat + add  -> stat + add * rank            (crit, haste)
##   stat "atk" + pct -> basic attack damage x (1 + pct * rank)
##   w           -> only while holding this weapon type ("dual" = a sword in each hand)

const FIRST_LEVEL := 5      # the first points come at hero level 5
const POINTS_PER_LEVEL := 2
const MAX_RANK := 5

const BRANCHES := [
	{"id": "general", "name": "Общие"},
	{"id": "sword", "name": "Меч и щит"},
	{"id": "greatsword", "name": "Двуручник"},
	{"id": "bow", "name": "Лук"},
	{"id": "staff", "name": "Посох"},
]

const TALENTS := {
	"toughness":    {"name": "Стойкость", "branch": "general", "icon": "hp", "stat": "hp", "pct": 0.05},
	"precision":    {"name": "Точность", "branch": "general", "icon": "crit", "stat": "crit", "add": 0.015},
	"swiftness":    {"name": "Проворство", "branch": "general", "icon": "haste", "stat": "haste", "add": 0.03},
	"blade_master": {"name": "Мастер клинка", "branch": "sword", "icon": "str", "stat": "str", "pct": 0.06, "w": "sword"},
	"bulwark":      {"name": "Оплот", "branch": "sword", "icon": "armor", "stat": "armor", "pct": 0.10, "w": "shield"},
	"twin_blades":  {"name": "Парные клинки", "branch": "sword", "icon": "w_sword", "stat": "atk", "pct": 0.08, "w": "dual"},
	"heavy_hand":   {"name": "Тяжёлая рука", "branch": "greatsword", "icon": "str", "stat": "str", "pct": 0.08, "w": "greatsword"},
	"brutality":    {"name": "Жестокость", "branch": "greatsword", "icon": "crit", "stat": "crit", "add": 0.02, "w": "greatsword"},
	"eagle_eye":    {"name": "Орлиный глаз", "branch": "bow", "icon": "agi", "stat": "agi", "pct": 0.08, "w": "bow"},
	"quick_draw":   {"name": "Быстрая тетива", "branch": "bow", "icon": "haste", "stat": "haste", "add": 0.04, "w": "bow"},
	"arcane_focus": {"name": "Чародейский фокус", "branch": "staff", "icon": "power", "stat": "power", "pct": 0.08, "w": "staff"},
	"mana_flow":    {"name": "Поток маны", "branch": "staff", "icon": "haste", "stat": "haste", "add": 0.04, "w": "staff"},
}

static func points_total(level: int) -> int:
	return max(0, level - FIRST_LEVEL + 1) * POINTS_PER_LEVEL

## Points to buy the next rank of a talent now at `rank`.
static func rank_cost(rank: int) -> int:
	return rank + 1

static func points_spent(talents: Dictionary) -> int:
	var n := 0
	for k in talents:
		var r := int(talents[k])
		n += r * (r + 1) / 2
	return n

static func points_free(hero: Dictionary) -> int:
	return points_total(int(hero["level"])) - points_spent(hero.get("talents", {}))

static func _active(t: Dictionary, weapons: Array) -> bool:
	if not t.has("w"):
		return true
	if t["w"] == "dual":
		return weapons.count("sword") >= 2
	return t["w"] in weapons

## Applies talents to stats before the basic attack is computed (all but "atk").
static func apply_stats(st: Dictionary, talents: Dictionary, weapons: Array) -> void:
	for id in talents:
		if not TALENTS.has(id):
			continue
		var t: Dictionary = TALENTS[id]
		var rank := int(talents[id])
		if rank <= 0 or t["stat"] == "atk" or not _active(t, weapons):
			continue
		if t.has("pct"):
			st[t["stat"]] = round(float(st.get(t["stat"], 0.0)) * (1.0 + float(t["pct"]) * rank))
		else:
			st[t["stat"]] = float(st.get(t["stat"], 0.0)) + float(t["add"]) * rank

## Basic attack multiplier from talents.
static func attack_mult(talents: Dictionary, weapons: Array) -> float:
	var m := 1.0
	for id in talents:
		if TALENTS.has(id) and TALENTS[id]["stat"] == "atk" and _active(TALENTS[id], weapons):
			m *= 1.0 + float(TALENTS[id]["pct"]) * int(talents[id])
	return m

## "+5% здоровья за ранг · с мечом в каждой руке"
static func describe(id: String) -> String:
	var t: Dictionary = TALENTS[id]
	var names := {"hp": "здоровья", "str": "силы", "agi": "ловкости", "power": "силы заклинаний", "armor": "брони",
		"crit": "крита", "haste": "скорости", "atk": "урона атаки"}
	var v: float = float(t.get("pct", t.get("add", 0.0))) * 100.0
	var txt := "+%s%% %s за ранг" % [str(snappedf(v, 0.1)).trim_suffix(".0"), names[t["stat"]]]
	if t.has("w"):
		txt += " · " + ("с мечом в каждой руке" if t["w"] == "dual" else "с оружием: " + Db.WEAPON_LABELS[t["w"]])
	return txt
