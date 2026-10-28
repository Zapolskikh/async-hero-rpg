extends SceneTree
var failures := 0
var assertions := 0

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		print("FAIL ", message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var snapshot := {"name":"Trainer", "stats":{"hp":1000.,"atk":30.,"power":100.,"str":100.,"agi":100.,"armor":10.}, "weapons":["sword","shield"], "spells":[{"id":"fireball","lvl":2}], "talents":{}}
	var original := snapshot.duplicate(true)
	var session := TrainingSession.new(snapshot)
	check(session.catalog().size() == 50, "All 50 available spells")
	check(session.sim.units.size() == 5, "Hero, three healing targets and dummy")
	check(session.sim.units[0].atk == snapshot["stats"]["atk"], "Original weapon damage preserved")
	for i in 100:
		session.advance(.1)
	check(session.sim.units[0].dealt > 0., "Live combat deals damage")
	check(session.sim.events.any(func(e): return e["t"] == "fx"), "Real spell animation events")
	var old_time := session.sim.time
	session.set_spell(0, "heal")
	check(session.sim.time == old_time, "Changing spell keeps battle running")
	for i in 40:
		session.advance(.1)
	check(session.sim.units[0].healed > 0., "Healing can be tested")
	session.set_spell(1, "heal")
	check(session.rotation.count("heal") == 1, "No duplicate spells")
	session.paused = true
	old_time = session.sim.time
	session.advance(1.)
	check(session.sim.time == old_time, "Pause")
	session.paused = false
	session.weapons = ["bow"]
	session.targets = 3
	session.low_health = true
	session.retaliation = true
	session.spell_level = 10
	session.restart()
	check(session.sim.side_units(1).size() == 3, "Three dummies")
	check(session.sim.side_units(1)[0].hp_frac() < .3, "Execute testing")
	check(session.sim.units[0].ranged, "Bow switches autoattack animation")
	check(session.sim.units[0].atk_speed == Loot.WEAPON_TYPES["bow"]["speed"], "Bow uses real attack timing")
	check(session.sim.units[0].spells[0]["lvl"] == 10, "All spell ranks available")
	for i in 100:
		session.advance(.1)
	check(session.sim.units[0].hp < session.sim.units[0].max_hp, "Retaliation damages the party")
	session.weapons = ["staff"]
	session.restart()
	check(session.sim.units[0].atk == 0., "Staff has no autoattack")
	session.dispose()
	check(snapshot == original, "Source snapshot unchanged")
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var game = root.get_node("Game")
	var profile_before := JSON.stringify(game.profile)
	var expedition_before = game.expedition
	main._dummy_popup()
	await process_frame
	await process_frame
	var panel = main.popup_layer.get_child(0).get_child(0)
	check(panel.session != null and panel.view.training_sim == panel.session.sim, "Training UI uses isolated simulation")
	for id in session.catalog():
		panel._equip(id)
		check(panel.session.rotation[panel.selected_slot] == id, "Selectable: " + id)
	panel._equip("fireball")
	panel.session.advance(2.)
	check(JSON.stringify(game.profile) == profile_before, "Training UI never mutates save")
	check(game.expedition == expedition_before, "Training UI never replaces expedition")
	check(panel.size.x <= root.size.x and panel.size.y <= root.size.y, "Training fits viewport")
	await create_timer(1.).timeout
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://build/qa")
		root.get_texture().get_image().save_png("res://build/qa/training.png")
	panel.queue_free()
	await process_frame
	await process_frame
	check(main.popup_layer.get_child_count() == 0, "Closing training removes overlay")
	main.queue_free()
	await process_frame
	print("TRAINING: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
