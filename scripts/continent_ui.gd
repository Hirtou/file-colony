class_name ContinentUI
extends CanvasLayer
## Интерфейс материка: путь сверху, инфо справа, подсказка, «Назад» и планета слева внизу, легенда справа внизу.

signal back_pressed
signal crumb_pressed(index: int)
signal search_changed(text: String)
signal result_chosen(index: int)
signal speed_pressed
signal file_chosen(index: int)
signal menu_chosen(id: int)
signal tree_pressed
signal type_chosen(t: int)

const BG := Color(0.07, 0.08, 0.11, 0.78)
const TEXT := Color(0.92, 0.93, 0.96)

var _crumbs: HBoxContainer
var _info: PanelContainer
var _info_box: VBoxContainer
var _files_title: Label
var _files_scroll: ScrollContainer
var _files: VBoxContainer
var _tip: PanelContainer
var _tip_label: Label
var _planet: Label
var _search: LineEdit
var _results: VBoxContainer
var _clock: Label
var _loading: Label
var _speed: Button
var _menu: PopupMenu
var _toast: Label
var _toast_tw: Tween
var _clip: PanelContainer
var _clip_pawn: PawnView
var _clip_name: Label
var _clip_title: Label
var tree: FamilyTree   # вкладка «Семейное древо»
var _type_rows: Array = []

## Житель крупно (модель файла в буфере обмена).
class PawnView extends Control:
	var look := {}
	func _init() -> void:
		custom_minimum_size = Vector2(64, 64)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if not look.is_empty():
			Pawn.draw(self, size / 2 + Vector2(0, 2), 60.0, look, Residents.Facing.DOWN, 0.0, false, true)

## Цветная точка для легенды.
class Dot extends Control:
	var color: Color
	func _init(c: Color) -> void:
		color = c
		custom_minimum_size = Vector2(12, 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_circle(size / 2, 5, color)
		draw_arc(size / 2, 5, 0, TAU, 16, Color(0, 0, 0, 0.8), 1.0, true)

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = make_theme()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # пиксельные рамки
	add_child(root)

	# путь сверху
	var top := _panel(root, Vector2(0, 0), Vector2(12, 12))
	_crumbs = HBoxContainer.new()
	top.add_child(_crumbs)

	# поиск под путём: поле и найденное
	var sp := _panel(root, Vector2(0, 0), Vector2(12, 64))
	var sv := VBoxContainer.new()
	sp.add_child(sv)
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск файла или папки…  (Ctrl+F)"
	_search.custom_minimum_size.x = 300
	_search.text_changed.connect(search_changed.emit)
	_search.text_submitted.connect(func(_t): if _results.get_child_count() > 0: result_chosen.emit(0))
	sv.add_child(_search)
	_results = VBoxContainer.new()
	_results.add_theme_constant_override("separation", 1)
	sv.add_child(_results)

	# информация справа
	_info = _panel(root, Vector2(1, 0), Vector2(-12, 12))
	_info.custom_minimum_size.x = 230
	var iv := VBoxContainer.new()
	_info.add_child(iv)
	_info_box = VBoxContainer.new()
	iv.add_child(_info_box)
	_info.visible = false
	# список файлов выбранного дома
	_files_title = Label.new()
	_files_title.add_theme_font_size_override("font_size", 13)
	_files_title.modulate.a = 0.7
	iv.add_child(_files_title)
	_files_scroll = ScrollContainer.new()
	_files_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_files_scroll.custom_minimum_size = Vector2(260, 0)
	iv.add_child(_files_scroll)
	_files = VBoxContainer.new()
	_files.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_files.add_theme_constant_override("separation", 0)
	_files_scroll.add_child(_files)
	show_files([])

	# «Назад» и планета слева снизу
	var bl := _panel(root, Vector2(0, 1), Vector2(12, -12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bl.add_child(row)
	var back := Button.new()
	back.text = "Назад"
	back.pressed.connect(back_pressed.emit)
	row.add_child(back)
	_planet = Label.new()
	row.add_child(_planet)
	_clock = Label.new()
	_clock.custom_minimum_size.x = 120
	row.add_child(_clock)
	_speed = Button.new()
	_speed.text = "×1"
	_speed.tooltip_text = "Скорость времени"
	_speed.pressed.connect(speed_pressed.emit)
	row.add_child(_speed)
	var tb := Button.new()
	tb.text = "Семейное древо"
	tb.tooltip_text = "Родня выбранного файла или папки  (T)"
	tb.pressed.connect(tree_pressed.emit)
	row.add_child(tb)

	# легенда справа снизу
	var br := _panel(root, Vector2(1, 1), Vector2(-12, -12))
	var leg := VBoxContainer.new()
	leg.add_theme_constant_override("separation", 2)
	br.add_child(leg)
	var title := Label.new()
	title.text = "Одежда = тип файла\nклик — найти на карте"
	title.add_theme_font_size_override("font_size", 12)
	title.modulate.a = 0.7
	leg.add_child(title)
	for t in FakeTree.TYPE_NAMES.size():
		var line := HBoxContainer.new()
		line.add_child(Dot.new(WorldMap.TYPE_COLORS[t]))
		var b := Button.new()
		b.text = FakeTree.TYPE_NAMES[t]
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		b.tooltip_text = "Показать на карте все файлы типа «%s»" % FakeTree.TYPE_NAMES[t]
		var tight := StyleBoxEmpty.new()  # строки легенды низкие, как раньше
		tight.content_margin_left = 2
		tight.content_margin_top = 0
		tight.content_margin_bottom = 0
		for s in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(s, tight)
		b.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.55))
		b.pressed.connect(type_chosen.emit.bind(t))
		line.add_child(b)
		leg.add_child(line)
		_type_rows.append(line)

	# буфер обмена над «Назад»: скопированный житель
	_clip = _panel(root, Vector2(0, 1), Vector2(12, -66))
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 10)
	_clip.add_child(ch)
	_clip_pawn = PawnView.new()
	ch.add_child(_clip_pawn)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	ch.add_child(cv)
	_clip_title = Label.new()
	_clip_title.text = "В буфере (Ctrl+V — вставить в дом):"
	_clip_title.add_theme_font_size_override("font_size", 12)
	_clip_title.modulate.a = 0.7
	cv.add_child(_clip_title)
	_clip_name = Label.new()
	cv.add_child(_clip_name)
	_clip.visible = false

	# надпись-уведомление сверху по центру
	_toast = Label.new()
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_top = 120
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	root.add_child(_toast)

	# меню правой кнопки
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(menu_chosen.emit)
	root.add_child(_menu)

	# семейное древо — поверх всего, кроме подсказки; под ним затемнение
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.visible = false
	root.add_child(shade)
	tree = FamilyTree.new()
	tree.visibility_changed.connect(func(): shade.visible = tree.visible)
	tree.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.offset_left = 40
	tree.offset_top = 40
	tree.offset_right = -40
	tree.offset_bottom = -40
	root.add_child(tree)

	# подсказка у мыши
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_label = Label.new()
	_tip_label.add_theme_font_size_override("font_size", 12)
	_tip.add_child(_tip_label)
	_tip.visible = false
	root.add_child(_tip)

## Панель, прижатая к углу anchor (0/1 по x и y) с отступом offset.
func _panel(parent: Control, anchor: Vector2, offset: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.anchor_left = anchor.x
	p.anchor_right = anchor.x
	p.anchor_top = anchor.y
	p.anchor_bottom = anchor.y
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN if anchor.x == 1 else Control.GROW_DIRECTION_END
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN if anchor.y == 1 else Control.GROW_DIRECTION_END
	p.offset_left = offset.x
	p.offset_right = offset.x
	p.offset_top = offset.y
	p.offset_bottom = offset.y
	parent.add_child(p)
	return p

## Общая тема интерфейса (меню тоже её берёт).
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var bg := StyleBoxFlat.new()
	bg.bg_color = BG
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(8)
	t.set_stylebox("panel", "PanelContainer", _skin("ui_panel", bg, 8))
	var bn := StyleBoxFlat.new()
	bn.bg_color = Color(1, 1, 1, 0.06)
	bn.set_corner_radius_all(4)
	bn.content_margin_left = 8
	bn.content_margin_right = 8
	bn.content_margin_top = 3
	bn.content_margin_bottom = 3
	var bh := bn.duplicate()
	bh.bg_color = Color(1, 1, 1, 0.18)
	t.set_stylebox("normal", "Button", _skin("ui_button_normal", bn, 4))
	t.set_stylebox("hover", "Button", _skin("ui_button_hover", bh, 4))
	t.set_stylebox("pressed", "Button", _skin("ui_button_pressed", bh, 4))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0, 0, 0, 0.35)
	le.border_color = Color(1, 1, 1, 0.25)
	le.set_border_width_all(1)
	le.set_corner_radius_all(4)
	le.set_content_margin_all(6)
	t.set_stylebox("normal", "LineEdit", le)
	var lf := le.duplicate()
	lf.border_color = Color(1.0, 0.85, 0.5, 0.8)
	t.set_stylebox("focus", "LineEdit", lf)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.4))
	t.set_color("font_color", "Label", TEXT)
	return t

## 9-patch из текстуры дизайнера (рамка 8 px); нет файла — запасной стиль.
static func _skin(tex_name: String, fallback: StyleBox, pad: int) -> StyleBox:
	if not Tiles.exists(tex_name):
		return fallback
	var sb := StyleBoxTexture.new()
	sb.texture = Tiles.tex(tex_name)
	sb.set_texture_margin_all(8)
	sb.set_content_margin_all(pad + 4)
	return sb

## Строка пути: каждый пункт — кнопка.
func set_path(names: Array) -> void:
	for c in _crumbs.get_children():
		c.queue_free()
	for i in names.size():
		if i > 0:
			var sep := Label.new()
			sep.text = ">"
			sep.modulate.a = 0.5
			_crumbs.add_child(sep)
		var b := Button.new()
		b.text = names[i]
		b.pressed.connect(crumb_pressed.emit.bind(i))
		_crumbs.add_child(b)

func set_planet(text: String) -> void:
	_planet.text = text

## Надпись по центру на время постройки мира ("" — убрать).
func show_loading(text: String) -> void:
	if _loading == null:
		_loading = Label.new()
		_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
		_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_loading.add_theme_font_size_override("font_size", 28)
		_loading.add_theme_color_override("font_outline_color", Color.BLACK)
		_loading.add_theme_constant_override("outline_size", 6)
		add_child(_loading)
	_loading.text = text
	_loading.visible = text != ""

func set_clock(text: String, speed: int) -> void:
	_clock.text = text
	_speed.text = "×%d" % speed

## rows: [[подпись, значение], ...]; пусто — спрятать (вместе со списком файлов).
func show_info(rows: Array) -> void:
	_info.visible = not rows.is_empty()
	if rows.is_empty():
		show_files([])
	for c in _info_box.get_children():
		c.queue_free()
	for i in rows.size():
		var l := Label.new()
		l.text = rows[i][1] if i == 0 else "%s: %s" % rows[i]
		if i == 0:
			l.add_theme_font_size_override("font_size", 18)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(l)

## Файлы дома: rows — [[имя, размер, цвет точки], ...]; клик — file_chosen(i); пусто — спрятать.
func show_files(rows: Array) -> void:
	for c in _files.get_children():
		c.queue_free()
	_files_title.visible = not rows.is_empty()
	_files_scroll.visible = not rows.is_empty()
	_files_title.text = "Жители дома (%d):" % rows.size()
	for i in rows.size():
		var line := HBoxContainer.new()
		line.add_child(Dot.new(rows[i][2]))
		var b := Button.new()
		b.text = rows[i][0]
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 150
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(file_chosen.emit.bind(i))
		line.add_child(b)
		var s := Label.new()
		s.text = rows[i][1]
		s.add_theme_font_size_override("font_size", 12)
		s.modulate.a = 0.6
		line.add_child(s)
		_files.add_child(line)
	_files_scroll.custom_minimum_size.y = mini(rows.size(), 12) * 24
	mark_file(-1)

## Подсветить строку i в списке файлов (-1 — ни одной).
func mark_file(i: int) -> void:
	for k in _files.get_child_count():
		_files.get_child(k).modulate = Color(1.0, 0.9, 0.4) if k == i else Color.WHITE

## Найденное: rows — [[текст, цвет точки], ...]; клик по строке — result_chosen(i).
func show_results(rows: Array) -> void:
	for c in _results.get_children():
		c.queue_free()
	for i in rows.size():
		var line := HBoxContainer.new()
		line.add_child(Dot.new(rows[i][1]))
		var b := Button.new()
		b.text = rows[i][0]
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(result_chosen.emit.bind(i))
		line.add_child(b)
		_results.add_child(line)

func focus_search() -> void:
	_search.grab_focus()
	_search.select_all()

func search_focused() -> bool:
	return _search.has_focus()

func release_search() -> void:
	_search.release_focus()

func clear_search() -> void:
	_search.text = ""
	show_results([])
	release_search()

## Меню правой кнопки: entries — [[текст, id], ...]; id < 0 — заголовок (не нажимается).
func show_menu(entries: Array, at: Vector2) -> void:
	_menu.clear()
	for e in entries:
		if e[1] < 0:
			_menu.add_separator(e[0])
		else:
			_menu.add_item(e[0], e[1])
	_menu.reset_size()
	_menu.position = Vector2i(at)
	_menu.popup()

## Короткое уведомление сверху, гаснет само.
func toast(text: String, color := Color.WHITE) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.modulate.a = 1.0
	if _toast_tw:
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_interval(1.8)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.6)

## Показать в буфере скопированный (cut — вырезанный) файл (null — пусто).
func set_clipboard(file, cut := false) -> void:
	_clip.visible = file != null
	if file == null:
		return
	_clip_title.text = "Вырезан (Ctrl+V — переселить в дом):" if cut else "В буфере (Ctrl+V — вставить в дом):"
	_clip_pawn.look = Pawn.look(file)
	_clip_pawn.queue_redraw()
	_clip_name.text = "%s  ·  %s" % [file.name, FakeTree.format_size(file.size)]

## Подсветить выбранный тип в легенде (-1 — ни один).
func mark_type(t: int) -> void:
	for i in _type_rows.size():
		_type_rows[i].modulate = Color(1.3, 1.2, 0.7) if i == t else (Color(1, 1, 1, 0.55) if t >= 0 else Color.WHITE)

func show_tip(text: String, at: Vector2) -> void:
	_tip_label.text = text
	_tip.reset_size()
	_tip.position = at + Vector2(14, 14)
	_tip.visible = true

func hide_tip() -> void:
	_tip.visible = false
