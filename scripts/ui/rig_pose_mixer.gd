class_name RigPoseMixer
extends RefCounted
## Interpolate poses in joint/weapon space, never squash a rotating blade.
## V3 command layout: legs 0..5, rear arm 6..8, torso/head 9..13,
## equipment from 14 up to the front-arm tube, then glove/finger overlays.

static func point(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1]))

static func raw(p: Vector2) -> Array:
	return [p.x, p.y]

static func basis(origin: Vector2, direction: Vector2) -> Transform2D:
	return Transform2D(direction.angle(), origin)

static func mix_transform(a: Transform2D, b: Transform2D, weight: float) -> Transform2D:
	return Transform2D(lerp_angle(a.get_rotation(), b.get_rotation(), weight), a.origin.lerp(b.origin, weight))

static func transform_command(a: Dictionary, b: Dictionary, ta: Transform2D, tb: Transform2D, target: Transform2D, weight: float) -> Dictionary:
	var result: Dictionary = b.duplicate(true)
	if result.has("color"):
		result.color = "#" + Color(str(a.color)).lerp(Color(str(b.color)), weight).to_html(true)
	for i in result.p.size():
		var local_a: Vector2 = ta.affine_inverse() * point(a.p[i])
		var local_b: Vector2 = tb.affine_inverse() * point(b.p[i])
		result.p[i] = raw(target * local_a.lerp(local_b, weight))
	return result

static func compatible(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if a[i].type != b[i].type or a[i].p.size() != b[i].p.size(): return false
	return true

static func mix(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	if weight >= 1.0 or not compatible(a.commands, b.commands): return b.duplicate(true)
	if weight <= 0.0: return a.duplicate(true)
	var result: Dictionary = b.duplicate(true)
	for key in result.joints:
		result.joints[key] = raw(point(a.joints[key]).lerp(point(b.joints[key]), weight))
	for key in result.sockets:
		var origin: Vector2 = point(a.sockets[key]).lerp(point(b.sockets[key]), weight)
		result.sockets[key] = [origin.x, origin.y, rad_to_deg(lerp_angle(deg_to_rad(a.sockets[key][2]), deg_to_rad(b.sockets[key][2]), weight))]
	result.right_grip_weight = lerpf(a.right_grip_weight, b.right_grip_weight, weight)
	for i in result.commands.size():
		for j in result.commands[i].p.size():
			result.commands[i].p[j] = raw(point(a.commands[i].p[j]).lerp(point(b.commands[i].p[j]), weight))
		if result.commands[i].has("color"):
			result.commands[i].color = "#" + Color(str(a.commands[i].color)).lerp(Color(str(b.commands[i].color)), weight).to_html(true)
		if result.commands[i].has("angle"):
			result.commands[i].angle = rad_to_deg(lerp_angle(deg_to_rad(a.commands[i].angle), deg_to_rad(b.commands[i].angle), weight))
	# Solve the middle joint with fixed bone lengths. Linear vertex blending
	# shortens the arm most visibly when cancelling a cast or reversing a swing.
	var front_arm := -1
	for i in result.commands.size():
		if result.commands[i].type != "tube": continue
		var prefix: Array
		var side: String
		if i == 0 or i == 3:
			prefix = ["hip", "knee", "ankle"]
			side = "R" if i == 0 else "L"
		else:
			prefix = ["shoulder", "elbow", "wrist"]
			side = "L" if i == 6 else "R"
			if side == "R": front_arm = i
		var start := point(result.joints[prefix[0]+"_"+side])
		var end := point(result.joints[prefix[2]+"_"+side])
		var reference := point(result.joints[prefix[1]+"_"+side])
		var length_a := point(b.commands[i].p[0]).distance_to(point(b.commands[i].p[1]))
		var length_b := point(b.commands[i].p[1]).distance_to(point(b.commands[i].p[2]))
		var distance := maxf(start.distance_to(end), .0001)
		var direction := (end-start)/distance
		var along := (length_a*length_a-length_b*length_b+distance*distance)/(2.0*distance)
		var height := sqrt(maxf(0.0, length_a*length_a-along*along))
		var normal := Vector2(-direction.y, direction.x)
		var sign_side := 1.0 if (reference-start).dot(normal) >= 0.0 else -1.0
		var middle := start + direction*along + normal*height*sign_side
		result.joints[prefix[1]+"_"+side] = raw(middle)
		result.commands[i].p = [raw(start), raw(middle), raw(end)]
		if prefix[0] != "shoulder": continue
		# Cuff and glove stay on the solved forearm, including during blends.
		var ta := basis(point(a.commands[i].p[2]), point(a.commands[i].p[2])-point(a.commands[i].p[1]))
		var tb := basis(point(b.commands[i].p[2]), point(b.commands[i].p[2])-point(b.commands[i].p[1]))
		var target := basis(end, end-middle)
		for j in range(i+1, i+3):
			result.commands[j] = transform_command(a.commands[j], b.commands[j], ta, tb, target, weight)
	# Equipment occupies the block between the head and the front arm.
	# Each item rotates around its grip as one rigid group.
	var loadout: String = b.get("loadout", "unarmed")
	if front_arm > 14:
		if loadout in ["dual", "shield"]:
			mix_item(a,b,result,14,19,"right_hand",["right_weapon_tip"],weight)
			mix_item(a,b,result,19,front_arm,"left_hand",["left_weapon_tip","shield_front"],weight)
		elif loadout == "bow":
			# Bow curvature and string are deliberately deformable.
			pass
		else:
			mix_item(a,b,result,14,front_arm,"right_hand",["right_weapon_tip","staff_tip"],weight)
	return result

static func mix_item(a: Dictionary, b: Dictionary, result: Dictionary, first: int, stop: int, grip: String, tips: Array, weight: float) -> void:
	# Geometry supplies orientation: greatsword's right-hand socket angle belongs
	# to the casting hand after it lets go, not to the sword held in the left.
	var ca: Dictionary = a.commands[first]
	var cb: Dictionary = b.commands[first]
	var oa := point(a.sockets[grip])
	var ob := point(b.sockets[grip])
	if b.get("loadout", "") == "greatsword":
		oa = point(ca.p[0])
		ob = point(cb.p[0])
	var ta := basis(oa, point(ca.p[1])-point(ca.p[0]))
	var tb := basis(ob, point(cb.p[1])-point(cb.p[0]))
	var target := mix_transform(ta,tb,weight)
	for i in range(first,stop):
		result.commands[i] = transform_command(a.commands[i],b.commands[i],ta,tb,target,weight)
	for key in tips:
		var local_a: Vector2 = ta.affine_inverse()*point(a.sockets[key])
		var local_b: Vector2 = tb.affine_inverse()*point(b.sockets[key])
		var p: Vector2 = target*local_a.lerp(local_b,weight)
		result.sockets[key][0] = p.x
		result.sockets[key][1] = p.y

static func add_loadout_attacks(data: Dictionary) -> void:
	for loadout in ["dual", "shield"]:
		var id: String = "sword_right_slash_"+loadout
		if data.has(id): continue
		var clip: Dictionary = data.sword_right_slash.duplicate(true)
		clip.meta.id = id
		clip.meta.loadout = loadout
		var idle: Dictionary = data["idle_"+loadout].frames[0]
		var end := 24 if loadout == "dual" else 22
		var source := Transform2D(deg_to_rad(idle.sockets.left_hand[2]),point(idle.sockets.left_hand))
		for frame in clip.frames:
			var target := Transform2D(deg_to_rad(frame.sockets.left_hand[2]),point(frame.sockets.left_hand))
			for i in range(19,end):
				var command: Dictionary = idle.commands[i].duplicate(true)
				for j in command.p.size(): command.p[j] = raw(target*source.affine_inverse()*point(command.p[j]))
				frame.commands.insert(i,command)
			for key in ["left_weapon_tip","shield_front"]:
				var p: Vector2 = target*source.affine_inverse()*point(idle.sockets[key])
				frame.sockets[key] = [p.x,p.y,frame.sockets.left_hand[2]]
		data[id] = clip
