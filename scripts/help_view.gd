extends PanelContainer
## Справка (F1): все клавиши и мышь на карте города, по разделам.

const KEYS := [
	["Камера", [
		["WASD / стрелки", "двигать камеру"],
		["Колёсико", "приблизить / отдалить к курсору"],
		["Средняя кнопка", "тащить карту"],
		["Мини-карта", "клик — перейти в это место"],
	]],
	["Карта", [
		["ЛКМ", "выбрать / открыть город, дом, жителя"],
		["ПКМ", "меню: копировать, вставить, удалить, древо"],
		["Esc", "назад (к выбору города)"],
		["Ctrl+F", "поиск файлов и папок"],
		["P / пробел", "пауза времени"],
	]],
	["Выбранный житель", [
		["Ctrl+C / Ctrl+X", "копировать / вырезать"],
		["Ctrl+V", "вставить в выбранный дом"],
		["Delete", "удалить (придут киллеры)"],
		["F2", "переименовать (только в игре)"],
		["Alt+Enter", "свойства (и для дома)"],
		["ПКМ", "все действия: открыть, в проводнике, следить, путь…"],
	]],
	["Окна", [
		["T", "семейное древо"],
		["I", "статистика города"],
		["L", "свернуть / развернуть легенду"],
		["F1", "эта справка"],
		["F12", "снимок экрана"],
	]],
]

func _init() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size.x = 720
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = "Управление"
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color(1.0, 0.95, 0.86))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Button.new()
	close.text = "Закрыть  (Esc)"
	close.pressed.connect(hide)
	head.add_child(close)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	v.add_child(cols)
	var halves := [VBoxContainer.new(), VBoxContainer.new()]
	for h in halves:
		h.add_theme_constant_override("separation", 12)
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(h)
	for i in KEYS.size():
		var sec := VBoxContainer.new()
		sec.add_theme_constant_override("separation", 3)
		halves[i % 2].add_child(sec)
		var st := Label.new()
		st.text = KEYS[i][0]
		st.add_theme_font_size_override("font_size", 14)
		st.add_theme_color_override("font_color", ContinentUI.ACCENT)
		sec.add_child(st)
		for row in KEYS[i][1]:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 10)
			sec.add_child(line)
			line.add_child(_key(row[0]))
			var d := Label.new()
			d.text = row[1]
			d.add_theme_font_size_override("font_size", 13)
			d.modulate.a = 0.85
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(d)

## Клавиша — светлая плашка.
func _key(text: String) -> Control:
	var p := PanelContainer.new()
	var sb := ContinentUI._box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.18), 5, 0)
	ContinentUI._pad(sb, 7, 2)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.x = 118
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p
