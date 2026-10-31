class_name FamilyTree
extends PanelContainer
## Вкладка «Семейное древо». Папка — родитель (отец или мать), всё, что в ней лежит, — её дети:
## файл — сын или дочь, подпапка — тоже ребёнок, у которого свои дети. Диск — родоначальник.
## Показывается родня выбранного: дедушка/бабушка, отец/мать, братья и сёстры, его дети.
## Длинные ряды переносятся по ширине окна. Клик по карточке — его семья; клик по выбранной
## (золотой) или «Показать на карте» — к нему на карту. Клавиши: ←/→ брат или сестра, ↑ родитель,
## ↓ первый ребёнок, Backspace — назад, Enter — на карту, Ctrl+F — поиск по роду.

signal show_on_map(person)   # Folder или FileItem

const CARD := Vector2(118, 134)
const GAP := 14.0
const ROW := 172.0             # шаг рядов (между рядами — место под линии)
const PAD := 40.0
const LINE := Color(0.85, 0.7, 0.45, 0.85)
const GOLD := Color(1.0, 0.85, 0.4)
const WORDS := {"grand": ["дедушка", "бабушка"], "parent": ["отец", "мать"], "sib": ["брат", "сестра"],
	"kid": ["сын", "дочь"]}

var _root
var _parent := {}     # человек (Folder / FileItem) -> Folder-родитель
var _looks := {}
var _focus
var _history: Array = []  # кого смотрели раньше (для «Назад»)
var _scroll: ScrollContainer
var _canvas: Control
var _crumbs: HBoxContainer
var _info: Label
var _back: Button
var _search: LineEdit
var _found_label: Label
var _found: Array = []
var _found_i := -1
var _links: Array = []    # [Rect2 родителя, [[Rect2 ...] по строкам]]
var _link_a := 1.0        # прозрачность линий (проявляются вместе с карточками)
var _drag := false
var _tw: Tween

static func is_folder(p) -> bool:
	return p is FakeTree.Folder

## Пол по имени (выдуманный, но всегда один и тот же).
static func female(p) -> bool:
	return absi(String(p.name).hash()) % 2 == 1

static func word(kind: String, p) -> String:
	return WORDS[kind][int(female(p))]

## Дети папки: сначала подпапки, потом файлы.
static func kids(f) -> Array:
	return f.children + f.files

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.06, 0.05, 0.97)
	bg.border_color = Color(0.6, 0.47, 0.28)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(14)
	add_theme_stylebox_override("panel", bg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	_back = Button.new()
	_back.text = "◀ Назад"
	_back.tooltip_text = "К кому смотрели до этого  (Backspace)"
	_back.pressed.connect(go_back)
	head.add_child(_back)
	var title := Label.new()
	title.text = "Семейное древо"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", GOLD)
	head.add_child(title)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(space)
	_search = LineEdit.new()
	_search.placeholder_text = "Найти в роду…  (Ctrl+F)"
	_search.custom_minimum_size.x = 220
	_search.text_changed.connect(func(_t): _found.clear())
	_search.text_submitted.connect(func(_t): _find_next())
	head.add_child(_search)
	_found_label = Label.new()
	_found_label.custom_minimum_size.x = 70
	_found_label.add_theme_font_size_override("font_size", 13)
	_found_label.modulate.a = 0.7
	head.add_child(_found_label)
	var map_btn := Button.new()
	map_btn.text = "Показать на карте"
	map_btn.tooltip_text = "Enter"
	map_btn.pressed.connect(func(): show_on_map.emit(_focus))
	head.add_child(map_btn)
	var close := Button.new()
	close.text = "Закрыть  (Esc)"
	close.pressed.connect(hide)
	head.add_child(close)
	_crumbs = HBoxContainer.new()
	v.add_child(_crumbs)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 13)
	_info.modulate.a = 0.75
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_info)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # ряды переносятся
	v.add_child(_scroll)
	_canvas = Control.new()
	_canvas.draw.connect(_draw_links)
	_canvas.gui_input.connect(_on_canvas_input)
	_scroll.add_child(_canvas)
	var hint := Label.new()
	hint.text = "Папка — родитель, всё внутри неё — её дети.   Клик — его семья · клик по золотой — на карту · ←/→ братья и сёстры · ↑ родитель · ↓ дети · Backspace — назад"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate.a = 0.5
	v.add_child(hint)

## Открыть древо на человеке (Folder или FileItem). root — корень диска.
func open(root, person) -> void:
	_root = root
	_parent.clear()
	_history.clear()
	_index(root)  # дерево могло поменяться (удаления, вставки)
	show()
	await get_tree().process_frame  # ширина окна известна — от неё зависит перенос рядов
	focus_on(person, false)

func _index(f) -> void:
	for c in f.children:
		_parent[c] = f
		_index(c)
	for x in f.files:
		_parent[x] = f

func parent_of(p):
	return _parent.get(p)

func focused():
	return _focus

## Печатают в поиске древа (тогда горячие клавиши не трогаем).
func typing() -> bool:
	return _search.has_focus()

## Внешность: файл — как его житель; папка — старший в одежде цвета самых частых её файлов, седой.
func look_of(p) -> Dictionary:
	if not _looks.has(p):
		if is_folder(p):
			var fi := FakeTree.FileItem.new()
			fi.name = "папка:" + p.name
			fi.type = _main_type(p)
			var lk := Pawn.look(fi)
			lk.hair_color = Pawn.HAIR_COLORS[5]
			if lk.hair == 2 and female(p):
				lk.hair = 3
			_looks[p] = lk
		else:
			_looks[p] = Pawn.look(p)
	return _looks[p]

static func _main_type(f) -> int:
	var n := {}
	for x in f.files:
		n[x.type] = n.get(x.type, 0) + 1
	var best := FakeTree.Type.OTHER
	for t in n:
		if n[t] > n.get(best, 0):
			best = t
	return best

## Кто он своему родителю: «сын «Проекты»», у диска — «родоначальник».
func role(p) -> String:
	var par = parent_of(p)
	return "родоначальник" if par == null else "%s «%s»" % [word("kid", p), par.name]

# --- навигация ---

func go_back() -> void:
	if not _history.is_empty():
		focus_on(_history.pop_back(), false)

func _unhandled_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey) or not e.pressed:
		return
	if e.keycode == KEY_F and e.ctrl_pressed:
		_search.grab_focus()
		_search.select_all()
		get_viewport().set_input_as_handled()
		return
	if typing():
		return
	var par = parent_of(_focus)
	match e.keycode:
		KEY_LEFT, KEY_RIGHT:
			if par != null:
				var sibs := kids(par)
				var i := (sibs.find(_focus) + (1 if e.keycode == KEY_RIGHT else -1) + sibs.size()) % sibs.size()
				focus_on(sibs[i])
		KEY_UP:
			if par != null:
				focus_on(par)
		KEY_DOWN:
			if is_folder(_focus) and not kids(_focus).is_empty():
				focus_on(kids(_focus)[0])
		KEY_BACKSPACE:
			go_back()
		KEY_ENTER, KEY_KP_ENTER:
			show_on_map.emit(_focus)
		_:
			return
	get_viewport().set_input_as_handled()

## Поиск по всему роду (диску): Enter — следующий найденный.
func _find_next() -> void:
	var q := _search.text.strip_edges().to_lower()
	if q.is_empty():
		return
	if _found.is_empty():
		_found_i = -1
		if String(_root.name).to_lower().contains(q):
			_found.append(_root)
		for p in _parent:
			if String(p.name).to_lower().contains(q):
				_found.append(p)
	if _found.is_empty():
		_found_label.text = "нет"
		return
	_found_i = (_found_i + 1) % _found.size()
	_found_label.text = "%d из %d" % [_found_i + 1, _found.size()]
	focus_on(_found[_found_i])
	_search.grab_focus()  # Enter ещё раз — следующий

# --- раскладка ---

## Показать семью человека p. remember — запомнить прежнего для «Назад».
func focus_on(p, remember := true) -> void:
	if remember and _focus != null and _focus != p:
		_history.append(_focus)
		if _history.size() > 50:
			_history.pop_front()
	_back.disabled = _history.is_empty()
	_focus = p
	for c in _canvas.get_children():
		c.queue_free()
	_links.clear()
	var par = parent_of(p)
	var grand = parent_of(par) if par != null else null
	var sibs: Array = kids(par) if par != null else [p]
	var mine: Array = kids(p) if is_folder(p) else []
	# сколько карточек в строке — по ширине окна
	var step := CARD.x + GAP
	var width := maxf(_scroll.size.x, 900.0)
	var cols := maxi(4, int((width - 2 * PAD + GAP) / step))
	var cx := width / 2
	var y := PAD * 0.5
	var cards: Array = []  # [карточка, человек] — для анимации появления
	var r_grand := Rect2()
	var r_par := Rect2()
	if grand != null:
		r_grand = _card(grand, Vector2(cx - CARD.x / 2, y), word("grand", grand), cards)
		y += ROW
	if par != null:
		r_par = _card(par, Vector2(cx - CARD.x / 2, y), word("parent", par), cards)
		y += ROW
		if grand != null:
			_links.append([r_grand, [[r_par]]])
	var r_me := Rect2()
	var lines: Array = []
	for i0 in range(0, sibs.size(), cols):
		var line: Array = []
		var n := mini(cols, sibs.size() - i0)
		var x0 := cx - (n * step - GAP) / 2
		for j in n:
			var s = sibs[i0 + j]
			var rel := ("это она" if female(s) else "это он") if s == p else word("sib", s)
			var r := _card(s, Vector2(x0 + j * step, y), rel, cards)
			line.append(r)
			if s == p:
				r_me = r
		lines.append(line)
		y += ROW
	if par != null:
		_links.append([r_par, lines])
	var klines: Array = []
	for i0 in range(0, mine.size(), cols):
		var line: Array = []
		var n := mini(cols, mine.size() - i0)
		var x0 := cx - (n * step - GAP) / 2
		for j in n:
			line.append(_card(mine[i0 + j], Vector2(x0 + j * step, y), word("kid", mine[i0 + j]), cards))
		klines.append(line)
		y += ROW
	if not klines.is_empty():
		_links.append([r_me, klines, true])
	_canvas.custom_minimum_size = Vector2(width - 20, y)
	_appear(cards)
	_fill_header(p, sibs, mine)
	# прокрутить: сверху родитель (или он сам)
	var top := (r_par.position.y if par != null else r_me.position.y) - 12
	if _tw:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(_scroll, "scroll_vertical", int(maxf(top, 0.0)), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## Карточки проявляются по очереди и чуть всплывают, линии — вместе с ними.
func _appear(cards: Array) -> void:
	var tw := create_tween().set_parallel()
	_link_a = 0.0
	tw.tween_method(func(a: float) -> void:
		_link_a = a
		_canvas.queue_redraw(), 0.0, 1.0, 0.35)
	for i in cards.size():
		var c: Control = cards[i]
		var to := c.position
		c.position = to + Vector2(0, 14)
		c.modulate.a = 0.0
		var d := minf(i * 0.02, 0.4)
		tw.tween_property(c, "position", to, 0.25).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "modulate:a", 1.0, 0.2).set_delay(d)

func _fill_header(p, sibs: Array, mine: Array) -> void:
	for c in _crumbs.get_children():
		c.queue_free()
	var chain := [p]
	while parent_of(chain[0]) != null:
		chain.push_front(parent_of(chain[0]))
	var l := Label.new()
	l.text = "Род:"
	l.modulate.a = 0.7
	_crumbs.add_child(l)
	for i in chain.size():
		if i > 0:
			var sep := Label.new()
			sep.text = "›"
			sep.modulate.a = 0.5
			_crumbs.add_child(sep)
		var b := Button.new()
		b.text = chain[i].name
		b.pressed.connect(focus_on.bind(chain[i]))
		_crumbs.add_child(b)
	var who := "%s — %s" % [p.name, role(p)]
	if is_folder(p):
		var sons := mine.filter(func(x): return not female(x)).size()
		who += " · детей %d (сыновей %d, дочерей %d; папок %d, файлов %d)" % [mine.size(), sons, mine.size() - sons,
			p.children.size(), p.files.size()]
	else:
		who += " · %s, %s" % [FakeTree.TYPE_NAMES[p.type], FakeTree.format_size(p.size)]
	if parent_of(p) != null:
		who += " · братьев и сестёр: %d" % (sibs.size() - 1)
	_info.text = who

## Карточка человека: портрет-житель, имя, кем приходится, размер или число детей.
func _card(p, at: Vector2, relation: String, cards: Array) -> Rect2:
	var me: bool = p == _focus
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.15, 0.09) if is_folder(p) else Color(0.13, 0.12, 0.11)
	sb.border_color = GOLD if me else Color(0.5, 0.4, 0.27)
	sb.set_border_width_all(3 if me else 1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	if me:
		sb.shadow_color = Color(1.0, 0.8, 0.3, 0.35)
		sb.shadow_size = 8
	card.add_theme_stylebox_override("panel", sb)
	card.position = at
	card.custom_minimum_size = CARD
	card.size = CARD
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "%s\n%s\n%s" % [p.name, role(p), "клик — показать на карте" if me else "клик — его семья"]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var pv := ContinentUI.PawnView.new()
	pv.look = look_of(p)
	pv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pv)
	_text(v, p.name, 13, Color.WHITE)
	_text(v, relation, 12, GOLD if me else Color(0.95, 0.8, 0.55))
	if is_folder(p):
		_text(v, "папка · детей %d" % kids(p).size(), 11, Color(1, 1, 1, 0.6))
	else:
		_text(v, "%s · %s" % [FakeTree.TYPE_NAMES[p.type], FakeTree.format_size(p.size)], 11, Color(1, 1, 1, 0.6))
	# наведение — карточка светлеет, рамка ярче
	card.mouse_entered.connect(func():
		card.self_modulate = Color(1.25, 1.2, 1.1)
		if not me:
			sb.border_color = Color(0.85, 0.7, 0.45))
	card.mouse_exited.connect(func():
		card.self_modulate = Color.WHITE
		if not me:
			sb.border_color = Color(0.5, 0.4, 0.27))
	card.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not e.double_click:
			if me:
				show_on_map.emit(p)  # клик по выбранному — показать на карте
			else:
				focus_on(p))
	_canvas.add_child(card)
	cards.append(card)
	return Rect2(at, CARD)

func _text(parent: Control, text: String, size: int, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size.x = CARD.x - 14
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)

## Линии родства: от родителя вниз; если детей несколько строк — ствол слева от строк,
## от него перекладина над каждой строкой и отводы к каждому ребёнку.
func _draw_links() -> void:
	var half := (ROW - CARD.y) / 2
	for link in _links:
		var top: Rect2 = link[0]
		var lines: Array = link[1]
		var own: bool = link.size() > 2  # дети выбранного — золотом и чуть в стороне, чтобы не путались
		var col := Color(GOLD if own else LINE, (0.9 if own else LINE.a) * _link_a)
		var a := Vector2(top.get_center().x, top.end.y)
		var first: Rect2 = lines[0][0]
		var direct := lines.size() == 1 and absf(first.position.y - top.end.y - 2 * half) < 1.0
		var ya := a.y + (half if direct or not own else half * 0.5)
		var trunk := 1e9
		for line in lines:
			trunk = minf(trunk, line[0].position.x - GAP - (8.0 if own else 0.0))
		_canvas.draw_line(a, Vector2(a.x, ya), col, 2.0)
		_canvas.draw_circle(a, 4.0, col)
		var last_y := ya
		if not direct:
			_canvas.draw_line(Vector2(a.x, ya), Vector2(trunk, ya), col, 2.0)
		for line in lines:
			var r0: Rect2 = line[0]
			var r1: Rect2 = line[-1]
			var bar := r0.position.y - half
			var x0 := minf(r0.get_center().x, a.x if direct else trunk)
			var x1 := maxf(r1.get_center().x, a.x if direct else trunk)
			_canvas.draw_line(Vector2(x0, bar), Vector2(x1, bar), col, 2.0)
			for r in line:
				_canvas.draw_line(Vector2(r.get_center().x, bar), Vector2(r.get_center().x, r.position.y), col, 2.0)
			last_y = bar
		if not direct:
			_canvas.draw_line(Vector2(trunk, ya), Vector2(trunk, last_y), col, 2.0)

## Перетаскивание фона — прокрутка.
func _on_canvas_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		_scroll.scroll_vertical -= int(e.relative.y)
