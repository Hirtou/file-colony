extends Node2D
## Карта города (папки верхнего уровня диска) сверху: город с районами и окрестностями, выбор объектов, интерфейс.
## Карта строится один раз и запоминается (Game) — вернёшься в город, он такой же.

signal exit_requested
signal built  # мир построен

const FLY_TIME := 0.8
const DAY_LEN := 360.0          # секунд на сутки при скорости ×1
const SPEEDS := [1, 10, 60]     # кнопка скорости времени

@onready var map: WorldMap = $Map
@onready var cam: Camera2D = $Camera
@onready var ui = $UI

var disk_name := "C:"
var disk_gb := 256.0
var site := {}        # город на планете (CitySites): {folder, env, ...}; пусто — первый город диска
var root
var city              # папка города
var path: Array = []  # [root, папка, ...] — текущий уровень
var _tw: Tween
var _info_t := 0.0
var _follow := false  # камера следует за выбранным жителем
var is_built := false
var hour := 9.0       # время суток, часы
var day := 1
var _speed_i := 0
var paused := false   # время стоит (P / пробел): жители замирают, часы не идут
var _index: Array = []  # всё, что можно найти поиском
var _found: Array = []  # найденное сейчас
var _files_of = null    # дом (Folder), чей список файлов открыт в панели
var _menu_for := {}     # на чём открыто меню правой кнопки

func _ready() -> void:
	cam.make_current()
	cam.speed = Game.settings.cam_speed
	_speed_i = Game.settings.time_speed
	ui.set_planet(I18n.t("Планета %s · %s") % [disk_name, Planet.format_size(disk_gb)])
	ui.back_pressed.connect(exit_requested.emit)
	ui.crumb_pressed.connect(_on_crumb)
	ui.search_changed.connect(_on_search)
	ui.result_chosen.connect(_on_result)
	ui.file_chosen.connect(func(i): if _files_of: _focus_file(map.by_folder[_files_of], i))
	ui.menu_chosen.connect(_on_menu)
	ui.tree_pressed.connect(_open_tree)
	ui.type_chosen.connect(_on_type)
	ui.arrow.pressed.connect(_fly_to_selected)
	ui.tree.show_on_map.connect(_tree_to_map)
	ui.stats_pressed.connect(_open_stats)
	ui.stats.show_on_map.connect(_stats_to_map)
	ui.speed_pressed.connect(func():
		if paused:
			paused = false  # с паузы кнопка просто снимает паузу
		else:
			_speed_i = (_speed_i + 1) % SPEEDS.size())
	root = Game.disk_root(disk_name)
	if site.is_empty():
		site = Game.city_sites(disk_name)[0]
	city = site.folder
	# постройка города занимает пару секунд — сначала показываем надпись
	ui.show_loading(I18n.t("Строим город «%s»…") % city.name)
	await get_tree().process_frame
	await get_tree().process_frame
	var seed_value := Game.tree_seed(disk_name)
	var key := "%s/%s" % [disk_name, city.name]
	var cached := Game.cached_world(key)  # второй вход — без перестройки, город тот же
	map.setup(root, seed_value, cached.get("world", {}), city, site.get("env", {}))
	map.file_deleted.connect(_on_file_deleted)
	map.files_changed.connect(_refresh)
	cam.bounds = map.land_rect  # камера не улетает с карты
	ui.set_clipboard(Game.clipboard, Game.clip_cut)
	if cached.is_empty():
		Game.cache_world(key, {"world": map.world})
	map.shadows_enabled = Game.settings.shadows
	_build_index()
	ui.set_cities(map.items.filter(func(it): return it.depth == 1).map(func(it): return it.folder.name))
	go_to([root, city], true)
	ui.minimap.tex = ImageTexture.create_from_image(map.minimap_image())
	ui.minimap.area = map.map_rect()
	ui.minimap.visible = true
	ui.minimap.jump.connect(func(p: Vector2):
		if _tw:
			_tw.kill()
		_follow = false
		cam.position = p)
	ui.show_loading("")
	is_built = true
	built.emit()

func _exit_tree() -> void:
	Game.set_rain(0.0)  # ушли из города — дождя не слышно

## Перейти на уровень: раскрыть города на пути, остальное затемнить, камера летит туда (если fly).
func go_to(new_path: Array, instant := false, fly := true) -> void:
	path = new_path
	map.expanded.clear()
	map.focus = null
	for f in path:
		if f != root and f.is_city():
			map.expanded[f] = true
			map.focus = f
	var names := [I18n.t("Космос")]
	for f in path:
		names.append(f.name)
	ui.set_path(names)
	if fly:
		_fly(path[-1], instant)

func _fly(f, instant: bool) -> void:
	var vp := get_viewport_rect().size
	var pos := Vector2.ZERO
	var z: float
	if f == root:
		z = minf(vp.x, vp.y) / (map.world.radius * 2.6)
	else:
		var it: Dictionary = map.by_folder[f]
		var fr := WorldMap.frame(it)
		var k := 0.85 if it.kind == "city" else 0.55
		if it.kind == "house":
			# дом и все его жители, где бы они сейчас ни гуляли
			for p in map.member_positions(it):
				fr = fr.expand(p)
			fr = fr.grow(WorldLayout.TILE * 2)
			k = 0.85
		pos = fr.get_center()
		z = minf(vp.x * k / fr.size.x, vp.y * k / fr.size.y)
	_fly_to(pos, z, instant)

func _fly_to(pos: Vector2, z: float, instant := false) -> void:
	z = minf(z, cam.max_zoom)
	if _tw:
		_tw.kill()
	if instant:
		cam.position = pos
		cam.zoom = Vector2(z, z)
		return
	_tw = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_property(cam, "position", pos, FLY_TIME)
	_tw.tween_property(cam, "zoom", Vector2(z, z), FLY_TIME)

func _on_crumb(i: int) -> void:
	if i <= 1:
		exit_requested.emit()  # «Космос» или диск — назад на планету, выбирать город
	else:
		go_to(path.slice(0, i))

func _unhandled_input(event: InputEvent) -> void:
	if not is_built:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F and event.ctrl_pressed:
		get_viewport().set_input_as_handled()
		ui.focus_search()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		get_viewport().set_input_as_handled()
		ui.help.visible = not ui.help.visible
		return
	if ui.help.visible:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			ui.help.hide()
		return
	if ui.stats.visible:
		# открыта статистика: Esc или I — закрыть
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_I):
			get_viewport().set_input_as_handled()
			ui.stats.hide()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I and not ui.search_focused() and not ui.tree.visible:
		_open_stats()
		return
	if ui.tree.visible:
		# открыто семейное древо: Esc или T — закрыть, карту не трогаем
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_T and not ui.tree.typing()):
			get_viewport().set_input_as_handled()
			ui.tree.hide()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T and not ui.search_focused():
		_open_tree()
		return
	if event is InputEventKey and event.pressed and not ui.search_focused():
		# горячие клавиши для выбранного: Ctrl+C, Ctrl+V, Delete
		if event.keycode == KEY_C and event.ctrl_pressed and map.selected.get("type") == "file":
			_copy(map.selected.item, map.selected.index)
		elif event.keycode == KEY_X and event.ctrl_pressed and map.selected.get("type") == "file":
			_cut(map.selected.item, map.selected.index)
		elif event.keycode == KEY_V and event.ctrl_pressed and not map.selected.is_empty():
			_paste(map.selected.item)
		elif event.keycode == KEY_DELETE and map.selected.get("type") == "file":
			_delete(map.selected.item, map.selected.index)
		elif event.keycode == KEY_L and not event.echo and not event.ctrl_pressed:
			ui.toggle_legend()
		elif (event.keycode == KEY_P or event.keycode == KEY_SPACE) and not event.echo:
			get_viewport().set_input_as_handled()
			paused = not paused
			ui.toast(I18n.t("Пауза") if paused else I18n.t("Время идёт"))
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if ui.search_focused():
			ui.clear_search()  # Esc в поиске — закрыть поиск, а не уйти в космос
		else:
			exit_requested.emit()
		return
	if event is InputEventMouseMotion:
		var h := map.pick(map.get_global_mouse_position())
		if h.get("type") == "file":
			var f = h.item.folder.files[h.index]
			ui.show_tip("%s · %s\n%s" % [f.name, FakeTree.format_size(f.size), map.file_where(h.item, h.index)], event.position)
		else:
			ui.hide_tip()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		ui.release_search()
		var h := map.pick(map.get_global_mouse_position())
		select(h)
		if h.get("type") == "folder" and h.item.kind != "hut":
			go_to(h.item.path)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		ui.release_search()
		_menu_for = map.pick(map.get_global_mouse_position())
		_open_menu(event.position)

# --- правая кнопка: копировать, вставить, удалить ---

enum M { COPY, PASTE, DELETE, OPEN, FAMILY, CUT }

## Меню для того, что под мышью (_menu_for).
func _open_menu(at: Vector2) -> void:
	var h := _menu_for
	var clip = Game.clipboard
	var entries := []
	if h.get("type") == "file":
		select(h)
		var f = h.item.folder.files[h.index]
		entries.append([f.name, -1])
		entries.append(["Копировать", M.COPY])
		entries.append(["Вырезать (переселить)", M.CUT])
		if clip != null:
			entries.append([I18n.t("Переселить «%s» в этот дом" if Game.clip_cut else "Вставить «%s» в этот дом") % clip.name, M.PASTE])
		entries.append(["Семейное древо", M.FAMILY])
		if not map.is_hunted(h.item, h.index):
			entries.append(["Удалить", M.DELETE])
	elif h.get("type") == "folder":
		entries.append([h.item.folder.name, -1])
		if h.item.kind == "house":
			entries.append([I18n.t("Переселить «%s» сюда" if Game.clip_cut else "Вставить «%s» сюда") % clip.name if clip != null else "Вставить (буфер пуст)", M.PASTE])
		if h.item.kind == "city":
			entries.append(["Открыть", M.OPEN])
		entries.append(["Семейное древо", M.FAMILY])
	if entries.size() > 1:
		ui.show_menu(entries, at)

func _on_menu(id: int) -> void:
	var h := _menu_for
	if h.is_empty():
		return
	match id:
		M.COPY:
			_copy(h.item, h.index)
		M.CUT:
			_cut(h.item, h.index)
		M.PASTE:
			_paste(h.item)
		M.DELETE:
			_delete(h.item, h.index)
		M.OPEN:
			select(h)
			go_to(h.item.path)
		M.FAMILY:
			_open_tree(h.item.folder.files[h.index] if h.type == "file" else h.item.folder)

## Клик по типу в легенде: метки над домами с такими файлами; повторный клик — снять.
func _on_type(t: int) -> void:
	if map.type_filter == t:
		t = -1
	var n := map.set_type_filter(t)
	ui.mark_type(t)
	if t < 0:
		ui.toast("Подсветка типов выключена")
	elif n.x == 0:
		ui.toast(I18n.t("Файлов типа «%s» на этой планете нет") % I18n.t(FakeTree.TYPE_NAMES[t]), Color(1.0, 0.8, 0.5))
	else:
		ui.toast(I18n.t("«%s»: %d файлов в %d домах — ищи метки на карте") % [I18n.t(FakeTree.TYPE_NAMES[t]), n.x, n.y],
			WorldMap.TYPE_COLORS[t].lightened(0.3))

## Семейное древо выбранного (файл, папка) или текущего уровня.
func _open_tree(person = null) -> void:
	if person == null:
		var h := map.selected
		if h.get("type") == "file":
			person = h.item.folder.files[h.index]
		elif h.get("type") == "folder":
			person = h.item.folder
		else:
			person = path[-1]
	ui.hide_tip()
	ui.tree.open(root, person)

## Статистика открытого города: все его дома (вместе с районами).
func _open_stats() -> void:
	ui.hide_tip()
	var houses := []
	for it in map.items:
		if it.kind == "house":
			houses.append(it.folder)
	ui.stats.open(city.name, houses)

## Из статистики — к дому или к жителю на карте.
func _stats_to_map(house, file) -> void:
	var it: Dictionary = map.by_folder.get(house, {})
	if it.is_empty():
		return
	go_to(it.path, false, file == null)
	if file != null:
		_focus_file(it, house.files.find(file))
	else:
		select({"type": "folder", "item": it})

## Из древа — к человеку на карте: файл — к жителю, папка — к её дому или городу.
func _tree_to_map(p) -> void:
	ui.tree.hide()
	if not FamilyTree.is_folder(p):
		var house = ui.tree.parent_of(p)
		var it: Dictionary = map.by_folder.get(house, {})
		if not it.is_empty():
			go_to(it.path, false, false)
			_focus_file(it, house.files.find(p))
		else:
			_other_city(p)
		return
	if p == root:
		go_to([root, city])
		return
	if not map.by_folder.has(p):
		_other_city(p)
		return
	var it: Dictionary = map.by_folder[p]
	go_to(it.path if it.kind == "city" else it.path.slice(0, it.path.size() - 1))
	select({"type": "folder", "item": it})

## Человек из другого города: на этой карте его нет — подсказать, где он живёт.
func _other_city(p) -> void:
	var top = p
	while ui.tree.parent_of(top) != null and ui.tree.parent_of(top) != root:
		top = ui.tree.parent_of(top)
	ui.toast(I18n.t("«%s» живёт в другом городе — «%s». Вернись на планету и выбери его.") % [p.name, top.name], Color(1.0, 0.8, 0.5))

## Скопировать файл: его модель (житель) теперь лежит в буфере слева внизу.
func _copy(item: Dictionary, index: int) -> void:
	var f = item.folder.files[index]
	Game.clipboard = f.copy_as(f.name)
	Game.clip_cut = false
	ui.set_clipboard(Game.clipboard)
	Game.sfx("copy")
	ui.toast(I18n.t("Скопировано: %s") % f.name, Color(0.7, 1.0, 0.7))

## Вырезать: в буфере сам файл; «Вставить» в другой дом — он туда переедет.
func _cut(item: Dictionary, index: int) -> void:
	var f = item.folder.files[index]
	Game.clipboard = f
	Game.clip_cut = true
	ui.set_clipboard(f, true)
	Game.sfx("copy")
	ui.toast(I18n.t("Вырезано: %s — выбери дом и вставь (Ctrl+V)") % f.name, Color(1.0, 0.85, 0.5))

## Дом, где сейчас живёт файл (на этой планете); {} — не нашёлся.
func _house_of(file) -> Dictionary:
	for it in map.items:
		if it.kind == "house" and it.folder.files.has(file):
			return it
	return {}

## Вставить файл из буфера в дом (только дом: у хижин и городов своих жителей нет).
func _paste(item: Dictionary) -> void:
	if Game.clipboard == null:
		ui.toast("Буфер пуст — сначала скопируйте файл", Color(1.0, 0.8, 0.5))
		return
	if item.kind != "house":
		ui.toast("Вставлять можно только в дом", Color(1.0, 0.8, 0.5))
		return
	if Game.clip_cut:
		var src := _house_of(Game.clipboard)
		if src.is_empty():
			ui.toast("Переселять можно только в пределах одного города", Color(1.0, 0.8, 0.5))
			return
		if src == item:
			ui.toast("Он и так живёт в этом доме", Color(1.0, 0.8, 0.5))
			return
		var moved := map.move_file(src, Game.clipboard, item)
		if moved == "":
			ui.toast("Нельзя: за ним уже пришли киллеры", Color(1.0, 0.55, 0.45))
			return
		Game.clipboard = null
		Game.clip_cut = false
		ui.set_clipboard(null)
		Game.sfx("paste")
		ui.toast(I18n.t("«%s» переезжает в «%s»") % [moved, item.folder.name], Color(0.7, 0.9, 1.0))
		return
	var f = map.paste(item, Game.clipboard)
	Game.sfx("paste")
	ui.toast(I18n.t("Вставлено в «%s»: %s") % [item.folder.name, f.name], Color(0.7, 0.9, 1.0))
	_refresh(item)

## Удалить файл: за жителем приходят киллеры с мушкетами (сам файл удалится после выстрела).
func _delete(item: Dictionary, index: int) -> void:
	var f = item.folder.files[index]
	if Game.clip_cut and Game.clipboard == f:
		Game.clipboard = null  # вырезанный файл удаляют — в буфере его больше нет
		Game.clip_cut = false
		ui.set_clipboard(null)
	if map.hunt(item, index):
		ui.toast(I18n.t("За «%s» выехали киллеры…") % f.name, Color(1.0, 0.55, 0.45))
	elif not map.is_hunted(item, index):
		map.remove_file(item, f)  # житель не нарисован (за «+N») — удаляем сразу
		ui.toast(I18n.t("Удалено: %s") % f.name, Color(1.0, 0.55, 0.45))

func _on_file_deleted(item: Dictionary) -> void:
	ui.toast("Файл удалён", Color(1.0, 0.55, 0.45))
	_refresh(item)

## Файлы дома поменялись: поиск, список в панели, выбор.
func _refresh(item: Dictionary) -> void:
	_build_index()
	if _files_of == item.folder or (not map.selected.is_empty() and map.selected.item == item):
		_files_of = null
		select({"type": "folder", "item": item})

## Выбрать объект ({} — снять выбор) и показать о нём информацию.
func select(h: Dictionary) -> void:
	map.selected = h
	_follow = false
	if h.is_empty():
		_files_of = null
		ui.show_info([])
		return
	# дом или его житель — в панели список файлов дома (пока выбран этот же дом, список не перестраивается)
	var house: Dictionary = h.item if h.item.kind == "house" else {}
	if house.is_empty():
		_files_of = null
		ui.show_files([])
	elif _files_of != house.folder:
		_files_of = house.folder
		var rows := []
		for f in house.folder.files:
			rows.append([f.name, FakeTree.format_size(f.size), WorldMap.TYPE_COLORS[f.type]])
		ui.show_files(rows)
	ui.mark_file(h.index if h.type == "file" else -1)
	_show_info()

## Панель информации о выбранном (обновляется на ходу: жители гуляют).
func _show_info() -> void:
	var h := map.selected
	if h.is_empty():
		return
	var it: Dictionary = h.item
	if h.type == "file":
		var f = it.folder.files[h.index]
		ui.show_info([["Имя", f.name], ["Тип", I18n.t("файл (%s)") % I18n.t(FakeTree.TYPE_NAMES[f.type])],
			["Файлов", "1"], ["Размер", FakeTree.format_size(f.size)], ["Глубина", str(it.depth + 1)],
			["Дом", it.folder.name], ["Семья", I18n.t("%s «%s»") % [FamilyTree.word("kid", f), it.folder.name]],
			["Сейчас", map.file_where(it, h.index)]])
		return
	var kinds := {"city": "город", "house": "дом", "hut": "хижина (пустая папка)"}
	var rows := [["Имя", it.folder.name], ["Тип", I18n.t(kinds[it.kind])], ["Файлов", str(it.folder.total_files())],
		["Размер", FakeTree.format_size(it.folder.total_size())], ["Глубина", str(it.depth)]]
	rows.append(["Семья", I18n.t("%s «%s», детей %d") % [FamilyTree.word("kid", it.folder), it.parent.name,
		FamilyTree.kids(it.folder).size()]])
	if it.kind == "house":
		var o := map.house_out(it)
		rows.append(["На улице", I18n.t("%d из %d") % [o.x, o.y]])
	ui.show_info(rows)

func _process(delta: float) -> void:
	if not is_built:
		return
	_tick_time(delta)
	_info_t += delta
	if _info_t > 0.5:
		_info_t = 0.0
		_show_info()
	_update_arrow()
	ui.minimap.view = map.view_rect()
	ui.minimap.mark = _selected_pos() if not map.selected.is_empty() else Vector2.INF
	ui.minimap.night = map.night
	# камера идёт за найденным жителем, пока игрок сам не двинет её
	if _follow:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D):
			_follow = false
		elif not (_tw and _tw.is_running()) and map.selected.get("type") == "file":
			var p := map.resident_pos(map.selected.item, map.selected.index)
			if p.is_finite():
				cam.position = cam.position.lerp(p, 1.0 - exp(-4.0 * delta))

## Где выбранный (житель или дом) в мире; Vector2.INF — ничего не выбрано.
func _selected_pos() -> Vector2:
	var h := map.selected
	if h.is_empty():
		return Vector2.INF
	if h.type == "file":
		var p := map.resident_pos(h.item, h.index)
		return p if p.is_finite() else h.item.pos
	return h.item.pos

## Выбранный за краем экрана — стрелка к нему.
func _update_arrow() -> void:
	var p := _selected_pos()
	if not p.is_finite():
		ui.point_arrow(Vector2.INF, "")
		return
	var h := map.selected
	if h.type == "file" and h.index >= h.item.folder.files.size():
		return
	var text: String = h.item.folder.files[h.index].name if h.type == "file" else h.item.folder.name
	var ct := get_viewport().get_canvas_transform()
	if h.type == "folder" and (ct * (h.item.rect as Rect2)).intersects(get_viewport_rect()):
		ui.point_arrow(Vector2.INF, "")  # дом хоть краем виден — стрелка не нужна
		return
	ui.point_arrow(ct * p, text)

func _fly_to_selected() -> void:
	var p := _selected_pos()
	if p.is_finite():
		_fly_to(p, maxf(cam.zoom.x, get_viewport_rect().size.y / (WorldLayout.TILE * 12.0)))
		_follow = map.selected.get("type") == "file"

# --- день и ночь ---

func _tick_time(delta: float) -> void:
	var speed: int = 0 if paused else SPEEDS[_speed_i]
	if not Game.settings.day_night:
		hour = 12.0  # смена дня и ночи выключена в настройках
	else:
		hour += delta * 24.0 / DAY_LEN * speed
	if hour >= 24.0:
		hour -= 24.0
		day += 1
	map.time_scale = minf(speed, 10.0)  # жители на ×60 не носятся как угорелые
	var rain := rain_of(Game.tree_seed(disk_name) + city.name.hash(), day, hour) if Game.settings.weather else 0.0
	map.weather.amount = rain
	Game.set_rain(rain)
	map.set_daylight(night_of(hour), dusk_of(hour))
	Game.play_music("space" if night_of(hour) > 0.6 else "village")  # ночью — тихий эмбиент
	var sky := I18n.t(part_of_day(hour)) + (I18n.t(" · дождь") if rain > 0.3 else "")
	ui.set_clock(I18n.t("День %d · %02d:%02d · %s") % [day, int(hour), int(fmod(hour, 1.0) * 60.0), sky], speed)

## Сила дождя 0..1 в этот час этого дня: примерно каждый третий день идёт дождь на 2–5 часов,
## начинается и кончается плавно (за полчаса). Для города и дня всегда одинаково.
static func rain_of(seed_value: int, d: int, h: float) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + d
	if rng.randf() > 0.34:
		return 0.0
	var start := rng.randf_range(6.0, 19.0)
	var span := rng.randf_range(2.0, 5.0)
	var k := minf(h - start, start + span - h) / 0.5
	return clampf(k, 0.0, 1.0) * rng.randf_range(0.6, 1.0)

## 0 — день, 1 — ночь; плавно на рассвете (5–7) и в сумерках (18–21).
static func night_of(h: float) -> float:
	if h >= 21.0 or h < 5.0:
		return 1.0
	if h < 7.0:
		return 1.0 - (h - 5.0) / 2.0
	if h >= 18.0:
		return (h - 18.0) / 3.0
	return 0.0

## Тёплый оттенок около 19:00 (закат) и 6:00 (рассвет).
static func dusk_of(h: float) -> float:
	return maxf(0.0, 1.0 - absf(h - 19.0) / 1.5) + maxf(0.0, 1.0 - absf(h - 6.0) / 1.2)

static func part_of_day(h: float) -> String:
	if h >= 5.0 and h < 11.0:
		return "утро"
	if h >= 11.0 and h < 17.0:
		return "день"
	if h >= 17.0 and h < 21.0:
		return "вечер"
	return "ночь"

# --- поиск ---

## Все файлы и папки материка для поиска: {text, low, where, color, type, item, index}.
func _build_index() -> void:
	_index.clear()
	for it in map.items:
		var kinds := {"city": "город", "house": "дом", "hut": "хижина"}
		_index.append({"text": it.folder.name, "low": String(it.folder.name).to_lower(), "where": I18n.t(kinds[it.kind]),
			"color": Color(0.85, 0.7, 0.45), "type": "folder", "item": it, "index": 0})
		for i in it.folder.files.size():
			var f = it.folder.files[i]
			_index.append({"text": f.name, "low": String(f.name).to_lower(), "where": I18n.t("дом «%s»") % it.folder.name,
				"color": WorldMap.TYPE_COLORS[f.type], "type": "file", "item": it, "index": i})

## Поиск: текст (от 2 букв) и/или фильтры (тип, размер, город). Все найденные файлы светятся на карте.
func _on_search(text: String) -> void:
	_found.clear()
	var low := text.strip_edges().to_lower()
	var f: Dictionary = ui.filters()
	var by_file: bool = f.type >= 0 or f.size >= 0
	var active: bool = low.length() >= 2 or by_file or f.city >= 0
	if active:
		var city = map.items.filter(func(it): return it.depth == 1)[f.city].folder if f.city >= 0 else null
		var lim: Array = ContinentUI.SIZE_LIMITS[f.size] if f.size >= 0 else []
		for e in _index:
			if low.length() >= 2 and not e.low.contains(low):
				continue
			if city != null and not e.item.path.has(city):
				continue
			if by_file:
				if e.type != "file":
					continue
				var file = e.item.folder.files[e.index]
				if f.type >= 0 and file.type != f.type:
					continue
				if not lim.is_empty() and (file.size < lim[0] or file.size >= lim[1]):
					continue
			_found.append(e)
	var rows := []
	for e in _found.slice(0, 200):
		rows.append(["%s  ·  %s" % [e.text, e.where], e.color])
	ui.show_results(rows, _found.size() if active else -1)
	# подсветить найденные файлы на карте
	var files := []
	for e in _found:
		if e.type == "file":
			files.append(e.item.folder.files[e.index])
	if active or map.type_filter < 0:
		map.type_filter = -1  # поиск заменяет подсветку типа из легенды
		map.highlight(files, Color(1.0, 0.85, 0.3))
		ui.mark_type(-1)

## Выбрали найденное: папка — открыть её уровень; файл — лететь к жителю и идти за ним.
func _on_result(i: int) -> void:
	if i >= _found.size():
		return
	var e: Dictionary = _found[i]
	ui.clear_search()
	if e.type == "folder":
		select({"type": "folder", "item": e.item})
		if e.item.kind != "hut":
			go_to(e.item.path)
		return
	go_to(e.item.path, false, false)
	_focus_file(e.item, e.index)

## Выбрать файл дома item: лететь к его жителю и идти за ним.
func _focus_file(item: Dictionary, index: int) -> void:
	select({"type": "file", "item": item, "index": index})
	var p := map.resident_pos(item, index)
	if not p.is_finite():
		p = item.pos  # файл за «+N» — показываем его дом
	_fly_to(p, get_viewport_rect().size.y / (WorldLayout.TILE * 9.0))
	_follow = true

## Для скриншотов: map / city / house / pawns (жители крупно) без анимации.
func debug_view(view: String) -> void:
	if not is_built:
		await built
	var best = null
	for it in map.items:
		if view == "city" and it.kind == "city" and it.depth == 1 and (best == null or it.r > best.r):
			best = it
		elif view in ["house", "pawns", "closeup", "hunt", "chase", "move", "filter", "find"] and it.kind == "house" and (best == null or it.folder.file_count > best.folder.file_count):
			best = it
		elif view.begins_with("family") and it.kind == "house" and it.depth >= 3 and (best == null or it.folder.file_count > best.folder.file_count):
			best = it  # дом во вложенном районе: видны дедушка, отец, братья, дети
		elif view == "room" and it.kind == "house" and (best == null or absi(it.folder.file_count - 14) < absi(best.folder.file_count - 14)):
			best = it  # дом средних размеров — видно мебель
	if view == "night" or view == "dusk":
		hour = 23.0 if view == "night" else 19.2
		view = "city"
		for it in map.items:
			if it.kind == "city" and it.depth == 1 and (best == null or it.r > best.r):
				best = it
	if view == "stats":
		_open_stats()
		return
	if view == "help":
		ui.help.show()
		return
	if view == "rain":
		# день и час, когда льёт: камера на улицы с жителями
		for d in range(1, 60):
			for h in range(7, 20):
				if rain_of(Game.tree_seed(disk_name) + city.name.hash(), d, h) > 0.8:
					day = d
					hour = h
					view = "work"
					break
			if view == "work":
				break
	if view == "river":
		# река в городе: камера на воду внутри города (если река здесь течёт через город)
		var w: Dictionary = map.world
		var t: Rect2i = w.town
		for y in range(t.position.y, t.end.y):
			for x in range(t.position.x, t.end.x):
				if w.ground[y * w.n + x] == WorldLayout.G.WATER:
					cam.position = w.origin + (Vector2(x, y) + Vector2(4, 4)) * WorldLayout.TILE
					cam.zoom = Vector2.ONE * 0.9
					return
		return
	if view == "ducks":
		# утки на воде, круги от рыб; немного подождать, чтобы поплыли
		var wl = map._wild
		if not wl._ducks.is_empty():
			cam.position = wl._ducks[0].pos
			cam.zoom = Vector2.ONE * 2.2
			for i in 90:
				wl.update(1.0 / 30.0, map.view_rect())
		return
	if view == "work" or view == "fishing" or view == "field":
		# место работы крупно: мастерская / мостки / поле
		var key: String = {"work": "идёт в кузницу", "fishing": "идёт на рыбалку", "field": "идёт в поле"}[view]
		for wk in map.world.work:
			if String(wk.go).begins_with(key):
				cam.position = map.world.origin + (Vector2(wk.cells[0]) + Vector2(0.5, 0.5)) * WorldLayout.TILE
				cam.zoom = Vector2.ONE * 1.4
				for t in map._towns.values():
					for i in 600:
						t.step(0.1)  # жители успели разойтись по делам
				for i in 90:
					map._wild.update(1.0 / 30.0, map.view_rect())  # дым кузницы успел подняться
				return
		return
	if view == "search":
		# найти файл по части имени и долететь до жителя
		var q: String = map.items[0].folder.name
		for it in map.items:
			if it.kind == "house":
				q = String(it.folder.files[0].name).left(4)
				break
		_on_search(q)
		_on_result(0)
		ui._search.text = q
		_on_search(q)
		if _tw:
			_tw.custom_step(10.0)
		return
	if best == null:
		return
	if view == "family" or view == "family_all":
		go_to(best.path, true)
		_open_tree(best.folder)
		for i in 3:
			await get_tree().process_frame
		if view == "family_all":
			ui.tree._view.fit(true)  # всё дерево диска
		for t in get_tree().get_processed_tweens():
			t.custom_step(3.0)
		return
	go_to(best.path, true)
	select({"type": "folder", "item": best})
	if view == "pawns":
		cam.zoom *= 2.6
	elif view == "hunt":
		# удалить файл и прокрутить до выстрела: киллеры целятся, вспышка, дым
		for i in best.folder.files.size():
			if map.resident_id(best, i) >= 0:
				_copy(best, i)
				_delete(best, i)
				break
		var hu: Hunt = map._hunts.back()
		for i in 3000:
			if hu.shot:
				break
			hu.town.step(1.0 / 30.0)
			hu.update(1.0 / 30.0)
		for i in 3:
			hu.update(1.0 / 30.0)
		cam.position = hu.target.lerp(hu.killers[0].pos, 0.5)
		cam.zoom = Vector2.ONE * 2.6
	elif view == "filter":
		_on_type(0)  # картинки
		go_to([root, city], true)
		return
	elif view == "find":
		# поиск по фильтрам: все видео больше 1 ГБ; выбран один — он за краем, видна стрелка
		ui._f_type.select(FakeTree.Type.VIDEO + 1)
		ui._f_size.select(4)
		_on_search("")
		go_to(best.path, true)
		if not _found.is_empty():
			select({"type": "file", "item": _found[-1].item, "index": _found[-1].index})
		return
	elif view == "move":
		# переселение: житель с коробкой идёт в соседний дом того же города
		var t := map.town_of(best)
		var dst = null
		for h in t.homes:
			if h != best and (dst == null or best.pos.distance_to(h.pos) < best.pos.distance_to(dst.pos)):
				dst = h
		var f = null
		for i in best.folder.files.size():
			var r := map.resident_id(best, i)
			if r >= 0 and t.state[r] == Residents.State.HOME:
				f = best.folder.files[i]
				break
		if dst == null or f == null:
			return
		map.move_file(best, f, dst)
		select({"type": "file", "item": dst, "index": dst.folder.files.find(f)})
		for i in 30 * 6:
			t.step(1.0 / 30.0)
			if t.carry[t.files.find(f)] == 1 and not t._in_home(t.files.find(f), t.cell[t.files.find(f)]):
				break  # вышел на улицу с коробкой
		cam.position = t.pos[t.files.find(f)]
		cam.zoom = Vector2.ONE * 2.6
	elif view == "chase":
		# погоня: жертва на улице убегает, киллеры идут следом
		var hu: Hunt = null
		for i in best.folder.files.size():
			var r := map.resident_id(best, i)
			if r >= 0 and map.town_of(best).state[r] == Residents.State.OUT:
				_delete(best, i)
				hu = map._hunts.back()
				break
		if hu == null:
			return
		for i in 30 * 2:
			hu.town.step(1.0 / 30.0)
			hu.update(1.0 / 30.0)
		cam.position = hu.target.lerp(hu.killers[0].pos, 0.5)
		cam.zoom = Vector2.ONE * 1.8
	elif view == "closeup":
		cam.position = best.rect.position + Vector2(5, 4) * WorldLayout.TILE  # угол дома с мебелью
		cam.zoom = Vector2.ONE * 2.2
	elif view == "room":
		cam.zoom *= 1.3
