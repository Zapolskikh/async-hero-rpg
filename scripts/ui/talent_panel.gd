class_name TalentPanel
extends VBoxContainer
## Four header tabs, a four-column tree and fixed details: landscape touch UI.
static var branch_index := 0
static var selected := "focus"
var hero: Dictionary
var snapshot: Dictionary
var buy: Callable
var read_only := false
var scroller: ScrollContainer

func configure(p_hero: Dictionary, p_snapshot: Dictionary, p_buy: Callable) -> void:
	hero = p_hero
	snapshot = p_snapshot
	buy = p_buy
	custom_minimum_size = Vector2(930,440)
	_render()

func _render() -> void:
	var scroll_y := scroller.scroll_vertical if is_instance_valid(scroller) else 0
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var tabs := UI.hbox(6)
	add_child(tabs)
	for i in Talents.BRANCHES.size():
		var br: Dictionary = Talents.BRANCHES[i]
		var button := UI.btn(br["name"],_switch.bind(i),"secondary" if i == branch_index else "ghost",16,br["icon"],0,48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(button)
	var branch: Dictionary = Talents.BRANCHES[branch_index]
	var ranks: Dictionary = hero.get("talents",{})
	add_child(UI.label("%s · вложено %d   |   Свободно: %d   |   1 очко за ранг" % [branch["name"],Talents.points_spent(ranks,branch["id"]),Talents.points_free(hero)],16,Style.TEXT))
	var row := UI.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(row)
	var tree := UI.vbox(6)
	scroller = UI.scroll(tree)
	scroller.custom_minimum_size = Vector2(620,340)
	row.add_child(scroller)
	var ids := []
	for id in Talents.TALENTS:
		if Talents.TALENTS[id]["branch"] == branch["id"]:
			ids.append(id)
	if not ids.has(selected):
		selected = ids[0]
	for tier in 4:
		var open: bool = Talents.points_spent(ranks,branch["id"]) >= Talents.GATES[tier]
		tree.add_child(UI.label("Ярус %d · %d очков %s" % [tier+1,Talents.GATES[tier],"" if open else "· закрыт"],14,Style.MUTED if open else Style.WARNING))
		var grid := UI.grid(4,8)
		tree.add_child(grid)
		for col in 4:
			var id: String = ids[tier*4+col]
			var t: Dictionary = Talents.TALENTS[id]
			var cell := UI.vbox(2)
			cell.custom_minimum_size = Vector2(140,104)
			grid.add_child(cell)
			var button := UI.btn("%d/%d" % [ranks.get(id,0),t["ranks"]],_select.bind(id),"primary" if id == selected else "secondary",14,t["icon"],0,60)
			button.icon = UI.icon_tex_px(t["icon"],40)
			button.modulate = Color.WHITE if open else Color(.55,.58,.65)
			button.tooltip_text = Talents.describe(id)
			cell.add_child(button)
			var name_label := UI.wrap(t["name"],14,Style.TEXT if open else Style.MUTED,true)
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_child(name_label)
	var detail := UI.card(Style.BG_DEEP,12)
	detail.custom_minimum_size.x = 280
	row.add_child(detail)
	var info := UI.vbox(10)
	detail.add_child(info)
	var talent: Dictionary = Talents.TALENTS[selected]
	info.add_child(UI.tile(talent["icon"],Style.CARD_3,64))
	info.add_child(UI.label(talent["name"],20,Style.TEXT,true))
	info.add_child(UI.label("Ранг %d / %d" % [ranks.get(selected,0),talent["ranks"]],16,Style.MUTED))
	info.add_child(UI.wrap(Talents.describe(selected),16,Style.TEXT))
	if not Talents._active(talent,snapshot.get("weapons",[])):
		info.add_child(UI.wrap("С текущим оружием не действует",14,Style.WARNING))
	var unlocked := Talents.unlocked(selected,ranks)
	info.add_child(UI.wrap("Нужно %d очков в ветке" % Talents.GATES[talent["tier"]],14,Style.SUCCESS if unlocked else Style.WARNING))
	var button := UI.btn("Изучить · 1 очко",_buy_selected,"secondary",18,"",0,48)
	button.disabled = read_only or not unlocked or Talents.points_free(hero) <= 0 or int(ranks.get(selected,0)) >= talent["ranks"]
	if read_only:
		button.text = "Таланты наёмника"
	info.add_child(button)
	scroller.set_deferred("scroll_vertical",scroll_y)

func _switch(index: int) -> void:
	branch_index = index
	_render()

func _select(id: String) -> void:
	selected = id
	_render()

func _buy_selected() -> void:
	buy.call(selected)
	_render()
