extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and message not in failures: failures.append(message)
func _initialize() -> void:
	run.call_deferred()
func held(actor: CharacterActor) -> int:
	return actor.rig._weapons.size()
func run() -> void:
	var actor := CharacterActor.new()
	root.add_child(actor)
	actor.set_process(false)
	for sex in ["male","female"]:
		for weapons in [["sword"],["sword","sword"],["sword","shield"],["greatsword"],["bow"],["staff"],[]]:
			actor.configure({"sex":sex},[],weapons)
			var count: int = held(actor)
			var l1 := float(actor.rig.skeleton.l1)
			var l2 := float(actor.rig.skeleton.l2)
			for phase in [.15,.35,.6,.9]:
				actor.play("idle")
				actor.rig.seek_normalized(.4)
				actor.begin_magic(Color.WHITE,false)
				actor.advance_visual(phase*.64)
				actor.cancel_cast()
				for tick in 10:
					actor.advance_visual(.01)
					check(held(actor)==count,"Equipment changed during cast transition")
					for side in ["R","L"]:
						var joints: Dictionary = actor.rig.joints
						var shoulder: Vector2 = joints["shoulder_"+side]
						var elbow: Vector2 = joints["elbow_"+side]
						var wrist: Vector2 = joints["wrist_"+side]
						check(absf(shoulder.distance_to(elbow)-l1*actor.rig._v(side.to_lower()+"uf"))<.04,"Upper arm shrank during crossfade")
						check(absf(wrist.distance_to(elbow)-l2)<.04,"Forearm shrank during crossfade")
			if actor.loadout in ["dual","shield"]:
				for attack in 2:
					actor.play("attack")
					check(actor.rig.data[actor.rig.current_clip].meta.loadout==actor.loadout,"Attack switched equipment")
					for tick in 100:
						actor.advance_visual(.01)
						check(held(actor)==count,"Offhand disappeared during attack/recovery")
	actor.queue_free()
	await process_frame
	for message in failures: push_error(message)
	print("RIG TRANSITIONS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
