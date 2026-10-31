extends PanelContainer
## Окно «Статистика города» (как анализатор диска): сколько жителей-файлов каждого типа и сколько они
## весят, самые большие файлы и самые людные дома. Клик по строке — показать на карте.
## Данные выдуманные (дерево FakeTree), реальный диск не читается.

signal show_on_map(house, file)  # file == null — показать сам дом

const W := 660
var _body: VBoxContainer

func _init() -> void:
	custom_minimum_size = Vector2(W, 0)
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)

## houses — [Folder дома, ...] города; title — имя города.
func open(title: String, houses: Array) -> void:
	for c in _body.get_children():
		c.queue_free()
	var by_type := {}  # тип -> [сколько, байт]
	var files := []    # [[размер, дом, файл], ...]
	var total := 0
	for h in houses:
		for f in h.files:
			var e: Array = by_type.get(f.type, [0, 0])
			e[0] += 1
			e[1] += f.size
			by_type[f.type] = e
			files.append([f.size, h, f])
			total += f.size
	# шапка
	var head := HBoxContainer.new()
	_body.add_child(head)
	var t := _label(head, I18n.t("Статистика города «%s»") % title, 20)
	t.add_theme_color_override("font_color", Color(1.0, 0.95, 0.86))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = I18n.t("Закрыть  (Esc)")
	close.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	close.pressed.connect(hide)
	head.add_child(close)
	var sum := _label(_body, I18n.t("Жителей: %d  ·  домов: %d  ·  всего: %s") % [files.size(), houses.size(), FakeTree.format_size(total)], 14)
	sum.modulate.a = 0.7
	_rule()
	# по типам: полоска — доля размера
	_label(_body, I18n.t("Место по типам файлов"), 15).add_theme_color_override("font_color", ContinentUI.ACCENT)
	var types := by_type.keys()
	types.sort_custom(func(a, b): return by_type[a][1] > by_type[b][1])
	var biggest: int = by_type[types[0]][1] if not types.is_empty() else 1
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	_body.add_child(grid)
	for ty in types:
		var name_row := HBoxContainer.new()
		name_row.custom_minimum_size.x = 130
		name_row.add_child(ContinentUI.Dot.new(WorldMap.TYPE_COLORS[ty]))
		_label(name_row, I18n.t(FakeTree.TYPE_NAMES[ty]), 13)
		grid.add_child(name_row)
		grid.add_child(Bar.new(float(by_type[ty][1]) / maxf(biggest, 1), WorldMap.TYPE_COLORS[ty]))
		var n := _label(grid, str(by_type[ty][0]), 13)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		n.custom_minimum_size.x = 40
		n.modulate.a = 0.7
		var s := _label(grid, FakeTree.format_size(by_type[ty][1]), 13)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		s.custom_minimum_size.x = 80
	_rule()
	# два столбца: большие файлы и людные дома
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	_body.add_child(cols)
	files.sort_custom(func(a, b): return a[0] > b[0])
	var left := _column(cols, I18n.t("Самые большие файлы"))
	for e in files.slice(0, 6):
		_row(left, e[2].name, FakeTree.format_size(e[0]), WorldMap.TYPE_COLORS[e[2].type], e[1], e[2])
	var crowded := houses.duplicate()
	crowded.sort_custom(func(a, b): return a.files.size() > b.files.size())
	var right := _column(cols, I18n.t("Самые людные дома"))
	for h in crowded.slice(0, 6):
		_row(right, h.name, I18n.t("жителей: %d") % h.files.size(), Color(0.85, 0.7, 0.45), h, null)
	var hint := _label(_body, I18n.t("Клик по строке — показать на карте"), 12)
	hint.modulate.a = 0.5
	show()

func _column(parent: Control, title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	parent.add_child(v)
	_label(v, title, 15).add_theme_color_override("font_color", ContinentUI.ACCENT)
	return v

func _row(parent: Control, text: String, value: String, dot: Color, house, file) -> void:
	var line := HBoxContainer.new()
	line.add_child(ContinentUI.Dot.new(dot))
	var b := Button.new()
	b.text = text
	b.flat = true
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.x = 120
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(func():
		hide()
		show_on_map.emit(house, file))
	line.add_child(b)
	var v := _label(line, value, 12)
	v.modulate.a = 0.6
	parent.add_child(line)

func _rule() -> void:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.08)
	r.custom_minimum_size.y = 1
	_body.add_child(r)

func _label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l

## Полоска доли: тёмная дорожка и цветная часть.
class Bar extends Control:
	var k: float
	var color: Color
	func _init(fraction: float, c: Color) -> void:
		k = clampf(fraction, 0.0, 1.0)
		color = c
		custom_minimum_size = Vector2(300, 14)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := Rect2(0, 2, size.x, size.y - 4)
		draw_rect(r, Color(1, 1, 1, 0.07))
		if k > 0.0:
			draw_rect(Rect2(r.position, Vector2(maxf(r.size.x * k, 2.0), r.size.y)), Color(color, 0.85))
