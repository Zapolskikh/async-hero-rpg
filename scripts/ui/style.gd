class_name Style
extends RefCounted
## All visual tokens of the UI in one place: colours, radii, sizes.
## Restyling the game should mostly mean editing this file.

# --- palette (flat mobile style) ---
const BG := Color("#1f2433")
const BG_DEEP := Color("#171b27")
const CARD := Color("#2c3346")
const CARD_2 := Color("#38405a")
const CARD_3 := Color("#465072")
const TEXT := Color("#f3f5fa")
const MUTED := Color("#9ba5bd")
const PRIMARY := Color("#ffb630")      # main call to action
const PRIMARY_TEXT := Color("#3a2500")
const SECONDARY := Color("#4a8af4")
const SUCCESS := Color("#35c779")
const DANGER := Color("#ef5b5b")
const WARNING := Color("#ffd166")
const BADGE := Color("#ff3d5a")
const HP_ALLY := Color("#4fd27b")
const HP_ENEMY := Color("#ef5b5b")

const RARITY := [Color("#8d96a8"), Color("#3f8cff"), Color("#a65cff"), Color("#ff9f1c")]
const TIER_COLORS := [Color("#6b4a4a"), Color("#465072"), Color("#2f9e64"), Color("#ffb630")]
const TIER_TEXT := [Color("#f3d0d0"), Color("#f3f5fa"), Color("#f3f5fa"), Color("#3a2500")]
const ROLE_COLORS := {
	"Герой": Color("#3f7fd6"), "Танк": Color("#5c6f8f"), "Лекарь": Color("#3fae6b"),
	"Пиромант": Color("#d2513a"), "Ядовик": Color("#6f9a2f"), "Боец": Color("#a8703c"),
	"Страж": Color("#6c7686"), "Паладин": Color("#c9a63a"), "Охотник": Color("#4f8a46"),
}

# --- shape ---
const RADIUS := 14
const RADIUS_SMALL := 9
const BUTTON_DEPTH := 5       # darker strip under buttons -> "pressable" look
const PAD := 12
const GAP := 10

# --- type ---
const FONT_BODY := 20
const FONT_SMALL := 16
const FONT_TINY := 14
const FONT_TITLE := 26
const FONT_HUGE := 34

static var _bold: FontVariation
static var _symbols: Font

## The default font in web builds has no arrows/stars/triangles; add a small
## DejaVu subset (assets/fonts/symbols.ttf) as a fallback for every font.
static func install_fonts() -> void:
	if _symbols != null:
		return
	_symbols = load("res://assets/fonts/symbols.ttf")
	var base: Font = ThemeDB.fallback_font
	var fb: Array[Font] = []
	fb.assign(base.fallbacks)
	if not fb.has(_symbols):
		fb.append(_symbols)
	base.fallbacks = fb

static func bold_font() -> Font:
	if _bold == null:
		install_fonts()
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.75
		var fb: Array[Font] = [_symbols]
		_bold.fallbacks = fb
	return _bold

static func box(color: Color, radius: int = RADIUS, pad: int = PAD) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing = true
	return sb

static func card_box(color: Color = CARD, radius: int = RADIUS, pad: int = PAD) -> StyleBoxFlat:
	var sb := box(color, radius, pad)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	return sb

## Flat button with a darker bottom edge; pressed state sinks into it.
static func button_boxes(color: Color, radius: int = RADIUS_SMALL) -> Dictionary:
	var normal := box(color, radius, 10)
	normal.border_width_bottom = BUTTON_DEPTH
	normal.border_color = color.darkened(0.32)
	normal.content_margin_bottom = 10 + BUTTON_DEPTH
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.08)
	var pressed := normal.duplicate()
	pressed.border_width_bottom = 1
	pressed.border_width_top = BUTTON_DEPTH - 1
	pressed.border_color = color.darkened(0.32)
	pressed.bg_color = color.darkened(0.06)
	var disabled := normal.duplicate()
	disabled.bg_color = Color("#4a5168")
	disabled.border_color = Color("#3a4054")
	return {"normal": normal, "hover": hover, "pressed": pressed, "disabled": disabled, "focus": StyleBoxEmpty.new()}

static func button_colors(kind: String) -> Array:
	match kind:
		"primary": return [PRIMARY, PRIMARY_TEXT]
		"secondary": return [SECONDARY, TEXT]
		"success": return [SUCCESS, Color("#062b16")]
		"danger": return [DANGER, TEXT]
		"ghost": return [CARD_2, TEXT]
	return [CARD_3, TEXT]

static func make_theme() -> Theme:
	install_fonts()
	var th := Theme.new()
	th.default_font_size = FONT_BODY
	var b := button_boxes(CARD_3)
	for k in b:
		th.set_stylebox(k, "Button", b[k])
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", TEXT)
	th.set_color("font_pressed_color", "Button", TEXT)
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.4))
	th.set_color("font_color", "Label", TEXT)
	# scroll bars: thin and quiet
	var grab := box(Color(1, 1, 1, 0.18), 4, 0)
	var track := box(Color(0, 0, 0, 0.0), 4, 0)
	for sb_name in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("grabber", sb_name, grab)
		th.set_stylebox("grabber_highlight", sb_name, grab)
		th.set_stylebox("grabber_pressed", sb_name, grab)
		th.set_stylebox("scroll", sb_name, track)
	return th
