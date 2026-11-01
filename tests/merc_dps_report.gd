extends SceneTree
## Damage of real board mercenaries by weapon, as the player meets them.
##   godot --headless --path . --script res://tests/merc_dps_report.gd -- --levels=18,30 --mercs=40
## Each merc keeps the random gear, talents and spells the generator gives it and
## hits a harmless brute of that campaign level for 60 s (single target).

var levels := [18, 30]
var mercs := 40
const SETS := [["staff"], ["bow"], ["greatsword"], ["sword", "sword"], ["sword", "shield"]]

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--levels="): levels = Array(arg.trim_prefix("--levels=").split(",")).map(func(v): return int(v))
		if arg.begins_with("--mercs="): mercs = arg.trim_prefix("--mercs=").to_int()
	for lvl in levels:
		print("== campaign level %d" % lvl)
		for weapons in SETS:
			var dps := []
			var spell_share := []
			for i in mercs:
				var rng := RandomNumberGenerator.new()
				rng.seed = 500 + i
				var m: Dictionary = MercGenerator.make(rng, lvl, weapons)
				Roster.ensure_merc(m)
				var r := fight(m, lvl, i)
				dps.append(r[0])
				spell_share.append(r[1])
			dps.sort()
			spell_share.sort()
			print("%-14s median DPS %6.0f  (p25 %6.0f, p75 %6.0f)  spells %d%% of damage" % [
				"+".join(weapons), dps[mercs / 2], dps[mercs / 4], dps[mercs * 3 / 4], roundi(spell_share[mercs / 2] * 100)])
	quit()

func fight(m: Dictionary, lvl: int, seed_value: int) -> Array:
	var u := BattleUnit.new(0, 0, 0, m)
	u.max_hp *= 100.0
	u.hp = u.max_hp
	var foe: Dictionary = Expedition.enemy_snapshot("brute", lvl)
	foe["stats"]["hp"] *= 1000.0
	foe["stats"]["atk"] = 0.0
	foe["stats"]["power"] = 0.0
	foe["spells"] = []
	var sim := BattleSim.new()
	sim.record_events = false
	sim.setup([u], [foe], seed_value)
	while sim.time < 60.0 and not sim.finished:
		sim.step()
	var total := 0.0
	var spells := 0.0
	for k in u.dealt_by:
		total += float(u.dealt_by[k])
		if k != "attack":
			spells += float(u.dealt_by[k])
	sim.release()
	return [total / 60.0, spells / maxf(1.0, total)]
