class_name CraftsScreen
extends VBoxContainer
## "Ремёсла" screen: gathering (AFK trips), crafting (recipes) and the materials inventory.
## All numbers come from Prof; all actions go through Game (server in online mode).

static var view := "gather"            # gather / craft / mats
static var gather_prof := "mining"
static var craft_prof := "blacksmithing"
static var duration := 3600
static var changing := false           # picking another crafting profession

var main: Node                         # main.gd, for _modal / _toast / mats_row
var timers: Array = []                 # [label, bar, start, end, done_text, was_done]

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.timeout.connect(_tick)
	add_child(t)

## Red dot on the tab: something finished and waits to be claimed.
static func has_ready() -> bool:
	var now: float = Game.now()
	var g = Game.profile.get("gathering")
	if g != null and now >= float(g["ends_at"]):
		return true
	for prof in Game.profile.get("crafting", {}):
		if now >= float(Game.profile["crafting"][prof]["ends_at"]):
			return true
	return false

func _build() -> void:
	for c in get_children():
		if not c is Timer:
			remove_child(c)
			c.queue_free()
	timers.clear()
	add_child(_header())
	match view:
		"gather": add_child(_gather_view())
		"craft": add_child(_craft_view())
		"mats": add_child(_mats_view())
	_tick(true)

func _rebuild() -> void:
	var keep := UI.scroll_state(self)
	_build()
	UI.restore_scrolls(self, keep)

func _header() -> Control:
	var h := UI.hbox(8)
	for v in [["gather", "Сбор", "prof_mining"], ["craft", "Ремесло", "prof_blacksmithing"], ["mats", "Материалы", "res_iron_ore"]]:
		var b := UI.btn(v[1], _set_view.bind(v[0]), "secondary" if view == v[0] else "ghost", Style.FONT_BODY, v[2], 170, 50)
		h.add_child(b)
	h.add_child(UI.spacer())
	var buffs := Rules.active_buffs(Game.profile, Game.now())
	for eff in buffs:
		var b: Dictionary = buffs[eff]
		var txt := ""
		if b.has("until"):
			txt = "%s · %s" % [_buff_name(eff, b), UI.format_time(float(b["until"]) - Game.now())]
		else:
			txt = "%s ×%d" % [_buff_name(eff, b), int(b["charges"])]
		h.add_child(UI.pill("res_" + str(b.get("res", "gatherers_tonic")), txt, Style.FONT_TINY, Style.CARD))
	return h

func _buff_name(eff: String, b: Dictionary) -> String:
	match eff:
		"potion": return str(Prof.RESOURCES[b["res"]]["name"])
		"gather_yield": return "Сбор +%d%%" % roundi((float(b["value"]) - 1.0) * 100)
	return eff

func _set_view(v: String) -> void:
	view = v
	_rebuild()

# =====================================================================
# Gathering
# =====================================================================

func _gather_view() -> Control:
	var h := UI.hbox(12)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := UI.vbox(10)
	left.custom_minimum_size.x = 270
	for prof in Prof.GATHERING:
		left.add_child(_prof_card(prof, prof == gather_prof, _pick_gather.bind(prof)))
	h.add_child(left)
	var right := UI.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var g = Game.profile.get("gathering")
	if g != null:
		right.add_child(_active_gather(g))
	var dur := UI.hbox(8)
	dur.add_child(UI.label("Длительность:", Style.FONT_SMALL, Style.MUTED))
	for d in Prof.DURATIONS:
		dur.add_child(UI.btn(d["label"], _pick_duration.bind(int(d["sec"])), "secondary" if duration == int(d["sec"]) else "ghost", Style.FONT_SMALL, "", 76, 42))
	right.add_child(dur)
	var list := UI.vbox(10)
	for loc in Prof.locations_of(gather_prof):
		list.add_child(_location_card(loc, g != null))
	right.add_child(UI.scroll(list))
	return h

func _pick_gather(prof: String) -> void:
	gather_prof = prof
	_rebuild()

func _pick_duration(sec: int) -> void:
	duration = sec
	_rebuild()

func _prof_card(prof: String, selected: bool, cb: Callable) -> Control:
	var d: Dictionary = Prof.PROFESSIONS[prof]
	var pr: Dictionary = Game.profile["professions"][prof]
	var c := UI.card(Style.CARD_2 if selected else Style.CARD, 10)
	if selected:
		var sb: StyleBoxFlat = c.get_theme_stylebox("panel").duplicate()
		sb.border_width_left = 4
		sb.border_color = Style.PRIMARY
		c.add_theme_stylebox_override("panel", sb)
	var h := UI.hbox(10)
	c.add_child(h)
	h.add_child(UI.tile(d["icon"], Style.CARD_3, 52))
	var v := UI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.label(d["name"], Style.FONT_BODY, Style.TEXT, true))
	var lvl := int(pr["level"])
	var need := Prof.xp_to_next(lvl)
	v.add_child(UI.label("Ур. %d%s" % [lvl, ("  ·  %d / %d" % [pr["xp"], need]) if need > 0 else "  ·  максимум"], Style.FONT_TINY, Style.MUTED))
	v.add_child(UI.progress(int(pr["xp"]), max(1, need), Style.SECONDARY, 8))
	var status := _prof_status(prof)
	if status != "":
		v.add_child(UI.label(status, Style.FONT_TINY, Style.SUCCESS, true))
	h.add_child(v)
	UI.tap_overlay(c, cb)
	return c

func _prof_status(prof: String) -> String:
	var now: float = Game.now()
	if prof in Prof.GATHERING:
		var g = Game.profile.get("gathering")
		if g != null and g["prof"] == prof:
			return "Готово!" if now >= float(g["ends_at"]) else "В пути"
	else:
		var c = Game.profile["crafting"].get(prof)
		if c != null:
			return "Готово!" if now >= float(c["ends_at"]) else "Создаёт…"
	return ""

func _active_gather(g: Dictionary) -> Control:
	var loc: Dictionary = Prof.LOCATIONS[g["loc"]]
	var c := UI.card(Color("#2b4a3d"), 12)
	var h := UI.hbox(12)
	c.add_child(h)
	h.add_child(UI.tile(Prof.PROFESSIONS[g["prof"]]["icon"], Style.SUCCESS, 64))
	var v := UI.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := "%s — %s" % [Prof.PROFESSIONS[g["prof"]]["name"], loc["name"]]
	if g.get("tonic", false):
		title += "  (+тоник)"
	v.add_child(UI.label(title, Style.FONT_BODY, Style.TEXT, true))
	var tl := UI.label("", Style.FONT_SMALL, Style.TEXT)
	var bar := UI.progress(0, 1, Style.SUCCESS, 12)
	v.add_child(tl)
	v.add_child(bar)
	timers.append([tl, bar, float(g["started_at"]), float(g["ends_at"]), "Готово — можно забирать", Game.now() >= float(g["ends_at"])])
	h.add_child(v)
	var done: bool = Game.now() >= float(g["ends_at"])
	var col := UI.vbox(6)
	var claim := UI.btn("Забрать", _gather_claim, "primary", Style.FONT_BODY, "", 140, 50)
	claim.disabled = not done
	col.add_child(claim)
	if not done:
		var cost := Shop.rush_cost(float(g["ends_at"]) - Game.now())
		var rb := UI.btn("Сейчас  %d" % cost, _rush.bind("gather", ""), "secondary", Style.FONT_TINY, "crystal", 140, 36)
		rb.disabled = Game.crystals < cost
		col.add_child(rb)
		col.add_child(UI.btn("Отменить", _gather_cancel, "ghost", Style.FONT_TINY, "", 140, 36))
	h.add_child(col)
	return c

func _location_card(loc_id: String, busy: bool) -> Control:
	var loc: Dictionary = Prof.LOCATIONS[loc_id]
	var lvl := Rules.prof_level(Game.profile, gather_prof)
	var locked := lvl < int(loc["req"])
	var c := UI.card(Style.CARD, 12)
	var h := UI.hbox(12)
	c.add_child(h)
	var v := UI.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UI.hbox(8)
	head.add_child(UI.label(loc["name"], Style.FONT_BODY, Style.TEXT if not locked else Style.MUTED, true))
	head.add_child(UI.chip("ур. %d" % loc["req"], Style.DANGER if locked else Style.CARD_3, 13))
	v.add_child(head)
	var tonic := Rules.active_buffs(Game.profile, Game.now()).has("gather_yield")
	var est := Prof.expected_yield(loc_id, duration, lvl, tonic)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	for res in est:
		var txt := ("≈%d" % est[res]) if not loc["rare"].has(res) else ("шанс %s" % _chance_text(float(est[res])))
		var pill := UI.pill("res_" + res, "%s %s" % [Prof.RESOURCES[res]["name"], txt], Style.FONT_TINY, Style.BG_DEEP)
		row.add_child(pill)
	v.add_child(row)
	v.add_child(UI.label("Опыт профессии: +%d" % Prof.gather_xp(loc_id, duration), Style.FONT_TINY, Style.MUTED))
	h.add_child(v)
	var b := UI.btn("Начать", _gather_start.bind(loc_id), "success", Style.FONT_BODY, "hourglass", 140, 52)
	b.disabled = locked or busy
	h.add_child(b)
	return c

func _chance_text(expected: float) -> String:
	if expected >= 1.0:
		return "≈%.1f" % expected
	return "%d%%" % roundi(expected * 100)

func _gather_start(loc_id: String) -> void:
	var r: Dictionary = await Game.gather_start(gather_prof, loc_id, duration)
	if not r.get("ok", false):
		main._toast(_err_text(r))
	_rebuild()

func _gather_claim() -> void:
	var r: Dictionary = await Game.gather_claim()
	if r.get("ok", false):
		Sfx.play("coin")
		var rep: Dictionary = r["report"]
		var v := UI.vbox(10)
		v.add_child(UI.label("%s — %s" % [Prof.PROFESSIONS[rep["prof"]]["name"], Prof.LOCATIONS[rep["loc"]]["name"]], Style.FONT_BODY, Style.TEXT, true))
		v.add_child(main.mats_row(rep["res"]))
		v.add_child(UI.label("Опыт профессии +%d%s" % [rep["xp"], ("  ·  новый уровень!" if rep["level_ups"] > 0 else "")], Style.FONT_SMALL, Style.SUCCESS if rep["level_ups"] > 0 else Style.MUTED, true))
		main._modal("Сбор завершён", v, [], "Отлично")
	else:
		main._toast(_err_text(r))
	_rebuild()

func _gather_cancel() -> void:
	main._modal("Отменить сбор?", UI.wrap("Добыча этого похода будет потеряна.", Style.FONT_BODY, Style.TEXT),
		[["Отменить сбор", _do_cancel, "danger", true]], "Назад")

func _do_cancel() -> void:
	await Game.gather_cancel()
	_rebuild()

# =====================================================================
# Crafting
# =====================================================================

func _craft_view() -> Control:
	var chosen: String = Game.profile["craft_prof"]
	if chosen == "" or changing:
		return _craft_choice()
	if craft_prof != chosen and not Game.profile["crafting"].has(craft_prof):
		craft_prof = chosen
	var h := UI.hbox(12)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := UI.vbox(10)
	left.custom_minimum_size.x = 270
	left.add_child(_prof_card(chosen, chosen == craft_prof, _pick_craft.bind(chosen)))
	for prof in Game.profile["crafting"]:   # a craft started before the choice can still be claimed
		if prof != chosen:
			left.add_child(_prof_card(prof, prof == craft_prof, _pick_craft.bind(prof)))
	left.add_child(UI.btn("Сменить ремесло", _set_change.bind(true), "ghost", Style.FONT_SMALL, "", 0, 44))
	h.add_child(left)
	var right := UI.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var c = Game.profile["crafting"].get(craft_prof)
	if c != null:
		right.add_child(_active_craft(craft_prof, c))
	var list := UI.vbox(10)
	for rid in Prof.recipes_of(craft_prof):
		list.add_child(_recipe_card(rid))
	right.add_child(UI.scroll(list))
	return h

func _pick_craft(prof: String) -> void:
	craft_prof = prof
	_rebuild()

## All crafts side by side: the first choice, and the paid change later.
func _craft_choice() -> Control:
	var current: String = Game.profile["craft_prof"]
	var v := UI.vbox(12)
	var note := "Герой осваивает одно ремесло. Первый выбор бесплатный, смена стоит %d золота." % Prof.CRAFT_CHANGE_GOLD
	if current != "":
		note = "Смена ремесла стоит %d золота. Уровни профессий сохраняются." % Prof.CRAFT_CHANGE_GOLD
	v.add_child(UI.wrap(note, Style.FONT_BODY, Style.TEXT))
	for prof in Prof.CRAFTING:
		if prof != current:
			v.add_child(_choice_card(prof))
	if current != "":
		v.add_child(UI.btn("Назад", _set_change.bind(false), "ghost", Style.FONT_SMALL, "", 140, 44))
	return UI.scroll(v)

func _choice_card(prof: String) -> Control:
	var d: Dictionary = Prof.PROFESSIONS[prof]
	var c := UI.card(Style.CARD, 12)
	var h := UI.hbox(12)
	c.add_child(h)
	h.add_child(UI.tile(d["icon"], Style.CARD_3, 72))
	var v := UI.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.label(d["name"], Style.FONT_BODY, Style.TEXT, true))
	v.add_child(UI.wrap(d["desc"], Style.FONT_SMALL, Style.TEXT))
	v.add_child(UI.label("Рецептов: %d  ·  ур. %d" % [Prof.recipes_of(prof).size(), Rules.prof_level(Game.profile, prof)], Style.FONT_TINY, Style.MUTED))
	h.add_child(v)
	h.add_child(UI.btn("Выбрать", _confirm_choice.bind(prof), "success", Style.FONT_BODY, "", 140, 52))
	return c

func _confirm_choice(prof: String) -> void:
	var text := "Рецепты других ремёсел станут недоступны."
	if Game.profile["craft_prof"] != "":
		text = "Смена стоит %d золота. Рецепты прежнего ремесла станут недоступны." % Prof.CRAFT_CHANGE_GOLD
	main._modal(Prof.PROFESSIONS[prof]["name"], UI.wrap(text, Style.FONT_BODY, Style.TEXT),
		[["Выбрать", _do_choice.bind(prof), "success", true]], "Назад")

func _do_choice(prof: String) -> void:
	var r: Dictionary = await Game.prof_choose(prof)
	if r.get("ok", false):
		craft_prof = prof
		changing = false
	else:
		main._toast(_err_text(r))
	_rebuild()

func _set_change(on: bool) -> void:
	changing = on
	_rebuild()

func _active_craft(prof: String, c: Dictionary) -> Control:
	var r: Dictionary = Prof.RECIPES[c["recipe"]]
	var card := UI.card(Color("#2b3d5a"), 12)
	var h := UI.hbox(12)
	card.add_child(h)
	h.add_child(_output_tile(c["recipe"], 64))
	var v := UI.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.label("Создаётся: " + r["name"], Style.FONT_BODY, Style.TEXT, true))
	var tl := UI.label("", Style.FONT_SMALL, Style.TEXT)
	var bar := UI.progress(0, 1, Style.SECONDARY, 12)
	v.add_child(tl)
	v.add_child(bar)
	timers.append([tl, bar, float(c["started_at"]), float(c["ends_at"]), "Готово — можно забирать", Game.now() >= float(c["ends_at"])])
	h.add_child(v)
	var claim := UI.btn("Забрать", _craft_claim.bind(prof), "primary", Style.FONT_BODY, "", 140, 50)
	claim.disabled = Game.now() < float(c["ends_at"])
	var col := UI.vbox(6)
	col.add_child(claim)
	if Game.now() < float(c["ends_at"]):
		var cost := Shop.rush_cost(float(c["ends_at"]) - Game.now())
		var rb := UI.btn("Сейчас  %d" % cost, _rush.bind("craft", prof), "secondary", Style.FONT_TINY, "crystal", 140, 36)
		rb.disabled = Game.crystals < cost
		col.add_child(rb)
	h.add_child(col)
	return card

func _output_tile(rid: String, size_px: float) -> Control:
	var r: Dictionary = Prof.RECIPES[rid]
	if r.has("item"):
		return UI.tile(UI.item_icon(Prof.make_item(rid, "preview", int(Game.hero["level"]))), Style.QUALITY[int(r["item"]["rarity"])], size_px)
	var res: String = r["output"].keys()[0]
	return UI.tile("res_" + res, Style.RARITY[int(Prof.RESOURCES[res]["tier"])], size_px)

func _recipe_card(rid: String) -> Control:
	var r: Dictionary = Prof.RECIPES[rid]
	var lvl := Rules.prof_level(Game.profile, craft_prof)
	var locked := lvl < int(r["req"])
	var chk := Rules.can_craft(Game.profile, rid)
	var c := UI.card(Style.CARD, 12)
	var h := UI.hbox(12)
	c.add_child(h)
	h.add_child(_output_tile(rid, 72))
	var v := UI.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UI.hbox(8)
	var rarity := int(r["item"]["rarity"]) if r.has("item") else int(Prof.RESOURCES[r["output"].keys()[0]]["tier"])
	var colors: Array = Style.QUALITY if r.has("item") else Style.RARITY
	head.add_child(UI.label(r["name"], Style.FONT_BODY, colors[rarity] if not locked else Style.MUTED, true))
	head.add_child(UI.chip("ур. %d" % r["req"], Style.DANGER if locked else Style.CARD_3, 13))
	if r.has("item"):
		var pv := Prof.make_item(rid, "preview", int(Game.hero["level"]))
		var kind: String = Loot.WEAPON_TYPES[pv["wtype"]]["name"] if pv.has("wtype") else Loot.SLOT_NAMES[pv["slot"]]
		head.add_child(UI.chip(kind, Style.CARD_3, 13))
	if r.get("drop_only", false):
		var known: bool = rid in Game.profile.get("recipes_known", [])
		head.add_child(UI.chip("Изучен" if known else "Редкий рецепт", Style.SUCCESS if known else Style.SECONDARY, 13,
			Color("#062b16") if known else Style.TEXT))
	v.add_child(head)
	v.add_child(UI.wrap(_output_text(rid), Style.FONT_SMALL, Style.TEXT))
	var ing := HFlowContainer.new()
	ing.add_theme_constant_override("h_separation", 6)
	ing.add_theme_constant_override("v_separation", 6)
	for res in r["ingredients"]:
		var need := int(r["ingredients"][res])
		var have := Rules.res_count(Game.profile, res)
		var bg := Color("#1f4a35") if have >= need else Color("#5a2530")
		var pill := UI.pill("res_" + res, "%s %d/%d" % [Prof.RESOURCES[res]["name"], have, need], Style.FONT_TINY, bg)
		ing.add_child(pill)
	var gp := UI.pill("gold", str(r["gold"]), Style.FONT_TINY, Color("#1f4a35") if Game.gold >= int(r["gold"]) else Color("#5a2530"))
	ing.add_child(gp)
	ing.add_child(UI.pill("hourglass", UI.format_time(float(r["time"])), Style.FONT_TINY, Style.BG_DEEP))
	ing.add_child(UI.chip("опыт +%d" % r["xp"], Style.BG_DEEP, 13))
	v.add_child(ing)
	h.add_child(v)
	var b := UI.btn("Создать", _craft_start.bind(rid), "success", Style.FONT_BODY, "", 140, 52)
	b.disabled = not chk["ok"]
	var col := UI.vbox(4)
	col.add_child(b)
	if not chk["ok"]:
		col.add_child(UI.wrap(_err_text(chk), Style.FONT_TINY, Style.MUTED))
	col.custom_minimum_size.x = 150
	h.add_child(col)
	return c

func _output_text(rid: String) -> String:
	var r: Dictionary = Prof.RECIPES[rid]
	if r.has("item"):
		var it := Prof.make_item(rid, "preview", int(Game.hero["level"]))
		var quality := int(r["item"]["rarity"])
		var parts := []
		if it.has("wtype"):
			parts.append(Loot.weapon_text(it))
		for a in it["affixes"]:
			if a.get("imp", false) or quality != Items.UNCOMMON or r.get("drop_only", false):
				parts.append(Loot.affix_text(a))
		if r.get("drop_only", false):
			return "%s, уровень %d. %s" % [Items.QUALITY_NAMES[quality], it["ilvl"], ", ".join(parts)]
		if quality == Items.COMMON:
			return "%s, уровень героя. Только базовые характеристики: %s" % [Items.QUALITY_NAMES[quality], ", ".join(parts)]
		return "%s, уровень героя. Основа: %s. Случайных характеристик: %d" % [Items.QUALITY_NAMES[quality], ", ".join(parts), Prof.CRAFT_RANDOM_STATS[quality]]
	var parts := []
	for res in r["output"]:
		var line := "%s ×%d" % [Prof.RESOURCES[res]["name"], r["output"][res]]
		if Prof.CONSUMABLES.has(res):
			line += " — " + Prof.CONSUMABLES[res]["desc"]
		parts.append(line)
	return ", ".join(parts)

func _craft_start(rid: String) -> void:
	var r: Dictionary = await Game.craft_start(rid)
	if not r.get("ok", false):
		main._toast(_err_text(r))
	_rebuild()

func _craft_claim(prof: String) -> void:
	var r: Dictionary = await Game.craft_claim(prof)
	if r.get("ok", false):
		var rep: Dictionary = r["report"]
		Sfx.play("craft")
		if not rep["items"].is_empty():
			Sfx.loot(int(rep["items"][0]["rarity"]))
		var v := UI.vbox(10)
		for it in rep["items"]:
			var row := UI.hbox(10)
			row.add_child(UI.tile(UI.item_icon(it), Style.QUALITY[it["rarity"]], 64))
			var iv := UI.vbox(2)
			iv.add_child(UI.label(it["name"], Style.FONT_BODY, Style.QUALITY[it["rarity"]], true))
			iv.add_child(UI.label(UI.item_line(it), Style.FONT_SMALL, Style.TEXT))
			iv.add_child(UI.label("В сумке — надеть можно на вкладке «Сумка»", Style.FONT_TINY, Style.MUTED))
			row.add_child(iv)
			v.add_child(row)
		if not rep["res"].is_empty():
			v.add_child(main.mats_row(rep["res"]))
		v.add_child(UI.label("Опыт профессии +%d%s" % [rep["xp"], ("  ·  новый уровень!" if rep["level_ups"] > 0 else "")], Style.FONT_SMALL, Style.SUCCESS if rep["level_ups"] > 0 else Style.MUTED, true))
		main._modal("Готово", v, [], "Отлично")
	else:
		main._toast(_err_text(r))
	_rebuild()

# =====================================================================
# Materials
# =====================================================================

func _mats_view() -> Control:
	var v := UI.vbox(12)
	var any := false
	for cat in Prof.CATEGORIES:
		if cat[0] == "alchemy":
			continue   # potions live in the bag
		var ids := []
		for res in Prof.RESOURCES:
			if Prof.RESOURCES[res]["cat"] == cat[0] and Rules.res_count(Game.profile, res) > 0:
				ids.append(res)
		if ids.is_empty():
			continue
		any = true
		var c := UI.card(Style.CARD, 12)
		var cv := UI.vbox(8)
		c.add_child(cv)
		cv.add_child(UI.title(cat[1], 20))
		var g := UI.grid(4, 10)
		for res in ids:
			g.add_child(_res_cell(res))
		cv.add_child(g)
		v.add_child(c)
	if not any:
		v.add_child(UI.wrap("Пока пусто. Руда, травы и кожа — со сбора, ткань и особые материалы — из боёв (фарм и боссы).", Style.FONT_BODY))
	v.add_child(UI.label("Зелья — во вкладке «Сумка».", Style.FONT_SMALL, Style.MUTED))
	return UI.scroll(v)

func _res_cell(res: String) -> Control:
	var d: Dictionary = Prof.RESOURCES[res]
	var h := UI.hbox(8)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UI.tile("res_" + res, Style.RARITY[int(d["tier"])], 52)
	var cnt := UI.chip(str(Rules.res_count(Game.profile, res)), Style.BG_DEEP, 13)
	cnt.position = Vector2(30, 32)
	t.add_child(cnt)
	h.add_child(t)
	var v := UI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.wrap(d["name"], Style.FONT_SMALL, Style.TEXT, true))
	if Prof.CONSUMABLES.has(res):
		v.add_child(UI.wrap(Prof.CONSUMABLES[res]["desc"], Style.FONT_TINY))
		v.add_child(UI.btn("Использовать", _use.bind(res), "success", Style.FONT_TINY, "", 0, 36))
	h.add_child(v)
	return h

func _rush(what: String, prof: String) -> void:
	var r: Dictionary = await Game.rush(what, prof)
	main._toast("Готово — можно забирать" if r.get("ok", false) else "Не хватает кристаллов")
	_rebuild()

func _use(res: String) -> void:
	Sfx.play("potion")
	var r: Dictionary = await Game.use_item(res)
	main._toast(("%s: эффект активен" % Prof.RESOURCES[res]["name"]) if r.get("ok", false) else _err_text(r))
	_rebuild()

# =====================================================================

func _tick(initial := false) -> void:
	var now: float = Game.now()
	var rebuild := false
	for t in timers:
		var lbl: Label = t[0]
		var bar: ProgressBar = t[1]
		if not is_instance_valid(lbl):
			continue
		var total: float = max(1.0, t[3] - t[2])
		var left: float = t[3] - now
		if left <= 0.0:
			if not t[5]:
				t[5] = true
				rebuild = true  # enable the claim button
			lbl.text = t[4]
			bar.max_value = 1
			bar.value = 1
		else:
			lbl.text = "Осталось " + UI.format_time(left)
			bar.max_value = total
			bar.value = total - left
	if rebuild and not initial:
		_rebuild()

func _err_text(r: Dictionary) -> String:
	var e := str(r.get("error", ""))
	match e:
		"profession level too low": return "Нужен выше уровень профессии"
		"recipe not learned": return "Рецепт не изучен — даётся за прохождение уровня, изредка падает с боссов"
		"already crafting": return "Уже идёт создание"
		"not your craft": return "Это рецепт другого ремесла"
		"already gathering": return "Уже идёт сбор"
		"not enough gold": return "Не хватает золота"
		"not finished": return "Ещё не готово"
		"nothing to claim": return "Нечего забирать"
	if e.begins_with("missing "):
		var res := e.substr(8)
		return "Не хватает: " + str(Prof.RESOURCES.get(res, {}).get("name", res))
	return e if e != "" else "Не получилось"
