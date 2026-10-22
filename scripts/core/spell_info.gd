class_name SpellInfo
extends RefCounted
## Human-readable numbers for a spell, computed with the same formulas the
## battle uses: amount = mult x level multiplier x caster's spell power.
## Damage numbers are before armor (DoT ignores armor) and without crits.

const DOT_TICK := 1.0

static func amount(sid: String, lvl: int, power: float) -> float:
	var s: Dictionary = Db.SPELLS[sid]
	return s["mult"] * Db.spell_level_mult(max(1, lvl)) * power

## Main effect lines: [[icon, text], ...]
static func effects(sid: String, lvl: int, power: float) -> Array:
	var s: Dictionary = Db.SPELLS[sid]
	var a := roundi(amount(sid, lvl, power))
	var dur: float = s.get("dur", 0.0)
	var ticks := int(round(dur / DOT_TICK))
	match s["kind"]:
		"damage":
			return [["swords", "Урон %d по цели" % a]]
		"aoe_damage":
			return [["swords", "Урон %d каждому врагу" % a], ["star", "Нужно врагов: %d+" % s.get("min_targets", 2)]]
		"dot":
			return [["sp_ignite", "%d урона в сек, %d с (всего %d)" % [a, ticks, a * ticks]]]
		"aoe_dot":
			return [["sp_poison_cloud", "%d урона в сек каждому, %d с (всего %d)" % [a, ticks, a * ticks]],
				["star", "Нужно врагов: %d+" % s.get("min_targets", 2)]]
		"execute":
			return [["swords", "Урон %d" % a], ["star", "Только по врагу ниже %d%% HP" % roundi(s.get("threshold", 0.3) * 100)]]
		"interrupt":
			return [["sp_kick", "Прерывает каст"], ["swords", "Урон %d" % a]]
		"stun":
			return [["sp_bash", "Оглушение %.0f с, прерывает каст" % dur], ["swords", "Урон %d" % a]]
		"drain":
			return [["swords", "Урон %d" % a], ["hp", "Лечит себя на нанесённый урон"]]
		"heal":
			return [["hp", "Лечение %d" % a], ["star", "Цель: самый раненый ниже %d%% HP" % roundi(s.get("threshold", 0.7) * 100)]]
		"hot_all":
			return [["hp", "%d лечения в сек всей группе, %d с (всего %d)" % [a, ticks, a * ticks]]]
		"shield":
			return [["sp_barrier", "Щит на %d урона, %.0f с" % [a, dur]]]
		"taunt":
			return [["sp_taunt", "Враги бьют только вас %.0f с" % dur], ["sp_barrier", "Щит на %d урона" % a]]
		"cleanse":
			return [["sp_cleanse", "Снимает яды, горение, оглушение"], ["hp", "Лечение %d" % a]]
	return []

## Timing lines: cast time and own cooldown.
static func timing(sid: String) -> Array:
	var s: Dictionary = Db.SPELLS[sid]
	var out := []
	var cast: float = s.get("cast", 0.0)
	out.append(["haste", ("Каст %.1f с" % cast) if cast > 0.0 else "Мгновенно"])
	var cd: float = s.get("cd", 0.0)
	out.append(["loop", ("Перезарядка %.0f с" % cd) if cd > 0.0 else "Без перезарядки"])
	return out

## One short line for tiles and cards, e.g. "Урон 42" or "Щит 90".
static func short(sid: String, lvl: int, power: float) -> String:
	var s: Dictionary = Db.SPELLS[sid]
	var a := roundi(amount(sid, lvl, power))
	match s["kind"]:
		"damage", "execute", "drain", "interrupt", "stun":
			return "Урон %d" % a
		"aoe_damage":
			return "Урон %d ×всем" % a
		"dot", "aoe_dot":
			return "%d/с · %.0f с" % [a, s.get("dur", 0.0)]
		"heal", "cleanse":
			return "Лечение %d" % a
		"hot_all":
			return "%d/с всем" % a
		"shield", "taunt":
			return "Щит %d" % a
	return ""

## Seconds between rotation steps for a unit with the given haste.
static func rotation_interval(haste: float) -> float:
	return BattleUnit.SPELL_INTERVAL / (1.0 + haste)
