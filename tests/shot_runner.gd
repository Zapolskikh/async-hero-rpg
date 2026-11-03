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
var mythic_only := false
var dev_only := false
var fx_level := 0
var enemy_fx := false
var boxes_only := false
var skins_only := false
var wskins_only := false
var tutorial_only := false
var ending_only := false
var layout_only := false
var skins_female := false

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
		if a == "--shots-mythic":
			mythic_only = true
		if a == "--shots-dev":
			dev_only = true
		if a == "--shots-layout":
			layout_only = true
		if a == "--shots-ending":
			ending_only = true
		if a == "--shots-tutorial":
			tutorial_only = true
		if a == "--shots-wskins":
			wskins_only = true
		if a == "--shots-skins" or a == "--shots-skins-female":
			skins_only = true
			skins_female = a.ends_with("female")
		if a == "--shots-boxes":
			boxes_only = true
		if a == "--shots-enemyfx":
			enemy_fx = true
		if a.begins_with("--shots-fx="):
			fx_level = a.trim_prefix("--shots-fx=").to_int()
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = get_parent()
	if layout_only:
		_run_layout()
	elif ending_only:
		_run_ending()
	elif tutorial_only:
		_run_tutorial()
	elif wskins_only:
		_run_wskins()
	elif skins_only:
		_run_skins()
	elif boxes_only:
		_run_boxes()
	elif enemy_fx:
		_run_enemy_fx()
	elif fx_level > 0:
		_run_fx()
	elif dev_only:
		_run_dev()
	elif mythic_only:
		_run_mythic()
	elif fb_only:
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
	var acc_rng := RandomNumberGenerator.new()
	acc_rng.seed = 3
	var shown := []
	for q in [2, 3, 4, 5]:
		var acc := Items.roll(acc_rng, 12, q, "accessory", "", "tank")
		Game.profile["inventory"].append(acc)
		shown.append(acc)
	Game.equip(shown[2]["id"], "accessory1")
	Game.equip(shown[3]["id"], "accessory2")
	main._switch("hero")
	await _wait(0.5)
	await _shot("40_gear_hero")
	main._item_popup(shown[3])
	await _wait(0.3)
	await _shot("40a_accessory_legendary")
	UI.clear(main.popup_layer)
	main._item_popup(shown[1])
	await _wait(0.3)
	await _shot("40b_accessory_rare")
	UI.clear(main.popup_layer)
	Game.profile["gold"] = 5000
	for i in 8:
		Game.profile["inventory"].append(Loot.roll_gear(acc_rng, 8 + i, "drop", "", "", "", 1))
	main._merge_popup()
	await _wait(0.3)
	await _shot("40c_merge")
	main._merge_pick_popup(1)
	await _wait(0.3)
	await _shot("40d_merge_pick")
	UI.clear(main.popup_layer)
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
	var top = Game.expedition.sim.unit_by_uid(int(main.meter_rows[0]["uid"]))
	for k in ["fire_totem", "ignition", "echo", "item:fireball", "thorns", "paired_blades"]:
		top.dealt_by[k] = 40.0 + top.dealt_by.size() * 7.0
	for k in ["healing_totem", "living_cover", "reserve", "lifesteal"]:
		top.healed_by[k] = 30.0 + top.healed_by.size() * 5.0
	main._meter_details(main.meter_rows, 0, "dealt_by", "Урон")
	await _wait(0.3)
	await _shot("29d_meter_breakdown")
	UI.clear(main.popup_layer)
	main._meter_details(main.meter_rows, 0, "healed_by", "Лечение + поглощение")
	await _wait(0.3)
	await _shot("29e_heal_breakdown")
	UI.clear(main.popup_layer)
	var units: Array = Game.expedition.sim.units
	for u in units:
		u.buffs["wall"] = {"value": 0.3, "remaining": 6.0, "src": u}
		u.hots.append({"id": "renew", "src": u, "per_tick": 1.0, "remaining": 9.0, "duration": 9.0, "tick": 1.0, "decay": 0.0})
		u.dots.append({"id": "e_plague", "per_tick": 1.0, "remaining": 7.0, "duration": 7.0, "tick": 1.0, "src": u, "school": "magic", "spell_dot": false})
		u.buffs["weakness"] = {"value": 0.2, "remaining": 4.0, "src": u}
		u.shield = 50.0
		u.shield_time = 8.0
		u.shield_sid = "barrier"
		u.silence = 3.0
	# cooldown sweeps on the hero: global cooldown 45% left, own cooldowns 80% left
	var hero_u = null
	for u in units:
		if u.side == 0 and not u.is_npc:
			hero_u = u
	for f in 12:
		if hero_u != null:
			hero_u.silence = 0.0
			hero_u.stun = 0.0
			hero_u.spell_cd = hero_u.spell_interval() * 0.45
			for e in hero_u.spells:
				if Db.spell_cd(e["id"], int(e.get("lvl", 1))) > 0.0:
					hero_u.cooldowns[e["id"]] = Db.spell_cd(e["id"], int(e.get("lvl", 1))) * 0.8
		await get_tree().process_frame
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
	Game.profile["hero"]["level"] = 30
	for id in ["focus", "focus", "focus", "fast_cast", "fast_cast", "spark", "spark", "spark", "echo", "echo", "echo", "ignition", "ignition", "ignition", "ignition"]:
		Game.talent_up(id)
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

## Mythic+: locked card, open card with keys, a running attempt and the result window.
func _run_mythic() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	await _wait(0.5)
	main._select_level(main.MYTHIC_NODE)
	await _wait(0.4)
	await _shot("m1_locked")
	Game.profile["hero"]["level"] = Db.HERO_MAX_LEVEL
	Game.profile["resources"][Db.MYTHIC_KEY] = 3
	Game.profile["mythic"]["best"] = 2
	Game.profile["mythic"]["best_time"] = 254.3
	Game.profile["mythic"]["level"] = 3
	Game.changed.emit()
	main._refresh()
	await _wait(0.5)
	await _shot("m2_open")
	main._mythic_leaderboard_popup()
	await _wait(0.4)
	await _shot("m3_board")
	UI.clear(main.popup_layer)
	main._start_mythic()
	Game.watch_speed = 4.0
	await _wait(3.0)
	await _shot("m4_battle")
	main._close_watch()
	await _wait(0.4)
	await _shot("m5_running")
	main._on_mythic_finished({"mode": "mythic", "closed": true, "level": 3, "time": 241.7, "gold": Db.mythic_gold(3), "boxes": 1, "mythic_next": 4, "mythic_record": true})
	await _wait(0.4)
	await _shot("m6_result")
	get_tree().quit()

## Test build tools: time skip window and the statistics window.
func _run_dev() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	await _wait(0.3)
	await Game.start_expedition(1, "push")
	Game.skip_time(600.0)
	UI.clear(main.popup_layer)
	await Game.start_expedition(1, "farm")
	main._close_watch()
	main._skip_popup()
	await _wait(0.4)
	await _shot("d1_skip")
	UI.clear(main.popup_layer)
	main._do_skip(7200)
	UI.clear(main.popup_layer)
	main._switch("hero")
	main._stats_popup()
	await _wait(0.4)
	await _shot("d2_stats")
	get_tree().quit()

## Spell visuals: a push on a level with enemy casters, a frame every 0.12 s.
func _run_fx() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	Game.profile["closed_level"] = fx_level - 1
	Game.profile["hero"]["level"] = 12
	await _wait(0.3)
	main._start(fx_level, "push")
	Game.watch_speed = 1.0
	await _wait(1.0)
	for i in 70:
		await _wait(0.12)
		await _shot("fx_%03d" % i)
	get_tree().quit()

## Every enemy spell cast on the party, three frames per spell; plus a shot absorbed by a shield
## a killing blow and an enemy cast aimed at an ally.
func _run_enemy_fx() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	var ex := Expedition.new()
	ex.level = 1
	ex.mode = "push"
	var allies := []
	for i in 4:
		var weapons: Array = [["sword","shield"],["bow"],["staff"],["staff"]][i]
		allies.append(BattleUnit.new(i,0,i,{"name":["Страж","Лучник","Маг","Лекарь"][i],"ranged":i>0,"stats":{"hp":10000.,"atk":0.,"power":90.,"str":100.,"agi":100.},"weapons":weapons,"talents":{},"spells":[]}))
	var foes := []
	for i in 3:
		var eid: String = ["warlock","caster","boss_lich"][i]
		var snap := Expedition.enemy_snapshot(eid, 5)
		snap["stats"]["hp"] = 100000.
		snap["stats"]["atk"] = 0.
		snap["spells"] = []
		foes.append(snap)
	ex.allies = allies
	ex.sim = BattleSim.new()
	ex.sim.setup(allies,foes,123)
	Game.expedition = ex
	main._open_watch()
	Game.watch_speed = 1.0
	await _wait(.5)
	var caster: BattleUnit = ex.sim.foes_of(allies[0])[0]
	# an enemy cast with its aim shown
	caster.casting = {"spell":"e_bolt","lvl":1,"remaining":1.6,"total":2.4,"target":allies[2],"interruptible":true,"threshold":-1.}
	await _wait(.3)
	await _shot("e_00_aim")
	caster.casting = {}
	for sid in ["e_bolt","e_curse","e_plague","e_volley","e_cataclysm","e_breath","e_doom","e_quake","e_mend","e_smash"]:
		var tgt: BattleUnit = allies[2] if Db.SPELLS[sid]["kind"] != "heal" else caster
		ex.sim._cast(caster,sid,1,tgt)
		ex.sim.events.append_array([])
		await _wait(.12)
		await _shot("e_%s_1" % sid)
		await _wait(.2)
		await _shot("e_%s_2" % sid)
		await _wait(.35)
		await _shot("e_%s_3" % sid)
		for a in allies: a.hp = a.max_hp
	# two Wild Growths from different healers on the same ally: one icon with ×2
	ex.sim._hot(allies[2],allies[1],"wild_growth",50.,6.,true)
	ex.sim._hot(allies[3],allies[1],"wild_growth",50.,6.,true)
	ex.sim._hot(allies[3],allies[1],"renew",30.,8.)
	await _wait(.3)
	await _shot("e_zy_stacks")
	# absorbed by a shield
	allies[2].shield = 99999.
	ex.sim._cast(caster,"e_bolt",1,allies[2])
	await _wait(.2)
	await _shot("e_zz_absorb_1")
	await _wait(.35)
	await _shot("e_zz_absorb_2")
	allies[2].shield = 0.
	# killing blow: the body waits for the bolt
	allies[3].hp = 5.
	ex.sim._cast(caster,"e_bolt",1,allies[3])
	await _wait(.15)
	await _shot("e_zz_kill_1")
	await _wait(.35)
	await _shot("e_zz_kill_2")
	await _wait(.6)
	await _shot("e_zz_kill_3")
	get_tree().quit()

## Spell boxes for gold: the price before and after the first ten of a day.
func _run_boxes() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	Game.profile["gold"] = 50000
	main._switch("spells")
	await _wait(.4)
	await _shot("b1_price")
	for i in 12:
		Rules.apply(Game.profile, "open_box", {"use": "gold"}, Game.now())
	UI.clear(main.popup_layer)
	main._refresh()
	await _wait(.4)
	await _shot("b2_after12")
	get_tree().quit()

## Worn armour of every type in each rarity, and the crafted sets, on the hero screen.
## Every tab must fit between the top bar and the bottom menu (the menu is never cut).
func _run_layout() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	for tab in ["expedition", "hero", "mercs", "spells", "crafts", "bag"]:
		main._switch(tab)
		main._refresh()
		await _wait(0.5)
		var win: Vector2 = main.get_rect().size
		var nav_bottom: float = main.nav_bar.get_global_rect().end.y
		print("layout %s: content min %.0f of %.0f, menu %.0f..%.0f of %.0f %s" % [tab, main.content.get_combined_minimum_size().y,
			main.content.size.y, main.nav_bar.get_global_rect().position.y, nav_bottom, win.y, "OK" if nav_bottom <= win.y + 0.5 else "CUT"])
		if tab == "hero":
			var scr = main.content.get_child(0)
			for c in scr.get_children():
				print("   column min ", c.get_combined_minimum_size())
		await _shot("layout_" + tab)
	print("shots done")
	get_tree().quit()

## How a push ends on screen: a won level and a lost one, a moment after the rules closed it.
func _run_ending() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	for case in [[1, "win"], [12, "loss"]]:
		Game.profile["closed_level"] = int(case[0]) - 1
		await main._start(int(case[0]), "push")
		Game.watch_speed = 8.0
		var waited := 0.0
		while Game.expedition != null and waited < 400.0:
			await _wait(0.5)
			waited += 0.5
		UI.clear(main.popup_layer)
		Game.watch_speed = 1.0
		main._open_watch()
		await _wait(0.6)
		await _shot("end_%s_a" % case[1])
		# the live copy may still be a few seconds behind the rules: let it play out
		var lb = Game.last_battle
		var t := 0.0
		while lb != null and lb.sim != null and not lb.sim.finished and t < 20.0:
			await _wait(0.5)
			t += 0.5
		await _wait(2.0)
		UI.clear(main.popup_layer)
		await _shot("end_%s_b" % case[1])
	print("shots done")
	get_tree().quit()

## The first-session guide, step by step, and an unlock hint.
func _run_tutorial() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	main._switch("expedition")
	main._refresh()
	await _wait(.8)
	await _shot("t0_welcome")
	main.tutorial._advance(0)
	await _wait(.8)
	await _shot("t1_push")
	await main._start(1, "push")
	await _wait(2.5)
	await _shot("t2_watch")
	main.tutorial._advance(2)
	await _wait(1.0)
	await _shot("t3_box")
	main._open_box("token")
	await _wait(1.5)
	await _shot("t3b_box_opened")
	UI.clear(main.popup_layer)
	await _wait(1.0)
	await _shot("t4_rotation")
	main.tutorial._advance(4)
	await _wait(.8)
	await _shot("t5_bag")
	main.tutorial._advance(5)
	await _wait(.8)
	await _shot("t6_mercs")
	main.tutorial._advance(6)
	await _wait(.8)
	await _shot("t7_farm")
	main.tutorial._advance(7)
	Game.profile["hero"]["level"] = 5
	Game.changed.emit()
	await _wait(1.2)
	await _shot("t8_hint_talents")
	print("shots done")
	get_tree().quit()

## Every weapon skin in the hero's hands: <type>_q<rarity>.png
func _run_wskins() -> void:
	Game.reset_progress()
	UI.clear(main.popup_layer)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	main._switch("hero")
	await _wait(.6)
	for wt in ["sword", "greatsword", "staff", "bow", "shield"]:
		for q in 6:
			var eq: Dictionary = Game.profile["hero"]["equipped"]
			eq["offhand"] = null
			var it := Items.roll(rng, 25, q, "", "sword" if wt == "shield" else wt, "")
			it["rarity"] = q
			eq["weapon"] = it
			if wt == "shield":
				var sh := Items.roll(rng, 25, q, "", "shield", "")
				sh["rarity"] = q
				eq["offhand"] = sh
			Game.changed.emit()
			main._switch("hero")
			main._refresh()
			await _wait(.4)
			await _shot("w_%s_%d" % [wt, q])
	get_tree().quit()

func _run_skins() -> void:
	Game.reset_progress()
	if skins_female:
		Game.profile["hero"]["appearance"] = {"sex": "female", "hair": "f04"}
	UI.clear(main.popup_layer)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var looks := []
	for atype in ["plate", "leather", "cloth"]:
		for q in 6:
			looks.append([atype, q, ""])
	for craft in [["plate", "iron_chestguard"], ["plate", "mithril_helm"], ["cloth", "linen_tunic"], ["cloth", "enchanted_robe"], ["leather", "ranger_cowl"], ["leather", "shadowhide_hood"]]:
		looks.append([craft[0], 3, craft[1]])
	for entry in looks:
		for slot in ["head", "armor", "hands", "legs", "feet"]:
			var it := Items.roll(rng, 25, entry[1], slot, "", "tank")
			it["atype"] = entry[0]
			it["slot"] = slot
			it["look"] = ("crafted_" + entry[2]) if entry[2] != "" else "%s_%s_t5" % [entry[0], slot]
			Game.profile["hero"]["equipped"][slot] = it
		Game.changed.emit()
		main._switch("hero")
		main._refresh()
		await _wait(.4)
		await _shot("s_%s_%d_%s" % [entry[0], entry[1], entry[2]])
	get_tree().quit()
