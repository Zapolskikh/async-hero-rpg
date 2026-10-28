extends VBoxContainer
const Session := preload("res://scripts/core/training_session.gd")
const View := preload("res://scripts/ui/battle_view.gd")
var session: TrainingSession
var view: Control
var summary: Label
var details: Label
var slots: Array = []
var selected_slot := 0
var group := "all"
var search := ""
var spell_list: VBoxContainer
var training_speed := 1.
var speed_picker: OptionButton

func configure(snapshot: Dictionary) -> void:
	session = Session.new(snapshot)

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var header := UI.hbox(10)
	header.add_child(UI.expand(UI.title("Тренировка · Манекен", 24)))
	header.add_child(UI.btn("Закрыть", queue_free, "ghost", 18))
	add_child(header)
	add_child(UI.wrap("Все 50 заклинаний доступны. Набор, оружие и уровень меняются только здесь. Союзники начинают с 55% здоровья; наград нет.", 16))
	var options := HFlowContainer.new()
	options.add_theme_constant_override("h_separation", 10)
	add_child(options)
	var weapon := OptionButton.new()
	weapon.tooltip_text = "Пресеты дают тренировочное оружие уровня героя. Остальные характеристики сохраняются."
	for name in ["Текущее оружие", "Меч и щит", "Два меча", "Двуручный меч", "Лук", "Посох"]:
		weapon.add_item(name)
	weapon.item_selected.connect(func(i):
		session.weapons = [session.source.get("weapons", []), ["sword","shield"], ["sword","sword"], ["greatsword"], ["bow"], ["staff"]][i].duplicate()
		_restart())
	options.add_child(weapon)
	var count := OptionButton.new()
	count.add_item("1 манекен")
	count.add_item("3 манекена")
	count.item_selected.connect(func(i): session.targets = 1 if i == 0 else 3; _restart())
	options.add_child(count)
	for config in [["Ответные атаки", "retaliation"], ["Цели: 20% HP", "low_health"]]:
		var check := CheckButton.new()
		check.text = config[0]
		check.tooltip_text = "Манекены атакуют, применяют сбиваемые касты, проклятия и щиты." if config[1] == "retaliation" else "Позволяет проверять Казнь и таланты добивания."
		check.toggled.connect(func(on): session.set(config[1], on); _restart())
		options.add_child(check)
	var level := OptionButton.new()
	for i in range(1, Rules.SPELL_MAX_LEVEL + 1):
		level.add_item("Ранг заклинаний %d" % i)
	level.item_selected.connect(func(i): session.spell_level = i + 1; _restart())
	options.add_child(level)
	var body := UI.hbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var left := UI.vbox(6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.7
	body.add_child(left)
	view = View.new()
	view.clip_contents = true
	view.custom_minimum_size = Vector2(0, 220)
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.training_sim = session.sim
	left.add_child(view)
	summary = UI.label("", 17)
	left.add_child(summary)
	var controls := UI.hbox(8)
	controls.add_child(UI.btn("Сбросить бой", _restart, "primary", 17))
	var pause := CheckButton.new()
	pause.text = "Пауза"
	pause.toggled.connect(func(on): session.paused = on)
	controls.add_child(pause)
	speed_picker = OptionButton.new()
	for rate in [.25,1.,2.,4.,8.]: speed_picker.add_item("×%s" % rate)
	speed_picker.selected = 1
	speed_picker.item_selected.connect(func(i): training_speed = [.25,1.,2.,4.,8.][i])
	controls.add_child(speed_picker)
	left.add_child(controls)
	var row := UI.hbox(6)
	left.add_child(row)
	for i in 3:
		var button := UI.btn("", _select_slot.bind(i), "ghost", 16, "", 0, 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slots.append(button)
		row.add_child(button)
	left.add_child(UI.btn("Очистить выбранный слот", _equip.bind(""), "ghost", 16))
	details = UI.wrap("", 16)
	left.add_child(details)
	var right := UI.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var filter := OptionButton.new()
	var groups := ["all","universal","arcane","life","bulwark","melee","ranged"]
	for name in ["Все заклинания", "Универсальные", "Чародейство", "Жизнь", "Защита", "Мечи", "Лук"]:
		filter.add_item(name)
	filter.item_selected.connect(func(i): group = groups[i]; _catalog())
	right.add_child(filter)
	var input := LineEdit.new()
	input.placeholder_text = "Поиск заклинания"
	input.text_changed.connect(func(value): search = value; _catalog())
	right.add_child(input)
	spell_list = UI.vbox(5)
	right.add_child(UI.scroll(spell_list))
	_refresh_slots()
	_catalog()

func _restart() -> void:
	session.restart()
	view.training_sim = session.sim
	_refresh_slots()
	_catalog()

func _select_slot(index: int) -> void:
	selected_slot = index
	_refresh_slots()

func _equip(id: String) -> void:
	session.set_spell(selected_slot, id)
	_refresh_slots()

func _refresh_slots() -> void:
	for i in 3:
		var id: String = session.rotation[i]
		slots[i].text = "%s%d. %s" % ["▶ " if i == selected_slot else "", i + 1, "Пусто" if id == "" else Db.SPELLS[id]["name"]]
	var id: String = session.rotation[selected_slot]
	details.text = "Выбери слот и заклинание справа. Проверка слева направо, как в походе." if id == "" else Db.SPELLS[id]["desc"]
	if id != "" and not Db.spell_usable(id, session.weapons, session.source.get("talents", {})):
		details.text += " ⚠ Требуется другое оружие: способность будет пропускаться."

func _catalog() -> void:
	UI.clear(spell_list)
	for id in Session.catalog():
		var spell: Dictionary = Db.SPELLS[id]
		if group != "all" and spell["group"] != group:
			continue
		if not search.is_empty() and not search.to_lower() in str(spell["name"]).to_lower():
			continue
		var usable := Db.spell_usable(id, session.weapons, session.source.get("talents", {}))
		var button := UI.btn(spell["name"] + (" · нужно оружие" if not usable else ""), _equip.bind(id), "ghost", 17, UI.spell_icon(id), 0, 44)
		button.tooltip_text = spell["desc"]
		spell_list.add_child(button)

func _process(delta: float) -> void:
	if session == null or summary == null:
		return
	view.animation_rate = 0. if session.paused else training_speed
	session.advance(delta * training_speed)
	var hero: BattleUnit = session.sim.units[0]
	var elapsed := maxf(.1, session.sim.time)
	summary.text = "%.1f с · Урон %d · DPS %.1f · Лечение %d · HPS %.1f%s" % [session.sim.time, hero.dealt, hero.dealt / elapsed, hero.healed, hero.healed / elapsed, " · Бой завершён — сбрось" if session.sim.finished else ""]

func _exit_tree() -> void:
	if session != null:
		session.dispose()
