class_name SpellInfo
extends RefCounted
## Human-readable numbers for a spell, computed with the same formulas the
## battle uses: amount = mult x level multiplier x caster's stat x weapon bonus.
## `caster` is a combat snapshot ({stats, weapons}).
## Damage numbers are before armor (DoT ignores armor) and without crits.

const DOT_TICK := 1.0

static func amount(sid: String, lvl: int, caster: Dictionary) -> float:
	var stats := {"hp":1.,"atk":0.,"power":0.}
	stats.merge(caster.get("stats",{}),true)
	var u := BattleUnit.new(0,0,0,{"name":"preview","stats":stats,"weapons":caster.get("weapons",[]),"talents":caster.get("talents",{})})
	var value := CombatV9.new()._amount(u,sid,lvl)
	if Db.SPELLS[sid]["kind"] in ["heal","hot","hot_all","riptide","chain_heal","earth_shield","prayer"]:
		value *= 1.+.03*u.rank("life_gift")
	return value

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
		var ranks: Dictionary = caster.get("talents", {})
		var ok: bool = Db.spell_usable(sid, weapons) or (sid == "execute" and "bow" in weapons and ranks.get("kill_shot",0) > 0) or ("bow" in req and "sword" in weapons and ranks.get("throwing",0) > 0)
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
	var s: Dictionary = Db.SPELLS[sid].duplicate()
	for e in caster.get("spells", []):
		if e["id"] == sid and e.has("threshold"):
			s["threshold"] = e["threshold"]
	var a := roundi(amount(sid, lvl, caster))
	var dur: float = s.get("dur", 0.0)
	if s["kind"] == "taunt":
		dur += 2. * int(caster.get("talents",{}).get("relentless",0))
	var ticks := int(round(dur / DOT_TICK))
	match s["kind"]:
		"damage":
			return [["swords", "Урон %d по цели" % a]]
		"aoe_damage":
			return [["swords", "Урон %d каждому врагу" % a]]
		"dot":
			return [["sp_ignite", "%d урона в сек, %d с (всего %d)" % [a, ticks, a * ticks]]]
		"aoe_dot":
			return [["sp_poison_cloud", "%d урона в сек каждому, %d с (всего %d)" % [a, ticks, a * ticks]]]
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
			return [["hp", "%d лечения в сек всей группе, %d с (всего %d)" % [a, ticks, a * ticks]],
				["star", "Если кто-то ниже %d%% HP" % roundi(s.get("threshold", 0.9) * 100)]]
		"shield":
			return [["sp_barrier", "Щит на %d урона, %.0f с" % [a, dur]]]
		"taunt":
			return [["sp_taunt", "Враги выбирают вас %.0f с; применяется по готовности" % dur]]
		"self_shield":
			return [["sp_barrier", "Щит на себя на %d урона, %.0f с" % [a, dur]]]
		"cleanse":
			return [["sp_cleanse", "Снимает яды, горение, оглушение"], ["hp", "Лечение %d" % a]]
	return [["star", s.get("desc", "")], ["power", "Сила эффекта: %d" % a]]

## Timing lines: cast time and own cooldown.
static func timing(sid: String, caster: Dictionary = {}) -> Array:
	var s: Dictionary = Db.SPELLS[sid]
	var out := []
	var cast: float = s.get("cast", 0.0)
	var talents: Dictionary = caster.get("talents",{})
	if not s.get("weapon",false):
		cast *= 1.-.03*int(talents.get("fast_cast",0))
		if s["kind"] in ["heal","chain_heal"]:
			cast *= 1.-.05*int(talents.get("steady_hand",0))
	cast /= 1.+float(caster.get("stats",{}).get("haste",0.))
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
		"hot":
			return "%d/с союзнику" % a
		"riptide":
			return "Лечение %d + HoT" % a
		"chain_heal":
			return "Лечение %d → 65%% → 42%%" % a
		"earth_shield", "prayer":
			return "%d лечения × 5 зарядов" % a
		"penance":
			return "%d × 3 · урон / лечение" % a
		"channel_aoe":
			return "%d × 3 всем" % a
		"seed", "explosive":
			return "Взрыв %d всем" % a
		"buff_all", "buff_self":
			return "+%d%% · %.0f с" % [roundi(s["value"]*100.),s["dur"]]
		"rally":
			return "+20% здоровья группе"
		"purge", "mass_dispel":
			return "Рассеивание эффектов"
		"prism":
			return "Урон %d + лечение группы" % a
		"debuff":
			return "Урон врага −15% · 15 с"
		"summon":
			return "Зверь · %.0f с" % s["dur"]
		"taunt":
			return "Провокация %.0f с" % s.get("dur",6.)
		"shield", "self_shield":
			return "Щит %d" % a
	return s.get("desc", "")

## Seconds between rotation steps for a unit with the given haste.
static func rotation_interval(haste: float) -> float:
	return BattleUnit.SPELL_INTERVAL / (1.0 + haste)
