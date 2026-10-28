class_name CharacterActor
extends Node2D
## V2 art remains indivisible: no V1 joints, bone transforms or drawn weapons.
const ROOT := "res://assets/characters/v2/"
const PIVOT := Vector2(256,400)
const DURATIONS := {"idle":1., "walk":1., "attack":2./3., "cast":1., "cast_hold":1., "hit":.5, "death":1.}
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

func configure(value: Dictionary, layers: Array = [], weapons: Array = []) -> void:
	appearance = CharacterAppearance.normalize(value)
	look = layers.duplicate(true)
	preset = preset_for(look, weapons)
	var key: String = appearance["sex"] + "/" + preset
	if not _textures.has(key):
		_textures[key] = load(ROOT + "sprites/" + key + ".png")
	body.texture = _textures[key]
	var rect: Array = metadata()[key]["alignment"]["bounds"]
	bounds = Rect2(rect[0], rect[1], rect[2] - rect[0], rect[3] - rect[1])
	_apply_pose()

func play(name: String) -> void:
	if name not in DURATIONS:
		return
	clip = name
	elapsed = 0.
	_apply_pose()

func _process(delta: float) -> void:
	elapsed += delta
	if clip not in ["idle", "walk", "cast_hold", "death"] and elapsed >= DURATIONS[clip]:
		clip = "idle"
		elapsed = 0.
	_apply_pose()

func _apply_pose() -> void:
	# Uniform whole-sprite motion preserves the exact art and weapon grip.
	pose.position = Vector2.ZERO
	pose.rotation = 0.
	var phase := clampf(elapsed / DURATIONS[clip], 0., 1.)
	match clip:
		"idle": pose.position.y = -sin(elapsed * TAU) * 1.2
		"walk": pose.position.y = -absf(sin(elapsed * TAU * 2.)) * 4.
		"attack": pose.rotation = sin(phase * PI) * .055
		"cast", "cast_hold": pose.position.y = -sin(elapsed * TAU) * 2.
		"hit": pose.position.x = sin(phase * TAU * 2.) * (1. - phase) * 7.
		"death": pose.rotation = -PI * .5 * smoothstep(0., 1., phase)
