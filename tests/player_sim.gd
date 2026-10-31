extends SceneTree
## Simulated real player: plays only through Rules.apply/Rules.tick on a virtual clock,
## so every number comes from the live rules, combat and rewards.
##   godot --headless --path . --script res://tests/player_sim.gd -- --runs=8 --target=30
## Each seed plays twice, with and without professions, to measure what they give.

const T0 := 1893456000.0     # Fixed start so daily limits behave the same in every run.
const MAX_DAYS := 120.0
const TRIES_BEFORE_AFK := 3  # Failed pushes with changed party/spells before going AFK.
const REROLLS_PER_TRY := 2
const HOUSEKEEPING := 120.   # Seconds of real play per visit to menus.
const PUSH_OVERHEAD := 20.
const AFK_MIN := 4.*3600.
const AFK_MAX := 8.*3600.
const BOX_GOLD_RESERVE := .5 # Share of gold boxes may take; the rest pays for mercs and crafts.
const BUILDS := {
	"melee": {"weapons":["sword","greatsword","shield"], "talents":["assault","bulwark","life","arcane"]},
	"caster": {"weapons":["staff"], "talents":["arcane","life","bulwark","assault"]},
	"archer": {"weapons":["bow"], "talents":["assault","arcane","life","bulwark"]},
	"healer": {"weapons":["staff"], "talents":["life","arcane","bulwark","assault"]},
}
const HEAL_KINDS := ["heal","hot","hot_all","riptide","chain_heal","penance","shield","earth_shield","prayer"]
const DAMAGE_KINDS := ["damage","aoe_damage","dot","execute","seed","channel_aoe","explosive","summon","prism"]

var rng := RandomNumberGenerator.new()
var blind := false

func _init() -> void:
	var runs := 8
	var first := 0
	var target := 30
	var merge := 0
	blind = "--blind" in OS.get_cmdline_user_args() # Ignores the level card, to price the specialist enemies.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="): runs = arg.trim_prefix("--runs=").to_int()
		if arg.begins_with("--first="): first = arg.trim_prefix("--first=").to_int()
		if arg.begins_with("--target="): target = arg.trim_prefix("--target=").to_int()
		if arg.begins_with("--merge="): merge = arg.trim_prefix("--merge=").to_int()
	var started := Time.get_ticks_msec()
	var results := {"with":[], "without":[]}
	if merge > 0: # Parallel runs write one shard each: --first=N --runs=1, then --merge=<count>.
		for i in merge:
			var shard = JSON.parse_string(FileAccess.get_file_as_string("res://build/qa/player_sim_%d.json" % i))
			results["with"].append_array(shard["with"])
			results["without"].append_array(shard["without"])
		report(results,target)
		quit()
		return
	var builds: Array = BUILDS.keys()
	for i in range(first,first+runs):
		var build: String = builds[i % builds.size()]
		for mode in ["with","without"]:
			var result := play(4242+i*17,build,mode == "with",target)
			results[mode].append(result)
			print("%-7s %-7s seed %d: L%d за %.1f дн (активно %.1f ч), герой %d, профессии %s" % [mode,build,i,result["closed"],result["hours"]/24.,result["active"]/3600.,result["hero"],result["profs"]])
	report(results,target)
	DirAccess.make_dir_recursive_absolute("res://build/qa")
	var file := FileAccess.open("res://build/qa/player_sim_%d.json" % first,FileAccess.WRITE)
	file.store_string(JSON.stringify(results))
	print("готово за %d с" % ((Time.get_ticks_msec()-started)/1000))
	quit()

# ------------------------------------------------------------------ one player

func play(seed_value: int, build: String, professions: bool, target: int) -> Dictionary:
	rng.seed = seed_value
	var now := T0
	var p := Rules.new_profile(seed_value,now)
	var run := {"build":build,"milestones":{},"attempts":0,"afk_sessions":0,"active":0.,"profs":{},"crafted_worn":0,"crafted_total":0,"potions":0,"upgrades":0,"gold_on_boxes":0,"rerolls":0,"stuck_at":{},"fails":{}}
	var farm_level := 0
	while int(p["closed_level"]) < target and now-T0 < MAX_DAYS*86400.:
		housekeeping(p,now,build,professions,run)
		now += HOUSEKEEPING
		run["active"] += HOUSEKEEPING
		var tries := 0
		while tries < TRIES_BEFORE_AFK and int(p["closed_level"]) < target:
			var level := int(p["closed_level"])+1
			prepare_party(p,now,build,tries,run,level)
			prepare_rotation(p,build,tries,level)
			if tries > 0 and professions: drink_potions(p,now,run)
			var started: Dictionary = Rules.apply(p,"start",{"level":level,"mode":"push"},now)
			if not started["ok"]:
				push_error("push refused: "+str(started))
				break
			var duration: float = float(p["expedition"]["tl"]["t_end"])
			now += duration+PUSH_OVERHEAD+1.
			run["active"] += duration+PUSH_OVERHEAD
			run["attempts"] += 1
			var ticked: Dictionary = Rules.tick(p,now)
			var closed: bool = not ticked["reports"].is_empty() and ticked["reports"][0].get("closed",false)
			if not closed and not ticked["reports"].is_empty():
				var key := "L%d/%d" % [level,int(ticked["reports"][0].get("waves",0))]
				run["fails"][key] = int(run["fails"].get(key,0))+1
			if closed:
				tries = 0
				run["milestones"][str(level)] = snapshot(p,now,run)
				housekeeping(p,now,build,professions,run)
				now += HOUSEKEEPING*.5
				run["active"] += HOUSEKEEPING*.5
			else:
				tries += 1
		if int(p["closed_level"]) >= target: break
		run["stuck_at"][str(int(p["closed_level"])+1)] = int(run["stuck_at"].get(str(int(p["closed_level"])+1),0))+1
		run["afk_sessions"] += 1
		var afk: float = rng.randf_range(AFK_MIN,AFK_MAX)
		if professions: start_gathering(p,now,afk)
		farm_level = maxi(1,mini(int(p["closed_level"]),farm_level+1 if farm_level > 0 else int(p["closed_level"])))
		if int(p["closed_level"]) > 0:
			prepare_party(p,now,build,0,run,farm_level)
			prepare_rotation(p,build,0,farm_level)
			Rules.apply(p,"start",{"level":farm_level,"mode":"farm"},now)
			var ending: float = now+afk
			var done: Dictionary = Rules.apply(p,"stop",{},ending)
			if done["ok"] and int(done["report"]["lost"]) > int(done["report"]["won"]):
				farm_level = maxi(1,farm_level-2) # Farm that wipes pays little: step back to a safer level.
		now += afk
	var last := snapshot(p,now,run)
	last["closed"] = int(p["closed_level"])
	last["build"] = build
	last["milestones"] = run["milestones"]
	last["attempts"] = run["attempts"]
	last["afk_sessions"] = run["afk_sessions"]
	last["stuck_at"] = run["stuck_at"]
	last["fails"] = run["fails"]
	last["active"] = run["active"]
	last["potions"] = run["potions"]
	last["upgrades"] = run["upgrades"]
	last["rerolls"] = run["rerolls"]
	return last

func snapshot(p: Dictionary, now: float, run: Dictionary) -> Dictionary:
	var profs := {}
	for prof in Prof.PROFESSIONS: profs[prof] = Rules.prof_level(p,prof)
	var best_ilvl := 0
	var crafted_ilvl := 0
	var crafted := 0
	var worn := 0
	var sum_ilvl := 0
	for slot in p["hero"]["equipped"]:
		var it = p["hero"]["equipped"][slot]
		if it == null: continue
		worn += 1
		sum_ilvl += int(it["ilvl"])
		best_ilvl = maxi(best_ilvl,int(it["ilvl"]))
		if it.get("crafted",false):
			crafted += 1
			crafted_ilvl = maxi(crafted_ilvl,int(it["ilvl"]))
	return {"hours":(now-T0)/3600.,"active":run["active"],"hero":int(p["hero"]["level"]),"gold":int(p["gold"]),"profs":profs,"worn":worn,"avg_ilvl":float(sum_ilvl)/maxf(worn,1),
		"best_ilvl":best_ilvl,"crafted_worn":crafted,"crafted_ilvl":crafted_ilvl,"spell_max":best_rotation_level(p),"power":Roster.power_score(Rules.hero_snapshot(p))}

func best_rotation_level(p: Dictionary) -> int:
	var best := 0
	for sid in p["hero"]["rotation"]: best = maxi(best,Roster.spell_best_level(p["collection"],sid))
	return best

# ------------------------------------------------------------------ menus

func housekeeping(p: Dictionary, now: float, build: String, professions: bool, run: Dictionary) -> void:
	if p.get("expedition") != null: Rules.apply(p,"stop",{},now)
	if professions: claim_professions(p,now)
	equip_best(p,build)
	merge_and_sell(p,build)
	upgrade_gear(p,run)
	open_boxes(p,now)
	for sid in p["collection"]:
		while Rules.can_fuse(p,sid): Rules.apply(p,"fuse",{"sid":sid},now)
	spend_talents(p,build)
	if professions: start_crafts(p,now,build)
	if professions and p.get("gathering") == null: start_gathering(p,now,AFK_MIN)

func stat_value(st: Dictionary, build: String) -> float:
	var attack: float = float(st.get("atk",0.))/maxf(.5,float(st.get("atk_speed",1.6)))
	var body: float = float(st["hp"])/8.+float(st.get("armor",0.))*1.5
	var tempo: float = (float(st.get("haste",0.))+float(st.get("crit",0.)))*400.
	match build:
		"melee": return attack*3.+float(st["str"])*2.+body+tempo
		"archer": return attack*3.+float(st["agi"])*2.+body+tempo
	return float(st["power"])*5.+body+tempo

func allowed(it: Dictionary, build: String) -> bool:
	return not it.has("wtype") or it["wtype"] in BUILDS[build]["weapons"]

func value_with(p: Dictionary, it: Dictionary, build: String) -> float:
	var hero: Dictionary = p["hero"].duplicate()
	hero["equipped"] = p["hero"]["equipped"].duplicate()
	Rules.place_item(hero["equipped"],it,it["slot"])
	return stat_value(Roster.hero_stats(hero),build)

func equip_best(p: Dictionary, build: String) -> void:
	var weapon = p["hero"]["equipped"]["weapon"]
	var wrong_weapon: bool = weapon != null and not allowed(weapon,build)
	var improved := true
	while improved:
		improved = false
		var current := stat_value(Roster.hero_stats(p["hero"]),build)
		var best_id := ""
		var best := current+.5
		for it in p["inventory"]:
			if not allowed(it,build): continue
			var value := value_with(p,it,build)
			if wrong_weapon and it["slot"] == "weapon": value += 100000.
			if value > best:
				best = value
				best_id = it["id"]
		if best_id != "":
			Rules.apply(p,"equip",{"id":best_id},0.)
			wrong_weapon = false
			improved = true

func merge_and_sell(p: Dictionary, build: String) -> void:
	for rarity in 3:
		while Rules.merge_candidates(p,rarity).size() > 0 and int(p["gold"]) > int(Rules.MERGE_GOLD[rarity])*3:
			if not Rules.apply(p,"merge_items",{"rarity":rarity},0.)["ok"]: break
	equip_best(p,build)
	for it in p["inventory"].duplicate():
		if int(it["rarity"]) < 2 or p["inventory"].size() > 12: Rules.apply(p,"sell",{"id":it["id"]},0.)

func upgrade_gear(p: Dictionary, run: Dictionary) -> void:
	var level := int(p["hero"]["level"])
	for slot in p["hero"]["equipped"]:
		var it = p["hero"]["equipped"][slot]
		if it == null or int(it["ilvl"]) >= level-3: continue
		var cost: Dictionary = Shop.upgrade_cost(it,level)
		if cost.is_empty() or int(p["gold"]) < int(cost["gold"])*2: continue
		if Rules.apply(p,"upgrade_item",{"id":it["id"],"pay":"gold"},0.)["ok"]: run["upgrades"] += 1

func open_boxes(p: Dictionary, now: float) -> void:
	if Rules.free_box_available(p,now): Rules.apply(p,"open_box",{"use":"free"},now)
	while int(p["boxes"]) > 0: Rules.apply(p,"open_pack",{"use":"token"},now)
	var budget := int(p["gold"]*BOX_GOLD_RESERVE)
	while budget >= Rules.BOX_PRICE and Rules.gold_boxes_left(p,now) > 0:
		if not Rules.apply(p,"open_box",{"use":"gold"},now)["ok"]: break
		budget -= Rules.BOX_PRICE

func spend_talents(p: Dictionary, build: String) -> void:
	var weapons := Loot.weapon_types(p["hero"]["equipped"])
	var spent := true
	while spent and Talents.points_free(p["hero"]) > 0:
		spent = false
		for branch in BUILDS[build]["talents"]:
			for id in Talents.TALENTS:
				var t: Dictionary = Talents.TALENTS[id]
				if t["branch"] == branch and Talents._active(t,weapons) and Rules.apply(p,"talent_up",{"id":id},0.)["ok"]:
					spent = true
					break
			if spent: break

# ------------------------------------------------------------------ party and spells

func niche(m: Dictionary) -> String:
	for s in m["spells"]:
		if Db.SPELLS[s["id"]]["kind"] in HEAL_KINDS and float(m["stats"].get("power",0.)) >= float(m["stats"].get("str",0.))*.9: return "healer"
	return "tank" if "shield" in m.get("weapons",[]) else "dps"

func merc_score(m: Dictionary) -> float:
	return float(Roster.power_score(m))

func wanted_niches(build: String) -> Array:
	if build == "healer": return ["tank","dps","dps"]
	return ["tank","healer","dps"]

func prepare_party(p: Dictionary, now: float, build: String, tries: int, run: Dictionary, level: int) -> void:
	var rerolls := REROLLS_PER_TRY*tries
	var needs := [] if blind else Db.level_needs(level)
	while true:
		reshape_party(p,build,needs)
		if tries > 0 and missing_needs(p,needs).is_empty() and rerolls < REROLLS_PER_TRY*tries: break
		if rerolls <= 0 or int(p["gold"]) < Rules.reroll_cost(p,now)*3: break
		if not Rules.apply(p,"reroll",{},now)["ok"]: break
		run["rerolls"] += 1
		rerolls -= 1
	order_party(p)

## A real player reads the level card: a merc who brings a missing answer is worth more.
func answers(spells: Array, weapons: Array, need: String) -> bool:
	for s in spells:
		var sid: String = s["id"] if s is Dictionary else s
		var d: Dictionary = Db.SPELLS[sid]
		match need:
			"interrupt":
				if d["kind"] in ["interrupt","stun"] or d.get("interrupt",false): return true
			"cleanse":
				if d["kind"] in ["cleanse","mass_dispel"]: return true
			"purge":
				if d["kind"] in ["purge","mass_dispel"] or d.get("purge",false) or sid == "shatter": return true
			"aoe":
				if d["kind"] in ["aoe_damage","channel_aoe","explosive","seed"]: return true
			"healer":
				if d["kind"] in HEAL_KINDS: return true
			"magic":
				if d["kind"] in DAMAGE_KINDS and d.get("school","magic") == "magic": return true
			"physical":
				if d["kind"] in DAMAGE_KINDS and d.get("school","magic") == "physical": return true
	return need == "physical" and not "staff" in weapons

func missing_needs(p: Dictionary, needs: Array) -> Array:
	var out := []
	var hero: Dictionary = Rules.hero_snapshot(p)
	for need in needs:
		var met: bool = answers(hero["spells"],hero["weapons"],need)
		for m in p["hired"]:
			met = met or answers(m["spells"],m.get("weapons",[]),need)
		if not met: out.append(need)
	return out

func reshape_party(p: Dictionary, build: String, needs: Array) -> void:
	var pool: Array = p["hired"].duplicate()
	pool.append_array(p["board"])
	var chosen := []
	var covered := {}
	for want in wanted_niches(build):
		var best = null
		for m in pool:
			if m in chosen: continue
			var score := merc_score(m)*(1.6 if niche(m) == want else 1.)
			for need in needs:
				if not covered.has(need) and answers(m["spells"],m.get("weapons",[]),need): score *= 1.35
			if best == null or score > best[0]: best = [score,m]
		chosen.append(best[1])
		for need in needs:
			if answers(best[1]["spells"],best[1].get("weapons",[]),need): covered[need] = true
	var outgoing := []
	for m in p["hired"]:
		if not m in chosen: outgoing.append(m["id"])
	for m in chosen:
		if not m in p["hired"]: Rules.apply(p,"replace",{"old":outgoing.pop_back(),"new":m["id"]},0.)

func order_party(p: Dictionary) -> void:
	var rank := func(id: String) -> int:
		if id == "hero":
			return 1
		var m = Rules.merc_by_id(p,id)
		var kind := niche(m)
		return 0 if kind == "tank" else (3 if kind == "healer" else 2)
	var order: Array = p["party_order"]
	for pass_index in order.size():
		for i in order.size()-1:
			if rank.call(order[i]) > rank.call(order[i+1]): Rules.apply(p,"move_party",{"index":i,"dir":1},0.)

func missing_needs_for_mercs(p: Dictionary, needs: Array) -> Array:
	var out := []
	for need in needs:
		var met := false
		for m in p["hired"]:
			met = met or answers(m["spells"],m.get("weapons",[]),need)
		if not met: out.append(need)
	return out

func spell_value(sid: String, lvl: int) -> float:
	var s: Dictionary = Db.SPELLS[sid]
	var pace: float = maxf(1.5,float(s.get("cd",0.)))+float(s.get("cast",0.))
	return float(s.get("mult",0.))*Db.spell_level_mult(lvl)/sqrt(pace)

func prepare_rotation(p: Dictionary, build: String, tries: int, level: int) -> void:
	var weapons := Loot.weapon_types(p["hero"]["equipped"])
	var pool := []
	var kinds: Array = HEAL_KINDS if build == "healer" else DAMAGE_KINDS
	for sid in p["collection"]:
		var s: Dictionary = Db.SPELLS[sid]
		if s["kind"] in kinds and Db.spell_usable(sid,weapons,p["hero"]["talents"]):
			pool.append(sid)
	pool.sort_custom(func(a, b): return spell_value(a,Roster.spell_best_level(p["collection"],a)) > spell_value(b,Roster.spell_best_level(p["collection"],b)))
	var rotation: Array = pool.slice(0,3)
	if tries >= 2 and pool.size() > 3:
		rotation[1] = pool[3]
	var slot := rotation.size()-1
	for need in missing_needs_for_mercs(p,[] if blind else Db.level_needs(level)):
		if slot < 1: break
		for sid in p["collection"]:
			if Db.spell_usable(sid,weapons,p["hero"]["talents"]) and not sid in rotation and answers([sid],weapons,need):
				rotation[slot] = sid
				slot -= 1
				break
	if not rotation.is_empty(): Rules.apply(p,"set_rotation",{"rotation":rotation},0.)

# ------------------------------------------------------------------ professions

func claim_professions(p: Dictionary, now: float) -> void:
	var g = p.get("gathering")
	if g != null and now >= float(g["ends_at"]): Rules.apply(p,"gather_claim",{},now)
	for prof in p["crafting"].keys():
		if now >= float(p["crafting"][prof]["ends_at"]): Rules.apply(p,"craft_claim",{"prof":prof},now)

func start_gathering(p: Dictionary, now: float, afk: float) -> void:
	if p.get("gathering") != null: return
	var prof: String = Prof.GATHERING[0]
	for option in Prof.GATHERING:
		if Rules.prof_level(p,option) < Rules.prof_level(p,prof): prof = option
	var loc := ""
	for id in Prof.locations_of(prof):
		if Rules.prof_level(p,prof) >= int(Prof.LOCATIONS[id]["req"]): loc = id
	var sec := 3600
	for option in Prof.DURATIONS:
		if float(option["sec"]) <= afk: sec = int(option["sec"])
	Rules.apply(p,"gather_start",{"prof":prof,"loc":loc,"sec":sec},now)

func start_crafts(p: Dictionary, now: float, build: String) -> void:
	for prof in Prof.CRAFTING:
		if p["crafting"].has(prof): continue
		var recipes: Array = Prof.recipes_of(prof)
		recipes.reverse()
		var chosen := ""
		var current := stat_value(Roster.hero_stats(p["hero"]),build)
		for id in recipes:
			if not Rules.can_craft(p,id)["ok"]: continue
			var r: Dictionary = Prof.RECIPES[id]
			if r.has("item"):
				var it := Prof.make_item(id,"preview")
				if allowed(it,build) and value_with(p,it,build) > current+1.:
					chosen = id
					break
			elif Rules.res_count(p,str(r["output"].keys()[0])) < 3:
				chosen = id
				break
		if chosen == "" and Rules.prof_level(p,prof) < Prof.MAX_LEVEL:
			recipes.reverse()
			for id in recipes:
				if Rules.can_craft(p,id)["ok"] and int(p["gold"]) > int(Prof.RECIPES[id]["gold"])*4:
					chosen = id
					break
		if chosen != "": Rules.apply(p,"craft_start",{"recipe":chosen},now)

func drink_potions(p: Dictionary, now: float, run: Dictionary) -> void:
	var buffs := Rules.active_buffs(p,now)
	if not buffs.has("dmg_mult"):
		for res in ["greater_strength_potion","minor_strength_potion"]:
			if Rules.res_count(p,res) > 0 and Rules.apply(p,"use_item",{"res":res},now)["ok"]:
				run["potions"] += 1
				break
	if not buffs.has("heal_mult") and Rules.res_count(p,"minor_recovery_potion") > 0 and Rules.apply(p,"use_item",{"res":"minor_recovery_potion"},now)["ok"]:
		run["potions"] += 1

# ------------------------------------------------------------------ report

func median(values: Array) -> float:
	if values.is_empty(): return NAN
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size()/2])

func report(results: Dictionary, target: int) -> void:
	for mode in ["with","without"]:
		var runs: Array = results[mode]
		var done := runs.filter(func(r): return int(r["closed"]) >= target)
		print("\n=== %s профессий: дошли до L%d %d из %d" % ["с" if mode == "with" else "без",target,done.size(),runs.size()])
		print("ур | дней | активно ч | герой | ср.ilvl | закл | шахта/трава/кожа | кузн/порт/алх | крафт на теле/ilvl")
		for level in range(5,target+1,5):
			var rows := []
			for r in runs:
				if r["milestones"].has(str(level)): rows.append(r["milestones"][str(level)])
			if rows.is_empty(): continue
			var pick := func(key: String) -> float: return median(rows.map(func(x): return x[key]))
			var prof := func(key: String) -> float: return median(rows.map(func(x): return x["profs"][key]))
			print("%2d | %5.1f | %6.1f | %3d | %4.1f | %2d | %d/%d/%d | %d/%d/%d | %d/%d" % [level,pick.call("hours")/24.,pick.call("active")/3600.,pick.call("hero"),pick.call("avg_ilvl"),pick.call("spell_max"),
				prof.call("mining"),prof.call("herbalism"),prof.call("skinning"),prof.call("blacksmithing"),prof.call("tailoring"),prof.call("alchemy"),pick.call("crafted_worn"),pick.call("crafted_ilvl")])
		var stuck := {}
		for r in runs:
			for level in r["stuck_at"]: stuck[level] = int(stuck.get(level,0))+int(r["stuck_at"][level])
		var keys: Array = stuck.keys()
		keys.sort_custom(func(a, b): return int(a) < int(b))
		var line := []
		for level in keys: line.append("L%s:%.1f" % [level,float(stuck[level])/runs.size()])
		print("AFK-сессий на уровень (среднее): ",", ".join(line))
		print("Зелий за игру: %.0f, улучшений вещей: %.0f, рероллов: %.0f" % [median(runs.map(func(r): return r["potions"])),median(runs.map(func(r): return r["upgrades"])),median(runs.map(func(r): return r["rerolls"]))])
	var pairs := []
	for i in results["with"].size():
		var a: Dictionary = results["with"][i]
		var b: Dictionary = results["without"][i]
		if int(a["closed"]) >= target and int(b["closed"]) >= target: pairs.append(float(b["hours"])-float(a["hours"]))
	if not pairs.is_empty(): print("\nПрофессии экономят (медиана по парам сидов): %.1f дней" % (median(pairs)/24.))
