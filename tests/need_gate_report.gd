extends SceneTree
## How much each specialist level asks for its answer: win rate of equal random parties
## with and without the answer. A gate should hurt without being a hard wall.
##   godot --headless --path . --script res://tests/need_gate_report.gd
## [answer, campaign level, hero level a typical player has there]
const GATES := [["aoe",12,16],["magic",13,16],["interrupt",14,17],["cleanse",18,23],["purge",21,24],["healer",22,26]]
const TRIES := 24
const HEAL_KINDS := ["heal","hot","hot_all","riptide","chain_heal","penance","shield","earth_shield","prayer"]
const DAMAGE_KINDS := ["damage","aoe_damage","dot","execute","seed","channel_aoe","explosive","summon","prism"]

func answers(m: Dictionary, need: String) -> bool:
	for s in m["spells"]:
		var d: Dictionary = Db.SPELLS[s["id"]]
		match need:
			"interrupt":
				if d["kind"] in ["interrupt","stun"] or d.get("interrupt",false): return true
			"cleanse":
				if d["kind"] in ["cleanse","mass_dispel"]: return true
			"purge":
				if d["kind"] in ["purge","mass_dispel"] or d.get("purge",false) or s["id"] == "shatter": return true
			"aoe":
				if d["kind"] in ["aoe_damage","channel_aoe","explosive","seed"]: return true
			"healer":
				if d["kind"] in HEAL_KINDS: return true
			"magic":
				if d["kind"] in DAMAGE_KINDS and d.get("school","magic") == "magic": return true
			"physical":
				if d["kind"] in DAMAGE_KINDS and d.get("school","magic") == "physical": return true
	return false

func party(rng: RandomNumberGenerator, need: String, level: int, covered: bool) -> Array:
	while true:
		var group := []
		for i in 4: group.append(MercGenerator.make(rng,level))
		var count := 0
		var healers := 0
		for m in group:
			if answers(m,need): count += 1
			if answers(m,"healer"): healers += 1
		# Only the tested answer differs: both sides are otherwise ordinary groups with healing.
		if (healers > 0 or need == "healer") and (count >= 1 if covered else count == 0): return group
	return []

func wins(need: String, level: int, hero: int, covered: bool) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900+level
	var won := 0
	for i in TRIES:
		var ex := Expedition.new()
		ex.record_events = false
		ex.start(level,"push",party(rng,need,hero,covered),100+i,true)
		while not ex.finished: ex.step_wave_headless()
		if ex.runs_won > 0: won += 1
	return won

func _init() -> void:
	var only := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--gate="): only = arg.trim_prefix("--gate=").to_int()
	for index in GATES.size():
		if only >= 0 and index != only: continue
		var gate: Array = GATES[index]
		for hero in [gate[2]-1,gate[2]+1,gate[2]+3]:
			print("%-9s | L%d | %d | %3d%% | %3d%%" % [gate[0],gate[1],hero,wins(gate[0],gate[1],hero,true)*100/TRIES,wins(gate[0],gate[1],hero,false)*100/TRIES])
	quit()
