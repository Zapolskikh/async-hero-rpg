extends SceneTree
## Campaign/AFK balance regressions; includes real combat and saved timeline migration.
const T0 := 1_800_000_000.0
var failures := 0
func check(ok: bool, label: String) -> void:
	print("  ", "ok " if ok else "FAIL ", label)
	if not ok: failures += 1

func farm_profile(hl: int = 4, stage: int = 4, hourly: float = 4000.0) -> Dictionary:
	var p := Rules.new_profile(42, T0)
	p["hero"]["level"] = hl
	p["closed_level"] = stage
	p["expedition"] = {"id":"fixture", "mode":"farm", "level":stage, "seed":42, "first":false,
		"party":Rules.party_snapshots(p), "started_at":T0, "collected":Expedition.zero_point(),
		"tl":{"mode":"farm", "level":stage, "seed":42, "reward_version":12, "combat_version":9,
		"pts":[Expedition.zero_point()], "items":[], "sim_until":0.0,
		"rate":[0.0, 200.0/3600.0, hourly/3600.0, 0.0, 0.0, 0.0, 1.0/180.0, 0.0, 0.0, {}, 1.0]}}
	return p

func _init() -> void:
	test_collections()
	test_restart()
	test_migration()
	test_real_combat()
	print("PROGRESSION FAILURES: ", failures)
	quit(1 if failures else 0)

func test_collections() -> void:
	for boosted in [false, true]:
		var once := farm_profile()
		if boosted: once["buffs"]["farm_x2"] = {"from":T0+413.0,"until":T0+7613.0}
		var frequent := once.duplicate(true)
		var preview := Rules.pending(once,T0+43200.)
		var report: Dictionary = Rules.apply(once,"collect",{},T0+43200.)["report"]
		for seconds in range(300,43201,300):
			Rules.apply(frequent,"collect",{},T0+seconds)
		check(once["hero"] == frequent["hero"], "frequent collect keeps XP across levels/soft penalty; boost="+str(boosted))
		check(once["boxes"] == frequent["boxes"] and once["boxes"] == 7, "six AFK boxes per 12 successful hours, independent of collect/boost")
		check(once["gold"] == frequent["gold"], "boost boundaries preserve gold under frequent collects")
		check(preview["xp"] == report["xp"] and preview["boxes"] == report["boxes"] and preview["gold"] == report["gold"], "preview equals awarded rewards")
		var empty: Dictionary = Rules.apply(once,"collect",{},T0+43200.)["report"]
		check(empty["xp"] == 0 and empty["boxes"] == 0 and empty["gold"] == 0, "repeat collect gives nothing")
	var cap := farm_profile()
	Rules.apply(cap,"collect",{},T0+86400.*7)
	var before := cap.duplicate(true)
	var again: Dictionary = Rules.apply(cap,"collect",{},T0+86400.*7)["report"]
	check(cap["boxes"] == 7 and again["boxes"] == 0 and again["xp"] == 0 and again["gold"] == 0, "12h cap cannot be drained with repeated clicks after a week")
	check(cap["hero"] == before["hero"], "repeat capped collect preserves hero")
	var over := farm_profile(15,4,Db.farm_xp_per_hour(4))
	var old: Dictionary = Rules.apply(over,"collect",{},T0+43200.)["report"]
	check(old["xp"] < 50 and over["hero"]["level"] == 15, "outgrown stage XP is heavily reduced")
	var early := farm_profile(4,4,Db.farm_xp_per_hour(4))
	Rules.apply(early,"collect",{},T0+28800.)
	check(early["hero"]["level"] >= 5 and early["hero"]["level"] <= 6, "8h successful stage 1-4: hero 4 -> 5-6")
	var capped := farm_profile(30)
	Rules.apply(capped,"collect",{},T0+43200.)
	check(capped["hero"]["xp"] == 0 and capped["boxes"] == 7, "max-level hero still earns AFK spell boxes")

func test_restart() -> void:
	var p := farm_profile()
	Rules.apply(p,"stop",{},T0+3600.)
	check(p["boxes"] == 1 and absf(p["farm_box_work"]-3600.) < 0.001, "half box retained after stop")
	# Load/save and start another stage, with a different simulated farm speed.
	p = JSON.parse_string(JSON.stringify(p))
	Rules.migrate(p,T0+3600.)
	var next := farm_profile(4,5)
	p["expedition"] = next["expedition"]
	p["expedition"]["started_at"] = T0+3600.
	Rules.apply(p,"stop",{},T0+7200.)
	check(p["boxes"] == 2 and absf(p["farm_box_work"]) < 0.001, "box progress survives JSON/restart/stage switch")

func test_migration() -> void:
	var p := farm_profile(15,4,500.)
	p["v"] = 11
	p["hero"]["xp"] = int(Db.legacy_xp_to_next(15)/2)
	p["expedition"]["tl"].erase("reward_version")
	p["expedition"]["tl"]["pts"][0].pop_back()
	p["expedition"]["tl"]["rate"].pop_back()
	p["expedition"]["collected"].pop_back()
	var expected := p.duplicate(true)
	Rules._add_xp(expected,3000)
	var expected_xp := int(floor(float(expected["hero"]["xp"])/Db.legacy_xp_to_next(15)*Db.xp_to_next(15)))
	Rules.migrate(p,T0+21600.)
	check(p["v"] == 12 and p["hero"]["level"] == 15 and p["hero"]["xp"] == expected_xp, "old XP settled using old curve, level and percentage retained")
	check(p["expedition"]["tl"]["reward_version"] == 12 and p["expedition"]["started_at"] == T0+21600., "old farm restarted once under new rewards")
	var again := JSON.stringify(p)
	Rules.migrate(p,T0+21600.)
	check(JSON.stringify(p) == again, "migration is idempotent")
	var idle := Rules.new_profile(9,T0)
	idle["v"] = 11
	idle["hero"]["level"] = 12
	idle["hero"]["xp"] = int(Db.legacy_xp_to_next(12)*.75)
	Rules.migrate(idle,T0)
	check(idle["hero"]["level"] == 12 and absf(float(idle["hero"]["xp"])/Db.xp_to_next(12)-.75)<.001, "idle save retains XP bar percentage")
	var attempt := Rules.new_profile(7,T0)
	Rules.apply(attempt,"start",{"level":1,"mode":"push"},T0)
	attempt["v"] = 11
	attempt["expedition"]["tl"].erase("reward_version")
	var elapsed := float(attempt["expedition"]["tl"]["pts"][0][0])
	Rules.migrate(attempt,T0+elapsed)
	check(attempt["expedition"] != null and attempt["expedition"]["started_at"] == T0, "unfinished push resumes from original start")
	check(Rules.pending(attempt,T0+elapsed)["xp"] == 0, "settled push waves are not paid twice after migration")
	check(not Rules.level_unlocked(attempt,0), "zero/negative campaign stage is rejected")

func test_real_combat() -> void:
	var p := Rules.new_profile(7,T0)
	p["hero"]["level"] = 6
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in p["hired"].size():
		p["hired"][i] = Roster.relevel(rng,p["hired"][i],6,MercGenerator.power_ref(p))
	var party := Rules.party_snapshots(p)
	var push := Expedition.build_timeline(4,"push",party,7,true)
	check(push["won"], "representative party clears stage 4")
	var xp: int = push["pts"][-1][Expedition.P_XP]
	check(xp >= Db.first_clear_xp(4) and xp-Db.first_clear_xp(4) < xp*.1, "over 90% push XP paid only on first victory")
	var tl := Expedition.build_timeline(4,"farm",party,7,false)
	var rewards := Expedition.rewards_at(tl,43200.)
	check(rewards[Expedition.P_XP] <= Db.farm_xp_per_hour(4)*12, "successful farm respects stage hourly XP budget")
	check(rewards[Expedition.P_BOXES] >= 5 and rewards[Expedition.P_BOXES] <= 6, "real 12h farm produces boxes even with zero boxes in sample window")
	check(xp > float(tl["rate"][Expedition.P_XP])/float(tl["rate"][Expedition.P_WON])*20., "first victory far outweighs one farm repeat")
	var live := Expedition.new()
	live.record_events = false
	live.start(4,"farm",party,7,false)
	while live.elapsed < tl["sim_until"]-.01: live.step_wave_headless()
	check(live.xp == tl["pts"][-1][Expedition.P_XP] and is_equal_approx(live.farm_work,float(tl["pts"][-1][Expedition.P_WORK])), "live and authoritative farm agree")
	live.sim.release()
	# An incapable party must not gain boxes or meaningful XP from repeated wipes.
	var weak := Rules.new_profile(42,T0)
	var bad := Expedition.build_timeline(4,"farm",Rules.party_snapshots(weak),42,false)
	var bad_rewards := Expedition.rewards_at(bad,43200.)
	check(bad_rewards[Expedition.P_WON] == 0 and bad_rewards[Expedition.P_BOXES] == 0, "zero victories -> zero AFK boxes")
	check(bad_rewards[Expedition.P_XP] <= Db.farm_xp_per_hour(4)*12*.1, "wipe farming capped at 10% successful XP")
	var failed := Expedition.build_timeline(4,"push",Rules.party_snapshots(weak),42,true)
	check(not failed["won"] and failed["pts"][-1][Expedition.P_XP] <= Db.farm_xp_per_hour(4)*float(failed["t_end"])/3600.*.1, "failed pushes cannot bypass AFK XP nerf")
