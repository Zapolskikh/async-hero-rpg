extends Node
## Dev helper: run the game with `-- --shots=<dir>` to walk through the screens
## and save screenshots (used to check the UI without a phone).

var out_dir := "user://shots"
var main: Node

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out_dir = a.substr(8)
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = get_parent()
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
	Game.expedition = Expedition.new()
	Game.expedition.start(29, "push", Game.party_snapshots(), 3, true)
	for i in 3:
		Game.expedition.step_wave_headless()
	Game.expedition.record_events = true
	main._open_watch()
	await _wait(3.0)
	await _shot("14_two_bosses")
	print("shots done")
	get_tree().quit()
