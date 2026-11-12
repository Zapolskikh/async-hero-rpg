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
	test_new_mechanics()
	test_shared_needs()
	test_spell_lock()
	test_meter_credit()
	test_accessories()
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
	check(count == 54,"54 collectible spells")

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
	# Enemy aimed spells go to the taunter; a cast begun before the taunt keeps its target.
	var tank := unit(0)
	var healer := unit(1,["staff"])
	var sim2 := battle([tank,healer])
	var caster: BattleUnit = sim2.foes_of(tank)[0]
	caster.target_rule = "back"
	caster.spells = [{"id":"e_bolt","lvl":1}]
	check(sim2._find_spell_target(caster,"e_bolt") == healer,"without a taunt the caster aims at the back line")
	check(sim2._try_rotation(caster) and caster.casting["target"] == healer,"the caster starts a bolt at the healer")
	sim2._cast(tank,"taunt",1,tank)
	check(caster.casting["target"] == healer,"a cast begun before the taunt keeps its target")
	caster.casting.clear()
	for sid in ["e_bolt","e_smash","e_execute","e_curse","e_silence","e_backstab"]:
		check(sim2._find_spell_target(caster,sid) == tank,"under taunt %s aims at the taunter" % sid)
	caster.spells = [{"id":"e_bolt","lvl":1}]
	caster.cooldowns.clear()
	caster.spell_cd = 0.
	check(sim2._try_rotation(caster) and caster.casting["target"] == tank,"a new cast after the taunt starts on the taunter")
	sim2._apply_dot(caster,tank,"e_curse",10.,8.)
	check(sim2._find_spell_target(caster,"e_curse") == null,"a DoT already on the taunter does not hop to another hero")
	sim2.release()

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
	check(sim._usable(u,"aimed_shot") and is_equal_approx(sim._amount(u,"aimed_shot",1),Db.SPELLS["aimed_shot"]["mult"]*100.),"throwing uses strength at full rank")
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
	var kit: Array = u.spells
	sim._buff(u,"weakness",.15,15.,u)
	u.spells = [{"id":"cleanse","lvl":1}]
	check(sim._try_rotation(u) and not sim._debuffed(u) and u.cooldowns.is_empty(),"cleanse has no cooldown")
	foe.shield = 100.
	u.spells = [{"id":"purge","lvl":1}]
	check(sim._try_rotation(u) and foe.shield <= 0. and u.cooldowns.is_empty(),"purge has no cooldown")
	check(not sim._try_rotation(u),"dispels wait for something to remove")
	u.spells = kit
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
	check(p["hero"]["talents"].is_empty() and Talents.points_free(p["hero"]) == Talents.points_total(12),"old talents refunded")
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
	var caster := unit(1,["staff"])
	var shielded := unit(2,["sword","shield"])
	sim._shield(caster,shielded,100.,8.,"barrier")
	sim._shield(u,shielded,100.,8.,"barrier")
	sim._credit_absorb(shielded,150.)
	check(caster.healed == 100. and u.healed == 50. and caster.healed_by["barrier"] == 100.,"absorbed damage counts for each shield caster, oldest shield first")
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

func test_new_mechanics() -> void:
	var tank := unit(0)
	var ally := unit(1,["staff"])
	var sim := battle([tank,ally])
	var foe: BattleUnit = sim.foes_of(tank)[0]
	foe.crit = 0.
	ally.hp = ally.max_hp*.5
	check(sim._find_spell_target(tank,"intervene") == ally,"intervene picks the injured ally, not the tank")
	sim._cast(tank,"intervene",1,ally)
	var tank_hp: float = tank.hp
	var ally_hp: float = ally.hp
	sim._deal(foe,ally,100.,false,false,"fireball",true,"magic")
	check(is_equal_approx(ally_hp-ally.hp,50.) and is_equal_approx(tank_hp-tank.hp,50.),"intervene moves half the damage to the tank")
	check(sim._find_spell_target(tank,"intervene") == null,"intervene is not reapplied while it lasts")
	ally.buffs.clear()
	ally.hp = ally.max_hp*.2
	tank.spells = [{"id":"pain_suppression","lvl":1}]
	tank.spell_cd = 99.
	sim._act(tank)
	check(ally.buffs.has("suppress") and tank.cooldowns.has("pain_suppression"),"pain suppression fires out of rotation below 30% HP")
	ally_hp = ally.hp
	sim._deal(foe,ally,100.,false,false,"fireball",true,"magic")
	check(is_equal_approx(ally_hp-ally.hp,60.),"pain suppression cuts damage by 40%")
	var hunter := unit(2,["bow"])
	sim._cast(hunter,"hunters_mark",1,foe)
	var foe_hp: float = foe.hp
	sim._deal(tank,foe,100.,false,false,"fireball",true,"magic")
	check(is_equal_approx(foe_hp-foe.hp,110.),"hunter's mark adds 10% damage from anyone")
	sim._cast(ally,"weakness",1,foe)
	for f in sim.foes_of(ally): check(f.buffs.has("weakness"),"weakness curses every enemy")
	var armored: BattleUnit = sim.foes_of(tank)[1]
	armored.armor = 100.
	armored.buffs.clear()
	tank.crit = 0.
	var plain := sim._deal(tank,armored,100.,false,false,"strike",true,"physical")
	var pierced := sim._deal(tank,armored,100.,false,false,"mortal_strike",true,"physical")
	check(is_equal_approx(plain,50.) and is_equal_approx(pierced,round(100.*100./170.)),"mortal strike ignores 30% armor")
	var near: BattleUnit = sim.foes_of(hunter)[1]
	var far: BattleUnit = sim.foes_of(hunter)[2]
	far.ranged = true
	near.armor = 0.
	far.armor = 0.
	near.buffs.clear()
	far.buffs.clear()
	hunter.crit = 0.
	var near_hp: float = near.hp
	var far_hp: float = far.hp
	sim._channel_pulse(hunter,{"spell":"arrow_rain","amount":100.,"target":near})
	check(is_equal_approx(near_hp-near.hp,100.) and is_equal_approx(far_hp-far.hp,150.),"arrow rain hits ranged enemies 50% harder")
	sim.release()

func test_shared_needs() -> void:
	var a := unit(0,["staff"])
	var b := unit(1,["staff"])
	var sim := battle([a,b])
	a.spells = [{"id":"mass_dispel","lvl":1}]
	b.spells = [{"id":"mass_dispel","lvl":1}]
	sim._buff(a,"weakness",.15,15.,a)
	check(sim._try_rotation(a) and not a.casting.is_empty(),"the first hero starts the mass dispel")
	check(sim._find_spell_target(b,"mass_dispel") == null and not sim._try_rotation(b),"a second hero does not cast another mass dispel over it")
	a.casting.clear()
	check(sim._find_spell_target(b,"mass_dispel") != null,"if the first cast is cancelled, the second hero takes over")
	b.spells = [{"id":"cleanse","lvl":1}]
	a.spells = [{"id":"cleanse","lvl":1}]
	check(sim._try_rotation(a) and not sim._debuffed(a),"an instant cleanse answers the need at once")
	check(sim._find_spell_target(b,"cleanse") == null,"so the next hero finds nothing to cleanse")
	var foe: BattleUnit = sim.foes_of(a)[0]
	foe.casting = {"spell":"e_bolt","lvl":1,"remaining":2.,"total":2.4,"target":a,"interruptible":true,"threshold":-1.}
	a.casting = {"spell":"kick","lvl":1,"remaining":.5,"total":.5,"target":foe,"interruptible":true,"threshold":-1.}
	check(sim._find_spell_target(b,"kick") == null,"an interrupt already on its way is not doubled")
	sim.release()

func test_spell_lock() -> void:
	var u := unit(0,["staff"])
	var sim := battle([u])
	var foe: BattleUnit = sim.foes_of(u)[0]
	foe.casting = {"spell":"e_doom","lvl":1,"remaining":2.,"total":3.,"target":foe,"interruptible":true,"threshold":-1.}
	u.spells = [{"id":"spell_lock","lvl":1}]
	u.spell_cd = 99.
	sim._act(u)
	check(foe.casting.is_empty() and foe.silence >= 4.9 and u.cooldowns.has("spell_lock"),"spell lock interrupts out of rotation and silences for 5 s")
	sim.release()

## Talent and item procs show up as their own lines in the meter breakdown; totals do not change.
func test_meter_credit() -> void:
	var shaman := unit(0,["staff"],{"fire_totem":3,"healing_totem":3,"ignition":3})
	shaman.crit = 1.
	var ally := unit(1)
	var sim := battle([shaman,ally])
	ally.hp = 2000.
	for i in 100:
		sim.step()
	check(shaman.dealt_by.get("fire_totem",0.) > 0. and not shaman.dealt_by.has("fireball"),"fire totem damage has its own meter line")
	check(shaman.healed_by.get("healing_totem",0.) > 0. and not shaman.healed_by.has("heal"),"healing totem has its own meter line")
	sim._cast(shaman,"fireball",1,sim.foes_of(shaman)[0])
	for i in 50:
		sim.step()
	check(shaman.dealt_by.get("ignition",0.) > 0.,"burning from a crit is listed as its talent")
	var total := 0.
	for k in shaman.dealt_by:
		total += shaman.dealt_by[k]
	check(is_equal_approx(total,shaman.dealt),"breakdown adds up to the total")
	sim._credited(shaman,"echo",func(): sim._deal(shaman,sim.foes_of(shaman)[0],100.,false,false,"fireball",true))
	check(shaman.dealt_by.get("echo",0.) > 0.,"echo copies are listed as the talent")
	sim.release()

func worn(effect: String, weapons: Array = ["sword","shield"]) -> BattleUnit:
	return BattleUnit.new(0,0,0,{"name":"QA","stats":{"hp":10000.,"atk":50.,"str":100.,"agi":80.,"power":100.,"armor":0.,"crit":0.},"weapons":weapons,"talents":{},"spells":[],"effects":[effect]})

## Every accessory effect does what its text says.
func test_accessories() -> void:
	for a in Items.ACCESSORIES:
		check(Items.EFFECTS.has(a["effect"]), "%s has a known effect" % a["name"])
	check(is_equal_approx(worn("acc_gcd_5").spell_interval(), BattleUnit.SPELL_INTERVAL - .5), "hourglass shortens the global cooldown")
	var glass := worn("acc_glass")
	check(is_equal_approx(glass.max_hp, 7500.) and glass.hp == glass.max_hp, "glass shard lowers health")
	check(is_equal_approx(worn("acc_colossus").max_hp, 14000.) and worn("acc_colossus").haste < 0., "colossus: more health, slower")
	check(worn("acc_regen_m").regen > 0., "regeneration accessory")
	# basic attacks
	var u := worn("acc_stun_m")
	u.gear_fx["attack_stun"] = 1.
	u.gear_fx["cleave"] = .4
	u.gear_fx["attack_taunt"] = 1.
	u.gear_fx["sunder_attack"] = .2
	var sim := battle([u])
	var foe: BattleUnit = sim.foes_of(u)[0]
	foe.is_boss = false
	sim._autoattack(u,foe)
	check(foe.stun > 0., "heavy knuckles stun on a basic attack")
	check(u.dealt_by.get("cleave",0.) > 0., "whirl ring hits a second enemy")
	check(u.taunt > 0. and sim.pick_target(foe) == u, "avenger chain taunts with basic attacks")
	check(foe.buff("sunder") > 0., "shatter ring lowers armor")
	sim.release()
	# targeting
	var back := worn("acc_target_back")
	var weak := worn("acc_target_weak")
	weak.uid = 1
	sim = battle([back,weak])
	var foes := sim.foes_of(back)
	foes[1].hp = 10.
	check(sim.pick_target(back) == foes[-1], "compass targets the last enemy")
	check(sim.pick_target(weak) == foes[1], "monocle targets the most wounded enemy")
	sim.release()
	var shade := worn("acc_shadow")
	var mate := unit(1)
	sim = battle([shade,mate])
	var enemy_unit: BattleUnit = sim.foes_of(shade)[0]
	var hits_shade := false
	for i in 20:
		if sim.pick_target(enemy_unit) == shade:
			hits_shade = true
	check(not hits_shade, "enemies ignore the shadow wearer while someone else stands")
	mate.hp = 0.
	check(sim.pick_target(enemy_unit) == shade, "the shadow wearer is a target when alone")
	sim.release()
	# casting
	var mage := worn("acc_steady",["staff"])
	mage.gear_fx["stun_immune"] = 1.
	sim = battle([mage])
	mage.casting = {"spell":"fireball","lvl":1,"remaining":1.,"total":1.,"target":sim.foes_of(mage)[0]}
	check(not sim._interruptible(mage), "seal of focus: casts cannot be interrupted")
	sim._stun(mage,2.)
	check(mage.stun == 0., "ice blood: no stuns")
	sim.release()
	var echo := worn("acc_echo_20",["staff"])
	echo.gear_fx["spell_echo"] = 1.
	echo.gear_fx["mirror"] = .35
	sim = battle([echo])
	sim._cast(echo,"fireball",1,sim.foes_of(echo)[0])
	check(echo.dealt_by.get("spell_echo",0.) > 0. and echo.dealt_by.get("mirror",0.) > 0., "echo crystal and twin mirror repeat a spell")
	sim.release()
	# survival
	var bird := worn("acc_phoenix")
	sim = battle([bird])
	sim._deal(sim.foes_of(bird)[0],bird,99999.,false,false,"attack")
	check(bird.alive() and is_equal_approx(bird.hp,5000.), "phoenix feather saves from death once")
	sim._deal(sim.foes_of(bird)[0],bird,99999.,false,false,"attack")
	check(not bird.alive(), "phoenix feather works once per run")
	sim.release()
	var wind := worn("acc_second_wind")
	sim = battle([wind])
	sim._deal(sim.foes_of(wind)[0],wind,7500.,false,false,"attack")
	check(wind.shield > 0. and wind.spent.has("second_wind"), "second wind shields below 30% health")
	sim.release()
	var pact := worn("acc_blood_pact")
	var plain := unit(1)
	sim = battle([pact,plain])
	var hitter: BattleUnit = sim.foes_of(pact)[0]
	sim._deal(hitter,pact,100.,false,false,"attack")
	sim._deal(hitter,plain,100.,false,false,"attack")
	check(pact.max_hp-pact.hp > plain.max_hp-plain.hp, "blood pact: more damage taken")
	sim.release()
	# kills
	var hunter := worn("acc_kill_reset")
	hunter.gear_fx["kill_frenzy"] = .3
	hunter.gear_fx["kill_heal"] = .06
	sim = battle([hunter])
	hunter.hp = 5000.
	hunter.cooldowns["fireball"] = 10.
	var victim: BattleUnit = sim.foes_of(hunter)[0]
	sim._deal(hunter,victim,999999.,false,false,"attack")
	check(not hunter.cooldowns.has("fireball"), "storm heart resets cooldowns on a kill")
	check(hunter.buff("frenzy") > 0. and hunter.attack_interval() < worn("acc_cd_5").attack_interval(), "hunter heart speeds up after a kill")
	check(hunter.hp > 5000., "trophy tooth heals on a kill")
	sim.release()
	# healing
	var priest := worn("acc_atonement",["staff"])
	priest.gear_fx["heal_splash"] = .25
	priest.gear_fx["mercy"] = .4
	priest.gear_fx["lifesteal"] = .5
	var hurt := unit(1)
	var other := unit(2)
	sim = battle([priest,hurt,other])
	hurt.hp = 1000.
	other.hp = 5000.
	sim._heal(priest,hurt,500.,false,"heal",true)
	check(is_equal_approx(hurt.hp,1700.), "sapphire of mercy: stronger heals on the wounded")
	check(other.hp > 5000., "chalice: a direct heal splashes to another ally")
	check(priest.dealt_by.get("atonement",0.) > 0., "atonement seal turns healing into damage without looping")
	sim.release()
	# damage over time spreads
	var plague := worn("acc_plague",["staff"])
	sim = battle([plague])
	var sick: BattleUnit = sim.foes_of(plague)[0]
	sim._apply_dot(plague,sick,"ignite",10.,8.)
	sim._deal(plague,sick,999999.,false,false,"attack")
	var spread := false
	for f in sim.foes_of(plague):
		if sim._own_dot(f,plague,"ignite") != null:
			spread = true
	check(spread, "plague flask spreads a DoT when its target dies")
	sim.release()
	# a war cry at the start of a wave
	var crier := worn("acc_war_cry")
	var friend := unit(1)
	sim = battle([crier,friend])
	check(friend.buff("war_cry") > 0. and crier.buff("war_cry") > 0., "banner of fury buffs the party at the start of a wave")
	sim.release()
	# ambush and mark
	var sniper := worn("acc_ambush",["bow"])
	sniper.gear_fx["mark"] = .08
	sim = battle([sniper])
	var fresh: BattleUnit = sim.foes_of(sniper)[0]
	var before := fresh.hp
	sim._deal(sniper,fresh,100.,true,false,"attack")
	check(is_equal_approx(before-fresh.hp,200.), "ambush eye: full-health targets take a crit")
	check(fresh.buff("mark") > 0., "trapper fang marks the target")
	sim.release()
