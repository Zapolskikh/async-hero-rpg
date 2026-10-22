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

const SAVE_PATH := "user://save.json"
const AUTOSAVE_EVERY := 10.0

# re-exported for the UI
const BOX_PRICE := Rules.BOX_PRICE
const BOX_PACK := Rules.BOX_PACK
const BOX_PACK_PRICE := Rules.BOX_PACK_PRICE
const FUSE_COUNT := Rules.FUSE_COUNT
const MAX_HIRED := Rules.MAX_HIRED
const OFFLINE_CAP := Rules.OFFLINE_CAP

var profile: Dictionary = {}
var mode := "offline"               # "online" when connected to a server (see Net)
var watch_speed := 1.0
var expedition: Expedition = null   # live copy for the battle view only (rewards come from Rules)
var offline_report := {}            # shown once after loading
var rng := RandomNumberGenerator.new()

var _view_id := ""
var _autosave := 0.0

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
	if not load_game():
		new_game()
	get_tree().set_auto_accept_quit(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_game()

## Game clock. Offline, watching at x2/x4 also speeds up the expedition (time warp).
func now() -> float:
	return Time.get_unix_time_from_system() + float(profile.get("time_warp", 0.0))

func _process(delta: float) -> void:
	if expedition != null:
		expedition.advance(delta * watch_speed)
	if mode == "offline" and watch_speed > 1.0 and profile.get("expedition") != null:
		profile["time_warp"] = float(profile.get("time_warp", 0.0)) + delta * (watch_speed - 1.0)
	if Rules.push_finished(profile, now()):
		_tick()
	_autosave += delta
	if _autosave >= AUTOSAVE_EVERY:
		_autosave = 0.0
		save_game()

# ---------------- lifecycle ----------------

func new_game() -> void:
	profile = Rules.new_profile(rng.randi(), now())
	expedition = null
	_view_id = ""
	save_game()
	changed.emit()

func reset_progress() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	new_game()

func _tick() -> void:
	var out := Rules.tick(profile, now(), {})
	for rep in out["reports"]:
		_emit_report(rep)
	_after_change()

func _emit_report(rep: Dictionary) -> void:
	if rep.get("type", "") == "push_end":
		expedition_finished.emit(rep)
	else:
		report.emit(rep)

func _after_change() -> void:
	_sync_view()
	changed.emit()

## Keeps the live battle copy in step with the profile's expedition.
func _sync_view() -> void:
	var ex = profile.get("expedition")
	if ex == null:
		expedition = null
		_view_id = ""
		return
	if ex["id"] == _view_id:
		return
	_view_id = ex["id"]
	var v := Expedition.new()
	v.start(int(ex["level"]), ex["mode"], ex["party"], int(ex["seed"]), bool(ex.get("first", false)))
	if ex["mode"] == "push":
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

func can_fuse(sid: String, lvl: int) -> bool:
	return Rules.can_fuse(profile, sid, lvl)

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

## Applies an action. Local actions run immediately; in online mode they are
## also sent to the server, authority actions only run there (see Net).
func act(action: String, args: Dictionary = {}) -> Dictionary:
	var res := Rules.apply(profile, action, args, now(), {})
	if res.get("ok", false):
		_after_change()
		if action in Rules.AUTHORITY_ACTIONS:
			save_game()
	return res

func set_rotation(rotation: Array) -> void:
	act("set_rotation", {"rotation": rotation})

func move_in_party(index: int, dir: int) -> void:
	act("move_party", {"index": index, "dir": dir})

func equip(id: String) -> void:
	act("equip", {"id": id})

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

func fuse(sid: String, lvl: int) -> bool:
	return act("fuse", {"sid": sid, "lvl": lvl})["ok"]

# authority actions (await them)

func reroll_board() -> bool:
	return act("reroll")["ok"]

func open_box(use: String) -> Dictionary:
	var res := act("open_box", {"use": use})
	return res["boxes"][0] if res["ok"] else {}

func open_box_pack(use: String) -> Array:
	var res := act("open_pack", {"use": use})
	return res["boxes"] if res["ok"] else []

func start_expedition(level: int, mode_name: String) -> bool:
	return act("start", {"level": level, "mode": mode_name})["ok"]

func stop_expedition() -> Dictionary:
	var res := act("stop")
	return res["report"] if res["ok"] else {}

func collect() -> Dictionary:
	var res := act("collect")
	return res["report"] if res["ok"] else {}

## Dev helper (screenshot runner): rebuild the starter group from the board.
func _auto_party() -> void:
	Rules._auto_party(profile)

# ---------------- save / load ----------------

func save_game() -> void:
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
