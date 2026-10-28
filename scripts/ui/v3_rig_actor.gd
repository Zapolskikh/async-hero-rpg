class_name V3RigActor
extends Node2D

signal action_event(event_name: StringName, socket_name: StringName, socket_transform: Transform2D)
signal clip_finished(clip_name: StringName)

static var _profile_cache: Dictionary = {}
var sex: String = "male"
var data: Dictionary = {}
var current_clip: String = "idle_sword"
var elapsed: float = 0.0
var speed: float = 1.0
var paused: bool = false
var debug_bones: bool = false
var head_texture: Texture2D
var commands: Array = []
var sockets: Dictionary = {}
var joints: Dictionary = {}
var right_grip_weight: float = 1.0
var _follow: String = ""
var _blend_from: Array = []
var _blend_sockets: Dictionary = {}
var _blend_elapsed: float = 1.0
var _blend_duration: float = 0.10
var _done: bool = false
var _fired_events := {}
var action_serial: int = 0
var default_follows := {}
var last_event_offset := 0.
var glow_color := Color("#99cfff")
var glow_visible := false
var glow_socket := "cast_right"
var arrow_loaded := true
const INK = Color("#211f2a")

func _ready() -> void:
	set_profile(sex)
	set_process(false) # CharacterActor/BattleView own the only scaled clock in the game.

func set_profile(value: String) -> void:
	sex = value if value in ["male", "female"] else "male"
	var parsed = _profile_cache.get(sex)
	if parsed == null:
		var packed := FileAccess.get_file_as_bytes("res://assets/characters/v3/animations_%s.json.gz" % sex)
		var source := packed.decompress_dynamic(32 * 1024 * 1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
		parsed = JSON.parse_string(source)
	if not parsed is Dictionary:
		push_error("Animation JSON not found or invalid")
		return
	_profile_cache[sex] = parsed
	data = parsed
	head_texture = load("res://assets/characters/v3/head_%s.png" % sex) as Texture2D
	commands = []
	_blend_from = []
	play_clip(current_clip if data.has(current_clip) else "idle_sword", "", 0.0)

func play_clip(id: String, follow: String = "", blend: float = 0.10) -> bool:
	if not data.has(id):
		push_warning("Unknown clip: " + id)
		return false
	action_serial += 1
	_blend_from = commands.duplicate(true)
	_blend_sockets = sockets.duplicate(true)
	_blend_duration = maxf(blend, 0.0)
	_blend_elapsed = 0.0
	current_clip = id
	_follow = follow if not follow.is_empty() else str(default_follows.get(id,""))
	elapsed = 0.0
	_done = false
	_fired_events.clear()
	_update_pose()
	return true

func begin_cast(loadout: String) -> void:
	play_clip("cast_begin_" + loadout, "cast_hold_" + loadout)

func release_cast(loadout: String) -> void:
	play_clip("cast_release_" + loadout, "idle_" + loadout)

func instant_cast(loadout: String) -> void:
	play_clip("cast_instant_" + loadout, "idle_" + loadout)

func interrupt_cast(loadout: String) -> void:
	# Drops pending events and returns from the current pose without releasing a spell.
	play_clip("idle_" + loadout, "", 0.14)

func get_socket(socket_name: String) -> Transform2D:
	var p: Array = sockets.get(socket_name, [0.0, 0.0, 0.0])
	return global_transform * Transform2D(deg_to_rad(float(p[2])), Vector2(float(p[0]), float(p[1])))

func seek_normalized(value: float) -> void:
	if data.is_empty():
		return
	elapsed = clampf(value, 0.0, 1.0) * float(data[current_clip].meta.duration)
	_blend_from = []
	_update_pose()
	# Inspection seeking intentionally never emits combat events.

func _process(delta: float) -> void:
	if not paused:
		advance_pose(delta * speed)

func advance_pose(delta: float) -> void:
	if data.is_empty() or delta <= 0.0:
		return
	var remaining: float = delta
	var transitions: int = 0
	var progressed := 0.
	while remaining > 0.000001 and transitions < 100:
		var generation: int = action_serial
		var clip: Dictionary = data[current_clip]
		var duration: float = float(clip.meta.duration)
		var before: float = elapsed
		var step: float = minf(remaining, maxf(duration - elapsed, 0.0))
		elapsed += step
		remaining -= step
		progressed += step
		_blend_elapsed += step
		_update_pose()
		if not _done:
			for event_index in clip.meta.events.size():
				var event: Dictionary = clip.meta.events[event_index]
				var at: float = float(event.time)
				if not _fired_events.has(event_index) and before < at and elapsed + 0.000001 >= at:
					_fired_events[event_index] = true
					# Sample the exact event timestamp; do not use a later frame after a long delta.
					var previous_time: float = elapsed
					elapsed = at
					last_event_offset = progressed - (previous_time-at)
					_update_pose()
					action_event.emit(StringName(event.name), StringName(event.socket), get_socket(str(event.socket)))
					if action_serial != generation:
						return
					elapsed = previous_time
					_update_pose()
		if elapsed + 0.000001 >= duration:
			if bool(clip.meta.loop):
				elapsed = 0.0
				_fired_events.clear()
				transitions += 1
			elif not _done:
				_done = true
				var completed: String = current_clip
				var next: String = _follow
				clip_finished.emit(StringName(completed))
				if action_serial != generation:
					return
				if not next.is_empty():
					play_clip(next)
					transitions += 1
				else:
					remaining = 0.0
			else:
				remaining = 0.0
		elif step <= 0.0:
			break

func _compatible(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i].type != b[i].type or a[i].p.size() != b[i].p.size():
			return false
	return true

func _mix_commands(a: Array, b: Array, weight: float) -> Array:
	if not _compatible(a, b):
		return b.duplicate(true)
	var result: Array = b.duplicate(true)
	for i in range(result.size()):
		for j in range(result[i].p.size()):
			result[i].p[j][0] = lerpf(float(a[i].p[j][0]), float(b[i].p[j][0]), weight)
			result[i].p[j][1] = lerpf(float(a[i].p[j][1]), float(b[i].p[j][1]), weight)
		if result[i].has("angle"):
			result[i].angle = rad_to_deg(lerp_angle(deg_to_rad(float(a[i].angle)), deg_to_rad(float(b[i].angle)), weight))
		if result[i].has("color"):
			result[i].color = "#" + Color(str(a[i].color)).lerp(Color(str(b[i].color)), weight).to_html(true)
	return result

func _mix_sockets(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var result: Dictionary = b.duplicate(true)
	for key in result:
		if not a.has(key):
			continue
		for k in range(2):
			result[key][k] = lerpf(float(a[key][k]), float(b[key][k]), weight)
		result[key][2] = rad_to_deg(lerp_angle(deg_to_rad(float(a[key][2])), deg_to_rad(float(b[key][2])), weight))
	return result

func _update_pose() -> void:
	if data.is_empty():
		return
	var clip: Dictionary = data[current_clip]
	var frames: Array = clip.frames
	var frame_time: float = clampf(elapsed * float(clip.meta.fps), 0.0, float(frames.size() - 1))
	var index: int = int(floor(frame_time))
	var next: int = mini(index + 1, frames.size() - 1)
	var alpha: float = frame_time - float(index)
	commands = _mix_commands(frames[index].commands, frames[next].commands, alpha)
	sockets = _mix_sockets(frames[index].sockets, frames[next].sockets, alpha)
	joints = frames[index].joints
	right_grip_weight = lerpf(float(frames[index].right_grip_weight), float(frames[next].right_grip_weight), alpha)
	if not _blend_from.is_empty() and _blend_duration > 0.0 and _blend_elapsed < _blend_duration:
		var weight: float = smoothstep(0.0, 1.0, _blend_elapsed / _blend_duration)
		commands = _mix_commands(_blend_from, commands, weight)
		sockets = _mix_sockets(_blend_sockets, sockets, weight)
	queue_redraw()

func _draw() -> void:
	for command in commands:
		if not arrow_loaded and data[current_clip].meta.loadout == "bow":
			# The V3 command stream identifies the nocked shaft/tip by their dedicated material.
			if command.type == "line" and command.get("color","") == "#b8a07a": continue
			if command.type == "poly" and command.p.size() == 3 and command.get("color","") == "#c5cedb": continue
		var points: PackedVector2Array = []
		for p in command.p:
			points.append(Vector2(float(p[0]), float(p[1])))
		var color: Color = Color(str(command.get("color", "#ffffff")))
		match str(command.type):
			"poly":
				if color.a > 0.0:
					draw_colored_polygon(points, color)
					if bool(command.outline):
						points.append(points[0])
						draw_polyline(points, INK, 4.0, true)
			"line":
				draw_polyline(points, color, float(command.width), true)
			"tube":
				for pass_index in range(2):
					var w: float = float(command.width) + (4.0 if pass_index == 0 else -2.0)
					var c: Color = INK if pass_index == 0 else color
					draw_polyline(points, c, w, true)
					for p in points:
						draw_circle(p, w * 0.5, c, true, -1.0, true)
			"texture":
				draw_set_transform(points[0], deg_to_rad(float(command.angle)))
				draw_texture(head_texture, Vector2(-77.0, -95.0))
				draw_set_transform(Vector2.ZERO)
	if glow_visible and sockets.has(glow_socket):
		var hand: Array = sockets[glow_socket]
		var point := Vector2(hand[0],hand[1])
		for i in 4:
			var color := glow_color
			color.a = .06+i*.07
			draw_circle(point,26.-i*6.,color,true,-1.,true)
	if debug_bones:
		for side in ["R", "L"]:
			var points: PackedVector2Array = []
			for part in ["shoulder", "elbow", "wrist"]:
				var p: Array = joints.get(part + "_" + side, [0.0, 0.0])
				points.append(Vector2(p[0], p[1]))
			draw_polyline(points, Color.HOT_PINK, 1.5, true)
		for raw in joints.values():
			draw_circle(Vector2(raw[0], raw[1]), 3.0, Color.GOLD)
