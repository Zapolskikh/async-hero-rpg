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
	["bag", "Сумка", "nav_bag"],
]

var current_tab := "expedition"
var selected_level := 1
var selected_item := ""

var top_bar: PanelContainer
var nav_bar: PanelContainer
var content: MarginContainer
var exp_status: Label
var watch_layer: Control
var watch_label: Label
var battle_view: Control
var popup_layer: Control
var toast_layer: Control

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
	Game.changed.connect(_refresh)
	Game.expedition_finished.connect(_on_expedition_finished)
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
		if a.begins_with("--shots"):
			add_child(load("res://tests/shot_runner.gd").new())


# =====================================================================
# Frame: top bar, bottom navigation, screen switching
# =====================================================================

func _switch(tab: String) -> void:
	if tab == current_tab:
		return
	current_tab = tab
	_refresh()
	content.modulate.a = 0.0
	create_tween().tween_property(content, "modulate:a", 1.0, 0.15)

func _refresh() -> void:
	if not Game.level_unlocked(selected_level):
		selected_level = min(Game.closed_level + 1, Db.level_count())
	_build_top_bar()
	_build_nav()
	UI.clear(content)
	exp_status = null
	match current_tab:
		"expedition": content.add_child(_screen_expedition())
		"hero": content.add_child(_screen_hero())
		"mercs": content.add_child(_screen_mercs())
		"spells": content.add_child(_screen_spells())
		"bag": content.add_child(_screen_bag())

func _build_top_bar() -> void:
	UI.clear(top_bar)
	var h := UI.hbox(12)
	top_bar.add_child(h)
	var hero: Dictionary = Game.hero
	var av := UI.avatar("hero", Style.ROLE_COLORS["Герой"], 56)
	h.add_child(av)
	UI.tap_overlay(av, _switch.bind("hero"))
	var who := UI.vbox(2)
	who.add_child(UI.label("%s · ур. %d" % [hero["name"], hero["level"]], Style.FONT_BODY, Style.TEXT, true))
	who.add_child(UI.progress(hero["xp"], Db.xp_to_next(hero["level"]), Style.SECONDARY, 10, 170))
	h.add_child(who)
	h.add_child(UI.spacer())
	var ex: Expedition = Game.expedition
	if ex != null:
		var mode := "Фарм" if ex.mode == "farm" else "Штурм"
		h.add_child(UI.pill("loop" if ex.mode == "farm" else "swords", "%s · ур. %d" % [mode, ex.level], Style.FONT_SMALL, Style.CARD))
	h.add_child(UI.pill("gold", str(Game.gold)))
	h.add_child(UI.pill("box", str(Game.boxes)))

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
	var ex: Expedition = Game.expedition
	var bag_upgrade := false
	for it in Game.inventory:
		var eq = Game.hero["equipped"][it["slot"]]
		if eq == null or Loot.item_score(it) > Loot.item_score(eq):
			bag_upgrade = true
			break
	var fusable := false
	for sid in Game.collection:
		for k in Game.collection[sid]:
			if Game.can_fuse(sid, int(k)):
				fusable = true
	return {
		"expedition": ex == null or (ex.mode == "farm" and ex.has_rewards()),
		"hero": Game.hero["rotation"].size() < 3,
		"mercs": not Game.party_ready(),
		"spells": Game.free_box_available() or Game.boxes > 0 or fusable,
		"bag": bag_upgrade,
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
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	for lvl in range(1, Db.level_count() + 1):
		if lvl > 1:
			var line := ColorRect.new()
			line.custom_minimum_size = Vector2(30, 6)
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.color = Style.SUCCESS if Game.level_unlocked(lvl) else Style.CARD_3
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(line)
		h.add_child(_path_node(lvl))
	var s := UI.scroll(h, true)
	s.custom_minimum_size.y = 92
	c.add_child(s)
	return c

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

func _select_level(lvl: int) -> void:
	selected_level = lvl
	_refresh()

func _is_boss_level(lvl: int) -> bool:
	for w in Db.LEVELS[lvl - 1]["waves"]:
		if "boss_lich" in w:
			return true
	return lvl % 5 == 0

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
	var ex: Expedition = Game.expedition
	var top := UI.hbox(8)
	top.position = Vector2(12, 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ex == null:
		top.add_child(UI.chip("Группа отдыхает", Style.CARD_2, Style.FONT_SMALL))
		holder.add_child(top)
		return c
	UI.tap_overlay(holder, _open_watch)
	holder.add_child(top)
	var mode := "Фарм" if ex.mode == "farm" else "Штурм"
	top.add_child(UI.chip("%s · ур. %d · забег %d" % [mode, ex.level, ex.run_index + 1],
		Style.SUCCESS if ex.mode == "farm" else Style.PRIMARY, Style.FONT_SMALL,
		Color("#062b16") if ex.mode == "farm" else Style.PRIMARY_TEXT))
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
	var v := UI.vbox(10)
	c.add_child(v)

	var head := UI.hbox(8)
	head.add_child(UI.expand(UI.title("%d. %s" % [lvl, Db.LEVELS[lvl - 1]["name"]], 24)))
	head.add_child(UI.chip("Пройден" if closed else "Новый", Style.SUCCESS if closed else Style.PRIMARY,
		Style.FONT_TINY, Color("#062b16") if closed else Style.PRIMARY_TEXT))
	v.add_child(head)

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
	var row := UI.hbox(12)
	var fv := UI.vbox(4)
	fv.add_child(UI.label("Враги · волн: %d" % Db.LEVELS[lvl - 1]["waves"].size(), Style.FONT_TINY, Style.MUTED))
	fv.add_child(foes)
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
	for hnt in hints:
		flow.add_child(UI.chip(hnt, Style.DANGER if hnt == "Risky" else Style.CARD_3))
	v.add_child(flow)
	v.add_child(UI.spacer())

	var party := UI.hbox(6)
	var order: Array = Game.party_order
	for i in range(order.size() - 1, -1, -1):
		var snap = Game.hero_snapshot() if order[i] == "hero" else Game.merc_by_id(order[i])
		if snap != null:
			Roster.ensure_visuals(snap)
			party.add_child(UI.avatar(snap["sprite"], Style.ROLE_COLORS.get(snap["role"], Style.CARD_3), 48))
	party.add_child(UI.spacer())
	party.add_child(UI.btn("Состав", _switch.bind("mercs"), "ghost", Style.FONT_SMALL, "nav_mercs", 0, 46))
	v.add_child(party)

	exp_status = UI.wrap("", Style.FONT_TINY, Style.MUTED)
	v.add_child(exp_status)
	v.add_child(_level_actions(lvl, closed))
	_tick_status()
	return c

func _level_actions(lvl: int, closed: bool) -> Control:
	var h := UI.hbox(8)
	var ex: Expedition = Game.expedition
	if ex != null and ex.level == lvl:
		if ex.mode == "farm":
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
	_show_rewards(Game.collect(), "Добыча фарма")

func _stop_expedition() -> void:
	_show_rewards(Game.stop_expedition(), "Поход остановлен")

func _tick_status() -> void:
	if exp_status == null or not is_instance_valid(exp_status):
		return
	var ex: Expedition = Game.expedition
	if ex == null:
		exp_status.text = "Поход идёт и при закрытой игре (до 12 ч)."
		return
	exp_status.text = "Сейчас: ур. %d, волна %d/%d · накоплено %d золота, %d опыта, %d предм. · побед %d, поражений %d" % [
		ex.level, min(ex.wave_index + 1, ex.total_waves()), ex.total_waves(), ex.gold, ex.xp,
		ex.items.size(), ex.runs_won, ex.runs_lost]

func _start(lvl: int, mode: String) -> void:
	if Game.expedition != null and Game.expedition.has_rewards():
		_show_rewards(Game.stop_expedition(), "Прошлый поход завершён")
	if Game.start_expedition(lvl, mode):
		_open_watch()

# =====================================================================
# Watch layer (full-screen battle)
# =====================================================================

func _build_watch_layer() -> void:
	watch_layer = Control.new()
	watch_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	watch_layer.visible = false
	add_child(watch_layer)
	battle_view = BattleView.new()
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
	for sp in [1.0, 2.0, 4.0]:
		h.add_child(UI.btn("x%d" % int(sp), _set_speed.bind(sp), "ghost", Style.FONT_BODY, "", 64, 48))

func _set_speed(s: float) -> void:
	Game.watch_speed = s

func _open_watch() -> void:
	watch_layer.visible = true
	watch_layer.modulate.a = 0.0
	create_tween().tween_property(watch_layer, "modulate:a", 1.0, 0.15)

func _close_watch() -> void:
	watch_layer.visible = false
	Game.watch_speed = 1.0
	_refresh()

func _process(_delta: float) -> void:
	if watch_layer.visible:
		var ex: Expedition = Game.expedition
		if ex == null:
			watch_label.text = "Поход завершён"
		else:
			var mode := "Штурм" if ex.mode == "push" else "Фарм"
			watch_label.text = "%s · ур. %d · забег %d · волна %d/%d · x%d" % [mode, ex.level, ex.run_index + 1,
				min(ex.wave_index + 1, ex.total_waves()), ex.total_waves(), int(Game.watch_speed)]

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
	var sv := UI.vbox(10)
	sc.add_child(sv)
	sv.add_child(UI.title("Характеристики", 22))
	var pw := UI.flat(Style.BG_DEEP, 10)
	var pwh := UI.hbox(10)
	pw.add_child(pwh)
	pwh.add_child(UI.icon("star", 34))
	pwh.add_child(UI.expand(UI.label("Сила", Style.FONT_BODY, Style.MUTED)))
	pwh.add_child(UI.title(str(Roster.power_score(snap)), 28, Style.PRIMARY))
	sv.add_child(pw)
	sv.add_child(UI.stat_row("hp", "Здоровье", "%d" % st["hp"]))
	sv.add_child(UI.stat_row("atk", "Атака", "%d" % st["atk"]))
	sv.add_child(UI.stat_row("power", "Магия", "%d" % st["power"]))
	sv.add_child(UI.stat_row("armor", "Броня", "%d" % st["armor"]))
	sv.add_child(UI.stat_row("haste", "Скорость", "%d%%" % roundi(st["haste"] * 100)))
	sv.add_child(UI.stat_row("crit", "Крит", "%d%%" % roundi(st["crit"] * 100)))
	sv.add_child(UI.stat_row("loop", "Ход ротации", "%.1f с" % SpellInfo.rotation_interval(st["haste"])))
	sv.add_child(UI.spacer())
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
	var left_col := UI.vbox(12)
	left_col.alignment = BoxContainer.ALIGNMENT_CENTER
	left_col.add_child(_gear_slot("weapon"))
	doll.add_child(left_col)
	var stage := UI.vbox(0)
	stage.alignment = BoxContainer.ALIGNMENT_END
	var big := UI.portrait("hero", 230)
	big.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.add_child(big)
	var ped := UI.flat(Style.BG_DEEP, 0, 20)
	ped.custom_minimum_size = Vector2(200, 18)
	ped.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.add_child(ped)
	doll.add_child(stage)
	var right_col := UI.vbox(12)
	right_col.alignment = BoxContainer.ALIGNMENT_CENTER
	right_col.add_child(_gear_slot("armor"))
	right_col.add_child(_gear_slot("trinket"))
	doll.add_child(right_col)
	mv.add_child(doll)

	var rot_head := UI.hbox(8)
	rot_head.add_child(UI.title("Ротация", 20))
	rot_head.add_child(UI.expand(UI.label("1 → 2 → 3 → снова 1, неприменимая пропускается", Style.FONT_TINY, Style.MUTED)))
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
	var it = Game.hero["equipped"][slot]
	var v := UI.vbox(4)
	var t: Control
	if it == null:
		t = UI.tile("item_" + slot, Style.CARD_3, 84, true)
	else:
		t = UI.tile(UI.item_icon(it), Style.RARITY[it["rarity"]], 84)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UI.tap_overlay(t, _gear_popup.bind(slot))
	v.add_child(t)
	var l := UI.label(Loot.SLOT_NAMES[slot], Style.FONT_TINY, Style.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v

func _rotation_slot(i: int, sid: String) -> Control:
	var v := UI.vbox(4)
	v.custom_minimum_size.x = 120
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
		name = "%s %s\n%s" % [Db.SPELLS[sid]["name"], UI.roman(lv), SpellInfo.short(sid, lv, Game.hero_snapshot()["stats"]["power"])]
	var l := UI.wrap(name, Style.FONT_TINY, Style.TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
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

func _gear_popup(slot: String) -> void:
	var it = Game.hero["equipped"][slot]
	if it == null:
		var body := UI.wrap("Слот «%s» пуст. Предметы падают за первое прохождение уровня и иногда на фарме." % Loot.SLOT_NAMES[slot], Style.FONT_BODY, Style.TEXT)
		_modal(Loot.SLOT_NAMES[slot], body, [["В сумку", _switch.bind("bag"), "secondary", true]])
		return
	_modal(UI.item_title(it), _item_details(it, false), [["Снять", Game.unequip.bind(slot), "danger", true]])

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
	var power: float = snap["stats"]["power"]
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
	if own and lvl > 0:
		var copies := int(Game.collection.get(sid, {}).get(str(lvl), 0))
		var ph := UI.hbox(8)
		ph.add_child(UI.label("Копии %s: %d / %d" % [UI.roman(lvl), copies, Game.FUSE_COUNT], Style.FONT_SMALL, Style.MUTED))
		ph.add_child(UI.expand(UI.progress(copies, Game.FUSE_COUNT, Style.SECONDARY, 12)))
		ph.add_child(UI.label("%s: %s" % [UI.roman(lvl + 1), SpellInfo.short(sid, lvl + 1, power)], Style.FONT_SMALL, Style.TEXT, true))
		body.add_child(ph)
	var buttons := []
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
	for line in SpellInfo.effects(sid, lvl, st["power"]):
		var h := UI.hbox(8)
		h.add_child(UI.icon(line[0], 24))
		h.add_child(UI.expand(UI.label(line[1], Style.FONT_BODY, Style.TEXT, true)))
		v.add_child(h)
	var th := UI.hbox(16)
	for line in SpellInfo.timing(sid):
		var h := UI.hbox(6)
		h.add_child(UI.icon(line[0], 20))
		h.add_child(UI.label(line[1], Style.FONT_SMALL, Style.TEXT))
		th.add_child(h)
	v.add_child(th)
	var note := "Сила заклинаний %d · ход ротации каждые %.1f с" % [st["power"], SpellInfo.rotation_interval(st.get("haste", 0.0))]
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
		var av := UI.avatar(snap["sprite"], Style.ROLE_COLORS.get(snap["role"], Style.CARD_3), 56)
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
	if Game.reroll_board():
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
	var av := UI.avatar(m["sprite"], role_col, 100)
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
	chips.add_child(_tier_chip(m))
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

func _tier_chip(m: Dictionary) -> Control:
	var t := int(m.get("tier", 1))
	var ch := UI.chip(Roster.TIERS[t]["name"], Style.TIER_COLORS[t], 13, Style.TIER_TEXT[t])
	ch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return ch

func _small_gear_tile(it, slot: String, size_px: float) -> Control:
	if it == null:
		return UI.tile("item_" + slot, Style.CARD_3, size_px, true)
	var t := UI.tile(UI.item_icon(it), Style.RARITY[it["rarity"]], size_px)
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
	top.add_child(UI.avatar(m["sprite"], Style.ROLE_COLORS.get(m["role"], Style.CARD_3), 110))
	var tv := UI.vbox(6)
	var chips := UI.hbox(6)
	chips.add_child(UI.chip(m["role"], Style.ROLE_COLORS.get(m["role"], Style.CARD_3), 14))
	chips.add_child(_tier_chip(m))
	chips.add_child(UI.chip("ур. %d" % m["level"], Style.CARD_3, 14))
	chips.add_child(UI.chip("NPC гильдии", Style.CARD_3, 14))
	tv.add_child(chips)
	tv.add_child(UI.pill("star", "Сила %d" % Roster.power_score(m), 22, Style.BG_DEEP))
	top.add_child(UI.expand(tv))
	body.add_child(top)
	var stats := UI.grid(3, 8)
	for row in [["hp", "HP", "%d" % st["hp"]], ["atk", "Атака", "%d" % st["atk"]], ["power", "Магия", "%d" % st["power"]],
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
			Style.RARITY[it["rarity"]] if it != null else Style.MUTED, true))
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
		sl.add_child(UI.label(SpellInfo.short(s["id"], s["lvl"], st["power"]), Style.FONT_TINY, Style.MUTED))
		sv.add_child(sl)
		rot.add_child(UI.expand(sv))
	body.add_child(rot)
	var buttons := []
	if hired:
		buttons.append(["Уволить", Game.fire.bind(m["id"]), "danger", true])
	elif Game.hired.size() < Game.MAX_HIRED:
		buttons.append(["Нанять", _hire.bind(m["id"]), "success", true])
	else:
		buttons.append(["Заменить…", _replace_popup.bind(m), "secondary", true])
	_modal(m["name"], body, buttons)

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
	tv.add_child(UI.label("5 одинаковых копий → следующий уровень", Style.FONT_TINY, Style.MUTED))
	h.add_child(UI.expand(tv))
	var free := UI.btn("Ежедневная", _open_box.bind("free"), "success", Style.FONT_SMALL, "box", 0, 52)
	free.disabled = not Game.free_box_available()
	if Game.free_box_available():
		UI.badge(free)
	var tok := UI.btn("Открыть (%d)" % Game.boxes, _open_box.bind("token"), "secondary", Style.FONT_SMALL, "box", 0, 52)
	tok.disabled = Game.boxes <= 0
	var buy := UI.btn("%d" % Game.BOX_PRICE, _open_box.bind("gold"), "primary", Style.FONT_SMALL, "gold", 0, 52)
	buy.disabled = Game.gold < Game.BOX_PRICE
	h.add_child(free)
	h.add_child(tok)
	h.add_child(buy)
	v.add_child(bar)
	var g := UI.grid(5, 12)
	for sid in Db.SPELLS:
		if Db.SPELLS[sid].get("enemy", false):
			continue
		g.add_child(_spell_card(sid))
	v.add_child(UI.scroll(g))
	return v

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
	var num := UI.label(SpellInfo.short(sid, max(1, lvl), Game.hero_snapshot()["stats"]["power"]) +
		(("  · кд %.0f с" % d["cd"]) if d.get("cd", 0.0) > 0.0 else ""), Style.FONT_TINY, Style.TEXT if lvl > 0 else Style.MUTED)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(num)
	if lvl == 0:
		var l := UI.label("Не открыто", Style.FONT_TINY, Style.MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		return c
	var copies := int(Game.collection[sid].get(str(lvl), 0))
	var fuse_lvl := 0
	for k in Game.collection[sid]:
		if Game.can_fuse(sid, int(k)):
			fuse_lvl = int(k)
	if fuse_lvl > 0:
		v.add_child(UI.btn("Слить → %s" % UI.roman(fuse_lvl + 1), _fuse.bind(sid, fuse_lvl), "primary", Style.FONT_TINY, "", 0, 40))
	else:
		var ph := UI.hbox(6)
		ph.add_child(UI.expand(UI.progress(copies, Game.FUSE_COUNT, Style.SECONDARY, 10)))
		ph.add_child(UI.label("%d/%d" % [copies, Game.FUSE_COUNT], Style.FONT_TINY, Style.MUTED))
		v.add_child(ph)
	return c

func _fuse(sid: String, lvl: int) -> void:
	if Game.fuse(sid, lvl):
		_toast("%s теперь %s" % [Db.SPELLS[sid]["name"], UI.roman(lvl + 1)])

func _open_box(use: String) -> void:
	var r := Game.open_box(use)
	if r.is_empty():
		_toast("Нечего открывать")
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
	lv.add_child(head)
	var items: Array = Game.inventory.duplicate()
	items.sort_custom(func(a, b): return a["rarity"] * 1000 + Loot.item_score(a) > b["rarity"] * 1000 + Loot.item_score(b))
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
		rv.add_child(_item_details(sel, true))
		rv.add_child(UI.spacer())
		var bh := UI.hbox(8)
		bh.add_child(UI.expand(UI.btn("Надеть", _equip.bind(sel["id"]), "primary", 22, "", 0, 58)))
		bh.add_child(UI.btn("Продать %d" % Loot.sell_price(sel), _sell.bind(sel["id"]), "danger", Style.FONT_SMALL, "gold", 0, 58))
		rv.add_child(bh)
	h.add_child(right)
	return h

func _equip(id: String) -> void:
	Game.equip(id)
	_toast("Предмет надет")

func _sell(id: String) -> void:
	Game.sell(id)
	_toast("Продано")

func _select_item(id: String) -> void:
	selected_item = id
	_refresh()

func _item_tile(it: Dictionary) -> Control:
	var t := UI.tile(UI.item_icon(it), Style.RARITY[it["rarity"]], 84, false, it["id"] == selected_item)
	var eq = Game.hero["equipped"][it["slot"]]
	if eq == null or Loot.item_score(it) > Loot.item_score(eq):
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
	top.add_child(UI.tile(UI.item_icon(it), Style.RARITY[it["rarity"]], 80))
	var tv := UI.vbox(4)
	tv.add_child(UI.label(UI.item_title(it), Style.FONT_BODY, Style.RARITY[it["rarity"]], true))
	var chips := UI.hbox(6)
	chips.add_child(UI.chip(Db.RARITY_NAMES[it["rarity"]], Style.RARITY[it["rarity"]]))
	chips.add_child(UI.chip(Loot.SLOT_NAMES[it["slot"]], Style.CARD_3))
	chips.add_child(UI.chip("ур. %d" % it["ilvl"], Style.CARD_3))
	tv.add_child(chips)
	top.add_child(UI.expand(tv))
	v.add_child(top)
	for a in it["affixes"]:
		var row := UI.hbox(8)
		row.add_child(UI.icon(UI.stat_icon(a["stat"]), 24))
		row.add_child(UI.expand(UI.label(Loot.affix_text(a), Style.FONT_BODY, Style.TEXT, true)))
		row.add_child(UI.label("ролл %d%%" % roundi(float(a["q"]) * 100), Style.FONT_TINY, Style.MUTED))
		v.add_child(row)
	if compare:
		var eq = Game.hero["equipped"][it["slot"]]
		var diff := Loot.item_score(it) - (Loot.item_score(eq) if eq != null else 0.0)
		var box := UI.flat(Style.BG_DEEP, 10)
		var bv := UI.vbox(4)
		box.add_child(bv)
		bv.add_child(UI.label("Сейчас надето:", Style.FONT_TINY, Style.MUTED))
		bv.add_child(UI.wrap(("%s — %s" % [UI.item_title(eq), UI.item_line(eq)]) if eq != null else "ничего", Style.FONT_SMALL, Style.TEXT))
		bv.add_child(UI.label(("Лучше на %d" % diff) if diff > 0 else ("Хуже на %d" % -diff), Style.FONT_SMALL,
			Style.SUCCESS if diff > 0 else Style.DANGER, true))
		v.add_child(box)
	return v

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

func _on_expedition_finished(r: Dictionary) -> void:
	if r.get("closed", false):
		selected_level = min(Game.closed_level + 1, Db.level_count())
		_refresh()
	_show_rewards(r, "Уровень пройден!" if r["won"] > 0 else "Уровень не пройден")

func _show_rewards(r: Dictionary, title_text: String) -> void:
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
	v.add_child(pills)
	if r.get("level_ups", 0) > 0:
		v.add_child(UI.chip("Новый уровень героя: %d" % Game.hero["level"], Style.SECONDARY, Style.FONT_SMALL))
	if r.get("board_refreshed", false):
		v.add_child(UI.chip("Гильдия прислала 6 новых наёмников", Style.CARD_3, Style.FONT_SMALL))
	if r.get("won", 0) + r.get("lost", 0) > 1:
		v.add_child(UI.label("Забегов: побед %d, поражений %d, убито %d" % [r["won"], r["lost"], r["kills"]], Style.FONT_SMALL, Style.MUTED))
	var items: Array = r["items"]
	if items.size() > 0:
		var ih := HFlowContainer.new()
		ih.add_theme_constant_override("h_separation", 8)
		ih.add_theme_constant_override("v_separation", 8)
		for i in min(items.size(), 12):
			var t := UI.tile(UI.item_icon(items[i]), Style.RARITY[items[i]["rarity"]], 64)
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
	_modal(title_text, v, [], "Отлично")
	var lbl: Label = gold_pill.get_child(0).get_child(1)
	var tw2 := create_tween()
	tw2.tween_interval(0.15)
	tw2.tween_method(_set_gold_text.bind(lbl), 0.0, float(r["gold"]), 0.6)

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
		var copies := int(Game.collection[r["spell"]].get("1", 0))
		chips.add_child(UI.chip("Копий I: %d/%d" % [copies, Game.FUSE_COUNT], Style.CARD_3))
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
