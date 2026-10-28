extends SceneTree
var failures := 0
var assertions := 0

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		print("FAIL ",message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280,720)
	var view = load("res://scripts/ui/battle_view.gd").new()
	view.size = Vector2(1280,720)
	root.add_child(view)
	view.set_process(false)
	var allies := []
	for i in 4:
		allies.append(BattleUnit.new(i,0,i,{"name":"Test","sprite":"hero","stats":{"hp":1000.,"atk":10.,"power":100.},"weapons":[["staff"],["bow"],["sword"],["sword","shield"]][i]}))
	var sim := BattleSim.new()
	sim.setup(allies,[{"name":"Dummy","stats":{"hp":1.e9,"atk":0.,"power":0.}}],7)
	view.training_sim = sim
	view._sync_characters(sim.units)
	for i in [0,1]:
		view._melee_motion(allies[i])
		check(view._anim(i)["lunge"] == 0., "Staff/bow never start melee lunge")
		check(view._lunge_offset(allies[i],.2) == Vector2.ZERO, "Legacy melee effects cannot move staff/bow forward")
	check(view.characters[0]["actor"].clip == "cast", "Staff uses spell motion")
	view._melee_motion(allies[2])
	check(view.characters[2]["actor"].clip == "attack", "Sword uses full wind-up, strike and recovery")
	check(view._lunge_offset(allies[2],.26).x > 40., "Sword retains lunge")
	view._melee_motion(allies[3],true)
	check(view.characters[3]["actor"].clip == "shield_bash", "Shield hit has its own animation")
	var shield_offset: Vector2 = view._lunge_offset(allies[3],.2)
	check(shield_offset.x > 0. and shield_offset.x < 20. and shield_offset.y < 0., "Shield bash is a short forward/upward movement")
	view._shoot(allies[1],sim.units[4],Color.WHITE,"arrow")
	check(view.characters[1]["actor"].clip == "shoot", "Arrow plays bow draw and release")
	check(view.projectiles[-1]["t"] == -.22, "Projectile waits for string release")
	for target in [Vector2(304,216),Vector2(281,234),Vector2(250,169),Vector2(305,222),Vector2(232,174),Vector2(160,263),Vector2(175,180),Vector2(240,220),Vector2(212,145)]:
		for shoulder in [Vector2(169,195),Vector2(237,195)]:
			var solved := WeaponMotion.solve_arm(shoulder,target)
			check(solved["elbow"].y >= (shoulder.y+solved["hand"].y)*.5-.01,"Elbow chooses the lower anatomical bend")
	var before_pole := WeaponMotion.solve_arm(Vector2(169,195),Vector2(168,215))
	var after_pole := WeaponMotion.solve_arm(Vector2(169,195),Vector2(170,215))
	check(before_pole["elbow"].distance_to(after_pole["elbow"]) < 12.,"Elbow does not pop across the shoulder when the wrist crosses vertically")
	for u in allies:
		u.casting = {"spell":"fireball","remaining":1.,"total":1.5,"target":sim.units[4],"lvl":1}
	view._sync_characters(sim.units)
	for u in allies:
		var actor: CharacterActor = view.characters[u.uid]["actor"]
		check(actor.clip == "cast" and actor.magic_color == Color(Db.SPELLS["fireball"]["color"]),"All weapons prepare magic with the spell color")
		actor.elapsed = .7
	view._sync_characters(sim.units)
	check(view.characters[0]["actor"].clip == "cast_hold","Long casts hold the raised hand")
	view._on_spell(sim,{"uid":0,"sid":"heal","text":"Heal"})
	check(view.characters[0]["actor"].clip == "cast_release" and view.characters[0]["actor"].magic_color == Color(Db.SPELLS["heal"]["color"]),"Release gesture uses the actual spell color")
	view.queue_free()
	await process_frame
	sim.release()
	for sex in ["male","female"]:
		var gallery := UI.card(Style.CARD,8)
		gallery.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(gallery)
		var grid := UI.grid(5,4)
		gallery.add_child(grid)
		for row in 3:
			for phase in [0.,.2,.5,.72,.95]:
				var cell := UI.vbox(0)
				cell.custom_minimum_size = Vector2(245,225)
				grid.add_child(cell)
				var canvas := Control.new()
				canvas.custom_minimum_size = Vector2(245,203)
				cell.add_child(canvas)
				var actor := CharacterActor.new()
				canvas.add_child(actor)
				actor.configure({"sex":sex},[],[["sword"],["bow"],["sword","shield"]][row])
				actor.position = Vector2(130,200)
				actor.scale = Vector2.ONE * .54
				actor.set_process(false)
				if phase > 0.:
					actor.play(["attack","shoot","shield_bash"][row])
					actor.elapsed = phase * actor.DURATIONS[actor.clip]
					actor._apply_pose()
				check(actor.motion.preset == actor.preset, "Weapon motion matches equipment")
				check(actor.pose.scale == Vector2.ONE and actor.body.scale == Vector2.ONE, "Torso retains V2 proportions")
				cell.add_child(UI.label(["Меч","Лук","Щит"][row]+" · "+str(phase),16))
		await create_timer(.2).timeout
		if DisplayServer.get_name() != "headless":
			DirAccess.make_dir_recursive_absolute("res://build/qa/weapon-motion")
			root.get_texture().get_image().save_png("res://build/qa/weapon-motion/"+sex+".png")
		gallery.queue_free()
		await process_frame
	if ("--motion-preview" in OS.get_cmdline_user_args() or "--magic-preview" in OS.get_cmdline_user_args()) and DisplayServer.get_name() != "headless":
		await _record_preview()
	print("WEAPON MOTION: %d assertions, %d failures" % [assertions,failures])
	quit(1 if failures else 0)

func _record_preview() -> void:
	var magic_preview := "--magic-preview" in OS.get_cmdline_user_args()
	var gallery := UI.card(Style.CARD,12)
	gallery.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(gallery)
	var grid := UI.grid(3,8)
	gallery.add_child(grid)
	var actors := []
	for sex in ["male","female"]:
		for i in 3:
			var cell := UI.vbox()
			grid.add_child(cell)
			var canvas := Control.new()
			canvas.custom_minimum_size = Vector2(405,290)
			cell.add_child(canvas)
			var actor := CharacterActor.new()
			canvas.add_child(actor)
			actor.configure({"sex":sex},[],([["staff"],["sword","shield"],["greatsword"]] if magic_preview else [["sword"],["bow"],["sword","shield"]])[i])
			actor.position = Vector2(210,285)
			actor.scale = Vector2.ONE * .75
			actor.set_process(false)
			actor.magic_color = Color(["#ff8a2a","#83efa0","#b68aff"][i])
			actors.append({"actor":actor,"clip":["attack","shoot","shield_bash"][i]})
			cell.add_child(UI.label((["Посох · правая рука","Щит остаётся в левой","Двуручник · отпускает правую"] if magic_preview else ["Меч · замах и удар","Лук · натяжение и выстрел","Щит · вперёд и вверх"])[i],22))
	var directory := "res://build/qa/weapon-motion/" + ("magic-frames" if magic_preview else "frames")
	DirAccess.make_dir_recursive_absolute(directory)
	for frame in 90:
		var time := fmod(frame/30.,1.5)-.3
		for item in actors:
			var actor: CharacterActor = item["actor"]
			var action: String = item["clip"]
			actor.clip = action if time >= 0. and time < actor.DURATIONS[action] else "idle"
			actor.elapsed = maxf(0.,time)
			if magic_preview:
				var t := fmod(frame/30.,1.5)
				if t < .65:
					actor.clip = "cast"
					actor.elapsed = t
				elif t < .9:
					actor.clip = "cast_hold"
					actor.elapsed = t-.65
				elif t < 1.3:
					actor.clip = "cast_release"
					actor.elapsed = .12+(t-.9)*.7
				else:
					actor.clip = "idle"
					actor.elapsed = t-1.3
			actor._apply_pose()
			var phase := clampf(time / actor.DURATIONS[action],0.,1.)
			actor.position = Vector2(210,285)
			if actor.clip == "attack":
				actor.position.x += sin(phase*PI)*40.
			elif actor.clip == "shield_bash":
				actor.position += Vector2(14,-5)*sin(phase*PI)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/%03d.png" % frame)
	gallery.queue_free()
	await process_frame
