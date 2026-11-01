extends SceneTree
## How far level 30 parties get in Mythic+, to tune Db.MYTHIC_BASE.
##   godot --headless --path . --script res://tests/mythic_report.gd -- --parties=12 --max=30
## A built party (tank, healer, two damage dealers) and fully random board mercenaries,
## all level 30 with the gear and talents NPCs get. For each party: the highest key it
## clears in a row from +1 (the dungeon seed is fixed, so the result is exact).

var parties := 12
var max_key := 30

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--parties="): parties = arg.trim_prefix("--parties=").to_int()
		if arg.begins_with("--max="): max_key = arg.trim_prefix("--max=").to_int()
	print("Mythic+: base %.2f, +%d%% per key, %d waves" % [Db.MYTHIC_BASE, roundi(Db.MYTHIC_STEP * 100), Db.MYTHIC_WAVES.size()])
	for kind in ["built", "random"]:
		var reached := []
		for i in parties:
			var rng := RandomNumberGenerator.new()
			rng.seed = 1000 + i
			var party := built_party(rng) if kind == "built" else random_party(rng)
			var key := 0
			var last_time := 0.0
			var fail_wave := 0
			while key < max_key:
				var tl := Expedition.build_timeline(key + 1, "mythic", party, Db.mythic_seed(key + 1), false)
				if not tl["won"]:
					fail_wave = int(tl["waves"]) + 1
					break
				key += 1
				last_time = float(tl["t_end"])
			reached.append(key)
			print("%-6s party %2d: clears up to +%d (%s), next key fails on wave %d" % [kind, i, key, "%d:%02d" % [int(last_time) / 60, int(last_time) % 60], fail_wave])
		reached.sort()
		print("%s: min +%d, median +%d, max +%d" % [kind, reached[0], reached[reached.size() / 2], reached[-1]])
	quit()

func member(rng: RandomNumberGenerator, weapons: Array, talents: String, spells: Array) -> Dictionary:
	var m: Dictionary = MercGenerator.make(rng, Db.HERO_MAX_LEVEL, weapons, talents, spells)
	Roster.ensure_merc(m)
	return m

func built_party(rng: RandomNumberGenerator) -> Array:
	return [
		member(rng, ["sword", "shield"], "bulwark", ["taunt", "shield_slam", "strike"]),
		member(rng, ["staff"], "arcane", ["kick", "fireball", "ignite"]),
		member(rng, ["bow"], "assault", ["hunters_mark", "serpent_sting", "aimed_shot"]),
		member(rng, ["staff"], "life", ["cleanse", "heal", "renew"]),
	]

func random_party(rng: RandomNumberGenerator) -> Array:
	var out := []
	for i in 4:
		var m: Dictionary = MercGenerator.make(rng, Db.HERO_MAX_LEVEL)
		Roster.ensure_merc(m)
		out.append(m)
	return out
