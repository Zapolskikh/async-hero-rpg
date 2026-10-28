extends SceneTree
var failures: Array[String] = []
var events: Array = []
func fail_if(condition: bool, message: String) -> void:
	if condition:
		failures.append(message)
func _initialize() -> void:
	call_deferred("_test")
func _test() -> void:
	var actor: V3RigActor = V3RigActor.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.action_event.connect(func(event, socket, pose): events.append([str(event),str(socket),pose]))
	var count: int = 0
	for sex in ["male", "female"]:
		actor.set_profile(sex)
		for id in actor.data:
			actor.play_clip(str(id), "", 0.0)
			var clip: Dictionary = actor.data[id]
			for i in range(21):
				actor.seek_normalized(float(i)/20.0)
				fail_if(actor.commands.is_empty(), "Empty pose: " + str(id))
				fail_if(not actor.sockets.has("right_hand"), "Missing socket: " + str(id))
				for side in ["R","L"]:
					var shoulder: Array = actor.joints["shoulder_"+side]
					var elbow: Array = actor.joints["elbow_"+side]
					var wrist: Array = actor.joints["wrist_"+side]
					var a := Vector2(shoulder[0],shoulder[1])
					var b := Vector2(elbow[0],elbow[1])
					var c := Vector2(wrist[0],wrist[1])
					fail_if(absf(a.distance_to(b)-48.)>.03,"Upper arm stretches: "+str(id))
					fail_if(absf(b.distance_to(c)-48.)>.03,"Forearm stretches: "+str(id))
					var ankle: Array = actor.joints["ankle_"+side]
					fail_if(absf(ankle[1]-377.)>.001,"Foot lifts/slides: "+str(id))
				if clip.meta.loadout == "greatsword" and actor.right_grip_weight > .999:
					var right: Array = actor.sockets["right_hand"]
					var left: Array = actor.sockets["left_hand"]
					var expected := Vector2(right[0],right[1])-Vector2(17,0).rotated(deg_to_rad(right[2]))
					# Linear socket interpolation and angular interpolation differ by a subpixel chord.
					fail_if(expected.distance_to(Vector2(left[0],left[1]))>.6,"Two-hand grip separates: "+str(id))
			actor.play_clip(str(id), "", 0.0)
			events.clear()
			actor.advance_pose(float(clip.meta.duration) + 0.05)
			fail_if(events.size() != clip.meta.events.size(), "Events count: " + str(id))
			if not bool(clip.meta.loop):
				actor.advance_pose(1.0)
				fail_if(events.size() != clip.meta.events.size(), "Duplicate event: " + str(id))
			count += 1
	actor.set_profile("male")
	actor.begin_cast("greatsword")
	actor.advance_pose(0.6)
	fail_if(actor.current_clip != "cast_hold_greatsword", "Begin did not enter hold")
	actor.seek_normalized(0.4)
	fail_if(actor.right_grip_weight > 0.001, "Right hand did not release greatsword")
	events.clear()
	actor.interrupt_cast("greatsword")
	actor.advance_pose(0.3)
	fail_if(events.size() != 0, "Interrupt released spell")
	actor.release_cast("greatsword")
	actor.advance_pose(0.6)
	fail_if(actor.current_clip != "idle_greatsword", "Release did not return idle")
	fail_if(events.size() != 1, "Release count != 1")
	actor.scale.x = -1.0
	var socket: Transform2D = actor.get_socket("right_hand")
	fail_if(not is_finite(socket.origin.x), "Mirrored socket invalid")
	print("VALIDATED_CLIPS=", count)
	for message in failures:
		push_error(message)
	print("FAILURES=", failures.size())
	quit(0 if failures.is_empty() else 1)
