extends SceneTree
var failures := 0
var assertions := 0

func check(condition: bool, text: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		print("FAIL ",text)

func unit(id: int = 0, weapons: Array = ["sword","shield"], talents: Dictionary = {}) -> BattleUnit:
	return BattleUnit.new(id,0,id,{"name":"QA","stats":{"hp":10000.,"atk":50.,"str":100.,"agi":80.,"power":100.,"armor":0.,"crit":0.},"weapons":weapons,"talents":talents,"spells":[]})

func enemy() -> Dictionary:
	return {"name":"Target","stats":{"hp":100000.,"atk":0.,"power":100.,"armor":0.,"crit":0.},"spells":[]}

func battle(allies: Array) -> BattleSim:
	var sim := BattleSim.new()
	sim.setup(allies,[enemy(),enemy(),enemy()],42)
	return sim

func _init() -> void:
	test_catalog()
	test_every_spell()
	test_every_talent()
	test_taunts()
	test_healing()
	test_weapons_and_damage()
	test_defensive_spells()
	test_vengeance_and_dual_weapons()
	test_migration()
	test_specialist_enemies()
	print("COMBAT V9: %d assertions, %d failures" % [assertions,failures])
	quit(1 if failures else 0)

func test_specialist_enemies() -> void:
	var sim := battle([unit(0),unit(1)])
	var foe: BattleUnit = sim.units[2]
	foe.stats["magic_resist"] = .5
	foe.armor = 0.
	var plain: BattleUnit = sim.units[3]
	var hero: BattleUnit = sim.units[0]
	hero.crit = 0.
	var resisted := sim._deal(hero,foe,100.,false,false,"fireball",true,"magic")
	var full := sim._deal(hero,plain,100.,false,false,"fireball",true,"magic")
	check(resisted == full*.5,"magic resistance cuts spell damage")
	check(sim._deal(hero,foe,100.,false,false,"attack",true,"physical") == full,"magic resistance ignores physical damage")
	var boss: BattleUnit = sim.units[4]
	boss.stats["enrage"] = 1.
	var base: float = boss.dmg_mult
	for tick in int(1.2/sim.STEP): sim._tick(boss)
	check(boss.counters.has("enraged") and boss.dmg_mult > base and boss.haste > 0.,"enrage strengthens a boss at its timer")
	var once: float = boss.dmg_mult
	for tick in int(1.2/sim.STEP): sim._tick(boss)
	check(boss.dmg_mult == once,"enrage happens once")
	check(sim._find_spell_target(boss,"e_ward") != null,"ward needs an unshielded ally")
	sim._cast(boss,"e_ward",1,boss)
	for f in sim.side_units(1): check(f.shield > 0.,"ward shields every enemy")
	check(sim._find_spell_target(boss,"e_ward") == null,"ward waits until shields are gone")
	sim._purge(foe)
	check(foe.shield <= 0.,"purge answers the ward")
	sim._cast(boss,"e_silence",1,hero)
	check(hero.silence > 0.,"siren song silences its target")
	hero.hp = hero.max_hp*.2
	foe.target_rule = "weak"
	check(sim.pick_target(foe) == hero,"weak rule hunts the most wounded")
	sim.release()
	var known := ["interrupt","cleanse","purge","aoe","physical","magic","healer"]
	var seen := {}
	for level in range(1,Db.level_count()+1):
		for need in Db.level_needs(level):
			check(need in known,"known level need: "+need)
			seen[need] = true
		for wave in Db.level_waves(level):
			for id in wave:
				check(ResourceLoader.exists("res://assets/units/%s.png" % Db.ENEMIES[id]["sprite"]),"enemy sprite exists: "+id)
				if Db.ENEMIES[id].has("need"): check(Db.ENEMIES[id].has("hint"),"answer is announced: "+id)
	check(seen.size() == known.size(),"campaign asks for every specialisation")

func test_catalog() -> void:
	check(Talents.TALENTS.size() == 64,"64 talents")
	for br in Talents.BRANCHES:
		var count := 0
		var ranks := 0
		for id in Talents.TALENTS:
			if Talents.TALENTS[id]["branch"] == br["id"]:
				count += 1
				ranks += Talents.TALENTS[id]["ranks"]
		check(count == 16 and ranks == 51,"16 talents / 51 ranks: " + br["id"])
	var count := 0
	for id in Db.SPELLS:
		if not Db.SPELLS[id].get("enemy",false) and not Db.SPELLS[id].get("hidden",false):
			count += 1
			check(ResourceLoader.exists("res://assets/icons/sp_%s.png"%id),"icon: "+id)
	check(count == 50,"50 collectible spells")

func test_every_spell() -> void:
	for id in Db.SPELLS:
		var s: Dictionary = Db.SPELLS[id]
		if s.get("enemy",false) or s.get("hidden",false):
			continue
		var req: Array = s.get("req",["sword","shield"])
		var u := unit(0,req)
		var ally := unit(1)
		var sim := battle([u,ally])
		ally.hp = 3000.
		u.hp = 5000.
		var target: BattleUnit = sim.pick_target(u)
		if s["kind"] in ["heal","hot","riptide","chain_heal","shield","cleanse","prayer","earth_shield","penance"]:
			target = ally
		if s["kind"] in ["taunt","buff_all","buff_self","hot_all","rally","self_shield","summon"]:
			target = u
		sim._cast(u,id,1,target)
		for tick in 160:
			sim.step()
		check(u.hp >= 0. and u.hp <= u.max_hp and ally.hp <= ally.max_hp,"valid combat state: "+id)
		sim.release()

func test_every_talent() -> void:
	for id in Talents.TALENTS:
		var talents := {id:Talents.TALENTS[id]["ranks"]}
		var w: String = Talents.TALENTS[id].get("w","sword")
		var weapons: Array = ["sword","sword"] if w == "dual" else [w,"shield"]
		var u := unit(0,weapons,talents)
		var ally := unit(1)
		var sim := battle([u,ally])
		u.spells = [{"id":"ignite","lvl":1},{"id":"heal","lvl":1},{"id":"fireball","lvl":1}]
		u.hp = 4500.
		ally.hp = 4500.
		for tick in 150:
			sim.step()
		check(u.hp <= u.max_hp and u.hp >= 0.,"talent smoke: "+id)
		sim.release()

func test_taunts() -> void:
	var a := unit(0,["sword","shield"],{"relentless":4})
	var b := unit(1)
	var sim := battle([a,b])
	var foe: BattleUnit = sim.foes_of(a)[0]
	sim._cast(a,"taunt",1,a)
	check(a.shield == 0. and a.taunt == 14.,"taunt has no shield, talent adds 8 seconds")
	sim._cast(b,"taunt",1,b)
	check(sim.pick_target(foe) == b and a.taunt == 0.,"latest tank takes aggro")
	b.taunt = 0.
	check(sim.pick_target(foe) == a,"expired new taunt falls back to normal front target")
	a.spells = [{"id":"taunt","lvl":1}]
	var gaps := 0
	for tick in 300:
		sim.step()
		if a.taunt <= 0.:
			gaps += 1
	check(gaps == 0,"max talent taunt refreshes on cooldown with no gap")
	sim.release()

func test_healing() -> void:
	var h := unit(0,["staff"],{"living_cover":3,"healing_trail":3,"shared_care":3,"reserve":3})
	var a := unit(1)
	var b := unit(2)
	var sim := battle([h,a,b])
	a.hp = 1000.
	b.hp = 1000.
	sim._hot(h,a,"renew",20.,6.)
	sim._heal(h,a,100.,false,"heal",true)
	check(is_equal_approx(a.hp,1120.) and b.hp > 1000.,"direct heal triggers immediate HoT and shared care")
	sim._heal(h,a,100.,false,"heal",true)
	check(a.hp > 1240.,"living cover has no three-second restriction")
	a.hp = a.max_hp-10.
	sim._heal(h,a,100.,false,"heal",true)
	check(a.shield > 0. and a.shield <= a.max_hp*.1,"overheal becomes capped reserve shield")
	a.shield = 0.
	sim._cast(h,"earth_shield",1,a)
	a.hp = 5000.
	sim._deal(sim.foes_of(h)[0],a,100.,false,false,"attack")
	check(a.buffs["earth_shield"]["charges"] == 4 and a.hp > 4900.,"earth shield spends a healing charge")
	sim._cast(h,"prayer",1,a)
	sim._deal(sim.foes_of(h)[0],a,100.,false,false,"attack")
	check(not a.buffs.has("prayer") and (h.buffs.has("prayer") or b.buffs.has("prayer")),"mending prayer heals and jumps")
	sim.release()
	var r := unit(0,["staff"],{"resurrection":1})
	var dead := unit(1)
	var revived := battle([r,dead])
	dead.hp = 0.
	revived.step()
	check(dead.hp == dead.max_hp*.5 and r.spent.has("resurrection"),"resurrection works once per run")
	dead.hp = 0.
	revived.step()
	check(dead.hp == 0.,"resurrection does not repeat")
	revived.release()

func test_weapons_and_damage() -> void:
	var u := unit(0,["sword","sword"],{"throwing":3})
	var sim := battle([u])
	check(sim._usable(u,"aimed_shot") and is_equal_approx(sim._amount(u,"aimed_shot",1),300.),"throwing uses strength at full rank")
	var target: BattleUnit = sim.foes_of(u)[0]
	sim._cast(u,"cleave",1,u)
	check(sim.foes_of(u)[1].hp < 100000.,"cleave hits a second target")
	for f in sim.foes_of(u).slice(1):
		f.hp = 0.
	check(sim._find_spell_target(u,"cleave") != null and sim._find_spell_target(u,"arrow_rain") != null,"AoE works on one target")
	sim._cast(u,"serpent_sting",1,target)
	var dot = sim._own_dot(target,u,"serpent_sting")
	dot["remaining"] = 1.
	var hp: float = target.hp
	sim._cast(u,"chimera",1,target)
	check(dot["remaining"] == dot["duration"] and target.hp < hp-180.,"chimera refreshes poison and adds periodic damage")
	sim.release()

func test_defensive_spells() -> void:
	var u := unit(0,["staff"],{"reflection":5})
	var sim := battle([u])
	var foe: BattleUnit = sim.foes_of(u)[0]
	var reflected := 0
	for i in 100:
		var before: float = u.hp
		var enemy_before: float = foe.hp
		sim._cast(foe,"fireball",1,u)
		if u.hp == before and foe.hp < enemy_before:
			reflected += 1
		u.hp = u.max_hp
	check(reflected >= 30 and reflected <= 70,"reflection probability and returned damage")
	sim._buff(foe,"weakness",.15,15.,u)
	check(sim._find_spell_target(u,"weakness") != foe,"long curse is not refreshed needlessly")
	sim._cast(u,"mass_dispel",1,u)
	check(not sim._debuffed(u),"mass dispel cleans allies")
	var a := foe.hp
	sim._cast(u,"explosive",1,foe)
	check(foe.hp == a,"explosive arrow waits for detonation")
	for tick in 22:
		sim.step()
	check(foe.hp < a,"explosive arrow detonates after delay")
	sim.release()

func test_migration() -> void:
	var p := Rules.new_profile(55,1000.)
	p["v"] = 8
	p["hero"]["level"] = 12
	p["hero"]["talents"] = {"blade_master":4,"toughness":2}
	p["collection"]["twin_strike"] = {"lvl":3,"copies":7}
	p["hero"]["rotation"] = ["twin_strike","strike","fireball"]
	Rules.migrate(p,1000.)
	check(p["hero"]["talents"].is_empty() and Talents.points_free(p["hero"]) == 16,"old talents refunded")
	check(not p["collection"].has("twin_strike") and p["collection"]["strike"]["lvl"] == 3 and p["collection"]["strike"]["copies"] >= 7,"spell replacement retains upgrades")
	check(p["hero"]["rotation"].size() == 2,"migration removes duplicate rotation entries")
	var copy: Dictionary = JSON.parse_string(JSON.stringify(p))
	Rules.migrate(copy,1000.)
	check(JSON.stringify(copy["collection"]) == JSON.stringify(p["collection"]) and JSON.stringify(copy["hero"]) == JSON.stringify(p["hero"]),"migration is idempotent")
	var farm := Rules.new_profile(9,1000.)
	farm["v"] = 8
	var total := [10.,100,50,2,0,0,1,0,1,{}]
	farm["expedition"] = {"id":"old","mode":"farm","level":1,"seed":9,"first":false,"started_at":1000.,"party":Rules.party_snapshots(farm),"collected":Expedition.zero_point(),"tl":{"mode":"farm","level":1,"seed":9,"pts":[total],"items":[],"sim_until":10.,"rate":[0.,10.,5.,.2,0.,0.,.1,0.,0.,{}]}}
	var gold_before: int = farm["gold"]
	Rules.migrate(farm,1010.)
	check(farm["gold"] == gold_before+100 and farm["expedition"]["started_at"] == 1010. and farm["expedition"]["tl"]["combat_version"] == 9,"old farm rewards settled before new simulation starts")
	Rules.migrate(farm,1010.)
	check(farm["gold"] == gold_before+100,"migration cannot credit old farm rewards twice")

func test_vengeance_and_dual_weapons() -> void:
	var u := unit(0,["sword","shield"])
	var sim := battle([u])
	var foe: BattleUnit = sim.foes_of(u)[0]
	sim._cast(u,"vengeance",1,u)
	sim._shield(u,u,50.,6.,"residual",false)
	var before: float = foe.hp
	sim._deal(foe,u,400.,false,false,"attack")
	check(foe.hp < before and not u.buffs.has("vengeance_charge"),"residual energy cannot overwrite vengeance detonation")
	sim.release()
	var dual := unit(0,["sword","sword"],{"poison_blades":3})
	var single := unit(1,["sword"],{"poison_blades":3})
	dual.offhand_atk = 20.
	var duel := battle([dual,single])
	var target: BattleUnit = duel.foes_of(dual)[0]
	var dual_poisons := 0
	var single_poisons := 0
	for i in 1000:
		target.dots.clear()
		target.hp = target.max_hp
		duel._autoattack(dual,target)
		dual_poisons += int(duel._own_dot(target,dual,"poison_blades") != null)
		target.dots.clear()
		target.hp = target.max_hp
		duel._autoattack(single,target)
		single_poisons += int(duel._own_dot(target,single,"poison_blades") != null)
	check(dual_poisons > single_poisons*1.4,"two swords provide independent poison checks")
	duel.release()
