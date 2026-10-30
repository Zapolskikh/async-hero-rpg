extends SceneTree
## Anatomy and playback contract for every baked clip of both profiles.
const EYE := {"male":Rect2(222,120,24,28),"female":Rect2(222,124,24,28)}
const KNEE_LIMIT := 2.
var failures: Array[String] = []
var events: Array = []
func fail_if(condition: bool, message: String) -> void:
	if condition and message not in failures:
		failures.append(message)
func _initialize() -> void:
	call_deferred("_test")
func _test() -> void:
	var actor := CharacterRig.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.action_event.connect(func(event, socket, pose): events.append([str(event),str(socket),pose]))
	var count: int = 0
	for sex in ["male","female"]:
		actor.set_profile(sex)
		var l1 := float(actor.skeleton.l1)
		var l2 := float(actor.skeleton.l2)
		var lt := float(actor.skeleton.lt)
		var ls := float(actor.skeleton.ls)
		fail_if(actor.data.size() != 56,"Clip count "+sex)
		for id in actor.data:
			actor.play_clip(str(id),"",0.)
			var clip: Dictionary = actor.data[id]
			var death := str(id).begins_with("death_")
			for i in range(61):
				actor.seek_normalized(float(i)/60.)
				fail_if(actor.pose.is_empty(),"Empty pose: "+str(id))
				fail_if(not actor.sockets.has("right_hand"),"Missing socket: "+str(id))
				for side in ["R","L"]:
					var key: String = side.to_lower()
					var a: Vector2 = actor.joints["shoulder_"+side]
					var b: Vector2 = actor.joints["elbow_"+side]
					var c: Vector2 = actor.joints["wrist_"+side]
					var foreshort := actor._v(key+"uf")
					fail_if(absf(a.distance_to(b)-l1*foreshort)>.05,"Upper arm stretches: "+str(id))
					fail_if(absf(b.distance_to(c)-l2)>.05,"Forearm stretches: "+str(id))
					# A real elbow only folds one way: the forearm never rotates past the upper arm backwards.
					if foreshort > .99:
						var fold := wrapf(actor._v(key+"fa")-actor._v(key+"ua"),-180.,180.)
						fail_if(fold > 1.5,"Elbow hyperextends: %s %s %.1f" % [id,side,fold])
					var hip: Vector2 = actor.joints["hip_"+side]
					var knee: Vector2 = actor.joints["knee_"+side]
					var ankle: Vector2 = actor.joints["ankle_"+side]
					fail_if(absf(hip.distance_to(knee)-lt)>.05,"Thigh stretches: "+str(id))
					fail_if(absf(knee.distance_to(ankle)-ls)>.05,"Shin stretches: "+str(id))
					var bend := wrapf(actor._v(key+"ca")-actor._v(key+"ta"),-180.,180.)
					fail_if(bend < -KNEE_LIMIT,"Knee bends backwards: %s %s %.1f" % [id,side,bend])
				if not death:
					var eye: Rect2 = EYE[sex]
					var hand := Vector2(actor.sockets["right_hand"][0],actor.sockets["right_hand"][1])
					fail_if(eye.has_point(hand),"Right hand covers the face: "+str(id))
					fail_if(eye.has_point(actor.joints["wrist_R"]),"Forearm covers the face: "+str(id))
				if clip.meta.loadout == "greatsword" and actor.right_grip_weight > .999:
					var right: Array = actor.sockets["right_hand"]
					var left: Array = actor.sockets["left_hand"]
					var along := Vector2.RIGHT.rotated(deg_to_rad(right[2]))
					var gap := (Vector2(left[0],left[1])+along*float(actor.skeleton.gap)).distance_to(Vector2(right[0],right[1]))
					# Chord between two 60 Hz samples at peak swing speed; baked frames themselves are exact.
					fail_if(gap>2.,"Two-hand grip separates: %s %.2f" % [id,gap])
			actor.play_clip(str(id),"",0.)
			events.clear()
			actor.advance_pose(float(clip.meta.duration)+.05)
			fail_if(events.size() != clip.meta.events.size(),"Events count: "+str(id))
			if not bool(clip.meta.loop):
				actor.advance_pose(1.)
				fail_if(events.size() != clip.meta.events.size(),"Duplicate event: "+str(id))
			count += 1
	actor.set_profile("male")
	actor.begin_cast("greatsword")
	actor.advance_pose(.6)
	fail_if(actor.current_clip != "cast_hold_greatsword","Begin did not enter hold")
	actor.seek_normalized(.4)
	fail_if(actor.right_grip_weight > .001,"Right hand did not release greatsword")
	events.clear()
	actor.interrupt_cast("greatsword")
	actor.advance_pose(.3)
	fail_if(events.size() != 0,"Interrupt released spell")
	actor.release_cast("greatsword")
	actor.advance_pose(.6)
	fail_if(actor.current_clip != "idle_greatsword","Release did not return idle")
	fail_if(events.size() != 1,"Release count != 1")
	actor.play_clip("sword_right_slash","",.1)
	actor.advance_pose(.04)
	actor.play_clip("death_sword","",.12)
	actor.advance_pose(.05)
	fail_if(absf(actor.joints["elbow_R"].distance_to(actor.joints["wrist_R"])-float(actor.skeleton.l2))>.05,"Blending keeps limbs connected")
	actor.scale.x = -1.
	fail_if(not is_finite(actor.get_socket("right_hand").origin.x),"Mirrored socket invalid")
	print("VALIDATED_CLIPS=",count)
	for message in failures:
		push_error(message)
		print("FAIL ",message)
	print("FAILURES=",failures.size())
	quit(0 if failures.is_empty() else 1)
