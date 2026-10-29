extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var actor := CharacterActor.new()
	root.add_child(actor)
	actor.set_process(false)
	for sex in ["male", "female"]:
		for weapons in [["sword"],["sword","sword"],["sword","shield"],["greatsword"],["bow"],["staff"],[]]:
			actor.configure({"sex":sex},[],weapons)
			var count: int = actor.rig.commands.size()
			for phase in [.15,.35,.6,.9]:
				actor.play("idle")
				actor.rig.seek_normalized(.4)
				actor.begin_magic(Color.WHITE,false)
				actor.advance_visual(phase*.64)
				actor.cancel_cast()
				for tick in 10:
					actor.advance_visual(.01)
					check(actor.rig.commands.size()==count,"Equipment topology changed during cast transition")
					for side in ["R","L"]:
						var joints: Dictionary = actor.rig.joints
						var shoulder := RigPoseMixer.point(joints["shoulder_"+side])
						var elbow := RigPoseMixer.point(joints["elbow_"+side])
						var wrist := RigPoseMixer.point(joints["wrist_"+side])
						check(absf(shoulder.distance_to(elbow)-48.)<.04,"Upper arm shrank during crossfade")
						check(absf(wrist.distance_to(elbow)-48.)<.04,"Forearm shrank during crossfade")
					if actor.loadout in ["sword","dual","shield","greatsword"]:
						var blade: Array = actor.rig.commands[16].p
						var source: Array = actor.rig.data["idle_"+actor.loadout].frames[0].commands[16].p
						check(absf(RigPoseMixer.point(blade[0]).distance_to(RigPoseMixer.point(blade[2]))-RigPoseMixer.point(source[0]).distance_to(RigPoseMixer.point(source[2])))<.02,"Blade shrank during crossfade")
			if actor.loadout in ["dual","shield"]:
				for attack in 2:
					actor.play("attack")
					check(actor.rig.data[actor.rig.current_clip].meta.loadout==actor.loadout,"Attack switched equipment")
					for tick in 100:
						actor.advance_visual(.01)
						check(actor.rig.commands.size()==count,"Offhand disappeared during attack/recovery")
	# Regression: the former vertex lerp halves a blade at a 120-degree turn.
	var frame: Dictionary = actor.rig.data.idle_sword.frames[0].duplicate(true)
	frame.loadout = "sword"
	var rotated: Dictionary = frame.duplicate(true)
	var pivot := RigPoseMixer.point(frame.sockets.right_hand)
	for i in range(14,19):
		for j in rotated.commands[i].p.size():
			rotated.commands[i].p[j] = RigPoseMixer.raw(pivot+(RigPoseMixer.point(frame.commands[i].p[j])-pivot).rotated(deg_to_rad(120.)))
	var mixed := RigPoseMixer.mix(frame,rotated,.5)
	var expected := RigPoseMixer.point(frame.commands[16].p[0]).distance_to(RigPoseMixer.point(frame.commands[16].p[2]))
	var actual := RigPoseMixer.point(mixed.commands[16].p[0]).distance_to(RigPoseMixer.point(mixed.commands[16].p[2]))
	check(absf(expected-actual)<.01,"120-degree blade rotation must remain rigid")
	actor.queue_free()
	await process_frame
	for message in failures: push_error(message)
	print("RIG TRANSITIONS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
