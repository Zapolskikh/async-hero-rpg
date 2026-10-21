extends Control
## Draws the live battle of Game.expedition with placeholder shapes.
## Allies on the left (frontline nearest the centre), enemies on the right.

const UNIT_SIZE := Vector2(84, 112)
const BOSS_SIZE := Vector2(120, 160)
const FLOAT_LIFE := 1.1

var floats: Array = []        # {text, color, uid, life, offset, size}
var flashes := {}             # uid -> time left
var _sim_ref: BattleSim = null

func _process(delta: float) -> void:
	var ex: Expedition = Game.expedition
	if ex != null and ex.sim != null:
		if ex.sim != _sim_ref:
			_sim_ref = ex.sim
			floats.clear()
			flashes.clear()
		_consume_events(ex.sim)
	for f in floats.duplicate():
		f["life"] -= delta
		if f["life"] <= 0.0:
			floats.erase(f)
	for k in flashes.keys():
		flashes[k] -= delta
		if flashes[k] <= 0.0:
			flashes.erase(k)
	queue_redraw()

func _consume_events(sim: BattleSim) -> void:
	for e in sim.events:
		match e["t"]:
			"dmg":
				var col := Color("#ffd27a") if e.get("dot", false) else Color.WHITE
				if e.get("crit", false):
					col = Color("#ff7b4a")
				_float(e["uid"], ("%d" % e["v"]) + ("!" if e.get("crit", false) else ""), col, 24 if e.get("crit", false) else 19)
				flashes[e["uid"]] = 0.12
			"heal":
				_float(e["uid"], "+%d" % e["v"], UI.GOOD, 20)
			"absorb":
				_float(e["uid"], "(%d)" % e["v"], Color("#9fd7ff"), 17)
			"shield":
				_float(e["uid"], "Щит", Color("#9fd7ff"), 18)
			"interrupt":
				_float(e["uid"], e["text"], Color("#ff5ad1"), 24)
			"status":
				_float(e["uid"], e["text"], Color("#c9b6ff"), 18)
			"spell":
				_float(e["uid"], e["text"], UI.ACCENT, 17, -40.0)
			"death":
				_float(e["uid"], "Пал", UI.BAD, 22)
	sim.events.clear()
	if floats.size() > 60:
		floats = floats.slice(floats.size() - 60)

func _float(uid: int, text: String, col: Color, size: int, y_off: float = 0.0) -> void:
	var stack := 0
	for f in floats:
		if f["uid"] == uid and f["life"] > FLOAT_LIFE - 0.35:
			stack += 1
	floats.append({"text": text, "color": col, "uid": uid, "life": FLOAT_LIFE,
		"offset": Vector2(0, y_off - stack * 22), "size": size})

func unit_rect(u: BattleUnit) -> Rect2:
	var sz := BOSS_SIZE if u.is_boss else UNIT_SIZE
	var mid := size.x / 2.0
	var gap: float = min(115.0, (mid - 60.0) / 4.0)
	var ground := size.y * 0.72
	var x: float
	if u.side == 0:
		x = mid - 70.0 - u.slot * gap - sz.x / 2.0
	else:
		x = mid + 70.0 + u.slot * gap - sz.x / 2.0
	return Rect2(Vector2(x, ground - sz.y), sz)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#cfe3ef"))
	draw_rect(Rect2(Vector2(0, size.y * 0.72), Vector2(size.x, size.y * 0.28)), Color("#b9a06a"))
	draw_line(Vector2(0, size.y * 0.72), Vector2(size.x, size.y * 0.72), Color("#7d6a3f"), 3.0)
	var font := ThemeDB.fallback_font
	var ex: Expedition = Game.expedition
	if ex == null or ex.sim == null:
		draw_string(font, Vector2(40, 80), "Нет активного похода", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.BLACK)
		return
	for u in ex.sim.units:
		_draw_unit(u, font)
	for f in floats:
		var u := ex.sim.unit_by_uid(f["uid"])
		if u == null:
			continue
		var r := unit_rect(u)
		var t: float = 1.0 - f["life"] / FLOAT_LIFE
		var pos: Vector2 = Vector2(r.position.x + r.size.x / 2.0, r.position.y - 46.0) + f["offset"] + Vector2(0, -36.0 * t)
		var col: Color = f["color"]
		col.a = clamp(f["life"] / FLOAT_LIFE * 1.6, 0.0, 1.0)
		var w := font.get_string_size(f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, f["size"]).x
		draw_string_outline(font, pos - Vector2(w / 2.0, 0), f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, f["size"], 4, Color(0, 0, 0, col.a))
		draw_string(font, pos - Vector2(w / 2.0, 0), f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, f["size"], col)
	if ex.pause > 0.0:
		var msg := "Волна %d / %d" % [ex.wave_index + 1, ex.total_waves()]
		var w := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		draw_string_outline(font, Vector2(size.x / 2.0 - w / 2.0, size.y * 0.35), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, 6, Color.BLACK)
		draw_string(font, Vector2(size.x / 2.0 - w / 2.0, size.y * 0.35), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, UI.ACCENT)

func _draw_unit(u: BattleUnit, font: Font) -> void:
	var r := unit_rect(u)
	var base := u.color
	if not u.alive():
		draw_rect(Rect2(r.position + Vector2(0, r.size.y - 18), Vector2(r.size.x, 18)), Color(0.3, 0.3, 0.3, 0.6))
		draw_string(font, Vector2(r.position.x, r.end.y + 22), u.name, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16, Color(0.2, 0.2, 0.2, 0.7))
		return
	if flashes.has(u.uid):
		base = base.lerp(Color.WHITE, 0.6)
	if u.stun > 0.0:
		base = base.darkened(0.35)
	draw_rect(r, base)
	draw_rect(r, Color.BLACK, false, 2.0)
	# "face" to show which way the unit looks
	var eye_x := r.end.x - 22.0 if u.side == 0 else r.position.x + 14.0
	draw_rect(Rect2(Vector2(eye_x, r.position.y + 18.0), Vector2(8, 8)), Color.BLACK)
	if u.shield > 0.0:
		draw_rect(r.grow(5.0), Color("#7fc8ff"), false, 4.0)
	if u.taunt > 0.0:
		draw_string(font, Vector2(r.position.x + 4, r.position.y + r.size.y - 8), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("#ff3b3b"))
	# status markers: small coloured dots along the bottom of the unit
	var marks := []
	for d in u.dots:
		marks.append(Color("#7ccf3a") if d["id"] in ["poison_cloud", "e_venom"] else Color("#ff8a2a"))
	if u.hots.size() > 0:
		marks.append(Color("#b6ffb0"))
	if u.stun > 0.0:
		marks.append(Color("#ffe14a"))
	for i in marks.size():
		var c := Vector2(r.position.x + 12.0 + i * 16.0, r.end.y - 12.0)
		draw_circle(c, 6.0, marks[i])
		draw_arc(c, 6.0, 0.0, TAU, 12, Color.BLACK, 1.5)
	# HP bar above the unit
	var bar := Rect2(Vector2(r.position.x - 6, r.position.y - 26), Vector2(r.size.x + 12, 12))
	draw_rect(bar, Color(0, 0, 0, 0.7))
	var hp_w := bar.size.x * u.hp_frac()
	draw_rect(Rect2(bar.position, Vector2(hp_w, bar.size.y)), UI.GOOD if u.side == 0 else UI.BAD)
	if u.shield > 0.0:
		var sw: float = min(bar.size.x, bar.size.x * u.shield / u.max_hp)
		draw_rect(Rect2(bar.position + Vector2(0, bar.size.y - 4), Vector2(sw, 4)), Color("#bfe6ff"))
	draw_string(font, Vector2(bar.position.x, bar.position.y - 4), u.name, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 16, Color.BLACK)
	# cast bar below the unit
	if u.is_casting():
		var c := u.casting
		var cb := Rect2(Vector2(r.position.x - 6, r.end.y + 8), Vector2(r.size.x + 12, 14))
		draw_rect(cb, Color(0, 0, 0, 0.75))
		var frac: float = 1.0 - c["remaining"] / c["total"]
		var col := Color("#f0a23a") if c.get("interruptible", true) else Color("#9a9a9a")
		draw_rect(Rect2(cb.position, Vector2(cb.size.x * frac, cb.size.y)), col)
		var sname: String = Db.SPELLS[c["spell"]]["name"]
		draw_string(font, Vector2(cb.position.x - 20, cb.end.y + 18), sname, HORIZONTAL_ALIGNMENT_CENTER, cb.size.x + 40, 15, Color.BLACK)
