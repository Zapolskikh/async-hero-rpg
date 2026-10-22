class_name SpellInfo
extends RefCounted
## Human-readable numbers for a spell, computed with the same formulas the
## battle uses: amount = mult x level multiplier x caster's stat x weapon bonus.
## `caster` is a combat snapshot ({stats, weapons}).
## Damage numbers are before armor (DoT ignores armor) and without crits.

const DOT_TICK := 1.0

static func amount(sid: String, lvl: int, caster: Dictionary) -> float:
	return Db.spell_amount(sid, lvl, caster.get("stats", {}), caster.get("weapons", []))

## Requirement / weapon bonus lines: [[icon, text, ok], ...]
static func weapon_lines(sid: String, caster: Dictionary) -> Array:
	var s: Dictionary = Db.SPELLS[sid]
	var weapons: Array = caster.get("weapons", [])
	var out := []
	var req: Array = s.get("req", [])
	if not req.is_empty():
		var names := []
		for w in req:
			names.append(Db.WEAPON_LABELS[w])
		var ok := Db.spell_usable(sid, weapons)
		out.append(["item_weapon", "Нужно оружие: %s%s" % [" или ".join(names), "" if ok else " — сейчас нет, заклинание пропускается"], ok])
	var b: Dictionary = s.get("bonus", {})
	if not b.is_empty():
		var on := Db.spell_bonus(sid, weapons) > 1.0
		out.append(["star", "+%d%% с оружием: %s%s" % [roundi((float(b["mult"]) - 1.0) * 100.0), Db.WEAPON_LABELS[b["w"]], " (действует)" if on else ""], on])
	return out

## Which stat the spell grows from, for the numbers block.
static func stat_label(sid: String) -> String:
	return Db.STAT_LABELS[Db.SPELLS[sid].get("stat", "power")]

## Main effect lines: [[icon, text], ...]
static func effects(sid: String, lvl: int, caster: Dictionary) -> Array:
	var s: Dictionary = Db.SPELLS[sid]
	var a := roundi(amount(sid, lvl, caster))
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
		"self_shield":
			return [["sp_barrier", "Щит на себя на %d урона, %.0f с" % [a, dur]]]
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
static func short(sid: String, lvl: int, caster: Dictionary) -> String:
	var s: Dictionary = Db.SPELLS[sid]
	var a := roundi(amount(sid, lvl, caster))
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
		"shield", "taunt", "self_shield":
			return "Щит %d" % a
	return ""

## Seconds between rotation steps for a unit with the given haste.
static func rotation_interval(haste: float) -> float:
	return BattleUnit.SPELL_INTERVAL / (1.0 + haste)
