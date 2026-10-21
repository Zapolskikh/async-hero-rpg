extends Control
## Root UI: top bar with currencies and tabs, tab screens, battle "Watch" layer, popups.
## All UI is built from code with placeholder styling.

const BattleView := preload("res://scripts/ui/battle_view.gd")

const TABS := [
	["expedition", "Поход"],
	["hero", "Герой"],
	["mercs", "Наёмники"],
	["spells", "Заклинания"],
	["bag", "Сумка"],
]

var current_tab := "expedition"
var selected_level := 1

var top_info: Label
var xp_bar: ProgressBar
var tab_buttons := {}
var content: MarginContainer
var exp_status: Label
var watch_layer: Control
var watch_info: Label
var battle_view: Control
var popup_layer: Control

func _ready() -> void:
	theme = _make_theme()
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := UI.vbox(0)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(_build_top_bar())
	content = MarginContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		content.add_theme_constant_override("margin_" + side, 12)
	root.add_child(content)

	_build_watch_layer()
	popup_layer = Control.new()
	popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(popup_layer)

	selected_level = min(Game.closed_level + 1, Db.level_count())
	Game.changed.connect(_refresh)
	Game.expedition_finished.connect(_on_expedition_finished)
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.timeout.connect(_tick_status)
	add_child(t)
	_refresh()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots"):
			add_child(load("res://tests/shot_runner.gd").new())
	if not Game.offline_report.is_empty():
		_show_offline_report(Game.offline_report)
		Game.offline_report = {}

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 20
	var normal := StyleBoxFlat.new()
	normal.bg_color = UI.PANEL_LIGHT
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(8)
	var hover := normal.duplicate()
	hover.bg_color = UI.PANEL_LIGHT.lightened(0.12)
	var pressed := normal.duplicate()
	pressed.bg_color = UI.ACCENT.darkened(0.35)
	var disabled := normal.duplicate()
	disabled.bg_color = UI.PANEL_LIGHT.darkened(0.3)
	th.set_stylebox("normal", "Button", normal)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("disabled", "Button", disabled)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	return th

# ---------------- top bar ----------------

func _build_top_bar() -> Control:
	var p := UI.panel(UI.PANEL, 8)
	var h := UI.hbox(10)
	p.add_child(h)
	top_info = UI.label("", 20, UI.ACCENT)
	top_info.custom_minimum_size.x = 330
	h.add_child(top_info)
	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(120, 20)
	xp_bar.show_percentage = false
	xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(xp_bar)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	for t in TABS:
		var id: String = t[0]
		var b := UI.button(t[1], func(): _switch(id), 20, 110)
		b.toggle_mode = true
		tab_buttons[id] = b
		h.add_child(b)
	return p

func _switch(tab: String) -> void:
	current_tab = tab
	_refresh()

func _refresh() -> void:
	var hero: Dictionary = Game.hero
	top_info.text = "Золото %d   Коробки %d   Герой ур. %d" % [Game.gold, Game.boxes, hero["level"]]
	xp_bar.max_value = Db.xp_to_next(hero["level"])
	xp_bar.value = hero["xp"]
	for id in tab_buttons:
		tab_buttons[id].button_pressed = id == current_tab
	UI.clear(content)
	match current_tab:
		"expedition": content.add_child(_build_expedition())
		"hero": content.add_child(_build_hero())
		"mercs": content.add_child(_build_mercs())
		"spells": content.add_child(_build_spells())
		"bag": content.add_child(_build_bag())

# ---------------- expedition tab ----------------

func _build_expedition() -> Control:
	var h := UI.hbox(12)
	# level list
	var list := UI.vbox(6)
	for lvl in range(1, Db.level_count() + 1):
		var status := "✓ " if lvl <= Game.closed_level else ("→ " if Game.level_unlocked(lvl) else "✕ ")
		var b := UI.button("%s%d. %s" % [status, lvl, Db.LEVELS[lvl - 1]["name"]], func(): selected_level = lvl; _refresh(), 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not Game.level_unlocked(lvl)
		b.toggle_mode = true
		b.button_pressed = lvl == selected_level
		list.add_child(b)
	var lp := UI.panel()
	lp.custom_minimum_size.x = 280
	lp.add_child(UI.scroll(list))
	h.add_child(lp)

	var right := UI.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	right.add_child(_level_panel())
	right.add_child(_party_panel())
	right.add_child(_expedition_panel())
	return h

func _level_panel() -> Control:
	var lvl := selected_level
	var p := UI.panel()
	var v := UI.vbox(6)
	p.add_child(v)
	var closed := lvl <= Game.closed_level
	var head := UI.hbox()
	head.add_child(UI.label("Уровень %d — %s" % [lvl, Db.LEVELS[lvl - 1]["name"]], 24, UI.ACCENT))
	head.add_child(UI.label("  пройден, доступен фарм" if closed else "  не пройден", 18, UI.GOOD if closed else UI.MUTED))
	v.add_child(head)
	var waves: Array = Db.LEVELS[lvl - 1]["waves"]
	var names := {}
	for w in waves:
		for e in w:
			if not Db.ENEMIES[e].get("boss", false):
				names[Db.ENEMIES[e]["name"]] = true
	v.add_child(UI.wrap_label("Волн: %d.  Враги: %s.  Босс: %s." % [waves.size(), ", ".join(names.keys()), Db.boss_of(lvl)], 18, Color.WHITE))
	var hints := Db.level_hints(lvl)
	if lvl > Game.closed_level + 0 and lvl > 1 and Game.hero["level"] < int(lvl * 1.4):
		hints.append("Risky")
	v.add_child(UI.wrap_label("Подсказки: " + (", ".join(hints) if hints.size() > 0 else "—"), 18, Color("#ffd27a")))
	var btns := UI.hbox()
	var push := UI.button("Штурм (push)", func(): _start(lvl, "push"), 20, 180)
	push.disabled = closed or not Game.level_unlocked(lvl) or not Game.party_ready()
	var farm := UI.button("Фарм (AFK-цикл)", func(): _start(lvl, "farm"), 20, 200)
	farm.disabled = not closed or not Game.party_ready()
	btns.add_child(push)
	btns.add_child(farm)
	if not Game.party_ready():
		btns.add_child(UI.label("Нужно 3 наёмника", 18, UI.BAD))
	v.add_child(btns)
	return p

func _party_panel() -> Control:
	var p := UI.panel()
	var v := UI.vbox(6)
	p.add_child(v)
	v.add_child(UI.label("Группа (слева — тыл, справа — передняя линия)", 18, UI.MUTED))
	var row := UI.hbox(8)
	v.add_child(row)
	var order: Array = Game.party_order
	# draw backline first so the row reads like the battlefield
	for i in range(order.size() - 1, -1, -1):
		var id: String = order[i]
		var snap = Game.hero_snapshot() if id == "hero" else Game.merc_by_id(id)
		if snap == null:
			continue
		var card := UI.panel(UI.PANEL_LIGHT, 6)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ch := UI.hbox(6)
		card.add_child(ch)
		Roster.ensure_visuals(snap)
		ch.add_child(UI.portrait(snap["sprite"], 72))
		var cv := UI.vbox(2)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ch.add_child(cv)
		var slot_name: String = ["Перед", "Слот 2", "Слот 3", "Тыл"][i]
		cv.add_child(UI.wrap_label("%s: %s" % [slot_name, snap["name"]], 18, UI.ACCENT if id == "hero" else Color.WHITE))
		cv.add_child(UI.wrap_label("%s, ур. %d, сила %d" % [snap["role"], snap["level"], Roster.power_score(snap)], 15, UI.MUTED))
		var arrows := UI.hbox(4)
		var idx := i
		var back := UI.button("◀", func(): Game.move_in_party(idx, 1), 18, 44)
		back.disabled = idx >= order.size() - 1
		var fwd := UI.button("▶", func(): Game.move_in_party(idx, -1), 18, 44)
		fwd.disabled = idx == 0
		arrows.add_child(back)
		arrows.add_child(fwd)
		cv.add_child(arrows)
		row.add_child(card)
	for i in range(order.size(), 4):
		var empty := UI.panel(UI.PANEL_LIGHT, 6)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.add_child(UI.label("Пусто — наймите на вкладке «Наёмники»", 16, UI.MUTED))
		row.add_child(empty)
	return p

func _expedition_panel() -> Control:
	var p := UI.panel()
	var v := UI.vbox(6)
	p.add_child(v)
	exp_status = UI.wrap_label("", 18, Color.WHITE)
	v.add_child(exp_status)
	var ex: Expedition = Game.expedition
	if ex != null:
		var btns := UI.hbox()
		btns.add_child(UI.button("Смотреть бой", _open_watch, 20, 180))
		if ex.mode == "farm":
			btns.add_child(UI.button("Забрать добычу", func(): _show_report(Game.collect(), "Добыча фарма"), 20, 200))
		btns.add_child(UI.button("Остановить", func(): _show_report(Game.stop_expedition(), "Поход остановлен"), 20, 160))
		v.add_child(btns)
	_tick_status()
	return p

func _tick_status() -> void:
	if exp_status == null or not is_instance_valid(exp_status):
		return
	var ex: Expedition = Game.expedition
	if ex == null:
		exp_status.text = "Активного похода нет. Выберите уровень и запустите штурм или фарм. Поход идёт и при закрытой игре (до 12 ч)."
		return
	var mode := "Штурм" if ex.mode == "push" else "Фарм"
	exp_status.text = "%s: уровень %d «%s», забег %d, волна %d/%d.\nНакоплено: %d золота, %d опыта, %d предм., побед %d, поражений %d." % [
		mode, ex.level, Db.LEVELS[ex.level - 1]["name"], ex.run_index + 1, min(ex.wave_index + 1, ex.total_waves()),
		ex.total_waves(), ex.gold, ex.xp, ex.items.size(), ex.runs_won, ex.runs_lost]

func _start(lvl: int, mode: String) -> void:
	if Game.expedition != null and Game.expedition.has_rewards():
		_show_report(Game.stop_expedition(), "Прошлый поход завершён")
	if Game.start_expedition(lvl, mode):
		_open_watch()

# ---------------- watch layer ----------------

func _build_watch_layer() -> void:
	watch_layer = Control.new()
	watch_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	watch_layer.visible = false
	add_child(watch_layer)
	battle_view = BattleView.new()
	battle_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	watch_layer.add_child(battle_view)
	var bar := UI.panel(Color(0.1, 0.12, 0.16, 0.85), 8)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	watch_layer.add_child(bar)
	var h := UI.hbox(10)
	bar.add_child(h)
	h.add_child(UI.button("← Назад", _close_watch, 20, 120))
	watch_info = UI.label("", 20, Color.WHITE)
	watch_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(watch_info)
	for sp in [1.0, 2.0, 4.0]:
		var s: float = sp
		h.add_child(UI.button("x%d" % int(sp), func(): Game.watch_speed = s, 20, 60))

func _open_watch() -> void:
	watch_layer.visible = true

func _close_watch() -> void:
	watch_layer.visible = false
	Game.watch_speed = 1.0
	_refresh()

func _process(_delta: float) -> void:
	if watch_layer.visible:
		var ex: Expedition = Game.expedition
		if ex == null:
			watch_info.text = "Поход завершён"
		else:
			var mode := "Штурм" if ex.mode == "push" else "Фарм"
			watch_info.text = "%s · ур. %d · забег %d · волна %d/%d · %d с · x%d" % [mode, ex.level, ex.run_index + 1,
				min(ex.wave_index + 1, ex.total_waves()), ex.total_waves(), int(ex.sim.time), int(Game.watch_speed)]

# ---------------- hero tab ----------------

func _build_hero() -> Control:
	var h := UI.hbox(12)
	var hero: Dictionary = Game.hero
	var snap := Game.hero_snapshot()
	var st: Dictionary = snap["stats"]

	var sp := UI.panel()
	sp.custom_minimum_size.x = 300
	var sv := UI.vbox(4)
	sp.add_child(UI.scroll(sv))
	var hh := UI.hbox(8)
	hh.add_child(UI.portrait("hero", 90))
	hh.add_child(UI.label("%s\nур. %d" % [hero["name"], hero["level"]], 24, UI.ACCENT))
	sv.add_child(hh)
	sv.add_child(UI.label("Опыт %d / %d" % [hero["xp"], Db.xp_to_next(hero["level"])], 16, UI.MUTED))
	sv.add_child(UI.label("Сила (Power): %d" % Roster.power_score(snap), 20))
	for row in [["Здоровье", "%d" % st["hp"]], ["Атака", "%d" % st["atk"]], ["Сила заклинаний", "%d" % st["power"]],
			["Броня", "%d" % st["armor"]], ["Скорость", "%d%%" % roundi(st["haste"] * 100)], ["Крит", "%d%%" % roundi(st["crit"] * 100)]]:
		sv.add_child(UI.label("%s: %s" % row, 18))
	sv.add_child(UI.label("Снаряжение", 20, UI.ACCENT))
	for slot in Loot.SLOTS:
		var it = hero["equipped"][slot]
		var line := UI.hbox(6)
		if it == null:
			line.add_child(UI.label("%s: —" % Loot.SLOT_NAMES[slot], 16, UI.MUTED))
		else:
			var l := UI.wrap_label("%s: %s\n%s" % [Loot.SLOT_NAMES[slot], UI.item_title(it), UI.item_line(it)], 15, Db.RARITY_COLORS[it["rarity"]])
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(l)
			var s: String = slot
			line.add_child(UI.button("Снять", func(): Game.unequip(s), 16))
		sv.add_child(line)
	h.add_child(sp)

	# rotation
	var rp := UI.panel()
	rp.custom_minimum_size.x = 380
	var rv := UI.vbox(6)
	rp.add_child(UI.scroll(rv))
	rv.add_child(UI.label("Ротация (порядок применения)", 20, UI.ACCENT))
	rv.add_child(UI.wrap_label("Слот 1 → 2 → 3 → снова 1. Если способность сейчас не применима, она пропускается.", 15))
	var rot: Array = hero["rotation"]
	for i in rot.size():
		var sid: String = rot[i]
		var d: Dictionary = Db.SPELLS[sid]
		var card := UI.panel(UI.PANEL_LIGHT, 6)
		var cv := UI.vbox(2)
		card.add_child(cv)
		cv.add_child(UI.label("%d. %s %s" % [i + 1, d["name"], UI.roman(max(1, Roster.spell_best_level(Game.collection, sid)))], 19))
		cv.add_child(UI.wrap_label(d["desc"], 14))
		var row := UI.hbox(4)
		var idx := i
		var up := UI.button("▲", func(): _rot_move(idx, -1), 16, 44)
		up.disabled = i == 0
		var dn := UI.button("▼", func(): _rot_move(idx, 1), 16, 44)
		dn.disabled = i == rot.size() - 1
		row.add_child(up)
		row.add_child(dn)
		row.add_child(UI.button("Убрать", func(): _rot_remove(idx), 16))
		cv.add_child(row)
		rv.add_child(card)
	if rot.size() < 3:
		rv.add_child(UI.label("Свободный слот: добавьте способность справа", 16, UI.MUTED))
	h.add_child(rp)

	# spell list
	var lv := UI.vbox(6)
	lv.add_child(UI.label("Ваши способности", 20, UI.ACCENT))
	for sid in Game.owned_spells():
		var d: Dictionary = Db.SPELLS[sid]
		var card := UI.panel(UI.PANEL_LIGHT, 6)
		var row := UI.hbox(6)
		card.add_child(row)
		var info := UI.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label("%s %s" % [d["name"], UI.roman(Roster.spell_best_level(Game.collection, sid))], 18, Db.RARITY_COLORS[d["rarity"]]))
		info.add_child(UI.wrap_label(d["desc"], 14))
		row.add_child(info)
		var s: String = sid
		var add := UI.button("В ротацию", func(): _rot_add(s), 16)
		add.disabled = rot.has(sid) or rot.size() >= 3
		row.add_child(add)
		lv.add_child(card)
	var lp := UI.panel()
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lp.add_child(UI.scroll(lv))
	h.add_child(lp)
	return h

func _rot_move(i: int, dir: int) -> void:
	var rot: Array = Game.hero["rotation"].duplicate()
	var j := i + dir
	var tmp = rot[i]
	rot[i] = rot[j]
	rot[j] = tmp
	Game.set_rotation(rot)

func _rot_remove(i: int) -> void:
	var rot: Array = Game.hero["rotation"].duplicate()
	rot.remove_at(i)
	Game.set_rotation(rot)

func _rot_add(sid: String) -> void:
	var rot: Array = Game.hero["rotation"].duplicate()
	if rot.size() < 3 and not rot.has(sid):
		rot.append(sid)
		Game.set_rotation(rot)

# ---------------- mercenaries tab ----------------

func _build_mercs() -> Control:
	var v := UI.vbox(10)
	var head := UI.hbox(10)
	var cost := Game.reroll_cost()
	var rr := UI.button("Обновить доску (%d золота)" % cost, func(): Game.reroll_board(), 20)
	rr.disabled = Game.gold < cost
	head.add_child(rr)
	head.add_child(UI.label("В группе: %d / 3. Нанятые наёмники остаются при обновлении." % (Game.party_order.size() - 1), 18, UI.MUTED))
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for m in Game.board:
		var hired: bool = Game.party_order.has(m["id"])
		var card := UI.panel(UI.PANEL_LIGHT if not hired else Color("#34452f"), 8)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mh := UI.hbox(8)
		card.add_child(mh)
		mh.add_child(UI.portrait(m.get("sprite", "hero"), 92))
		var cv := UI.vbox(3)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mh.add_child(cv)
		cv.add_child(UI.wrap_label("%s — %s" % [m["name"], m["role"]], 20, Color.WHITE))
		cv.add_child(UI.wrap_label("Гильдейский наёмник (NPC) · ур. %d · сила %d" % [m["level"], Roster.power_score(m)], 15, UI.MUTED))
		var st: Dictionary = m["stats"]
		cv.add_child(UI.wrap_label("HP %d  Атк %d  Магия %d  Броня %d" % [st["hp"], st["atk"], st["power"], st["armor"]], 15, Color.WHITE))
		cv.add_child(UI.wrap_label("Ротация: " + Roster.spell_tags_text(m), 15, Color("#ffd27a")))
		var id: String = m["id"]
		var b := UI.button("Уволить" if hired else "Нанять", func(): Game.toggle_hire(id), 18)
		b.disabled = not hired and Game.party_order.size() >= 4
		cv.add_child(b)
		grid.add_child(card)
	v.add_child(UI.scroll(grid))
	return v

# ---------------- spells tab ----------------

func _build_spells() -> Control:
	var v := UI.vbox(10)
	var head := UI.hbox(10)
	var free := UI.button("Ежедневная коробка", func(): _open_box("free"), 18)
	free.disabled = not Game.free_box_available()
	var tok := UI.button("Открыть коробку (%d)" % Game.boxes, func(): _open_box("token"), 18)
	tok.disabled = Game.boxes <= 0
	var buy := UI.button("Купить за %d золота" % Game.BOX_PRICE, func(): _open_box("gold"), 18)
	buy.disabled = Game.gold < Game.BOX_PRICE
	head.add_child(free)
	head.add_child(tok)
	head.add_child(buy)
	head.add_child(UI.label("5 одинаковых копий → следующий уровень", 16, UI.MUTED))
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var ids := []
	for sid in Db.SPELLS:
		if not Db.SPELLS[sid].get("enemy", false):
			ids.append(sid)
	for sid in ids:
		var d: Dictionary = Db.SPELLS[sid]
		var owned := Roster.spell_best_level(Game.collection, sid) > 0
		var card := UI.panel(UI.PANEL_LIGHT if owned else UI.PANEL, 8)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := UI.vbox(3)
		card.add_child(cv)
		cv.add_child(UI.label(d["name"], 19, Db.RARITY_COLORS[d["rarity"]] if owned else UI.MUTED))
		cv.add_child(UI.wrap_label(d["desc"], 14))
		if owned:
			var counts := []
			var levels: Array = Game.collection[sid].keys()
			levels.sort()
			for k in levels:
				if int(Game.collection[sid][k]) > 0:
					counts.append("%s×%d" % [UI.roman(int(k)), int(Game.collection[sid][k])])
			cv.add_child(UI.label("Копии: " + ", ".join(counts), 16))
			for k in levels:
				var lvl := int(k)
				if Game.can_fuse(sid, lvl):
					var s: String = sid
					cv.add_child(UI.button("Слить 5×%s → %s" % [UI.roman(lvl), UI.roman(lvl + 1)], func(): Game.fuse(s, lvl), 16))
		else:
			cv.add_child(UI.label("Не открыто", 16, UI.MUTED))
		grid.add_child(card)
	v.add_child(UI.scroll(grid))
	return v

func _open_box(use: String) -> void:
	var r := Game.open_box(use)
	if r.is_empty():
		return
	var d: Dictionary = Db.SPELLS[r["spell"]]
	_popup("Spell Box", "Выпало: %s (%s)\n%s%s" % [d["name"], Db.RARITY_NAMES[d["rarity"]], d["desc"],
		"\n\nНовая способность!" if r["new"] else ""])

# ---------------- bag tab ----------------

func _build_bag() -> Control:
	var v := UI.vbox(10)
	v.add_child(UI.label("Сумка: %d предм. Сравнение — с надетым в том же слоте." % Game.inventory.size(), 18, UI.MUTED))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var items: Array = Game.inventory.duplicate()
	items.sort_custom(func(a, b): return Loot.item_score(a) > Loot.item_score(b))
	for it in items:
		var card := UI.panel(UI.PANEL_LIGHT, 8)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := UI.vbox(3)
		card.add_child(cv)
		cv.add_child(UI.label(UI.item_title(it), 18, Db.RARITY_COLORS[it["rarity"]]))
		cv.add_child(UI.label(Loot.SLOT_NAMES[it["slot"]], 15, UI.MUTED))
		cv.add_child(UI.wrap_label(UI.item_line(it), 15, Color.WHITE))
		var eq = Game.hero["equipped"][it["slot"]]
		var diff := Loot.item_score(it) - (Loot.item_score(eq) if eq != null else 0.0)
		cv.add_child(UI.label(("Лучше надетого (+%d)" % diff) if diff > 0 else ("Хуже надетого (%d)" % diff), 15, UI.GOOD if diff > 0 else UI.BAD))
		var row := UI.hbox(6)
		var id: String = it["id"]
		row.add_child(UI.button("Надеть", func(): Game.equip(id), 16))
		row.add_child(UI.button("Продать (%d)" % Loot.sell_price(it), func(): Game.sell(id), 16))
		cv.add_child(row)
		grid.add_child(card)
	if items.is_empty():
		v.add_child(UI.label("Пусто. Предметы падают за первое прохождение уровня и иногда на фарме.", 18, UI.MUTED))
	v.add_child(UI.scroll(grid))
	var reset := UI.button("Сбросить прогресс", func(): _confirm_reset(), 16)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(reset)
	return v

func _confirm_reset() -> void:
	_popup("Сброс", "Удалить сохранение и начать заново?", func(): Game.reset_progress())

# ---------------- popups ----------------

func _on_expedition_finished(r: Dictionary) -> void:
	var title := "Уровень пройден!" if r["won"] > 0 else "Группа не прошла уровень"
	_show_report(r, title)

func _show_report(r: Dictionary, title: String) -> void:
	if r.is_empty():
		return
	var lines := []
	if r.has("reason") and r["won"] == 0:
		lines.append("%s на волне %d из %d. Уровень не открыт, награда за достигнутый прогресс:" % [r["reason"], r["waves"] + 1, r["total_waves"]])
	if r.get("closed", false):
		lines.append("Уровень %d закрыт — теперь его можно фармить." % r["level"])
	lines.append("Золото +%d, опыт +%d, убито %d" % [r["gold"], r["xp"], r["kills"]])
	if r.get("won", 0) + r.get("lost", 0) > 1:
		lines.append("Забегов: побед %d, поражений %d" % [r["won"], r["lost"]])
	if r.get("level_ups", 0) > 0:
		lines.append("Герой получил %d ур.!" % r["level_ups"])
	if r.get("boxes", 0) > 0:
		lines.append("Spell Box +%d" % r["boxes"])
	for it in r["items"]:
		lines.append("Предмет: %s — %s" % [UI.item_title(it), UI.item_line(it)])
	if r.get("won", 0) == 0 and r.has("reason"):
		lines.append("\nСовет: проверьте состав (лекарь, щиты, interrupt) и порядок способностей.")
	_popup(title, "\n".join(lines))

func _show_offline_report(o: Dictionary) -> void:
	var mode := "штурм" if o["mode"] == "push" else "фарм"
	_popup("Пока вас не было", "Прошло %s, шёл %s уровня %d.\nНакоплено: золото +%d, опыт +%d, предметов %d, побед %d, поражений %d.\nЗаберите добычу на вкладке «Поход»." % [
		UI.format_time(o["away"]), mode, o["level"], o["gold"], o["xp"], o["items"], o["won"], o["lost"]])

func _popup(title: String, text: String, on_ok: Callable = Callable()) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var p := UI.panel(UI.PANEL, 18)
	p.custom_minimum_size = Vector2(560, 0)
	center.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	v.add_child(UI.label(title, 26, UI.ACCENT))
	var body := UI.wrap_label(text, 19, Color.WHITE)
	body.custom_minimum_size.x = 520
	v.add_child(body)
	var row := UI.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	if on_ok.is_valid():
		row.add_child(UI.button("Отмена", func(): dim.queue_free(), 20, 120))
	row.add_child(UI.button("OK", func(): _close_popup(dim, on_ok), 20, 120))
	v.add_child(row)

func _close_popup(dim: Control, on_ok: Callable) -> void:
	dim.queue_free()
	if on_ok.is_valid():
		on_ok.call()
