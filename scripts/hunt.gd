class_name Hunt
extends RefCounted
## Удаление файла: за жителем приходят двое киллеров в камзолах и треуголках с мушкетами.
## Жертва не стоит столбом: дома — бежит в дальний угол и прячется за мебелью; на улице — убегает
## подальше от киллеров, петляет, а потом бросается домой прятаться. Киллеры идут по улицам следом
## (путь пересчитывают на каждой клетке) и чуть быстрее жертвы. Догнали (2 клетки) — жертва замирает,
## киллеры целятся и стреляют: вспышка, дым, житель падает и исчезает — файл удалён (из выдуманного
## дерева). Потом киллеры уходят тем же путём и пропадают.

enum K { WALK, WAIT, AIM, FIRED, LEAVE, GONE }
enum V { FLEE, HIDE, HIDDEN, CAUGHT, DEAD }
const STEP := 0.26                     # секунд на клетку у киллера (жертва — Residents.STEP_RUN)
const STOP := [2, 3]                   # за сколько клеток пути до жертвы встают
const AIM_TIME := 0.9
const LIE_TIME := 1.4                  # сколько лежит до исчезновения
const GIVE_UP := 40.0                  # столько бегает, потом выдыхается
const STOCK := Color(0.47, 0.29, 0.15)
const METAL := Color(0.36, 0.37, 0.4)
const BRASS := Color(0.85, 0.66, 0.28)
const STATUS := ["убегает от киллеров", "бежит прятаться", "затаился в углу дома", "попался киллерам", "удалён"]

var town: Residents
var item: Dictionary                   # дом жертвы
var file                               # FileItem жертвы
var target: Vector2                    # где жертва сейчас
var victim_look: Dictionary
var mode := V.FLEE
var status: String:  # что сейчас с жертвой — для панели
	get:
		return I18n.t(STATUS[mode])
var killers: Array = []
var shot := false                      # прозвучал первый выстрел — файл удаляется
var applied := false                   # карта уже удалила файл
var fall := -1.0                       # секунд с выстрела (-1 — ещё жив)
var over := false                      # всё закончилось — убрать
var _fx: Array = []                    # {kind: smoke/flash/tracer, p, q, v, t, life, r}
var _t := 0.0
var _caught_t := 0.0
var _legs := 0                         # сколько раз уже перебегал
var _rethink := 0.0
var _rng := RandomNumberGenerator.new()

func _init(t: Residents, house: Dictionary, r: int) -> void:
	town = t
	item = house
	file = t.files[r]
	victim_look = t.looks[r]
	_rng.seed = absi(String(file.name).hash())
	t.doom(r)
	target = t.pos[r]
	var spawn := _spawn_cell(r)
	for k in 2:
		killers.append({"cell": spawn, "next": spawn, "t": 0.0, "pos": t.center(spawn), "path": [], "trail": [spawn],
			"facing": Residents.Facing.DOWN, "walk": 0.0, "state": K.WALK, "delay": k * 0.6, "stop": STOP[k],
			"aim": 0.0, "n": k, "look": killer_look(k), "replan": 0.0})
	# дома — прячется; на улице — то убегает, то сразу домой
	if t._in_home(r, t.cell[r]) or _rng.randf() < 0.35:
		_hide(r)
	else:
		_flee(r)

## Внешность киллера: тёмный камзол с перевязью, треуголка с пером, платок на лице.
static func killer_look(k: int) -> Dictionary:
	return {"style": 8, "main": [Color(0.15, 0.16, 0.22), Color(0.22, 0.13, 0.12)][k], "accent": Color(0.55, 0.12, 0.12),
		"skin": Pawn.SKINS[1 + k * 2], "hair": 1 if k == 1 else 0, "hair_color": Pawn.HAIR_COLORS[k * 2],
		"width": 1.12, "hat": 7, "hat_color": Color(0.1, 0.09, 0.1), "mask": true}

func _victim() -> int:
	return town.files.find(file)

## Откуда приходят: улица посёлка примерно в 12 клетках, до жертвы есть путь.
func _spawn_cell(r: int) -> Vector2i:
	var from: Vector2i = town.cell[r]
	var pub: Array[Vector2i] = town._public
	var cands: Array = []
	for i in mini(60, pub.size()):
		var c: Vector2i = pub[_rng.randi_range(0, pub.size() - 1)]
		cands.append([absf(Vector2(c - from).length() - 12.0), c])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for k in mini(4, cands.size()):
		if not town.find_path(r, cands[k][1], from).is_empty():
			return cands[k][1]
	return from + Vector2i(6, 0)  # улиц нет — подходят напрямик

# --- жертва ---

## Спрятаться: самая дальняя от двери клетка дома, лучше рядом с мебелью.
func _hide(r: int) -> void:
	var h: int = town.home[r]
	var door: Vector2i = town._door[h]
	var best := Vector2i(-1, -1)
	var score := -1.0
	for c in town.home_cells(h):
		var s := float(absi(c.x - door.x) + absi(c.y - door.y))
		for d in Residents.DIRS:
			if town._furn.has(c + d):
				s += 1.5  # за кроватью, шкафом
		if s > score:
			score = s
			best = c
	var path := town.find_path(r, town.cell[r], best) if best.x >= 0 else []
	if path.is_empty() and best != town.cell[r]:
		_flee(r)  # домой не пробиться — бежит куда глаза глядят
		return
	mode = V.HIDE
	town.route[r] = path

## Убежать: улица подальше от киллеров.
func _flee(r: int) -> void:
	mode = V.FLEE
	_legs += 1
	_rethink = 1.2
	var pub: Array[Vector2i] = town._public
	var cands: Array = []
	for i in mini(40, pub.size()):
		var c: Vector2i = pub[_rng.randi_range(0, pub.size() - 1)]
		var far := INF
		for k in killers:
			far = minf(far, Vector2(c - k.cell).length())
		cands.append([-far + Vector2(c - town.cell[r]).length() * 0.3, c])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for k in mini(6, cands.size()):
		var path := town.find_path(r, town.cell[r], cands[k][1])
		if not path.is_empty() and _safe(path):
			town.route[r] = path
			return
	if _legs < 3:
		_legs = 3
		_hide(r)  # на улице путь отрезан — домой
	else:
		mode = V.HIDDEN  # бежать некуда — замирает и дрожит

## Путь не идёт мимо киллеров (ближе 3 клеток).
func _safe(path: Array) -> bool:
	for c in path:
		for k in killers:
			if Vector2(c - k.cell).length() < 3.0:
				return false
	return true

func _update_victim(r: int, delta: float) -> void:
	var still: bool = town.route[r].is_empty() and town._next[r] == town.cell[r]
	match mode:
		V.FLEE:
			_rethink -= delta
			var near := INF
			for k in killers:
				near = minf(near, Vector2(k.cell - town.cell[r]).length())
			# добежал или киллеры близко — дальше; набегался — домой прятаться
			if still or (near < 4.0 and _rethink <= 0.0):
				if _legs >= 3:
					_hide(r)
				else:
					_flee(r)
		V.HIDE:
			_rethink -= delta
			if still:
				mode = V.HIDDEN
			elif _rethink <= 0.0 and not town._in_home(r, town.cell[r]) and not _safe(town.route[r].slice(0, 5)):
				_rethink = 1.0
				_legs = mini(_legs, 1)
				_flee(r)  # к дому не прорваться — киллеры на пути, бежит в другую сторону
	if mode == V.HIDDEN or mode == V.CAUGHT:
		if still:  # дрожит от страха
			town.pos[r] = town.center(town.cell[r]) + Vector2(sin(_t * 45.0) * 1.3, 0)
	target = town.pos[r]

func _catch(r: int) -> void:
	if mode == V.CAUGHT:
		return
	mode = V.CAUGHT
	town.route[r] = []  # доделает текущий шаг и встанет

# --- киллеры ---

static func _face(d: Vector2) -> int:
	if absf(d.x) > absf(d.y):
		return Residents.Facing.RIGHT if d.x > 0 else Residents.Facing.LEFT
	return Residents.Facing.DOWN if d.y > 0 else Residents.Facing.UP

## Путь киллера до жертвы (по тем же клеткам, где может пройти жертва); нет — напрямик.
func _plan(k: Dictionary, r: int) -> void:
	var goal: Vector2i = town.cell[r]
	if k.cell == goal:
		k.path = []
		return
	var path := town.find_path(r, k.cell, goal)
	k.path = path if not path.is_empty() else [goal]

func update(delta: float) -> void:
	_t += delta
	var r := _victim() if fall < 0.0 else -1
	if r >= 0:
		_update_victim(r, delta)
		if mode != V.CAUGHT and _t > GIVE_UP:
			_catch(r)
	for k in killers:
		match k.state:
			K.WALK:
				if _t >= k.delay and r >= 0:
					_chase(k, r, delta)
			K.WAIT:
				k.replan -= delta
				if r >= 0 and k.replan <= 0.0:
					k.replan = 0.25
					_plan(k, r)
					if k.path.size() > k.stop + 1 and mode != V.CAUGHT:
						k.state = K.WALK  # жертва снова убежала
				k.facing = _face(target - k.pos)
			K.AIM:
				k.facing = _face(target - k.pos)
				k.aim += delta
				if k.aim >= AIM_TIME + k.n * 0.35:  # второй стреляет чуть позже
					_fire(k)
			K.FIRED:
				k.aim += delta
				if fall > LIE_TIME + 0.5:
					k.state = K.LEAVE
					k.path = []
					var back: Array = k.trail.duplicate()
					back.reverse()
					for c in back.slice(1, 14):
						k.path.append(c)
			K.LEAVE:
				if k.t == 0.0 and k.path.is_empty():
					k.state = K.GONE
					_smoke(k.pos, 5, 0.9)
				else:
					_move(k, delta)
	if mode == V.CAUGHT and r >= 0:
		_caught_t += delta
		var ready := killers.all(func(k): return k.state != K.WALK or _t < k.delay)
		for k in killers:
			if k.state == K.WAIT and (ready or _caught_t > 3.0):
				k.state = K.AIM
				_step_back(k, r)
	for k in killers:
		if k.state == K.AIM and k.t > 0.0:
			_move(k, delta)  # отходит на шаг, чтобы не стрелять в упор
	if fall >= 0.0:
		var before := fall
		fall += delta
		if before < LIE_TIME and fall >= LIE_TIME:
			_smoke(target, 9, 1.2)  # был файл — и нет его
	for e in _fx:
		e.t += delta
		e.p += e.v * delta
	_fx = _fx.filter(func(e): return e.t < e.life)
	over = fall > LIE_TIME and _fx.is_empty() and killers.all(func(k): return k.state == K.GONE)

## Стоит вплотную к жертве — шаг назад на соседнюю клетку подальше.
func _step_back(k: Dictionary, r: int) -> void:
	if k.pos.distance_to(target) >= WorldLayout.TILE * 1.6:
		return
	var best: Vector2i = k.cell
	for d in Residents.DIRS:
		var c: Vector2i = k.cell + d
		if town.can_stand(r, c) and Vector2(c - town.cell[r]).length() > Vector2(best - town.cell[r]).length():
			best = c
	if best != k.cell:
		k.path = [best]
		_move(k, 0.0001)

## Погоня: на каждой клетке путь заново (жертва бегает), подошёл на stop клеток — встал.
func _chase(k: Dictionary, r: int, delta: float) -> void:
	if k.t == 0.0:
		_plan(k, r)
		if k.path.size() <= k.stop:
			k.state = K.WAIT
			k.walk = 0.0
			if k.path.size() <= STOP[0]:
				_catch(r)  # догнали
			return
	_move(k, delta)

## Шаг к следующей клетке пути k.path.
func _move(k: Dictionary, delta: float) -> void:
	if k.t == 0.0:
		if k.path.is_empty():
			return
		k.next = k.path[0]
	var a: Vector2 = town.center(k.cell)
	var b: Vector2 = town.center(k.next)
	k.t += delta / (STEP * maxf(1.0, Vector2(k.next - k.cell).length()))
	k.facing = _face(b - a)
	if k.t >= 1.0:
		k.cell = k.next
		k.path.pop_front()
		k.trail.append(k.cell)
		k.t = 0.0
		k.pos = b
		k.walk = 0.0
	else:
		k.pos = a.lerp(b, k.t)
		k.walk = k.t

## Где мушкет: [приклад, дуло].
func _musket(k: Dictionary) -> Array:
	var u := WorldLayout.TILE
	var p: Vector2 = k.pos
	if k.state == K.AIM or k.state == K.FIRED:
		var d := (target - p).normalized()
		var a := p + d.orthogonal() * u * 0.1 - d * u * 0.1 + Vector2(0, u * 0.04)
		return [a, a + d * u * 1.05]
	var s := -1.0 if k.facing == Residents.Facing.LEFT else 1.0  # на плече, прикладом вниз
	return [p + Vector2(s * u * 0.3, u * 0.36), p + Vector2(s * u * 0.4, -u * 0.58)]

func _fire(k: Dictionary) -> void:
	k.state = K.FIRED
	var m: Array = _musket(k)
	var muzzle: Vector2 = m[1]
	_fx.append({"kind": "flash", "p": muzzle, "q": muzzle, "v": Vector2.ZERO, "t": 0.0, "life": 0.14, "r": 0.0})
	_fx.append({"kind": "tracer", "p": muzzle, "q": target, "v": Vector2.ZERO, "t": 0.0, "life": 0.09, "r": 0.0})
	_smoke(muzzle, 5, 1.3)
	if not shot:
		shot = true
		fall = 0.0
		mode = V.DEAD

func _smoke(at: Vector2, n: int, life: float) -> void:
	var u := WorldLayout.TILE
	for i in n:
		var v := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(4.0, 14.0) + Vector2(0, -6)
		_fx.append({"kind": "smoke", "p": at + v * 0.5, "q": at, "v": v, "t": 0.0,
			"life": life * _rng.randf_range(0.7, 1.0), "r": u * _rng.randf_range(0.12, 0.22)})

# --- рисование ---

## near — вблизи (человечки, мушкеты), иначе киллеры — тёмные точки; full — с деталями одежды.
func draw(ci: CanvasItem, near: bool, full: bool) -> void:
	var u := WorldLayout.TILE
	if fall < 0.0:
		# над жертвой — «!» (догнали — красный)
		var col := Color(1.0, 0.3, 0.25) if mode == V.CAUGHT else Color(1.0, 0.85, 0.2)
		var top := target + Vector2(0, -u * 0.72 + sin(_t * 8.0) * u * 0.03)
		ci.draw_rect(Rect2(top + Vector2(-u * 0.045, -u * 0.24), Vector2(u * 0.09, u * 0.17)), col)
		ci.draw_circle(top + Vector2(0, u * 0.03), u * 0.05, col)
	elif fall < LIE_TIME and near:
		# падает набок и лежит
		var a := minf(fall / 0.35, 1.0) * PI / 2
		ci.draw_set_transform(target + Vector2(0, u * 0.2), a, Vector2.ONE)
		Pawn.draw(ci, Vector2(0, -u * 0.2), u, victim_look, Residents.Facing.DOWN, 0.0, false, full)
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	var order := killers.filter(func(k): return k.state != K.GONE and _t >= k.delay)
	order.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	for k in order:
		if not near:
			ci.draw_circle(k.pos, u * 0.3, Color(0.1, 0.1, 0.12))
			continue
		var m: Array = _musket(k)
		var aiming: bool = k.state == K.AIM or k.state == K.FIRED
		var behind: bool = k.facing == Residents.Facing.UP and not aiming
		if behind:
			draw_musket(ci, m[0], m[1], u, null)
		Pawn.draw(ci, k.pos, u, k.look, k.facing, k.walk, false, full)
		if not behind:
			draw_musket(ci, m[0], m[1], u, k.look.skin if aiming else null)
	for e in _fx:
		var f: float = e.t / e.life
		match e.kind:
			"smoke":
				ci.draw_circle(e.p, e.r * (1.0 + f * 1.6), Color(0.85, 0.85, 0.82, 0.55 * (1.0 - f)))
			"flash":
				var pts := PackedVector2Array()
				for i in 10:
					pts.append(e.p + Vector2.from_angle(TAU * i / 10.0) * u * (0.3 if i % 2 == 0 else 0.12) * (1.0 - f * 0.5))
				ci.draw_colored_polygon(pts, Color(1.0, 0.8, 0.3, 1.0 - f))
				ci.draw_circle(e.p, u * 0.08, Color(1, 1, 0.85, 1.0 - f))
			"tracer":
				ci.draw_line(e.p, e.q, Color(1.0, 0.95, 0.7, 0.8 * (1.0 - f)), u * 0.04)

## Кремнёвый мушкет от приклада a до дула b: ореховое ложе, ствол с латунными кольцами,
## замок с курком, шомпол, штык. hands — цвет кожи, если держат в руках (целятся).
static func draw_musket(ci: CanvasItem, a: Vector2, b: Vector2, u: float, hands) -> void:
	var d := (b - a).normalized()
	var nrm := d.orthogonal() * 1.5  # толщина ружья (в долях клетки по y ниже)
	var L := a.distance_to(b)
	var P := func(x: float, y: float) -> Vector2: return a + d * x * L + nrm * y * u
	var poly := func(pts: Array, col: Color) -> void:
		var pp := PackedVector2Array()
		for q in pts:
			pp.append(P.call(q.x, q.y))
		ci.draw_colored_polygon(pp, col)
		pp.append(pp[0])
		ci.draw_polyline(pp, Pawn.OUTLINE, u * 0.022)
	# приклад и ложе
	poly.call([Vector2(0, -0.085), Vector2(0.06, -0.09), Vector2(0.3, -0.042), Vector2(0.62, -0.036),
		Vector2(0.62, 0.03), Vector2(0.3, 0.036), Vector2(0.06, 0.085), Vector2(0, 0.08)], STOCK)
	ci.draw_line(P.call(0.08, -0.04), P.call(0.25, -0.02), STOCK.lightened(0.25), u * 0.018)  # блик на дереве
	poly.call([Vector2(0.62, -0.032), Vector2(0.86, -0.027), Vector2(0.86, 0.022), Vector2(0.62, 0.027)], STOCK.lightened(0.08))
	# ствол и шомпол
	poly.call([Vector2(0.32, -0.024), Vector2(1.0, -0.019), Vector2(1.0, 0.007), Vector2(0.32, 0.01)], METAL)
	ci.draw_line(P.call(0.36, -0.016), P.call(0.98, -0.013), METAL.lightened(0.35), u * 0.012)
	ci.draw_line(P.call(0.62, 0.03), P.call(0.97, 0.026), METAL.darkened(0.2), u * 0.014)
	# замок с курком и латунные кольца
	poly.call([Vector2(0.37, -0.058), Vector2(0.47, -0.058), Vector2(0.47, -0.02), Vector2(0.37, -0.02)], BRASS)
	poly.call([Vector2(0.37, -0.058), Vector2(0.34, -0.1), Vector2(0.39, -0.095)], METAL.darkened(0.3))
	for x in [0.7, 0.84, 0.97]:
		ci.draw_line(P.call(x, -0.03), P.call(x, 0.03), BRASS, u * 0.026)
	ci.draw_line(P.call(0.02, -0.08), P.call(0.02, 0.078), BRASS.darkened(0.15), u * 0.03)  # затыльник
	# штык
	poly.call([Vector2(0.97, -0.03), Vector2(1.22, -0.008), Vector2(0.97, 0.004)], Color(0.82, 0.84, 0.88))
	if hands != null:
		for x in [0.3, 0.66]:
			ci.draw_circle(P.call(x, 0.04), u * 0.065, Pawn.OUTLINE)
			ci.draw_circle(P.call(x, 0.04), u * 0.05, hands)
