class_name CharacterActor
extends Node2D
## Animated body sheet with swappable hair attached to the per-frame head pose.
const ROOT := "res://assets/characters/"
const SHADER := preload("res://assets/characters/body.gdshader")
const COUNTS := {"idle":24, "walk":24, "attack":16, "cast":24, "cast_hold":24, "hit":12, "death":24}
static var _textures := {}
static var _attachments := {}
var appearance := {"sex":"male", "hair":"m01"}
var look: Array = []
var clip := "idle"
var elapsed := 0.
var body: Sprite2D
var hair_back: Sprite2D
var hair_front: Sprite2D
var equipment: GearLayer
var _key := ""
var _last_frame := -1

class GearLayer extends Node2D:
	var look: Array = []
	var pose := {}
	func _draw() -> void:
		for layer in look:
			var item := str(layer[0])
			if not (item.begins_with("w_") or item in ["shield", "offhand_sword"]):
				continue
			var point: Dictionary = pose.get("hand_far" if item in ["shield", "offhand_sword"] else "hand_near", {})
			if point.is_empty():
				continue
			draw_set_transform(Vector2(point["x"] - 128., point["y"] - 225.), deg_to_rad(point["angle"]))
			var steel := Color("#cbd5df")
			var edge := Color("#303745")
			if item == "shield":
				draw_colored_polygon(PackedVector2Array([Vector2(-16,-22),Vector2(16,-22),Vector2(14,8),Vector2(0,22),Vector2(-14,8)]), edge)
				draw_colored_polygon(PackedVector2Array([Vector2(-12,-18),Vector2(12,-18),Vector2(10,6),Vector2(0,16),Vector2(-10,6)]), Color("#397ec0"))
				draw_line(Vector2(0,-17),Vector2(0,15),Color("#e7bb54"),4,true)
			elif item == "w_bow":
				draw_arc(Vector2(-16, -10), 38, -PI/2., PI/2., 20, Color("#ac793e"),5,true)
				draw_line(Vector2(-16,-48),Vector2(-16,28),Color("#e7dfc3"),1.5,true)
			elif item == "w_staff":
				draw_line(Vector2(0,28),Vector2(0,-75),Color("#6f482f"),6,true)
				draw_circle(Vector2(0,-75),10,edge)
				draw_circle(Vector2(0,-75),7,Color("#b07ce3"))
			else:
				var length := 90. if item == "w_greatsword" else 60.
				draw_line(Vector2(0,12),Vector2(0,-length),edge,10,true)
				draw_line(Vector2(0,-8),Vector2(0,-length+3),steel,6,true)
				draw_line(Vector2(-12,-6),Vector2(12,-6),Color("#d9ac49"),5,true)
				draw_line(Vector2(0,-3),Vector2(0,12),Color("#70472d"),6,true)
		draw_set_transform(Vector2.ZERO)

static func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(ROOT + path)
	return _textures[path]

static func attachments(sex: String) -> Dictionary:
	if not _attachments.has(sex):
		_attachments[sex] = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "animations/" + sex + "/attachments.json"))
	return _attachments[sex]

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	hair_back = Sprite2D.new()
	body = Sprite2D.new()
	hair_front = Sprite2D.new()
	for sprite in [hair_back, body, hair_front]:
		sprite.centered = false
		add_child(sprite)
	body.position = Vector2(-128,-225)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	body.material = mat
	hair_back.offset = Vector2(-64,-72)
	hair_front.offset = Vector2(-64,-72)
	hair_back.modulate = Color("#714b29")
	hair_front.modulate = hair_back.modulate
	equipment = GearLayer.new()
	add_child(equipment)

func configure(value: Dictionary, layers: Array = []) -> void:
	appearance = CharacterAppearance.normalize(value)
	look = layers.duplicate(true)
	equipment.look = look
	var sex: String = appearance["sex"]
	var hair: String = appearance["hair"]
	hair_back.texture = texture("hair/%s/%s_back.png" % [sex, hair])
	hair_front.texture = texture("hair/%s/%s_front.png" % [sex, hair])
	_key = ""
	_update_frame()

func play(name: String) -> void:
	if name not in COUNTS:
		return
	clip = name
	elapsed = 0.
	_update_frame()

func _process(delta: float) -> void:
	elapsed += delta
	if clip not in ["idle", "walk", "cast_hold", "death"] and elapsed >= COUNTS[clip] / 24.:
		play("idle")
	_update_frame()

func _update_frame() -> void:
	var sex: String = appearance["sex"]
	var key := sex + "/" + clip
	if key != _key:
		body.texture = texture("animations/%s/%s.png" % [sex, clip])
		body.hframes = COUNTS[clip]
		body.material.set_shader_parameter("skin_mask", texture("animations/%s/%s_skin_mask.png" % [sex, clip]))
		_key = key
		_last_frame = -1
	var frame := int(elapsed * 24.)
	frame = frame % COUNTS[clip] if clip in ["idle", "walk", "cast_hold"] else mini(frame, COUNTS[clip] - 1)
	if frame == _last_frame:
		return
	_last_frame = frame
	body.frame = frame
	var pose: Dictionary = attachments(sex)[clip][frame]
	var head: Dictionary = pose["head"]
	for hair in [hair_back, hair_front]:
		hair.position = Vector2(head["x"] - 128., head["y"] - 225.)
		hair.rotation = deg_to_rad(head["angle"])
	equipment.pose = pose
	equipment.queue_redraw()
