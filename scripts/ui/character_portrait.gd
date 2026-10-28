extends Control
const Actor := preload("res://scripts/ui/character_actor.gd")
var actor: CharacterActor
var flipped := false

func configure(appearance: Dictionary, look: Array, height: float, flip: bool = false, glow: String = "") -> void:
	custom_minimum_size = Vector2(height * .81, height)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	flipped = flip
	actor = Actor.new()
	actor.configure(appearance, look)
	if glow != "":
		actor.modulate = Color.WHITE.lerp(Color(glow), .15)
	add_child(actor)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if actor == null:
		return
	actor.position = Vector2(size.x * .5, size.y)
	# The pack shares eye/ground alignment: keep body height stable across weapon presets.
	var factor := minf(size.y / 350., size.x / (actor.bounds.size.x + 8.))
	var center_x := actor.bounds.get_center().x - Actor.PIVOT.x
	actor.position.x -= center_x * factor * (-1. if flipped else 1.)
	actor.scale = Vector2(-factor if flipped else factor, factor)
