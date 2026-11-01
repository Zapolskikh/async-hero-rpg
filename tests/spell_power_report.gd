extends SceneTree
## Compares every collectible spell by what it adds to a fight.
##   godot --headless --path . --script res://tests/spell_power_report.gd -- --seeds=40
## Options: --seeds=N, --levels=10,20,30, --only=heal,cleanse, --out=path.md
## A fixed party fights real enemies. Their strength is calibrated until a party with
## only the filler spell ends fights at margin 0, so any spell has room to change the result.
## Margin: won +(party hp left share), lost -(enemy hp left share).
## Value: margin with [spell, filler] minus margin with [filler], on the same seeds.

const SCENARIOS := {
	"boss": ["boss_titan"],
	"pack": ["brute","brute","ranged","caster"],
	"poison": ["plaguebearer","poisoner","warlock"],
	"ward": ["warden","warden","priest"],
	"casters": ["doomcaller","siren","brute"],
}
const FILLER := "arcane_bolt"
const TANK_FILLER := "strike"
const CALIBRATION_SEEDS := 16
const CALIBRATION_STEPS := 9
const ANOMALY_FLOOR := .05
const ANOMALY_MADS := 2.
const MIN_TIER_GROUP := 3
const RARITY := ["обычная","редкая","эпическая","легендарная"]
const ROLE_OF_KIND := {
	"damage":"damage","dot":"damage","execute":"damage","summon":"damage","prism":"damage",
	"aoe_damage":"aoe","channel_aoe":"aoe","seed":"aoe","explosive":"aoe",
	"heal":"healing","hot":"healing","hot_all":"healing","riptide":"healing","chain_heal":"healing",
	"shield":"healing","earth_shield":"healing","prayer":"healing","penance":"healing",
	"taunt":"tank","buff_self":"tank","self_shield":"tank",
}

var seeds := 40
var levels := [10,20,30]
var only: Array = []
var out_path := ""
var blocks := {}
var pressure := {}
var fights := 0

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="): seeds = arg.trim_prefix("--seeds=").to_int()
		elif arg.begins_with("--levels="): levels = Array(arg.trim_prefix("--levels=").split(",")).map(func(v): return int(v))
		elif arg.begins_with("--only="): only = Array(arg.trim_prefix("--only=").split(","))
		elif arg.begins_with("--out="): out_path = arg.trim_prefix("--out=")
	var t0 := Time.get_ticks_msec()
	calibrate()
	var calibrated := Time.get_ticks_msec()
	var rows := measure()
	var measured := Time.get_ticks_msec()
	var text := report(rows)
	print(text)
	if out_path != "":
		var f := FileAccess.open(out_path,FileAccess.WRITE)
		f.store_string(text)
		f.close()
	print("%d fights: calibration %.1f s, measuring %.1f s, %.2f ms per fight" % [fights,(calibrated-t0)/1000.,(measured-calibrated)/1000.,float(measured-t0)/maxi(1,fights)])
	quit()

func spell_ids() -> Array:
	var ids := []
	for id in Db.SPELLS:
		var s: Dictionary = Db.SPELLS[id]
		if not s.get("enemy",false) and not s.get("hidden",false) and (only.is_empty() or id in only):
			ids.append(id)
	return ids

func role(id: String) -> String:
	var s: Dictionary = Db.SPELLS[id]
	return "aoe" if "aoe" in s.get("tags",[]) else ROLE_OF_KIND.get(s["kind"],"utility")

func weapons_for(id: String) -> Array:
	var req: Array = Db.SPELLS[id].get("req",[])
	if role(id) == "tank" or "shield" in req:
		return ["sword","shield"]
	if Db.SPELLS[id].has("bonus"):
		return [Db.SPELLS[id]["bonus"]["w"]]
	return [req[0]] if not req.is_empty() else ["staff"]

## Average geared stats for this weapon, with one main stat so spells compare fairly.
func stat_block(level: int, weapons: Array) -> Dictionary:
	var key := "%d:%s" % [level,",".join(weapons)]
	if blocks.has(key):
		return blocks[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7+level
	var sum := {}
	var main := 0.
	const SAMPLES := 32
	for i in SAMPLES:
		var st: Dictionary = MercGenerator.make(rng,level,weapons)["stats"]
		main += maxf(st["str"],maxf(st["agi"],st["power"]))/SAMPLES
		for k in st:
			if typeof(st[k]) in [TYPE_FLOAT,TYPE_INT]:
				sum[k] = sum.get(k,0.)+float(st[k])/SAMPLES
	for k in ["str","agi","power"]:
		sum[k] = main
	blocks[key] = sum
	return sum

func member(level: int, slot: int, weapons: Array, rotation: Array) -> BattleUnit:
	var lvl := Roster.baseline_spell_level(level)
	var spells := rotation.map(func(id): return {"id":id,"lvl":lvl})
	return BattleUnit.new(slot,0,slot,{"name":"QA","stats":stat_block(level,weapons).duplicate(),"weapons":weapons,"talents":{},"spells":spells})

## The tested seat is the tank for tank spells, otherwise a damage dealer behind the tank.
func party(level: int, weapons: Array, rotation: Array, is_tank: bool) -> Array:
	var seat := member(level,0 if is_tank else 1,weapons,rotation)
	var other := member(level,1 if is_tank else 0,["staff"] if is_tank else ["sword","shield"],["fireball"] if is_tank else [TANK_FILLER])
	var group := [seat,other] if is_tank else [other,seat]
	group.append(member(level,2,["staff"],["fireball"]))
	group.append(member(level,3,["staff"],["heal","renew"]))
	return group

func enemies(level: int, scenario: String, scale: float) -> Array:
	var snaps := []
	for id in SCENARIOS[scenario]:
		var snap: Dictionary = Expedition.enemy_snapshot(id,level)
		for k in ["hp","atk","power","start_shield"]:
			if snap["stats"].has(k):
				snap["stats"][k] *= scale
		snaps.append(snap)
	return snaps

func fight(level: int, scenario: String, scale: float, weapons: Array, rotation: Array, is_tank: bool, seed_value: int) -> Dictionary:
	fights += 1
	var sim := BattleSim.new()
	sim.record_events = false
	sim.setup(party(level,weapons,rotation,is_tank),enemies(level,scenario,scale),seed_value)
	sim.run_to_end()
	var hp := [0.,0.]
	var total := [0.,0.]
	for u in sim.units:
		hp[u.side] += maxf(0.,u.hp)
		total[u.side] += u.max_hp
	var seat: BattleUnit = sim.units[0 if is_tank else 1]
	var id: String = rotation[0]
	var result := {"margin":hp[0]/total[0] if sim.won else -hp[1]/total[1],"won":sim.won,"time":sim.time,
		"output":seat.dealt_by.get(id,0.)+seat.healed_by.get(id,0.)}
	sim.release()
	return result

func margins(level: int, scenario: String, scale: float, weapons: Array, rotation: Array, is_tank: bool, count: int) -> Array:
	var out := []
	for i in count:
		out.append(fight(level,scenario,scale,weapons,rotation,is_tank,1000+i))
	return out

func mean(results: Array, key: String) -> float:
	var total := 0.
	for r in results:
		total += float(r[key])
	return total/maxi(1,results.size())

func calibrate() -> void:
	for level in levels:
		for scenario in SCENARIOS:
			var low := .05
			var high := 8.
			for i in CALIBRATION_STEPS:
				var mid := sqrt(low*high)
				if mean(margins(level,scenario,mid,["staff"],[FILLER],false,CALIBRATION_SEEDS),"margin") > 0.:
					low = mid
				else:
					high = mid
			pressure["%d:%s" % [level,scenario]] = sqrt(low*high)

func measure() -> Array:
	var baselines := {}
	var rows := []
	for id in spell_ids():
		var weapons := weapons_for(id)
		var is_tank: bool = role(id) == "tank"
		var filler: String = TANK_FILLER if is_tank else FILLER
		for level in levels:
			for scenario in SCENARIOS:
				var scale: float = pressure["%d:%s" % [level,scenario]]
				var key := "%d:%s:%s:%s" % [level,scenario,",".join(weapons),is_tank]
				if not baselines.has(key):
					baselines[key] = margins(level,scenario,scale,weapons,[filler],is_tank,seeds)
				var base: Array = baselines[key]
				var runs := margins(level,scenario,scale,weapons,[id,filler],is_tank,seeds)
				var deltas := []
				for i in seeds:
					deltas.append({"margin":runs[i]["margin"]-base[i]["margin"]})
				var value := mean(deltas,"margin")
				var spread := 0.
				for d in deltas:
					spread += pow(d["margin"]-value,2)
				rows.append({"id":id,"level":level,"scenario":scenario,"value":value,
					"error":sqrt(spread/maxi(1,seeds-1)/seeds),"win":mean(runs.map(func(r): return {"w":1. if r["won"] else 0.}),"w"),
					"base":mean(base,"margin"),"output":mean(runs.map(func(r): return {"o":r["output"]/r["time"]}),"o"),"idle":spread == 0. and value == 0.})
	return rows

func median(values: Array) -> float:
	var v := values.duplicate()
	v.sort()
	if v.is_empty():
		return 0.
	return v[v.size()/2] if v.size()%2 else (v[v.size()/2-1]+v[v.size()/2])/2.

## Utility answers one problem, so it is judged by its best scenario; the rest by the average.
func score_spells(rows: Array) -> Array:
	var out := []
	for id in spell_ids():
		var own := rows.filter(func(r): return r["id"] == id)
		var by_scenario := {}
		for r in own:
			by_scenario[r["scenario"]] = by_scenario.get(r["scenario"],0.)+r["value"]/levels.size()
		var best: String = by_scenario.keys()[0]
		var total := 0.
		for k in by_scenario:
			total += by_scenario[k]
			if by_scenario[k] > by_scenario[best]:
				best = k
		var average: float = total/by_scenario.size()
		var r_role := role(id)
		var error := sqrt(own.reduce(func(acc,r): return acc+r["error"]*r["error"],0.))/own.size()
		out.append({"id":id,"role":r_role,"rarity":int(Db.SPELLS[id]["rarity"]),"score":by_scenario[best] if r_role == "utility" else average,
			"average":average,"best":best,"best_value":by_scenario[best],"error":error,"scenarios":by_scenario,
			"idle":own.all(func(r): return r["idle"])})
	return out

func mark_anomalies(spells: Array) -> void:
	for s in spells:
		var tier := spells.filter(func(o): return o["role"] == s["role"] and o["rarity"] == s["rarity"])
		var peers := tier if tier.size() >= MIN_TIER_GROUP else spells.filter(func(o): return o["role"] == s["role"])
		var mid := median(peers.map(func(o): return o["score"]))
		var mad := median(peers.map(func(o): return absf(o["score"]-mid)))
		var limit := maxf(ANOMALY_FLOOR,ANOMALY_MADS*mad)
		s["mid"] = mid
		s["flag"] = "слишком сильная" if s["score"] > mid+limit else ("слишком слабая" if s["score"] < mid-limit else "")
		if s["idle"]:
			s["flag"] = "не срабатывает"

func report(rows: Array) -> String:
	var spells := score_spells(rows)
	mark_anomalies(spells)
	spells.sort_custom(func(a,b): return [a["role"],-a["score"]] < [b["role"],-b["score"]])
	var lines := ["# Сила способностей","","Сиды: %d. Уровни: %s. Ценность: изменение запаса боя относительно одного филлера, от -2 до +2." % [seeds,str(levels)],"",
		"## Калибровка: множитель силы врагов","","| Уровень | "+" | ".join(SCENARIOS.keys())+" |","|---|"+"---|".repeat(SCENARIOS.size())]
	for level in levels:
		lines.append("| %d | " % level+" | ".join(SCENARIOS.keys().map(func(k): return "%.2f" % pressure["%d:%s" % [level,k]]))+" |")
	lines += ["","## Рейтинг","","| Роль | Способность | Тир | Оценка | ± | Медиана | Лучший сценарий | "+" | ".join(SCENARIOS.keys())+" | Статус |","|---|---|---|---|---|---|---|"+"---|".repeat(SCENARIOS.size())+"---|"]
	for s in spells:
		lines.append("| %s | %s | %s | %+.3f | %.3f | %+.3f | %s | %s | %s |" % [s["role"],s["id"],RARITY[s["rarity"]],s["score"],s["error"],s["mid"],s["best"],
			" | ".join(SCENARIOS.keys().map(func(k): return "%+.2f" % s["scenarios"].get(k,0.))),s["flag"]])
	lines += ["","## Лестница тиров: медиана оценки","","| Роль | обычная | редкая | эпическая | легендарная |","|---|---|---|---|---|"]
	for r in ["damage","aoe","healing","utility","tank"]:
		var cells := []
		for tier in 4:
			var group := spells.filter(func(o): return o["role"] == r and o["rarity"] == tier)
			cells.append("%+.3f (%d)" % [median(group.map(func(o): return o["score"])),group.size()] if not group.is_empty() else "—")
		lines.append("| %s | %s |" % [r," | ".join(cells)])
	var flagged := spells.filter(func(s): return s["flag"] != "")
	lines += ["","## Аномалии: %d" % flagged.size(),""]
	for s in flagged:
		lines.append("- %s (%s, %s): %+.3f при медиане %+.3f, %s" % [s["id"],s["role"],RARITY[s["rarity"]],s["score"],s["mid"],s["flag"]])
	return "\n".join(lines)
