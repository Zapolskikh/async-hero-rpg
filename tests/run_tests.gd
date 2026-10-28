extends SceneTree
## Headless unit tests for the battle core. Run:
##   godot --headless --script res://tests/run_tests.gd

var failures := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)

func _init() -> void:
	test_determinism()
	test_rotation_skips_invalid()
	test_priority_rotation()
	test_reactive_kick()
	test_interrupt_and_execute()
	test_push_wipe_gives_partial()
	test_farm_fast_forward()
	test_cooldown()
	test_random_mercenaries()
	test_board_and_group()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)

func party(level: int, templates: Array, seed_value: int = 1) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var hero := {"name": "Hero", "level": level, "rotation": ["kick", "fireball", "strike"],
		"equipped": {"weapon": null, "armor": null, "trinket": null}}
	var p := [Roster.hero_snapshot(hero, {})]
	for t in templates:
		p.append(Roster.make_merc(rng, t, level, 1))
	return p

func run_push(lvl: int, p: Array, seed_value: int) -> Expedition:
	var ex := Expedition.new()
	ex.record_events = false
	ex.start(lvl, "push", p, seed_value, true)
	while not ex.finished:
		ex.step_wave_headless()
	return ex

func test_determinism() -> void:
	print("determinism")
	var a := run_push(3, party(3, [0, 1, 3]), 42)
	var b := run_push(3, party(3, [0, 1, 3]), 42)
	check(a.gold == b.gold and a.best_wave == b.best_wave and is_equal_approx(a.elapsed, b.elapsed),
		"same seed and party give identical result")

func test_rotation_skips_invalid() -> void:
	print("rotation")
	# Kick is only valid while an enemy casts. Against a lone brute that never
	# starts a cast, the hero must keep using fireball/strike instead.
	var sim := BattleSim.new()
	var hero := BattleUnit.new(0, 0, 0, {"name": "H", "stats": {"hp": 5000, "atk": 1, "power": 10, "armor": 0},
		"weapons": ["sword"], "spells": [{"id": "kick", "lvl": 1}, {"id": "strike", "lvl": 1}]})
	var dummy := {"name": "D", "stats": {"hp": 100000, "atk": 0, "power": 0, "armor": 0}, "spells": []}
	sim.setup([hero], [dummy], 1)
	var casts := {}
	for i in 300:
		sim.step()
		for e in sim.events:
			if e["t"] == "spell" and e["uid"] == 0:
				casts[e["text"]] = casts.get(e["text"], 0) + 1
		sim.events.clear()
	check(not casts.has(Db.SPELLS["kick"]["name"]), "kick skipped when nobody casts")
	check(casts.get(Db.SPELLS["strike"]["name"], 0) >= 5, "strike used instead (%d times)" % casts.get(Db.SPELLS["strike"]["name"], 0))

func test_priority_rotation() -> void:
	print("priority rotation")
	# Heal in slot 1 with no cooldown: while an ally stays below the threshold,
	# every step heals and strike in slot 2 is never reached.
	var sim := BattleSim.new()
	var healer := BattleUnit.new(0, 0, 0, {"name": "H", "stats": {"hp": 5000, "atk": 1, "power": 10, "armor": 0},
		"spells": [{"id": "heal", "lvl": 1, "threshold": 0.99}, {"id": "strike", "lvl": 1}]})
	var tank := BattleUnit.new(1, 0, 1, {"name": "T", "stats": {"hp": 1000000, "atk": 1, "power": 1, "armor": 0}, "spells": []})
	tank.hp = 1000.0
	var dummy := {"name": "D", "stats": {"hp": 100000, "atk": 0, "power": 0, "armor": 0}, "spells": []}
	sim.setup([healer, tank], [dummy], 1)
	var casts := {}
	for i in 300:
		sim.step()
		for e in sim.events:
			if e["t"] == "spell" and e["uid"] == 0:
				casts[e["text"]] = casts.get(e["text"], 0) + 1
		sim.events.clear()
	var heals: int = casts.get(Db.SPELLS["heal"]["name"], 0)
	check(heals >= 6 and not casts.has(Db.SPELLS["strike"]["name"]), "slot 1 heal used every step (%d), strike never" % heals)
	# custom threshold: at 50% the 60%-hp tank is not healed, strike runs instead
	var sim2 := BattleSim.new()
	var h2 := BattleUnit.new(0, 0, 0, {"name": "H", "stats": {"hp": 5000, "atk": 1, "power": 10, "armor": 0},
		"spells": [{"id": "heal", "lvl": 1, "threshold": 0.5}, {"id": "strike", "lvl": 1}]})
	var t2 := BattleUnit.new(1, 0, 1, {"name": "T", "stats": {"hp": 1000000, "atk": 1, "power": 1, "armor": 0}, "spells": []})
	t2.hp = 600000.0
	sim2.setup([h2, t2], [dummy], 1)
	check(sim2._find_spell_target(h2, "heal", 0.5) == null and sim2._find_spell_target(h2, "heal", 0.7) == t2, "threshold setting decides who gets healed")
	var p := Rules.new_profile(3, 0.0)
	check(Rules.apply(p, "set_threshold", {"sid": "heal", "value": 0.9}, 0.0)["ok"], "threshold can be set for heal")
	check(not Rules.apply(p, "set_threshold", {"sid": "strike", "value": 0.9}, 0.0)["ok"] and not Rules.apply(p, "set_threshold", {"sid": "heal", "value": 0.42}, 0.0)["ok"], "only healing spells and listed values")
	p["hero"]["rotation"] = ["heal", "kick", "strike"]
	var sp: Array = Rules.hero_snapshot(p)["spells"]
	check(sp[0].get("threshold", 0.0) == 0.9, "hero snapshot carries the threshold")

func test_reactive_kick() -> void:
	print("reactive interrupt")
	# kick in slot 3 behind spells that are always usable still interrupts every cast it can
	var sim := BattleSim.new()
	var hero := BattleUnit.new(0, 0, 0, {"name": "H", "stats": {"hp": 100000, "atk": 1, "power": 1, "armor": 0},
		"spells": [{"id": "strike", "lvl": 1}, {"id": "fireball", "lvl": 1}, {"id": "kick", "lvl": 1}]})
	var caster := Expedition.enemy_snapshot("caster", 1)
	caster["stats"]["hp"] = 1000000.0
	sim.setup([hero], [caster], 3)
	var casts := 0
	var kicks := 0
	for i in 600:
		sim.step()
		for e in sim.events:
			if e["t"] == "cast" and e["uid"] != 0:
				casts += 1
			if e["t"] == "interrupt":
				kicks += 1
		sim.events.clear()
	check(kicks >= 4 and hero.dealt_by.has("kick") and hero.dealt_by.has("attack"), "kick fires on enemy casts outside the rotation (%d kicks / %d casts)" % [kicks, casts])

func test_interrupt_and_execute() -> void:
	print("interrupt")
	var sim := BattleSim.new()
	var hero := BattleUnit.new(0, 0, 0, {"name": "H", "stats": {"hp": 100000, "atk": 1, "power": 1, "armor": 0},
		"spells": [{"id": "kick", "lvl": 1}]})
	var caster := Expedition.enemy_snapshot("caster", 1)
	caster["stats"]["hp"] = 100000.0
	sim.setup([hero], [caster], 3)
	var interrupts := 0
	var bolts := 0
	for i in 600:
		sim.step()
		for e in sim.events:
			if e["t"] == "interrupt":
				interrupts += 1
			if e["t"] == "spell" and e["uid"] == 1:
				bolts += 1
		sim.events.clear()
	check(interrupts > 0, "enemy casts get interrupted (%d)" % interrupts)
	check(interrupts >= 5 and bolts >= 1, "8-second kick stops casts but leaves cooldown windows (%d stopped / %d landed)" % [interrupts, bolts])

func test_push_wipe_gives_partial() -> void:
	print("push / wipe")
	var ex := run_push(10, party(1, [3, 4, 5]), 5)
	check(ex.runs_won == 0 and ex.finished, "underleveled push wipes")
	check(ex.gold > 0 or ex.kills == 0, "partial rewards for progress made (gold %d)" % ex.gold)
	check(not ex.level_closed_now, "wipe does not close the level")

func test_farm_fast_forward() -> void:
	print("farm fast-forward")
	var ex := Expedition.new()
	ex.start(1, "farm", party(4, [0, 1, 3]), 9, false)
	var t0 := Time.get_ticks_msec()
	var res := ex.fast_forward(8 * 3600.0)
	var ms := Time.get_ticks_msec() - t0
	check(ms < 5000, "8h offline computed in %d ms" % ms)
	check(res["extrapolated"] > 0.0, "long farm is extrapolated (simulated %d s)" % int(res["simulated"]))
	check(ex.runs_won > 50, "many farm runs credited (%d)" % ex.runs_won)
	check(not ex.finished, "farm keeps running")

func test_cooldown() -> void:
	print("cooldown")
	# Barrier has a cooldown: with a single-spell rotation it must not be used every step.
	var sim := BattleSim.new()
	var hero := BattleUnit.new(0, 0, 0, {"name": "H", "stats": {"hp": 100000, "atk": 0, "power": 10, "armor": 0},
		"spells": [{"id": "barrier", "lvl": 1}]})
	var dummy := {"name": "D", "stats": {"hp": 100000, "atk": 50, "power": 0, "armor": 0}, "spells": []}
	sim.setup([hero], [dummy], 1)
	var times := []
	for i in 300:
		sim.step()
		for e in sim.events:
			if e["t"] == "spell" and e["uid"] == 0:
				times.append(sim.time)
		sim.events.clear()
	var min_gap := 999.0
	for i in range(1, times.size()):
		min_gap = min(min_gap, times[i] - times[i - 1])
	check(times.size() >= 2 and min_gap >= Db.SPELLS["barrier"]["cd"] - 0.01,
		"barrier respects %.0f s cooldown (min gap %.1f s)" % [Db.SPELLS["barrier"]["cd"], min_gap])

func test_random_mercenaries() -> void:
	print("random classless mercenaries")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var weapons := {}
	var builds := {}
	var valid := true
	for i in 60:
		var m := Roster.make_merc(rng, 0, 24)
		weapons[str(m["weapons"])] = true
		builds[str(m["spells"])] = true
		valid = valid and not m.has("tier") and m["spells"].size() == 3 and Talents.points_spent(m["talents"]) == Talents.points_total(24)
		var sim := BattleSim.new()
		var u := BattleUnit.new(0,0,0,m)
		for entry in m["spells"]:
			valid = valid and sim._usable(u,entry["id"])
	check(valid, "mercenaries have usable spells, legal talent budgets and no quality tier")
	check(weapons.size() == 5 and builds.size() > 30, "rerolls cover all weapon sets and diverse random builds")

func test_board_and_group() -> void:
	print("board and group")
	var info := SpellInfo.effects("ignite", 1, {"stats": {"power": 20.0}})
	check(info.size() > 0 and "в сек" in info[0][1], "spell info gives numbers (%s)" % info[0][1])
