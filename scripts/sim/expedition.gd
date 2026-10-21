class_name Expedition
extends RefCounted
## An AFK expedition on one campaign level (concept 7.1).
##   push: a single attempt at a level. A wipe ends it with partial rewards.
##   farm: a closed level looped forever; each run gives full rewards.
## HP carries over between waves, so sustain matters over a whole level.

const WAVE_PAUSE := 1.5
const BETWEEN_WAVE_HEAL := 0.25
const FIRST_CLEAR_RARITY_BONUS := 0.25
const FARM_DROP_CHANCE := 0.35

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
var last_reason := ""

var rng := RandomNumberGenerator.new()
var record_events := true

func start(p_level: int, p_mode: String, p_party: Array, p_seed: int, p_first_clear: bool) -> void:
	level = p_level
	mode = p_mode
	party = p_party.duplicate(true)
	base_seed = p_seed
	first_clear_pending = p_first_clear
	rng.seed = p_seed
	_start_run()

func waves() -> Array:
	return Db.LEVELS[level - 1]["waves"]

func _start_run() -> void:
	allies.clear()
	for i in party.size():
		allies.append(BattleUnit.new(i, 0, i, party[i]))
	wave_index = 0
	_start_wave()

func _start_wave() -> void:
	var snaps := []
	for eid in waves()[wave_index]:
		snaps.append(enemy_snapshot(eid, level))
	sim = BattleSim.new()
	sim.record_events = record_events
	sim.setup(allies, snaps, base_seed + run_index * 97 + wave_index * 13)

static func enemy_snapshot(eid: String, lvl: int) -> Dictionary:
	var e: Dictionary = Db.ENEMIES[eid]
	var sc := Db.enemy_scale(lvl)
	var spells := []
	for s in e["spells"]:
		spells.append({"id": s, "lvl": 1})
	return {
		"name": e["name"], "color": e["color"], "boss": e.get("boss", false), "target": e["target"],
		"sprite": e.get("sprite", ""), "ranged": e.get("ranged", false),
		"stats": {
			"hp": e["hp"] * sc, "atk": e["atk"] * sc, "power": e["power"] * sc,
			"armor": e["armor"] * (1.0 + 0.12 * (lvl - 1)), "haste": e["haste"], "crit": 0.05,
		},
		"spells": spells,
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
			gold += int(round(5.0 * pow(sc, 0.85) * mult))
			xp += int(round(6.0 * level * mult))
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
		xp += 30 * level
		if mode == "push":
			gold += 40 * level
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
		"won": runs_won, "lost": runs_lost, "closed": level_closed_now}
	gold = 0
	xp = 0
	kills = 0
	items.clear()
	boxes = 0
	runs_won = 0
	runs_lost = 0
	level_closed_now = false
	return r

func has_rewards() -> bool:
	return gold > 0 or xp > 0 or not items.is_empty() or boxes > 0
