extends SceneTree
## Chapter 6 difficulty: how often parties of level 30 clear campaign levels 30-40.
##   godot --headless --path . --script res://tests/endgame_report.gd -- --seeds=6 --from=30 --to=40
## Parties (all level 30, the hero cap):
##   board   - four random board mercenaries (hybrids and specialists, merc gear)
##   spec    - tank, healer, mage and physical specialists with merc gear
##   geared  - the same specialists in epic ilvl 35 gear on every slot, spells VIII
##   max     - legendary ilvl 40 gear on every slot, spells X
## Each party fights a push of the level `seeds` times (different battle seeds).

var seeds := 6
var from := 30
var to := 40

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="): seeds = arg.trim_prefix("--seeds=").to_int()
		if arg.begins_with("--from="): from = arg.trim_prefix("--from=").to_int()
		if arg.begins_with("--to="): to = arg.trim_prefix("--to=").to_int()
	print("Chapter 6: growth %.2f per level after 30" % Db.ENDGAME_GROWTH)
	var kinds := ["board", "spec", "geared", "max"]
	var parties := {}
	for kind in kinds:
		parties[kind] = []
		for i in seeds:
			var rng := RandomNumberGenerator.new()
			rng.seed = 900 + i
			parties[kind].append(party(rng, kind))
	print("level | " + " | ".join(kinds.map(func(k): return "%-11s" % k)))
	for lvl in range(from, to + 1):
		var cells := []
		for kind in kinds:
			var wins := 0
			var waves := 0
			for i in seeds:
				var tl := Expedition.build_timeline(lvl, "push", parties[kind][i], 4000 + lvl * 31 + i, false)
				if tl["won"]:
					wins += 1
				waves += int(tl["waves"])
			cells.append("%d/%d w%4.1f" % [wins, seeds, waves / float(seeds)])
		print("%5d | %s" % [lvl, " | ".join(cells)])
	quit()

func party(rng: RandomNumberGenerator, kind: String) -> Array:
	var out := []
	if kind == "board":
		for i in 4:
			out.append(MercGenerator.make(rng, Db.HERO_MAX_LEVEL))
	else:
		for spec in ["tank", "healer", "mage", "physical"]:
			out.append(MercGenerator.make(rng, Db.HERO_MAX_LEVEL, [], "", [], spec))
	for m in out:
		if kind == "geared":
			upgrade(rng, m, 35, Items.EPIC, 8)
		elif kind == "max":
			upgrade(rng, m, 40, Items.LEGENDARY, 10)
		Roster.ensure_merc(m)
	return out

## Every slot re-rolled at this item level and quality, spells raised to this level.
func upgrade(rng: RandomNumberGenerator, m: Dictionary, ilvl: int, quality: int, spell_lvl: int) -> void:
	var weapons: Array = m["weapons"]
	var role := Items.role_of(weapons)
	var gear := {}
	gear["weapon"] = Loot.roll_gear(rng, ilvl, "merc", "weapon", weapons[0], role, quality)
	gear["offhand"] = Loot.roll_gear(rng, ilvl, "merc", "offhand", weapons[1], role, quality) if weapons.size() > 1 else null
	for slot in ["head", "armor", "hands", "legs", "feet", "trinket"]:
		gear[slot] = Loot.roll_gear(rng, ilvl, "merc", slot, "", role, quality)
	for slot in ["accessory1", "accessory2"]:
		gear[slot] = Loot.roll_gear(rng, ilvl, "merc", "accessory", "", role, quality)
	var st := Roster.apply_gear(m["base_stats"].duplicate(), gear)
	Talents.apply_stats(st, m["talents"], weapons)
	st.merge(Loot.attack_of(st, gear), true)
	m["gear"] = gear
	m["stats"] = st
	m["effects"] = Items.effects_of(gear)
	for e in m["spells"]:
		e["lvl"] = spell_lvl
