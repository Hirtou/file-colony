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
signal stats_pressed

const STATS := preload("res://scripts/stats_view.gd")
const HELP := preload("res://scripts/help_view.gd")

const BG := Color(0.065, 0.075, 0.1, 0.88)
const TEXT := Color(0.92, 0.93, 0.96)
const ACCENT := Color(0.95, 0.76, 0.42)  # золото: кайма, выбранное, ползунки

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
var _results_scroll: ScrollContainer
var _found_label: Label
var _f_type: OptionButton
var _f_size: OptionButton
var _f_city: OptionButton
const SIZE_NAMES := ["до 1 МБ", "1–100 МБ", "100 МБ–1 ГБ", "больше 1 ГБ"]
const SIZE_LIMITS := [[0, 1 << 20], [1 << 20, 100 << 20], [100 << 20, 1 << 30], [1 << 30, 1 << 62]]
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
var arrow: EdgeArrow   # стрелка к выбранному за краем экрана
var _legend_grid: GridContainer
var _legend_title: Button
static var legend_open := false  # помнится, пока игра запущена
var minimap: Minimap
var stats: PanelContainer  # окно статистики (stats_view.gd)
var help: PanelContainer   # справка F1 (help_view.gd)
var _legend_panel: PanelContainer
var _files_rows := 0

## Житель крупно (модель файла в буфере обмена).
class PawnView extends Control:
	var look := {}
	func _init() -> void:
		custom_minimum_size = Vector2(64, 64)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if not look.is_empty():
			Pawn.draw(self, size / 2 + Vector2(0, 2), 60.0, look, Residents.Facing.DOWN, 0.0, false, true)

## Стрелка у края экрана к выбранному, когда он вне кадра; клик — лететь к нему.
class EdgeArrow extends Control:
	signal pressed
	var angle := 0.0
	var label := ""
	var _t := 0.0
	func _init() -> void:
		size = Vector2(64, 64)
		pivot_offset = size / 2
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		visible = false
	func _process(delta: float) -> void:
		if visible:
			_t += delta
			queue_redraw()
	func _draw() -> void:
		var c := size / 2
		var d := Vector2.from_angle(angle)
		var push := d * (2.0 + 3.0 * sin(_t * 6.0))  # подталкивает в сторону цели
		draw_circle(c + push, 22, Color(0.1, 0.08, 0.05, 0.85))
		draw_arc(c + push, 22, 0, TAU, 32, Color(1.0, 0.85, 0.4), 2.0, true)
		var n := d.orthogonal()
		draw_colored_polygon(PackedVector2Array([c + push + d * 15, c + push - d * 8 + n * 10, c + push - d * 3, c + push - d * 8 - n * 10]),
			Color(1.0, 0.85, 0.4))
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var tp := c + push - d * 36 + Vector2(-w / 2, 4)
		draw_string_outline(font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.8))
		draw_string(font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.92, 0.7))
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()

## Мини-карта города: вся карта, рамка того, что в кадре, и выбранное; клик или перетаскивание — камера туда.
class Minimap extends Control:
	signal jump(world_pos: Vector2)
	var tex: Texture2D
	var area := Rect2()      # мировые координаты всей карты
	var view := Rect2()      # что в кадре
	var mark := Vector2.INF  # выбранное (мир. координаты)
	var night := 0.0
	var _t := 0.0
	func _init() -> void:
		custom_minimum_size = Vector2(176, 176)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "Мини-карта: клик — перейти"
	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_t += delta
			queue_redraw()
	func _to_px(p: Vector2) -> Vector2:
		return (p - area.position) / area.size * size
	func _draw() -> void:
		if tex == null or area.size.x <= 0.0:
			return
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1).darkened(night * 0.45))
		var r := Rect2(_to_px(view.position), view.size / area.size * size).intersection(Rect2(Vector2.ZERO, size))
		if r.size.x > 0.0:
			draw_rect(r, Color(1, 1, 1, 0.08))
			draw_rect(r, Color(1.0, 0.92, 0.7, 0.9), false, 1.5)
		if mark.is_finite():
			var p := _to_px(mark)
			var k := 0.5 + 0.5 * sin(_t * 5.0)
			draw_circle(p, 3.0 + k * 2.0, Color(1.0, 0.85, 0.3, 0.35 + 0.3 * k))
			draw_circle(p, 2.5, Color(1.0, 0.9, 0.4))
		draw_rect(Rect2(Vector2.ZERO, size), Color(ContinentUI.ACCENT, 0.35), false, 1.0)
	func _gui_input(e: InputEvent) -> void:
		var go := false
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			go = true
		elif e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT:
			go = true
		if go:
			var p: Vector2 = e.position.clamp(Vector2.ZERO, size)
			jump.emit(area.position + p / size * area.size)
			accept_event()

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
	# фильтры: тип, размер, город (можно искать и без текста — только по фильтрам)
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 4)
	sv.add_child(fr)
	_f_type = _option(fr, ["Все типы"] + FakeTree.TYPE_NAMES)
	_f_size = _option(fr, ["Любой размер"] + SIZE_NAMES)
	_f_city = _option(fr, ["Все города"])
	_found_label = Label.new()
	_found_label.add_theme_font_size_override("font_size", 12)
	_found_label.modulate.a = 0.75
	_found_label.visible = false
	sv.add_child(_found_label)
	_results_scroll = ScrollContainer.new()
	_results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_results_scroll.custom_minimum_size = Vector2(330, 0)
	sv.add_child(_results_scroll)
	_results = VBoxContainer.new()
	_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results.add_theme_constant_override("separation", 1)
	_results_scroll.add_child(_results)

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
	var st := Button.new()
	st.text = "Статистика"
	st.tooltip_text = "Статистика города: типы файлов, самые большие файлы и дома  (I)"
	st.pressed.connect(stats_pressed.emit)
	row.add_child(st)
	var hb := Button.new()
	hb.text = "?"
	hb.tooltip_text = "Управление и горячие клавиши  (F1)"
	hb.custom_minimum_size.x = 34
	hb.pressed.connect(func(): help.visible = not help.visible)
	row.add_child(hb)

	# легенда справа снизу
	var br := _panel(root, Vector2(1, 1), Vector2(-12, -12))
	_legend_panel = br
	var leg := VBoxContainer.new()
	leg.add_theme_constant_override("separation", 2)
	br.add_child(leg)
	var title := Button.new()  # заголовок легенды сворачивает её (L)
	title.flat = true
	title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # текст ставит _show_legend
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	title.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	title.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	title.modulate.a = 0.75
	leg.add_child(title)
	var grid := GridContainer.new()  # типов много — в две колонки
	_legend_grid = grid
	_legend_title = title
	title.pressed.connect(toggle_legend)
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 0)
	leg.add_child(grid)
	for t in FakeTree.TYPE_NAMES.size():
		var line := HBoxContainer.new()
		line.add_child(Dot.new(WorldMap.TYPE_COLORS[t]))
		var b := Button.new()
		b.text = FakeTree.TYPE_NAMES[t]
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		b.tooltip_text = I18n.t("Показать на карте все файлы типа «%s»") % I18n.t(FakeTree.TYPE_NAMES[t])
		var tight := StyleBoxEmpty.new()  # строки легенды низкие, как раньше
		tight.content_margin_left = 2
		tight.content_margin_top = 0
		tight.content_margin_bottom = 0
		for s in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(s, tight)
		b.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.55))
		b.pressed.connect(type_chosen.emit.bind(t))
		line.add_child(b)
		grid.add_child(line)
		_type_rows.append(line)
	_show_legend(legend_open)
	minimap = Minimap.new()
	minimap.visible = false  # покажет continent, когда карта построена
	leg.add_child(minimap)

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

	arrow = EdgeArrow.new()
	root.add_child(arrow)

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

	# статистика города — окно по центру, под ним то же затемнение
	stats = STATS.new()
	stats.visibility_changed.connect(func(): shade.visible = stats.visible or tree.visible)
	root.add_child(stats)
	help = HELP.new()
	help.visibility_changed.connect(func(): shade.visible = help.visible or stats.visible or tree.visible)
	root.add_child(help)

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

## Общая тема интерфейса (меню, космос, древо тоже её берут): тёмное стекло, тонкая золотая кайма.
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var panel := _box(BG, Color(ACCENT, 0.28), 10, 12)
	panel.shadow_color = Color(0, 0, 0, 0.35)
	panel.shadow_size = 10
	panel.shadow_offset = Vector2(0, 3)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "PopupPanel", panel)
	# кнопки: спокойные, при наведении — светлее и с золотой каймой, нажатая — золотистая
	var bn := _box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.10), 7, 0)
	_pad(bn, 12, 5)
	var bh := _box(Color(1, 1, 1, 0.13), Color(ACCENT, 0.7), 7, 0)
	_pad(bh, 12, 5)
	var bp := _box(Color(ACCENT, 0.28), ACCENT, 7, 0)
	_pad(bp, 12, 5)
	var bd := _box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.05), 7, 0)
	_pad(bd, 12, 5)
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, bn)
		t.set_stylebox("hover", type, bh)
		t.set_stylebox("pressed", type, bp)
		t.set_stylebox("hover_pressed", type, bp)
		t.set_stylebox("disabled", type, bd)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color(1.0, 0.95, 0.85))
		t.set_color("font_pressed_color", type, Color(1.0, 0.9, 0.65))
		t.set_color("font_hover_pressed_color", type, Color(1.0, 0.9, 0.65))
		t.set_color("font_disabled_color", type, Color(TEXT, 0.35))
	# флажки — без подложки-кнопки, только строка
	var flat := StyleBoxEmpty.new()
	flat.content_margin_left = 2
	flat.content_margin_top = 4
	flat.content_margin_bottom = 4
	var fh := _box(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 6, 0)
	_pad(fh, 2, 4)
	for s in ["normal", "pressed", "disabled", "focus"]:
		t.set_stylebox(s, "CheckBox", flat)
	t.set_stylebox("hover", "CheckBox", fh)
	t.set_stylebox("hover_pressed", "CheckBox", fh)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color(1.0, 0.95, 0.85))
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", Color(1.0, 0.95, 0.85))
	t.set_constant("h_separation", "CheckBox", 10)
	t.set_icon("checked", "CheckBox", _tick(true))
	t.set_icon("unchecked", "CheckBox", _tick(false))
	# поля ввода
	var le := _box(Color(0, 0, 0, 0.32), Color(1, 1, 1, 0.16), 7, 0)
	_pad(le, 10, 6)
	var lf := le.duplicate()
	lf.border_color = Color(ACCENT, 0.85)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", lf)
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.38))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	t.set_color("font_color", "Label", TEXT)
	# выпадающие и контекстные меню
	var pm := _box(Color(0.06, 0.07, 0.09, 0.98), Color(ACCENT, 0.35), 8, 6)
	t.set_stylebox("panel", "PopupMenu", pm)
	var ph := _box(Color(ACCENT, 0.22), Color(0, 0, 0, 0), 5, 0)
	t.set_stylebox("hover", "PopupMenu", ph)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color(1.0, 0.95, 0.85))
	t.set_color("font_separator_color", "PopupMenu", Color(TEXT, 0.5))
	t.set_constant("v_separation", "PopupMenu", 8)
	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.1)
	t.set_stylebox("separator", "PopupMenu", sep)
	# подсказки
	var tip := _box(Color(0.05, 0.06, 0.08, 0.96), Color(ACCENT, 0.4), 6, 0)
	_pad(tip, 8, 5)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	# ползунки
	var track := _box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 3, 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := _box(Color(ACCENT, 0.75), Color(0, 0, 0, 0), 3, 0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _knob(false))
	t.set_icon("grabber_highlight", "HSlider", _knob(true))
	# полосы прокрутки — тонкие
	for type in ["VScrollBar", "HScrollBar"]:
		var sc := _box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 4, 0)
		_pad(sc, 3, 3)
		var gr := _box(Color(1, 1, 1, 0.22), Color(0, 0, 0, 0), 4, 0)
		_pad(gr, 3, 3)
		var gh := _box(Color(ACCENT, 0.6), Color(0, 0, 0, 0), 4, 0)
		_pad(gh, 3, 3)
		t.set_stylebox("scroll", type, sc)
		t.set_stylebox("grabber", type, gr)
		t.set_stylebox("grabber_highlight", type, gh)
		t.set_stylebox("grabber_pressed", type, gh)
	return t

## Главная кнопка экрана — золотая с тёмным текстом.
static func make_primary(b: Button) -> void:
	for s in [["normal", 0.85], ["hover", 1.0], ["pressed", 0.7], ["hover_pressed", 0.7]]:
		var sb := _box(Color(ACCENT, s[1]), Color(1.0, 0.9, 0.7, 0.6 * s[1]), 7, 0)
		_pad(sb, 12, 5)
		b.add_theme_stylebox_override(s[0], sb)
	b.add_theme_color_override("font_color", Color(0.12, 0.08, 0.03))
	b.add_theme_color_override("font_hover_color", Color(0.08, 0.05, 0.02))
	b.add_theme_color_override("font_pressed_color", Color(0.08, 0.05, 0.02))

## Скруглённая плашка с каймой (border — прозрачный цвет: без каймы).
static func _box(bg: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1 if border.a > 0.0 else 0)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing = true
	return sb

static func _pad(sb: StyleBox, h: int, v: int) -> void:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v

## Значок флажка 18×18: скруглённый квадрат, у включённого — золотой с галочкой.
static func _tick(on: bool) -> ImageTexture:
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var q := (p - Vector2(n, n) / 2).abs() - Vector2(n / 2.0 - 4.0, n / 2.0 - 4.0)
			var d := Vector2(maxf(q.x, 0), maxf(q.y, 0)).length() + minf(maxf(q.x, q.y), 0) - 3.0  # расстояние до скруглённого квадрата
			var a := clampf(0.5 - d, 0, 1)
			var c := Color(ACCENT, a) if on else Color(1, 1, 1, a * 0.1)
			var edge := clampf(1.0 - absf(d + 0.5), 0, 1)
			if not on and edge > 0:
				c = c.blend(Color(1, 1, 1, edge * 0.45))
			if on:
				# галочка: два отрезка
				var t1 := _seg(p, Vector2(4.5, 9.5), Vector2(7.5, 12.5))
				var t2 := _seg(p, Vector2(7.5, 12.5), Vector2(13.5, 5.5))
				var k := clampf(1.8 - minf(t1, t2), 0, 1) * a
				c = c.lerp(Color(0.1, 0.08, 0.05, a), k)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

static func _seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var h := clampf((p - a).dot(ab) / ab.length_squared(), 0, 1)
	return (p - a - ab * h).length()

## Ручка ползунка: светлый кружок с золотой каймой.
static func _knob(hot: bool) -> ImageTexture:
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(n, n) / 2)
			var a := clampf(7.0 - d, 0, 1)
			var c := Color(1.0, 0.97, 0.9) if hot else Color(0.92, 0.9, 0.86)
			if d > 5.0:
				c = ACCENT
			img.set_pixel(x, y, Color(c, a))
	return ImageTexture.create_from_image(img)

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
	# заголовок — имя крупно; ниже строки «подпись — значение»: подпись приглушённая слева, значение справа
	for i in rows.size():
		var l := Label.new()
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # имена и уже переведённый текст
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if i == 0:
			l.text = rows[i][1]
			l.add_theme_font_size_override("font_size", 19)
			l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.86))
			_info_box.add_child(l)
			var bar := ColorRect.new()
			bar.color = Color(ACCENT, 0.6)
			bar.custom_minimum_size = Vector2(36, 2)
			bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			_info_box.add_child(bar)
			continue
		var row := HBoxContainer.new()
		var k := Label.new()
		k.text = I18n.t(rows[i][0])
		k.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		k.add_theme_font_size_override("font_size", 13)
		k.modulate.a = 0.55
		k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		k.custom_minimum_size.x = 70
		row.add_child(k)
		l.text = rows[i][1]
		l.add_theme_font_size_override("font_size", 14)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		_info_box.add_child(row)

## Файлы дома: rows — [[имя, размер, цвет точки], ...]; клик — file_chosen(i); пусто — спрятать.
func show_files(rows: Array) -> void:
	for c in _files.get_children():
		c.queue_free()
	_files_title.visible = not rows.is_empty()
	_files_scroll.visible = not rows.is_empty()
	_files_title.text = I18n.t("Жители дома (%d):") % rows.size()
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
	_files_rows = rows.size()
	_fit_files()
	mark_file(-1)

## Список не дотягивается до легенды внизу справа: строк столько, сколько влезает по высоте окна.
func _fit_files() -> void:
	if _legend_panel == null:
		return
	var below: float = _legend_panel.get_combined_minimum_size().y + 24  # легенда с мини-картой и зазоры
	var room := int((_files_scroll.get_viewport_rect().size.y - below - 290) / 24)
	_files_scroll.custom_minimum_size.y = mini(_files_rows, clampi(room, 3, 14)) * 24
	_shrink(_info)

## Ужать панель, прижатую к углу, до её содержимого (растёт снова от угла).
func _shrink(p: Control) -> void:
	if p.grow_horizontal == Control.GROW_DIRECTION_BEGIN:
		p.offset_left = p.offset_right
	else:
		p.offset_right = p.offset_left
	if p.grow_vertical == Control.GROW_DIRECTION_BEGIN:
		p.offset_top = p.offset_bottom
	else:
		p.offset_bottom = p.offset_top

## Подсветить строку i в списке файлов (-1 — ни одной).
func mark_file(i: int) -> void:
	for k in _files.get_child_count():
		_files.get_child(k).modulate = Color(1.0, 0.9, 0.4) if k == i else Color.WHITE

func _option(parent: Control, names: Array) -> OptionButton:
	var o := OptionButton.new()
	for n in names:
		o.add_item(n)
	o.add_theme_font_size_override("font_size", 12)
	o.fit_to_longest_item = false
	o.custom_minimum_size.x = 100
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.item_selected.connect(func(_i): search_changed.emit(_search.text))
	parent.add_child(o)
	return o

## Города для фильтра поиска.
func set_cities(names: Array) -> void:
	_f_city.clear()
	_f_city.add_item("Все города")
	for n in names:
		_f_city.add_item(n)

## Выбранные фильтры: type (-1 — любой), size (-1 — любой; иначе индекс SIZE_LIMITS), city (-1 — любой).
func filters() -> Dictionary:
	return {"type": _f_type.selected - 1, "size": _f_size.selected - 1, "city": _f_city.selected - 1}

## Найденное: rows — [[текст, цвет точки], ...]; клик по строке — result_chosen(i). total — сколько всего нашлось.
func show_results(rows: Array, total := -1) -> void:
	_found_label.visible = total >= 0
	if total == 0:
		_found_label.text = "Ничего не нашлось"
	elif total > 0:
		_found_label.text = I18n.t("Найдено: %d%s — подсвечены на карте") % [total, I18n.t(" (показаны первые %d)") % rows.size() if rows.size() < total else ""]
	_results_scroll.custom_minimum_size.y = mini(rows.size(), 10) * 25
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
	for o in [_f_type, _f_size, _f_city]:
		o.select(0)
	show_results([])
	search_changed.emit("")
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

## Стрелка к точке экрана at (Vector2.INF — спрятать): видна, только если точка за краем.
func point_arrow(at: Vector2, text: String) -> void:
	var vp: Vector2 = arrow.get_viewport_rect().size
	var inner := Rect2(Vector2(60, 60), vp - Vector2(120, 120))
	if not at.is_finite() or inner.has_point(at) or tree.visible:
		arrow.visible = false
		return
	var c := vp / 2
	var d := (at - c).normalized()
	var half := vp / 2 - Vector2(70, 70)
	var k := minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
	arrow.position = c + d * k - arrow.size / 2
	arrow.angle = d.angle()
	arrow.label = text
	arrow.visible = true

func toggle_legend() -> void:
	_show_legend(not legend_open)

func _show_legend(on: bool) -> void:
	legend_open = on
	_legend_grid.visible = on
	_legend_title.text = I18n.t("Одежда = тип файла  %s") % ("▾" if on else "▸")
	_legend_title.tooltip_text = I18n.t("Свернуть / развернуть легенду  (L)") + ("\n" + I18n.t("клик по типу — найти на карте") if on else "")
	_shrink(_legend_panel)
	_fit_files()

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
