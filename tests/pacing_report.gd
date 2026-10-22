extends SceneTree
## Pacing simulation: a simple player who
##   - tries the next campaign level (push) with a "normal" party,
##   - on a wipe farms the last cleared level for FARM_CHUNK seconds, then retries.
## Prints, per campaign level, how much game time it took and the hero level.
## Conservative: hero has no gear, mercs are "normal" tier.
##   godot --headless --script res://tests/pacing_report.gd

const FARM_CHUNK := 300.0          # seconds of AFK farm between push attempts
const TIME_LIMIT := 60.0 * 3600.0  # stop after 60 h of game time
# Compositions the simulated player tries on each push (a real player adapts the group):
const PARTIES := [
	[0, 1, 3],   # tank, healer (renew), pyromancer
	[0, 2, 4],   # tank, healer (cleanse), poisoner
	[6, 1, 5],   # guard (kick/stun), healer, fighter
]

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var hero_lvl := 1
	var xp := 0
	var closed := 0
	var t := 0.0
	var gold := 0
	var attempt := 0
	var last_clear := 0.0
	print("lvl | time for level | total time | hero lvl | attempts | gold")
	var attempts_here := 0
	while closed < Db.level_count() and t < TIME_LIMIT:
		attempt += 1
		attempts_here += 1
		var target := closed + 1
		var r := {}
		for p_i in PARTIES.size():
			var ex := Expedition.new()
			ex.record_events = false
			ex.start(target, "push", _party(hero_lvl, attempt, PARTIES[p_i]), 1000 + attempt, true)
			while not ex.finished:
				ex.step_wave_headless()
			t += ex.elapsed
			r = ex.take_rewards()
			xp += r["xp"]
			gold += r["gold"]
			if r["closed"]:
				break
		if r["closed"]:
			closed = target
			print("%3d | %6.1f min | %6.1f h | %3d | %3d | %d" % [closed, (t - last_clear) / 60.0, t / 3600.0, hero_lvl, attempts_here, gold])
			last_clear = t
			attempts_here = 0
		elif closed > 0:
			var fx := Expedition.new()
			fx.record_events = false
			fx.start(closed, "farm", _party(hero_lvl, attempt, PARTIES[0]), 5000 + attempt, false)
			fx.fast_forward(FARM_CHUNK)
			t += FARM_CHUNK
			var fr := fx.take_rewards()
			xp += fr["xp"]
			gold += fr["gold"]
		while xp >= Db.xp_to_next(hero_lvl):
			xp -= Db.xp_to_next(hero_lvl)
			hero_lvl += 1
	if closed < Db.level_count():
		print("STUCK at level %d after %.1f h (hero %d)" % [closed + 1, t / 3600.0, hero_lvl])
	print("done in %d ms" % (Time.get_ticks_msec() - t0))
	quit()

func _party(hero_lvl: int, seed_value: int, templates: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var spell_lvl := 1 + int(hero_lvl / 8)   # hero fuses slower than veteran mercs
	var hero := {"name": "Hero", "level": hero_lvl, "rotation": ["fireball", "strike", "kick"],
		"equipped": {"weapon": null, "armor": null, "trinket": null}}
	var coll := {}
	for sid in hero["rotation"]:
		coll[sid] = {str(spell_lvl): 1}
	var party := [Roster.hero_snapshot(hero, coll)]
	for tpl in templates:
		party.append(Roster.make_merc(rng, tpl, hero_lvl, 1))
	return party
