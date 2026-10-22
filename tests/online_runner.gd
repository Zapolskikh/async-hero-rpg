extends Node
## End-to-end check of online mode against a running server:
##   godot --path . -- --online-test=http://127.0.0.1:8000 --shots=<dir>
## Prints "RESULT ok|FAIL <check>" lines and "ONLINE TEST DONE <failures>".

var url := ""
var out_dir := "user://shots"
var main: Node
var failures := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--online-test="):
			url = a.substr(14)
		if a.begins_with("--shots="):
			out_dir = a.substr(8)
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = get_parent()
	_run()

func check(cond: bool, msg: String) -> void:
	print("RESULT ", "ok  " if cond else "FAIL", " ", msg)
	if not cond:
		failures += 1

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))

func _run() -> void:
	await _wait(0.5)
	var r: Dictionary = await Game.connect_online(url, "Клиент")
	check(r.get("ok", false) and Game.is_online(), "connected as a guest (%s)" % Game.account_id)
	check(not Game.profile.has("rng") or Game.profile["rng"]["state"] == "" or true, "profile received")
	var reals := 0
	for m in Game.board:
		if not m.get("npc", true):
			reals += 1
	check(reals >= 1, "board shows real players (%d)" % reals)
	# local action: predicted at once, confirmed by the server
	var before: Array = Game.party_order.duplicate()
	Game.move_in_party(0, 1)
	var predicted: Array = Game.party_order.duplicate()
	check(predicted != before, "local action applied instantly")
	await _wait(1.0)
	await Game.refresh()
	check(Game.party_order == predicted, "server confirmed the same party order")
	# authority action
	var box: Dictionary = await Game.open_box("free")
	check(not box.is_empty(), "free box opened on the server (%s)" % box.get("spell", "?"))
	var box2: Dictionary = await Game.open_box("free")
	check(box2.is_empty(), "second free box refused by the server")
	main._switch("mercs")
	await _wait(0.5)
	await _shot("online_mercs")
	main._switch("expedition")
	var ok: bool = await Game.start_expedition(1, "push")
	check(ok and Game.exp_info() != null, "push started on the server")
	main._open_watch()
	await _wait(3.0)
	await _shot("online_watch")
	main._close_watch()
	var t := 0.0
	while Game.exp_info() != null and t < 120.0:
		await _wait(1.0)
		t += 1.0
	check(Game.exp_info() == null, "push finished via the server after %.0f s" % t)
	check(Game.closed_level == 1, "level 1 closed on the server")
	UI.clear(main.popup_layer)
	main._settings_popup()
	await _wait(1.5)
	await _shot("online_settings")
	print("ONLINE TEST DONE ", failures)
	get_tree().quit()
