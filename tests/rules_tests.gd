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
	test_boxes_and_validation()
	test_json_roundtrip()
	test_migrate_v1()
	test_real_players_and_assists()
	test_gathering()
	test_crafting_and_concurrency()
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
	return Loot.roll_gear(rng, 10, 0.0, "", wtype)

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
	check(b_hi["atk"] > b_lo["atk"] and s_hi["atk"] > s_lo["atk"], "bow scales with agility, staff with spell power")
	# weapon spells: requirement and bonus
	check(not Db.spell_usable("aimed_shot", ["sword"]) and Db.spell_usable("aimed_shot", ["bow"]), "aimed shot needs a bow")
	check(Db.spell_bonus("fireball", ["staff"]) > 1.0 and Db.spell_bonus("fireball", ["sword"]) == 1.0, "fireball is stronger with a staff")
	check(Db.spell_bonus("twin_strike", ["sword", "sword"]) > Db.spell_bonus("twin_strike", ["sword", "shield"]), "twin strike bonus with two swords")
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
	check(sim._find_spell_target(u2, "aimed_shot") != null and u2.atk_speed == 2.0, "with a bow it is used; the bow shoots every 2.0 s")
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
	check(w["wtype"] == "staff" and w["dmg"] > 0 and w["affixes"][0]["stat"] == "str", "old 'Посох' became a staff, attack became strength")
	check(q["inventory"][0]["affixes"][0]["stat"] == "str" and q["hero"]["equipped"].has("offhand"), "old items lose the attack stat; left hand slot added")
	var qs := Rules.hero_snapshot(q)
	check(qs["weapons"] == ["staff"] and qs["stats"]["atk"] > 0, "migrated hero has a working attack")

func test_spell_levels() -> void:
	print("spell levels")
	var p := fresh(21)
	var col: Dictionary = p["collection"]
	check(col["fireball"]["lvl"] == 1 and col["fireball"]["copies"] == 0, "starter spell is level I, no spare copies")
	check(not Rules.apply(p, "fuse", {"sid": "fireball"}, T0)["ok"], "no upgrade without copies")
	col["fireball"]["copies"] = 3
	check(not Rules.can_fuse(p, "fireball"), "3 copies are not enough for II")
	col["fireball"]["copies"] = 4
	check(Rules.apply(p, "fuse", {"sid": "fireball"}, T0)["ok"] and col["fireball"]["lvl"] == 2 and col["fireball"]["copies"] == 0, "4 copies: I -> II")
	col["fireball"]["copies"] = 4
	check(not Rules.can_fuse(p, "fireball"), "II -> III needs more than I -> II")
	col["fireball"]["copies"] = 1000
	var ups := 0
	while Rules.apply(p, "fuse", {"sid": "fireball"}, T0)["ok"]:
		ups += 1
	check(col["fireball"]["lvl"] == Rules.SPELL_MAX_LEVEL and ups == Rules.SPELL_MAX_LEVEL - 2, "upgrades go all the way to X")
	var spent := 0
	for c in Rules.FUSE_COST:
		spent += int(c)
	check(col["fireball"]["copies"] == 1000 + 4 - spent, "each upgrade eats its own cost")
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
	check(oc["fireball"]["lvl"] == 2 and oc["fireball"]["copies"] == 3 + 30 - 1 - 4, "old II copies are refunded as spare copies (%s)" % oc["fireball"])
	check(oc["heal"]["lvl"] == 1 and oc["heal"]["copies"] == 0, "old single copy stays level I")
	check(not oc.has("kick"), "empty entries are dropped")

func test_boxes_and_validation() -> void:
	print("boxes and validation")
	var p := fresh(13)
	p["gold"] = 2000
	var copies_before := 0
	for sid in p["collection"]:
		copies_before += 1 + int(p["collection"][sid]["copies"])
	var r := Rules.apply(p, "open_pack", {"use": "gold"}, T0)
	var copies_after := 0
	for sid in p["collection"]:
		copies_after += 1 + int(p["collection"][sid]["copies"])
	check(r["ok"] and r["boxes"].size() == 10 and p["gold"] == 650 and copies_after == copies_before + 10, "pack of 10 for 1350 gold")
	check(not Rules.apply(p, "open_pack", {"use": "gold"}, T0)["ok"], "cannot buy without gold")
	check(Rules.apply(p, "open_box", {"use": "free"}, T0)["ok"] and not Rules.apply(p, "open_box", {"use": "free"}, T0 + 60)["ok"], "one free box per day")
	check(Rules.apply(p, "open_box", {"use": "free"}, T0 + 86400.0)["ok"], "free box again next day")
	check(not Rules.apply(p, "set_rotation", {"rotation": ["chain_lightning", "x"]}, T0)["ok"], "rotation with unknown spell rejected")
	check(not Rules.apply(p, "hire", {"id": p["board"][0]["id"]}, T0)["ok"], "hire rejected when the group is full")
	check(not Rules.apply(p, "start", {"level": 3, "mode": "farm"}, T0)["ok"], "farm on a locked level rejected")
	check(not Rules.apply(p, "grant_assists", {}, T0)["ok"], "empty grant rejected")
	var cost := Rules.reroll_cost(p, T0)
	Rules.apply(p, "reroll", {}, T0)
	check(Rules.reroll_cost(p, T0) > cost and Rules.reroll_cost(p, T0 + 86400.0) == cost, "reroll price grows during the day and resets next day")

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
	check(int(p["professions"]["mining"]["level"]) == 2 and int(p["professions"]["mining"]["xp"]) == 0, "100 mining XP -> level 2")
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
	check(not Rules.apply(p, "craft_start", {"recipe": "simple_iron_helmet"}, T0)["ok"], "craft without materials rejected")
	give(p, {"iron_ore": 10, "raw_leather": 2})
	var gold0: int = p["gold"]
	check(Rules.apply(p, "craft_start", {"recipe": "simple_iron_helmet"}, T0)["ok"], "helmet craft started")
	check(Rules.res_count(p, "iron_ore") == 0 and p["gold"] == gold0 - 60, "materials and gold taken at start")
	check(not Rules.apply(p, "craft_start", {"recipe": "simple_iron_helmet"}, T0)["ok"], "one craft per profession")
	give(p, {"rough_cloth": 10, "greenleaf": 4, "bitterroot": 2})
	p["gold"] = 1000
	check(Rules.apply(p, "craft_start", {"recipe": "rough_cloth_hood"}, T0)["ok"]
		and Rules.apply(p, "craft_start", {"recipe": "minor_strength_potion"}, T0)["ok"], "three professions craft at the same time")
	check(Rules.apply(p, "gather_start", {"prof": "herbalism", "loc": "green_meadow", "sec": 900}, T0)["ok"], "gathering runs alongside crafting")
	p["closed_level"] = 1
	check(Rules.apply(p, "start", {"level": 1, "mode": "farm"}, T0)["ok"], "combat farm runs alongside both")
	check(not Rules.apply(p, "craft_claim", {"prof": "blacksmithing"}, T0 + 299.0)["ok"], "craft cannot finish early")
	var r := Rules.apply(p, "craft_claim", {"prof": "blacksmithing"}, T0 + 300.0)
	var it: Dictionary = r["report"]["items"][0] if r["ok"] else {}
	check(it.get("slot", "") == "head" and it.get("crafted", false) and it["affixes"].size() == 2, "helmet in the bag: %s" % str(it.get("name", "")))
	check(not Rules.apply(p, "craft_claim", {"prof": "blacksmithing"}, T0 + 400.0)["ok"], "craft claimed only once")
	check(int(p["professions"]["blacksmithing"]["xp"]) == 40, "blacksmithing XP awarded")
	var pr := Rules.apply(p, "craft_claim", {"prof": "alchemy"}, T0 + 180.0)
	check(pr["ok"] and Rules.res_count(p, "minor_strength_potion") == 2, "potions crafted (2)")
	check(Rules.apply(p, "equip", {"id": it["id"]}, T0)["ok"] and p["hero"]["equipped"]["head"] != null, "crafted helmet equipped in the new head slot")
	var stats: Dictionary = Rules.hero_snapshot(p)["stats"]
	check(stats["armor"] > Db.hero_base_stats(1)["armor"], "helmet adds armor")
	var boss := Rules.can_craft(p, "boss_forged_chestguard")
	check(not boss["ok"], "rare recipe locked behind level and boss core")

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
	Rules.apply(p, "use_item", {"res": "gatherers_tonic"}, T0)
	Rules.apply(p, "gather_start", {"prof": "mining", "loc": "abandoned_quarry", "sec": 900}, T0)
	check(p["gathering"]["tonic"] and not Rules.active_buffs(p, T0).has("gather_yield"), "tonic applies to the next gathering and is used up")

func test_combat_materials() -> void:
	print("combat materials")
	var p := fresh(43)
	Rules.apply(p, "start", {"level": 1, "mode": "push"}, T0)
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
	check(Rules.apply(q, "gather_start", {"prof": "herbalism", "loc": "green_meadow", "sec": 900}, T0)["ok"], "migrated profile can gather")
