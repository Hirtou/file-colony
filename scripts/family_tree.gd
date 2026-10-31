class_name FamilyTree
extends PanelContainer
## Вкладка «Семейное древо» — родословная сверху вниз. Наверху родоначальник-диск, ниже поколения:
## папка — родитель (отец или мать), всё, что в ней лежит, — её дети. Файлы дома висят под ним столбиком.
## Колёсико — приближение, перетаскивание — сдвиг, клик — карточка справа (путь до родоначальника светится
## золотом), «−/+» под папкой — свернуть/развернуть детей, двойной клик — приблизить.
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
var _fold: Button
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
	return I18n.t(WORDS[kind][int(female(p))])

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
	_fold = Button.new()
	_fold.tooltip_text = "Свёрнутые ветки раскрываются «+» под папкой"
	_fold.pressed.connect(func(): _view.fold_all(_view.collapsed.is_empty()))
	head.add_child(_fold)
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
	hint.text = "Колёсико — приблизить · перетаскивание — двигать · клик — выбрать · «−/+» — свернуть ветку · ↑ родитель · ↓ дети · ←/→ братья и сёстры · Enter — на карту"
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
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # тут имена и готовый текст
	parent.add_child(l)
	return l

## Открыть древо на человеке (Folder или FileItem). root — корень диска.
func open(root, person) -> void:
	_root = root
	_parent.clear()
	_index(root)  # дерево могло поменяться (удаления, вставки, переселения)
	show()
	await get_tree().process_frame  # размер окна известен — от него зависит «всё в кадр»
	_view.opened.clear()
	_view.root = root
	_view.focus_on(person)  # раскрыта только ветка выбранного — остальное под «+»
	_view.build(root)
	_whole.visible = false
	_sync_fold()
	_view.fit(true)
	_go(person, true)

## Кнопка «Свернуть всё» / «Развернуть всё» — по тому, есть ли свёрнутые ветки.
func _sync_fold() -> void:
	_fold.text = I18n.t("Свернуть всё" if _view.collapsed.is_empty() else "Развернуть всё")

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
	return I18n.t("родоначальник") if par == null else I18n.t("%s «%s»") % [word("kid", p), par.name]

## Показать дерево только этой папки (или всего диска).
func _show_branch(f) -> void:
	if not is_folder(f):
		return
	var keep = _view.selected
	_view.build(f)
	_whole.visible = f != _root
	_sync_fold()
	_view.fit(true)
	_go(keep if _view.has(keep) else f, true)

## Выбрать человека, лететь к нему, обновить карточку. Свёрнутые ветки на пути к нему раскрываются.
func _go(p, instant := false) -> void:
	if p == null:
		return
	if not _view.has(p) and not _view.reveal(p):
		_show_branch(_root)
		_view.reveal(p)
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
		lines.append(I18n.t("папка · детей %d") % k.size())
		lines.append(I18n.t("сыновей %d, дочерей %d") % [sons, k.size() - sons])
		lines.append(I18n.t("всего потомков-файлов: %d") % p.total_files())
	else:
		lines.append("%s · %s" % [I18n.t(FakeTree.TYPE_NAMES[p.type]), FakeTree.format_size(p.size)])
	var par = parent_of(p)
	if par != null:
		lines.append(I18n.t("братьев и сестёр: %d") % (kids(par).size() - 1))
	var chain := [p]
	while parent_of(chain[0]) != null:
		chain.push_front(parent_of(chain[0]))
	lines.append(I18n.t("род: ") + " › ".join(chain.map(func(x): return x.name)))
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
		_found_label.text = I18n.t("нет")
		return
	_found_i = (_found_i + 1) % _found.size()
	_found_label.text = I18n.t("%d из %d") % [_found_i + 1, _found.size()]
	_go(_found[_found_i])
	_search.grab_focus()  # Enter ещё раз — следующий


## Сама родословная: раскладка и рисование. Мир: родоначальник наверху в (x, 0), поколения вниз (y > 0).
class TreeView extends Control:
	const COL := 196.0        # ширина места под одну карточку
	const ROW := 150.0        # шаг поколений
	const CW := 176.0         # карточка папки
	const CH := 64.0
	const FW := 150.0         # карточка файла (в столбике под домом)
	const FH := 38.0
	const FSTEP := 46.0       # шаг файлов в столбике
	const STACK := 6          # сколько файлов видно в столбике, пока его не развернули
	const MIN_ZOOM := 0.03
	const LINE := Color(0.62, 0.48, 0.3)
	const GOLD := Color(1.0, 0.85, 0.4)
	const CARD := Color(0.17, 0.13, 0.09)
	const CARD_FILE := Color(0.12, 0.11, 0.1)
	const MALE := Color(0.45, 0.62, 0.85)
	const FEMALE := Color(0.88, 0.55, 0.68)

	var owner_tree: FamilyTree
	var root                  # папка — корень показанного дерева
	var selected = null
	var hovered = null
	var nodes := {}           # человек -> {pos (середина верха карточки), parent, folder, rect, stack}
	var order: Array = []     # все показанные люди
	var toggles := {}         # папка -> центр кнопки «−/+» (мир)
	var more := {}            # папка -> Rect2 карточки «ещё N…» под столбиком
	var collapsed := {}       # папки со свёрнутыми детьми
	var opened := {}          # папки, у которых в столбике показаны все файлы
	var rows := 1             # поколений на экране
	var zoom := 1.0
	var offset := Vector2.ZERO  # где на экране точка (0, 0) мира
	var _w := {}              # ширина поддерева в колонках
	var _drag := false
	var _moved := 0.0
	var _tw: Tween
	var _font := ThemeDB.fallback_font
	var _box := StyleBoxFlat.new()
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

	## Разложить родословную папки f: дети ровно под родителем, у каждого поддерева своя полоса колонок.
	func build(f) -> void:
		root = f
		nodes.clear()
		order.clear()
		toggles.clear()
		more.clear()
		_w.clear()
		rows = 1
		_width(f)
		_place(f, null, 0.0, 0)
		queue_redraw()

	func _width(f) -> float:
		var w := 0.0
		if not collapsed.has(f):
			for c in f.children:
				w += _width(c)
			if not f.children.is_empty() and not f.files.is_empty():
				w += 1.0  # своя колонка под столбик файлов
		w = maxf(w, 1.0)
		_w[f] = w
		return w

	func _place(f, par, x0: float, depth: int) -> void:
		var y := depth * ROW
		rows = maxi(rows, depth + 1)
		var w: float = _w[f]
		var cx := x0 + w * COL / 2.0
		var open := not collapsed.has(f)
		var stack_x := cx  # середина колонки столбика файлов
		if open and not f.children.is_empty():
			var x := x0
			for c in f.children:
				_place(c, f, x, depth + 1)
				x += _w[c] * COL
			var lo: float = nodes[f.children[0]].pos.x
			var hi: float = nodes[f.children[-1]].pos.x
			if not f.files.is_empty():
				stack_x = x0 + (w - 0.5) * COL
				hi = stack_x
			cx = (lo + hi) / 2.0  # родитель — над серединой своих детей
		nodes[f] = {"pos": Vector2(cx, y), "parent": par, "folder": true,
			"rect": Rect2(cx - CW / 2.0, y, CW, CH)}
		order.append(f)
		if not kids(f).is_empty():
			toggles[f] = Vector2(cx, y + CH)
		if open and not f.files.is_empty():
			_place_stack(f, stack_x, y + CH + 22.0 if f.children.is_empty() else y + ROW)

	## Файлы — столбиком под домом, слева общая «нить».
	func _place_stack(f, sx: float, top: float) -> void:
		var spine := sx - CW / 2.0 + 12.0
		var left := sx - CW / 2.0 + 26.0
		var k: int = f.files.size()
		var n := k if opened.has(f) or k <= STACK + 1 else STACK
		var last := top
		for i in n:
			var file = f.files[i]
			var py := top + i * FSTEP
			nodes[file] = {"pos": Vector2(left + FW / 2.0, py), "parent": f, "folder": false,
				"rect": Rect2(left, py, FW, FH)}
			order.append(file)
			last = py + FH / 2.0
		if n < k:
			more[f] = Rect2(left, top + n * FSTEP, FW, FH * 0.8)
			last = top + n * FSTEP + FH * 0.4
		nodes[f].stack = [spine, top, last]

	static func kids(f) -> Array:
		return f.children + f.files

	## Раскрыть свёрнутые ветки до человека p (внутри показанного корня). false — он не из этой ветки.
	func reveal(p) -> bool:
		var chain := []
		var q = p
		while q != null and q != root:
			q = owner_tree.parent_of(q)
			if q != null:
				chain.append(q)
		if q != root:
			return false
		for a in chain:
			collapsed.erase(a)
		if not (p is FakeTree.Folder):
			var f = owner_tree.parent_of(p)
			if f.files.find(p) >= STACK:
				opened[f] = true
		build(root)
		return nodes.has(p)

	## Свернуть все ветки, кроме пути от корня до p (сам p раскрыт); p = null — видно только первое поколение.
	func focus_on(p) -> void:
		collapsed.clear()
		_fold(root)
		collapsed.erase(root)
		var q = p
		while q != null:
			collapsed.erase(q)
			q = owner_tree.parent_of(q)

	func _fold(f) -> void:
		if not f.children.is_empty() or not f.files.is_empty():
			collapsed[f] = true
		for c in f.children:
			_fold(c)

	## Свернуть всё / развернуть всё.
	func fold_all(fold := true) -> void:
		if fold:
			focus_on(null)
		else:
			collapsed.clear()
		build(root)
		if selected != null and not nodes.has(selected):
			selected = root
			owner_tree._update_card()
		owner_tree._sync_fold()
		fit()

	## Свернуть/развернуть ветку f (или весь столбик файлов), не сдвигая её на экране.
	func _toggle(f, stack := false) -> void:
		var before := to_screen(nodes[f].pos)
		if stack:
			opened[f] = true
		elif collapsed.has(f):
			collapsed.erase(f)
		else:
			collapsed[f] = true
		build(root)
		offset += before - to_screen(nodes[f].pos)
		_frame = null
		if selected != null and not nodes.has(selected):
			selected = f
			owner_tree._update_card()
		owner_tree._sync_fold()
		queue_redraw()

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
		var r: Rect2 = nodes[root].rect
		for p in nodes:
			r = r.merge(nodes[p].rect)
		for f in more:
			r = r.merge(more[f])
		r = r.grow(40)
		var z := clampf(minf(size.x / r.size.x, size.y / r.size.y), MIN_ZOOM, 1.4)
		_animate(z, size / 2 - r.get_center() * z, instant)

	## Лететь к человеку: он по центру, крупно.
	func fly_to(p, instant := false) -> void:
		if not nodes.has(p):
			return
		_frame = p
		var z := maxf(zoom, 1.0)
		_animate(z, size / 2 - nodes[p].rect.get_center() * z, instant)

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

	## Что под точкой экрана: человек, {toggle: папка}, {more: папка} или null.
	func _pick(s: Vector2):
		var w := to_world(s)
		var hit := maxf(12.0, 8.0 / zoom)
		for f in toggles:
			if w.distance_to(toggles[f]) < hit and zoom > 0.25:
				return {"toggle": f}
		for f in more:
			if more[f].has_point(w):
				return {"more": f}
		for p in nodes:
			if nodes[p].rect.has_point(w):
				return p
		return null

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if e.pressed:
					var k := 1.15 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
					var nz := clampf(zoom * k, MIN_ZOOM, 3.0)
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
						if p != null and not (p is Dictionary):
							zoom = maxf(zoom, 1.0)
							owner_tree._go(p)
				else:
					_drag = false
					if _moved < 6.0:
						var p = _pick(e.position)
						if p is Dictionary:
							if p.has("toggle"):
								_toggle(p.toggle)
							else:
								_toggle(p.more, true)
						elif p != null and zoom < 0.6:
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
				if h is Dictionary:
					h = null
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
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.09))
		if nodes.is_empty():
			return
		var view := Rect2(to_world(Vector2.ZERO), size / zoom).grow(40)
		_draw_rows()
		var gold := _gold_path()
		# линии родства: от родителя вниз, по общей перекладине, к ребёнку
		for p in order:
			var n: Dictionary = nodes[p]
			if n.folder and n.parent != null:
				_elbow(nodes[n.parent], n, gold.has(p), view)
		for p in order:
			if nodes[p].has("stack"):
				_stack(p, gold, view)
		for p in order:
			if view.intersects(nodes[p].rect):
				_card(p, gold.has(p))
		for f in more:
			if view.intersects(more[f]):
				_more(f)
		for f in toggles:
			if view.has_point(toggles[f]):
				_toggle_btn(f)

	## Полосы поколений с подписью слева.
	func _draw_rows() -> void:
		for d in rows:
			var top := to_screen(Vector2(0, d * ROW - 18.0)).y
			var bottom := to_screen(Vector2(0, d * ROW + CH + 18.0)).y
			if bottom < 0 or top > size.y:
				continue
			draw_rect(Rect2(0, top, size.x, bottom - top), Color(1, 1, 1, 0.025 if d % 2 == 0 else 0.045))
			if bottom - top > 14:
				var label := I18n.t("Поколение %d") % (d + 1)
				draw_string(_font, Vector2(8, (top + bottom) / 2 + 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.3))

	## Путь от корня до выбранного — светится золотом.
	func _gold_path() -> Dictionary:
		var out := {}
		var p = selected
		while p != null and nodes.has(p):
			out[p] = true
			p = nodes[p].parent
		return out

	func _lw() -> float:
		return maxf(1.5, 2.5 * zoom)

	func _elbow(a: Dictionary, b: Dictionary, lit: bool, view: Rect2) -> void:
		var top: Vector2 = a.pos + Vector2(0, CH)
		var end: Vector2 = b.pos
		var mid := (top.y + end.y) / 2.0
		if not view.intersects(Rect2(top, Vector2.ZERO).expand(end).grow(4)):
			return
		var pts := PackedVector2Array([to_screen(top), to_screen(Vector2(top.x, mid)), to_screen(Vector2(end.x, mid)), to_screen(end)])
		draw_polyline(pts, LINE, _lw())
		if lit:
			draw_polyline(pts, GOLD, _lw() + 1.5)

	## Столбик файлов: вертикальная нить и отводы к каждой карточке.
	func _stack(f, gold: Dictionary, view: Rect2) -> void:
		var n: Dictionary = nodes[f]
		var sx: float = n.stack[0]
		var top: float = n.stack[1]
		var last: float = n.stack[2]
		var start: float = n.pos.y + CH
		var from := Vector2(sx, start)
		if not f.children.is_empty():
			# у папки с подпапками столбик в своей колонке — нить с общей перекладины
			var mid := start + (ROW - CH) / 2.0
			draw_polyline(PackedVector2Array([to_screen(Vector2(n.pos.x, start)), to_screen(Vector2(n.pos.x, mid)),
				to_screen(Vector2(sx, mid))]), LINE, _lw())
			from = Vector2(sx, mid)
		if not view.intersects(Rect2(from, Vector2.ZERO).expand(Vector2(sx + 20, last))):
			return
		draw_line(to_screen(from), to_screen(Vector2(sx, last)), LINE, _lw())
		var lit_y := -1.0
		for x in f.files:
			if not nodes.has(x):
				break
			var r: Rect2 = nodes[x].rect
			var y := r.position.y + FH / 2.0
			draw_line(to_screen(Vector2(sx, y)), to_screen(Vector2(r.position.x, y)), LINE, _lw())
			if gold.has(x):
				lit_y = y
				draw_line(to_screen(Vector2(sx, y)), to_screen(Vector2(r.position.x, y)), GOLD, _lw() + 1.5)
		if more.has(f):
			var y: float = more[f].position.y + more[f].size.y / 2.0
			draw_line(to_screen(Vector2(sx, y)), to_screen(Vector2(more[f].position.x, y)), LINE, _lw())
		if lit_y > 0.0:
			draw_line(to_screen(from), to_screen(Vector2(sx, lit_y)), GOLD, _lw() + 1.5)

	func _rounded(r: Rect2, fill: Color, border: Color, bw: float, radius: float) -> void:
		_box.bg_color = fill
		_box.border_color = border
		_box.set_border_width_all(int(maxf(1.0, bw)))
		_box.set_corner_radius_all(int(maxf(0.0, radius)))
		draw_style_box(_box, r)

	## Карточка: портрет, имя, кто он. Рамка — цвет пола, у выбранного и его предков — золото.
	func _card(p, lit: bool) -> void:
		var n: Dictionary = nodes[p]
		var r := Rect2(to_screen(n.rect.position), n.rect.size * zoom)
		var sel: bool = p == selected
		var accent: Color = GOLD if p == root else (FEMALE if FamilyTree.female(p) else MALE)
		var border := GOLD if sel or lit else accent.darkened(0.35)
		var fill: Color = CARD if n.folder else CARD_FILE
		if r.size.y < 7.0:  # совсем издалека — просто плашка
			draw_rect(r, border if sel or lit else (accent.darkened(0.5) if n.folder else WorldMap.TYPE_COLORS[p.type].darkened(0.3)))
			return
		if sel:
			_rounded(r.grow(6.0 * zoom), Color(GOLD, 0.25), Color(GOLD, 0.0), 0.0, 12.0 * zoom)
		_rounded(r, fill, border, (3.0 if sel else 2.0) * zoom, 8.0 * zoom)
		var h := r.size.y
		var pc := Vector2(r.position.x + h * 0.5, r.position.y + h * 0.5)  # портрет слева
		var pr := h * 0.36
		if not n.folder:
			draw_rect(Rect2(r.position + Vector2(2, 2) * zoom, Vector2(5.0 * zoom, h - 4.0 * zoom)), WorldMap.TYPE_COLORS[p.type])
			pc.x += 4.0 * zoom
		draw_circle(pc, pr + 2.0 * zoom, accent.darkened(0.2))
		draw_circle(pc, pr, Color(0.08, 0.07, 0.06))
		if pr > 5.0:
			Pawn.draw(self, pc + Vector2(0, pr * 0.15), pr * 1.45, owner_tree.look_of(p), Residents.Facing.DOWN, 0.0, false, pr > 14.0)
		var tx := pc.x + pr + 8.0 * zoom
		var tw := r.end.x - tx - 6.0 * zoom
		var sub := ""
		if p == root:
			sub = I18n.t("родоначальник")
		elif n.folder:
			sub = I18n.t("%s · детей %d") % [FamilyTree.word("parent", p), kids(p).size()]
		else:
			sub = "%s · %s" % [FamilyTree.word("kid", p), FakeTree.format_size(p.size)]
		var big := 15.0 if n.folder else 12.0
		_text(Vector2(tx, r.position.y + h * 0.46), p.name, int(big * zoom), Color(1.0, 0.95, 0.85), tw)
		_text(Vector2(tx, r.position.y + h * 0.8), sub, int(big * 0.75 * zoom), Color(accent, 0.85), tw)

	## «ещё N…» под длинным столбиком — клик раскрывает весь.
	func _more(f) -> void:
		var r := Rect2(to_screen(more[f].position), more[f].size * zoom)
		_rounded(r, Color(0.1, 0.1, 0.1, 0.8), LINE.darkened(0.3), zoom, 6.0 * zoom)
		var t := I18n.t("ещё %d…") % (f.files.size() - STACK)
		_text(r.get_center() + Vector2(0, 4.0 * zoom), t, int(12 * zoom), Color(1, 1, 1, 0.7), r.size.x, true)

	## Кнопка «−» под раскрытой папкой, «+N» под свёрнутой.
	func _toggle_btn(f) -> void:
		var c := to_screen(toggles[f])
		var rad := 9.0 * zoom
		if rad < 3.0:
			return
		var shut := collapsed.has(f)
		var t := "+%d" % kids(f).size() if shut else "−"
		var fs := int(12 * zoom)
		var w := maxf(rad * 2.0, _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0 * zoom)
		var r := Rect2(c - Vector2(w / 2.0, rad), Vector2(w, rad * 2.0))
		_rounded(r, Color(0.3, 0.22, 0.12) if shut else CARD, GOLD if shut else LINE, 1.5 * zoom, rad)
		_text(c + Vector2(0, fs * 0.36), t, fs, Color.WHITE, w, true)

	## Текст в ширину maxw (длинное — с «…»); fs < 6 — не рисуем.
	func _text(at: Vector2, text: String, fs: int, col: Color, maxw: float, center := false) -> void:
		if fs < 6:
			return
		var t := text
		if _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > maxw:
			while t.length() > 1 and _font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > maxw:
				t = t.left(-1)
			t += "…"
		var x := at.x
		if center:
			x -= _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x / 2.0
		draw_string(_font, Vector2(x, at.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
