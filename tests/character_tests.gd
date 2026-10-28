extends SceneTree
var failures := 0
var assertions := 0

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		print("FAIL ", message)

func _initialize() -> void:
	_run.call_deferred()

func shot(name: String) -> void:
	await create_timer(.25).timeout
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://build/qa/characters")
		root.get_texture().get_image().save_png("res://build/qa/characters/" + name + ".png")

func _run() -> void:
	root.size = Vector2i(1280,720)
	var p := Rules.new_profile(42,100.)
	check(p["hero"]["appearance"] == {"sex":"male","hair":"m01"}, "New profile appearance")
	p["hero"].erase("appearance")
	Rules.migrate(p,100.)
	check(CharacterAppearance.valid(p["hero"]["appearance"]["sex"], p["hero"]["appearance"]["hair"]), "Old save migration")
	var stats: Dictionary = Rules.hero_snapshot(p)["stats"].duplicate(true)
	var rng: Dictionary = p["rng"].duplicate(true)
	for sex in ["male","female"]:
		for hair in CharacterAppearance.hair_ids(sex):
			check(Rules.apply(p,"set_appearance",{"sex":sex,"hair":hair},100.)["ok"], "Available style " + hair)
			check(Rules.hero_snapshot(p)["appearance"]["hair"] == hair, "Appearance propagated to hero snapshot")
	check(p["rng"] == rng, "Appearance never consumes gameplay RNG")
	check(Rules.hero_snapshot(p)["stats"] == stats, "Appearance never changes combat stats")
	check(Rules.public_snapshot(p,"owner")["appearance"]["hair"] == "f05", "Public snapshot carries appearance")
	var before: Dictionary = p["hero"]["appearance"].duplicate()
	for invalid in [{"sex":"female","hair":"m01"}, {"sex":"invalid","hair":"f01"}, {"sex":"male","hair":"../../file"}, {}]:
		check(not Rules.apply(p,"set_appearance",invalid,100.)["ok"], "Invalid appearance rejected")
	check(p["hero"]["appearance"] == before, "Rejected edits leave appearance intact")
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(p))
	Rules.migrate(loaded,100.)
	check(loaded["hero"]["appearance"] == before, "Appearance survives save/load")
	var actor := CharacterActor.new()
	root.add_child(actor)
	for sex in ["male","female"]:
		for hair in CharacterAppearance.hair_ids(sex):
			actor.configure({"sex":sex,"hair":hair})
			check(actor.hair_front.texture != null and actor.hair_back.texture != null, "Hair layers load " + hair)
		for clip in CharacterActor.COUNTS:
			actor.play(clip)
			actor.elapsed = .4
			actor._update_frame()
			check(actor.body.texture != null and actor.body.material.get_shader_parameter("skin_mask") != null, "Body and skin mask load " + sex + "/" + clip)
			check(actor.body.frame < actor.body.hframes * actor.body.vframes, "Frame inside atlas")
	actor.queue_free()
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var game = root.get_node("Game")
	game.set_appearance("male","m01")
	main._switch("hero")
	await shot("01_hero_male")
	main._appearance_popup()
	await process_frame
	var dim = main.popup_layer.get_child(0)
	var panel = dim.get_child(0).get_child(0).get_child(0).get_child(1)
	panel._select_sex(1)
	panel._select_hair(4)
	check(game.hero["appearance"]["sex"] == "male", "Preview does not mutate profile")
	check(panel.value == {"sex":"female","hair":"f05"}, "Editor switches sex and hairstyle")
	await shot("02_appearance_preview")
	main._modal_action(dim, main._apply_appearance.bind(panel))
	await process_frame
	await process_frame
	check(game.hero_snapshot()["appearance"] == {"sex":"female","hair":"f05"}, "Editor saves appearance")
	check(main.popup_layer.get_child_count() == 0, "Save closes editor")
	await shot("03_hero_female")
	main._appearance_popup()
	await process_frame
	dim = main.popup_layer.get_child(0)
	panel = dim.get_child(0).get_child(0).get_child(0).get_child(1)
	panel._select_sex(0)
	dim.queue_free()
	await process_frame
	check(game.hero["appearance"]["sex"] == "female", "Cancel leaves saved appearance intact")
	game.act("start", {"level":1,"mode":"push"})
	var sim_before = game.expedition.sim
	game.set_appearance("male","m04")
	check(game.expedition.sim == sim_before, "Appearance does not restart combat")
	var local_slot: int = game.party_order.find("hero")
	check(game.expedition.allies[local_slot].appearance["hair"] == "m04", "Live battle receives new appearance")
	check(game.profile["expedition"]["party"][local_slot]["appearance"]["hair"] == "m04", "Expedition save receives new appearance")
	main._dummy_popup()
	await create_timer(.7).timeout
	await shot("04_training")
	main.queue_free()
	await process_frame
	print("CHARACTERS: %d assertions, %d failures" % [assertions,failures])
	quit(1 if failures else 0)
