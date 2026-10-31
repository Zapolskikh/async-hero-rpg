extends Control
## Root UI: top resource bar, screen area, bottom navigation, battle "Watch"
## layer, modal popups and toasts. Everything is built from code; colours and
## sizes live in Style, reusable widgets in UI.

const BattleView := preload("res://scripts/ui/battle_view.gd")

const TABS := [
	["expedition", "Поход", "nav_map"],
	["hero", "Герой", "nav_hero"],
	["mercs", "Наёмники", "nav_mercs"],
	["spells", "Заклинания", "nav_spells"],
	["crafts", "Ремёсла", "nav_crafts"],
	["bag", "Сумка", "nav_bag"],
]

var current_tab := "expedition"
var selected_level := 1
var _built_tab := ""         # tab whose content is on screen (scroll is kept when rebuilding the same tab)
var bag_sort := "level"     # bag order: level / rarity / type
var selected_item := ""
var spell_group := "all"

var top_bar: PanelContainer
var nav_bar: PanelContainer
var content: MarginContainer
var exp_status: Label
var watch_layer: Control
var watch_label: Label
var battle_view: Control
const METER_HEIGHT := 165.0  # space the battle meters take at the bottom of the watch screen
var meter_rows: Array = []   # [{root, bar, name, value}] damage meter in the watch screen
var heal_rows: Array = []    # same for the healing meter
var popup_layer: Control
var toast_layer: Control
var speed_buttons: Array = []

func _ready() -> void:
	theme = Style.make_theme()
	var bg := ColorRect.new()
	bg.color = Style.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := UI.vbox(0)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	top_bar = PanelContainer.new()
	top_bar.add_theme_stylebox_override("panel", Style.box(Style.BG_DEEP, 0, 8))
	root.add_child(top_bar)
	content = MarginContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		content.add_theme_constant_override("margin_" + side, 12)
	root.add_child(content)
	nav_bar = PanelContainer.new()
	nav_bar.add_theme_stylebox_override("panel", Style.box(Style.BG_DEEP, 0, 6))
	root.add_child(nav_bar)

	_build_watch_layer()
	popup_layer = Control.new()
	popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(popup_layer)
	toast_layer = Control.new()
	toast_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_layer)

	selected_level = min(Game.closed_level + 1, Db.level_count())
	if Game.exp_info() != null:
		selected_level = int(Game.exp_info()["level"])
	Game.changed.connect(_refresh)
	Game.online_changed.connect(_refresh)
	Game.expedition_finished.connect(_on_expedition_finished)
	Game.report.connect(_on_report)
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.timeout.connect(_tick_status)
	add_child(t)
	_refresh()
	if not Game.offline_report.is_empty():
		_show_offline_report(Game.offline_report)
		Game.offline_report = {}
	for a in OS.get_cmdline_user_args():
		if a == "--qa-combat":
			add_child(load("res://tests/combat_visual_runner.gd").new())
			break
		if a.begins_with("--online-test="):
			add_child(load("res://tests/online_runner.gd").new())
			break
		if a.begins_with("--shots"):
			add_child(load("res://tests/shot_runner.gd").new())
			break


# =====================================================================
# Frame: top bar, bottom navigation, screen switching
# =====================================================================

func _switch(tab: String) -> void:
	if tab == current_tab:
		return
	current_tab = tab
	if tab == "expedition" and Game.exp_info() != null:
		selected_level = int(Game.exp_info()["level"])   # show the running expedition
	_refresh()
	content.modulate.a = 0.0
	create_tween().tween_property(content, "modulate:a", 1.0, 0.15)

func _refresh() -> void:
	if not Game.level_unlocked(selected_level):
		selected_level = min(Game.closed_level + 1, Db.level_count())
	_build_top_bar()
	_build_nav()
	var keep := UI.scroll_state(content) if current_tab == _built_tab else []
	_built_tab = current_tab
	UI.clear(content)
	exp_status = null
	match current_tab:
		"expedition": content.add_child(_screen_expedition())
		"hero": content.add_child(_screen_hero())
		"mercs": content.add_child(_screen_mercs())
		"spells": content.add_child(_screen_spells())
		"crafts":
			var cs := CraftsScreen.new()
			cs.main = self
			content.add_child(cs)
		"bag": content.add_child(_screen_bag())
	UI.restore_scrolls(content, keep)

func _build_top_bar() -> void:
	UI.clear(top_bar)
	var h := UI.hbox(12)
	top_bar.add_child(h)
	var hero: Dictionary = Game.hero
	var av := UI.avatar("hero", Style.ROLE_COLORS["Герой"], 56, false, Game.hero_snapshot()["look"], Game.hero_snapshot()["appearance"])
	h.add_child(av)
	UI.tap_overlay(av, _switch.bind("hero"))
	var who := UI.vbox(2)
	who.add_child(UI.label("%s · ур. %d" % [hero["name"], hero["level"]], Style.FONT_BODY, Style.TEXT, true))
	who.add_child(UI.progress(hero["xp"], Db.xp_to_next(hero["level"]), Style.SECONDARY, 10, 170))
	h.add_child(who)
	h.add_child(UI.spacer())
	var ex = Game.exp_info()
	if ex != null:
		var mode := "Фарм" if ex["mode"] == "farm" else "Штурм"
		var sp := ("  ×%d" % int(Game.watch_speed)) if Game.watch_speed > 1.0 and not Game.is_online() else ""
		var ep := UI.pill("loop" if ex["mode"] == "farm" else "swords", "%s · ур. %d%s" % [mode, ex["level"], sp], Style.FONT_SMALL, Style.CARD)
		UI.tap_overlay(ep, _go_to_expedition)
		h.add_child(ep)
	h.add_child(UI.pill("gold", str(Game.gold)))
	var cr := UI.pill("crystal", "%d  +" % Game.crystals, Style.FONT_BODY, Color("#3a2f5a"))
	UI.tap_overlay(cr, _shop_popup)
	h.add_child(cr)
	h.add_child(UI.pill("box", str(Game.boxes)))
	if Game.is_online():
		var on := UI.pill("online", "…" if Game.busy else "Онлайн", Style.FONT_SMALL, Color("#1f4a35"))
		h.add_child(on)
	var gear := UI.btn("", _settings_popup, "ghost", Style.FONT_BODY, "settings", 52, 52)
	h.add_child(gear)

func _build_nav() -> void:
	UI.clear(nav_bar)
	var h := UI.hbox(6)
	nav_bar.add_child(h)
	var badges := _nav_badges()
	for t in TABS:
		var id: String = t[0]
		var active := id == current_tab
		var b := Button.new()
		b.text = t[1]
		b.icon = UI.icon_tex(t[2])
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 36)
		b.add_theme_font_size_override("font_size", Style.FONT_SMALL)
		b.add_theme_font_override("font", Style.bold_font())
		b.custom_minimum_size = Vector2(0, 76)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := Style.box(Style.CARD_2 if active else Color(0, 0, 0, 0), Style.RADIUS, 6)
		if active:
			sb.border_width_top = 4
			sb.border_color = Style.PRIMARY
		for k in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(k, sb)
		var fc := Style.PRIMARY if active else Style.MUTED
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(k, fc)
		b.pressed.connect(_switch.bind(id))
		if badges.get(id, false):
			UI.badge(b, "", true)
		h.add_child(b)

## Red dots: something on that screen is waiting for the player.
func _nav_badges() -> Dictionary:
	var ex = Game.exp_info()
	var bag_upgrade := false
	for it in Game.inventory:
		if Game.power_with(it) > Game.power_now():
			bag_upgrade = true
			break
	var fusable := false
	for sid in Game.collection:
		if Game.can_fuse(sid):
			fusable = true
	return {
		"expedition": ex == null or (ex["mode"] == "farm" and Game.has_pending()),
		"hero": Game.hero["rotation"].size() < 3 or Talents.points_free(Game.hero) > 0,
		"mercs": not Game.party_ready(),
		"spells": Game.free_box_available() or Game.boxes > 0 or fusable,
		"bag": bag_upgrade or (Game.profile["merging"] != null and Game.now() >= float(Game.profile["merging"]["ends_at"])),
		"crafts": CraftsScreen.has_ready(),
	}

# =====================================================================
# Screen: Expedition (campaign path + live battle + level card)
# =====================================================================

func _screen_expedition() -> Control:
	var v := UI.vbox(12)
	v.add_child(_campaign_path())
	var row := UI.hbox(12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	row.add_child(_battle_card())
	row.add_child(_level_card())
	return v

func _campaign_path() -> Control:
	var c := UI.card(Style.CARD, 10)
	var h := UI.hbox(0)
	var focus: Control = null
	for lvl in range(1, Db.level_count() + 1):
		var ch: Dictionary = Db.chapter_of(lvl)
		if ch["from"] == lvl:
			h.add_child(_chapter_marker(ch))
		elif lvl > 1:
			var line := ColorRect.new()
			line.custom_minimum_size = Vector2(26, 6)
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.color = Style.SUCCESS if Game.level_unlocked(lvl) else Style.CARD_3
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(line)
		var node := _path_node(lvl)
		if lvl == selected_level:
			focus = node
		h.add_child(node)
	var s := UI.scroll(h, true)
	s.custom_minimum_size.y = 92
	c.add_child(s)
	if focus != null:
		_scroll_path_to.call_deferred(s, focus)
	return c

## Chapter title between two levels on the path.
func _chapter_marker(ch: Dictionary) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10 if ch["from"] > 1 else 0)
	m.add_theme_constant_override("margin_right", 10)
	var p := UI.flat(Style.BG_DEEP, 8, 12)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := UI.vbox(0)
	var n := 1
	for i in Db.CHAPTERS.size():
		if Db.CHAPTERS[i] == ch:
			n = i + 1
	v.add_child(UI.label("Глава %d" % n, Style.FONT_TINY, Style.MUTED, true))
	v.add_child(UI.label(ch["name"], Style.FONT_SMALL, Style.TEXT, true))
	p.add_child(v)
	m.add_child(p)
	return m

func _scroll_path_to(s: ScrollContainer, node: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(s) or not is_instance_valid(node):
		return
	s.scroll_horizontal = int(max(0.0, node.position.x - (s.size.x - node.size.x) / 2.0))

func _path_node(lvl: int) -> Control:
	var closed := lvl <= Game.closed_level
	var unlocked := Game.level_unlocked(lvl)
	var col := Style.SUCCESS if closed else (Style.PRIMARY if unlocked else Style.CARD_3)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(76, 86)
	var b := Button.new()
	b.size = Vector2(76, 76)
	b.position = Vector2(0, 6)
	var sb := Style.box(col, 38, 4)
	sb.border_width_bottom = 5
	sb.border_color = col.darkened(0.35)
	if lvl == selected_level:
		sb.border_width_left = 4
		sb.border_width_right = 4
		sb.border_width_top = 4
		sb.border_color = Color.WHITE
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, sb)
	b.disabled = not unlocked
	b.pressed.connect(_select_level.bind(lvl))
	holder.add_child(b)
	var inner := UI.vbox(0)
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icn := UI.icon("check" if closed else ("swords" if unlocked else "lock"), 30)
	icn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(icn)
	var num := UI.label(str(lvl), Style.FONT_SMALL, Style.PRIMARY_TEXT if unlocked and not closed else Style.TEXT, true)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(num)
	b.add_child(inner)
	if _is_boss_level(lvl):
		var sk := UI.icon("boss", 26)
		sk.position = Vector2(54, 0)
		holder.add_child(sk)
	return holder

func _go_to_expedition() -> void:
	var ex = Game.exp_info()
	if ex != null:
		selected_level = int(ex["level"])
	current_tab = ""
	_switch("expedition")

func _select_level(lvl: int) -> void:
	selected_level = lvl
	_refresh()

## Skull marks the last level of each chapter (its big boss fight).
func _is_boss_level(lvl: int) -> bool:
	if lvl == Db.level_count():
		return true
	return Db.chapter_of(lvl + 1)["from"] == lvl + 1

func _battle_card() -> Control:
	var c := UI.card(Style.BG_DEEP, 0)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.clip_contents = true
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(300, 260)
	c.add_child(holder)
	var bv := BattleView.new()
	bv.preview_mode = true
	bv.set_anchors_preset(Control.PRESET_FULL_RECT)
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bv)
	var ex = Game.exp_info()
	var view: Expedition = Game.expedition
	var top := UI.hbox(8)
	top.position = Vector2(12, 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ex == null:
		top.add_child(UI.chip("Группа отдыхает", Style.CARD_2, Style.FONT_SMALL))
		holder.add_child(top)
		return c
	UI.tap_overlay(holder, _open_watch)
	holder.add_child(top)
	var mode := "Фарм" if ex["mode"] == "farm" else "Штурм"
	var run_txt := (" · забег %d" % (view.run_index + 1)) if view != null and ex["mode"] == "farm" else ""
	top.add_child(UI.chip("%s · ур. %d%s" % [mode, ex["level"], run_txt],
		Style.SUCCESS if ex["mode"] == "farm" else Style.PRIMARY, Style.FONT_SMALL,
		Color("#062b16") if ex["mode"] == "farm" else Style.PRIMARY_TEXT))
	var watch := UI.btn("Смотреть", _open_watch, "secondary", Style.FONT_SMALL, "watch", 150, 46)
	watch.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	watch.offset_left = -162
	watch.offset_top = -58
	watch.offset_right = -12
	watch.offset_bottom = -12
	holder.add_child(watch)
	return c

func _level_card() -> Control:
	var lvl := selected_level
	var closed := lvl <= Game.closed_level
	var c := UI.card(Style.CARD, 14)
	c.custom_minimum_size.x = 430
	# info scrolls if it does not fit, the status and buttons always stay visible:
	# the card can never push the bottom navigation off the screen
	var outer := UI.vbox(8)
	c.add_child(outer)
	var v := UI.vbox(10)
	var info := UI.scroll(v)
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size.y = 60
	outer.add_child(info)

	var head := UI.hbox(8)
	var hv := UI.vbox(0)
	hv.add_child(UI.label(Db.chapter_of(lvl)["name"], Style.FONT_TINY, Style.MUTED, true))
	hv.add_child(UI.title("%d. %s" % [lvl, Db.LEVELS[lvl - 1]["name"]], 24))
	head.add_child(UI.expand(hv))
	head.add_child(UI.chip("Пройден" if closed else "Новый", Style.SUCCESS if closed else Style.PRIMARY,
		Style.FONT_TINY, Color("#062b16") if closed else Style.PRIMARY_TEXT))
	v.add_child(head)
	var run = Game.exp_info()
	if run != null and int(run["level"]) != lvl:
		v.add_child(UI.btn("Идёт %s на ур. %d — открыть" % ["фарм" if run["mode"] == "farm" else "штурм", int(run["level"])],
			_select_level.bind(int(run["level"])), "secondary", Style.FONT_SMALL, "loop", 0, 44))

	var foes := UI.hbox(6)
	var seen := {}
	var boss_id := ""
	for w in Db.LEVELS[lvl - 1]["waves"]:
		for e in w:
			if Db.ENEMIES[e].get("boss", false):
				boss_id = e
			elif not seen.has(e):
				seen[e] = true
				foes.add_child(UI.avatar(Db.ENEMIES[e]["sprite"], Style.CARD_2, 52, true))
	foes.add_child(UI.btn("Атлас", _atlas_popup.bind(lvl), "ghost", Style.FONT_TINY, "", 0, 44))
	var row := UI.hbox(12)
	var fv := UI.vbox(4)
	fv.add_child(UI.label("Враги · волн: %d" % Db.level_waves(lvl).size(), Style.FONT_TINY, Style.MUTED))
	fv.add_child(foes)
	var mods := Db.level_modifiers(lvl)
	if not mods.is_empty():
		var mh := UI.hbox(6)
		for m in mods:
			mh.add_child(UI.pill(Db.MODIFIERS[m]["icon"], Db.MODIFIERS[m]["name"], Style.FONT_TINY, Color("#5a2530")))
		fv.add_child(mh)
	row.add_child(UI.expand(fv))
	if boss_id != "":
		var bv := UI.vbox(4)
		bv.add_child(UI.label("Босс", Style.FONT_TINY, Style.MUTED))
		var bh := UI.hbox(6)
		bh.add_child(UI.avatar(Db.ENEMIES[boss_id]["sprite"], Color("#5a2a3a"), 52, true))
		bh.add_child(UI.wrap(Db.ENEMIES[boss_id]["name"], Style.FONT_SMALL, Style.TEXT, true))
		bv.add_child(bh)
		bv.custom_minimum_size.x = 140
		row.add_child(bv)
	v.add_child(row)

	var hints := Db.level_hints(lvl)
	if not closed and Game.hero["level"] < int(lvl * 1.4):
		hints.append("Risky")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	const MAX_HINTS := 5
	var shown: Array = hints.slice(0, MAX_HINTS)
	if hints.has("Risky") and not shown.has("Risky"):
		shown[shown.size() - 1] = "Risky"
	for hnt in shown:
		flow.add_child(UI.chip(hnt, Style.DANGER if hnt == "Risky" else Style.CARD_3))
	if hints.size() > MAX_HINTS:
		flow.add_child(UI.chip("+%d" % (hints.size() - MAX_HINTS), Style.BG_DEEP))
	v.add_child(flow)
	v.add_child(UI.spacer())

	var party := UI.hbox(6)
	var order: Array = Game.party_order
	for i in range(order.size() - 1, -1, -1):
		var snap = Game.hero_snapshot() if order[i] == "hero" else Game.merc_by_id(order[i])
		if snap != null:
			Roster.ensure_visuals(snap)
			party.add_child(UI.avatar(snap["sprite"], Style.ROLE_COLORS.get(snap["role"], Style.CARD_3), 48, false, snap.get("look", []), snap.get("appearance", {})))
	party.add_child(UI.spacer())
	party.add_child(UI.btn("Состав", _switch.bind("mercs"), "ghost", Style.FONT_SMALL, "nav_mercs", 0, 46))
	v.add_child(party)

	exp_status = UI.wrap("", Style.FONT_TINY, Style.MUTED)
	outer.add_child(exp_status)
	outer.add_child(_level_actions(lvl, closed))
	_tick_status()
	return c

func _level_actions(lvl: int, closed: bool) -> Control:
	var h := UI.hbox(8)
	var ex = Game.exp_info()
	if ex != null and int(ex["level"]) == lvl:
		if ex["mode"] == "farm":
			h.add_child(UI.expand(UI.btn("Забрать добычу", _collect_farm, "primary", 22, "gold", 0, 62)))
		h.add_child(UI.btn("Стоп", _stop_expedition, "danger", 20, "", 110, 62))
		return h
	if not Game.party_ready():
		h.add_child(UI.expand(UI.btn("Наберите группу", _switch.bind("mercs"), "secondary", 22, "nav_mercs", 0, 62)))
	elif closed:
		h.add_child(UI.expand(UI.btn("Фарм", _start.bind(lvl, "farm"), "success", 24, "loop", 0, 62)))
	else:
		h.add_child(UI.expand(UI.btn("Штурм", _start.bind(lvl, "push"), "primary", 24, "swords", 0, 62)))
	return h

func _collect_farm() -> void:
	_show_rewards(await Game.collect(), "Добыча фарма")

func _stop_expedition() -> void:
	_show_rewards(await Game.stop_expedition(), "Поход остановлен")

func _tick_status() -> void:
	if exp_status == null or not is_instance_valid(exp_status):
		return
	var ex = Game.exp_info()
	if ex == null:
		exp_status.text = "Поход идёт и при закрытой игре (до 12 ч)."
		return
	var pd := Game.pending()
	var where := ""
	if ex["mode"] == "push":
		where = "Штурм ур. %d, волна %d/%d" % [ex["level"], min(int(pd.get("wave", 0)) + 1, int(ex["tl"]["total"])), int(ex["tl"]["total"])]
	else:
		where = "Фарм ур. %d, %s" % [ex["level"], UI.format_time(pd["t"])]
	exp_status.text = "%s · накоплено %d золота, %d опыта, %d предм. · побед %d, поражений %d" % [
		where, pd["gold"], pd["xp"], pd["items"], pd["won"], pd["lost"]]

func _start(lvl: int, mode: String) -> void:
	if Game.exp_info() != null and Game.has_pending():
		_show_rewards(await Game.stop_expedition(), "Прошлый поход завершён")
	if await Game.start_expedition(lvl, mode):
		_open_watch()
	else:
		_toast("Не удалось начать поход")

# =====================================================================
# Watch layer (full-screen battle)
# =====================================================================

func _build_watch_layer() -> void:
	watch_layer = Control.new()
	watch_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	watch_layer.visible = false
	add_child(watch_layer)
	battle_view = BattleView.new()
	battle_view.show_last = true
	battle_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	watch_layer.add_child(battle_view)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", Style.box(Color(0.09, 0.1, 0.15, 0.82), 0, 8))
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	watch_layer.add_child(bar)
	var h := UI.hbox(10)
	bar.add_child(h)
	h.add_child(UI.btn("Назад", _close_watch, "ghost", Style.FONT_BODY, "", 120, 48))
	watch_label = UI.label("", Style.FONT_BODY, Style.TEXT, true)
	watch_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(watch_label)
	for sp in [1.0, 2.0, 4.0, 8.0]:
		var b := UI.btn("x%d" % int(sp), _set_speed.bind(sp), "ghost", Style.FONT_BODY, "", 64, 48)
		speed_buttons.append(b)
		h.add_child(b)
	_build_meter()

## Recount-style meters: one bar per ally, total (per second), best on top.
func _build_meter() -> void:
	meter_rows = _build_meter_panel("Урон", "всего (DPS) · нажмите на строку", 12)
	heal_rows = _build_meter_panel("Лечение", "всего (HPS)", 464)
	for i in meter_rows.size():
		UI.tap_overlay(meter_rows[i]["root"], _meter_details.bind(meter_rows, i, "dealt_by", "Урон"))
	for i in heal_rows.size():
		UI.tap_overlay(heal_rows[i]["root"], _meter_details.bind(heal_rows, i, "healed_by", "Лечение"))

func _build_meter_panel(title: String, hint: String, x: float) -> Array:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.box(Color(0.06, 0.07, 0.1, 0.85), Style.RADIUS_SMALL, 8))
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = x
	panel.offset_right = x + 440
	panel.offset_bottom = -4
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	watch_layer.add_child(panel)
	var v := UI.vbox(3)
	panel.add_child(v)
	var head := UI.hbox(6)
	head.add_child(UI.expand(UI.label(title, Style.FONT_SMALL, Style.TEXT, true)))
	head.add_child(UI.label(hint, Style.FONT_TINY, Style.MUTED))
	v.add_child(head)
	var rows := []
	for i in 4:
		var row := Control.new()
		row.custom_minimum_size = Vector2(0, 26)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := ColorRect.new()
		bg.color = Color(1, 1, 1, 0.06)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.add_child(bg)
		var bar := ColorRect.new()
		bar.anchor_bottom = 1.0
		row.add_child(bar)
		var name := UI.label("", Style.FONT_TINY, Style.TEXT, true)
		name.set_anchors_preset(Control.PRESET_FULL_RECT)
		name.offset_left = 8
		name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name)
		var val := UI.label("", Style.FONT_TINY, Style.TEXT, true)
		val.set_anchors_preset(Control.PRESET_FULL_RECT)
		val.offset_right = -8
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(val)
		v.add_child(row)
		rows.append({"root": row, "bar": bar, "name": name, "value": val})
	return rows

func _update_meter(ex: Expedition) -> void:
	var allies := []
	if ex != null and ex.sim != null:
		for u in ex.sim.units:
			if u.side == 0:
				allies.append(u)
	# one meter per run: allies are created fresh each run (each farm loop) and keep counting across waves
	var t: float = max(1.0, ex.run_time_done + ex.sim.time) if ex != null and ex.sim != null else 1.0
	_fill_meter(meter_rows, allies, "dealt", t)
	_fill_meter(heal_rows, allies, "healed", t)

## Breakdown by spell for one meter row (Recount-style detail).
func _meter_details(rows: Array, i: int, field: String, title: String) -> void:
	var ex: Expedition = Game.shown_battle()
	if ex == null or ex.sim == null or not rows[i].has("uid"):
		return
	var u = ex.sim.unit_by_uid(int(rows[i]["uid"]))
	if u == null:
		return
	var by: Dictionary = u.get(field)
	var total := 0.0
	for k in by:
		total += float(by[k])
	var t: float = max(1.0, ex.run_time_done + ex.sim.time)
	var keys: Array = by.keys()
	keys.sort_custom(func(a, b): return by[a] > by[b])
	var v := UI.vbox(6)
	if keys.is_empty():
		v.add_child(UI.label("Пока ничего.", Style.FONT_SMALL, Style.MUTED))
	for k in keys:
		var amount := float(by[k])
		var row := UI.hbox(8)
		var icon := "atk" if k == "attack" else UI.spell_icon(k)
		row.add_child(UI.icon(icon, 28))
		var name: String = "Автоатака" if k == "attack" else Db.SPELLS[k]["name"]
		var nv := UI.vbox(2)
		nv.add_child(UI.label(name, Style.FONT_SMALL, Style.TEXT, true))
		nv.add_child(UI.progress(amount, max(1.0, total), Style.SECONDARY, 8))
		row.add_child(UI.expand(nv))
		row.add_child(UI.label("%d (%d/с) · %d%%" % [roundi(amount), roundi(amount / t), roundi(amount / max(1.0, total) * 100)], Style.FONT_SMALL, Style.TEXT))
		v.add_child(row)
	_modal("%s: %s · за забег" % [title, u.name], v)

func _fill_meter(rows: Array, units: Array, field: String, t: float) -> void:
	var allies := units.duplicate()
	allies.sort_custom(func(a, b): return a.get(field) > b.get(field))
	var top := 1.0
	for u in allies:
		top = max(top, u.get(field))
	for i in rows.size():
		var r: Dictionary = rows[i]
		r["root"].visible = i < allies.size()
		if i >= allies.size():
			continue
		var u = allies[i]
		var bar: ColorRect = r["bar"]
		bar.color = Color(u.color, 0.75) if u.alive() else Color(0.4, 0.4, 0.45, 0.6)
		var amount: float = u.get(field)
		r["uid"] = u.uid
		bar.anchor_right = amount / top
		r["name"].text = "%d. %s" % [i + 1, u.name]
		r["value"].text = "%d (%d)" % [roundi(amount), roundi(amount / t)]

func _set_speed(s: float) -> void:
	Game.watch_speed = s

func _open_watch() -> void:
	for b in speed_buttons:
		b.visible = not Game.is_online()  # online the server keeps real time
	watch_layer.visible = true
	watch_layer.modulate.a = 0.0
	create_tween().tween_property(watch_layer, "modulate:a", 1.0, 0.15)

func _close_watch() -> void:
	watch_layer.visible = false   # the chosen speed stays (offline): the expedition keeps going faster
	_refresh()

func _process(_delta: float) -> void:
	if watch_layer.visible:
		var ex: Expedition = Game.shown_battle()
		if Game.expedition == null:
			watch_label.text = "Поход завершён"
		else:
			var mode := "Штурм" if ex.mode == "push" else "Фарм"
			watch_label.text = "%s · ур. %d · забег %d · волна %d/%d · x%d" % [mode, ex.level, ex.run_index + 1,
				min(ex.wave_index + 1, ex.total_waves()), ex.total_waves(), int(Game.watch_speed)]
		_update_meter(ex)

# =====================================================================
# Screen: Hero
# =====================================================================

func _screen_hero() -> Control:
	var h := UI.hbox(12)
	var hero: Dictionary = Game.hero
	var snap := Game.hero_snapshot()
	var st: Dictionary = snap["stats"]

	var sc := UI.card()
	sc.custom_minimum_size.x = 290
	var sv := UI.vbox(6)
	sc.add_child(sv)
	sv.add_child(UI.title("Характеристики", 22))
	var pw := UI.flat(Style.BG_DEEP, 10)
	var pwh := UI.hbox(10)
	pw.add_child(pwh)
	pwh.add_child(UI.icon("star", 34))
	pwh.add_child(UI.expand(UI.label("Мощь", Style.FONT_BODY, Style.MUTED)))
	pwh.add_child(UI.title(str(Roster.power_score(snap)), 28, Style.PRIMARY))
	sv.add_child(pw)
	sv.add_child(UI.stat_row("hp", "Здоровье", "%d" % st["hp"]))
	sv.add_child(UI.stat_row("atk", "Атака", ("%d · %.1f с" % [st["atk"], st.get("atk_speed", 1.6) / (1.0 + st["haste"])]) if st["atk"] > 0 else "нет (посох)"))
	sv.add_child(UI.stat_row("str", "Сила", "%d" % st["str"]))
	sv.add_child(UI.stat_row("agi", "Ловкость", "%d" % st["agi"]))
	sv.add_child(UI.stat_row("power", "Сила заклинаний", "%d" % st["power"]))
	sv.add_child(UI.stat_row("armor", "Броня", "%d" % st["armor"]))
	sv.add_child(UI.stat_row("haste", "Скорость", "%d%%" % roundi(st["haste"] * 100)))
	sv.add_child(UI.stat_row("crit", "Крит", "%d%%" % roundi(st["crit"] * 100)))
	sv.add_child(UI.stat_row("loop", "Ход ротации", "%.1f с" % SpellInfo.rotation_interval(st["haste"])))
	sv.add_child(UI.spacer())
	var free := Talents.points_free(hero)
	var tb := UI.btn("Таланты" + (" (+%d)" % free if free > 0 else ""), _talents_popup, "primary" if free > 0 else "secondary", Style.FONT_SMALL, "star", 0, 44)
	var trow := UI.hbox(6)
	trow.add_child(UI.expand(tb))
	trow.add_child(UI.btn("Манекен", _dummy_popup, "ghost", Style.FONT_SMALL, "swords", 0, 44))
	sv.add_child(trow)
	sv.add_child(UI.label("Опыт %d / %d" % [hero["xp"], Db.xp_to_next(hero["level"])], Style.FONT_TINY, Style.MUTED))
	sv.add_child(UI.progress(hero["xp"], Db.xp_to_next(hero["level"]), Style.SECONDARY, 12))
	h.add_child(sc)

	var mid := UI.card()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mv := UI.vbox(12)
	mid.add_child(mv)
	var doll := UI.hbox(20)
	doll.alignment = BoxContainer.ALIGNMENT_CENTER
	doll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left_extra := UI.vbox(2)
	left_extra.add_child(_gear_slot("accessory1"))
	doll.add_child(left_extra)
	var left_col := UI.vbox(2)
	left_col.alignment = BoxContainer.ALIGNMENT_CENTER
	for slot in ["weapon", "offhand", "hands", "trinket"]:
		left_col.add_child(_gear_slot(slot))
	doll.add_child(left_col)
	var stage := UI.vbox(0)
	stage.alignment = BoxContainer.ALIGNMENT_END
	var big := UI.portrait("hero", 200, false, Game.hero_snapshot()["look"], Game.hero_snapshot()["cosmetics"].get("glow", ""), Game.hero_snapshot()["appearance"])
	big.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.add_child(big)
	var ped := UI.flat(Style.BG_DEEP, 0, 20)
	ped.custom_minimum_size = Vector2(200, 18)
	ped.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.add_child(ped)
	stage.add_child(UI.btn("Внешность", _appearance_popup, "ghost", 18, "", 0, 40))
	doll.add_child(stage)
	var right_col := UI.vbox(2)
	right_col.alignment = BoxContainer.ALIGNMENT_CENTER
	for slot in ["head", "armor", "legs", "feet"]:
		right_col.add_child(_gear_slot(slot))
	doll.add_child(right_col)
	var right_extra := UI.vbox(2)
	right_extra.add_child(_gear_slot("accessory2"))
	doll.add_child(right_extra)
	mv.add_child(doll)

	var rot_head := UI.hbox(8)
	rot_head.add_child(UI.title("Ротация", 20))
	rot_head.add_child(UI.expand(UI.label("каждый ход: первая подходящая слева направо", Style.FONT_TINY, Style.MUTED)))
	mv.add_child(rot_head)
	var rot := UI.hbox(8)
	rot.alignment = BoxContainer.ALIGNMENT_CENTER
	var rotation: Array = hero["rotation"]
	for i in 3:
		if i > 0:
			rot.add_child(UI.label("→", 26, Style.MUTED, true))
		rot.add_child(_rotation_slot(i, rotation[i] if i < rotation.size() else ""))
	mv.add_child(rot)
	h.add_child(mid)

	var lc := UI.card()
	lc.custom_minimum_size.x = 330
	var lv := UI.vbox(10)
	lc.add_child(lv)
	lv.add_child(UI.title("Способности", 22))
	lv.add_child(UI.label("Нажмите, чтобы поставить в ротацию", Style.FONT_TINY, Style.MUTED))
	var g := UI.grid(4, 8)
	for sid in Game.owned_spells():
		g.add_child(_spell_tile_button(sid, 64, rotation.has(sid)))
	lv.add_child(UI.scroll(g))
	h.add_child(lc)
	return h

func _gear_slot(slot: String) -> Control:
	var it = Game.hero["equipped"].get(slot)
	var v := UI.vbox(0)
	var t: Control
	var label: String = Loot.SLOT_NAMES[slot]
	var main_w = Game.hero["equipped"].get("weapon")
	if it == null and slot == "offhand" and Loot.is_two_handed(main_w):
		t = UI.tile(UI.item_icon(main_w), Style.CARD_3, 50, true)
		label = "Двуручное"
	elif it == null:
		t = UI.tile("item_accessory" if slot.begins_with("accessory") else "item_" + slot, Style.CARD_3, 50, true)
	else:
		t = UI.tile(UI.item_icon(it), Style.QUALITY[it["rarity"]], 50)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UI.tap_overlay(t, _gear_popup.bind(slot))
	v.add_child(t)
	var l := UI.label(label, Style.FONT_TINY, Style.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v

func _rotation_slot(i: int, sid: String) -> Control:
	var v := UI.vbox(2)
	v.custom_minimum_size.x = 160
	var t: Control
	if sid == "":
		t = UI.tile("star", Style.CARD_3, 76, true)
		UI.tap_overlay(t, _toast.bind("Выберите способность справа"))
	else:
		var d: Dictionary = Db.SPELLS[sid]
		t = UI.tile(UI.spell_icon(sid), Style.RARITY[d["rarity"]], 76)
		UI.tap_overlay(t, _spell_popup.bind(sid))
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var num := UI.chip(str(i + 1), Style.PRIMARY, 13, Style.PRIMARY_TEXT)
	num.position = Vector2(-8, -8)
	t.add_child(num)
	v.add_child(t)
	var name := "Пусто"
	if sid != "":
		var lv: int = max(1, Roster.spell_best_level(Game.collection, sid))
		name = "%s %s\n%s" % [Db.SPELLS[sid]["name"], UI.roman(lv), SpellInfo.short(sid, lv, Game.hero_snapshot())]
	var l := UI.wrap(name, Style.FONT_TINY, Style.TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	if sid != "" and not Db.spell_usable(sid, Game.hero_snapshot()["weapons"]):
		var w := UI.label("Нет оружия", Style.FONT_TINY, Style.DANGER, true)
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(w)
	return v

func _spell_tile_button(sid: String, size_px: float, marked: bool = false) -> Control:
	var d: Dictionary = Db.SPELLS[sid]
	var lvl := Roster.spell_best_level(Game.collection, sid)
	var t := UI.tile(UI.spell_icon(sid), Style.RARITY[d["rarity"]], size_px, lvl == 0)
	if lvl > 0:
		var ch := UI.chip(UI.roman(lvl), Style.BG_DEEP, 12)
		ch.position = Vector2(size_px - 30, size_px - 26)
		t.add_child(ch)
	if marked:
		var ck := UI.icon("check", 22)
		ck.position = Vector2(-6, -6)
		t.add_child(ck)
	UI.tap_overlay(t, _spell_popup.bind(sid))
	return t

func _rot_move(i: int, dir: int) -> void:
	var rot: Array = Game.hero["rotation"].duplicate()
	var j := i + dir
	if j < 0 or j >= rot.size():
		return
	var tmp = rot[i]
	rot[i] = rot[j]
	rot[j] = tmp
	Game.set_rotation(rot)

func _rot_set(i: int, sid: String) -> void:
	var rot: Array = Game.hero["rotation"].duplicate()
	if rot.has(sid):
		return
	if i < rot.size():
		rot[i] = sid
	else:
		rot.append(sid)
	Game.set_rotation(rot)
	_toast("%s — слот %d" % [Db.SPELLS[sid]["name"], min(i, rot.size() - 1) + 1])

func _rot_remove(i: int) -> void:
	var rot: Array = Game.hero["rotation"].duplicate()
	rot.remove_at(i)
	Game.set_rotation(rot)

## Enemy atlas: every enemy of a level with its stats at that level, spells and modifiers.
func _atlas_popup(lvl: int) -> void:
	var v := UI.vbox(8)
	var mods := Db.level_modifiers(lvl)
	for m in mods:
		var mh := UI.hbox(8)
		mh.add_child(UI.icon(Db.MODIFIERS[m]["icon"], 28))
		mh.add_child(UI.expand(UI.wrap("%s: %s" % [Db.MODIFIERS[m]["name"], Db.MODIFIERS[m]["desc"]], Style.FONT_SMALL, Style.WARNING)))
		v.add_child(mh)
	var ids := []
	for w in Db.level_waves(lvl):
		for e in w:
			if not e in ids:
				ids.append(e)
	ids.sort_custom(func(a, b): return int(Db.ENEMIES[a].get("boss", false)) < int(Db.ENEMIES[b].get("boss", false)))
	var list := UI.vbox(8)
	for eid in ids:
		var e: Dictionary = Db.ENEMIES[eid]
		var snap := Expedition.enemy_snapshot(eid, lvl)
		var st: Dictionary = snap["stats"]
		var c := UI.card(Color("#3a2530") if e.get("boss", false) else Style.BG_DEEP, 10)
		var h := UI.hbox(12)
		c.add_child(h)
		h.add_child(UI.avatar(e["sprite"], Style.CARD_2, 72, true))
		var cv := UI.vbox(4)
		var nh := UI.hbox(6)
		nh.add_child(UI.label(e["name"], Style.FONT_BODY, Style.TEXT, true))
		if e.get("boss", false):
			nh.add_child(UI.chip("Босс", Style.DANGER, 13))
		nh.add_child(UI.chip({"front": "бьёт передних", "back": "бьёт тыл", "random": "бьёт случайных", "lowest": "добивает раненых"}.get(e["target"], ""), Style.CARD_3, 13))
		cv.add_child(nh)
		var sh := HFlowContainer.new()
		sh.add_theme_constant_override("h_separation", 6)
		sh.add_theme_constant_override("v_separation", 4)
		var stat_list := [["hp", "%d" % st["hp"]], ["atk", "%d" % st["atk"]], ["power", "%d" % st["power"]], ["armor", "%d" % st["armor"]]]
		if st["haste"] != 0.0:
			stat_list.append(["haste", "%+d%%" % roundi(st["haste"] * 100)])
		if st.has("start_shield"):
			stat_list.append(["sp_barrier", "щит %d" % st["start_shield"]])
		if st.has("regen"):
			stat_list.append(["hp", "+%d/с" % roundi(st["hp"] * st["regen"])])
		for sl in stat_list:
			sh.add_child(UI.pill(sl[0], sl[1], Style.FONT_TINY, Style.CARD_2))
		cv.add_child(sh)
		for sp in e["spells"]:
			var s: Dictionary = Db.SPELLS[sp]
			var bits := [SpellInfo.short(sp, 1, snap)]
			bits.append(("каст %.1f с" % s["cast"]) if s.get("cast", 0.0) > 0.0 else "мгновенно")
			if s.get("cd", 0.0) > 0.0:
				bits.append("кд %.0f с" % s["cd"])
			if s.get("cast", 0.0) > 0.0:
				bits.append("можно сбить" if s.get("interruptible", true) else "НЕЛЬЗЯ сбить")
			var sl := UI.hbox(6)
			sl.add_child(UI.label("• " + s["name"], Style.FONT_TINY, Style.TEXT, true))
			sl.add_child(UI.label(" · ".join(bits), Style.FONT_TINY,
				Style.DANGER if s.get("cast", 0.0) > 0.0 and not s.get("interruptible", true) else Style.MUTED))
			cv.add_child(sl)
		h.add_child(UI.expand(cv))
		list.add_child(c)
	var sc := UI.scroll(list)
	sc.custom_minimum_size = Vector2(780, 420 - 36 * mods.size())
	v.add_child(sc)
	_modal("Атлас врагов · %d. %s" % [lvl, Db.LEVELS[lvl - 1]["name"]], v)

# =====================================================================
# Shop (crystals). Prototype: purchases are test grants.
# =====================================================================

func _shop_popup() -> void:
	var keep := UI.scroll_state(popup_layer)
	UI.clear(popup_layer)
	var v := UI.vbox(10)
	v.add_child(UI.wrap("Прототип: покупки тестовые, деньги не списываются.", Style.FONT_TINY, Style.WARNING))
	var packs := UI.hbox(8)
	for pk in Shop.PACKS:
		var c := UI.card(Style.BG_DEEP, 8)
		var cv := UI.vbox(4)
		c.add_child(cv)
		cv.add_child(UI.pill("crystal", str(pk["crystals"]), Style.FONT_BODY, Color("#3a2f5a")))
		cv.add_child(UI.btn("%s (тест)" % pk["price"], _shop_buy_pack.bind(pk["id"]), "primary", Style.FONT_SMALL, "", 0, 44))
		packs.add_child(c)
	v.add_child(packs)
	# boost
	var bh := UI.hbox(8)
	var b = Game.profile.get("buffs", {}).get("farm_x2")
	var left: float = float(b["until"]) - Game.now() if b != null else 0.0
	bh.add_child(UI.icon("loop", 32))
	var bv := UI.vbox(0)
	bv.add_child(UI.label("Ускорение фарма ×2 на 2 ч", Style.FONT_BODY, Style.TEXT, true))
	bv.add_child(UI.label(("Активно ещё %s · " % UI.format_time(left) if left > 0.0 else "") + "золото и опыт с фарма ×2 (вещи и редкий дроп — нет)", Style.FONT_TINY, Style.MUTED))
	bh.add_child(UI.expand(bv))
	var bb := UI.btn("%d" % Shop.BOOST_PRICE, _shop_boost, "secondary", Style.FONT_SMALL, "crystal", 0, 44)
	bb.disabled = Game.crystals < Shop.BOOST_PRICE
	bh.add_child(bb)
	v.add_child(bh)
	# cosmetics
	v.add_child(UI.label("Косметика — только внешний вид", Style.FONT_SMALL, Style.MUTED, true))
	var g := UI.grid(2, 8)
	var worn: Dictionary = Game.hero.get("cosmetics", {})
	var owned: Array = Game.profile.get("cosmetics_owned", [])
	for id in Shop.COSMETICS:
		var cm: Dictionary = Shop.COSMETICS[id]
		var c := UI.card(Style.BG_DEEP, 8)
		c.custom_minimum_size.x = 380
		var ch := UI.hbox(8)
		c.add_child(ch)
		var sw := UI.flat(Color(cm["color"]), 0, 18)
		sw.custom_minimum_size = Vector2(36, 36)
		ch.add_child(sw)
		var cv := UI.vbox(0)
		cv.add_child(UI.label(cm["name"], Style.FONT_SMALL, Style.TEXT, true))
		cv.add_child(UI.label(Shop.COSMETIC_SLOTS[cm["slot"]], Style.FONT_TINY, Style.MUTED))
		ch.add_child(UI.expand(cv))
		if worn.get(cm["slot"], "") == id:
			ch.add_child(UI.btn("Снять", _shop_wear.bind(cm["slot"], ""), "ghost", Style.FONT_SMALL, "", 0, 40))
		elif id in owned:
			ch.add_child(UI.btn("Надеть", _shop_wear.bind(cm["slot"], id), "primary", Style.FONT_SMALL, "", 0, 40))
		else:
			var buy := UI.btn("%d" % cm["price"], _shop_cosmetic.bind(id), "secondary", Style.FONT_SMALL, "crystal", 0, 40)
			buy.disabled = Game.crystals < int(cm["price"])
			ch.add_child(buy)
		g.add_child(c)
	var sc := UI.scroll(g)
	sc.custom_minimum_size = Vector2(780, 230)
	v.add_child(sc)
	_modal("Магазин · кристаллов: %d" % Game.crystals, v)
	UI.restore_scrolls(popup_layer, keep)

func _shop_buy_pack(id: String) -> void:
	await Game.fake_purchase(id)
	_shop_popup()

func _shop_boost() -> void:
	var r: Dictionary = await Game.buy_boost()
	_toast("Фарм ×2 включён" if r.get("ok", false) else "Не хватает кристаллов")
	_shop_popup()

func _shop_cosmetic(id: String) -> void:
	var r: Dictionary = await Game.buy_cosmetic(id)
	_toast("Куплено и надето" if r.get("ok", false) else "Не хватает кристаллов")
	_shop_popup()

func _shop_wear(slot: String, id: String) -> void:
	Game.set_cosmetic(slot, id)
	_shop_popup()

## A separate live sandbox; never changes the saved hero or the active expedition.
func _dummy_popup() -> void:
	var backdrop := UI.card(Style.BG, 16)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_layer.add_child(backdrop)
	var panel := preload("res://scripts/ui/training_panel.gd").new()
	panel.configure(Game.hero_snapshot())
	backdrop.add_child(panel)
	panel.tree_exited.connect(backdrop.queue_free)

func _talents_popup() -> void:
	UI.clear(popup_layer)
	var panel := TalentPanel.new()
	panel.configure(Game.hero, Game.hero_snapshot(), func(id): Game.talent_up(id))
	_modal("Таланты", panel, [["Сбросить бесплатно", _talent_reset, "danger", Talents.points_spent(Game.hero.get("talents",{})) > 0]])
	panel.custom_minimum_size.x = 930

func _appearance_popup() -> void:
	var panel := preload("res://scripts/ui/appearance_panel.gd").new()
	var snap := Game.hero_snapshot()
	panel.configure(snap["appearance"], snap["look"])
	_modal("Внешность героя", panel, [["Сохранить", _apply_appearance.bind(panel), "primary", true]], "Отмена")

func _apply_appearance(panel: Control) -> void:
	var result := Game.set_appearance(panel.value["sex"], panel.value["hair"])
	if not result.get("ok", false):
		_toast("Не удалось сохранить внешность")

func _set_threshold(sid: String, value: float) -> void:
	Game.set_threshold(sid, value)
	UI.clear(popup_layer)
	_spell_popup(sid)

func _talent_up(id: String) -> void:
	Game.talent_up(id)
	_talents_popup()

func _talent_reset() -> void:
	Game.talent_reset()
	_talents_popup()

func _gear_popup(slot: String) -> void:
	UI.clear(popup_layer)
	var it = Game.hero["equipped"].get(slot)
	var body := UI.vbox(10)
	if it == null:
		var where := "Предметы падают за первое прохождение уровня и на фарме, часть вещей делают кузнецы и портные."
		body.add_child(UI.wrap("Слот «%s» пуст. %s" % [Loot.SLOT_NAMES[slot], where], Style.FONT_SMALL, Style.MUTED))
	else:
		body.add_child(_item_details(it, false))
	# what from the bag fits this slot
	var fits := []
	for x in Game.inventory:
		if x["slot"] == slot or (slot == "offhand" and Loot.fits_offhand(x)) or (x["slot"] == "accessory" and slot.begins_with("accessory")):
			fits.append(x)
	fits.sort_custom(func(a, b): return Game.power_with(a, slot) > Game.power_with(b, slot))
	if not fits.is_empty():
		body.add_child(UI.label("Из сумки в этот слот:", Style.FONT_SMALL, Style.TEXT, true))
		var list := UI.vbox(6)
		for x in fits:
			var row := UI.hbox(8)
			row.add_child(UI.tile(UI.item_icon(x), Style.QUALITY[x["rarity"]], 48))
			var tv := UI.vbox(0)
			tv.add_child(UI.label("%s · ур. %d" % [UI.item_title(x), x["ilvl"]], Style.FONT_SMALL, Style.QUALITY[x["rarity"]], true))
			tv.add_child(UI.label(UI.item_line(x), Style.FONT_TINY, Style.MUTED))
			row.add_child(UI.expand(tv))
			var d := Game.power_with(x, slot) - Game.power_now()
			row.add_child(UI.label(("+%d" % d) if d > 0 else str(d), Style.FONT_SMALL, Style.SUCCESS if d > 0 else Style.DANGER, true))
			row.add_child(UI.btn("Надеть", _equip_from_slot.bind(x["id"], slot), "primary", Style.FONT_SMALL, "", 0, 40))
			list.add_child(row)
		var sc := UI.scroll(list)
		sc.custom_minimum_size = Vector2(620, min(300, 56 * fits.size()))
		body.add_child(sc)
	elif it == null:
		body.add_child(UI.label("В сумке нет подходящих вещей.", Style.FONT_SMALL, Style.MUTED))
	var buttons := []
	if it != null:
		buttons.append(["Снять", Game.unequip.bind(slot), "danger", true])
	_modal(UI.item_title(it) if it != null else Loot.SLOT_NAMES[slot], body, buttons)

func _equip_from_slot(id: String, slot: String) -> void:
	Game.equip(id, slot if slot == "offhand" or slot.begins_with("accessory") else "")
	_gear_popup(slot)

func _spell_popup(sid: String, caster: Dictionary = {}) -> void:
	var d: Dictionary = Db.SPELLS[sid]
	var own := caster.is_empty()
	var snap: Dictionary = Game.hero_snapshot() if own else caster
	var lvl := 0
	if own:
		lvl = Roster.spell_best_level(Game.collection, sid)
	else:
		for sp in caster["spells"]:
			if sp["id"] == sid:
				lvl = int(sp["lvl"])
	var shown_lvl: int = max(1, lvl)
	var body := UI.vbox(10)
	var top := UI.hbox(14)
	top.add_child(UI.tile(UI.spell_icon(sid), Style.RARITY[d["rarity"]], 88, lvl == 0))
	var tv := UI.vbox(6)
	var chips := UI.hbox(6)
	chips.add_child(UI.chip(Db.RARITY_NAMES[d["rarity"]], Style.RARITY[d["rarity"]]))
	chips.add_child(UI.chip("Уровень " + UI.roman(shown_lvl), Style.CARD_3))
	tv.add_child(chips)
	tv.add_child(UI.wrap(d["desc"], Style.FONT_SMALL, Style.MUTED))
	top.add_child(UI.expand(tv))
	body.add_child(top)
	body.add_child(_spell_numbers(sid, shown_lvl, snap))
	var buttons := []
	if own and lvl > 0:
		var ph := UI.hbox(8)
		if lvl >= Game.SPELL_MAX_LEVEL:
			ph.add_child(UI.label("Максимальный уровень", Style.FONT_SMALL, Style.SUCCESS, true))
		else:
			var copies := Game.spell_copies(sid)
			var cost := Game.fuse_cost(lvl)
			ph.add_child(UI.label("Копии для %s: %d / %d" % [UI.roman(lvl + 1), copies, cost], Style.FONT_SMALL, Style.MUTED))
			ph.add_child(UI.expand(UI.progress(min(copies, cost), cost, Style.SECONDARY, 12)))
			ph.add_child(UI.label("%s: %s" % [UI.roman(lvl + 1), SpellInfo.short(sid, lvl + 1, snap)], Style.FONT_SMALL, Style.TEXT, true))
			if Game.can_fuse(sid):
				buttons.append(["Улучшить → %s" % UI.roman(lvl + 1), _fuse.bind(sid), "primary", true])
		body.add_child(ph)
	if own and lvl > 0 and d["kind"] in Db.THRESHOLD_KINDS:
		var th := UI.hbox(6)
		th.add_child(UI.label("Лечить, если здоровье ниже:", Style.FONT_SMALL, Style.MUTED))
		var cur := Game.spell_threshold(sid)
		for o in Db.THRESHOLD_OPTIONS:
			var b := UI.btn("%d%%" % roundi(float(o) * 100), _set_threshold.bind(sid, float(o)),
				"primary" if absf(cur - float(o)) < 0.001 else "ghost", Style.FONT_SMALL, "", 64, 40)
			th.add_child(b)
		body.add_child(th)
	if own:
		var rot: Array = Game.hero["rotation"]
		var idx := rot.find(sid)
		if lvl == 0:
			body.add_child(UI.label("Ещё не открыта. Выпадает из Spell Box.", Style.FONT_SMALL, Style.MUTED))
		elif idx >= 0:
			buttons.append(["◀ Раньше", _rot_move.bind(idx, -1), "ghost", idx > 0])
			buttons.append(["Позже ▶", _rot_move.bind(idx, 1), "ghost", idx < rot.size() - 1])
			buttons.append(["Убрать", _rot_remove.bind(idx), "danger", true])
		elif rot.size() < 3:
			buttons.append(["В ротацию", _rot_set.bind(rot.size(), sid), "primary", true])
		else:
			body.add_child(UI.label("Ротация заполнена. Поставить вместо:", Style.FONT_SMALL, Style.MUTED))
			for i in rot.size():
				buttons.append(["%d. %s" % [i + 1, Db.SPELLS[rot[i]]["name"]], _rot_set.bind(i, sid), "secondary", true])
	var title_text: String = d["name"] if own else "%s — %s" % [d["name"], caster["name"]]
	_modal(title_text, body, buttons)

## Numbers block: effect, cast, cooldown, rotation interval for this caster.
func _spell_numbers(sid: String, lvl: int, snap: Dictionary) -> Control:
	var st: Dictionary = snap["stats"]
	var box := UI.flat(Style.BG_DEEP, 12)
	var v := UI.vbox(8)
	box.add_child(v)
	for line in SpellInfo.effects(sid, lvl, snap):
		var h := UI.hbox(8)
		h.add_child(UI.icon(line[0], 24))
		h.add_child(UI.expand(UI.label(line[1], Style.FONT_BODY, Style.TEXT, true)))
		v.add_child(h)
	for line in SpellInfo.weapon_lines(sid, snap):
		var h := UI.hbox(8)
		h.add_child(UI.icon(line[0], 20))
		h.add_child(UI.expand(UI.wrap(line[1], Style.FONT_SMALL, Style.SUCCESS if line[2] else Style.WARNING)))
		v.add_child(h)
	var th := UI.hbox(16)
	for line in SpellInfo.timing(sid,snap):
		var h := UI.hbox(6)
		h.add_child(UI.icon(line[0], 20))
		h.add_child(UI.label(line[1], Style.FONT_SMALL, Style.TEXT))
		th.add_child(h)
	v.add_child(th)
	var note := "Растёт от: %s %d · ход ротации каждые %.1f с" % [SpellInfo.stat_label(sid), roundi(Db.spell_stat_value(sid, st)), SpellInfo.rotation_interval(st.get("haste", 0.0))]
	if Db.SPELLS[sid]["kind"] in ["damage", "aoe_damage", "execute", "interrupt", "stun", "drain"]:
		note += " · урон до брони, без крита"
	elif Db.SPELLS[sid]["kind"] in ["heal", "hot_all", "cleanse"]:
		note += " · без крита"
	v.add_child(UI.wrap(note, Style.FONT_TINY, Style.MUTED))
	return box

func _item_popup(it: Dictionary) -> void:
	_modal(UI.item_title(it), _item_details(it, false))

# =====================================================================
# Screen: Mercenaries
# =====================================================================

func _screen_mercs() -> Control:
	var v := UI.vbox(12)
	v.add_child(_party_editor())
	var head := UI.hbox(10)
	var hv := UI.vbox(0)
	hv.add_child(UI.title("Доска гильдии", 22))
	hv.add_child(UI.label("Обновляется бесплатно после каждого нового пройденного уровня", Style.FONT_TINY, Style.MUTED))
	head.add_child(UI.expand(hv))
	var cost := Game.reroll_cost()
	var rr := UI.btn("Новые кандидаты  %d" % cost, _reroll, "secondary", Style.FONT_SMALL, "gold", 0, 50)
	rr.disabled = Game.gold < cost
	head.add_child(rr)
	v.add_child(head)
	var g := UI.grid(3, 12)
	for m in Game.board:
		g.add_child(_merc_card(m))
	if Game.board.is_empty():
		v.add_child(UI.wrap("На доске никого не осталось. Обновите её или пройдите новый уровень.", Style.FONT_BODY))
	v.add_child(UI.scroll(g))
	return v

func _party_editor() -> Control:
	var c := UI.card(Style.CARD, 10)
	var h := UI.hbox(10)
	c.add_child(h)
	var tv := UI.vbox(2)
	tv.add_child(UI.title("Ваша группа", 22))
	tv.add_child(UI.label("тыл ← → перед", Style.FONT_TINY, Style.MUTED))
	tv.add_child(UI.label("%d / %d наёмника" % [Game.hired.size(), Game.MAX_HIRED], Style.FONT_TINY, Style.MUTED))
	h.add_child(tv)
	var order: Array = Game.party_order
	for i in range(3, -1, -1):
		if i >= order.size():
			var empty := UI.flat(Style.CARD_2, 8)
			empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			empty.custom_minimum_size.y = 68
			var el := UI.label("Свободно — наймите с доски", Style.FONT_SMALL, Style.MUTED)
			el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			empty.add_child(el)
			h.add_child(empty)
			continue
		var id: String = order[i]
		var snap = Game.hero_snapshot() if id == "hero" else Game.merc_by_id(id)
		if snap == null:
			continue
		Roster.ensure_visuals(snap)
		var slot := UI.flat(Style.CARD_2, 6)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sh := UI.hbox(6)
		slot.add_child(sh)
		var av := UI.avatar(snap["sprite"], Style.ROLE_COLORS.get(snap["role"], Style.CARD_3), 56, false, snap.get("look", []), snap.get("appearance", {}))
		sh.add_child(av)
		if id != "hero":
			UI.tap_overlay(av, _merc_popup.bind(snap))
		var sv := UI.vbox(0)
		var nl := UI.label(snap["name"], Style.FONT_SMALL, Style.PRIMARY if id == "hero" else Style.TEXT, true)
		nl.clip_text = true
		sv.add_child(nl)
		sv.add_child(UI.label("%s · ур. %d" % [snap["role"], snap["level"]], Style.FONT_TINY, Style.MUTED))
		var pw := UI.label("★ %d" % Roster.power_score(snap), Style.FONT_TINY, Style.PRIMARY, true)
		if id != "hero" and int(snap["level"]) < Game.hero["level"] - 2:
			pw.text += "  устарел"
			pw.add_theme_color_override("font_color", Style.DANGER)
		sv.add_child(pw)
		sh.add_child(UI.expand(sv))
		var arrows := UI.vbox(4)
		var back := UI.btn("◀", Game.move_in_party.bind(i, 1), "ghost", 14, "", 34, 30)
		back.disabled = i >= order.size() - 1
		var fwd := UI.btn("▶", Game.move_in_party.bind(i, -1), "ghost", 14, "", 34, 30)
		fwd.disabled = i == 0
		arrows.add_child(back)
		arrows.add_child(fwd)
		sh.add_child(arrows)
		h.add_child(slot)
	return c

func _reroll() -> void:
	if await Game.reroll_board():
		_toast("На доске 6 новых кандидатов")
	else:
		_toast("Не хватает золота")

func _merc_card(m: Dictionary) -> Control:
	Roster.ensure_merc(m)
	var c := UI.card(Style.CARD, 12)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := UI.hbox(12)
	c.add_child(h)
	var role_col: Color = Style.ROLE_COLORS.get(m["role"], Style.CARD_3)
	var left := UI.vbox(6)
	var av := UI.avatar(m["sprite"], role_col, 100, false, m.get("look", []), m.get("appearance", {}))
	left.add_child(av)
	UI.tap_overlay(av, _merc_popup.bind(m))
	var gear_row := UI.hbox(4)
	for slot in Loot.SLOTS:
		gear_row.add_child(_small_gear_tile(m["gear"].get(slot), slot, 30))
	left.add_child(gear_row)
	h.add_child(left)
	var v := UI.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var top := UI.hbox(6)
	top.add_child(UI.expand(UI.label(m["name"], Style.FONT_BODY, Style.TEXT, true)))
	top.add_child(UI.chip("ур. %d" % m["level"], Style.BG_DEEP, 13))
	v.add_child(top)
	var chips := UI.hbox(6)
	chips.add_child(UI.chip(m["role"], role_col, 13))
	if not m.get("npc", true):
		chips.add_child(UI.chip("Игрок", Style.PRIMARY, 13, Style.PRIMARY_TEXT))
	v.add_child(chips)
	var sp := UI.hbox(5)
	for s in m["spells"]:
		var t := UI.tile(UI.spell_icon(s["id"]), Style.RARITY[Db.SPELLS[s["id"]]["rarity"]], 44)
		UI.tap_overlay(t, _spell_popup.bind(s["id"], m))
		sp.add_child(t)
	sp.add_child(UI.spacer())
	sp.add_child(UI.pill("star", str(Roster.power_score(m)), 15, Style.BG_DEEP))
	v.add_child(sp)
	var b: Button
	if Game.hired.size() < Game.MAX_HIRED:
		b = UI.btn("Нанять", _hire.bind(m["id"]), "success", Style.FONT_SMALL, "", 0, 44)
	else:
		b = UI.btn("Заменить…", _replace_popup.bind(m), "secondary", Style.FONT_SMALL, "", 0, 44)
	v.add_child(b)
	return c

func _small_gear_tile(it, slot: String, size_px: float) -> Control:
	if it == null:
		return UI.tile("item_" + slot, Style.CARD_3, size_px, true)
	var t := UI.tile(UI.item_icon(it), Style.QUALITY[it["rarity"]], size_px)
	UI.tap_overlay(t, _item_popup.bind(it))
	return t

func _hire(id: String) -> void:
	if Game.hire(id):
		_toast("Наёмник в группе")

func _replace_popup(m: Dictionary) -> void:
	var body := UI.wrap("Группа заполнена. Кого заменить на %s (%s, ★ %d)? Уволенный уйдёт насовсем." % [
		m["name"], m["role"], Roster.power_score(m)], Style.FONT_BODY, Style.TEXT)
	var buttons := []
	for h in Game.hired:
		buttons.append(["%s · %s ★%d" % [h["name"], h["role"], Roster.power_score(h)], _do_replace.bind(h["id"], m["id"]), "secondary", true])
	_modal("Заменить наёмника", body, buttons, "Отмена")

func _do_replace(old_id: String, new_id: String) -> void:
	if Game.replace_hired(old_id, new_id):
		_toast("Состав обновлён")

func _merc_popup(m: Dictionary) -> void:
	Roster.ensure_merc(m)
	var hired := Game.is_hired(m["id"])
	var st: Dictionary = m["stats"]
	var body := UI.vbox(12)
	var top := UI.hbox(14)
	top.add_child(UI.avatar(m["sprite"], Style.ROLE_COLORS.get(m["role"], Style.CARD_3), 110, false, m.get("look", []), m.get("appearance", {})))
	var tv := UI.vbox(6)
	var chips := UI.hbox(6)
	chips.add_child(UI.chip(m["role"], Style.ROLE_COLORS.get(m["role"], Style.CARD_3), 14))
	chips.add_child(UI.chip("ур. %d" % m["level"], Style.CARD_3, 14))
	if m.get("npc", true):
		chips.add_child(UI.chip("NPC гильдии", Style.CARD_3, 14))
	else:
		chips.add_child(UI.chip("Игрок", Style.PRIMARY, 14, Style.PRIMARY_TEXT))
	tv.add_child(chips)
	tv.add_child(UI.pill("star", "Мощь %d" % Roster.power_score(m), 22, Style.BG_DEEP))
	top.add_child(UI.expand(tv))
	body.add_child(top)
	var stats := UI.grid(3, 8)
	for row in [["hp", "HP", "%d" % st["hp"]], ["atk", "Атака", ("%d / %.1f с" % [st["atk"], st.get("atk_speed", 1.6)]) if st["atk"] > 0 else "нет"],
			["power", "Магия", "%d" % st["power"]], ["str", "Сила", "%d" % st.get("str", 0)], ["agi", "Ловкость", "%d" % st.get("agi", 0)],
			["armor", "Броня", "%d" % st["armor"]], ["haste", "Скорость", "%d%%" % roundi(st.get("haste", 0.0) * 100)],
			["crit", "Крит", "%d%%" % roundi(st.get("crit", 0.0) * 100)]]:
		var r := UI.stat_row(row[0], row[1], row[2])
		r.custom_minimum_size.x = 170
		stats.add_child(r)
	body.add_child(stats)
	body.add_child(UI.label("Снаряжение", Style.FONT_SMALL, Style.MUTED, true))
	var gear := UI.hbox(10)
	for slot in Loot.SLOTS:
		var it = m["gear"].get(slot)
		var gv := UI.hbox(6)
		gv.add_child(_small_gear_tile(it, slot, 48))
		var gl := UI.vbox(0)
		gl.add_child(UI.label(Loot.SLOT_NAMES[slot], Style.FONT_TINY, Style.MUTED))
		gl.add_child(UI.label(UI.item_title(it) if it != null else "пусто", Style.FONT_TINY,
			Style.QUALITY[it["rarity"]] if it != null else Style.MUTED, true))
		gv.add_child(gl)
		gear.add_child(UI.expand(gv))
	body.add_child(gear)
	body.add_child(UI.label("Ротация", Style.FONT_SMALL, Style.MUTED, true))
	var rot := UI.hbox(10)
	for i in m["spells"].size():
		var s: Dictionary = m["spells"][i]
		var sv := UI.hbox(6)
		var t := UI.tile(UI.spell_icon(s["id"]), Style.RARITY[Db.SPELLS[s["id"]]["rarity"]], 48)
		UI.tap_overlay(t, _spell_popup.bind(s["id"], m))
		sv.add_child(t)
		var sl := UI.vbox(0)
		sl.add_child(UI.label("%d. %s %s" % [i + 1, Db.SPELLS[s["id"]]["name"], UI.roman(s["lvl"])], Style.FONT_TINY, Style.TEXT, true))
		sl.add_child(UI.label(SpellInfo.short(s["id"], s["lvl"], m), Style.FONT_TINY, Style.MUTED))
		sv.add_child(sl)
		rot.add_child(UI.expand(sv))
	body.add_child(rot)
	var buttons := []
	buttons.append(["Таланты",_merc_talents.bind(m),"secondary",true])
	if hired:
		buttons.append(["Уволить", Game.fire.bind(m["id"]), "danger", true])
	elif Game.hired.size() < Game.MAX_HIRED:
		buttons.append(["Нанять", _hire.bind(m["id"]), "success", true])
	else:
		buttons.append(["Заменить…", _replace_popup.bind(m), "secondary", true])
	_modal(m["name"], body, buttons)

func _merc_talents(m: Dictionary) -> void:
	UI.clear(popup_layer)
	var panel := TalentPanel.new()
	panel.read_only = true
	panel.configure({"level":m["level"],"talents":m.get("talents",{})},m,func(_id): pass)
	_modal("Таланты · " + m["name"],panel)
	panel.custom_minimum_size.x = 930

# =====================================================================
# Screen: Spells (boxes + collection)
# =====================================================================

func _screen_spells() -> Control:
	var v := UI.vbox(12)
	var bar := UI.card(Style.CARD, 10)
	var h := UI.hbox(10)
	bar.add_child(h)
	h.add_child(UI.icon("box", 48))
	var tv := UI.vbox(0)
	tv.add_child(UI.title("Spell Box", 22))
	tv.add_child(UI.label("Повторы копятся и повышают уровень, до X", Style.FONT_TINY, Style.MUTED))
	h.add_child(UI.expand(tv))
	var free := UI.btn("Ежедневная", _open_box.bind("free"), "success", Style.FONT_SMALL, "box", 0, 52)
	free.disabled = not Game.free_box_available()
	if Game.free_box_available():
		UI.badge(free)
	var tok := UI.btn("Открыть (%d)" % Game.boxes, _open_box.bind("token"), "secondary", Style.FONT_SMALL, "box", 0, 52)
	tok.disabled = Game.boxes <= 0
	var left := Game.gold_boxes_left()
	var buy := UI.btn("%d" % Game.BOX_PRICE, _open_box.bind("gold"), "primary", Style.FONT_SMALL, "gold", 0, 52)
	buy.disabled = Game.gold < Game.BOX_PRICE or left < 1
	var buy10 := UI.btn("×%d  %d" % [Game.BOX_PACK, Game.BOX_PACK_PRICE], _open_pack.bind("gold"), "primary", Style.FONT_SMALL, "gold", 0, 52)
	buy10.disabled = Game.gold < Game.BOX_PACK_PRICE or left < Game.BOX_PACK
	var cb := UI.btn("%d" % Shop.BOX_CRYSTALS, _open_box.bind("crystals"), "secondary", Style.FONT_SMALL, "crystal", 0, 52)
	cb.disabled = Game.crystals < Shop.BOX_CRYSTALS
	var cb10 := UI.btn("×%d  %d" % [Game.BOX_PACK, Shop.BOX_PACK_CRYSTALS], _open_pack.bind("crystals"), "secondary", Style.FONT_SMALL, "crystal", 0, 52)
	cb10.disabled = Game.crystals < Shop.BOX_PACK_CRYSTALS
	h.add_child(free)
	h.add_child(tok)
	if Game.boxes > 1:
		h.add_child(UI.btn("Открыть все" if Game.boxes <= Game.BOX_PACK else "Открыть %d" % Game.BOX_PACK, _open_pack.bind("token"), "secondary", Style.FONT_SMALL, "box", 0, 52))
	v.add_child(bar)
	var buy_row := UI.hbox(8)
	buy_row.add_child(UI.label("Купить за золото (сегодня ещё %d):" % left, Style.FONT_SMALL, Style.MUTED))
	buy_row.add_child(buy)
	buy_row.add_child(buy10)
	buy_row.add_child(UI.spacer())
	buy_row.add_child(UI.label("за кристаллы, без лимита:", Style.FONT_SMALL, Style.MUTED))
	buy_row.add_child(cb)
	buy_row.add_child(cb10)
	v.add_child(buy_row)
	var g := UI.grid(5, 12)
	var filters := UI.hbox(4)
	for entry in [["all","Все"],["universal","Общие"],["arcane","Магия"],["life","Лечение"],["bulwark","Защита"],["melee","Мечи"],["ranged","Охота"]]:
		var filter_button := UI.btn(entry[1],_set_spell_group.bind(entry[0]),"secondary" if spell_group == entry[0] else "ghost",14,"",0,40)
		filter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filters.add_child(filter_button)
	v.add_child(filters)
	for sid in Db.SPELLS:
		if Db.SPELLS[sid].get("enemy", false) or Db.SPELLS[sid].get("hidden", false):
			continue
		if spell_group != "all" and Db.SPELLS[sid].get("group","") != spell_group:
			continue
		g.add_child(_spell_card(sid))
	v.add_child(UI.scroll(g))
	return v

func _set_spell_group(group: String) -> void:
	spell_group = group
	_refresh()

func _spell_card(sid: String) -> Control:
	var d: Dictionary = Db.SPELLS[sid]
	var lvl := Roster.spell_best_level(Game.collection, sid)
	var c := UI.card(Style.CARD, 10)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(6)
	c.add_child(v)
	var t := _spell_tile_button(sid, 64)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(t)
	var name := UI.label(d["name"], Style.FONT_SMALL, Style.TEXT if lvl > 0 else Style.MUTED, true)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.clip_text = true
	v.add_child(name)
	var num := UI.label(SpellInfo.short(sid, max(1, lvl), Game.hero_snapshot()) +
		(("  · кд %.0f с" % d["cd"]) if d.get("cd", 0.0) > 0.0 else ""), Style.FONT_TINY, Style.TEXT if lvl > 0 else Style.MUTED)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.clip_text = true
	num.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(num)
	var req: Array = d.get("req", [])
	if not req.is_empty():
		var names := []
		for w in req:
			names.append(Db.WEAPON_LABELS[w])
		var has := Db.spell_usable(sid, Game.hero_snapshot()["weapons"],Game.hero.get("talents",{}))
		var rl := UI.label("Нужен " + " / ".join(names), Style.FONT_TINY, Style.SUCCESS if has else Style.WARNING)
		rl.clip_text = true
		rl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(rl)
	if lvl == 0:
		var l := UI.label("Не открыто", Style.FONT_TINY, Style.MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		return c
	var copies := Game.spell_copies(sid)
	var cost := Game.fuse_cost(lvl)
	if lvl >= Game.SPELL_MAX_LEVEL:
		var l := UI.label("Макс. уровень", Style.FONT_TINY, Style.SUCCESS, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	elif Game.can_fuse(sid):
		v.add_child(UI.btn("Улучшить → %s" % UI.roman(lvl + 1), _fuse.bind(sid), "primary", Style.FONT_TINY, "", 0, 40))
	else:
		var ph := UI.hbox(6)
		ph.add_child(UI.expand(UI.progress(copies, cost, Style.SECONDARY, 10)))
		ph.add_child(UI.label("%d/%d" % [copies, cost], Style.FONT_TINY, Style.MUTED))
		v.add_child(ph)
	return c

func _fuse(sid: String) -> void:
	if Game.fuse(sid):
		UI.clear(popup_layer)
		_toast("%s теперь %s" % [Db.SPELLS[sid]["name"], UI.roman(Roster.spell_best_level(Game.collection, sid))])

func _open_pack(use: String) -> void:
	var res: Array = await Game.open_box_pack(use)
	if res.is_empty():
		_toast({"gold": "Не хватает золота или дневной лимит", "crystals": "Не хватает кристаллов"}.get(use, "Нечего открывать"))
		return
	_pack_popup(res)

## Result of several boxes: tiles appear one by one, duplicates are grouped.
func _pack_popup(res: Array) -> void:
	var v := UI.vbox(12)
	var counts := {}
	var order := []
	var news := {}
	for r in res:
		if not counts.has(r["spell"]):
			order.append(r["spell"])
		counts[r["spell"]] = counts.get(r["spell"], 0) + 1
		if r["new"]:
			news[r["spell"]] = true
	order.sort_custom(func(a, b): return Db.SPELLS[a]["rarity"] > Db.SPELLS[b]["rarity"])
	var g := UI.grid(5, 10)
	var i := 0
	for sid in order:
		var d: Dictionary = Db.SPELLS[sid]
		var cell := UI.vbox(4)
		cell.custom_minimum_size.x = 104
		var t := UI.tile(UI.spell_icon(sid), Style.RARITY[d["rarity"]], 72)
		t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if counts[sid] > 1:
			var ch := UI.chip("×%d" % counts[sid], Style.BG_DEEP, 13)
			ch.position = Vector2(44, 48)
			t.add_child(ch)
		if news.has(sid):
			var nw := UI.chip("Новая", Style.PRIMARY, 12, Style.PRIMARY_TEXT)
			nw.position = Vector2(-8, -8)
			t.add_child(nw)
		UI.tap_overlay(t, _spell_popup.bind(sid))
		cell.add_child(t)
		var nm := UI.wrap(d["name"], 13, Style.RARITY[d["rarity"]], true)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(nm)
		cell.modulate.a = 0.0
		g.add_child(cell)
		var tw := create_tween()
		tw.tween_interval(0.15 + i * 0.07)
		tw.tween_property(cell, "modulate:a", 1.0, 0.15)
		i += 1
	v.add_child(g)
	var fusable := 0
	for sid in Game.collection:
		if Game.can_fuse(sid):
			fusable += 1
	var summary := "Новых способностей: %d · копий всего: %d" % [news.size(), res.size()]
	if fusable > 0:
		summary += " · можно улучшить: %d" % fusable
	v.add_child(UI.label(summary, Style.FONT_SMALL, Style.MUTED))
	_modal("Spell Box ×%d" % res.size(), v, [], "Забрать")

func _open_box(use: String) -> void:
	var r: Dictionary = await Game.open_box(use)
	if r.is_empty():
		_toast({"gold": "Не хватает золота или дневной лимит", "crystals": "Не хватает кристаллов"}.get(use, "Нечего открывать"))
		return
	_box_animation(r)

# =====================================================================
# Screen: Bag
# =====================================================================

func _screen_bag() -> Control:
	var h := UI.hbox(12)
	var left := UI.card()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lv := UI.vbox(10)
	left.add_child(lv)
	var head := UI.hbox(8)
	head.add_child(UI.expand(UI.title("Сумка", 22)))
	head.add_child(UI.label("%d предм." % Game.inventory.size(), Style.FONT_SMALL, Style.MUTED))
	head.add_child(UI.btn("Переплавка", _merge_popup, "secondary", Style.FONT_TINY, "", 0, 36))
	lv.add_child(head)
	var potions := _potions_row()
	if potions != null:
		lv.add_child(potions)
	var sort_row := UI.hbox(6)
	sort_row.add_child(UI.label("Сортировка:", Style.FONT_TINY, Style.MUTED))
	for so in [["level", "Уровень"], ["rarity", "Редкость"], ["type", "Тип"]]:
		sort_row.add_child(UI.btn(so[1], _set_bag_sort.bind(so[0]), "primary" if bag_sort == so[0] else "ghost", Style.FONT_TINY, "", 0, 34))
	lv.add_child(sort_row)
	var items: Array = Game.inventory.duplicate()
	var slot_order := {}
	for i in Loot.ALL_SLOTS.size():
		slot_order[Loot.ALL_SLOTS[i]] = i
	match bag_sort:
		"rarity":
			items.sort_custom(func(a, b): return a["rarity"] * 100000 + a["ilvl"] * 100 + Loot.item_score(a) / 100.0 > b["rarity"] * 100000 + b["ilvl"] * 100 + Loot.item_score(b) / 100.0)
		"type":
			items.sort_custom(func(a, b):
				if a["slot"] != b["slot"]:
					return slot_order.get(a["slot"], 99) < slot_order.get(b["slot"], 99)
				return a["ilvl"] * 10 + a["rarity"] > b["ilvl"] * 10 + b["rarity"])
		_:
			items.sort_custom(func(a, b): return a["ilvl"] * 10 + a["rarity"] > b["ilvl"] * 10 + b["rarity"])
	if items.is_empty():
		lv.add_child(UI.wrap("Пусто. Предметы падают за первое прохождение уровня и иногда на фарме.", Style.FONT_BODY))
	var sel = null
	for it in items:
		if it["id"] == selected_item:
			sel = it
	if sel == null and items.size() > 0:
		sel = items[0]
	selected_item = sel["id"] if sel != null else ""
	var g := UI.grid(6, 10)
	for it in items:
		g.add_child(_item_tile(it))
	lv.add_child(UI.scroll(g))
	if not Game.is_online():
		var reset := UI.btn("Сбросить прогресс", _confirm_reset, "ghost", Style.FONT_TINY, "", 0, 40)
		reset.size_flags_horizontal = Control.SIZE_SHRINK_END
		lv.add_child(reset)
	h.add_child(left)

	var right := UI.card()
	right.custom_minimum_size.x = 400
	var rv := UI.vbox(10)
	right.add_child(rv)
	if sel == null:
		rv.add_child(UI.wrap("Выберите предмет, чтобы увидеть свойства.", Style.FONT_BODY))
	else:
		rv.add_child(UI.scroll(_item_details(sel, true)))
		var bh := UI.hbox(8)
		bh.add_child(UI.expand(UI.btn("Надеть", _equip.bind(sel["id"], ""), "primary", 22, "", 0, 58)))
		if sel.get("wtype", "") == "sword":
			bh.add_child(UI.btn("В левую", _equip.bind(sel["id"], "offhand"), "secondary", Style.FONT_SMALL, "", 0, 58))
		bh.add_child(UI.btn("Продать %d" % Loot.sell_price(sel), _sell.bind(sel["id"]), "danger", Style.FONT_SMALL, "gold", 0, 58))
		rv.add_child(bh)
	h.add_child(right)
	return h

## Potions and tonics in the bag: count, effect and a "Выпить" button.
func _potions_row() -> Control:
	var have := []
	for res in Prof.CONSUMABLES:
		if Rules.res_count(Game.profile, res) > 0:
			have.append(res)
	var buffs: Dictionary = Rules.active_buffs(Game.profile, Game.now())
	if have.is_empty() and buffs.is_empty():
		return null
	var v := UI.vbox(6)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	for res in have:
		var c := UI.card(Style.BG_DEEP, 8)
		var h := UI.hbox(8)
		c.add_child(h)
		var t := UI.tile("res_" + res, Style.RARITY[int(Prof.RESOURCES[res]["tier"])], 52)
		var n := UI.chip("×%d" % Rules.res_count(Game.profile, res), Style.BG_DEEP, 12)
		n.position = Vector2(30, 32)
		t.add_child(n)
		h.add_child(t)
		var tv := UI.vbox(2)
		tv.add_child(UI.label(Prof.RESOURCES[res]["name"], Style.FONT_SMALL, Style.TEXT, true))
		tv.add_child(UI.label(Prof.CONSUMABLES[res]["desc"], Style.FONT_TINY, Style.MUTED))
		h.add_child(tv)
		h.add_child(UI.btn("Выпить", _drink.bind(res), "primary", Style.FONT_SMALL, "", 0, 44))
		row.add_child(c)
	v.add_child(row)
	var parts := []
	for eff in buffs:
		var b: Dictionary = buffs[eff]
		if eff == "gather_yield":
			parts.append("тоник: +%d%% к следующему сбору" % roundi((float(b["value"]) - 1.0) * 100))
		else:
			parts.append("%s ещё %s" % [Prof.RESOURCES[b["res"]]["name"], UI.format_time(float(b["until"]) - Game.now())])
	var note := "Зелье действует с запуска следующего похода. Активно только одно: новое заменяет прежнее."
	if not parts.is_empty():
		note = "Активно: " + ", ".join(parts) + ". " + note
	v.add_child(UI.wrap(note, Style.FONT_TINY, Style.WARNING))
	return v

func _drink(res: String) -> void:
	var r: Dictionary = await Game.use_item(res)
	_toast(("%s: эффект активен" % Prof.RESOURCES[res]["name"]) if r.get("ok", false) else "Не получилось")
	_refresh()

func _merge_popup() -> void:
	UI.clear(popup_layer)
	var v := UI.vbox(10)
	v.add_child(UI.wrap("3 вещи одной редкости → 1 случайная вещь следующей редкости, уровня самой высокой из трёх. Берутся самые слабые вещи из сумки, надетые не трогаются. Переплавка идёт одна за раз и занимает время.", Style.FONT_SMALL, Style.MUTED))
	var job = Game.profile["merging"]
	if job != null:
		var done: bool = Game.now() >= float(job["ends_at"])
		var c := UI.card(Style.BG_DEEP, 8)
		var h := UI.hbox(8)
		c.add_child(h)
		var text := "Готово: %s вещь" % Items.QUALITY_NAMES[int(job["rarity"])] if done else "Идёт переплавка: %s вещь, осталось %s" % [Items.QUALITY_NAMES[int(job["rarity"])], UI.format_time(float(job["ends_at"]) - Game.now())]
		h.add_child(UI.expand(UI.wrap(text, Style.FONT_SMALL, Style.QUALITY[int(job["rarity"])], true)))
		if done:
			h.add_child(UI.btn("Забрать", _merge_take, "primary", Style.FONT_SMALL, "", 0, 44))
		else:
			var cost := Shop.rush_cost(float(job["ends_at"]) - Game.now())
			var rush := UI.btn("Сейчас  %d" % cost, _merge_rush, "secondary", Style.FONT_TINY, "crystal", 0, 44)
			rush.disabled = Game.crystals < cost
			h.add_child(rush)
		v.add_child(c)
	for r in Rules.MERGE_GOLD.size():
		var used := Rules.merge_candidates(Game.profile, r)
		var c := UI.card(Style.BG_DEEP, 8)
		var h := UI.hbox(8)
		c.add_child(h)
		var tv := UI.vbox(2)
		tv.add_child(UI.label("%s ×3 → %s · %s" % [Items.QUALITY_NAMES[r], Items.QUALITY_NAMES[r + 1], UI.format_time(float(Rules.MERGE_TIME[r]))], Style.FONT_SMALL, Style.QUALITY[r + 1], true))
		var names := []
		for it in used:
			names.append("%s ур.%d" % [UI.item_title(it), it["ilvl"]])
		tv.add_child(UI.wrap(", ".join(names) if not names.is_empty() else "нужно 3 вещи этой редкости в сумке", Style.FONT_TINY, Style.MUTED))
		h.add_child(UI.expand(tv))
		var b := UI.btn("%d" % Rules.MERGE_GOLD[r], _merge.bind(r), "primary", Style.FONT_SMALL, "gold", 0, 44)
		b.disabled = used.is_empty() or Game.gold < Rules.MERGE_GOLD[r] or job != null
		h.add_child(b)
		v.add_child(c)
	_modal("Переплавка вещей", v)

func _merge(rarity: int) -> void:
	var r: Dictionary = await Game.merge_items(rarity)
	_toast("Переплавка началась" if r.get("ok", false) else "Не хватает вещей или золота")
	_merge_popup()

func _merge_take() -> void:
	var r: Dictionary = await Game.merge_claim()
	if r.get("ok", false):
		selected_item = r["item"]["id"]
		_toast("Получено: %s (%s)" % [UI.item_title(r["item"]), Items.QUALITY_NAMES[int(r["item"]["rarity"])]])
	_merge_popup()

func _merge_rush() -> void:
	var r: Dictionary = await Game.rush("merge", "")
	_toast("Готово — можно забирать" if r.get("ok", false) else "Не хватает кристаллов")
	_merge_popup()

func _set_bag_sort(s: String) -> void:
	bag_sort = s
	_refresh()

func _equip(id: String, to: String) -> void:
	Game.equip(id, to)
	_toast("Предмет надет")

func _sell(id: String) -> void:
	Game.sell(id)
	_toast("Продано")

func _select_item(id: String) -> void:
	selected_item = id
	_refresh()

func _item_tile(it: Dictionary) -> Control:
	var t := UI.tile(UI.item_icon(it), Style.QUALITY[it["rarity"]], 84, false, it["id"] == selected_item)
	if Game.power_with(it) > Game.power_now():
		var up := UI.chip("▲", Style.SUCCESS, 12, Color("#062b16"))
		up.position = Vector2(-6, -6)
		t.add_child(up)
	var ch := UI.chip(str(it["ilvl"]), Style.BG_DEEP, 12)
	ch.position = Vector2(50, 54)
	t.add_child(ch)
	UI.tap_overlay(t, _select_item.bind(it["id"]))
	return t

func _item_details(it: Dictionary, compare: bool) -> Control:
	var v := UI.vbox(10)
	var top := UI.hbox(12)
	top.add_child(UI.tile(UI.item_icon(it), Style.QUALITY[it["rarity"]], 80))
	var tv := UI.vbox(4)
	tv.add_child(UI.label(UI.item_title(it), Style.FONT_BODY, Style.QUALITY[it["rarity"]], true))
	var chips := UI.hbox(6)
	chips.add_child(UI.chip(Items.QUALITY_NAMES[it["rarity"]], Style.QUALITY[it["rarity"]]))
	chips.add_child(UI.chip(Loot.SLOT_NAMES[it["slot"]], Style.CARD_3))
	if it.has("atype"):
		chips.add_child(UI.chip(Items.ARMOR_NAMES[it["atype"]], Style.CARD_3))
	if it.has("roll"):
		chips.add_child(UI.chip("Ковка %d%%" % roundi(float(it["roll"]) * 100), Style.CARD_3))
	chips.add_child(UI.chip("ур. %d" % it["ilvl"], Style.CARD_3))
	tv.add_child(chips)
	top.add_child(UI.expand(tv))
	v.add_child(top)
	if it.has("wtype"):
		var wl := UI.wrap(Loot.weapon_text(it), Style.FONT_SMALL, Style.WARNING)
		v.add_child(wl)
		if Loot.is_two_handed(it):
			v.add_child(UI.label("Двуручное: занимает обе руки", Style.FONT_TINY, Style.MUTED))
		elif it["wtype"] == "sword":
			v.add_child(UI.label("Можно взять в левую руку: +%d%% урона меча к каждому удару" % roundi(Loot.OFFHAND_SWORD_SHARE * 100), Style.FONT_TINY, Style.MUTED))
	for a in it["affixes"]:
		var row := UI.hbox(8)
		row.add_child(UI.icon(UI.stat_icon(a["stat"]), 24))
		row.add_child(UI.expand(UI.label(Loot.affix_text(a), Style.FONT_BODY, Style.TEXT, true)))
		v.add_child(row)
	if it.has("effect"):
		v.add_child(UI.wrap("Эффект: " + Items.effect_text(it["effect"]), Style.FONT_SMALL, Style.QUALITY[it["rarity"]]))
	if compare:
		var eq = Game.hero["equipped"][Loot.wear_slot(Game.hero["equipped"], it)]
		var diff := Game.power_with(it) - Game.power_now()
		var box := UI.flat(Style.BG_DEEP, 10)
		var bv := UI.vbox(4)
		box.add_child(bv)
		bv.add_child(UI.label("Сейчас надето:", Style.FONT_TINY, Style.MUTED))
		bv.add_child(UI.wrap(("%s — %s" % [UI.item_title(eq), UI.item_line(eq)]) if eq != null else "ничего", Style.FONT_SMALL, Style.TEXT))
		bv.add_child(UI.label(("Мощь героя +%d" % diff) if diff > 0 else ("Мощь героя %d" % diff), Style.FONT_SMALL,
			Style.SUCCESS if diff > 0 else Style.DANGER, true))
		v.add_child(box)
	return v

# =====================================================================
# Settings: offline / online, server, name, leaderboard
# =====================================================================

func _line_edit(text: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size", Style.FONT_BODY)
	e.custom_minimum_size = Vector2(0, 50)
	e.add_theme_stylebox_override("normal", Style.box(Style.BG_DEEP, Style.RADIUS_SMALL, 10))
	e.add_theme_stylebox_override("focus", Style.box(Style.CARD_3, Style.RADIUS_SMALL, 10))
	return e

func _settings_popup() -> void:
	var v := UI.vbox(10)
	var online := Game.is_online()
	var head := UI.hbox(8)
	head.add_child(UI.chip("Онлайн" if online else "Офлайн", Style.SUCCESS if online else Style.CARD_3, Style.FONT_SMALL,
		Color("#062b16") if online else Style.TEXT))
	if Game.online_status != "" and Game.online_status != "Онлайн":
		head.add_child(UI.label(Game.online_status, Style.FONT_SMALL, Style.MUTED))
	v.add_child(head)
	v.add_child(UI.label("Имя героя", Style.FONT_TINY, Style.MUTED, true))
	var name_edit := _line_edit(str(Game.hero.get("name", "Герой")), "2–16 символов")
	name_edit.max_length = 16
	v.add_child(name_edit)
	v.add_child(UI.label("Адрес сервера", Style.FONT_TINY, Style.MUTED, true))
	var url_edit := _line_edit(Game.server_url, "https://api.example.com")
	url_edit.editable = not online
	v.add_child(url_edit)
	if online:
		v.add_child(UI.label("Аккаунт: " + Game.account_id, Style.FONT_TINY, Style.MUTED))
		var lb_box := UI.vbox(4)
		lb_box.add_child(UI.label("Загрузка рейтинга…", Style.FONT_SMALL, Style.MUTED))
		v.add_child(lb_box)
		_fill_leaderboard(lb_box)
	else:
		v.add_child(UI.wrap("Офлайн-прогресс хранится на этом устройстве. В онлайне у вас отдельный аккаунт на сервере: ваш герой появляется в найме у других игроков, а за каждый найм вы получаете золото.", Style.FONT_TINY))
	var buttons := [["Сохранить имя", _rename.bind(name_edit), "ghost", true]]
	if online:
		buttons.append(["Играть офлайн", Game.go_offline, "danger", true])
	else:
		buttons.append(["Подключиться", _connect.bind(url_edit, name_edit), "primary", true])
	_modal("Настройки", v, buttons)

func _rename(edit: LineEdit) -> void:
	if Game.rename_hero(edit.text):
		_toast("Имя сохранено")
	else:
		_toast("Имя: от 2 до 16 символов")

func _connect(url_edit: LineEdit, name_edit: LineEdit) -> void:
	var url := url_edit.text
	var nm := name_edit.text
	_toast("Подключение…")
	var r: Dictionary = await Game.connect_online(url, nm)
	_toast("Вы в онлайне" if r.get("ok", false) else str(r.get("error", "Ошибка")))

func _fill_leaderboard(box: VBoxContainer) -> void:
	var d: Dictionary = await Game.leaderboard()
	if not is_instance_valid(box):
		return
	UI.clear(box)
	if d.is_empty():
		box.add_child(UI.label("Рейтинг недоступен", Style.FONT_SMALL, Style.MUTED))
		return
	var h := UI.hbox(8)
	h.add_child(UI.icon("trophy", 26))
	h.add_child(UI.label("Игроков: %d" % d.get("players", 0), Style.FONT_SMALL, Style.TEXT, true))
	box.add_child(h)
	var i := 0
	for row in d.get("campaign", []).slice(0, 5):
		i += 1
		box.add_child(UI.label("%d. %s — уровень %d, герой %d ур." % [i, row["name"], row["closed_level"], row["level"]], Style.FONT_SMALL, Style.TEXT))
	if not d.get("most_hired", []).is_empty():
		box.add_child(UI.label("Чаще всех нанимают:", Style.FONT_TINY, Style.MUTED, true))
		for row in d["most_hired"].slice(0, 3):
			box.add_child(UI.label("%s (%s) — %d раз" % [row["name"], row["role"], row["hires"]], Style.FONT_SMALL, Style.TEXT))

func _confirm_reset() -> void:
	_modal("Сброс прогресса", UI.wrap("Удалить сохранение и начать заново?", Style.FONT_BODY, Style.TEXT),
		[["Удалить", Game.reset_progress, "danger", true]])

# =====================================================================
# Popups, rewards, toasts
# =====================================================================

## buttons: [[text, callable, kind, enabled], ...]; every button also closes the modal.
func _modal(title_text: String, body: Control, buttons: Array = [], close_text: String = "Закрыть") -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_layer.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(cc)
	var p := UI.card(Style.CARD, 20, 18)
	p.custom_minimum_size = Vector2(600, 0)
	cc.add_child(p)
	var v := UI.vbox(14)
	p.add_child(v)
	v.add_child(UI.title(title_text, Style.FONT_TITLE))
	body.custom_minimum_size.x = 560
	v.add_child(body)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	row.alignment = FlowContainer.ALIGNMENT_END
	for b in buttons:
		var bt := UI.btn(b[0], _modal_action.bind(dim, b[1]), b[2], Style.FONT_BODY, "", 0, 52)
		bt.disabled = not b[3]
		row.add_child(bt)
	if close_text != "":
		row.add_child(UI.btn(close_text, dim.queue_free, "ghost", Style.FONT_BODY, "", 130, 52))
	v.add_child(row)
	p.modulate.a = 0.0
	p.scale = Vector2(0.92, 0.92)
	_pop_in.call_deferred(p)
	return dim

func _pop_in(p: Control) -> void:
	if not is_instance_valid(p):
		return
	p.pivot_offset = p.size / 2.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(p, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.12)

func _modal_action(dim: Control, cb: Callable) -> void:
	dim.queue_free()
	cb.call()

func _toast(text: String) -> void:
	var p := UI.flat(Style.CARD_3, 12, 24)
	var l := UI.label(text, Style.FONT_SMALL, Style.TEXT, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = min(700.0, text.length() * 10.0 + 20.0)
	p.add_child(l)
	p.modulate.a = 0.0
	toast_layer.add_child(p)
	_place_toast.call_deferred(p)

func _place_toast(p: Control) -> void:
	if not is_instance_valid(p):
		return
	p.position = Vector2((size.x - p.size.x) / 2.0, 84)
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.8)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(p.queue_free)

## Reports that are not a direct answer to a tap (assist rewards from the server, etc.).
func _on_report(r: Dictionary) -> void:
	match r.get("type", ""):
		"assists":
			var v := UI.vbox(10)
			v.add_child(UI.wrap("Другие игроки нанимали вашего героя: %d раз." % r["hires"], Style.FONT_BODY, Style.TEXT))
			v.add_child(UI.pill("gold", "+%d" % r["gold"], 24))
			_modal("Вашего героя нанимали", v, [], "Отлично")
		"rewards", "push_abort":
			_show_rewards(r, "Добыча")

func _on_expedition_finished(r: Dictionary) -> void:
	if r.get("closed", false):
		selected_level = min(Game.closed_level + 1, Db.level_count())
		_refresh()
	var buttons := []
	if r["won"] > 0:
		var ready := Game.party_ready()
		if int(r["level"]) < Db.level_count():
			buttons.append(["Следующий уровень", _start.bind(int(r["level"]) + 1, "push"), "primary", ready])
		buttons.append(["Фармить этот уровень", _start.bind(int(r["level"]), "farm"), "secondary", ready])
	_show_rewards(r, "Уровень пройден!" if r["won"] > 0 else "Уровень не пройден", buttons)

func _show_rewards(r: Dictionary, title_text: String, buttons: Array = []) -> void:
	if r.is_empty():
		return
	var v := UI.vbox(12)
	if r.has("reason") and r["won"] == 0:
		v.add_child(UI.wrap("%s на волне %d из %d. Уровень не открыт, награда за достигнутый прогресс." % [
			r["reason"], r["waves"] + 1, r["total_waves"]], Style.FONT_BODY, Style.TEXT))
	if r.get("closed", false):
		v.add_child(UI.chip("Уровень %d закрыт — доступен фарм" % r["level"], Style.SUCCESS, Style.FONT_SMALL, Color("#062b16")))
	var pills := UI.hbox(10)
	var gold_pill := UI.pill("gold", "+0", 24)
	pills.add_child(gold_pill)
	pills.add_child(UI.pill("xp", "+%d" % r["xp"], 24))
	if r.get("boxes", 0) > 0:
		pills.add_child(UI.pill("box", "+%d" % r["boxes"], 24))
	if r.get("crystals", 0) > 0:
		pills.add_child(UI.pill("crystal", "+%d" % r["crystals"], 24, Color("#3a2f5a")))
	v.add_child(pills)
	if r.get("boost_gold", 0) > 0:
		v.add_child(UI.label("Из них ускорение ×2: +%d золота, +%d опыта" % [r["boost_gold"], r.get("boost_xp", 0)], Style.FONT_SMALL, Style.SUCCESS))
	if r.get("level_ups", 0) > 0:
		v.add_child(UI.chip("Новый уровень героя: %d" % Game.hero["level"], Style.SECONDARY, Style.FONT_SMALL))
	if r.get("board_refreshed", false):
		v.add_child(UI.chip("Гильдия прислала 6 новых наёмников", Style.CARD_3, Style.FONT_SMALL))
	if r.get("won", 0) + r.get("lost", 0) > 1:
		v.add_child(UI.label("Забегов: побед %d, поражений %d, убито %d" % [r["won"], r["lost"], r["kills"]], Style.FONT_SMALL, Style.MUTED))
	if not r.get("mats", {}).is_empty():
		v.add_child(mats_row(r["mats"]))
	if r.get("auto_sold", 0) > 0:
		v.add_child(UI.label("Сумка не резиновая: ещё %d предм. проданы за %d золота" % [r["auto_sold"], r["auto_sold_gold"]], Style.FONT_SMALL, Style.MUTED))
	var items: Array = r["items"]
	if items.size() > 0:
		var ih := HFlowContainer.new()
		ih.add_theme_constant_override("h_separation", 8)
		ih.add_theme_constant_override("v_separation", 8)
		for i in min(items.size(), 12):
			var t := UI.tile(UI.item_icon(items[i]), Style.QUALITY[items[i]["rarity"]], 64)
			t.modulate.a = 0.0
			ih.add_child(t)
			var tw := create_tween()
			tw.tween_interval(0.25 + i * 0.08)
			tw.tween_property(t, "modulate:a", 1.0, 0.15)
		v.add_child(ih)
		if items.size() > 12:
			v.add_child(UI.label("и ещё %d" % (items.size() - 12), Style.FONT_SMALL, Style.MUTED))
	if r.get("won", 0) == 0 and r.has("reason"):
		v.add_child(UI.wrap("Совет: проверьте состав (лекарь, щиты, interrupt) и порядок способностей.", Style.FONT_SMALL))
	var window := _modal(title_text, v, buttons, "Закрыть" if not buttons.is_empty() else "Отлично")
	if watch_layer.visible:
		_keep_meters_visible(window)
	var lbl: Label = gold_pill.get_child(0).get_child(1)
	var tw2 := lbl.create_tween()  # bound to the label: stops if the window is closed early
	tw2.tween_interval(0.15)
	tw2.tween_method(_set_gold_text.bind(lbl), 0.0, float(r["gold"]), 0.6)

## The result window sits above the meters and hardly dims the battle behind it.
func _keep_meters_visible(window: Control) -> void:
	if window is ColorRect:
		window.color.a = 0.2
		window.get_child(0).offset_bottom = -METER_HEIGHT

## Row of resource pills: icon + "+N" (materials from combat, gathering, crafting).
func mats_row(mats: Dictionary) -> Control:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 8)
	f.add_theme_constant_override("v_separation", 8)
	for res in mats:
		if res.begins_with("rcp_"):
			if int(mats[res]) <= 0:
				continue
			var rp := UI.pill("recipe", "Рецепт: " + Prof.RECIPES.get(res.substr(4), {}).get("name", res), Style.FONT_SMALL, Style.SECONDARY)
			f.add_child(rp)
			continue
		var pill := UI.pill("res_" + res, "+%d" % int(mats[res]), Style.FONT_SMALL, Style.BG_DEEP)
		pill.tooltip_text = Prof.RESOURCES.get(res, {}).get("name", res)
		f.add_child(pill)
	return f

func _set_gold_text(x: float, lbl: Label) -> void:
	if is_instance_valid(lbl):
		lbl.text = "+%d" % int(x)

func _box_animation(r: Dictionary) -> void:
	var d: Dictionary = Db.SPELLS[r["spell"]]
	var v := UI.vbox(12)
	var stage := CenterContainer.new()
	stage.custom_minimum_size = Vector2(560, 140)
	v.add_child(stage)
	var box_icon := UI.icon("box", 120)
	box_icon.pivot_offset = Vector2(60, 60)
	stage.add_child(box_icon)
	var reveal := UI.vbox(8)
	reveal.modulate.a = 0.0
	reveal.visible = false
	var t := UI.tile(UI.spell_icon(r["spell"]), Style.RARITY[d["rarity"]], 110)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reveal.add_child(t)
	var nm := UI.title(d["name"], 24, Style.RARITY[d["rarity"]])
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reveal.add_child(nm)
	var chips := UI.hbox(6)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_child(UI.chip(Db.RARITY_NAMES[d["rarity"]], Style.RARITY[d["rarity"]]))
	if r["new"]:
		chips.add_child(UI.chip("Новая!", Style.PRIMARY, Style.FONT_TINY, Style.PRIMARY_TEXT))
	else:
		var slvl := Roster.spell_best_level(Game.collection, r["spell"])
		if slvl >= Game.SPELL_MAX_LEVEL:
			chips.add_child(UI.chip("Макс. уровень", Style.CARD_3))
		else:
			chips.add_child(UI.chip("Копий для %s: %d/%d" % [UI.roman(slvl + 1), Game.spell_copies(r["spell"]), Game.fuse_cost(slvl)], Style.CARD_3))
	reveal.add_child(chips)
	var desc := UI.wrap(d["desc"], Style.FONT_SMALL)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reveal.add_child(desc)
	v.add_child(reveal)
	_modal("Spell Box", v, [], "Забрать")
	var tw := create_tween()
	for i in 6:
		tw.tween_property(box_icon, "rotation", 0.18 if i % 2 == 0 else -0.18, 0.07)
	tw.tween_property(box_icon, "rotation", 0.0, 0.05)
	tw.tween_property(box_icon, "scale", Vector2(1.3, 1.3), 0.12)
	tw.tween_property(box_icon, "modulate:a", 0.0, 0.12)
	tw.tween_callback(_reveal_box.bind(stage, reveal))
	tw.tween_property(reveal, "modulate:a", 1.0, 0.2)

func _reveal_box(stage: Control, reveal: Control) -> void:
	stage.visible = false
	reveal.visible = true

func _show_offline_report(o: Dictionary) -> void:
	var v := UI.vbox(12)
	var mode := "штурм" if o["mode"] == "push" else "фарм"
	v.add_child(UI.wrap("Прошло %s, шёл %s уровня %d." % [UI.format_time(o["away"]), mode, o["level"]], Style.FONT_BODY, Style.TEXT))
	var pills := UI.hbox(10)
	pills.add_child(UI.pill("gold", "+%d" % o["gold"], 24))
	pills.add_child(UI.pill("xp", "+%d" % o["xp"], 24))
	pills.add_child(UI.pill("item_weapon", "+%d" % o["items"], 24))
	v.add_child(pills)
	v.add_child(UI.label("Побед %d, поражений %d. Добычу заберите на экране «Поход»." % [o["won"], o["lost"]], Style.FONT_SMALL, Style.MUTED))
	_modal("Пока вас не было", v, [], "Хорошо")
