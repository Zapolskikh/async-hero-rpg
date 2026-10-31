extends Node
## Dev helper: run the game with `-- --shots=<dir>` to walk through the screens
## and save screenshots (used to check the UI without a phone).

var out_dir := "user://shots"
var main: Node
var crafts_only := false
var gear_only := false
var spells_only := false
var weapons_only := false
var meter_only := false
var talents_only := false
var atlas_only := false
var doll_only := false
var shop_only := false
var farm_only := false
var fb_only := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out_dir = a.substr(8)
		if a == "--shots-crafts":
			crafts_only = true
		if a == "--shots-spells":
			spells_only = true
		if a == "--shots-weapons":
			weapons_only = true
		if a == "--shots-meter":
			meter_only = true
		if a == "--shots-gear":
			gear_only = true
		if a == "--shots-talents":
			talents_only = true
		if a == "--shots-atlas":
			atlas_only = true
		if a == "--shots-doll":
			doll_only = true
		if a == "--shots-shop":
			shop_only = true
		if a == "--shots-farm":
			farm_only = true
		if a == "--shots-fb":
			fb_only = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = get_parent()
	if fb_only:
		_run_fb()
	elif farm_only:
		_run_farm()
	elif shop_only:
		_run_shop()
	elif doll_only:
		_run_doll()
	elif atlas_only:
		_run_atlas()
	elif talents_only:
		_run_talents()
	elif gear_only:
		_run_gear()
	elif meter_only:
		_run_meter()
	elif weapons_only:
		_run_weapons()
	elif spells_only:
		_run_spells()
	elif crafts_only:
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
	await _shot("16a_craft_choice")
	await Game.prof_choose("blacksmithing")
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

func _run_spells() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	var col: Dictionary = Game.profile["collection"]
	col["fireball"] = {"lvl": 3, "copies": 7}
	col["strike"] = {"lvl": 2, "copies": 2}
	col["heal"] = {"lvl": 10, "copies": 5}
	col["cleave"] = {"lvl": 1, "copies": 4}
	Game.changed.emit()
	main._switch("spells")
	await _wait(0.5)
	await _shot("20_spells_levels")
	main._spell_popup("fireball")
	await _wait(0.4)
	await _shot("21_spell_popup_upgrade")
	UI.clear(main.popup_layer)
	main._spell_popup("heal")
	await _wait(0.4)
	await _shot("21b_heal_threshold")
	print("shots done")
	get_tree().quit()

func _run_weapons() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var p: Dictionary = Game.profile
	p["hero"]["level"] = 8
	var gs := Loot.roll_gear(rng, 8, "first", "", "greatsword")
	var sh := Loot.roll_gear(rng, 8, "first", "", "shield")
	var sw := Loot.roll_gear(rng, 8, "first", "", "sword")
	var bow := Loot.roll_gear(rng, 8, "first", "", "bow")
	var st := Loot.roll_gear(rng, 8, "first", "", "staff")
	p["inventory"].append_array([gs, sh, sw, bow, st])
	for sid in ["mortal_strike", "whirlwind", "aimed_shot", "shield_slam", "twin_strike", "arcane_bolt", "shield_wall", "arrow_rain"]:
		p["collection"][sid] = {"lvl": 1, "copies": 0}
	p["hero"]["rotation"] = ["mortal_strike", "strike", "aimed_shot"]
	Game.equip(gs["id"])
	Game.changed.emit()
	main._switch("hero")
	await _wait(0.5)
	await _shot("22_hero_greatsword")
	main.selected_item = sw["id"]
	main._switch("bag")
	await _wait(0.5)
	await _shot("23_bag_sword")
	main._spell_popup("aimed_shot")
	await _wait(0.4)
	await _shot("24_spell_needs_bow")
	UI.clear(main.popup_layer)
	Game.equip(sw["id"])
	Game.equip(sh["id"])
	main._switch("hero")
	await _wait(0.5)
	await _shot("25_hero_sword_shield")
	main._switch("spells")
	await _wait(0.5)
	await _shot("26_spells_weapons")
	main._switch("mercs")
	await _wait(0.4)
	main._merc_popup(Game.board[0])
	await _wait(0.4)
	await _shot("27_merc_weapons")
	print("shots done")
	get_tree().quit()

## Gear art on the hero screen and in battle.
func _run_gear() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	Game.profile["hero"]["level"] = 12
	for key in ["tank_t2_0_plate_head", "tank_t2_0_plate_armor", "tank_t2_0_plate_hands", "tank_t2_0_plate_legs", "tank_t2_0_plate_feet", "tank_t2_0_sword", "tank_t2_0_shield"]:
		var it := Items.make(key, 12, key)
		Game.profile["inventory"].append(it)
		Game.equip(it["id"], "offhand" if it["slot"] == "offhand" else "")
	main._switch("hero")
	await _wait(0.5)
	await _shot("40_gear_hero")
	await Game.start_expedition(1, "push")
	main._open_watch()
	await _wait(3.0)
	await _shot("41_gear_battle")
	print("shots done")
	get_tree().quit()

func _run_meter() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	await Game.start_expedition(1, "push")
	main._open_watch()
	await _wait(0.4)
	await _shot("28_meter_start")
	await _wait(6.0)
	await _shot("29_meter_fight")
	var units: Array = Game.expedition.sim.units
	for u in units:
		u.buffs["wall"] = {"value": 0.3, "remaining": 6.0, "src": u}
		u.hots.append({"id": "renew", "src": u, "per_tick": 1.0, "remaining": 9.0, "duration": 9.0, "tick": 1.0, "decay": 0.0})
		u.dots.append({"id": "e_plague", "per_tick": 1.0, "remaining": 7.0, "tick": 1.0, "src": u, "school": "magic"})
		u.buffs["weakness"] = {"value": 0.2, "remaining": 4.0, "src": u}
		u.shield = 50.0
		u.shield_time = 8.0
		u.shield_sid = "barrier"
		u.silence = 3.0
	await _wait(0.2)
	await _shot("29a_statuses")
	Game.profile["time_warp"] = float(Game.profile.get("time_warp", 0.0)) + 3000.0
	await _wait(1.5)
	await _shot("29b_meter_result")
	UI.clear(main.popup_layer)
	main._on_expedition_finished({"won": 1, "lost": 0, "closed": true, "level": 1, "gold": 120, "xp": 200, "items": [], "boxes": 1})
	await _wait(0.5)
	await _shot("29c_meter_win")
	UI.clear(main.popup_layer)
	main._close_watch()
	main._settings_popup()
	await _wait(0.4)
	await _shot("29d_settings")
	print("shots done")
	get_tree().quit()

func _run_talents() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	Game.profile["hero"]["level"] = 10
	Game.talent_up("toughness")
	Game.talent_up("focus")
	Game.talent_up("focus")
	Game.talent_up("spell_crit")
	main._switch("hero")
	await _wait(0.4)
	await _shot("30_hero_talents_button")
	main._talents_popup()
	await _wait(0.5)
	await _shot("31_talents")
	print("shots done")
	get_tree().quit()

func _run_atlas() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	Game.profile["closed_level"] = 20
	Game.profile["hero"]["level"] = 30
	Game.profile["recipes_known"] = ["core_blade"]
	for r in ["iron_ore", "raw_leather", "coal", "tough_leather", "silver_ore", "mithril_fragment", "boss_core"]:
		Rules._add_res(Game.profile, r, 40)
	Game.changed.emit()
	main._switch("expedition")
	await _wait(0.5)
	await _shot("32_level_mods")
	main._atlas_popup(21)
	await _wait(0.5)
	await _shot("33_atlas")
	UI.clear(main.popup_layer)
	CraftsScreen.view = "craft"
	CraftsScreen.craft_prof = "blacksmithing"
	main._switch("crafts")
	await _wait(0.5)
	main.content.get_child(0)._set_view("craft")
	await _wait(0.4)
	await _shot("34_weapon_recipes")
	print("shots done")
	get_tree().quit()

func _run_doll() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var p: Dictionary = Game.profile
	for spec in [["armor", "", 0.3], ["head", "", 0.3], ["legs", "", 0.0], ["feet", "", 0.5], ["hands", "", 0.3], ["trinket", "", 0.6], ["", "shield", 0.3]]:
		var it := Loot.roll_gear(rng, 3, "first", spec[0], spec[1])
		p["inventory"].append(it)
		Game.equip(it["id"])
	Game.changed.emit()
	main._switch("hero")
	await _wait(0.5)
	await _shot("35_doll_hero")
	Rules._add_res(Game.profile, "minor_strength_potion", 3)
	Rules._add_res(Game.profile, "gatherers_tonic", 1)
	await Game.use_item("minor_recovery_potion")
	Rules._add_res(Game.profile, "minor_recovery_potion", 1)
	await Game.use_item("minor_recovery_potion")
	main._switch("bag")
	await _wait(0.5)
	await _shot("35b_bag_potions")
	await Game.start_expedition(1, "push")
	main._open_watch()
	await _wait(2.5)
	await _shot("36_doll_battle")
	print("shots done")
	get_tree().quit()

func _run_shop() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	await Game.fake_purchase("c1200")
	await Game.buy_cosmetic("glow_gold")
	await Game.buy_cosmetic("aura_fire")
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	for spec in [["armor", "", 0.3], ["head", "", 0.3], ["legs", "", 0.0], ["feet", "", 0.5], ["", "shield", 0.3]]:
		var it := Loot.roll_gear(rng, 1, "first", spec[0], spec[1])
		Game.profile["inventory"].append(it)
		Game.equip(it["id"])
	Game.profile["hero"]["level"] = 9
	var old := Loot.roll_gear(rng, 2, "first", "", "greatsword")
	Game.profile["inventory"].append(old)
	main.selected_item = old["id"]
	Game.changed.emit()
	main._shop_popup()
	await _wait(0.5)
	await _shot("37_shop")
	UI.clear(main.popup_layer)
	main._switch("bag")
	await _wait(0.5)
	await _shot("38_bag_upgrade")
	main._switch("spells")
	await _wait(0.5)
	await _shot("39_spells_buy")
	await Game.start_expedition(1, "push")
	main._open_watch()
	await _wait(2.0)
	await _shot("40_aura_glow")
	print("shots done")
	get_tree().quit()

func _run_farm() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	Game.profile["closed_level"] = 14
	Game.profile["hero"]["level"] = 20
	await Game.start_expedition(3, "farm")
	main._switch("expedition")
	await _wait(1.0)
	await _shot("42_farm_hub")
	print("shots done")
	get_tree().quit()

func _run_fb() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	Game.profile["hero"]["level"] = 12
	Game.profile["gold"] = 5000
	Game.profile["closed_level"] = 5
	for i in 7:
		Game.profile["inventory"].append(Loot.roll_gear(rng, 5 + i, "drop", "", "", "", i % 2))
	Game.profile["inventory"].append(Loot.roll_gear(rng, 10, "first", "armor"))
	Game.profile["inventory"].append(Loot.roll_gear(rng, 8, "first", "armor"))
	Game.changed.emit()
	main._switch("hero")
	await _wait(0.4)
	main._gear_popup("armor")
	await _wait(0.4)
	await _shot("43_gear_slot")
	UI.clear(main.popup_layer)
	main._talents_popup()
	await _wait(0.4)
	await _shot("44_talents_ranks")
	UI.clear(main.popup_layer)
	main._dummy_popup()
	await _wait(0.4)
	await _shot("45_dummy")
	UI.clear(main.popup_layer)
	main._switch("bag")
	await _wait(0.3)
	main._merge_popup()
	await _wait(0.4)
	await _shot("46_merge")
	UI.clear(main.popup_layer)
	await _shot("47_bag_sort")
	await Game.start_expedition(5, "farm")
	main._open_watch()
	await _wait(6.0)
	main._meter_details(main.meter_rows, 0, "dealt_by", "Урон")
	await _wait(0.4)
	await _shot("48_meter_breakdown")
	print("shots done")
	get_tree().quit()
