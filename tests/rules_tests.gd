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

func test_boxes_and_validation() -> void:
	print("boxes and validation")
	var p := fresh(13)
	p["gold"] = 2000
	var copies_before := 0
	for sid in p["collection"]:
		copies_before += int(p["collection"][sid].get("1", 0))
	var r := Rules.apply(p, "open_pack", {"use": "gold"}, T0)
	var copies_after := 0
	for sid in p["collection"]:
		copies_after += int(p["collection"][sid].get("1", 0))
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
	check(q["v"] == 3 and q["professions"].size() == 6 and q["hero"]["equipped"].has("feet"), "old profile gets professions and new slots")
	check(Rules.apply(q, "gather_start", {"prof": "herbalism", "loc": "green_meadow", "sec": 900}, T0)["ok"], "migrated profile can gather")
