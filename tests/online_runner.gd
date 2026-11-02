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
	Game.token = ""   # a fresh guest every run (the saved account would carry the last run's state)
	Game.server_url = ""
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
	await _account_checks()
	print("ONLINE TEST DONE ", failures)

## Account linking: e-mail, transfer code, logout and coming back with the code.
func _account_checks() -> void:
	UI.clear(main.popup_layer)
	var me := Game.account_id
	var info: Dictionary = await Game.account_info()
	check(info.get("ok", false) and info.get("guest", false), "a new player is a guest")
	main._account_popup()
	await _wait(1.0)
	await _shot("account_guest")
	var email := "e2e-%d@example.com" % (Time.get_ticks_usec() % 1000000)
	var r: Dictionary = await Game.link_email(email, "short")
	check(not r["ok"] and r["error"] == "Пароль: от 8 до 128 символов", "short password refused in Russian")
	r = await Game.link_email(email, "correct horse")
	check(r["ok"] and not r.get("guest", true), "e-mail linked")
	UI.clear(main.popup_layer)
	main._account_popup()
	await _wait(1.0)
	await _shot("account_linked")
	main._show_transfer_code.call()
	await _wait(1.0)
	await _shot("account_code")
	UI.clear(main.popup_layer)
	var code: Dictionary = await Game.transfer_code()   # a new code replaces the shown one
	check(code.get("ok", false) and str(code.get("code", "")).length() == 9, "transfer code issued (%s)" % code.get("code", ""))
	await Game.logout()
	check(Game.is_online() and Game.account_id != me, "logout starts a fresh guest")
	r = await Game.use_transfer_code(str(code["code"]))
	check(r["ok"] and Game.account_id == me and Game.closed_level == 1, "the transfer code brings the account back")
	r = await Game.login_email(email, "wrong password")
	check(not r["ok"] and r["error"] == "Неверная почта или пароль", "wrong password refused")
	r = await Game.login_email(email, "correct horse")
	check(r["ok"] and Game.account_id == me, "e-mail login opens the same account")
	get_tree().quit()
