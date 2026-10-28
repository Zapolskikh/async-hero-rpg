extends HBoxContainer
var value: Dictionary
var look: Array
var preview: Control
var sex_picker: OptionButton

func configure(appearance: Dictionary, layers: Array) -> void:
	value = CharacterAppearance.normalize(appearance)
	look = layers.duplicate(true)

func _ready() -> void:
	add_theme_constant_override("separation", 24)
	preview = UI.vbox()
	preview.custom_minimum_size = Vector2(220, 270)
	add_child(preview)
	var options := UI.vbox(12)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(options)
	options.add_child(UI.label("Пол", 20))
	sex_picker = OptionButton.new()
	sex_picker.add_item("Мужской")
	sex_picker.add_item("Женский")
	sex_picker.selected = 1 if value["sex"] == "female" else 0
	sex_picker.item_selected.connect(_select_sex)
	options.add_child(sex_picker)
	options.add_child(UI.wrap("Для каждого пола доступен готовый образ. Причёска входит в него. Изменение внешности бесплатно и не влияет на характеристики.", 17))
	_update_preview()

func _select_sex(index: int) -> void:
	sex_picker.selected = index
	var hair_index: int = CharacterAppearance.hair_ids(value["sex"]).find(value["hair"])
	value["sex"] = "female" if index == 1 else "male"
	value["hair"] = CharacterAppearance.hair_ids(value["sex"])[maxi(0, hair_index)]
	_update_preview()

func _update_preview() -> void:
	UI.clear(preview)
	preview.add_child(UI.portrait("hero", 270, false, look, "", value))
