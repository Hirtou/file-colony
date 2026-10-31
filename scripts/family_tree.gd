class_name FamilyTree
extends PanelContainer
## Вкладка «Семейное древо» — настоящее дерево. Внизу корень-диск (родоначальник), от него растут
## ветви-папки (толще — где больше потомков), на концах — кроны из листьев-файлов (лист цвета типа).
## Папка — родитель (отец или мать), всё, что в ней лежит, — её дети: файл — сын или дочь.
## Колёсико — приближение, перетаскивание — сдвиг, клик — карточка справа (путь до корня светится
## золотом), двойной клик — приблизить. Поиск по роду, «Только эта ветка», «Показать на карте».
## Клавиши: ↑ родитель, ↓ первый ребёнок, ←/→ братья и сёстры, Enter — на карту.

signal show_on_map(person)   # Folder или FileItem

const WORDS := {"grand": ["дедушка", "бабушка"], "parent": ["отец", "мать"], "sib": ["брат", "сестра"],
	"kid": ["сын", "дочь"]}
const GOLD := Color(1.0, 0.85, 0.4)

var _root                 # корень диска
var _parent := {}         # человек (Folder / FileItem) -> Folder-родитель
var _looks := {}
var _view: TreeView
var _card_pawn: ContinentUI.PawnView
var _card_name: Label
var _card_role: Label
var _card_info: Label
var _card_branch: Button
var _card_up: Button
var _whole: Button
var _search: LineEdit
var _found_label: Label
var _found: Array = []
var _found_i := -1

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
	bg.bg_color = Color(0.05, 0.06, 0.08, 0.98)
	bg.border_color = Color(0.6, 0.47, 0.28)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(12)
	add_theme_stylebox_override("panel", bg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	# шапка: название, поиск, «весь род», закрыть
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var title := Label.new()
	title.text = "Семейное древо"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", GOLD)
	head.add_child(title)
	_whole = Button.new()
	_whole.text = "◀ Весь род"
	_whole.tooltip_text = "Снова показать всё дерево диска  (Backspace)"
	_whole.visible = false
	_whole.pressed.connect(func(): _show_branch(_root))
	head.add_child(_whole)
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
	_found_label.custom_minimum_size.x = 64
	_found_label.add_theme_font_size_override("font_size", 13)
	_found_label.modulate.a = 0.7
	head.add_child(_found_label)
	var fit := Button.new()
	fit.text = "Всё дерево в кадр"
	fit.pressed.connect(func(): _view.fit())
	head.add_child(fit)
	var close := Button.new()
	close.text = "Закрыть  (Esc)"
	close.pressed.connect(hide)
	head.add_child(close)
	# дерево и карточка справа
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	v.add_child(body)
	_view = TreeView.new()
	_view.owner_tree = self
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_view)
	body.add_child(_make_card())
	var hint := Label.new()
	hint.text = "Колёсико — приблизить · перетаскивание — двигать · клик — выбрать · двойной клик — приблизить к нему · ↑ родитель · ↓ дети · ←/→ братья и сёстры · Enter — на карту"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate.a = 0.5
	v.add_child(hint)

func _make_card() -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 250
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.09, 0.06)
	sb.border_color = Color(0.55, 0.42, 0.26)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	_card_pawn = ContinentUI.PawnView.new()
	_card_pawn.custom_minimum_size = Vector2(96, 96)
	_card_pawn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_card_pawn)
	_card_name = _label(v, 18, Color.WHITE)
	_card_role = _label(v, 14, GOLD)
	_card_info = _label(v, 13, Color(1, 1, 1, 0.7))
	var map_btn := Button.new()
	map_btn.text = "Показать на карте"
	map_btn.pressed.connect(func(): show_on_map.emit(_view.selected))
	v.add_child(map_btn)
	_card_branch = Button.new()
	_card_branch.text = "Только эта ветка"
	_card_branch.tooltip_text = "Показать дерево только этой папки"
	_card_branch.pressed.connect(func(): _show_branch(_view.selected))
	v.add_child(_card_branch)
	_card_up = Button.new()
	_card_up.text = "↑ К родителю"
	_card_up.pressed.connect(func(): _go(parent_of(_view.selected)))
	v.add_child(_card_up)
	return card

func _label(parent: Control, size: int, col: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l

## Открыть древо на человеке (Folder или FileItem). root — корень диска.
func open(root, person) -> void:
	_root = root
	_parent.clear()
	_index(root)  # дерево могло поменяться (удаления, вставки, переселения)
	show()
	await get_tree().process_frame  # размер окна известен — от него зависит «всё в кадр»
	_view.build(root)
	_whole.visible = false
	_view.fit(true)
	_go(person, true)

func _index(f) -> void:
	for c in f.children:
		_parent[c] = f
		_index(c)
	for x in f.files:
		_parent[x] = f

func parent_of(p):
	return _parent.get(p)

func focused():
	return _view.selected if _view else null

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
			lk.erase("item")
			lk.chest = false
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

## Показать дерево только этой папки (или всего диска).
func _show_branch(f) -> void:
	if not is_folder(f):
		return
	var keep = _view.selected
	_view.build(f)
	_whole.visible = f != _root
	_view.fit(true)
	_go(keep if _view.has(keep) else f, true)

## Выбрать человека, лететь к нему, обновить карточку.
func _go(p, instant := false) -> void:
	if p == null:
		return
	if not _view.has(p):
		_show_branch(_root)
	_view.select(p)
	_view.fly_to(p, instant)
	_update_card()

func _update_card() -> void:
	var p = _view.selected
	if p == null:
		return
	_card_pawn.look = look_of(p)
	_card_pawn.queue_redraw()
	_card_name.text = p.name
	_card_role.text = role(p)
	var lines := []
	if is_folder(p):
		var k := kids(p)
		var sons := k.filter(func(x): return not female(x)).size()
		lines.append("папка · детей %d" % k.size())
		lines.append("сыновей %d, дочерей %d" % [sons, k.size() - sons])
		lines.append("всего потомков-файлов: %d" % p.total_files())
	else:
		lines.append("%s · %s" % [FakeTree.TYPE_NAMES[p.type], FakeTree.format_size(p.size)])
	var par = parent_of(p)
	if par != null:
		lines.append("братьев и сестёр: %d" % (kids(par).size() - 1))
	var chain := [p]
	while parent_of(chain[0]) != null:
		chain.push_front(parent_of(chain[0]))
	lines.append("род: " + " › ".join(chain.map(func(x): return x.name)))
	_card_info.text = "\n".join(lines)
	_card_branch.visible = is_folder(p) and kids(p).size() > 0 and p != _view.root
	_card_up.visible = par != null

# --- клавиши и поиск ---

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
	var p = _view.selected
	var par = parent_of(p) if p != null else null
	match e.keycode:
		KEY_UP:
			_go(par)
		KEY_DOWN:
			if p != null and is_folder(p) and not kids(p).is_empty():
				_go(kids(p)[0])
		KEY_LEFT, KEY_RIGHT:
			if par != null:
				var sibs := kids(par)
				_go(sibs[(sibs.find(p) + (1 if e.keycode == KEY_RIGHT else -1) + sibs.size()) % sibs.size()])
		KEY_ENTER, KEY_KP_ENTER:
			if p != null:
				show_on_map.emit(p)
		KEY_BACKSPACE:
			if _whole.visible:
				_show_branch(_root)
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
	_go(_found[_found_i])
	_search.grab_focus()  # Enter ещё раз — следующий


## Само дерево: раскладка и рисование. Мир дерева: корень в (0, 0), растёт вверх (y < 0).
class TreeView extends Control:
	const LEVEL := 190.0      # высота яруса ветвей
	const UNIT := 64.0        # ширина «места» на ярусе
	const LEAF := 26.0        # шаг листьев в кроне
	const BARK := Color(0.36, 0.24, 0.14)
	const BARK_DARK := Color(0.16, 0.1, 0.06)
	const GOLD := Color(1.0, 0.85, 0.4)

	var owner_tree: FamilyTree
	var root                  # папка — корень показанного дерева
	var selected = null
	var hovered = null
	var nodes := {}           # человек -> {pos, parent, folder, r, w (толщина ветви), crown}
	var order: Array = []     # папки сверху вниз по глубине — для рисования веток
	var leaves: Array = []    # файлы
	var zoom := 1.0
	var offset := Vector2.ZERO  # где на экране точка (0, 0) мира
	var _drag := false
	var _moved := 0.0
	var _tw: Tween
	var _font := ThemeDB.fallback_font

	var _frame = null         # что держать в кадре при смене размера: "fit" или человек; null — двигали руками

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		# окно ещё раскладывается — кадр пересчитываем, пока игрок сам не двинул дерево
		resized.connect(func():
			if _frame is String:
				fit(true)
			elif _frame != null:
				fly_to(_frame, true))

	func has(p) -> bool:
		return nodes.has(p)

	const SPAN := 2.8         # веер ветвей, рад (~160°, вверх)
	const MIN_ZOOM := 0.02    # дерево диска большое — отдалять можно сильно
	var _outer := 300.0       # радиус купола кроны
	var _depth := 1           # самая глубокая папка

	## Разложить дерево папки f куполом: ствол в (0, 0), ветви веером вверх, папки-дома (кроны листьев)
	## — по наружной дуге, промежуточные папки — на своих ярусах. Угол ветви — по её ширине.
	func build(f) -> void:
		root = f
		nodes.clear()
		order.clear()
		leaves.clear()
		var widths := {}
		_measure(f, widths)
		_depth = maxi(1, _max_depth(f, 0))
		_outer = maxf(widths[f] * UNIT / SPAN, LEVEL * 1.6)
		_place(f, null, 0.0, 0, widths)
		order.sort_custom(func(a, b): return nodes[a].pos.y < nodes[b].pos.y)
		queue_redraw()

	func _max_depth(f, d: int) -> int:
		var m := d
		for c in f.children:
			m = maxi(m, _max_depth(c, d + 1))
		return m

	## Точка ветви: угол — доля ширины, радиус — ярус (дом с кроной — на краю купола).
	func _polar(x_units: float, total: float, depth: int, is_house: bool) -> Vector2:
		if depth == 0:
			return Vector2.ZERO
		var a := -PI / 2 - SPAN / 2 + SPAN * (x_units / total)
		var r := _outer if is_house else _outer * 0.82 * pow(float(depth) / _depth, 0.85)
		return Vector2(cos(a), sin(a)) * r

	func _crown_r(k: int) -> float:
		return 0.0 if k == 0 else LEAF * sqrt(float(k)) * 0.95 + LEAF * 0.7

	func _measure(f, widths: Dictionary) -> float:
		var w := 0.0
		for c in f.children:
			w += _measure(c, widths)
		w = maxf(w, (_crown_r(f.files.size()) * 2.0 + 24.0) / UNIT)
		w = maxf(w, 1.0)
		widths[f] = w
		return w

	func _place(f, par, x0: float, depth: int, widths: Dictionary) -> void:
		var w: float = widths[f]
		var total_w: float = widths[root]
		var pos := _polar(x0 + w / 2.0, total_w, depth, f.children.is_empty())
		var total: int = f.total_files() + f.children.size()
		nodes[f] = {"pos": pos, "parent": par, "folder": true, "r": 22.0,
			"w": clampf(4.0 + sqrt(float(total)) * 2.6, 5.0, 60.0)}
		order.append(f)
		var x := x0
		for c in f.children:
			_place(c, f, x, depth + 1, widths)
			x += widths[c]
		# крона: листья по спирали подсолнуха снаружи от конца ветки
		var k: int = f.files.size()
		if k > 0:
			var cr := _crown_r(k)
			var out := pos.normalized() if pos.length() > 1.0 else Vector2.UP
			var center := pos + out * (cr + 16.0)
			if not f.children.is_empty():
				center = pos + out.rotated(-0.9) * (cr + 30.0)  # у папки с подпапками — крона сбоку
			nodes[f].crown = [center, cr]
			for i in k:
				var a := i * 2.39996  # золотой угол
				var d := LEAF * 0.95 * sqrt(float(i) + 0.5)
				var lp := center + Vector2(cos(a), sin(a)) * d
				nodes[f.files[i]] = {"pos": lp, "parent": f, "folder": false, "r": 13.0, "w": 2.0,
					"rot": float(absi(hash(f.files[i].name)) % 628) / 100.0}
				leaves.append(f.files[i])

	# --- камера дерева ---

	func to_screen(p: Vector2) -> Vector2:
		return offset + p * zoom

	func to_world(s: Vector2) -> Vector2:
		return (s - offset) / zoom

	## Всё дерево в кадр.
	func fit(instant := false) -> void:
		_frame = "fit"
		if nodes.is_empty() or size.x < 10:
			return
		var r := Rect2(nodes[root].pos, Vector2.ZERO)
		for p in nodes:
			r = r.expand(nodes[p].pos)
		r = r.grow(60).expand(Vector2(r.get_center().x, trunk_len() + 60))  # и ствол с землёй
		var z := clampf(minf(size.x / r.size.x, size.y / r.size.y), MIN_ZOOM, 2.0)
		_animate(z, size / 2 - r.get_center() * z, instant)

	## Лететь к человеку: он по центру, крупно.
	func fly_to(p, instant := false) -> void:
		if not nodes.has(p):
			return
		_frame = p
		var z := maxf(zoom, 1.1 if nodes[p].folder else 1.6)
		_animate(z, size / 2 - nodes[p].pos * z, instant)

	func _animate(z: float, off: Vector2, instant: bool) -> void:
		if _tw:
			_tw.kill()
		if instant:
			zoom = z
			offset = off
			queue_redraw()
			return
		_tw = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tw.tween_property(self, "zoom", z, 0.45)
		_tw.tween_property(self, "offset", off, 0.45)
		_tw.tween_method(func(_v): queue_redraw(), 0.0, 1.0, 0.45)

	func select(p) -> void:
		selected = p
		queue_redraw()

	func _pick(s: Vector2):
		var w := to_world(s)
		var best = null
		var bd := INF
		for p in nodes:
			var n: Dictionary = nodes[p]
			var d: float = w.distance_to(n.pos)
			if d < n.r + 4.0 / zoom and d < bd:
				bd = d
				best = p
		return best

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if e.pressed:
					var k := 1.15 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
					var nz := clampf(zoom * k, MIN_ZOOM, 4.0)
					var wp := to_world(e.position)
					zoom = nz
					offset = e.position - wp * zoom  # приближаем к курсору
					_frame = null
					queue_redraw()
				accept_event()
			elif e.button_index == MOUSE_BUTTON_LEFT:
				if e.pressed:
					_drag = true
					_moved = 0.0
					if e.double_click:
						var p = _pick(e.position)
						if p != null:
							zoom = maxf(zoom, 1.0)
							owner_tree._go(p)
				else:
					_drag = false
					if _moved < 6.0:
						var p = _pick(e.position)
						if p != null and zoom < 0.9:
							owner_tree._go(p)  # издалека — подлететь
						elif p != null:
							_select_only(p)
		elif e is InputEventMouseMotion:
			if _drag:
				offset += e.relative
				_moved += e.relative.length()
				if _moved > 6.0:
					_frame = null
				queue_redraw()
			else:
				var h = _pick(e.position)
				if h != hovered:
					hovered = h
					tooltip_text = "" if h == null else "%s\n%s" % [h.name, owner_tree.role(h)]
					queue_redraw()

	## Выбрать без полёта (уже крупно).
	func _select_only(p) -> void:
		select(p)
		owner_tree._update_card()

	# --- рисование ---

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.08, 0.1))
		if nodes.is_empty():
			return
		var view := Rect2(to_world(Vector2.ZERO), size / zoom).grow(80)
		_draw_ground()
		var gold := _gold_path()
		# ветви: от родителя к ребёнку, толстые снизу
		for f in order:
			var n: Dictionary = nodes[f]
			if n.parent == null:
				continue
			var a: Vector2 = nodes[n.parent].pos
			_branch(a, n.pos, n.w, gold.has(f), view)
		# веточки к листьям
		for f in leaves:
			var n: Dictionary = nodes[f]
			if not view.has_point(n.pos):
				continue
			var tip: Vector2 = nodes[n.parent].pos
			if zoom > 0.35:
				draw_line(to_screen(tip.lerp(n.pos, 0.35)), to_screen(n.pos), Color(BARK, 0.6), maxf(1.0, 1.5 * zoom))
		for f in leaves:
			if view.has_point(nodes[f].pos):
				_leaf(f, gold.has(f))
		for f in order:
			if view.has_point(nodes[f].pos):
				_knot(f, gold.has(f))
		# подписи папок — постоянного экранного размера
		for f in order:
			var n: Dictionary = nodes[f]
			if not view.has_point(n.pos) or (zoom < 0.3 and f != root and n.w < 18.0):
				continue
			_caption(to_screen(n.pos) + Vector2(0, 24 * minf(zoom, 1.5) + 4), f.name, 13 if f != root else 16, Color(1.0, 0.93, 0.78))
		if hovered != null and nodes.has(hovered):
			var hp := to_screen(nodes[hovered].pos)
			draw_arc(hp, (nodes[hovered].r + 6.0) * zoom, 0, TAU, 32, Color(1, 1, 1, 0.7), 2.0, true)

	## Путь от корня до выбранного — светится золотом.
	func _gold_path() -> Dictionary:
		var out := {}
		var p = selected
		while p != null and nodes.has(p):
			out[p] = true
			p = nodes[p].parent
		return out

	func _branch(a: Vector2, b: Vector2, w: float, lit: bool, view: Rect2) -> void:
		if not view.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(w)):
			return
		# изгиб: из родителя — по его направлению от ствола, в ребёнка — по направлению ребёнка
		var dist := a.distance_to(b)
		var da := a.normalized() if a.length() > 1.0 else Vector2.UP
		var db := b.normalized() if b.length() > 1.0 else Vector2.UP
		if b.y > a.y and a.length() < 1.0:
			da = Vector2.DOWN  # корни растут вниз
			db = (b - a).normalized()
		var c1 := a + da * dist * 0.45
		var c2 := b - db * dist * 0.35
		var pts := PackedVector2Array()
		var steps := 14
		for i in steps + 1:
			var t := float(i) / steps
			var u := 1.0 - t
			pts.append(to_screen(a * u * u * u + c1 * 3 * u * u * t + c2 * 3 * u * t * t + b * t * t * t))
		var least := clampf(w * 0.22, 1.5, 12.0)  # издалека толстые ветви не превращаются в нитки
		for i in steps:
			var t := float(i) / steps
			var wi := maxf(lerpf(w * 1.15, w * 0.7, t) * zoom, least)
			draw_line(pts[i], pts[i + 1], BARK_DARK, wi + 3.0)
		for i in steps:
			var t := float(i) / steps
			var wi := maxf(lerpf(w * 1.15, w * 0.7, t) * zoom, least)
			draw_line(pts[i], pts[i + 1], BARK, wi)
			draw_circle(pts[i + 1], wi * 0.5, BARK)
		if lit:
			draw_polyline(pts, Color(GOLD, 0.85), maxf(2.0, w * 0.25 * zoom), true)

	## Корень-диск: земля и корни под стволом.
	func _draw_ground() -> void:
		var base: Vector2 = nodes[root].pos
		var w: float = nodes[root].w
		var trunk := trunk_len()
		var foot := base + Vector2(0, trunk)
		var g := to_screen(foot)
		var all := Rect2(to_world(Vector2.ZERO), size / zoom).grow(400)
		draw_rect(Rect2(Vector2(0, g.y), Vector2(size.x, maxf(0.0, size.y - g.y))), Color(0.12, 0.09, 0.06))
		draw_line(Vector2(0, g.y), Vector2(size.x, g.y), Color(0.28, 0.4, 0.18), maxf(2.0, 6.0 * zoom))
		# ствол и корни
		for k in 5:
			var dx := (k - 2) * w * 1.4
			_branch(foot + Vector2(dx * 0.15, -4), foot + Vector2(dx * 2.2, trunk * 0.35 + absf(dx) * 0.4), w * 0.4, false, all)
		_draw_trunk(foot, base, w, all)

	## Ствол: от земли к развилке, внизу толще.
	func _draw_trunk(foot: Vector2, top: Vector2, w: float, view: Rect2) -> void:
		if not view.intersects(Rect2(top, Vector2.ZERO).expand(foot).grow(w * 2)):
			return
		var a := to_screen(foot)
		var b := to_screen(top)
		var kz := maxf(zoom, 18.0 / w)  # ствол издалека не тоньше ~18 px
		draw_line(a, b, BARK_DARK, (w * 1.6 + 6.0) * kz)
		var pts := PackedVector2Array([a + Vector2(-w * 1.0, 0) * kz, a + Vector2(w * 1.0, 0) * kz,
			b + Vector2(w * 0.6, 0) * kz, b + Vector2(-w * 0.6, 0) * kz])
		draw_colored_polygon(pts, BARK)
		draw_circle(b, w * 0.6 * kz, BARK)
		for k in 3:  # трещинки коры
			var x := (k - 1) * w * 0.4
			draw_line(a.lerp(b, 0.15) + Vector2(x, 0) * zoom, a.lerp(b, 0.75) + Vector2(x * 0.6, 0) * zoom, BARK_DARK, maxf(1.0, 2.0 * zoom))
		if selected != null:
			draw_line(a, b, Color(GOLD, 0.85), maxf(2.0, w * 0.25 * zoom))

	func trunk_len() -> float:
		return maxf(80.0, _outer * 0.3)

	## Узел-папка: деревянный медальон с портретом старшего.
	func _knot(f, lit: bool) -> void:
		var n: Dictionary = nodes[f]
		var c := to_screen(n.pos)
		var r: float = n.r * zoom * (1.3 if f == root else 1.0)
		var sel: bool = f == selected
		if sel:
			draw_circle(c, r + 9.0, Color(GOLD, 0.35))
		draw_circle(c, r + 3.0, GOLD if sel or lit else BARK_DARK)
		draw_circle(c, r, Color(0.45, 0.31, 0.18))
		draw_circle(c, r * 0.82, Color(0.2, 0.15, 0.1))
		if r > 9.0:
			Pawn.draw(self, c + Vector2(0, r * 0.12), r * 1.5, owner_tree.look_of(f), Residents.Facing.DOWN, 0.0, false, r > 18.0)

	## Лист-файл цвета типа; вблизи — лицо жителя и имя.
	func _leaf(f, lit: bool) -> void:
		var n: Dictionary = nodes[f]
		var c := to_screen(n.pos)
		var r: float = n.r * zoom
		var col: Color = WorldMap.TYPE_COLORS[f.type].lerp(Color(0.3, 0.6, 0.25), 0.35)
		var sel: bool = f == selected
		if r < 3.0:
			draw_circle(c, maxf(r, 1.5), col)
			return
		var d := Vector2.from_angle(n.rot)
		var s := d.orthogonal()
		var pts := PackedVector2Array([c + d * r * 1.25, c + s * r * 0.75, c - d * r * 1.1, c - s * r * 0.75])
		if sel:
			draw_circle(c, r * 1.6, Color(GOLD, 0.4))
		var outline := PackedVector2Array([c + d * (r * 1.25 + 2), c + s * (r * 0.75 + 2), c - d * (r * 1.1 + 2), c - s * (r * 0.75 + 2)])
		draw_colored_polygon(outline, GOLD if sel or lit else Color(0.1, 0.18, 0.08))
		draw_colored_polygon(pts, col)
		draw_line(c - d * r * 0.9, c + d * r * 1.0, col.darkened(0.3), maxf(1.0, r * 0.08))  # прожилка
		if r > 12.0:
			Pawn.draw(self, c + Vector2(0, r * 0.15), r * 1.25, owner_tree.look_of(f), Residents.Facing.DOWN, 0.0, false, r > 22.0)
		if r > 16.0 or sel:
			_caption(c + Vector2(0, r * 1.2 + 4), f.name, 11, Color(1, 1, 1, 0.9))

	func _caption(at: Vector2, text: String, size_px: int, col: Color) -> void:
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var p := at + Vector2(-w / 2, size_px)
		draw_string_outline(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 4, Color(0, 0, 0, 0.85))
		draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)
