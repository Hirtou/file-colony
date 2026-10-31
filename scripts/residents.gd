class_name Residents
extends RefCounted
## Жители одного посёлка (деревня целиком или отдельный дом). У каждого файла свой дом:
## дома он стоит в своей клетке пола (одна клетка — один житель) и занят делом у мебели
## (сидит за столом, греется у очага...), ночью спит. Днём выходит в дверь по делам: к колодцу,
## к лавкам, в гости к соседям, на площадь; встретив гуляющего рядом — болтает с ним. Потом домой.
## Путь по клеткам — обходом в ширину.

enum Facing { DOWN, UP, LEFT, RIGHT }
enum State { HOME, WALK_OUT, OUT, WALK_HOME, DOOMED }
const WHERE := ["дома", "идёт гулять", "гуляет по улице", "идёт домой", "за ним пришли киллеры"]
const STEP_HOME := 0.7  # секунд на клетку дома
const STEP_OUT := 0.42  # на улице шагают бодрее
const STEP_RUN := 0.3   # убегает от киллеров
const DIRS := [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]

var homes: Array                    # items домов посёлка
var home_of := {}                   # Folder дома -> индекс в homes
var files: Array = []               # файл каждого жителя
var looks: Array = []               # внешность (Pawn.look)
var home := PackedInt32Array()      # индекс дома жителя
var file_index := PackedInt32Array()  # индекс файла в его доме
var rid := {}                       # Vector2i(дом, файл) -> житель
var pos := PackedVector2Array()     # текущий центр
var radius := PackedFloat32Array()  # для попадания мышью
var cell: Array[Vector2i] = []
var facing := PackedInt32Array()
var walk := PackedFloat32Array()    # фаза шага 0..1 (покачивание), 0 — стоит
var state := PackedInt32Array()
var route: Array = []               # оставшийся путь каждого: Array[Vector2i]
var area: Rect2i                    # где можно гулять (клетки мира)
var night := false                  # ночью все расходятся по домам и не выходят
var _next: Array[Vector2i] = []
var _t := PackedFloat32Array()
var _wait := PackedFloat32Array()
var _busy := {}                     # занятые клетки пола -> житель
var _walk: PackedByteArray
var _n := 0
var _origin := Vector2.ZERO
var _public: Array[Vector2i] = []   # улицы посёлка
var _plaza: Array[Vector2i] = []    # площади (туда ходят чаще)
var _rng := RandomNumberGenerator.new()
var _floor: Array[Rect2i] = []      # пол каждого дома (клетки)
var _furn := {}                     # клетки под мебелью (кровати, столы...) — там не стоят
var _spots := {}                    # клетка пола -> занятие («греется у очага»)
var _sights: Array = []             # куда ходят по делам: {cells, go, at, home}
var doing: Array = []               # чем житель занят сейчас (для панели)
var chat: Array = []                # с кем болтает (FileItem) или null
var _at: Array = []                 # чем займётся, когда дойдёт
var _door: Array[Vector2i] = []     # дверь каждого дома
var _seen := PackedInt32Array()     # обход в ширину: метка обхода по клеткам area
var _prev := PackedInt32Array()     # откуда пришли
var _gen := 0

func _init(house_items: Array, walk_area: Rect2i, world: Dictionary, seed_value: int) -> void:
	homes = house_items
	area = walk_area
	_walk = world.walk
	_n = world.n
	_origin = world.origin
	_rng.seed = seed_value
	for y in range(maxi(area.position.y, 0), mini(area.end.y, _n)):
		for x in range(maxi(area.position.x, 0), mini(area.end.x, _n)):
			if _walk[y * _n + x] == 1:
				_public.append(Vector2i(x, y))
				if world.ground[y * _n + x] == WorldLayout.G.PLAZA:
					_plaza.append(Vector2i(x, y))
	for it in homes:
		_floor.append(Rect2i(it.cell + Vector2i.ONE, it.size - Vector2i(2, 2)))
		_door.append(it.door)
		for c in it.get("furniture", []):
			_furn[c] = true
		_spots.merge(it.get("spots", {}))
	_find_sights(world)
	for h in homes.size():
		var it: Dictionary = homes[h]
		home_of[it.folder] = h
		var cells := _shuffled(home_cells(h))
		var fs: Array = it.folder.files.slice(0, WorldMap.drawn_count(it.folder))
		for i in mini(fs.size(), cells.size()):
			var r := files.size()
			files.append(fs[i])
			looks.append(Pawn.look(fs[i]))
			home.append(h)
			file_index.append(i)
			rid[Vector2i(h, i)] = r
			var c: Vector2i = cells[i]
			var st := State.HOME
			# часть жителей с самого начала гуляет
			if not _public.is_empty() and _rng.randf() < 0.35:
				c = _public[_rng.randi_range(0, _public.size() - 1)]
				st = State.OUT
			else:
				_busy[c] = r
			_spawn(c, st)

## Места, куда ходят по делам: колодец, лавки, двери соседей.
func _find_sights(world: Dictionary) -> void:
	var near := {"decor_well": ["идёт к колодцу", "набирает воду у колодца"],
		"decor_stall_1": ["идёт на рынок", "торгуется у лавки с овощами"],
		"decor_stall_2": ["идёт на рынок", "разглядывает зелья в лавке"]}
	for d in world.decor:
		if not near.has(d.tex) or not area.has_point(Vector2i(d.c)):
			continue
		var cells: Array[Vector2i] = []
		for c in _public:
			var dist := (Vector2(c) + Vector2(0.5, 0.5)).distance_to(d.c)
			if dist > 0.9 and dist < 2.1:
				cells.append(c)
		if not cells.is_empty():
			_sights.append({"cells": cells, "go": near[d.tex][0], "at": near[d.tex][1], "home": -1})
	for h in homes.size():
		var it: Dictionary = homes[h]
		var front: Vector2i = it.door + it.door_side
		if area.has_point(front) and _walk[front.y * _n + front.x] == 1:
			_sights.append({"cells": [front], "go": "идёт в гости к «%s»" % it.folder.name,
				"at": "стучится к соседям «%s»" % it.folder.name, "home": h})

## Дописать в массивы жителя, чьи files/looks/home/file_index уже добавлены.
func _spawn(c: Vector2i, st: int) -> void:
	doing.append("гуляет по улице" if st == State.OUT else "дома")
	_at.append("гуляет по улице")
	chat.append(null)
	cell.append(c)
	_next.append(c)
	pos.append(center(c))
	radius.append(WorldLayout.TILE * 0.4)
	facing.append(Facing.DOWN)
	walk.append(0.0)
	state.append(st)
	route.append([])
	_t.append(0.0)
	_wait.append(_rng.randf_range(0.5, 6.0))

## Сколько жителей нарисовано у дома h.
func count(h: int) -> int:
	var n := 0
	for r in home.size():
		if home[r] == h:
			n += 1
	return n

## Новый житель дома h (файл уже лежит в папке дома). at_door — входит с улицы через дверь.
## -1 — места в доме нет (файл останется за «+N»).
func add_file(h: int, file, at_door := true) -> int:
	if count(h) >= WorldMap.MAX_RESIDENTS:
		return -1
	var free: Array[Vector2i] = []
	for c in home_cells(h):
		if not _busy.has(c):
			free.append(c)
	if free.is_empty():
		return -1
	var c: Vector2i = free[_rng.randi_range(0, free.size() - 1)]
	var r := files.size()
	files.append(file)
	looks.append(Pawn.look(file))
	home.append(h)
	file_index.append(0)
	_spawn(c, State.HOME)
	_busy[c] = r
	if at_door:
		var path := find_path(r, _door[h], c)
		if not path.is_empty():
			cell[r] = _door[h]
			_next[r] = _door[h]
			pos[r] = center(_door[h])
			route[r] = path
			state[r] = State.WALK_HOME
	_reindex()
	return r

## Убрать жителя r (его файл уже удалён из папки дома).
func remove(r: int) -> void:
	_end_chat(r)
	doing.remove_at(r)
	_at.remove_at(r)
	chat.remove_at(r)
	for c in _busy.keys():
		if _busy[c] == r:
			_busy.erase(c)
		elif _busy[c] > r:
			_busy[c] -= 1
	files.remove_at(r)
	looks.remove_at(r)
	route.remove_at(r)
	cell.remove_at(r)
	_next.remove_at(r)
	home.remove_at(r)
	file_index.remove_at(r)
	pos.remove_at(r)
	radius.remove_at(r)
	facing.remove_at(r)
	walk.remove_at(r)
	state.remove_at(r)
	_t.remove_at(r)
	_wait.remove_at(r)
	_reindex()

## Номера файлов в папках домов сдвинулись — пересчитать file_index и rid.
func _reindex() -> void:
	rid.clear()
	for r in files.size():
		file_index[r] = homes[home[r]].folder.files.find(files[r])
		rid[Vector2i(home[r], file_index[r])] = r

## За жителем пришли: замирает на месте и ждёт своей участи.
func doom(r: int) -> void:
	_end_chat(r)
	for c in _busy.keys():
		if _busy[c] == r:
			_busy.erase(c)  # своё место дома больше не держит
	state[r] = State.DOOMED
	route[r] = []
	_next[r] = cell[r]
	_t[r] = 0.0
	walk[r] = 0.0
	pos[r] = center(cell[r])

## Мировой центр клетки.
func center(c: Vector2i) -> Vector2:
	return _origin + (Vector2(c) + Vector2(0.5, 0.5)) * WorldLayout.TILE

## Клетки пола дома h.
func home_cells(h: int) -> Array[Vector2i]:
	var it: Dictionary = homes[h]
	var out: Array[Vector2i] = []
	for y in range(it.cell.y + 1, it.cell.y + it.size.y - 1):
		for x in range(it.cell.x + 1, it.cell.x + it.size.x - 1):
			if not _furn.has(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out

func _in_home(r: int, c: Vector2i) -> bool:
	return _floor[home[r]].has_point(c)

## Может ли житель r стоять в клетке c: свой пол (не под мебелью), своя дверь или улица посёлка.
func can_stand(r: int, c: Vector2i) -> bool:
	var h := home[r]
	if _floor[h].has_point(c):
		return not _furn.has(c)
	if c == _door[h]:
		return true
	if not area.has_point(c) or c.x < 0 or c.y < 0 or c.x >= _n or c.y >= _n:
		return false
	return _walk[c.y * _n + c.x] == 1

## Чем житель занят — для панели и подсказки.
func where(r: int) -> String:
	var still: bool = route[r].is_empty() and _next[r] == cell[r]
	match state[r]:
		State.HOME:
			if night and still:
				return "спит"
			return _spots.get(cell[r], "хлопочет по дому") if still else "ходит по дому"
		State.WALK_HOME:
			return "спешит домой — темнеет" if night else "идёт домой"
		State.WALK_OUT, State.OUT:
			return doing[r]
	return WHERE[state[r]]

## Спит ли (ночью дома, стоит на месте) — рисуется «z».
func sleeping(r: int) -> bool:
	return night and state[r] == State.HOME and route[r].is_empty() and _next[r] == cell[r]

func step(delta: float) -> void:
	for r in cell.size():
		var doomed := state[r] == State.DOOMED  # за ним киллеры: бежит, куда велит охота (Hunt)
		if _next[r] != cell[r]:
			var out := not (_in_home(r, cell[r]) and _in_home(r, _next[r]))
			_t[r] += delta / (STEP_RUN if doomed else (STEP_OUT if out else STEP_HOME))
			if _t[r] < 1.0:
				pos[r] = center(cell[r]).lerp(center(_next[r]), _t[r])
				walk[r] = _t[r]
				continue
			cell[r] = _next[r]
			_t[r] = 0.0
			walk[r] = 0.0
			pos[r] = center(cell[r])
		if not route[r].is_empty():
			var nx: Vector2i = route[r].pop_front()
			facing[r] = DIRS.find(nx - cell[r])
			_next[r] = nx
			continue
		match state[r]:
			State.WALK_OUT:
				state[r] = State.OUT
				doing[r] = _at[r]
				_wait[r] = _rng.randf_range(3.0, 8.0)
				_try_chat(r)
			State.WALK_HOME:
				state[r] = State.HOME
				_wait[r] = _rng.randf_range(4.0, 12.0)
			State.HOME:
				_home_tick(r, delta)
			State.OUT:
				_out_tick(r, delta)

## Дошёл до места: если рядом стоит другой гуляющий — заводят разговор.
func _try_chat(r: int) -> void:
	if _rng.randf() > 0.65:
		return
	for q in files.size():
		if q == r or state[q] != State.OUT or chat[q] != null or not route[q].is_empty() or _next[q] != cell[q]:
			continue
		var d := cell[q] - cell[r]
		if absi(d.x) + absi(d.y) > 2:
			continue
		chat[r] = files[q]
		chat[q] = files[r]
		doing[r] = "болтает с %s" % files[q].name
		doing[q] = "болтает с %s" % files[r].name
		facing[r] = _face(d)
		facing[q] = _face(-d)
		_wait[r] = _rng.randf_range(6.0, 11.0)
		_wait[q] = _wait[r]
		return

static func _face(d: Vector2i) -> int:
	if absi(d.x) > absi(d.y):
		return Facing.RIGHT if d.x > 0 else Facing.LEFT
	return Facing.DOWN if d.y >= 0 else Facing.UP

## Закончить разговор (собеседник тоже скоро пойдёт дальше).
func _end_chat(r: int) -> void:
	if chat[r] == null:
		return
	var q := files.find(chat[r])
	chat[r] = null
	if q >= 0 and chat[q] == files[r]:
		chat[q] = null
		doing[q] = "стоит на улице"
		_wait[q] = minf(_wait[q], _rng.randf_range(0.5, 2.0))

## Дома: занят делом у мебели, иногда переходит к другому делу или выходит по делам. Ночью спит.
func _home_tick(r: int, delta: float) -> void:
	_wait[r] -= delta
	if _wait[r] > 0.0:
		return
	_wait[r] = _rng.randf_range(1.5, 5.0)
	if night:
		return  # спит
	if not _public.is_empty() and _rng.randf() < 0.3:
		var path := find_path(r, cell[r], _street_target(r))
		if not path.is_empty():
			_busy.erase(cell[r])
			route[r] = path
			state[r] = State.WALK_OUT
			return
	# к мебели: за стол, к очагу, к полке...
	if _rng.randf() < 0.45:
		var free: Array[Vector2i] = []
		for c in home_cells(home[r]):
			if _spots.has(c) and not _busy.has(c) and c != cell[r]:
				free.append(c)
		if not free.is_empty():
			var c: Vector2i = free[_rng.randi_range(0, free.size() - 1)]
			var path := find_path(r, cell[r], c)
			if not path.is_empty():
				_busy.erase(cell[r])
				_busy[c] = r
				route[r] = path
				_wait[r] = _rng.randf_range(5.0, 12.0)  # побудет там подольше
				return
	var d: Vector2i = DIRS[_rng.randi_range(0, 3)]
	var n := cell[r] + d
	facing[r] = DIRS.find(d)
	if _in_home(r, n) and not _busy.has(n) and not _furn.has(n):
		_busy.erase(cell[r])
		_busy[n] = r
		_next[r] = n

## На улице: постоял — пошёл дальше гулять или домой.
func _out_tick(r: int, delta: float) -> void:
	_wait[r] -= delta
	if _wait[r] > 0.0:
		return
	_wait[r] = _rng.randf_range(2.0, 5.0)
	_end_chat(r)
	if night:
		_wait[r] = _rng.randf_range(0.2, 1.0)  # темнеет — скорее домой
	elif _rng.randf() < 0.45:
		var path := find_path(r, cell[r], _street_target(r))
		if not path.is_empty():
			route[r] = path
			state[r] = State.WALK_OUT
		return
	# домой: заранее занимаем свободную клетку пола
	for c in _shuffled(home_cells(home[r])):
		if _busy.has(c):
			continue
		var path := find_path(r, cell[r], c)
		if path.is_empty():
			return
		_busy[c] = r
		route[r] = path
		state[r] = State.WALK_HOME
		return

## Куда пойти по делам (и что там делать — в doing/_at жителя r).
func _street_target(r: int) -> Vector2i:
	var roll := _rng.randf()
	if roll < 0.5 and not _sights.is_empty():
		var s: Dictionary = _sights[_rng.randi_range(0, _sights.size() - 1)]
		if s.home != home[r]:  # не в гости к себе
			doing[r] = s.go
			_at[r] = s.at
			return s.cells[_rng.randi_range(0, s.cells.size() - 1)]
	if roll < 0.75 and not _plaza.is_empty():
		doing[r] = "идёт на площадь"
		_at[r] = "отдыхает на площади"
		return _plaza[_rng.randi_range(0, _plaza.size() - 1)]
	doing[r] = "идёт прогуляться"
	_at[r] = "гуляет по улице"
	return _public[_rng.randi_range(0, _public.size() - 1)]

## Кратчайший путь по клеткам (обход в ширину) без стартовой клетки; [] — не дойти.
## Посещённые клетки — в массивах с меткой обхода (без словарей и выделения памяти — быстро).
func find_path(r: int, from: Vector2i, to: Vector2i) -> Array:
	if from == to or not can_stand(r, to) or not area.has_point(from) or not area.has_point(to):
		return []
	var aw := area.size.x
	var cells := aw * area.size.y
	if _seen.size() != cells:
		_seen.resize(cells)
		_prev.resize(cells)
		_seen.fill(0)
	_gen += 1
	var start := (from.y - area.position.y) * aw + from.x - area.position.x
	var goal := (to.y - area.position.y) * aw + to.x - area.position.x
	_seen[start] = _gen
	var q := PackedInt32Array([start])
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		if i == goal:
			var path := []
			while i != start:
				path.push_front(Vector2i(i % aw, i / aw) + area.position)
				i = _prev[i]
			return path
		var c := Vector2i(i % aw, i / aw) + area.position
		for d in DIRS:
			var n: Vector2i = c + d
			if not area.has_point(n):
				continue
			var j := (n.y - area.position.y) * aw + n.x - area.position.x
			if _seen[j] != _gen and can_stand(r, n):
				_seen[j] = _gen
				_prev[j] = i
				q.append(j)
	return []

func _shuffled(a: Array[Vector2i]) -> Array[Vector2i]:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := a[i]
		a[i] = a[j]
		a[j] = tmp
	return a

## Проверка: все стоят там, где можно, и дома никто не делит клетку.
func check() -> bool:
	var seen := {}
	for r in cell.size():
		if not can_stand(r, cell[r]) or not can_stand(r, _next[r]):
			return false
		if state[r] == State.HOME:
			# своя (занятая заранее) клетка — та, куда идёт или где стоит
			var own: Vector2i = route[r].back() if not route[r].is_empty() else _next[r]
			if seen.has(own) or _busy.get(own, -1) != r:
				return false
			seen[own] = true
	return true
