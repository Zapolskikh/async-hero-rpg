class_name UI
extends RefCounted
## Reusable UI building blocks. Colours and sizes come from Style.

# kept for the battle view
const GOOD := Style.HP_ALLY
const BAD := Style.HP_ENEMY
const ACCENT := Style.PRIMARY
const MUTED := Style.MUTED

static var _icons := {}

static func icon_tex(name: String) -> Texture2D:
	if not _icons.has(name):
		var path := "res://assets/icons/%s.png" % name
		_icons[name] = load(path) if ResourceLoader.exists(path) else null
	return _icons[name]

static var _big_icons := {}

## Icon upscaled with nearest filtering for places that draw textures at
## native size (button icons).
static func icon_tex_px(name: String, px: int) -> Texture2D:
	var key := "%s@%d" % [name, px]
	if not _big_icons.has(key):
		var t := icon_tex(name)
		if t == null:
			_big_icons[key] = null
		else:
			var img := t.get_image()
			if img.is_compressed():
				img.decompress()
			img.resize(px, px, Image.INTERPOLATE_NEAREST)
			_big_icons[key] = ImageTexture.create_from_image(img)
	return _big_icons[key]

# ---------------- containers ----------------

static func card(color: Color = Style.CARD, pad: int = Style.PAD, radius: int = Style.RADIUS) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.card_box(color, radius, pad))
	return p

static func flat(color: Color, pad: int = 8, radius: int = Style.RADIUS_SMALL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.box(color, radius, pad))
	return p

static func hbox(sep: int = Style.GAP) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func vbox(sep: int = Style.GAP) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func grid(columns: int, sep: int = Style.GAP) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", sep)
	g.add_theme_constant_override("v_separation", sep)
	return g

static func scroll(child: Control, horizontal: bool = false) -> ScrollContainer:
	var s := ScrollContainer.new()
	if horizontal:
		s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	else:
		s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s

static func spacer(w: float = 0.0, h: float = 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	if w == 0.0 and h == 0.0:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

static func center(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.add_child(c)
	return cc

static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

# ---------------- text ----------------

static func label(text: String, size: int = Style.FONT_BODY, color: Color = Style.TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", Style.bold_font())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func title(text: String, size: int = Style.FONT_TITLE, color: Color = Style.TEXT) -> Label:
	return label(text, size, color, true)

static func wrap(text: String, size: int = Style.FONT_SMALL, color: Color = Style.MUTED, bold: bool = false) -> Label:
	var l := label(text, size, color, bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 60
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

# ---------------- icons ----------------

static func icon(name: String, size: float = 32.0, tint: Color = Color.WHITE) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon_tex(name)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.modulate = tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Pixel-art portrait of a unit sprite, scaled with nearest filtering.
static func portrait(sprite: String, height: float = 84.0, flip: bool = false) -> TextureRect:
	var path := "res://assets/units/%s.png" % sprite
	var r := TextureRect.new()
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.flip_h = flip
	r.custom_minimum_size = Vector2(height * 0.81, height)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(path):
		r.texture = load(path)
	return r

## Portrait on a rounded coloured square (avatar style).
static func avatar(sprite: String, bg: Color, size: float = 96.0, flip: bool = false) -> PanelContainer:
	var p := flat(bg, 2, int(size * 0.18))
	p.custom_minimum_size = Vector2(size, size)
	p.add_child(portrait(sprite, size * 0.92, flip))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## Rounded tile with an icon in the middle, coloured by rarity/kind.
## Returns a plain Control so badges/chips can be positioned freely on top;
## the coloured panel is available as get_meta("panel").
static func tile(icon_name: String, bg: Color, size: float = 72.0, dim: bool = false, selected: bool = false) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := PanelContainer.new()
	var base := bg if not dim else Color("#3a4054")
	var sb := Style.box(base.darkened(0.12), Style.RADIUS_SMALL + 2, 6)
	sb.border_width_bottom = 4
	sb.border_color = base.darkened(0.45)
	if selected:
		sb.border_width_left = 3
		sb.border_width_right = 3
		sb.border_width_top = 3
		sb.border_color = Color.WHITE
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := icon(icon_name, size * 0.62, Color(1, 1, 1, 0.35) if dim else Color.WHITE)
	p.add_child(ic)
	holder.add_child(p)
	holder.set_meta("panel", p)
	return holder

# ---------------- buttons ----------------

static func btn(text: String, cb: Callable, kind: String = "ghost", size: int = Style.FONT_BODY,
		icon_name: String = "", min_w: float = 0.0, min_h: float = 52.0) -> Button:
	var b := Button.new()
	b.text = text
	var cols := Style.button_colors(kind)
	var boxes := Style.button_boxes(cols[0])
	for k in boxes:
		b.add_theme_stylebox_override(k, boxes[k])
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, cols[1])
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", Style.bold_font())
	b.custom_minimum_size = Vector2(min_w, min_h)
	if icon_name != "":
		b.icon = icon_tex_px(icon_name, int(size * 1.5))
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.pressed.connect(cb)
	return b

## Invisible full-size button laid over a card to make the whole card tappable.
static func tap_overlay(parent: Control, cb: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	var empty := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, empty)
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

# ---------------- small widgets ----------------

## Icon + number on a dark rounded pill (currencies, stats).
static func pill(icon_name: String, text: String, size: int = Style.FONT_BODY, bg: Color = Style.BG_DEEP) -> PanelContainer:
	var p := flat(bg, 6, 20)
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.content_margin_left = 8
	sb.content_margin_right = 14
	var h := hbox(6)
	p.add_child(h)
	h.add_child(icon(icon_name, size * 1.3))
	h.add_child(label(text, size, Style.TEXT, true))
	return p

static func chip(text: String, color: Color, size: int = Style.FONT_TINY, text_color: Color = Style.TEXT) -> PanelContainer:
	var p := flat(color, 4, 12)
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	p.add_child(label(text, size, text_color, true))
	return p

static func progress(value: float, max_value: float, color: Color, height: float = 10.0, width: float = 0.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = max(1.0, max_value)
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, height)
	bar.add_theme_stylebox_override("background", Style.box(Style.BG_DEEP, int(height / 2.0), 0))
	bar.add_theme_stylebox_override("fill", Style.box(color, int(height / 2.0), 0))
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar

## Red notification dot. By default in the top-right corner of `parent`;
## with `near_center` it sits just right of the parent's top centre (tab icons).
static func badge(parent: Control, text: String = "", near_center: bool = false) -> void:
	var p := flat(Style.BADGE, 0, 11)
	p.custom_minimum_size = Vector2(22, 22)
	p.size = Vector2(22, 22)
	if text != "":
		var l := label(text, 13, Color.WHITE, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(l)
	if near_center:
		p.anchor_left = 0.5
		p.anchor_right = 0.5
		p.offset_left = 14
		p.offset_right = 36
		p.offset_top = 4
		p.offset_bottom = 26
	else:
		p.anchor_left = 1.0
		p.anchor_right = 1.0
		p.offset_left = -14
		p.offset_right = 8
		p.offset_top = -8
		p.offset_bottom = 14
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)

static func stat_row(icon_name: String, name: String, value: String) -> HBoxContainer:
	var h := hbox(8)
	h.add_child(icon(icon_name, 26))
	h.add_child(expand(label(name, Style.FONT_SMALL, Style.MUTED)))
	h.add_child(label(value, Style.FONT_BODY, Style.TEXT, true))
	return h

# ---------------- text helpers ----------------

static func roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI"][clamp(n, 0, 6)]

static func spell_icon(sid: String) -> String:
	return "sp_" + sid

static func item_icon(item: Dictionary) -> String:
	return "item_" + str(item["slot"])

static func stat_icon(stat: String) -> String:
	return {"hp": "hp", "atk": "atk", "power": "power", "armor": "armor", "haste": "haste", "crit": "crit"}.get(stat, "star")

static func item_line(item: Dictionary) -> String:
	var parts := []
	for a in item["affixes"]:
		parts.append(Loot.affix_text(a))
	return ", ".join(parts)

static func item_title(item: Dictionary) -> String:
	return str(item["name"])

static func format_time(sec: float) -> String:
	var s := int(sec)
	if s >= 3600:
		return "%d ч %d мин" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%d мин %d с" % [s / 60, s % 60]
	return "%d с" % s
