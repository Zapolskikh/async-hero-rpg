class_name GearArt
extends RefCounted
## Worn gear from tools/build_gear_atlas.py: look -> texture and the parts in it.
## Textures load on demand, so only the gear in use takes memory.

static var _index = null
static var _worn := {}

## {"texture": Texture2D, "parts": {part: Rect2}} or empty when the look is not drawn yet.
static func find(look: String, sex: String) -> Dictionary:
	if _index == null:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/gear/gear_index.json"))
		_index = parsed if parsed is Dictionary else {}
	var bodies: Dictionary = _index.get(look, {})
	var body: String = sex if bodies.has(sex) else "any"
	if not bodies.has(body):
		return {}
	var key := look + ":" + body
	if not _worn.has(key):
		var rects := {}
		for part in bodies[body]["parts"]:
			var r: Array = bodies[body]["parts"][part]
			rects[part] = Rect2(r[0], r[1], r[2], r[3])
		_worn[key] = {"texture": load("res://assets/gear/%s.png" % bodies[body]["file"]), "parts": rects}
	return _worn[key]
