extends SceneTree
## Tests for the shared rules (client + server). Run:
##   godot --headless --script res://tests/rules_tests.gd

var failures := 0
const T0 := 1_800_000_000.0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)

func _init() -> void:
	test_new_profile_deterministic()
	test_timeline_matches_live()
	test_farm_collect_and_cap()
	test_push_finish()
	test_spell_levels()
	test_weapons()
	test_talents()
	test_rare_loot_and_mods()
	test_crystals()
	test_feedback_fixes()
	test_drop_extra_heroes()
	test_boxes_and_validation()
	test_json_roundtrip()
	test_migrate_v1()
	test_real_players_and_assists()
	test_gathering()
	test_crafting_and_concurrency()
	test_items()
	test_consumables()
	test_combat_materials()
	test_v2_migration()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)

func fresh(seed_value: int = 5) -> Dictionary:
	return Rules.new_profile(seed_value, T0, "Тест")

func test_new_profile_deterministic() -> void:
	print("new profile")
	var a := fresh(42)
	var b := fresh(42)
	var held := []
	for m in a["hired"]:
		held.append(m["weapons"])
	check(held == [["sword", "shield"], ["bow"], ["staff"]], "starter group: tank, archer, healer")
	check(a["party_order"].size() == 4 and a["party_order"][1] == "hero", "the tank stands in front of the hero")
	check(a["hired"][2]["spells"][0]["id"] == "heal", "the starter healer heals")
	var bag := []
	for it in a["inventory"]:
		bag.append(it.get("wtype", ""))
	check(bag == ["staff", "greatsword", "shield", "sword", "bow"], "every weapon type waits in the bag")
	check(JSON.stringify(a) == JSON.stringify(b), "same seed -> identical profile")
	check(a["hired"].size() == 3 and a["board"].size() == 6 and Rules.party_ready(a), "starter group of 3 and a board of 6")

func test_timeline_matches_live() -> void:
	print("timeline vs live battle")
	var p := fresh(7)
	var party := Rules.party_snapshots(p)
	var tl := Expedition.build_timeline(1, "push", party, 123, true)
	var live := Expedition.new()
	live.start(1, "push", party, 123, true)
	var guard := 0
	while not live.finished and guard < 100000:
		live.advance(0.1)
		guard += 1
	check(live.gold == tl["pts"][-1][1] and live.xp == tl["pts"][-1][2], "live view earns exactly the timeline rewards (%d gold)" % live.gold)
	check(abs(live.elapsed - float(tl["t_end"])) < 0.5, "push ends at the same time (%.1f vs %.1f s)" % [live.elapsed, tl["t_end"]])

func test_farm_collect_and_cap() -> void:
	print("farm collect and 12 h cap")
	var p := fresh(9)
	p["closed_level"] = 1
	check(Rules.apply(p, "start", {"level": 1, "mode": "farm"}, T0)["ok"], "farm started")
	var tl: Dictionary = p["expedition"]["tl"]
	var g600: int = Expedition.rewards_at(tl, 600.0)[1]
	var gold0: int = p["gold"]
	var r1 := Rules.apply(p, "collect", {}, T0 + 600.0)
	check(r1["ok"] and r1["report"]["gold"] == g600 and p["gold"] == gold0 + g600, "collect at 10 min gives the timeline gold (%d)" % g600)
	var r2 := Rules.apply(p, "collect", {}, T0 + 600.0)
	check(r2["report"]["gold"] == 0, "collecting twice gives nothing extra")
	var r3 := Rules.apply(p, "collect", {}, T0 + 600.0 + 30.0 * 3600.0)
	var expect: int = Expedition.rewards_at(tl, 600.0 + Rules.OFFLINE_CAP)[1] - g600
	check(r3["report"]["gold"] == expect, "farm is capped at 12 h after the last collect (%d)" % expect)
	check(r3["report"]["items"].size() <= Rules.MAX_ITEMS_PER_COLLECT, "at most %d items per collect, rest auto-sold (%d sold)" % [Rules.MAX_ITEMS_PER_COLLECT, r3["report"]["auto_sold"]])

func test_push_finish() -> void:
	print("push finish")
	var p := fresh(11)
	check(Rules.apply(p, "start", {"level": 1, "mode": "push"}, T0)["ok"], "push started")
	var t_end: float = p["expedition"]["tl"]["t_end"]
	var won: bool = p["expedition"]["tl"]["won"]
	check(Rules.tick(p, T0 + t_end - 1.0)["reports"].is_empty(), "nothing happens before the push ends")
	var out := Rules.tick(p, T0 + t_end + 0.1)
	check(out["reports"].size() == 1 and out["reports"][0]["type"] == "push_end" and p["expedition"] == null, "tick after the end closes the push")
	check(int(p["closed_level"]) == (1 if won else 0), "level closed only on a win (won=%s)" % won)
	check(not Rules.apply(p, "start", {"level": 1, "mode": "push"}, T0 + t_end + 1.0)["ok"] or not won, "cannot push an already cleared level")

func _weapon(rng: RandomNumberGenerator, wtype: String) -> Dictionary:
	return Loot.roll_gear(rng, 10, "drop", "", wtype)

func test_weapons() -> void:
	print("weapons")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var p := fresh(31)
	var eq: Dictionary = p["hero"]["equipped"]
	check(eq["weapon"] != null and eq["weapon"]["wtype"] == "sword" and eq["offhand"] == null, "new hero starts with a sword")
	var gs := _weapon(rng, "greatsword")
	var sh := _weapon(rng, "shield")
	var sw := _weapon(rng, "sword")
	check(gs["slot"] == "weapon" and sh["slot"] == "offhand" and sw["slot"] == "weapon", "weapon types pick their slot")
	check(gs["affixes"][0].get("imp", false) and gs["affixes"][0]["stat"] == "str" and gs["dmg"] > sw["dmg"], "greatsword: implicit strength, more damage than a sword")
	p["inventory"].append_array([gs, sh, sw])
	check(Rules.apply(p, "equip", {"id": sh["id"]}, T0)["ok"] and eq["offhand"] == sh, "shield goes to the left hand")
	check(Rules.apply(p, "equip", {"id": gs["id"]}, T0)["ok"] and eq["weapon"] == gs and eq["offhand"] == null, "two-handed weapon pushes the shield to the bag")
	check(sh in p["inventory"], "the shield is back in the bag")
	check(Rules.apply(p, "equip", {"id": sw["id"], "to": "offhand"}, T0)["ok"] and eq["offhand"] == sw and eq["weapon"] == null, "sword in the left hand pushes the two-hander out")
	check(not Rules.apply(p, "equip", {"id": gs["id"], "to": "offhand"}, T0)["ok"], "two-hander cannot go to the left hand")
	# basic attack follows the weapon
	var base := Db.hero_base_stats(10)
	var st_gs := Roster.combat_stats(base, {"weapon": gs, "offhand": null})
	var st_sw := Roster.combat_stats(base, {"weapon": sw, "offhand": null})
	var st_dual := Roster.combat_stats(base, {"weapon": sw, "offhand": sw})
	var st_none := Roster.combat_stats(base, {"weapon": null, "offhand": null})
	check(st_gs["atk_speed"] > st_sw["atk_speed"] and st_gs["atk"] > st_sw["atk"], "greatsword hits harder and slower (%d/%.1f vs %d/%.1f)" % [st_gs["atk"], st_gs["atk_speed"], st_sw["atk"], st_sw["atk_speed"]])
	check(st_dual["atk"] > st_sw["atk"], "second sword adds damage")
	check(st_none["atk"] == base["str"] and st_sw["atk"] > st_none["atk"], "unarmed attack = strength, a sword is better")
	var bow := _weapon(rng, "bow")
	var b_lo := Roster.combat_stats({"str": 10.0, "agi": 10.0, "power": 10.0, "hp": 100.0}, {"weapon": bow})
	var b_hi := Roster.combat_stats({"str": 10.0, "agi": 60.0, "power": 10.0, "hp": 100.0}, {"weapon": bow})
	var staff := _weapon(rng, "staff")
	var s_hi := Roster.combat_stats({"str": 10.0, "agi": 10.0, "power": 60.0, "hp": 100.0}, {"weapon": staff})
	var s_lo := Roster.combat_stats({"str": 10.0, "agi": 10.0, "power": 10.0, "hp": 100.0}, {"weapon": staff})
	check(b_hi["atk"] > b_lo["atk"], "bow scales with agility")
	check(s_hi["atk"] == 0 and s_lo["atk"] == 0 and staff["affixes"][0]["stat"] == "power", "staff: no basic attack, adds spell power")
	check(st_sw["atk_speed"] < 1.6 and st_gs["atk_speed"] >= 3.0, "one-handed sword is fast, greatsword slow")
	# weapon spells: requirement and bonus
	check(not Db.spell_usable("aimed_shot", ["sword"]) and Db.spell_usable("aimed_shot", ["bow"]), "aimed shot needs a bow")
	check(Db.spell_usable("fireball", ["sword"]) and Db.spell_amount("fireball",1,s_hi,["staff"]) > Db.spell_amount("fireball",1,s_lo,["staff"]), "universal fireball benefits from spell power")
	check(Db.spell_usable("strike", ["sword", "sword"]) and Db.spell_usable("strike", ["greatsword"]), "Bloodthirst supports all swords")
	check(Db.spell_amount("strike", 1, {"str": 50.0, "power": 10.0}, []) == 1.8 * 50.0, "strike scales from strength")
	var hero := {"name": "H", "level": 10, "rotation": ["aimed_shot"], "equipped": {"weapon": sw, "offhand": null}}
	var snap := Roster.hero_snapshot(hero, {"aimed_shot": {"lvl": 1, "copies": 0}})
	var u := BattleUnit.new(0, 0, 0, snap)
	var sim := BattleSim.new()
	sim.setup([u], [{"name": "dummy", "stats": {"hp": 99999.0, "atk": 0.0, "power": 0.0}}], 1)
	check(sim._find_spell_target(u, "aimed_shot") == null, "battle skips a spell without its weapon")
	hero["equipped"]["weapon"] = bow
	var u2 := BattleUnit.new(5, 0, 0, Roster.hero_snapshot(hero, {"aimed_shot": {"lvl": 1, "copies": 0}}))
	sim.setup([u2], [{"name": "dummy", "stats": {"hp": 99999.0, "atk": 0.0, "power": 0.0}}], 1)
	check(sim._find_spell_target(u2, "aimed_shot") != null and u2.atk_speed == 2.8, "with a bow it is used; the bow shoots every 2.8 s")
	# v4 -> v5: old weapons get a type, attack becomes strength
	var old := fresh(32)
	old["hero"]["equipped"]["weapon"] = {"id": "x1", "slot": "weapon", "name": "Посох", "rarity": 1, "ilvl": 5,
		"affixes": [{"stat": "atk", "value": 10.0, "q": 0.8}]}
	old["hero"]["equipped"].erase("offhand")
	old["inventory"] = [{"id": "x2", "slot": "trinket", "name": "Кольцо", "rarity": 0, "ilvl": 3, "affixes": [{"stat": "atk", "value": 5.0, "q": 0.7}]}]
	old["v"] = 4
	var q = JSON.parse_string(JSON.stringify(old))
	Rules.migrate(q, T0)
	var w: Dictionary = q["hero"]["equipped"]["weapon"]
	check(w["wtype"] == "staff" and w["affixes"][0]["stat"] == "str", "old 'Посох' became a staff, attack became strength")
	check(q["inventory"][0]["affixes"][0]["stat"] == "str" and q["hero"]["equipped"].has("offhand"), "old items lose the attack stat; left hand slot added")
	var qs := Rules.hero_snapshot(q)
	check(qs["weapons"] == ["staff"] and qs["stats"]["atk"] == 0, "migrated staff hero casts instead of attacking")

func test_drop_extra_heroes() -> void:
	print("v7 heroes removed")
	var p := fresh(81)
	var main_hero: Dictionary = p["hero"].duplicate(true)
	main_hero["id"] = "h0"
	main_hero["level"] = 15
	var alt: Dictionary = p["hero"].duplicate(true)
	alt["id"] = "h1"
	alt["level"] = 10
	p["hero"] = alt
	p["professions"]["herbalism"]["level"] = 2
	var main_prof := Rules._fresh_professions()
	main_prof["mining"]["level"] = 6
	p["heroes_other"] = [{"hero": main_hero, "professions": main_prof, "gathering": null, "crafting": {}}]
	p["hero_slots"] = 2
	p["crystals"] = 100
	var q = JSON.parse_string(JSON.stringify(p))
	Rules.migrate(q, T0)
	check(int(q["hero"]["level"]) == 15 and int(q["professions"]["mining"]["level"]) == 6, "the first hero is back with his professions")
	check(not q.has("heroes_other") and not q.has("hero_slots") and int(q["crystals"]) == 600, "extra heroes dropped, 500 crystals refunded per slot")

func test_feedback_fixes() -> void:
	print("feedback fixes")
	# maxed spells no longer drop
	var p := fresh(91)
	for sid in Db.SPELLS:
		if not Db.SPELLS[sid].get("enemy", false) and sid != "heal":
			p["collection"][sid] = {"lvl": Rules.SPELL_MAX_LEVEL, "copies": 0}
	p["crystals"] = 10000
	var only_heal := true
	for i in 5:
		for b in Rules.apply(p, "open_pack", {"use": "crystals"}, T0)["boxes"]:
			if b["spell"] != "heal":
				only_heal = false
	check(only_heal, "boxes skip spells at max level")
	# merge
	var q := fresh(92)
	q["gold"] = 1000
	q["inventory"].clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for i in 3:
		q["inventory"].append(Loot.roll_gear(rng, 4 + i, "drop", "", "", "", 0))
	var r := Rules.apply(q, "merge_items", {"rarity": 0}, T0)
	check(r["ok"] and q["inventory"].is_empty(), "merge takes the items at once")
	check(Rules.apply(q, "merge_claim", {}, T0 + 10.0)["error"] == "not finished", "merge takes time")
	check(Rules.apply(q, "merge_claim", {}, T0 + float(Rules.MERGE_TIME[0]))["ok"], "merge finishes on time")
	check(r["ok"] and q["inventory"].size() == 1 and int(q["inventory"][0]["rarity"]) == 1 and int(q["inventory"][0]["ilvl"]) == 6, "3 common -> 1 rare at the highest level")
	check(not Rules.apply(q, "merge_items", {"rarity": 1}, T0)["ok"], "merge needs 3 items")
	# level toughness is evened out
	var lo := 10.0
	var hi := 0.0
	for l in range(1, Db.level_count() + 1):
		lo = min(lo, Db.level_hp_factor(l))
		hi = max(hi, Db.level_hp_factor(l))
	check(lo >= 0.75 and hi <= 1.3 and Db.level_hp_factor(13) < 1.0, "golem/guard levels get less health (%.2f..%.2f, L13 %.2f)" % [lo, hi, Db.level_hp_factor(13)])
	var hr := RandomNumberGenerator.new()
	hr.seed = 5
	var compatible := true
	for i in 30:
		var m := Roster.make_merc(hr,1,20)
		compatible = compatible and Loot.weapon_types(m["gear"]) == m["weapons"]
	check(compatible, "random mercenary equipment matches its weapons")

func test_crystals() -> void:
	print("crystals")
	var p := fresh(61)
	check(int(p["crystals"]) == 0 and Rules.apply(p, "fake_purchase", {"pack": "c550"}, T0)["ok"] and int(p["crystals"]) == 550, "test purchase grants crystals")
	check(not Rules.apply(p, "fake_purchase", {"pack": "nope"}, T0)["ok"], "unknown pack rejected")
	# boxes: gold limited per day, crystals not
	p["gold"] = 100000
	check(Rules.apply(p, "open_pack", {"use": "gold"}, T0)["ok"] and not Rules.apply(p, "open_box", {"use": "gold"}, T0)["ok"], "10 gold boxes a day, then the limit")
	check(Rules.apply(p, "open_box", {"use": "gold"}, T0 + 86400.0)["ok"], "gold limit resets next day")
	var c0 := int(p["crystals"])
	for i in 3:
		Rules.apply(p, "open_pack", {"use": "crystals"}, T0)
	check(int(p["crystals"]) == c0 - 3 * Shop.BOX_PACK_CRYSTALS, "crystal packs have no daily limit")
	# cosmetics
	p["crystals"] = int(p["crystals"]) + 1000
	check(Rules.apply(p, "buy_cosmetic", {"id": "aura_fire"}, T0)["ok"] and p["hero"]["cosmetics"]["aura"] == "aura_fire", "cosmetic bought and worn")
	check(Rules.hero_snapshot(p)["cosmetics"]["aura"] == Shop.COSMETICS["aura_fire"]["color"], "snapshot carries the aura colour")
	check(not Rules.apply(p, "buy_cosmetic", {"id": "aura_fire"}, T0)["ok"], "cannot buy twice")
	Rules.apply(p, "set_cosmetic", {"slot": "aura", "id": ""}, T0)
	check(not p["hero"]["cosmetics"].has("aura") and not Rules.apply(p, "set_cosmetic", {"slot": "glow", "id": "glow_gold"}, T0)["ok"], "take off; cannot wear what you do not own")
	# rush
	Rules.apply(p, "gather_start", {"prof": "mining", "loc": "abandoned_quarry", "sec": 3600}, T0)
	var cr := int(p["crystals"])
	check(Rules.apply(p, "rush", {"what": "gather"}, T0 + 60.0)["ok"] and int(p["crystals"]) == cr - 6, "rush: 59 min left costs 6 crystals")
	check(Rules.apply(p, "gather_claim", {}, T0 + 61.0)["ok"], "rushed gathering can be claimed")
	# farm boost: only gold and xp, only while active
	var q := fresh(62)
	q["crystals"] = 500
	q["closed_level"] = 1
	var a := fresh(62)
	a["closed_level"] = 1
	Rules.apply(q, "start", {"level": 1, "mode": "farm"}, T0)
	Rules.apply(a, "start", {"level": 1, "mode": "farm"}, T0)
	Rules.apply(q, "buy_boost", {}, T0)
	var rq: Dictionary = Rules.apply(q, "collect", {}, T0 + 3600.0)["report"]
	var ra: Dictionary = Rules.apply(a, "collect", {}, T0 + 3600.0)["report"]
	check(rq["gold"] == ra["gold"] * 2 or absi(rq["gold"] - ra["gold"] * 2) <= 1, "boost doubles farm gold (%d vs %d)" % [rq["gold"], ra["gold"]])
	check(rq["items"].size() == ra["items"].size(), "boost does not add items")
func test_items() -> void:
	print("item catalogue")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var counts := [0, 0, 0, 0, 0, 0]
	for i in 4000:
		counts[int(Loot.roll_gear(rng, 12, "first")["rarity"])] += 1
	check(counts[0] == 0 and counts[1] + counts[2] > 3700 and counts[3] < 200 and counts[4] < 40 and counts[5] < 5, "first clears: common and uncommon, the rest is rare (%s)" % str(counts))
	var by_role := {"melee": ["str"], "tank": ["str"], "ranged": ["agi"], "caster": ["power"], "healer": ["power"]}
	var clean := true
	for i in 3000:
		var role: String = Items.ROLES[i % 5]
		var it := Loot.roll_gear(rng, 1 + i % 30, "drop", "", "", role)
		if int(it["rarity"]) == Items.LEGENDARY or it["role"] != role:
			continue
		for a in it["affixes"]:
			if a["stat"] in ["str", "agi", "power"] and not a["stat"] in by_role[role] and not a.get("imp", false):
				clean = false
	check(clean, "an item only has the main stat of its role")
	var keys := 0
	var legendary := 0
	for key in ItemCatalog.NAMED:
		var spec: Dictionary = ItemCatalog.NAMED[key]
		keys += 1
		var it := Items.make(key, 20, "t")
		check(it["slot"] == "accessory" or it["slot"] in Loot.ALL_SLOTS, "%s has a real slot" % key)
		if spec.has("effect"):
			check(Items.EFFECTS.has(spec["effect"]), "%s has a known effect" % key)
		if int(spec["q"]) == Items.LEGENDARY:
			legendary += 1
			check(spec.has("effect"), "%s is legendary through its effect" % key)
	check(keys >= 1000 and legendary >= 30, "big collection (%d items, %d legendary)" % [keys, legendary])
	for id in Items.EFFECTS:
		for p in Items.EFFECTS[id]["fx"].get("procs", []):
			check(Db.SPELLS.has(p["sid"]), "%s procs a real spell" % id)
		for k in Items.EFFECTS[id]["fx"]:
			if k.begins_with("spell:"):
				check(Db.SPELLS.has(k.substr(6)), "%s boosts a real spell" % id)
	var hero := fresh(70)
	var a1 := Items.make("melee_t2_0_accessory", 12, "a1")
	var a2 := Items.make("melee_t2_1_accessory", 12, "a2")
	hero["inventory"].append_array([a1, a2])
	check(Rules.apply(hero, "equip", {"id": "a1"}, T0)["ok"] and Rules.apply(hero, "equip", {"id": "a2"}, T0)["ok"], "accessories go on")
	check(hero["hero"]["equipped"]["accessory1"]["id"] == "a1" and hero["hero"]["equipped"]["accessory2"]["id"] == "a2", "two accessory slots")
	check(Rules.hero_snapshot(hero)["effects"].size() == 2, "worn effects reach the battle")
	var twin := BattleUnit.new(0, 0, 0, {"stats": {"hp": 10.0, "atk": 1.0, "power": 1.0}, "effects": ["twin_wind", "double_5"]})
	check(is_equal_approx(twin.gear_fx["double_attack"], 0.35), "effects add up")
	check(is_equal_approx(Items.damage_bonus({"spell:fireball": 0.35, "magic_bonus": 0.05}, "fireball", "damage", false, "magic", false, 1.0), 0.4), "spell bonus applies")
	var helm := Items.make("tank_t2_0_plate_head", 12, "h1")
	check(["gear:head", "plate_head_t3"] in Roster.look({"head": helm}), "worn art reaches the look layers")
	check(not GearArt.find("plate_head_t3", "female").is_empty() and not GearArt.find("sword_t3", "male").is_empty(), "drawn gear is found for each body")
	check(GearArt.find("no_such_look", "male").is_empty(), "gear without art falls back to the body")
	var undrawn := []
	for key in ItemCatalog.NAMED:
		var spec: Dictionary = ItemCatalog.NAMED[key]
		if not spec["slot"] in ["accessory", "trinket"] and (GearArt.find(spec["look"], "male").is_empty() or GearArt.find(spec["look"], "female").is_empty()):
			undrawn.append(spec["look"])
	for rid in Prof.RECIPES:
		if Prof.RECIPES[rid].has("item") and int(Prof.RECIPES[rid]["item"]["rarity"]) > Items.COMMON and GearArt.find("crafted_" + rid, "male").is_empty():
			undrawn.append("crafted_" + rid)
	check(undrawn.is_empty(), "every worn item has art: %s" % str(undrawn.slice(0, 5)))
	var old := fresh(71)
	old["inventory"] = [{"id": "o1", "slot": "armor", "name": "Кираса", "rarity": 3, "ilvl": 5, "affixes": []}]
	old["v"] = 9
	Rules.migrate(old, T0)
	check(int(old["inventory"][0]["rarity"]) == Items.EPIC, "old legendaries become epic: they have no unique effect")

func test_rare_loot_and_mods() -> void:
	print("rare loot, weapon recipes, enemy modifiers")
	var sw := Prof.make_item("iron_sword", "x", 10)
	check(sw["slot"] == "weapon" and sw["wtype"] == "sword" and sw["dmg"] > 0 and sw["affixes"][0].get("imp", false), "crafted sword is a real sword")
	check(Prof.make_item("iron_shield", "y", 10)["slot"] == "offhand", "crafted shield goes to the left hand")
	var crafts := {}
	var craft_rng := RandomNumberGenerator.new()
	for i in 40:
		var made := Prof.make_item("iron_chestguard", "z", 25, craft_rng)
		check(int(made["ilvl"]) == 25, "crafted gear takes the given level")
		crafts[str(made["affixes"])] = true
	check(crafts.size() > 30, "crafted stats are random")
	for rid in Prof.RECIPES:
		var spec: Dictionary = Prof.RECIPES[rid]
		if spec.has("item"):
			var q_item := int(spec["item"]["rarity"])
			check(int(spec["req"]) >= [0, 0, 1, 5, 8][q_item] and int(spec["time"]) >= [0, 0, 60, 7200, 28800][q_item], "%s is as hard as its quality" % rid)
	var p := fresh(51)
	p["gold"] = 5000
	p["professions"]["blacksmithing"]["level"] = 10
	p["craft_prof"] = "blacksmithing"
	for r in ["silver_ore", "mithril_fragment", "boss_core"]:
		Rules._add_res(p, r, 100)
	check(Rules.can_craft(p, "core_blade")["error"] == "recipe not learned", "drop-only recipe needs to be learned")
	Rules._add_res(p, "rcp_core_blade", 1)
	check(Rules.can_craft(p, "core_blade")["ok"] and not p["resources"].has("rcp_core_blade"), "recipe drop teaches it, not stored as a resource")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var slots := {}
	for i in 3000:
		slots[Loot.roll_gear(rng, 10)["slot"]] = true
	check(slots.has("head") and slots.has("feet") and slots.has("offhand"), "combat loot can be any slot")
	var drops := {}
	var ex := Expedition.new()
	ex.record_events = false
	var party := [Roster.hero_snapshot({"name": "H", "level": 40, "rotation": ["strike"], "equipped": {}}, {})]
	ex.start(1, "farm", party, 5, false)
	ex.fast_forward(4 * 3600.0, 2400.0)
	var got_res := false
	for k in ex.mats:
		if Prof.RESOURCES.has(k) and Prof.RESOURCES[k]["cat"] in ["ore", "herb", "leather"]:
			got_res = true
	check(got_res, "farming sometimes drops gathering resources (%s)" % str(ex.mats))
	check(Db.level_modifiers(5).is_empty() and Db.level_modifiers(12).size() == 1 and Db.level_modifiers(25).size() == 2, "modifiers from level 11, two from 21")
	var lv := 11
	while not "armored" in Db.level_modifiers(lv):
		lv += 1
	var plain := Db.ENEMIES["brute"]["armor"] * Db.enemy_armor_mult(lv)
	check(absf(Expedition.enemy_snapshot("brute", lv)["stats"]["armor"] - plain * 1.35) < 0.01, "armored modifier raises armor (level %d)" % lv)

func test_talents() -> void:
	print("talents")
	var p := fresh(41)
	check(Talents.points_free(p["hero"]) == 0 and not Rules.apply(p, "talent_up", {"id": "toughness"}, T0)["ok"], "no talent points before level 5")
	p["hero"]["level"] = 7
	check(Talents.points_free(p["hero"]) == 6, "6 points at level 7 (2 per level from 5)")
	var hp0: float = Rules.hero_snapshot(p)["stats"]["hp"]
	for i in 3:
		Rules.apply(p, "talent_up", {"id": "toughness"}, T0)
	check(Rules.hero_snapshot(p)["stats"]["hp"] >= hp0 * 1.08 and Talents.points_free(p["hero"]) == 3, "3 ranks cost 3 points and give 9% health")
	check(not Rules.apply(p, "talent_up", {"id": "full_block"}, T0)["ok"], "second tier needs 10 points in branch")
	Rules.apply(p, "talent_reset", {}, T0)
	check(Talents.points_free(p["hero"]) == 6, "reset returns the points")
	check(Rules.apply(p, "talent_up", {"id": "poison_blades"}, T0)["ok"] and not Talents._active(Talents.TALENTS["poison_blades"],["bow"]), "sword talent can be learned but is inactive with a bow")
	check(Loot.sell_price({"ilvl": 10, "rarity": 1}) < (5 + 30) * 3, "selling pays less gold now")

func test_spell_levels() -> void:
	print("spell levels")
	var p := fresh(21)
	var col: Dictionary = p["collection"]
	check(col["fireball"]["lvl"] == 1 and col["fireball"]["copies"] == 0, "starter spell is level I, no spare copies")
	check(not Rules.apply(p, "fuse", {"sid": "fireball"}, T0)["ok"], "no upgrade without copies")
	var first_cost: int = Rules.fuse_cost(1)
	col["fireball"]["copies"] = first_cost-1
	check(not Rules.can_fuse(p, "fireball"), "too few copies for II")
	col["fireball"]["copies"] = first_cost
	check(Rules.apply(p, "fuse", {"sid": "fireball"}, T0)["ok"] and col["fireball"]["lvl"] == 2 and col["fireball"]["copies"] == 0, "exact copies: I -> II")
	col["fireball"]["copies"] = first_cost
	check(not Rules.can_fuse(p, "fireball"), "II -> III needs more than I -> II")
	col["fireball"]["copies"] = 1000
	var ups := 0
	while Rules.apply(p, "fuse", {"sid": "fireball"}, T0)["ok"]:
		ups += 1
	check(col["fireball"]["lvl"] == Rules.SPELL_MAX_LEVEL and ups == Rules.SPELL_MAX_LEVEL - 2, "upgrades go all the way to X")
	var spent := 0
	for c in Rules.FUSE_COST:
		spent += int(c)
	check(col["fireball"]["copies"] == 1000 + first_cost - spent, "each upgrade eats its own cost")
	check(Rules.apply(p, "fuse", {"sid": "fireball"}, T0)["error"] == "max level", "no upgrade past X")
	var snap := Rules.hero_snapshot(p)
	var lv := 0
	for sp in snap["spells"]:
		if sp["id"] == "fireball":
			lv = int(sp["lvl"])
	check(lv == Rules.SPELL_MAX_LEVEL, "hero snapshot uses the spell level")
	# v3 -> v4: copies per level become one level + spare copies (level-k copy = 5^(k-1) level-I copies)
	var old := fresh(22)
	old["collection"] = {"fireball": {"1": 3, "2": 6}, "heal": {"1": 1}, "kick": {"1": 0, "2": 0}}
	Rules.migrate(old, T0)
	var oc: Dictionary = old["collection"]
	check(oc["fireball"]["lvl"] == 2 and oc["fireball"]["copies"] == 3 + 30 - 1 - Rules.fuse_cost(1), "old II copies are refunded as spare copies (%s)" % oc["fireball"])
	check(oc["heal"]["lvl"] == 1 and oc["heal"]["copies"] == 0, "old single copy stays level I")
	check(not oc.has("kick"), "empty entries are dropped")

func test_boxes_and_validation() -> void:
	print("boxes and validation")
	var p := fresh(13)
	p["gold"] = 3000
	var copies_before := 0
	for sid in p["collection"]:
		copies_before += 1 + int(p["collection"][sid]["copies"])
	var r := Rules.apply(p, "open_pack", {"use": "gold"}, T0)
	var copies_after := 0
	for sid in p["collection"]:
		copies_after += 1 + int(p["collection"][sid]["copies"])
	check(r["ok"] and r["boxes"].size() == 10 and p["gold"] == 300 and copies_after == copies_before + 10 * Rules.BOX_COPIES, "pack of 10 for 2700 gold")
	check(not Rules.apply(p, "open_pack", {"use": "gold"}, T0)["ok"], "cannot buy without gold")
	check(Rules.apply(p, "open_box", {"use": "free"}, T0)["ok"] and not Rules.apply(p, "open_box", {"use": "free"}, T0 + 60)["ok"], "one free box per day")
	check(Rules.apply(p, "open_box", {"use": "free"}, T0 + 86400.0)["ok"], "free box again next day")
	check(not Rules.apply(p, "set_rotation", {"rotation": ["chain_lightning", "x"]}, T0)["ok"], "rotation with unknown spell rejected")
	check(not Rules.apply(p, "hire", {"id": p["board"][0]["id"]}, T0)["ok"], "hire rejected when the group is full")
	check(not Rules.apply(p, "start", {"level": 3, "mode": "farm"}, T0)["ok"], "farm on a locked level rejected")
	check(not Rules.apply(p, "grant_assists", {}, T0)["ok"], "empty grant rejected")
	var cost := Rules.reroll_cost(p, T0)
	for i in 5:
		Rules.apply(p, "reroll", {}, T0)
	check(Rules.reroll_cost(p, T0) > cost and Rules.reroll_cost(p, T0) < cost * 2 and Rules.reroll_cost(p, T0 + 86400.0) == cost, "reroll price grows a little during the day and resets next day")
	p["hero"]["level"] = 20
	check(Rules.reroll_cost(p, T0 + 86400.0) == 70, "reroll price follows the hero level (70 at level 20)")

func test_json_roundtrip() -> void:
	print("json roundtrip")
	var p := fresh(17)
	Rules.apply(p, "start", {"level": 1, "mode": "push"}, T0)
	var q = JSON.parse_string(JSON.stringify(p))
	Rules.migrate(q, T0)
	var pa := Rules.pending(p, T0 + 30.0)
	var pb := Rules.pending(q, T0 + 30.0)
	check(pa["gold"] == pb["gold"] and typeof(q["gold"]) == TYPE_INT, "profile survives JSON (ints restored)")
	var t_end: float = q["expedition"]["tl"]["t_end"]
	var oa := Rules.tick(p, T0 + t_end + 1.0)
	var ob := Rules.tick(q, T0 + t_end + 1.0)
	check(oa["reports"][0]["gold"] == ob["reports"][0]["gold"] and p["rng"]["state"] == q["rng"]["state"], "same result after the roundtrip")

func test_migrate_v1() -> void:
	print("migrate v1 save")
	var p := fresh(19)
	var old := p.duplicate(true)
	old.erase("rng")
	old.erase("reports")
	old.erase("stats")
	old["v"] = 1
	old["time"] = T0 - 3600.0
	old["expedition"] = {"level": 1, "mode": "push", "party": Rules.party_snapshots(p), "seed": 5, "first": true,
		"gold": 77, "xp": 10, "kills": 2, "items": [], "boxes": 0, "won": 0, "lost": 0, "closed_now": false}
	var json = JSON.parse_string(JSON.stringify(old))
	Rules.migrate(json, T0)
	check(json["v"] == Rules.VERSION and json["expedition"].has("tl") and json["gold"] == p["gold"] + 77, "v1 expedition becomes a timeline, old loot kept")
	check(Rules.push_finished(json, T0), "time since the old save counts (push already over)")

func test_real_players_and_assists() -> void:
	print("real players and assists")
	var owner := fresh(23)
	owner["hero"]["level"] = 3
	var snap := Rules.public_snapshot(owner, "acc_owner")
	var me := fresh(29)
	me["hero"]["level"] = 3
	var own_snap := Rules.public_snapshot(me, "acc_me")
	var ctx := {"account": "acc_me", "real_pool": [snap, own_snap]}
	me["gold"] = 1000
	Rules.apply(me, "reroll", {}, T0, ctx)
	var ids := []
	for m in me["board"]:
		ids.append(m["id"])
	check(ids.has("pacc_owner") and not ids.has("pacc_me"), "board shows the other player, never yourself")
	check(me["board"].size() == 6, "board still has 6 candidates")
	Rules.apply(me, "replace", {"old": me["hired"][2]["id"], "new": "pacc_owner"}, T0)
	check(Rules.is_hired(me, "pacc_owner"), "real player hired")
	me["closed_level"] = 1
	Rules.apply(me, "start", {"level": 1, "mode": "farm"}, T0, ctx)
	var res := Rules.apply(me, "collect", {}, T0 + 900.0, ctx)
	var a: Array = res["assists"]
	check(a.size() == 1 and a[0]["owner"] == "acc_owner" and a[0]["gold"] == max(1, int(res["report"]["gold"] * 0.05)), "owner gets 5%% of the gold (%s)" % str(a))
	var g0: int = owner["gold"]
	Rules.apply(owner, "grant_assists", {"gold": 12, "hires": 3}, T0)
	check(owner["gold"] == g0 + 12 and owner["stats"]["hired_total"] == 3 and owner["reports"].size() == 1, "assist grant adds gold, counter and a report")

func test_gathering() -> void:
	print("gathering")
	var p := fresh(31)
	check(not Rules.apply(p, "gather_start", {"prof": "mining", "loc": "iron_hills", "sec": 900}, T0)["ok"], "location above profession level rejected")
	check(not Rules.apply(p, "gather_start", {"prof": "mining", "loc": "abandoned_quarry", "sec": 123}, T0)["ok"], "unknown duration rejected")
	check(Rules.apply(p, "gather_start", {"prof": "mining", "loc": "abandoned_quarry", "sec": 3600}, T0)["ok"], "mining started (1 h)")
	check(not Rules.apply(p, "gather_start", {"prof": "herbalism", "loc": "green_meadow", "sec": 900}, T0)["ok"], "only one gathering at a time")
	check(not Rules.apply(p, "gather_claim", {}, T0 + 3599.0)["ok"], "cannot claim before the timer ends")
	var r := Rules.apply(p, "gather_claim", {}, T0 + 3600.0)
	var got: Dictionary = r["report"]["res"] if r["ok"] else {}
	check(r["ok"] and got.get("copper_ore", 0) > 0 and got.get("iron_ore", 0) > 0, "claim gives ore %s" % str(got))
	check(Rules.res_count(p, "iron_ore") == got.get("iron_ore", -1), "ore stored in the materials inventory")
	check(int(p["professions"]["mining"]["xp"]) == Prof.gather_xp("abandoned_quarry", 3600), "gathering gives profession XP")
	Rules._add_prof_xp(p, "mining", Prof.xp_to_next(1) - int(p["professions"]["mining"]["xp"]))
	check(int(p["professions"]["mining"]["level"]) == 2 and int(p["professions"]["mining"]["xp"]) == 0, "enough XP -> level 2")
	var again := Rules.apply(p, "gather_claim", {}, T0 + 3700.0)
	check(not again["ok"] and Rules.res_count(p, "iron_ore") == got["iron_ore"], "second claim gives nothing")
	Rules.apply(p, "gather_start", {"prof": "skinning", "loc": "wild_plains", "sec": 28800}, T0)
	Rules.apply(p, "gather_claim", {}, T0 + 28800.0)
	check(int(p["professions"]["skinning"]["level"]) >= 3, "8 h of skinning levels the profession (level %d)" % p["professions"]["skinning"]["level"])
	check(Rules.apply(p, "gather_start", {"prof": "skinning", "loc": "wolf_woods", "sec": 900}, T0)["ok"], "higher location unlocked by level")

func give(p: Dictionary, res: Dictionary) -> void:
	for k in res:
		Rules._add_res(p, k, res[k])

func test_crafting_and_concurrency() -> void:
	print("crafting and concurrency")
	var p := fresh(37)
	give(p, {"iron_ore": 10, "raw_leather": 2})
	check(Rules.can_craft(p, "simple_iron_helmet")["error"] == "not your craft", "no crafting before a profession is chosen")
	check(not Rules.apply(p, "prof_choose", {"prof": "mining"}, T0)["ok"], "gathering is not a crafting choice")
	check(Rules.apply(p, "prof_choose", {"prof": "blacksmithing"}, T0)["ok"], "first choice is free")
	p["resources"].clear()
	check(not Rules.apply(p, "craft_start", {"recipe": "simple_iron_helmet"}, T0)["ok"], "craft without materials rejected")
	give(p, {"iron_ore": 10, "raw_leather": 2})
	var gold0: int = p["gold"]
	check(Rules.apply(p, "craft_start", {"recipe": "simple_iron_helmet"}, T0)["ok"], "helmet craft started")
	check(Rules.res_count(p, "iron_ore") == 0 and p["gold"] == gold0 - 60, "materials and gold taken at start")
	check(not Rules.apply(p, "craft_start", {"recipe": "simple_iron_helmet"}, T0)["ok"], "one craft at a time")
	give(p, {"rough_cloth": 10, "greenleaf": 4, "bitterroot": 2})
	p["gold"] = Prof.CRAFT_CHANGE_GOLD
	check(Rules.can_craft(p, "rough_cloth_hood")["error"] == "not your craft", "other crafting professions stay closed")
	check(Rules.apply(p, "prof_choose", {"prof": "tailoring"}, T0)["error"] == "already crafting", "cannot change a craft mid-job")
	check(Rules.apply(p, "gather_start", {"prof": "herbalism", "loc": "green_meadow", "sec": 900}, T0)["ok"], "gathering runs alongside crafting")
	p["closed_level"] = 1
	check(Rules.apply(p, "start", {"level": 1, "mode": "farm"}, T0)["ok"], "combat farm runs alongside both")
	check(not Rules.apply(p, "craft_claim", {"prof": "blacksmithing"}, T0 + 299.0)["ok"], "craft cannot finish early")
	var r := Rules.apply(p, "craft_claim", {"prof": "blacksmithing"}, T0 + 300.0)
	var it: Dictionary = r["report"]["items"][0] if r["ok"] else {}
	check(it.get("slot", "") == "head" and it.get("crafted", false) and int(it.get("ilvl", 0)) == 1, "helmet in the bag: %s" % str(it.get("name", "")))
	check(not Rules.apply(p, "craft_claim", {"prof": "blacksmithing"}, T0 + 400.0)["ok"], "craft claimed only once")
	check(int(p["professions"]["blacksmithing"]["xp"]) == int(Prof.RECIPES["simple_iron_helmet"]["xp"]), "blacksmithing XP awarded")
	check(Rules.apply(p, "prof_choose", {"prof": "alchemy"}, T0)["ok"] and int(p["gold"]) == 0, "changing the craft costs gold")
	check(Rules.apply(p, "prof_choose", {"prof": "tailoring"}, T0)["error"] == "not enough gold", "no second change without gold")
	check(int(p["professions"]["blacksmithing"]["xp"]) > 0, "levels of the old craft are kept")
	p["gold"] = 1000
	check(Rules.apply(p, "craft_start", {"recipe": "minor_strength_potion"}, T0)["ok"], "the new craft works")
	var pr := Rules.apply(p, "craft_claim", {"prof": "alchemy"}, T0 + 180.0)
	check(pr["ok"] and Rules.res_count(p, "minor_strength_potion") == 2, "potions crafted (2)")
	check(Rules.apply(p, "equip", {"id": it["id"]}, T0)["ok"] and p["hero"]["equipped"]["head"] != null, "crafted helmet equipped in the new head slot")
	var stats: Dictionary = Rules.hero_snapshot(p)["stats"]
	check(stats["armor"] > Db.hero_base_stats(1)["armor"], "helmet adds armor")
	p["craft_prof"] = "blacksmithing"
	var boss := Rules.can_craft(p, "boss_forged_chestguard")
	check(not boss["ok"], "rare recipe locked behind level and boss core")
	check(Prof.drop_recipes("blacksmithing").all(func(id): return Prof.RECIPES[id]["prof"] == "blacksmithing"), "a hero finds only recipes of his craft")
	check(Prof.drop_recipes("alchemy").size() > 0 and Prof.drop_recipes("tailoring").size() > 0, "every craft has rare recipes")
	for id in Prof.RECIPES:
		for res in Prof.RECIPES[id]["ingredients"]:
			check(Prof.RESOURCES.has(res), "%s uses a known resource" % id)
		for res in Prof.RECIPES[id].get("output", {}):
			check(Prof.CONSUMABLES.has(res), "%s makes a consumable" % id)
	check(FileAccess.file_exists("res://assets/icons/res_titan_flask.png"), "new potions have icons")

func test_consumables() -> void:
	print("consumables")
	var p := fresh(41)
	give(p, {"minor_strength_potion": 1, "gatherers_tonic": 1})
	check(Rules.apply(p, "use_item", {"res": "minor_strength_potion"}, T0)["ok"], "strength potion used")
	check(Rules.res_count(p, "minor_strength_potion") == 0 and not Rules.apply(p, "use_item", {"res": "minor_strength_potion"}, T0)["ok"], "potion consumed")
	Rules.apply(p, "start", {"level": 1, "mode": "push"}, T0 + 60.0)
	check(is_equal_approx(float(p["expedition"]["party"][0]["stats"].get("dmg_mult", 1.0)), 1.1), "expedition started under the buff gets +10% damage")
	Rules.apply(p, "stop", {}, T0 + 61.0)
	Rules.apply(p, "start", {"level": 1, "mode": "push"}, T0 + 7300.0)
	check(not p["expedition"]["party"][0]["stats"].has("dmg_mult"), "buff expires after 2 h")
	var one := fresh(44)
	one["resources"] = {"minor_strength_potion": 1, "elixir_bull": 1}
	var str0: float = Rules.hero_snapshot(one)["stats"]["str"]
	Rules.apply(one, "use_item", {"res": "minor_strength_potion"}, T0)
	Rules.apply(one, "use_item", {"res": "elixir_bull"}, T0)
	check(Rules.active_buffs(one, T0).size() == 1 and one["buffs"]["potion"]["res"] == "elixir_bull", "only one potion works: the new one replaces it")
	one["closed_level"] = 1
	Rules.apply(one, "start", {"level": 1, "mode": "farm"}, T0)
	var ids: Array = one["party_order"]
	var hero_stats: Dictionary = one["expedition"]["party"][ids.find("hero")]["stats"]
	check(is_equal_approx(float(hero_stats["str"]), str0 * 1.1) and not hero_stats.has("dmg_mult"), "a personal potion raises the stat of the hero only")
	Rules.apply(p, "use_item", {"res": "gatherers_tonic"}, T0)
	Rules.apply(p, "gather_start", {"prof": "mining", "loc": "abandoned_quarry", "sec": 900}, T0)
	check(p["gathering"]["tonic"] and not Rules.active_buffs(p, T0).has("gather_yield"), "tonic applies to the next gathering and is used up")

func test_combat_materials() -> void:
	print("combat materials")
	var p := fresh(43)
	for i in 20:   # a starting party can lose level 1: find one that clears it
		p = fresh(43 + i)
		Rules.apply(p, "start", {"level": 1, "mode": "push"}, T0)
		if p["expedition"]["tl"]["won"]:
			break
	var t_end: float = p["expedition"]["tl"]["t_end"]
	var out := Rules.tick(p, T0 + t_end + 1.0)
	var mats: Dictionary = out["reports"][0].get("mats", {})
	check(p["closed_level"] == 1 and mats.get("boss_core", 0) == 1, "first clear: the boss drops a Boss Core %s" % str(mats))
	check(mats.get("rough_cloth", 0) > 0, "combat drops cloth")
	Rules.apply(p, "start", {"level": 1, "mode": "farm"}, T0 + 100.0)
	var r := Rules.apply(p, "collect", {}, T0 + 100.0 + 3600.0)
	var cloth: int = r["report"]["mats"].get("rough_cloth", 0)
	check(cloth >= 15 and cloth <= 60, "1 h of farming gives a sensible amount of cloth (%d)" % cloth)
	var r2 := Rules.apply(p, "collect", {}, T0 + 100.0 + 3600.0)
	check(r2["report"]["mats"].is_empty(), "materials collected once")
	var tbl: Dictionary = Prof.cloth_table(20)
	check(tbl.has("fine_cloth") and not tbl.has("rough_cloth"), "late levels drop linen and fine cloth")
	for res in Prof.LOCATIONS:
		for y in Prof.LOCATIONS[res]["yields"].keys() + Prof.LOCATIONS[res]["rare"].keys():
			if Prof.RESOURCES[y]["cat"] in ["cloth", "special"]:
				check(false, "gathering must not give %s" % y)

func test_v2_migration() -> void:
	print("v2 -> v3 migration")
	var p := fresh(47)
	for k in ["resources", "professions", "gathering", "crafting", "buffs"]:
		p.erase(k)
	p["hero"]["equipped"] = {"weapon": null, "armor": null, "trinket": null}
	p["v"] = 2
	var q = JSON.parse_string(JSON.stringify(p))
	Rules.migrate(q, T0)
	check(q["v"] == Rules.VERSION and q["professions"].size() == 6 and q["hero"]["equipped"].has("feet"), "old profile gets professions and new slots")
	check(q["craft_prof"] == "", "old profile chooses its craft freely")
	check(Rules.apply(q, "gather_start", {"prof": "herbalism", "loc": "green_meadow", "sec": 900}, T0)["ok"], "migrated profile can gather")
