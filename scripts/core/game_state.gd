extends Node
## Autoload "Game": holds the player's profile and talks to the rules.
##
## All game logic lives in Rules (shared with the server). This node only
##   - keeps the profile (offline: saved locally; online: mirrored from the server),
##   - runs a live copy of the current expedition for the battle view,
##   - exposes convenient getters and action methods for the UI.
##
## Local actions (no randomness) apply instantly. Authority actions (boxes,
## rerolls, expeditions, rewards) are coroutines: callers should `await` them,
## because in online mode they wait for the server.

signal changed
signal expedition_finished(report: Dictionary)
signal report(report: Dictionary)
signal online_changed

const SAVE_PATH := "user://save.json"
const ACCOUNT_PATH := "user://account.json"
const REFRESH_EVERY := 60.0
const AUTOSAVE_EVERY := 10.0

# re-exported for the UI
const BOX_PRICE := Rules.BOX_PRICE
const BOX_PACK := Rules.BOX_PACK
const SPELL_MAX_LEVEL := Rules.SPELL_MAX_LEVEL
const MAX_HIRED := Rules.MAX_HIRED
const OFFLINE_CAP := Rules.OFFLINE_CAP

var profile: Dictionary = {}
var mode := "offline"               # "online" when connected to a server (see Net)
var watch_speed := 1.0
var expedition: Expedition = null   # live copy for the battle view only (rewards come from Rules)
var last_battle: Expedition = null  # the finished one, still shown with its meters
var offline_report := {}            # shown once after loading
var rng := RandomNumberGenerator.new()

var _view_id := ""
var _autosave := 0.0

# online mode
var net: Net
var server_url := ""
var account_id := ""
var token := ""
var time_offset := 0.0            # server clock - local clock
var online_status := ""           # human-readable connection state for the settings screen
var busy := false                 # an authority request is in flight
var _queue: Array = []            # local actions waiting to be confirmed by the server
var _queue_running := false
var _refreshing := false
var _refresh_timer := 0.0
var _telemetry: Array = []        # client events for analytics, sent with the next refresh
## Release builds (export feature "online_only", or --online-only[=url]) play only on the server:
## no local save, no offline mode, no time skip. The page/app shows a blocking screen until connected.
var online_only := false
var update_required := false       # the server runs a newer build than this client
## Build of this client (build.json, written by CI before export; empty in local builds).
var build_id := ""

# ---------------- profile getters (UI convenience) ----------------

var gold: int:
	get: return int(profile.get("gold", 0))
	set(v): profile["gold"] = v
var boxes: int:
	get: return int(profile.get("boxes", 0))
	set(v): profile["boxes"] = v
var closed_level: int:
	get: return int(profile.get("closed_level", 0))
	set(v): profile["closed_level"] = v
var hero: Dictionary:
	get: return profile.get("hero", {})
var collection: Dictionary:
	get: return profile.get("collection", {})
var inventory: Array:
	get: return profile.get("inventory", [])
var board: Array:
	get: return profile.get("board", [])
	set(v): profile["board"] = v
var hired: Array:
	get: return profile.get("hired", [])
	set(v): profile["hired"] = v
var party_order: Array:
	get: return profile.get("party_order", [])
	set(v): profile["party_order"] = v

func _ready() -> void:
	rng.randomize()
	net = Net.new()
	add_child(net)
	build_id = _read_build()
	net.build = build_id
	if "--qa" in OS.get_cmdline_user_args():
		profile = Rules.new_profile(20261028, now())
		return
	var forced := _arg("--online-only")
	online_only = OS.has_feature("online_only") or forced != ""
	if online_only:
		# Placeholder profile under the connecting screen; nothing is saved on the device.
		profile = Rules.new_profile(rng.randi(), now())
		get_tree().set_auto_accept_quit(false)
		_load_account()
		var url := forced if forced.begins_with("http") else _default_server()
		if url == "":
			url = _page_api()
		if url != "":
			server_url = url
		mode = "offline"
		online_status = "Подключение…"
		_resume_online.call_deferred()
		return
	if not load_game():
		new_game()
	get_tree().set_auto_accept_quit(false)
	_load_account()
	if server_url == "":
		server_url = _default_server()
	if mode == "online" and token != "":
		mode = "offline"
		_resume_online.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_game()

## Test builds only: the «Промотать время» button (never online, never in online_only builds).
const DEV_TIME_SKIP := true

## Game clock. time_warp moves an offline game forward (test time skip).
func now() -> float:
	if mode == "online":
		return Time.get_unix_time_from_system() + time_offset
	return Time.get_unix_time_from_system() + float(profile.get("time_warp", 0.0))

func _process(delta: float) -> void:
	if expedition != null:
		expedition.advance(delta * watch_speed)
	elif last_battle != null and last_battle.sim != null and not last_battle.sim.finished:
		# The rules may close a push a moment before this live copy gets there: play the last
		# wave to its end (visual only), so the losing side falls instead of freezing on low HP.
		last_battle.sim.advance(delta * watch_speed)
	# x2..x8 (offline) speeds up only the expedition: it is moved back in time,
	# so professions, potions and daily timers keep real time
	if mode == "offline" and watch_speed > 1.0 and profile.get("expedition") != null:
		var ex: Dictionary = profile["expedition"]
		ex["started_at"] = float(ex["started_at"]) - delta * (watch_speed - 1.0)
	if Rules.push_finished(profile, now()):
		if mode == "online":
			refresh()
		else:
			_tick()
	if mode == "online":
		_refresh_timer += delta
		if _refresh_timer >= REFRESH_EVERY:
			_refresh_timer = 0.0
			refresh()
			flush_telemetry()
	_autosave += delta
	if _autosave >= AUTOSAVE_EVERY:
		_autosave = 0.0
		save_game()

# ---------------- lifecycle ----------------

func new_game() -> void:
	profile = Rules.new_profile(rng.randi(), now())
	expedition = null
	_drop_last_battle()
	_view_id = ""
	save_game()
	changed.emit()

func reset_progress() -> void:
	if "--qa" in OS.get_cmdline_user_args():
		new_game()
		return
	if mode == "online":
		return  # server progress is not reset from the client
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	new_game()

func _tick() -> void:
	var out := Rules.tick(profile, now(), {})
	for rep in out["reports"]:
		_emit_report(rep)
	_after_change()

func _emit_report(rep: Dictionary) -> void:
	if rep.get("type", "") in ["push_end", "mythic_end"]:
		expedition_finished.emit(rep)
	else:
		report.emit(rep)

func _after_change() -> void:
	_sync_view()
	changed.emit()

func _drop_last_battle() -> void:
	if last_battle != null and last_battle.sim != null:
		last_battle.sim.release()
	last_battle = null

## The battle to show: the running one, else the one that just ended.
func shown_battle() -> Expedition:
	return expedition if expedition != null else last_battle

## Keeps the live battle copy in step with the profile's expedition.
func _sync_view() -> void:
	var ex = profile.get("expedition")
	if ex == null:
		if expedition != null:
			_drop_last_battle()
			last_battle = expedition
		expedition = null
		_view_id = ""
		return
	if ex["id"] == _view_id:
		return
	_drop_last_battle()
	if expedition != null and expedition.sim != null:
		expedition.sim.release()
	_view_id = ex["id"]
	var v := Expedition.new()
	v.start(int(ex["level"]), ex["mode"], ex["party"], int(ex["seed"]), bool(ex.get("first", false)))
	if Expedition.is_attempt(ex["mode"]):
		# jump to the wave the push is at right now (deterministic: same seed as the authority)
		var done := Expedition.waves_done_at(ex["tl"], now() - float(ex["started_at"]))
		v.record_events = false
		for i in done:
			if not v.finished:
				v.step_wave_headless()
		v.record_events = true
	expedition = v

# ---------------- queries ----------------

func hero_snapshot() -> Dictionary:
	return Rules.hero_snapshot(profile)

func merc_by_id(id: String):
	return Rules.merc_by_id(profile, id)

func is_hired(id: String) -> bool:
	return Rules.is_hired(profile, id)

func party_snapshots() -> Array:
	return Rules.party_snapshots(profile)

func party_ready() -> bool:
	return Rules.party_ready(profile)

func level_unlocked(level: int) -> bool:
	return Rules.level_unlocked(profile, level)

func reroll_cost() -> int:
	return Rules.reroll_cost(profile, now())

func free_box_available() -> bool:
	return Rules.free_box_available(profile, now())

func can_fuse(sid: String) -> bool:
	return Rules.can_fuse(profile, sid)

func fuse_cost(lvl: int) -> int:
	return Rules.fuse_cost(lvl)

func spell_copies(sid: String) -> int:
	return int(collection.get(sid, {}).get("copies", 0))

func owned_spells() -> Array:
	var out := []
	for sid in collection.keys():
		if Roster.spell_best_level(collection, sid) > 0:
			out.append(sid)
	out.sort_custom(func(a, b): return Db.SPELLS[a]["name"] < Db.SPELLS[b]["name"])
	return out

## Current expedition from the profile (authoritative), or null.
func exp_info():
	return profile.get("expedition")

func pending() -> Dictionary:
	return Rules.pending(profile, now())

func has_pending() -> bool:
	var pd := pending()
	return pd["gold"] > 0 or pd["xp"] > 0 or pd["items"] > 0 or pd["boxes"] > 0

# ---------------- actions ----------------

## Local action: applied immediately. Online it is also queued to the server,
## whose answer then replaces the profile (normally identical).
func act(action: String, args: Dictionary = {}) -> Dictionary:
	var res := Rules.apply(profile, action, args, now(), {})
	if res.get("ok", false):
		_after_change()
		if mode == "online":
			_queue.append([action, args])
			if not _queue_running:
				_run_queue()
		elif action in Rules.AUTHORITY_ACTIONS:
			save_game()
	return res

## Authority action (randomness / rewards). Offline: local rules. Online: the
## server decides and the UI waits. Always `await` it.
func act_authority(action: String, args: Dictionary = {}) -> Dictionary:
	if mode != "online":
		return act(action, args)
	while _queue_running:
		await get_tree().process_frame
	busy = true
	changed.emit()
	var r := await net.post_json("/v1/action", {"action": action, "args": args})
	busy = false
	var d: Dictionary = r["data"]
	if d.has("profile"):
		_apply_view(d)
	else:
		changed.emit()
	if r["status"] == 0:
		online_status = "Нет связи с сервером"
		online_changed.emit()
	elif r["status"] == 426:
		_need_update()
	if d.has("result") and typeof(d["result"]) == TYPE_DICTIONARY and not d["result"].is_empty():
		return d["result"]
	return {"ok": false, "error": str(d.get("error", "ошибка сервера"))}

func set_rotation(rotation: Array) -> void:
	act("set_rotation", {"rotation": rotation})

func move_in_party(index: int, dir: int) -> void:
	act("move_party", {"index": index, "dir": dir})

func equip(id: String, to: String = "") -> void:
	act("equip", {"id": id, "to": to})

## Hero "Мощь" if this item were put on (slot "" = its own slot).
func power_with(it: Dictionary, slot: String = "") -> int:
	var h: Dictionary = hero.duplicate(true)
	Rules.place_item(h["equipped"], it.duplicate(true), slot if slot != "" else str(it["slot"]))
	return Roster.power_score(Roster.hero_snapshot(h, collection))

func power_now() -> int:
	return Roster.power_score(hero_snapshot())

func unequip(slot: String) -> void:
	act("unequip", {"slot": slot})

func sell(id: String) -> void:
	act("sell", {"id": id})

func hire(id: String) -> bool:
	return act("hire", {"id": id})["ok"]

func fire(id: String) -> void:
	act("fire", {"id": id})

func replace_hired(old_id: String, new_id: String) -> bool:
	return act("replace", {"old": old_id, "new": new_id})["ok"]

func talent_up(id: String) -> bool:
	return act("talent_up", {"id": id})["ok"]

func set_threshold(sid: String, value: float) -> void:
	act("set_threshold", {"sid": sid, "value": value})

## Threshold the hero uses for this spell (player setting or the spell's own).
func spell_threshold(sid: String) -> float:
	var st: Dictionary = hero.get("spell_settings", {})
	if st.has(sid) and st[sid].has("threshold"):
		return float(st[sid]["threshold"])
	return float(Db.SPELLS[sid].get("threshold", 0.7))

var crystals: int:
	get: return int(profile.get("crystals", 0))

func gold_box_price() -> int:
	return Rules.gold_box_price(profile, now())

func gold_pack_price() -> int:
	return Rules.gold_pack_price(profile, now())

func gold_boxes_today() -> int:
	return Rules.gold_boxes_today(profile, now())

func set_cosmetic(slot: String, id: String) -> void:
	act("set_cosmetic", {"slot": slot, "id": id})

func set_appearance(sex: String, hair: String) -> Dictionary:
	var result := act("set_appearance", {"sex": sex, "hair": hair})
	if result.get("ok", false):
		if expedition != null:
			for i in expedition.party.size():
				var snapshot: Dictionary = expedition.party[i]
				if snapshot.get("is_hero", false) and not snapshot.has("owner"):
					snapshot["appearance"] = hero["appearance"].duplicate()
					expedition.allies[i].appearance = hero["appearance"].duplicate()
		save_game()
	return result

func fake_purchase(pack: String) -> Dictionary:
	return await act_authority("fake_purchase", {"pack": pack})

func buy_cosmetic(id: String) -> Dictionary:
	return await act_authority("buy_cosmetic", {"id": id})

func rush(what: String, prof: String = "") -> Dictionary:
	return await act_authority("rush", {"what": what, "prof": prof})

func buy_boost() -> Dictionary:
	return await act_authority("buy_boost", {})

func merge_items(rarity: int, ids: Array = []) -> Dictionary:
	return await act_authority("merge_items", {"rarity": rarity, "ids": ids})

func merge_claim() -> Dictionary:
	return await act_authority("merge_claim")

func tutorial(args: Dictionary) -> void:
	act("tutorial", args)

func talent_reset() -> void:
	act("talent_reset")

func fuse(sid: String) -> bool:
	return act("fuse", {"sid": sid})["ok"]

# authority actions (await them)

func reroll_board() -> bool:
	var res: Dictionary = await act_authority("reroll")
	return res.get("ok", false)

func open_box(use: String) -> Dictionary:
	var res: Dictionary = await act_authority("open_box", {"use": use})
	return res["boxes"][0] if res.get("ok", false) else {}

func open_box_pack(use: String) -> Array:
	var res: Dictionary = await act_authority("open_pack", {"use": use})
	return res["boxes"] if res.get("ok", false) else []

## Offline test helper: everything that runs on the clock (farm, gathering, crafting,
## daily limits) behaves as if `sec` seconds passed.
func skip_time(sec: float) -> Dictionary:
	if mode == "online" or online_only:
		return {"ok": false, "error": "в онлайне время ведёт сервер"}
	if sec <= 0.0:
		return {"ok": false, "error": "нечего мотать"}
	var before := pending()
	profile["time_warp"] = float(profile.get("time_warp", 0.0)) + sec
	var st := Rules._stats(profile)
	st["skipped_sec"] = float(st["skipped_sec"]) + sec
	_tick()
	save_game()
	var after := pending()
	return {"ok": true, "gold": int(after["gold"]) - int(before["gold"]), "xp": int(after["xp"]) - int(before["xp"]),
		"items": int(after["items"]) - int(before["items"])}

func mythic() -> Dictionary:
	return profile.get("mythic", {})

func mythic_keys() -> int:
	return Rules.res_count(profile, Db.MYTHIC_KEY)

func mythic_open() -> bool:
	return Rules.mythic_open(profile)

func start_mythic() -> Dictionary:
	return await act_authority("start", {"mode": "mythic"})

func start_expedition(level: int, mode_name: String) -> bool:
	var res: Dictionary = await act_authority("start", {"level": level, "mode": mode_name})
	return res.get("ok", false)

func stop_expedition() -> Dictionary:
	var res: Dictionary = await act_authority("stop")
	return res["report"] if res.get("ok", false) else {}

func collect() -> Dictionary:
	var res: Dictionary = await act_authority("collect")
	return res["report"] if res.get("ok", false) else {}

# professions (authority actions: await them)

func gather_start(prof: String, loc: String, sec: int) -> Dictionary:
	return await act_authority("gather_start", {"prof": prof, "loc": loc, "sec": sec})

func gather_claim() -> Dictionary:
	return await act_authority("gather_claim")

func gather_cancel() -> Dictionary:
	return await act_authority("gather_cancel")

func prof_choose(prof: String) -> Dictionary:
	return await act_authority("prof_choose", {"prof": prof})

func craft_start(recipe: String) -> Dictionary:
	return await act_authority("craft_start", {"recipe": recipe})

func craft_claim(prof: String) -> Dictionary:
	return await act_authority("craft_claim", {"prof": prof})

func use_item(res: String) -> Dictionary:
	return await act_authority("use_item", {"res": res})

func rename_hero(new_name: String) -> bool:
	return act("set_name", {"name": new_name})["ok"]

## Dev helper (screenshot runner): rebuild the starter group from the board.
func _auto_party() -> void:
	Rules._auto_party(profile)

# ---------------- online ----------------

## Server address from the page URL (web: ?server=https://...) or empty.
func _default_server() -> String:
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('server') || ''", true)
		if typeof(v) == TYPE_STRING:
			return v
	return ""

func is_online() -> bool:
	return mode == "online"

## API next to the web page: https://host/async-hero/ -> https://host/async-hero/api.
func _page_api() -> String:
	if not OS.has_feature("web"):
		return ""
	var v = JavaScriptBridge.eval("window.location.origin + window.location.pathname.replace(/[^/]*$/, '') + 'api'", true)
	return str(v) if typeof(v) == TYPE_STRING else ""

## Value of a "--name=value" command line argument ("" if absent, "1" for a bare flag).
func _arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a == name:
			return "1"
		if a.begins_with(name + "="):
			return a.substr(name.length() + 1)
	return ""

static func _read_build() -> String:
	if not FileAccess.file_exists("res://build.json"):
		return ""
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://build.json"))
	return str(d.get("build", "")) if typeof(d) == TYPE_DICTIONARY else ""

## The server answered 426: it runs another build. Web reloads the page, apps ask for an update.
func _need_update() -> void:
	if update_required:
		return
	update_required = true
	online_status = "Доступна новая версия игры"
	online_changed.emit()

## Connects to a server: resumes the saved account or creates a guest one.
func connect_online(url: String, name: String = "") -> Dictionary:
	url = url.strip_edges().rstrip("/")
	if not (url.begins_with("http://") or url.begins_with("https://")):
		return {"ok": false, "error": "адрес должен начинаться с https://"}
	if url != server_url:
		token = ""
		account_id = ""
	server_url = url
	net.base_url = url
	online_status = "Подключение…"
	online_changed.emit()
	var r: Dictionary
	if token != "":
		net.token = token
		r = await net.get_json("/v1/me")
		if r["status"] == 401:
			token = ""
	if token == "":
		net.token = ""
		r = await net.post_json("/v1/auth/guest", {"name": name if name != "" else str(hero.get("name", "Герой"))})
		if r["status"] == 200:
			token = r["data"]["token"]
			account_id = r["data"]["account_id"]
			net.token = token
	if r["status"] == 426:
		_need_update()
		return {"ok": false, "error": online_status}
	if r["status"] != 200:
		online_status = "Ошибка: " + str(r["data"].get("error", r["data"].get("detail", "сервер недоступен")))
		if r["status"] == 0:
			online_status = "Нет связи с сервером"
		online_changed.emit()
		return {"ok": false, "error": online_status}
	save_game()  # keep the offline progress safe before switching
	mode = "online"
	var size := DisplayServer.window_get_size()
	track({"e": "session", "platform": OS.get_name(), "online_only": online_only, "w": size.x, "h": size.y, "build": build_id.substr(0, 12)})
	_view_id = ""
	_apply_view(r["data"])
	online_status = "Онлайн"
	_save_account()
	online_changed.emit()
	return {"ok": true}

## Analytics: a client event (screen opened, popup, session start). Online only, batched.
func track(event: Dictionary) -> void:
	if mode != "online" or _telemetry.size() >= 50:
		return
	_telemetry.append(event)

func flush_telemetry() -> void:
	if mode != "online" or _telemetry.is_empty():
		return
	var batch := _telemetry.duplicate()
	_telemetry.clear()
	await net.post_json("/v1/telemetry", {"events": batch})

func _resume_online() -> void:
	await connect_online(server_url)

func go_offline() -> void:
	if online_only:
		return
	mode = "offline"
	online_status = ""
	_queue.clear()
	_save_account()
	if not load_game():
		new_game()
	_view_id = ""
	_sync_view()
	online_changed.emit()
	changed.emit()

## Pulls the latest profile from the server (finishes pushes, pays assists).
func refresh() -> void:
	if mode != "online" or _refreshing:
		return
	_refreshing = true
	var r := await net.get_json("/v1/me")
	_refreshing = false
	if r["status"] == 200:
		_apply_view(r["data"])
		if online_status != "Онлайн":
			online_status = "Онлайн"
			online_changed.emit()
	elif r["status"] == 426:
		_need_update()
	elif r["status"] == 0:
		online_status = "Нет связи с сервером"
		online_changed.emit()

func _run_queue() -> void:
	_queue_running = true
	while not _queue.is_empty():
		var item: Array = _queue.pop_front()
		var r := await net.post_json("/v1/action", {"action": item[0], "args": item[1]})
		if r["status"] == 200 and r["data"].has("profile"):
			if _queue.is_empty():
				_apply_view(r["data"])
		elif r["status"] == 426:
			_queue.clear()
			_need_update()
		elif r["status"] == 0:
			online_status = "Нет связи с сервером"
			online_changed.emit()
			_queue.clear()
		else:
			_queue.clear()
			_queue_running = false
			await refresh()  # server disagreed: take its state
			return
	_queue_running = false

## Takes the server's answer: profile, clock offset, reports to show.
func _apply_view(d: Dictionary) -> void:
	if d.has("server_time"):
		time_offset = float(d["server_time"]) - Time.get_unix_time_from_system()
	if d.has("profile") and typeof(d["profile"]) == TYPE_DICTIONARY:
		profile = d["profile"]
		Rules.migrate(profile, now())
	for rep in d.get("reports", []):
		_emit_report(rep)
	_after_change()

# ---------------- account linking (server/app/accounts.py) ----------------

const ACCOUNT_ERRORS := {
	"bad email": "Неверный адрес почты",
	"password must be 8-128 characters": "Пароль: от 8 до 128 символов",
	"email already linked": "Почта уже привязана",
	"email belongs to another account": "Эта почта привязана к другому аккаунту",
	"wrong email or password": "Неверная почта или пароль",
	"wrong password": "Неверный пароль",
	"too many attempts, try later": "Слишком много попыток, попробуйте позже",
	"code is wrong or expired": "Код неверный или устарел",
	"no email linked": "Почта не привязана",
	"google sign-in is not configured": "Вход через Google пока не подключён",
	"apple sign-in is not configured": "Вход через Apple пока не подключён",
}

func _account_result(r: Dictionary) -> Dictionary:
	var d: Dictionary = r["data"]
	if r["status"] == 200:
		d["ok"] = true
		return d
	var err := str(d.get("error", d.get("detail", "")))
	return {"ok": false, "error": ACCOUNT_ERRORS.get(err, "Нет связи с сервером" if r["status"] == 0 else "Ошибка: " + err)}

## {ok, guest, linked: {email, google, apple}, providers: {google, apple}}
func account_info() -> Dictionary:
	if mode != "online":
		return {"ok": false, "error": "Доступно в онлайне"}
	return _account_result(await net.get_json("/v1/account"))

func link_email(email: String, password: String) -> Dictionary:
	return _account_result(await net.post_json("/v1/account/email", {"email": email, "password": password}))

func change_password(old: String, new_password: String) -> Dictionary:
	return _account_result(await net.post_json("/v1/account/password", {"old": old, "new": new_password}))

## {ok, code: "ABCD-EFGH", ttl}
func transfer_code() -> Dictionary:
	return _account_result(await net.post_json("/v1/account/transfer-code", {}))

func login_email(email: String, password: String) -> Dictionary:
	return await _login(await net.post_json("/v1/auth/login", {"email": email, "password": password}))

func use_transfer_code(code: String) -> Dictionary:
	return await _login(await net.post_json("/v1/auth/transfer", {"code": code}))

## A login answers with a new device token and the profile of that account.
func _login(r: Dictionary) -> Dictionary:
	var res := _account_result(r)
	if not res["ok"]:
		return res
	token = str(res["token"])
	account_id = str(res["account_id"])
	net.token = token
	mode = "online"
	_queue.clear()
	_view_id = ""
	_apply_view(res)
	online_status = "Онлайн"
	_save_account()
	online_changed.emit()
	return {"ok": true}

## Ends this device's session and starts a fresh guest (only offered once the account is linked).
func logout() -> void:
	await net.post_json("/v1/auth/logout", {})
	token = ""
	account_id = ""
	net.token = ""
	_save_account()
	await connect_online(server_url)

func leaderboard() -> Dictionary:
	if server_url == "":
		return {}
	var saved_token := net.token
	net.base_url = server_url
	var r := await net.get_json("/v1/leaderboard")
	net.token = saved_token
	return r["data"] if r["status"] == 200 else {}

func _save_account() -> void:
	var f := FileAccess.open(ACCOUNT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"server": server_url, "token": token, "account_id": account_id, "mode": mode}))

func _load_account() -> void:
	if not FileAccess.file_exists(ACCOUNT_PATH):
		return
	var f := FileAccess.open(ACCOUNT_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	if typeof(d) != TYPE_DICTIONARY:
		return
	server_url = str(d.get("server", ""))
	token = str(d.get("token", ""))
	account_id = str(d.get("account_id", ""))
	mode = str(d.get("mode", "offline"))
	net.base_url = server_url
	net.token = token

# ---------------- save / load ----------------

func save_game() -> void:
	if "--qa" in OS.get_cmdline_user_args():
		return
	if mode != "offline":
		return
	profile["saved_at"] = now()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(profile))

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or not data.has("hero"):
		return false
	profile = data
	var saved_at: float = float(profile.get("saved_at", profile.get("time", now())))
	Rules.migrate(profile, now())
	_make_offline_report(saved_at)
	_sync_view()
	return true

func _make_offline_report(saved_at: float) -> void:
	var ex = profile.get("expedition")
	var away := now() - saved_at
	if ex == null or away < 5.0:
		return
	var before := Rules.pending(profile, saved_at)
	var after := Rules.pending(profile, now())
	offline_report = {
		"away": min(away, OFFLINE_CAP), "level": ex["level"], "mode": ex["mode"],
		"gold": after["gold"] - before["gold"], "xp": after["xp"] - before["xp"],
		"items": after["items"] - before["items"],
		"won": after["won"] - before["won"], "lost": after["lost"] - before["lost"],
	}
