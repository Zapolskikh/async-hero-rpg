class_name CharacterActor
extends Node2D
## Game-facing controller; poses and events are owned exclusively by CharacterRig.
const Rig := preload("res://scripts/ui/character_rig.gd")
const PIVOT := Vector2(206,400) # Hip centre of the rig; planted soles remain on y=400.
const PRESETS := ["base","sword","dual_swords","sword_shield","greatsword","bow","staff"]
signal marker(action_id: int, event_name: StringName, socket_name: StringName, socket_transform: Transform2D)
signal action_cancelled(action_id: int)
var rig: CharacterRig
var appearance := {"sex":"male","hair":"m01"}
var preset := "base"
var loadout := "unarmed"
var look: Array = []
var bounds := Rect2(120,70,280,330)
var magic_color := Color("#99cfff")
var action_serial := 0
var _auto_bow := false
var _dead := false
var _alternate := false
var _configured := false
var clip: String:
	get:
		if _dead: return "death"
		var id := rig.current_clip
		if id.begins_with("idle_"): return "idle"
		if id.begins_with("cast_begin_") or id == "staff_cast_begin": return "cast"
		if id.begins_with("cast_hold_") or id == "staff_cast_hold": return "cast_hold"
		if id.begins_with("cast_release_") or id.begins_with("cast_instant_") or id == "staff_cast_release": return "cast_release"
		if id in ["bow_draw","bow_hold"]: return "shoot" if _auto_bow else "aim_hold"
		if id == "bow_release": return "shoot"
		if id == "shield_bash": return "shield_bash"
		return "attack"
var elapsed: float:
	get: return rig.elapsed
	set(value):
		rig.elapsed = value
		rig._blend_from = PackedFloat32Array()
		rig._update_pose()

static func preset_for(layers: Array, weapons: Array = []) -> String:
	var held := weapons.duplicate()
	if held.is_empty():
		for layer in layers:
			var id := str(layer[0])
			if id.begins_with("w_"): held.append(id.trim_prefix("w_"))
			elif id == "offhand_sword": held.append("sword")
			elif id == "shield": held.append("shield")
	if "staff" in held: return "staff"
	if "bow" in held: return "bow"
	if "greatsword" in held: return "greatsword"
	if "sword" in held and "shield" in held: return "sword_shield"
	if held.count("sword") >= 2: return "dual_swords"
	return "sword" if "sword" in held else "base"

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rig = Rig.new()
	rig.default_follows = {"bow_release":"idle_bow"}
	rig.position = -PIVOT
	rig.set_process(false)
	add_child(rig)
	rig.action_event.connect(_on_marker)
	rig.clip_finished.connect(_on_finished)

func configure(value: Dictionary, layers: Array = [], weapons: Array = []) -> void:
	var next := CharacterAppearance.normalize(value)
	var next_preset := preset_for(layers,weapons)
	if _configured and next == appearance and next_preset == preset: return
	if _configured: action_cancelled.emit(action_serial)
	appearance = next
	preset = next_preset
	loadout = {"base":"unarmed","dual_swords":"dual","sword_shield":"shield"}.get(preset,preset)
	look = layers.duplicate(true)
	_alternate = false
	_auto_bow = false
	_dead = false
	if not _configured or rig.sex != appearance["sex"]: rig.set_profile(appearance["sex"])
	action_serial += 1
	rig.play_clip("idle_"+loadout,"",0.)
	rig.glow_visible = false
	rig.arrow_loaded = true
	_configured = true

func _start() -> void:
	action_cancelled.emit(action_serial)
	action_serial += 1
	_auto_bow = false
	_dead = false

func begin_magic(color: Color, preparing: bool = true) -> void:
	var prepared := clip in ["cast","cast_hold"]
	_start()
	magic_color = color
	rig.glow_color = color
	rig.glow_socket = "cast_right"
	rig.glow_visible = true
	if preparing: rig.begin_cast(loadout)
	elif prepared: rig.release_cast(loadout)
	else: rig.instant_cast(loadout)

func begin_staff_magic(color: Color, preparing: bool = true) -> void:
	var prepared := clip in ["cast","cast_hold"]
	_start()
	magic_color = color
	rig.glow_color = color
	rig.glow_socket = "staff_tip"
	rig.glow_visible = true
	if preparing: rig.play_clip("staff_cast_begin","staff_cast_hold")
	elif prepared: rig.play_clip("staff_cast_release","idle_staff")
	else:
		rig.glow_socket = "cast_right"
		rig.instant_cast("staff")

func begin_aim() -> void:
	if rig.current_clip in ["bow_draw","bow_hold"] and not _auto_bow: return
	_start()
	rig.glow_visible = false
	rig.arrow_loaded = true
	rig.play_clip("bow_draw","bow_hold")

func release_aim() -> void:
	_start()
	rig.glow_visible = false
	rig.play_clip("bow_release","idle_bow")

func cancel_cast() -> void:
	if clip not in ["cast","cast_hold","cast_release","aim_hold","shoot"]: return
	_start()
	rig.interrupt_cast(loadout)
	rig.glow_visible = false

func play(name: String) -> void:
	if name == "hit": return # Incoming-hit tint belongs to BattleView, not the casting controller.
	if name in ["cast","cast_hold"]:
		if name == "cast": begin_magic(magic_color)
		else: rig.play_clip("cast_hold_"+loadout)
		return
	if name == "cast_release":
		begin_magic(magic_color,false)
		return
	if name == "aim_hold":
		begin_aim()
		return
	_start()
	rig.glow_visible = false
	match name:
		"death":
			_dead = true
			rig.play_clip("death_"+loadout,"",.12)
		"idle", "walk": rig.play_clip("idle_"+loadout)
		"shield_bash": rig.play_clip("shield_bash","idle_"+loadout)
		"shoot":
			_auto_bow = true
			rig.arrow_loaded = true
			rig.play_clip("bow_draw","bow_release")
		"attack":
			if preset == "staff":
				rig.play_clip("idle_staff") # Staff physical thrust exists in the pack but is not an autoattack.
			elif preset == "bow":
				_auto_bow = true
				rig.arrow_loaded = true
				rig.play_clip("bow_draw","bow_release")
			elif preset == "greatsword": rig.play_clip("greatsword_slash","idle_greatsword")
			elif preset == "dual_swords":
				_alternate = not _alternate
				rig.play_clip("sword_right_slash_dual" if _alternate else "sword_left_slash","idle_dual")
			elif preset == "sword_shield": rig.play_clip("sword_right_slash_shield","idle_shield")
			elif preset == "sword": rig.play_clip("sword_right_slash","idle_sword")
			else: rig.play_clip("idle_unarmed")

func play_native(id: String, follow: String = "") -> void:
	_start()
	rig.play_clip(id,follow)

func _on_marker(event: StringName, socket: StringName, transform: Transform2D) -> void:
	if str(event) == "arrow_release": rig.arrow_loaded = false
	marker.emit(action_serial,event,socket,transform)

func _on_finished(id: StringName) -> void:
	if str(id).begins_with("cast_release_") or str(id).begins_with("cast_instant_") or str(id) == "staff_cast_release":
		rig.glow_visible = false

func advance_visual(delta: float) -> void:
	rig.advance_pose(delta)

func _process(delta: float) -> void:
	advance_visual(delta)

func socket_world(name: String) -> Transform2D:
	return rig.get_socket(name)
