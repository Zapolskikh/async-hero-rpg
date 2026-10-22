class_name Expedition
extends RefCounted
## An AFK expedition on one campaign level (concept 7.1).
##   push: a single attempt at a level. A wipe ends it with partial rewards.
##   farm: a closed level looped forever; each run gives full rewards.
## HP carries over between waves, so sustain matters over a whole level.

const WAVE_PAUSE := 1.5
const BETWEEN_WAVE_HEAL := 0.25
const FIRST_CLEAR_RARITY_BONUS := 0.25
const FARM_DROP_CHANCE := 0.15  # per farm run won; first clears always drop

var level := 1
var mode := "push"
var party: Array = []          # snapshots of 4 party members, slot order
var base_seed := 0
var first_clear_pending := false

var allies: Array = []
var sim: BattleSim
var wave_index := 0
var pause := 0.0
var run_index := 0
var finished := false          # push attempt over (farm never finishes by itself)
var elapsed := 0.0             # sim seconds spent, including pauses

# Rewards accumulated since the player last collected.
var gold := 0
var xp := 0
var kills := 0
var items: Array = []
var boxes := 0
var runs_won := 0
var runs_lost := 0
var best_wave := 0
var level_closed_now := false  # set when a push clears the level for the first time
var mats := {}                 # crafting materials (cloth, boss materials) earned so far
var last_reason := ""

var rng := RandomNumberGenerator.new()
var mat_rng := RandomNumberGenerator.new()   # separate stream: material drops do not shift gear drops
var record_events := true

func start(p_level: int, p_mode: String, p_party: Array, p_seed: int, p_first_clear: bool) -> void:
	level = p_level
	mode = p_mode
	party = p_party.duplicate(true)
	base_seed = p_seed
	first_clear_pending = p_first_clear
	rng.seed = p_seed
	mat_rng.seed = hash([p_seed, "mats"])
	_start_run()

func waves() -> Array:
	return Db.level_waves(level)

## Battle time of the finished waves of the current run (damage meter: DPS per run).
var run_time_done := 0.0

func _start_run() -> void:
	run_time_done = 0.0
	allies.clear()
	for i in party.size():
		allies.append(BattleUnit.new(i, 0, i, party[i]))
	wave_index = 0
	_start_wave()

func _start_wave() -> void:
	var snaps := []
	for eid in waves()[wave_index]:
		snaps.append(enemy_snapshot(eid, level))
	if sim != null and wave_index > 0:
		run_time_done += sim.time
	sim = BattleSim.new()
	sim.record_events = record_events
	sim.setup(allies, snaps, base_seed + run_index * 97 + wave_index * 13)

static func enemy_snapshot(eid: String, lvl: int) -> Dictionary:
	var e: Dictionary = Db.ENEMIES[eid]
	var sc := Db.enemy_scale(lvl)
	var spells := []
	for s in e["spells"]:
		spells.append({"id": s, "lvl": 1})
	var st := {
		"hp": e["hp"] * sc, "atk": e["atk"] * sc, "power": e["power"] * sc,
		"armor": e["armor"] * Db.enemy_armor_mult(lvl), "haste": e["haste"], "crit": 0.05,
	}
	var mods := Db.level_modifiers(lvl)
	for m in mods:
		match m:
			"armored": st["armor"] *= 1.35
			"swift": st["haste"] += 0.2
			"shielded": st["start_shield"] = st["hp"] * 0.15
			"regen": st["regen"] = 0.008
			"brutal":
				st["atk"] *= 1.15
				st["power"] *= 1.15
			"vital": st["hp"] *= 1.2
	if st.has("start_shield"):
		st["start_shield"] = st["hp"] * 0.15
	return {
		"name": e["name"], "color": e["color"], "boss": e.get("boss", false), "target": e["target"],
		"sprite": e.get("sprite", ""), "ranged": e.get("ranged", false),
		"stats": st, "spells": spells, "mods": mods, "id": eid,
	}

func advance(dt: float) -> void:
	if finished:
		return
	if pause > 0.0:
		pause -= dt
		elapsed += dt
		if pause <= 0.0:
			_start_wave()
		return
	var before := sim.time
	sim.advance(dt)
	elapsed += sim.time - before
	if sim.finished:
		_on_wave_end()

## Runs headless until the current wave ends. Used by fast-forward.
func step_wave_headless() -> void:
	if pause > 0.0:
		elapsed += pause
		pause = 0.0
		_start_wave()
	sim.record_events = false
	var before := sim.time
	sim.run_to_end()
	elapsed += sim.time - before
	_on_wave_end()

func _on_wave_end() -> void:
	var sc := Db.enemy_scale(level)
	for u in sim.units:
		if u.side == 1 and not u.alive():
			kills += 1
			var mult := 8 if u.is_boss else 1
			gold += int(round(5.0 * pow(sc, 0.85) * mult * Db.GOLD_MULT))
			xp += int(round(6.0 * Db.xp_level_factor(level) * mult))
			_drop_mats(u)
	if sim.won:
		wave_index += 1
		best_wave = max(best_wave, wave_index)
		if wave_index >= waves().size():
			_on_run_end(true, "Уровень пройден")
			return
		for a in allies:
			if a.alive():
				a.hp = min(a.max_hp, a.hp + a.max_hp * BETWEEN_WAVE_HEAL)
				a.dots.clear()
				a.hots.clear()
				a.stun = 0.0
		pause = WAVE_PAUSE
	else:
		_on_run_end(false, sim.end_reason)

func _on_run_end(cleared: bool, reason: String) -> void:
	last_reason = reason
	run_index += 1
	if cleared:
		runs_won += 1
		if mode == "push":
			var table := Prof.cloth_table(level)
			var best: String = table.keys()[-1]
			_add_mat(best, Prof.CLOTH_ON_CLEAR)
		xp += int(round(30.0 * Db.xp_level_factor(level)))
		if mode == "push":
			gold += int(round(40 * level * Db.GOLD_MULT))
		if first_clear_pending:
			first_clear_pending = false
			level_closed_now = true
			items.append(Loot.roll_gear(rng, level, FIRST_CLEAR_RARITY_BONUS))
			boxes += 1
		elif rng.randf() < FARM_DROP_CHANCE:
			items.append(Loot.roll_gear(rng, level, 0.0))
	else:
		runs_lost += 1
	if mode == "push":
		finished = true
	else:
		_start_run()

## Cloth from every kill, special materials from bosses (spec 9-10, 20).
func _drop_mats(u: BattleUnit) -> void:
	var table := Prof.cloth_table(level)
	for res in table:
		if mat_rng.randf() < float(table[res]):
			_add_mat(res, mat_rng.randi_range(Prof.CLOTH_PER_DROP[0], Prof.CLOTH_PER_DROP[1]))
	# rare extras: a gathering resource or a drop-only recipe
	if mat_rng.randf() < Prof.RES_DROP_CHANCE:
		var pool := Prof.drop_resources(level)
		_add_mat(pool[mat_rng.randi_range(0, pool.size() - 1)], mat_rng.randi_range(Prof.RES_DROP_AMOUNT[0], Prof.RES_DROP_AMOUNT[1]))
	if mat_rng.randf() < (Prof.RECIPE_DROP_CHANCE_BOSS if u.is_boss else Prof.RECIPE_DROP_CHANCE):
		var rcps := Prof.drop_recipes()
		_add_mat("rcp_" + rcps[mat_rng.randi_range(0, rcps.size() - 1)], 1)
	if u.is_boss and Prof.BOSS_DROPS.has(u.sprite):
		var drops: Dictionary = Prof.BOSS_DROPS[u.sprite]
		var first := true
		for res in drops:
			if (first and mode == "push" and first_clear_pending) or mat_rng.randf() < float(drops[res]):
				_add_mat(res, 1)
			first = false

func _add_mat(res: String, n: int) -> void:
	mats[res] = int(mats.get(res, 0)) + n

func total_waves() -> int:
	return waves().size()

## Simulates `seconds` of offline time (concept 7: server-side math, not a live tick).
## Runs are simulated for real up to `sim_budget` seconds, the rest of a farm is
## extrapolated from the observed reward rate.
func fast_forward(seconds: float, sim_budget: float = 1200.0) -> Dictionary:
	var start := {"gold": gold, "xp": xp, "kills": kills, "items": items.size(), "won": runs_won, "lost": runs_lost}
	var target: float = elapsed + min(seconds, sim_budget)
	var t0 := elapsed
	record_events = false
	while not finished and elapsed < target:
		step_wave_headless()
	var simulated := elapsed - t0
	var extra := 0.0
	if mode == "farm" and seconds > simulated and simulated > 0.0:
		extra = seconds - simulated
		var k := extra / simulated
		gold += int((gold - start["gold"]) * k)
		xp += int((xp - start["xp"]) * k)
		kills += int((kills - start["kills"]) * k)
		var new_items := int(round((items.size() - start["items"]) * k))
		for i in min(new_items, 30):
			items.append(Loot.roll_gear(rng, level, 0.0))
		runs_won += int((runs_won - start["won"]) * k)
		runs_lost += int((runs_lost - start["lost"]) * k)
	record_events = true
	if not finished:
		# Resume watching from a fresh run so the live view has events again.
		_start_run()
	return {"simulated": simulated, "extrapolated": extra}

func take_rewards() -> Dictionary:
	var r := {"gold": gold, "xp": xp, "kills": kills, "items": items.duplicate(), "boxes": boxes,
		"won": runs_won, "lost": runs_lost, "closed": level_closed_now, "mats": mats.duplicate()}
	gold = 0
	xp = 0
	kills = 0
	items.clear()
	boxes = 0
	runs_won = 0
	runs_lost = 0
	level_closed_now = false
	mats.clear()
	return r

func has_rewards() -> bool:
	return gold > 0 or xp > 0 or not items.is_empty() or boxes > 0

# ---------------------------------------------------------------------------
# Timeline model (used by Rules on client and server).
# An expedition is simulated once when it starts; the result is a compact list
# of cumulative reward points. Rewards at any moment are a lookup, so the server
# never has to tick expeditions (concept 7 / 15).
#   point = [t, gold, xp, kills, items_n, boxes, won, lost, best_wave]
# Farm: runs are simulated for a window, beyond it rewards grow at the measured
# rate and extra items are generated deterministically from the seed.
# ---------------------------------------------------------------------------

const FARM_WINDOW := 1200.0
const FARM_WINDOW_MAX := 2400.0
const FARM_MIN_RUNS := 6
const P_T := 0
const P_GOLD := 1
const P_XP := 2
const P_KILLS := 3
const P_ITEMS := 4
const P_BOXES := 5
const P_WON := 6
const P_LOST := 7
const P_WAVE := 8
const P_MATS := 9   # Dictionary resource -> cumulative count

func _point() -> Array:
	return [snappedf(elapsed, 0.01), gold, xp, kills, items.size(), boxes, runs_won, runs_lost, best_wave, mats.duplicate()]

static func build_timeline(p_level: int, p_mode: String, p_party: Array, p_seed: int, p_first: bool) -> Dictionary:
	var ex := Expedition.new()
	ex.record_events = false
	ex.start(p_level, p_mode, p_party, p_seed, p_first)
	var pts := []
	if p_mode == "push":
		while not ex.finished:
			ex.step_wave_headless()
			pts.append(ex._point())
		return {"mode": "push", "level": p_level, "seed": p_seed, "pts": pts, "items": ex.items.duplicate(true),
			"t_end": snappedf(ex.elapsed, 0.01), "won": ex.runs_won > 0, "reason": ex.last_reason,
			"waves": ex.best_wave, "total": ex.total_waves(), "closed": ex.level_closed_now}
	var last_run := 0
	while true:
		ex.step_wave_headless()
		if ex.run_index != last_run:
			last_run = ex.run_index
			pts.append(ex._point())
			if (ex.elapsed >= FARM_WINDOW and ex.run_index >= FARM_MIN_RUNS) or ex.elapsed >= FARM_WINDOW_MAX:
				break
	var t_sim: float = pts[-1][P_T]
	var rate := []
	for i in P_MATS:
		rate.append(0.0 if i == P_T else float(pts[-1][i]) / t_sim)
	var mat_rate := {}
	for res in pts[-1][P_MATS]:
		mat_rate[res] = float(pts[-1][P_MATS][res]) / t_sim
	rate.append(mat_rate)
	return {"mode": "farm", "level": p_level, "seed": p_seed, "pts": pts, "items": ex.items.duplicate(true),
		"sim_until": t_sim, "rate": rate}

## Cumulative rewards at time t (seconds since start).
static func rewards_at(tl: Dictionary, t: float) -> Array:
	var cur := zero_point()
	for pt in tl["pts"]:
		if float(pt[P_T]) <= t:
			cur = pt.duplicate(true)
		else:
			break
	if tl["mode"] == "farm" and t > float(tl["sim_until"]):
		var last: Array = tl["pts"][-1]
		var extra: float = t - float(tl["sim_until"])
		cur = [t]
		for i in range(1, P_MATS):
			cur.append(int(last[i]) + int(floor(float(tl["rate"][i]) * extra)))
		cur[P_WAVE] = last[P_WAVE]
		var m := {}
		var last_m: Dictionary = last[P_MATS] if last.size() > P_MATS else {}
		var rate_m: Dictionary = tl["rate"][P_MATS] if tl["rate"].size() > P_MATS else {}
		for res in last_m:
			m[res] = int(last_m[res]) + int(floor(float(rate_m.get(res, 0.0)) * extra))
		cur.append(m)
	if cur.size() <= P_MATS:
		cur.append({})
	cur[P_T] = t
	return cur

static func zero_point() -> Array:
	return [0.0, 0, 0, 0, 0, 0, 0, 0, 0, {}]

## a - b for material dictionaries
static func mats_diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for res in a:
		var n := int(a[res]) - int(b.get(res, 0))
		if n > 0:
			out[res] = n
	return out

## i-th dropped item of the timeline (stored ones first, then generated).
static func item_at(tl: Dictionary, i: int) -> Dictionary:
	var stored: Array = tl["items"]
	if i < stored.size():
		return stored[i]
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(tl["seed"]), i])
	return Loot.roll_gear(r, int(tl["level"]), 0.0)

## Seconds of the expedition after which waves up to index k are done (for the live view).
static func waves_done_at(tl: Dictionary, t: float) -> int:
	var n := 0
	for pt in tl["pts"]:
		if float(pt[P_T]) <= t:
			n += 1
	return n
