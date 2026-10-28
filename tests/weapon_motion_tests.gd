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
	if "--motion-preview" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _record_preview()
	print("WEAPON MOTION: %d assertions, %d failures" % [assertions,failures])
	quit(1 if failures else 0)

func _record_preview() -> void:
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
			actor.configure({"sex":sex},[],[["sword"],["bow"],["sword","shield"]][i])
			actor.position = Vector2(210,285)
			actor.scale = Vector2.ONE * .75
			actor.set_process(false)
			actors.append({"actor":actor,"clip":["attack","shoot","shield_bash"][i]})
			cell.add_child(UI.label(["Меч · замах и удар","Лук · натяжение и выстрел","Щит · вперёд и вверх"][i],22))
	var directory := "res://build/qa/weapon-motion/frames"
	DirAccess.make_dir_recursive_absolute(directory)
	for frame in 90:
		var time := fmod(frame/30.,1.5)-.3
		for item in actors:
			var actor: CharacterActor = item["actor"]
			var action: String = item["clip"]
			actor.clip = action if time >= 0. and time < actor.DURATIONS[action] else "idle"
			actor.elapsed = maxf(0.,time)
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
