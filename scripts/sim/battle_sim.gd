class_name BattleSim
extends RefCounted
## Deterministic fixed-step battle between up to 4 allies and up to 4 enemies.
## There is no tactical AI: every unit walks its 3-spell rotation in order and
## skips a spell whose validity condition is not met (concept 4.1).

const STEP := 0.1
const TIME_LIMIT := 150.0
const DOT_TICK := 1.0

var rng := RandomNumberGenerator.new()
var units: Array = []          # all units, allies first, in slot order
var time := 0.0
var finished := false
var won := false
var end_reason := ""
var record_events := true
var events: Array = []         # read by views (each keeps its own cursor); ignored headless
var event_seq := 0

var _acc := 0.0

## allies: Array of BattleUnit (kept between waves). enemies: Array of snapshots.
func setup(allies: Array, enemy_snaps: Array, seed_value: int) -> void:
	rng.seed = seed_value
	units.clear()
	var uid := 0
	for a in allies:
		uid = max(uid, a.uid + 1)
		units.append(a)
	for i in enemy_snaps.size():
		var e := BattleUnit.new(uid + i, 1, i, enemy_snaps[i])
		e.attack_cd = rng.randf_range(0.2, 1.0)
		e.spell_cd = rng.randf_range(1.5, 3.0)
		units.append(e)
	for a in allies:
		a.casting = {}
		a.cooldowns.clear()
		a.attack_cd = rng.randf_range(0.1, 0.6)
		a.spell_cd = rng.randf_range(0.5, 1.2)
		a.rot_index = 0

## Advance real time; runs as many fixed steps as fit.
func advance(dt: float) -> void:
	_acc += dt
	while _acc >= STEP and not finished:
		_acc -= STEP
		step()

func run_to_end() -> void:
	record_events = false
	while not finished:
		step()

func step() -> void:
	if finished:
		return
	time += STEP
	for u in units:
		if u.alive():
			_tick_statuses(u)
	for u in units:
		if u.alive():
			_act(u)
	_check_end()

# ---------------- queries ----------------

func side_units(side: int) -> Array:
	var out := []
	for u in units:
		if u.side == side and u.alive():
			out.append(u)
	return out

func foes_of(u: BattleUnit) -> Array:
	return side_units(1 - u.side)

func friends_of(u: BattleUnit) -> Array:
	return side_units(u.side)

func unit_by_uid(id: int) -> BattleUnit:
	for u in units:
		if u.uid == id:
			return u
	return null

func pick_target(u: BattleUnit, rule: String = "") -> BattleUnit:
	var foes := foes_of(u)
	if foes.is_empty():
		return null
	var taunters := foes.filter(func(f): return f.taunt > 0.0)
	if not taunters.is_empty():
		return taunters[0]
	if rule == "":
		rule = u.target_rule
	match rule:
		"back":
			var best = foes[0]
			for f in foes:
				if f.slot > best.slot:
					best = f
			return best
		"random":
			return foes[rng.randi_range(0, foes.size() - 1)]
		"lowest":
			var best = foes[0]
			for f in foes:
				if f.hp_frac() < best.hp_frac():
					best = f
			return best
		_:
			var best = foes[0]
			for f in foes:
				if f.slot < best.slot:
					best = f
			return best

# ---------------- per-step logic ----------------

func _tick_statuses(u: BattleUnit) -> void:
	if u.stun > 0.0:
		u.stun = max(0.0, u.stun - STEP)
	if u.taunt > 0.0:
		u.taunt = max(0.0, u.taunt - STEP)
	for sid in u.cooldowns.keys():
		u.cooldowns[sid] -= STEP
		if u.cooldowns[sid] <= 0.0:
			u.cooldowns.erase(sid)
	if u.shield > 0.0:
		u.shield_time -= STEP
		if u.shield_time <= 0.0:
			u.shield = 0.0
	for d in u.dots.duplicate():
		d["tick"] -= STEP
		d["remaining"] -= STEP
		if d["tick"] <= 0.0:
			d["tick"] += DOT_TICK
			_deal(d["src"], u, d["per_tick"], false, true)
		if d["remaining"] <= 0.0 or not u.alive():
			u.dots.erase(d)
	for h in u.hots.duplicate():
		h["tick"] -= STEP
		h["remaining"] -= STEP
		if h["tick"] <= 0.0:
			h["tick"] += DOT_TICK
			_heal(h["src"], u, h["per_tick"], false)
		if h["remaining"] <= 0.0:
			u.hots.erase(h)

func _act(u: BattleUnit) -> void:
	if u.stun > 0.0:
		return
	if u.is_casting():
		u.casting["remaining"] -= STEP
		if u.casting["remaining"] <= 0.0:
			var c := u.casting
			u.casting = {}
			var target = c["target"]
			if target is BattleUnit and not target.alive():
				target = _find_spell_target(u, c["spell"])
			if target != null:
				_cast(u, c["spell"], c["lvl"], target)
		return
	u.spell_cd -= STEP
	if u.spell_cd <= 0.0 and not u.spells.is_empty():
		if _try_rotation(u):
			u.spell_cd = u.spell_interval()
			return
		u.spell_cd = BattleUnit.RETRY_DELAY
	u.attack_cd -= STEP
	if u.attack_cd <= 0.0:
		u.attack_cd = u.attack_interval()
		var t := pick_target(u)
		if t != null:
			_emit({"t": "attack", "uid": u.uid, "tgt": t.uid})
			_deal(u, t, u.atk * rng.randf_range(0.9, 1.1), true, false)

## Walks Slot 1 -> 2 -> 3, starting from the current rotation position.
## The first spell whose validity condition holds is used; invalid ones are skipped.
func _try_rotation(u: BattleUnit) -> bool:
	var n := u.spells.size()
	for i in n:
		var idx := (u.rot_index + i) % n
		var entry: Dictionary = u.spells[idx]
		if u.cooldowns.has(entry["id"]):
			continue
		var target = _find_spell_target(u, entry["id"])
		if target == null:
			continue
		u.rot_index = (idx + 1) % n
		var spell: Dictionary = Db.SPELLS[entry["id"]]
		if spell.get("cd", 0.0) > 0.0:
			u.cooldowns[entry["id"]] = spell["cd"]
		if spell.get("cast", 0.0) > 0.0:
			u.casting = {
				"spell": entry["id"], "lvl": entry.get("lvl", 1),
				"remaining": spell["cast"], "total": spell["cast"],
				"target": target, "interruptible": spell.get("interruptible", true),
			}
			_emit({"t": "cast", "uid": u.uid, "text": spell["name"]})
		else:
			_cast(u, entry["id"], entry.get("lvl", 1), target)
		return true
	return false

## Returns the target the spell would hit, `u` itself for group spells,
## or null when the spell is not valid right now.
func _find_spell_target(u: BattleUnit, sid: String):
	var s: Dictionary = Db.SPELLS[sid]
	if not Db.spell_usable(sid, u.weapons):
		return null   # needs a weapon this unit does not hold
	var foes := foes_of(u)
	var friends := friends_of(u)
	if foes.is_empty():
		return null
	match s["kind"]:
		"damage", "drain":
			return pick_target(u)
		"aoe_damage":
			return u if foes.size() >= s.get("min_targets", 2) else null
		"dot":
			var t := pick_target(u)
			if t != null and not t.has_dot(sid):
				return t
			for f in foes:
				if not f.has_dot(sid):
					return f
			return null
		"aoe_dot":
			if foes.size() < s.get("min_targets", 2):
				return null
			for f in foes:
				if not f.has_dot(sid):
					return u
			return null
		"execute":
			var best = null
			for f in foes:
				if f.hp_frac() < s.get("threshold", 0.3) and (best == null or f.hp < best.hp):
					best = f
			return best
		"interrupt":
			for f in foes:
				if f.is_casting() and f.casting.get("interruptible", true):
					return f
			return null
		"stun":
			var cands := foes.filter(func(f): return not f.is_boss and f.stun <= 0.0)
			if cands.is_empty():
				return null
			for f in cands:
				if f.is_casting():
					return f
			var t := pick_target(u)
			return t if t in cands else cands[0]
		"heal":
			var best = null
			for f in friends:
				if f.hp_frac() < s.get("threshold", 0.7) and (best == null or f.hp_frac() < best.hp_frac()):
					best = f
			return best
		"hot_all":
			for f in friends:
				if f.hp_frac() < s.get("threshold", 0.9) and not f.has_hot(sid):
					return u
			return null
		"shield":
			var best = null
			for f in friends:
				if f.shield <= 0.0 and (best == null or f.slot < best.slot):
					best = f
			return best
		"taunt":
			return u if u.taunt <= 0.0 else null
		"self_shield":
			return u if u.shield <= 0.0 else null
		"cleanse":
			for f in friends:
				if f.is_debuffed():
					return f
			return null
	return null

func _cast(u: BattleUnit, sid: String, lvl: int, target) -> void:
	var s: Dictionary = Db.SPELLS[sid]
	var amount: float = Db.spell_amount(sid, lvl, u.stats, u.weapons)
	var tgt_uid: int = target.uid if target is BattleUnit else u.uid
	_emit({"t": "spell", "uid": u.uid, "text": s["name"], "sid": sid, "kind": s["kind"], "tgt": tgt_uid})
	match s["kind"]:
		"damage", "execute":
			_deal(u, target, amount, true, false)
		"aoe_damage":
			for f in foes_of(u):
				_deal(u, f, amount, true, false)
		"dot":
			_apply_dot(u, target, sid, amount, s.get("dur", 6.0))
		"aoe_dot":
			for f in foes_of(u):
				_apply_dot(u, f, sid, amount, s.get("dur", 6.0))
		"interrupt":
			_interrupt(u, target)
			_deal(u, target, amount, true, false)
		"stun":
			_interrupt(u, target)
			target.stun = s.get("dur", 2.0)
			_emit({"t": "status", "uid": target.uid, "text": "Оглушён"})
			_deal(u, target, amount, true, false)
		"drain":
			var d := _deal(u, target, amount, true, false)
			_heal(u, u, d, false)
		"heal":
			_heal(u, target, amount, true)
		"hot_all":
			for f in friends_of(u):
				var found := false
				for h in f.hots:
					if h["id"] == sid:
						h["remaining"] = s.get("dur", 6.0)
						found = true
				if not found:
					f.hots.append({"id": sid, "per_tick": amount, "remaining": s.get("dur", 6.0), "tick": DOT_TICK, "src": u})
		"shield":
			target.shield += amount
			target.shield_time = s.get("dur", 10.0)
			_emit({"t": "shield", "uid": target.uid, "v": amount})
		"self_shield":
			u.shield += amount
			u.shield_time = s.get("dur", 8.0)
			_emit({"t": "shield", "uid": u.uid, "v": amount})
		"taunt":
			u.taunt = s.get("dur", 6.0)
			u.shield += amount
			u.shield_time = max(u.shield_time, s.get("dur", 6.0))
			_emit({"t": "status", "uid": u.uid, "text": "Провокация"})
		"cleanse":
			target.dots.clear()
			target.stun = 0.0
			_emit({"t": "status", "uid": target.uid, "text": "Очищен"})
			_heal(u, target, amount, true)

func _apply_dot(src: BattleUnit, t: BattleUnit, sid: String, per_tick: float, dur: float) -> void:
	for d in t.dots:
		if d["id"] == sid:
			d["remaining"] = dur
			return
	t.dots.append({"id": sid, "per_tick": per_tick, "remaining": dur, "tick": DOT_TICK, "src": src})

func _interrupt(src: BattleUnit, t: BattleUnit) -> void:
	if t.is_casting() and t.casting.get("interruptible", true):
		t.casting = {}
		t.spell_cd = t.spell_interval()
		_emit({"t": "interrupt", "uid": t.uid, "text": "Прервано!"})

## Damage after armor (DoTs ignore armor), crits, then shield absorption.
func _deal(src: BattleUnit, t: BattleUnit, amount: float, can_crit: bool, is_dot: bool) -> float:
	if not t.alive():
		return 0.0
	var dmg := amount * src.dmg_mult
	if not is_dot:
		dmg *= 100.0 / (100.0 + t.armor)
	var crit := can_crit and rng.randf() < src.crit
	if crit:
		dmg *= 2.0
	dmg = max(1.0, round(dmg))
	var absorbed := 0.0
	if t.shield > 0.0:
		absorbed = min(t.shield, dmg)
		t.shield -= absorbed
		dmg -= absorbed
		if absorbed > 0.0:
			_emit({"t": "absorb", "uid": t.uid, "v": absorbed})
	if dmg > 0.0:
		t.hp = max(0.0, t.hp - dmg)
		_emit({"t": "dmg", "uid": t.uid, "v": dmg, "crit": crit, "dot": is_dot, "src": src.uid})
	src.dealt += dmg + absorbed
	if not t.alive():
		t.casting = {}
		t.dots.clear()
		t.hots.clear()
		t.shield = 0.0
		_emit({"t": "death", "uid": t.uid})
	return dmg + absorbed

func _heal(src: BattleUnit, t: BattleUnit, amount: float, can_crit: bool) -> void:
	if not t.alive():
		return
	var h := amount * src.heal_mult
	var crit := can_crit and rng.randf() < src.crit
	if crit:
		h *= 2.0
	h = round(min(h, t.max_hp - t.hp))
	if h <= 0.0:
		return
	t.hp += h
	src.healed += h
	_emit({"t": "heal", "uid": t.uid, "v": h, "crit": crit})

func _check_end() -> void:
	if side_units(1).is_empty():
		finished = true
		won = true
		end_reason = "Волна зачищена"
	elif side_units(0).is_empty():
		finished = true
		won = false
		end_reason = "Группа погибла"
	elif time >= TIME_LIMIT:
		finished = true
		won = false
		end_reason = "Время вышло"

func _emit(e: Dictionary) -> void:
	if record_events:
		event_seq += 1
		e["n"] = event_seq
		events.append(e)
		if events.size() > 300:
			events = events.slice(150)
