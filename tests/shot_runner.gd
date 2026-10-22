extends Node
## Dev helper: run the game with `-- --shots=<dir>` to walk through the screens
## and save screenshots (used to check the UI without a phone).

var out_dir := "user://shots"
var main: Node
var crafts_only := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out_dir = a.substr(8)
		if a == "--shots-crafts":
			crafts_only = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = get_parent()
	if crafts_only:
		_run_crafts()
	else:
		_run()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _run() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	Game.gold = 600
	Game.boxes = 2
	Game.changed.emit()
	await _wait(0.5)
	await _shot("01_expedition")
	for tab in ["hero", "mercs", "spells", "bag"]:
		main._switch(tab)
		await _wait(0.4)
		await _shot("02_" + tab)
	main._switch("hero")
	main._spell_popup("fireball")
	await _wait(0.4)
	await _shot("02_hero_spell_popup")
	UI.clear(main.popup_layer)
	main._switch("spells")
	main._open_box("token")
	await _wait(1.2)
	await _shot("02_box_open")
	UI.clear(main.popup_layer)
	main._switch("expedition")
	main._start(1, "push")
	Game.watch_speed = 2.0
	await _wait(4.0)
	await _shot("03_battle")
	Game.watch_speed = 4.0
	await _wait(1.5)
	await _shot("04_battle_later")
	Game.watch_speed = 16.0
	var t := 0.0
	while Game.expedition != null and not Game.expedition.finished and t < 30.0:
		await _wait(0.5)
		t += 0.5
	main._close_watch()
	await _wait(1.2)
	await _shot("05_result")
	UI.clear(main.popup_layer)
	main._switch("bag")
	await _wait(0.4)
	await _shot("05_bag_with_item")
	main._switch("expedition")
	Game.start_expedition(1, "farm")
	await _wait(2.0)
	await _shot("05_hub_farming")
	# late level with a boss and casters
	UI.clear(main.popup_layer)
	Game.closed_level = 9
	Game.hero["level"] = 16
	Game.board = Roster.roll_board(Game.rng, 16)
	Game._auto_party()
	Game.board = Roster.roll_board(Game.rng, 16)
	main._start(10, "push")
	Game.watch_speed = 3.0
	for i in 4:
		await _wait(5.0)
		await _shot("06_late_%d" % i)
	main._close_watch()
	Game.stop_expedition()
	UI.clear(main.popup_layer)
	main._switch("mercs")
	await _wait(0.3)
	UI.clear(main.popup_layer)
	await _shot("07_mercs")
	main._merc_popup(Game.board[0])
	await _wait(0.4)
	await _shot("08_merc_popup")
	UI.clear(main.popup_layer)
	main._spell_popup("renew", Game.hired[0])
	await _wait(0.4)
	await _shot("09_merc_spell")
	UI.clear(main.popup_layer)
	main._switch("hero")
	main._spell_popup("fireball")
	await _wait(0.4)
	await _shot("10_hero_spell")
	UI.clear(main.popup_layer)
	main._switch("spells")
	await _wait(0.4)
	await _shot("11_spells")
	Game.gold += 3000
	main._open_pack("gold")
	await _wait(1.4)
	await _shot("12_pack")
	UI.clear(main.popup_layer)
	Game.closed_level = 22
	main.selected_level = 23
	main._switch("expedition")
	await _wait(0.6)
	await _shot("13_campaign_late")
	Game.closed_level = 28
	Game.hero["level"] = 36
	Game.board = Roster.roll_board(Game.rng, 36)
	Game.hired = []
	Game.party_order = ["hero"]
	for i in 3:
		Game.hire(Game.board[0]["id"])
	await Game.stop_expedition()
	await Game.start_expedition(29, "push")
	# jump to the boss wave: pretend the push started earlier
	var ex = Game.exp_info()
	ex["started_at"] = float(ex["started_at"]) - float(ex["tl"]["pts"][2][0]) - 2.0
	Game._view_id = ""
	Game._sync_view()
	main._open_watch()
	await _wait(3.0)
	await _shot("14_two_bosses")
	await _run_crafts()
	get_tree().quit()

func _run_crafts() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	var p: Dictionary = Game.profile
	for r in ["iron_ore", "copper_ore", "coal", "rough_cloth", "linen_cloth", "raw_leather", "greenleaf", "redthorn", "boss_core", "minor_strength_potion", "gatherers_tonic"]:
		Rules._add_res(p, r, 12)
	Game.gold += 2000
	Game.changed.emit()
	CraftsScreen.view = "gather"
	main._switch("crafts")
	await _wait(0.5)
	await _shot("15a_gather_idle")
	var r: Dictionary = await Game.gather_start("mining", "abandoned_quarry", 900)
	print("gather_start ", r.get("ok"), " ", r.get("error", ""))
	main._switch("crafts")
	await _wait(0.5)
	await _shot("15_gather")
	CraftsScreen.view = "craft"
	main._switch("crafts")
	await _wait(0.4)
	await _shot("16a_recipes")
	r = await Game.craft_start("simple_iron_helmet")
	print("craft_start ", r.get("ok"), " ", r.get("error", ""))
	main._switch("crafts")
	await _wait(0.4)
	await _shot("16_craft")
	main.content.get_child(0)._set_view("mats")
	await _wait(0.4)
	await _shot("17_mats")
	p["time_warp"] = float(p.get("time_warp", 0.0)) + 20000.0
	CraftsScreen.view = "gather"
	main._switch("crafts")
	await _wait(0.6)
	await _shot("18a_gather_ready")
	main.content.get_child(0)._gather_claim()
	await _wait(0.6)
	await _shot("18_gather_claim")
	UI.clear(main.popup_layer)
	r = await Game.craft_claim("blacksmithing")
	print("craft_claim ", r.get("ok"), " ", r.get("error", ""))
	if r.get("ok", false):
		Game.equip(str(r["report"]["items"][0]["id"]))
	main._switch("hero")
	await _wait(0.5)
	await _shot("19_hero_slots")
	print("shots done")
	get_tree().quit()
