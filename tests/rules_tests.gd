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
