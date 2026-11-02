class_name Tutorial
extends Control
## First-session guide and one-time hints when a new system opens.
##
## Progress lives in the profile (Rules._tutorial, synced with the server). A step either
## waits for "Далее" or for the player to do something (start a push, open a box). Steps
## with a target cut a hole in the dim layer over that control (main.tut_targets) so only
## it can be pressed. Hidden while a popup is open, so result windows stay usable.

var main: Control
var _shown := ""          # signature of what is on screen, to rebuild only on change
var _entered := -1        # step whose tab switch was done

const STEPS := [
	{"id": "welcome", "tab": "expedition", "next": true,
		"text": "Добро пожаловать! Вы — герой отряда из четырёх бойцов. Бои идут сами: ваша задача — собрать группу, заклинания и снаряжение и вести отряд всё дальше."},
	{"id": "push", "tab": "expedition", "target": "push",
		"text": "Нажмите «Штурм»: отряд попробует пройти первый уровень. В каждом уровне 10 волн и босс."},
	{"id": "watch", "tab": "watch", "next": true,
		"text": "Бой идёт сам: каждый боец применяет заклинания своей ротации. Внизу — урон и лечение за забег, строку можно нажать. Штурм продолжится и при закрытой игре."},
	{"id": "box", "tab": "spells", "target": "box_token",
		"text": "Пока идёт штурм — заклинания. Spell Box дают за прохождения и каждый день. Откройте коробку: повторы повышают уровень заклинания."},
	{"id": "rotation", "tab": "hero", "target": "rotation", "next": true,
		"text": "Ротация — три заклинания героя. Каждый ход берётся первое подходящее слева направо. Нажмите на заклинание справа, чтобы поставить его в ротацию."},
	{"id": "bag", "tab": "bag", "target": "bag", "next": true,
		"text": "Вещи из боёв лежат в сумке: выберите вещь и нажмите «Надеть». Оружие задаёт стиль: посох — магия и лечение, щит — танк, лук — стрелок. Роль можно сменить в любой момент."},
	{"id": "mercs", "tab": "mercs", "target": "party", "next": true,
		"text": "Отряд — вы и три наёмника, порядок задаёт строй. На доске ниже можно нанять других, в том числе героев других игроков: за найм их владелец получает золото."},
	{"id": "farm", "tab": "expedition", "next": true,
		"text": "Пройденный уровень можно фармить: поход идёт без конца и при закрытой игре (до 12 часов) и приносит золото, опыт и вещи. Удачи в походе!"},
]

## One-time hints: id -> [condition, title, text].
func _hints() -> Array:
	var p: Dictionary = Game.profile
	var hero: Dictionary = Game.hero
	return [
		["talents", int(hero["level"]) >= Talents.FIRST_LEVEL, "Таланты",
			"Открылись таланты: 1 очко за уровень. Ряд открывается за каждые 5 очков в ветке, так что выбирайте — глубже в одну ветку или понемногу в две. Сброс бесплатный. Кнопка — на экране героя."],
		["crafts", int(p["closed_level"]) >= 3, "Ремёсла",
			"Из боёв падают ресурсы. На вкладке «Ремёсла» выберите профессию: кузнец, портной или кожевник делают снаряжение, которое в бою почти не найти."],
		["merge", int(p["closed_level"]) >= 2 and _merge_ready(), "Переплавка",
			"В сумке набралось %d вещей одной редкости. «Переплавка» в сумке превращает их в одну вещь следующей редкости — вещи выбираете вы." % Rules.MERGE_COUNT],
		["accessory", _has_accessory(), "Аксессуары",
			"Аксессуары не дают характеристик — у каждого свой эффект: вторая атака, оглушение, повтор заклинаний, а легендарные меняют бой целиком. Надеваются в два слота."],
		["modifiers", int(p["closed_level"]) >= 10, "Особенности врагов",
			"С 11-го уровня у врагов есть особенности: броня, щиты, регенерация, ярость. Они видны на карточке уровня, а «Атлас» покажет врагов подробно."],
		["chapter6", int(p["closed_level"]) >= Db.CAMPAIGN_CORE, "Глава 6",
			"Уровни 31–40 — испытание после капа: враги сильнее с каждым уровнем. Без хорошего снаряжения и продуманной группы их не пройти."],
		["mythic", Rules.mythic_open(p), "Мифик+",
			"На 30-м уровне открылся Мифик+: одно длинное подземелье, каждый пройденный ключ повышает сложность. Лучшие по сезону получают награды."],
	]

var disabled := false     # automated runs (screenshots, online test) play without the guide

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var args := OS.get_cmdline_user_args()
	for a in args:
		if (a.begins_with("--shots") and not "--shots-tutorial" in args) or a.begins_with("--online-test") or a == "--qa-combat":
			disabled = true

func _state() -> Dictionary:
	return Game.profile.get("tutorial", {"step": 0, "done": true, "hints": []})

func update() -> void:
	if main == null or Game.profile.is_empty() or disabled:
		return
	if Game.online_only and not Game.is_online():
		_clear()
		return
	var t := _state()
	if main.popup_layer.get_child_count() > 0:
		_clear()
		return
	if not bool(t.get("done", false)) and int(t.get("step", 0)) < STEPS.size():
		_show_step(int(t["step"]))
	else:
		_clear()
		_maybe_hint(t)

func _clear() -> void:
	if get_child_count() > 0:
		UI.clear(self)
	_shown = ""

func _advance(step: int) -> void:
	Game.tutorial({"step": step + 1})
	_shown = ""
	update()

func _skip() -> void:
	Game.track({"e": "tutorial_skip", "step": int(_state().get("step", 0))})
	Game.tutorial({"step": STEPS.size()})
	_clear()

func _step_done(step: Dictionary) -> bool:
	match step["id"]:
		"push":
			return Game.exp_info() != null or Game.closed_level > 0
		"box":
			return int(Rules._stats(Game.profile).get("boxes_opened", 0)) > 0
	return false

func _show_step(i: int) -> void:
	var step: Dictionary = STEPS[i]
	if _step_done(step):
		_advance(i)
		return
	if _entered != i:
		_entered = i
		if step["tab"] == "watch":
			if not main.watch_layer.visible and Game.exp_info() != null:
				main._open_watch()
		else:
			if main.watch_layer.visible:
				main._close_watch()
			main._switch(step["tab"])
	var target: Control = main.tut_targets.get(step.get("target", ""))
	var hole := Rect2()
	if target != null and is_instance_valid(target) and target.is_visible_in_tree():
		hole = Rect2(target.get_global_rect().position - get_global_rect().position, target.size).grow(8)
	var sig := "%d|%s" % [i, str(hole)]
	if sig == _shown:
		return
	UI.clear(self)
	_shown = sig
	_dim_around(hole)
	var panel := UI.card(Style.CARD, 18, 14)
	panel.custom_minimum_size = Vector2(560, 0)
	var v := UI.vbox(12)
	panel.add_child(v)
	var head := UI.hbox(8)
	head.add_child(UI.expand(UI.label("Обучение · %d из %d" % [i + 1, STEPS.size()], Style.FONT_SMALL, Style.MUTED, true)))
	head.add_child(UI.btn("Пропустить", _skip, "ghost", Style.FONT_TINY, "", 0, 36))
	v.add_child(head)
	v.add_child(UI.wrap(step["text"], Style.FONT_BODY, Style.TEXT))
	if step.get("next", false):
		var row := UI.hbox(8)
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_child(UI.btn("Далее" if i < STEPS.size() - 1 else "Начать игру", _advance.bind(i), "primary", Style.FONT_BODY, "", 160, 52))
		v.add_child(row)
	add_child(panel)
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	var area: Vector2 = main.get_rect().size
	var pos := Vector2((area.x - panel.size.x) / 2.0, (area.y - panel.size.y) / 2.0)
	if hole.size != Vector2.ZERO:
		pos.x = clampf(hole.get_center().x - panel.size.x / 2.0, 12.0, area.x - panel.size.x - 12.0)
		pos.y = hole.end.y + 16.0 if hole.get_center().y < area.y / 2.0 else hole.position.y - panel.size.y - 16.0
		pos.y = clampf(pos.y, 12.0, area.y - panel.size.y - 12.0)
	panel.position = pos

## Dim everything except the hole; clicks outside it are blocked, inside go to the game.
func _dim_around(hole: Rect2) -> void:
	var area: Vector2 = main.get_rect().size
	var col := Color(0, 0, 0, 0.62)
	if hole.size == Vector2.ZERO:
		_block(Rect2(Vector2.ZERO, area), col)
		return
	_block(Rect2(0, 0, area.x, hole.position.y), col)
	_block(Rect2(0, hole.end.y, area.x, area.y - hole.end.y), col)
	_block(Rect2(0, hole.position.y, hole.position.x, hole.size.y), col)
	_block(Rect2(hole.end.x, hole.position.y, area.x - hole.end.x, hole.size.y), col)
	var frame := ReferenceRect.new()
	frame.border_color = Style.PRIMARY
	frame.border_width = 3.0
	frame.editor_only = false
	frame.position = hole.position
	frame.size = hole.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var tw := frame.create_tween().set_loops()
	tw.tween_property(frame, "modulate:a", 0.35, 0.6)
	tw.tween_property(frame, "modulate:a", 1.0, 0.6)

func _block(r: Rect2, col: Color) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var c := ColorRect.new()
	c.color = col
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(c)

func _maybe_hint(t: Dictionary) -> void:
	if main.watch_layer.visible:
		return
	for h in _hints():
		if h[1] and not h[0] in t.get("hints", []):
			Game.tutorial({"hint": h[0]})
			var body := UI.wrap(h[3], Style.FONT_BODY, Style.TEXT)
			main._modal(h[2], body, [], "Понятно")
			return

func _merge_ready() -> bool:
	var counts := {}
	for it in Game.inventory:
		var r := int(it["rarity"])
		counts[r] = int(counts.get(r, 0)) + 1
		if r < Rules.MERGE_GOLD.size() and counts[r] >= Rules.MERGE_COUNT:
			return true
	return false

func _has_accessory() -> bool:
	for it in Game.inventory:
		if it["slot"] == "accessory":
			return true
	for slot in ["accessory1", "accessory2"]:
		if Game.hero["equipped"].get(slot) != null:
			return true
	return false
