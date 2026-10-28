extends SceneTree
## Record the real simulator + BattleView, never a replacement animation renderer.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit()
		return
	root.size = Vector2i(1280,720)
	var view = load("res://scripts/ui/battle_view.gd").new()
	view.size = Vector2(1280,720)
	view.theme = Style.make_theme()
	root.add_child(view)
	view.set_process(false)
	var allies := []
	for i in 4:
		var stats := Db.hero_base_stats(15)
		stats["hp"] = 20000.
		stats["power"] = 100.
		stats["str"] = 100.
		stats["agi"] = 100.
		stats["atk"] = 40. if i != 3 else 0.
		stats["atk_speed"] = [3.,1.3,2.8,1.6][i]
		allies.append(BattleUnit.new(i,0,i,{"name":["Герой","Ира","Рада","Маг"][i],"sprite":"hero","stats":stats,"weapons":[["greatsword"],["sword","shield"],["bow"],["staff"]][i],"ranged":i in [2,3],"appearance":{"sex":"female" if i in [1,2] else "male"},"spells":[{"id":["fireball","shield_slam","aimed_shot","fireball"][i],"lvl":1}]}))
	var sim := BattleSim.new()
	sim.setup(allies,[{"name":"Манекен","sprite":"training_dummy","stats":{"hp":1.e9,"atk":0.,"power":0.}},{"name":"Заклинатель","sprite":"caster","stats":{"hp":1.e9,"atk":0.,"power":50.},"spells":[{"id":"e_bolt","lvl":1}]}],7)
	view.training_sim = sim
	var directory := "res://build/qa/v3/battle-frames"
	DirAccess.make_dir_recursive_absolute(directory)
	for frame in 210:
		sim.advance(1./30.)
		view._process(1./30.)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/%03d.png" % frame)
	view.queue_free()
	await process_frame
	sim.release()
	print("V3 battle preview: 210 frames from the real combat view")
	quit()
