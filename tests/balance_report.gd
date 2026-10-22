extends SceneTree
## Headless balance report. Run:
##   godot --headless --script res://tests/balance_report.gd
## For each campaign level and party archetype it finds the lowest hero level
## (no gear, NPC mercs of the same level) that wins at least 4 of 6 push attempts.

const PARTIES := {
	"balanced": [0, 1, 3],
	"4 dps": [3, 4, 5],
	"2 heal": [0, 1, 2],
	"kick+heal": [6, 1, 3],
}
const TRIES := 6
const NEED := 4

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var floor_lvl := {}
	for p in PARTIES:
		floor_lvl[p] = 1
	for lvl in range(1, Db.level_count() + 1):
		var line := "L%-2d %-18s" % [lvl, Db.LEVELS[lvl - 1]["name"]]
		for pname in PARTIES:
			var h: int = floor_lvl[pname]
			while h <= 60 and _wins(lvl, h, PARTIES[pname]) < NEED:
				h += 1
			floor_lvl[pname] = h
			line += " | %s: %s" % [pname, ("hero %d" % h) if h <= 60 else ">60"]
		print(line)
	print("done in %d ms" % (Time.get_ticks_msec() - t0))
	quit()

func _wins(lvl: int, hero_lvl: int, merc_templates: Array) -> int:
	var wins := 0
	for i in TRIES:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + i
		var hero := {"name": "Hero", "level": hero_lvl, "rotation": ["fireball", "strike", "kick"],
			"equipped": {"weapon": null, "armor": null, "trinket": null}}
		var party := [Roster.hero_snapshot(hero, {})]
		for t in merc_templates:
			party.append(Roster.make_merc(rng, t, hero_lvl, 1))  # normal tier
		var ex := Expedition.new()
		ex.record_events = false
		ex.start(lvl, "push", party, 77 + i, true)
		while not ex.finished:
			ex.step_wave_headless()
		if ex.runs_won > 0:
			wins += 1
	return wins
