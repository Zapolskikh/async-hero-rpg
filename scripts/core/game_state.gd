extends Node
## Autoload "Game": player profile, economy, expedition loop, saving.
## Everything is local for the prototype; in the real game this state lives on
## the server (concept 12/15) and the client only displays it.

signal changed
signal expedition_finished(report: Dictionary)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const OFFLINE_CAP := 12.0 * 3600.0
const AUTOSAVE_EVERY := 10.0
const BOX_PRICE := 150
const REROLL_BASE := 20
const REROLL_GROWTH := 1.5       # each reroll today costs x1.5 more
const MAX_HIRED := 3
const FUSE_COUNT := 5

var gold := 0
var boxes := 0
var closed_level := 0            # highest fully cleared campaign level
var hero := {}
var collection := {}             # spell_id -> {"1": copies, "2": copies, ...}
var inventory: Array = []        # gear not equipped
var board: Array = []            # guild board: up to 6 candidates, never includes hired ones
var hired: Array = []            # your 3 mercenaries, kept separately from the board
var party_order: Array = []      # 4 entries: "hero" or merc id, slot order
var rerolls_today := 0
var reroll_day := ""
var free_box_day := ""

var expedition: Expedition = null
var watch_speed := 1.0
var offline_report := {}         # shown once after loading
var last_report := {}

var rng := RandomNumberGenerator.new()
var _autosave := 0.0

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

func _process(delta: float) -> void:
	if expedition != null and not expedition.finished:
		expedition.advance(delta * watch_speed)
		if expedition.finished:
			_finish_push()
	_autosave += delta
	if _autosave >= AUTOSAVE_EVERY:
		_autosave = 0.0
		save_game()

# ---------------- new game ----------------

func new_game() -> void:
	gold = 100
	boxes = 1
	closed_level = 0
	hero = {
		"name": "Герой", "level": 1, "xp": 0,
		"rotation": ["fireball", "strike", "kick"],
		"equipped": {"weapon": null, "armor": null, "trinket": null},
	}
	collection = {}
	for sid in Db.STARTER_SPELLS:
		collection[sid] = {"1": 1}
	inventory = []
	hired = []
	board = Roster.roll_board(rng, hero["level"])
	_auto_party()
	board = Roster.roll_board(rng, hero["level"])
	expedition = null
	save_game()
	changed.emit()

func _auto_party() -> void:
	# starter group: tank + healer + one more, from the first board
	var picks := []
	for role in ["Танк", "Лекарь"]:
		for m in board:
			if m["role"] == role and not picks.has(m):
				picks.append(m)
				break
	for m in board:
		if picks.size() >= MAX_HIRED:
			break
		if not picks.has(m) and not m["role"] in ["Танк", "Лекарь"]:
			picks.append(m)
	for m in board:
		if picks.size() >= MAX_HIRED:
			break
		if not picks.has(m):
			picks.append(m)
	hired = picks
	# tank in front, hero second, then the others
	party_order = [picks[0]["id"], "hero", picks[2]["id"], picks[1]["id"]]

# ---------------- hero / party ----------------

func hero_snapshot() -> Dictionary:
	return Roster.hero_snapshot(hero, collection)

func merc_by_id(id: String):
	for m in hired:
		if m["id"] == id:
			return m
	for m in board:
		if m["id"] == id:
			return m
	return null

func is_hired(id: String) -> bool:
	for m in hired:
		if m["id"] == id:
			return true
	return false

func party_snapshots() -> Array:
	var out := []
	for id in party_order:
		if id == "hero":
			out.append(hero_snapshot())
		else:
			var m = merc_by_id(id)
			if m != null:
				out.append(m)
	return out

func party_ready() -> bool:
	return party_snapshots().size() == 4

## Takes a candidate from the board into the group (goes to the backline).
func hire(id: String) -> bool:
	if hired.size() >= MAX_HIRED:
		return false
	for m in board:
		if m["id"] == id:
			board.erase(m)
			hired.append(m)
			party_order.append(id)
			changed.emit()
			return true
	return false

## Dismissed mercenaries leave for good; they do not return to the board.
func fire(id: String) -> void:
	for m in hired:
		if m["id"] == id:
			hired.erase(m)
			party_order.erase(id)
			changed.emit()
			return

## Board candidate takes the place (and party position) of a hired one.
func replace_hired(old_id: String, new_id: String) -> bool:
	var newcomer = null
	for m in board:
		if m["id"] == new_id:
			newcomer = m
	if newcomer == null or not is_hired(old_id):
		return false
	board.erase(newcomer)
	for i in hired.size():
		if hired[i]["id"] == old_id:
			hired[i] = newcomer
	var pos := party_order.find(old_id)
	party_order[pos] = new_id
	changed.emit()
	return true

func move_in_party(index: int, dir: int) -> void:
	var j := index + dir
	if j < 0 or j >= party_order.size():
		return
	var tmp = party_order[index]
	party_order[index] = party_order[j]
	party_order[j] = tmp
	changed.emit()

func reroll_cost() -> int:
	_check_day()
	return int(round(REROLL_BASE * pow(REROLL_GROWTH, rerolls_today) / 5.0) * 5)

## Replaces all 6 board candidates. Your hired group is not touched.
func reroll_board() -> bool:
	var cost := reroll_cost()
	if gold < cost:
		return false
	gold -= cost
	rerolls_today += 1
	board = Roster.roll_board(rng, hero["level"])
	changed.emit()
	return true

func set_rotation(rotation: Array) -> void:
	hero["rotation"] = rotation
	changed.emit()

func owned_spells() -> Array:
	var out := []
	for sid in collection.keys():
		if Roster.spell_best_level(collection, sid) > 0:
			out.append(sid)
	out.sort_custom(func(a, b): return Db.SPELLS[a]["name"] < Db.SPELLS[b]["name"])
	return out

func equip(item_id: String) -> void:
	for it in inventory:
		if it["id"] == item_id:
			var slot: String = it["slot"]
			var old = hero["equipped"][slot]
			hero["equipped"][slot] = it
			inventory.erase(it)
			if old != null:
				inventory.append(old)
			changed.emit()
			return

func unequip(slot: String) -> void:
	var it = hero["equipped"][slot]
	if it != null:
		inventory.append(it)
		hero["equipped"][slot] = null
		changed.emit()

func sell(item_id: String) -> void:
	for it in inventory:
		if it["id"] == item_id:
			gold += Loot.sell_price(it)
			inventory.erase(it)
			changed.emit()
			return

func add_xp(amount: int) -> int:
	var ups := 0
	hero["xp"] += amount
	while hero["xp"] >= Db.xp_to_next(hero["level"]):
		hero["xp"] -= Db.xp_to_next(hero["level"])
		hero["level"] += 1
		ups += 1
	return ups

# ---------------- spells ----------------

func free_box_available() -> bool:
	return free_box_day != _today()

func open_box(use: String) -> Dictionary:
	match use:
		"free":
			if not free_box_available():
				return {}
			free_box_day = _today()
		"token":
			if boxes <= 0:
				return {}
			boxes -= 1
		"gold":
			if gold < BOX_PRICE:
				return {}
			gold -= BOX_PRICE
	var pool := []
	var weights := [10.0, 5.0, 2.0, 0.7]
	var total := 0.0
	for sid in Db.SPELLS:
		if Db.SPELLS[sid].get("enemy", false):
			continue
		pool.append(sid)
		total += weights[Db.SPELLS[sid]["rarity"]]
	var r := rng.randf() * total
	var pick: String = pool[0]
	for sid in pool:
		r -= weights[Db.SPELLS[sid]["rarity"]]
		if r <= 0.0:
			pick = sid
			break
	if not collection.has(pick):
		collection[pick] = {}
	collection[pick]["1"] = int(collection[pick].get("1", 0)) + 1
	changed.emit()
	return {"spell": pick, "new": int(collection[pick]["1"]) == 1 and Roster.spell_best_level(collection, pick) == 1}

## Fuses FUSE_COUNT copies of level L into one copy of L+1 (concept 5).
func can_fuse(sid: String, lvl: int) -> bool:
	return int(collection.get(sid, {}).get(str(lvl), 0)) >= FUSE_COUNT

func fuse(sid: String, lvl: int) -> bool:
	if not can_fuse(sid, lvl):
		return false
	collection[sid][str(lvl)] = int(collection[sid][str(lvl)]) - FUSE_COUNT
	collection[sid][str(lvl + 1)] = int(collection[sid].get(str(lvl + 1), 0)) + 1
	changed.emit()
	return true

# ---------------- expeditions ----------------

func level_unlocked(level: int) -> bool:
	return level <= closed_level + 1 and level <= Db.level_count()

func start_expedition(level: int, mode: String) -> bool:
	if not party_ready() or not level_unlocked(level):
		return false
	if mode == "farm" and level > closed_level:
		return false
	if expedition != null:
		stop_expedition()
	expedition = Expedition.new()
	expedition.start(level, mode, party_snapshots(), rng.randi(), level > closed_level)
	changed.emit()
	return true

## Stops the current expedition and collects what it earned.
func stop_expedition() -> Dictionary:
	if expedition == null:
		return {}
	var rep := collect()
	expedition = null
	changed.emit()
	return rep

func collect() -> Dictionary:
	if expedition == null:
		return {}
	var r := expedition.take_rewards()
	r["level"] = expedition.level
	r["mode"] = expedition.mode
	_apply_rewards(r)
	changed.emit()
	return r

func _apply_rewards(r: Dictionary) -> void:
	gold += r["gold"]
	boxes += r["boxes"]
	r["level_ups"] = add_xp(r["xp"])
	for it in r["items"]:
		inventory.append(it)
	r["board_refreshed"] = false
	if r["closed"] and r["level"] > closed_level:
		closed_level = r["level"]
		# a new level is cleared: the guild sends a fresh board (free)
		board = Roster.roll_board(rng, hero["level"])
		r["board_refreshed"] = true
	elif r["level_ups"] > 0:
		for i in board.size():
			if int(board[i]["level"]) < hero["level"] - 1:
				board[i] = Roster.relevel(rng, board[i], hero["level"])

func _finish_push() -> void:
	var ex := expedition
	if ex == null or not ex.finished:
		return
	var r := ex.take_rewards()
	r["level"] = ex.level
	r["mode"] = ex.mode
	r["waves"] = ex.best_wave
	r["total_waves"] = ex.total_waves()
	r["reason"] = ex.last_reason
	_apply_rewards(r)
	last_report = r
	expedition = null
	expedition_finished.emit(r)
	changed.emit()

# ---------------- save / load ----------------

func save_game() -> void:
	var data := {
		"v": SAVE_VERSION, "time": Time.get_unix_time_from_system(),
		"gold": gold, "boxes": boxes, "closed_level": closed_level,
		"hero": hero, "collection": collection, "inventory": inventory,
		"board": board, "hired": hired, "party_order": party_order,
		"rerolls_today": rerolls_today, "reroll_day": reroll_day, "free_box_day": free_box_day,
		"expedition": _expedition_to_dict(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or int(data.get("v", 0)) != SAVE_VERSION:
		return false
	gold = int(data["gold"])
	boxes = int(data["boxes"])
	closed_level = int(data["closed_level"])
	hero = data["hero"]
	hero["level"] = int(hero["level"])
	hero["xp"] = int(hero["xp"])
	collection = data["collection"]
	inventory = data["inventory"]
	board = data["board"]
	party_order = data["party_order"]
	if data.has("hired"):
		hired = data["hired"]
	else:
		# older saves kept the group inside the board
		hired = []
		for m in board:
			if party_order.has(m["id"]):
				hired.append(m)
		board = []
	rerolls_today = int(data.get("rerolls_today", 0))
	reroll_day = data.get("reroll_day", "")
	free_box_day = data.get("free_box_day", "")
	_fix_ints()
	var ex = data.get("expedition")
	if ex != null and typeof(ex) == TYPE_DICTIONARY:
		_expedition_from_dict(ex, Time.get_unix_time_from_system() - float(data["time"]))
	return true

## JSON turns every number into float; restore the ints the sim relies on.
func _fix_ints() -> void:
	for it in inventory:
		it["rarity"] = int(it["rarity"])
		it["ilvl"] = int(it["ilvl"])
	for slot in hero["equipped"]:
		var it = hero["equipped"][slot]
		if it != null:
			it["rarity"] = int(it["rarity"])
			it["ilvl"] = int(it["ilvl"])
	for m in board + hired:
		Roster.ensure_merc(m)
	if board.is_empty():
		board = Roster.roll_board(rng, hero["level"])

func _expedition_to_dict():
	if expedition == null or expedition.finished:
		return null
	return {
		"level": expedition.level, "mode": expedition.mode, "party": expedition.party,
		"seed": expedition.base_seed + expedition.run_index * 7919,
		"first": expedition.first_clear_pending,
		"gold": expedition.gold, "xp": expedition.xp, "kills": expedition.kills,
		"items": expedition.items, "boxes": expedition.boxes,
		"won": expedition.runs_won, "lost": expedition.runs_lost,
		"closed_now": expedition.level_closed_now,
	}

func _expedition_from_dict(d: Dictionary, away: float) -> void:
	var party: Array = d["party"]
	for p in party:
		if p.get("npc", false):
			Roster.ensure_merc(p)
		else:
			Roster.ensure_visuals(p)
			for s in p["spells"]:
				s["lvl"] = int(s["lvl"])
	expedition = Expedition.new()
	expedition.start(int(d["level"]), d["mode"], party, int(d["seed"]), d["first"])
	expedition.gold = int(d["gold"])
	expedition.xp = int(d["xp"])
	expedition.kills = int(d["kills"])
	expedition.items = d["items"]
	expedition.boxes = int(d["boxes"])
	expedition.runs_won = int(d["won"])
	expedition.runs_lost = int(d["lost"])
	expedition.level_closed_now = d["closed_now"]
	away = clamp(away, 0.0, OFFLINE_CAP)
	if away > 5.0:
		var before := {"gold": expedition.gold, "xp": expedition.xp, "items": expedition.items.size(),
			"won": expedition.runs_won, "lost": expedition.runs_lost}
		expedition.fast_forward(away)
		offline_report = {
			"away": away, "level": expedition.level, "mode": expedition.mode,
			"gold": expedition.gold - before["gold"], "xp": expedition.xp - before["xp"],
			"items": expedition.items.size() - before["items"],
			"won": expedition.runs_won - before["won"], "lost": expedition.runs_lost - before["lost"],
		}
		if expedition.finished:
			call_deferred("_finish_push")

# ---------------- helpers ----------------

func _today() -> String:
	return Time.get_date_string_from_system()

func _check_day() -> void:
	if reroll_day != _today():
		reroll_day = _today()
		rerolls_today = 0

func reset_progress() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	new_game()
