class_name CharacterActor
extends Node2D
## V2 torso stays intact; weapon actions use overlapping continuous sleeves.
const Motion := preload("res://scripts/ui/weapon_motion.gd")
const ARMS_MASK := preload("res://assets/characters/v2/arms_mask.gdshader")
const ROOT := "res://assets/characters/v2/"
const PIVOT := Vector2(256,400)
const DURATIONS := {"idle":1., "walk":1., "attack":.52, "shoot":.5, "aim_hold":1., "shield_bash":.4, "cast":1., "cast_hold":1., "cast_release":.4, "hit":.5, "death":1.}
const PRESETS := ["base", "sword", "dual_swords", "sword_shield", "greatsword", "bow", "staff"]
static var _textures := {}
static var _metadata: Dictionary = {}
var appearance := {"sex":"male", "hair":"m01"}
var look: Array = []
var preset := "base"
var clip := "idle"
var elapsed := 0.
var bounds := Rect2(128, 50, 256, 350)
var body: Sprite2D
var pose: Node2D
var motion: WeaponMotion
var arms_material: ShaderMaterial
var _idle_texture: Texture2D
var _base_texture: Texture2D
var magic_color := Color("#99cfff")

func begin_magic(color: Color, preparing: bool = true) -> void:
	magic_color = color
	var was_preparing := clip in ["cast","cast_hold"]
	play("cast" if preparing else "cast_release")
	if not preparing and was_preparing:
		elapsed = DURATIONS["cast_release"] * .3
	_apply_pose()

static func preset_for(layers: Array, weapons: Array = []) -> String:
	var held := weapons.duplicate()
	if held.is_empty():
		for layer in layers:
			var id := str(layer[0])
			if id.begins_with("w_"):
				held.append(id.trim_prefix("w_"))
			elif id == "offhand_sword":
				held.append("sword")
			elif id == "shield":
				held.append("shield")
	if "staff" in held:
		return "staff"
	if "bow" in held:
		return "bow"
	if "greatsword" in held:
		return "greatsword"
	if "sword" in held and "shield" in held:
		return "sword_shield"
	if held.count("sword") >= 2:
		return "dual_swords"
	return "sword" if "sword" in held else "base"

static func metadata() -> Dictionary:
	if _metadata.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
		for item in data["variants"]:
			_metadata[item["sex"] + "/" + item["id"]] = item
	return _metadata

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pose = Node2D.new()
	add_child(pose)
	body = Sprite2D.new()
	body.centered = false
	body.position = -PIVOT
	pose.add_child(body)
	arms_material = ShaderMaterial.new()
	arms_material.shader = ARMS_MASK
	motion = Motion.new()
	motion.position = -PIVOT
	pose.add_child(motion)

func configure(value: Dictionary, layers: Array = [], weapons: Array = []) -> void:
	appearance = CharacterAppearance.normalize(value)
	arms_material.set_shader_parameter("female",appearance["sex"] == "female")
	look = layers.duplicate(true)
	preset = preset_for(look, weapons)
	var key: String = appearance["sex"] + "/" + preset
	if not _textures.has(key):
		_textures[key] = load(ROOT + "sprites/" + key + ".png")
	_idle_texture = _textures[key]
	var base_key: String = appearance["sex"] + "/base"
	if not _textures.has(base_key):
		_textures[base_key] = load(ROOT + "sprites/" + base_key + ".png")
	_base_texture = _textures[base_key]
	var rect: Array = metadata()[key]["alignment"]["bounds"]
	bounds = Rect2(rect[0], rect[1], rect[2] - rect[0], rect[3] - rect[1])
	if preset == "bow":
		bounds = Rect2(140,90,200,310)
	_apply_pose()

func play(name: String) -> void:
	if name == "attack":
		if preset == "staff":
			name = "cast"
		elif preset == "bow":
			name = "shoot"
	if name not in DURATIONS:
		return
	clip = name
	elapsed = 0.
	_apply_pose()

func _process(delta: float) -> void:
	elapsed += delta
	if clip not in ["idle", "walk", "cast_hold", "aim_hold", "death"] and elapsed >= DURATIONS[clip]:
		clip = "idle"
		elapsed = 0.
	_apply_pose()

func _apply_pose() -> void:
	# The torso is never stretched or split into V1 joints.
	pose.position = Vector2.ZERO
	pose.rotation = 0.
	var phase := clampf(elapsed / DURATIONS[clip], 0., 1.)
	motion.preset = preset
	motion.sex = appearance["sex"]
	motion.clip = clip
	motion.phase = phase
	motion.magic_color = magic_color
	motion.active = preset == "bow" or clip in ["cast","cast_hold","cast_release"] or (clip in ["attack", "shoot", "shield_bash"] and preset in ["sword","dual_swords","sword_shield","greatsword"])
	body.texture = _base_texture if motion.active else _idle_texture
	body.material = arms_material if motion.active else null
	motion.queue_redraw()
	match clip:
		"idle": pose.position.y = -sin(elapsed * TAU) * 1.2
		"walk": pose.position.y = -absf(sin(elapsed * TAU * 2.)) * 4.
		"attack": pose.rotation = sin(phase * PI) * .025
		"cast", "cast_hold": pose.position.y = -sin(elapsed * TAU) * 2.
		"hit": pose.position.x = sin(phase * TAU * 2.) * (1. - phase) * 7.
		"death": pose.rotation = -PI * .5 * smoothstep(0., 1., phase)
