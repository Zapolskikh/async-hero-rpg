class_name CharacterRig
extends Node2D
## Cut-out hero rig: baked bone angles from tools/build_character_rig.py, forward kinematics here.
## Blending happens on the bones, so limbs and grips stay connected through every transition.

signal action_event(event_name: StringName, socket_name: StringName, socket_transform: Transform2D)
signal clip_finished(clip_name: StringName)

const STRING_COLOR := Color("#d9dbe2")
const INK_COLOR := Color("#17141d")
const SWORD_TIP := 138.
const GREATSWORD_TIP := 182.
const STAFF_TIP := 176.
const BOW_TIP := Vector2(-14.,112.)
const ARROW_LENGTH := 134.
const BOW_FLEX := .22
const BOW_SHORTEN := .05
const PALM_REACH := 22.
const SHIELD_OFFSET := Vector2(6.,0.)
const SHIELD_FACE := 36.
const ANGLES := ["ha","ca","na","rua","rfa","rha","lua","lfa","lha","rta","rca","rba","lta","lca","lba","w1a","w2a"]
const STEPPED := ["nock","ro","lo","wz","lz"]
const GEAR_SLOTS := {"head":"head","chest":"armor","hem":"armor","upper_r":"armor","upper_l":"armor",
	"fore_r":"hands","fore_l":"hands","fist_r":"hands","fist_l":"hands","palm_r":"hands","palm_l":"hands",
	"thigh_r":"legs","thigh_l":"legs","shin_r":"legs","shin_l":"legs","boot_r":"feet","boot_l":"feet"}

static var _profile_cache: Dictionary = {}
var sex: String = "male"
var data: Dictionary = {}
var skeleton: Dictionary = {}
var current_clip: String = "idle_sword"
var elapsed: float = 0.
var loadout := "sword"
var head_texture: Texture2D
var atlas: Texture2D
var pose := PackedFloat32Array()
var sockets: Dictionary = {}
var joints: Dictionary = {}
var right_grip_weight: float = 1.
var action_serial: int = 0
var default_follows := {}
var last_event_offset := 0.
var glow_color := Color("#99cfff")
var glow_visible := false
var glow_socket := "cast_right"
var arrow_loaded := true
var _follow: String = ""
var _blend_from := PackedFloat32Array()
var _blend_elapsed: float = 1.
var _blend_duration: float = .10
var _done: bool = false
var _fired_events := {}
var _bones := {}
var worn := {}          # slot -> GearArt.find result
var _weapons: Array = []
var _rects := {}
var _field := {}
var _angular := PackedInt32Array()
var _stepped := PackedInt32Array()

func _ready() -> void:
	set_process(false) # CharacterActor/BattleView own the only scaled clock in the game.

func set_profile(value: String) -> void:
	sex = value if value in ["male","female"] else "male"
	var parsed = _profile_cache.get(sex)
	if parsed == null:
		var packed := FileAccess.get_file_as_bytes("res://assets/characters/rig/clips_%s.json.gz" % sex)
		var source := packed.decompress_dynamic(8 * 1024 * 1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
		parsed = JSON.parse_string(source)
	if not parsed is Dictionary:
		push_error("Character rig data not found or invalid")
		return
	_profile_cache[sex] = parsed
	skeleton = parsed.skeleton
	data = parsed.clips
	head_texture = load("res://assets/characters/rig/head_%s.png" % sex) as Texture2D
	atlas = load("res://assets/characters/rig/atlas_%s.png" % sex) as Texture2D
	_field.clear()
	_angular.clear()
	_stepped.clear()
	for i in skeleton.fields.size():
		var field: String = skeleton.fields[i]
		_field[field] = i
		if field in ANGLES: _angular.append(i)
		if field in STEPPED: _stepped.append(i)
	_rects.clear()
	var res := float(skeleton.res)
	for part in skeleton.parts:
		var info: Dictionary = skeleton.parts[part]
		for layer in ["ink","fill"]:
			var r: Array = info[layer]
			var size := Vector2(r[2],r[3])
			_rects[part+":"+layer] = [Rect2(Vector2(info.origin[0],info.origin[1]),size/res),Rect2(Vector2(r[0],r[1]),size)]
	pose = PackedFloat32Array()
	_blend_from = PackedFloat32Array()
	play_clip(current_clip if data.has(current_clip) else "idle_sword","",0.)

func play_clip(id: String, follow: String = "", blend: float = .10) -> bool:
	if not data.has(id):
		push_warning("Unknown clip: " + id)
		return false
	action_serial += 1
	_blend_from = pose.duplicate()
	_blend_duration = maxf(blend,0.)
	_blend_elapsed = 0.
	current_clip = id
	loadout = str(data[id].meta.loadout)
	_follow = follow if not follow.is_empty() else str(default_follows.get(id,""))
	elapsed = 0.
	_done = false
	_fired_events.clear()
	_update_pose()
	return true

func begin_cast(kit: String) -> void:
	play_clip("cast_begin_"+kit,"cast_hold_"+kit)

func release_cast(kit: String) -> void:
	play_clip("cast_release_"+kit,"idle_"+kit)

func instant_cast(kit: String) -> void:
	play_clip("cast_instant_"+kit,"idle_"+kit)

func interrupt_cast(kit: String) -> void:
	# Drops pending events and returns from the current pose without releasing a spell.
	play_clip("idle_"+kit,"",.14)

func get_socket(socket_name: String) -> Transform2D:
	var p: Array = sockets.get(socket_name,[0.,0.,0.])
	return global_transform * Transform2D(deg_to_rad(float(p[2])),Vector2(float(p[0]),float(p[1])))

func seek_normalized(value: float) -> void:
	if data.is_empty(): return
	elapsed = clampf(value,0.,1.) * float(data[current_clip].meta.duration)
	_blend_from = PackedFloat32Array()
	_update_pose()
	# Inspection seeking intentionally never emits combat events.

func advance_pose(delta: float) -> void:
	if data.is_empty() or delta <= 0.: return
	var remaining: float = delta
	var transitions: int = 0
	var progressed := 0.
	while remaining > .000001 and transitions < 100:
		var generation: int = action_serial
		var clip: Dictionary = data[current_clip]
		var duration: float = float(clip.meta.duration)
		var before: float = elapsed
		var step: float = minf(remaining,maxf(duration-elapsed,0.))
		elapsed += step
		remaining -= step
		progressed += step
		_blend_elapsed += step
		_update_pose()
		if not _done:
			for event_index in clip.meta.events.size():
				var event: Dictionary = clip.meta.events[event_index]
				var at: float = float(event.time)
				if not _fired_events.has(event_index) and before < at and elapsed + .000001 >= at:
					_fired_events[event_index] = true
					# Sample the exact event timestamp; do not use a later frame after a long delta.
					var previous_time: float = elapsed
					elapsed = at
					last_event_offset = progressed-(previous_time-at)
					_update_pose()
					action_event.emit(StringName(event.name),StringName(event.socket),get_socket(str(event.socket)))
					if action_serial != generation: return
					elapsed = previous_time
					_update_pose()
		if elapsed + .000001 >= duration:
			if bool(clip.meta.loop):
				elapsed = 0.
				_fired_events.clear()
				transitions += 1
			elif not _done:
				_done = true
				var completed: String = current_clip
				var next: String = _follow
				clip_finished.emit(StringName(completed))
				if action_serial != generation: return
				if not next.is_empty():
					play_clip(next)
					transitions += 1
				else:
					remaining = 0.
			else:
				remaining = 0.
		elif step <= 0.:
			break

func _sample() -> PackedFloat32Array:
	var clip: Dictionary = data[current_clip]
	var frames: Array = clip.frames
	var at: float = clampf(elapsed*float(clip.meta.fps),0.,float(frames.size()-1))
	var index: int = int(floor(at))
	var a: Array = frames[index]
	var b: Array = frames[mini(index+1,frames.size()-1)]
	var alpha: float = at-float(index)
	var out := PackedFloat32Array()
	out.resize(a.size())
	for i in a.size(): out[i] = lerpf(a[i],b[i],alpha)
	for i in _stepped: out[i] = a[i]
	return out

func _update_pose() -> void:
	if data.is_empty(): return
	var next := _sample()
	right_grip_weight = next[_field["grip"]]
	if _blend_from.size() == next.size() and _blend_duration > 0. and _blend_elapsed < _blend_duration:
		var weight: float = smoothstep(0.,1.,_blend_elapsed/_blend_duration)
		var mixed := next.duplicate()
		for i in next.size(): mixed[i] = lerpf(_blend_from[i],next[i],weight)
		for i in _angular: mixed[i] = rad_to_deg(lerp_angle(deg_to_rad(_blend_from[i]),deg_to_rad(next[i]),weight))
		for i in _stepped: mixed[i] = next[i]
		next = mixed
	pose = next
	_solve()
	queue_redraw()

func _v(field: String) -> float:
	return pose[_field[field]]

func _ray(from: Vector2, degrees: float, length: float) -> Vector2:
	return from + Vector2.RIGHT.rotated(deg_to_rad(degrees))*length

func _solve() -> void:
	var s: Dictionary = skeleton
	var hip := Vector2(_v("hx"),_v("hy"))
	var waist: Vector2 = hip + Vector2(s.waist[0],s.waist[1]).rotated(deg_to_rad(_v("ha")))
	var chest_turn := deg_to_rad(_v("ca"))
	_bones = {"hem":[hip,_v("ha"),1.],"chest":[waist,_v("ca"),1.],"head":[waist+Vector2(s.neck[0],s.neck[1]).rotated(chest_turn),_v("na"),1.]}
	joints = {}
	var limb_names := {"r":"R","l":"L"}
	var index := 0
	for side in ["r","l"]:
		var shoulder: Vector2 = waist + Vector2(_v(side+"sx"),_v(side+"sy")).rotated(chest_turn)
		var elbow := _ray(shoulder,_v(side+"ua"),float(s.l1)*_v(side+"uf"))
		var wrist := _ray(elbow,_v(side+"fa"),float(s.l2))
		var joint: Vector2 = hip + Vector2(float(s.hipx[index]),0.).rotated(deg_to_rad(_v("ha")))
		var knee := _ray(joint,_v(side+"ta"),float(s.lt))
		var ankle := _ray(knee,_v(side+"ca"),float(s.ls))
		_bones["upper_"+side] = [shoulder,_v(side+"ua"),_v(side+"uf")]
		_bones["fore_"+side] = [elbow,_v(side+"fa"),1.]
		_bones["hand_"+side] = [wrist,_v(side+"ha"),1.]
		_bones["thigh_"+side] = [joint,_v(side+"ta"),1.]
		_bones["shin_"+side] = [knee,_v(side+"ca"),1.]
		_bones["boot_"+side] = [ankle,_v(side+"ba"),1.]
		var mark: String = limb_names[side]
		joints["shoulder_"+mark] = shoulder
		joints["elbow_"+mark] = elbow
		joints["wrist_"+mark] = wrist
		joints["hip_"+mark] = joint
		joints["knee_"+mark] = knee
		joints["ankle_"+mark] = ankle
		index += 1
	var grip_r := _ray(_bones["hand_r"][0],_v("rha"),float(s.grip))
	var grip_l := _ray(_bones["hand_l"][0],_v("lha"),float(s.grip))
	var w1 := _v("w1a")
	var w2 := _v("w2a")
	var right_tip := grip_r
	var left_tip := grip_l
	var staff_tip := grip_r
	var muzzle := grip_l
	var shield_front := grip_l
	_weapons = []
	match loadout:
		"sword","dual","shield":
			_weapons.append(["sword",grip_r,w1,"main"])
			right_tip = _ray(grip_r,w1,SWORD_TIP)
			if loadout == "dual":
				_weapons.append(["sword",grip_l,w2,"off"])
				left_tip = _ray(grip_l,w2,SWORD_TIP)
			if loadout == "shield":
				_weapons.append(["shield",grip_l+SHIELD_OFFSET,w2,"off"])
				shield_front = _ray(grip_l+SHIELD_OFFSET,w2,SHIELD_FACE)
		"greatsword":
			var origin := _ray(grip_l,w1,float(s.gap))
			_weapons.append(["greatsword",origin,w1,"main"])
			right_tip = _ray(origin,w1,GREATSWORD_TIP)
		"staff":
			_weapons.append(["staff",grip_r,w1,"main"])
			staff_tip = _ray(grip_r,w1,STAFF_TIP)
		"bow":
			_weapons.append(["bow",grip_l,w2,"off"])
			muzzle = _ray(grip_l,w2,28.)
	sockets = {"right_hand":[grip_r.x,grip_r.y,w1],"left_hand":[grip_l.x,grip_l.y,w2],"right_weapon_tip":[right_tip.x,right_tip.y,w1],
		"left_weapon_tip":[left_tip.x,left_tip.y,w2],"staff_tip":[staff_tip.x,staff_tip.y,w1],"arrow_muzzle":[muzzle.x,muzzle.y,w2],"shield_front":[shield_front.x,shield_front.y,w2]}
	var palm := _ray(grip_r,_v("rha"),PALM_REACH if _v("ro") > .5 else 8.)
	sockets["cast_right"] = [palm.x,palm.y,_v("rha")]

## Gear from Roster.look layers. Drawn gear replaces the body part under it.
func set_gear(layers: Array) -> void:
	worn.clear()
	for layer in layers:
		if str(layer[0]).begins_with("gear:"):
			var art := GearArt.find(str(layer[1]),sex)
			if not art.is_empty(): worn[str(layer[0]).substr(5)] = art
	queue_redraw()

func _art(part: String, slot: String = "") -> Dictionary:
	var art: Dictionary = worn.get(slot if slot != "" else str(GEAR_SLOTS.get(part,"")),{})
	return art if art.get("parts",{}).has(part) else {}

func _wear(art: Dictionary, part: String, target: Rect2) -> void:
	draw_texture_rect_region(art["texture"],target,art["parts"][part])

func _blit(part: String, layer: String, bone: Array) -> void:
	draw_set_transform(bone[0],deg_to_rad(bone[1]),Vector2(bone[2],1.))
	var rects: Array = _rects[part+":"+layer]
	draw_texture_rect_region(atlas,rects[0],rects[1])

## Outlines first, fills second: neighbouring segments of a limb share one silhouette.
func _group(items: Array) -> void:
	var bare: Array = items.filter(func(item): return _art(item[0]).is_empty())
	for layer in ["ink","fill"]:
		for item in bare: _blit(item[0],layer,_bones[item[1]])
	for item in items:
		var art := _art(item[0])
		if art.is_empty(): continue
		var bone: Array = _bones[item[1]]
		draw_set_transform(bone[0],deg_to_rad(bone[1]),Vector2(bone[2],1.))
		_wear(art,item[0],_rects[item[0]+":ink"][0])

func _single(part: String, at: Vector2, angle: float) -> void:
	_group_at(part,[at,angle,1.])

## A held weapon or shield; its art comes from the slot it is worn in.
func _held(weapon: Array) -> void:
	var art: Dictionary = worn.get("offhand" if weapon[3] == "off" else "weapon",{})
	if art.get("parts",{}).has("weapon"):
		draw_set_transform(weapon[1],deg_to_rad(weapon[2]))
		draw_texture_rect_region(art["texture"],_rects[weapon[0]+":ink"][0],art["parts"]["weapon"])
	else:
		_single(weapon[0],weapon[1],weapon[2])

func _group_at(part: String, bone: Array) -> void:
	_blit(part,"ink",bone)
	_blit(part,"fill",bone)

func _draw_bow(at: Vector2, angle: float) -> void:
	var flex := _v("draw")
	var shape := Vector2(1.+BOW_FLEX*maxf(flex,0.),1.-BOW_SHORTEN*flex)
	var turn := deg_to_rad(angle)
	var top := at + Vector2(BOW_TIP.x*shape.x,-BOW_TIP.y*shape.y).rotated(turn)
	var bottom := at + Vector2(BOW_TIP.x*shape.x,BOW_TIP.y*shape.y).rotated(turn)
	var nocked := _v("nock") > .5 and arrow_loaded
	var rest := at + Vector2(BOW_TIP.x*shape.x+minf(flex,0.)*-30.,0.).rotated(turn)
	var grip_r: Vector2 = Vector2(sockets["right_hand"][0],sockets["right_hand"][1])
	var nock: Vector2 = grip_r if _v("nock") > .5 else rest
	draw_set_transform(Vector2.ZERO)
	draw_polyline(PackedVector2Array([top,nock,bottom]),STRING_COLOR,1.8,true)
	var art: Dictionary = worn.get("weapon",{})
	draw_set_transform(at,turn,shape)
	if art.get("parts",{}).has("weapon"):
		draw_texture_rect_region(art["texture"],_rects["bow:ink"][0],art["parts"]["weapon"])
	else:
		for layer in ["ink","fill"]:
			var rects: Array = _rects["bow:"+layer]
			draw_texture_rect_region(atlas,rects[0],rects[1])
	if nocked: _single("arrow",nock,rad_to_deg((at-nock).angle()))

func _draw() -> void:
	if pose.is_empty() or atlas == null: return
	var hand_r := ["palm_r" if _v("ro") > .5 else "fist_r","hand_r"]
	var hand_l := ["palm_l" if _v("lo") > .5 else "fist_l","hand_l"]
	var far_arm := [["upper_l","upper_l"],["fore_l","fore_l"]]
	var hand_on_top := _v("lz") > .5
	if not hand_on_top: far_arm.append(hand_l)
	_group(far_arm)
	for weapon in _weapons:
		if weapon[3] == "off" and weapon[0] == "sword": _held(weapon)
	_group([["thigh_l","thigh_l"],["shin_l","shin_l"]])
	_group([["boot_l","boot_l"]])
	_group([["thigh_r","thigh_r"],["shin_r","shin_r"]])
	_group([["boot_r","boot_r"]])
	_group([["hem","hem"],["chest","chest"]])
	for weapon in _weapons:
		if weapon[3] == "off":
			if weapon[0] == "shield": _held(weapon)
			elif weapon[0] == "bow": _draw_bow(weapon[1],weapon[2])
	if hand_on_top: _group([hand_l])
	var behind := _v("wz") < .5
	if behind: _draw_main()
	var head: Array = _bones["head"]
	draw_set_transform(head[0],deg_to_rad(head[1]))
	var res := float(skeleton.res)
	var neck := Vector2(skeleton.neck_rest[0],skeleton.neck_rest[1])
	var head_rect := Rect2(Vector2(skeleton.head_box[0],skeleton.head_box[1])-neck,head_texture.get_size()/res)
	draw_texture_rect(head_texture,head_rect,false)
	var helm := _art("head")
	if not helm.is_empty(): _wear(helm,"head",head_rect)
	_group([["upper_r","upper_r"],["fore_r","fore_r"]])
	if not behind: _draw_main()
	_group([hand_r])
	draw_set_transform(Vector2.ZERO)
	if glow_visible and sockets.has(glow_socket):
		var at: Array = sockets[glow_socket]
		var point := Vector2(at[0],at[1])
		for i in 4:
			var color := glow_color
			color.a = .06+i*.07
			draw_circle(point,26.-i*6.,color,true,-1.,true)

func _draw_main() -> void:
	for weapon in _weapons:
		if weapon[3] == "main": _held(weapon)
