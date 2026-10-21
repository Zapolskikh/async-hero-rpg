class_name UI
extends RefCounted
## Small helpers to build placeholder UI from code (no art assets needed).

const BG := Color("#1b1f27")
const PANEL := Color("#262b36")
const PANEL_LIGHT := Color("#313847")
const ACCENT := Color("#e2b04a")
const GOOD := Color("#6fcf7f")
const BAD := Color("#e5665a")
const MUTED := Color("#9aa3b2")

static func panel(color: Color = PANEL, pad: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	return p

static func label(text: String, size: int = 20, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func wrap_label(text: String, size: int = 18, color: Color = MUTED) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	return l

static func button(text: String, cb: Callable, size: int = 20, min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(min_w, 44)
	b.pressed.connect(cb)
	return b

static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s

static func expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

static func roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI"][clamp(n, 0, 6)]

static func item_line(item: Dictionary) -> String:
	var parts := []
	for a in item["affixes"]:
		parts.append(Loot.affix_text(a))
	return ", ".join(parts)

static func item_title(item: Dictionary) -> String:
	return "%s %s (ур. %d)" % [Db.RARITY_NAMES[item["rarity"]], item["name"], item["ilvl"]]

static func format_time(sec: float) -> String:
	var s := int(sec)
	if s >= 3600:
		return "%d ч %d мин" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%d мин %d с" % [s / 60, s % 60]
	return "%d с" % s
