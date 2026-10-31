class_name Wildlife
extends Node2D
## Живая природа на карте города: утки с утятами плавают по озёрам и реке (утята — цепочкой за мамой),
## от рыб по воде расходятся круги, над горном кузницы вьётся дым. Только рисунок — на жителей не влияет.
## Рисуется и двигается только то, что в кадре; издалека слой прячется.

const T := WorldLayout.TILE
const DUCK_SPEED := 0.32      # клеток в секунду
const SMOKE_EVERY := 0.28     # секунд между клубами дыма

var _ground: PackedByteArray
var _n := 0
var _origin := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _ducks: Array = []        # [{pos, head (угол), leader (индекс или -1), drake, size}]
var _ripples: Array = []      # [{pos, t}]
var _smoke: Array = []        # [{pos, vel, t, r}]
var _chimneys: Array[Vector2] = []
var _water: Array[Vector2i] = []  # клетки воды вдали от берега (там всплески)
var _t_ripple := 0.0
var _t_smoke := 0.0
var _time := 0.0

func setup(world: Dictionary, seed_value: int) -> void:
	_ground = world.ground
	_n = world.n
	_origin = world.origin
	_rng.seed = seed_value + 404
	for d in world.decor:
		if d.tex == "decor_forge":
			_chimneys.append(_origin + d.c * T)
	# вода «поглубже»: все 8 соседей — вода
	for y in range(1, _n - 1):
		for x in range(1, _n - 1):
			if _deep(Vector2i(x, y)):
				_water.append(Vector2i(x, y))
	# стайки уток поближе к городу: мама (или селезень) и 0-4 утёнка
	var town: Rect2i = world.get("town", Rect2i(0, 0, _n, _n))
	var near: Array[Vector2i] = _water.filter(func(c): return town.grow(24).has_point(c))
	for k in mini(5, int(near.size() / 6.0)):
		var c: Vector2i = near[_rng.randi_range(0, near.size() - 1)]
		var lead := _ducks.size()
		var head := _rng.randf() * TAU
		var drake := _rng.randf() < 0.4
		_ducks.append({"pos": _cell_pos(c), "head": head, "leader": -1, "drake": drake, "size": 1.0, "turn": 0.0})
		if drake:
			continue
		var prev := lead
		for j in _rng.randi_range(1, 4):
			_ducks.append({"pos": _cell_pos(c) - Vector2.from_angle(head) * T * 0.4 * (j + 1), "head": head,
				"leader": prev, "drake": false, "size": 0.55, "turn": 0.0})
			prev = _ducks.size() - 1

func _cell_pos(c: Vector2i) -> Vector2:
	return _origin + (Vector2(c) + Vector2(0.5, 0.5)) * T

func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(((p - _origin) / T).floor())

func _is_water(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _n and c.y < _n and _ground[c.y * _n + c.x] == WorldLayout.G.WATER

func _deep(c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not _is_water(c + Vector2i(dx, dy)):
				return false
	return true

## Двигаем всё, что в кадре view (мир. координаты); время ночи — утки дремлют, дыма меньше не делаем.
func update(delta: float, view: Rect2) -> void:
	_time += delta
	var wide := view.grow(T * 4)
	for i in _ducks.size():
		var d: Dictionary = _ducks[i]
		if not wide.has_point(d.pos):
			continue
		if d.leader < 0:
			_swim(d, delta)
		else:
			# утёнок — за тем, кто впереди
			var to: Vector2 = _ducks[d.leader].pos - d.pos
			if to.length() > T * 0.38:
				d.head = lerp_angle(d.head, to.angle(), 1.0 - exp(-5.0 * delta))
				var step: Vector2 = to.normalized() * minf(to.length() - T * 0.38, DUCK_SPEED * 1.6 * T * delta)
				if _is_water(_cell_of(d.pos + step)):
					d.pos += step
	# круги от рыб — иногда, в воде, что видно
	_t_ripple -= delta
	if _t_ripple <= 0.0 and not _water.is_empty():
		_t_ripple = _rng.randf_range(0.4, 1.2)
		for attempt in 12:
			var c: Vector2i = _water[_rng.randi_range(0, _water.size() - 1)]
			var p := _cell_pos(c) + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4)) * T
			if view.has_point(p):
				_ripples.append({"pos": p, "t": 0.0})
				break
	for r in _ripples:
		r.t += delta
	_ripples = _ripples.filter(func(r): return r.t < 1.8)
	# дым кузницы: клубы поднимаются и сносятся ветром
	_t_smoke -= delta
	if _t_smoke <= 0.0:
		_t_smoke = SMOKE_EVERY
		for c in _chimneys:
			if wide.has_point(c):
				_smoke.append({"pos": c + Vector2(_rng.randf_range(-3, 3), -4), "vel": Vector2(_rng.randf_range(6, 12), _rng.randf_range(-22, -16)),
					"t": 0.0, "r": _rng.randf_range(3.0, 5.0)})
	for s in _smoke:
		s.t += delta
		s.pos += s.vel * delta
		s.vel.x += 4.0 * delta  # ветер
		s.r += 4.5 * delta
	_smoke = _smoke.filter(func(s): return s.t < 3.2)
	queue_redraw()

## Утка-вожак: плывёт, плавно поворачивает; впереди берег — сворачивает туда, где вода.
func _swim(d: Dictionary, delta: float) -> void:
	d.turn = lerpf(d.turn, _rng.randf_range(-1.2, 1.2), 1.0 - exp(-0.8 * delta))
	d.head += d.turn * delta
	var dir := Vector2.from_angle(d.head)
	if not _is_water(_cell_of(d.pos + dir * T * 0.9)):
		var left := _is_water(_cell_of(d.pos + dir.rotated(-0.9) * T * 0.9))
		d.head += -2.2 * delta if left else 2.2 * delta
		if not _is_water(_cell_of(d.pos + dir * T * 0.45)):
			return  # упёрлась — только разворачивается
	var step := dir * DUCK_SPEED * T * delta
	if _is_water(_cell_of(d.pos + step)):
		d.pos += step

func _draw() -> void:
	for r in _ripples:
		var k: float = r.t / 1.8
		for j in 2:
			var rr: float = (k * 0.55 + j * 0.12) * T
			_ellipse_ring(r.pos, rr, Color(0.85, 0.92, 0.95, 0.45 * (1.0 - k)))
	for d in _ducks:
		_duck(d)
	for s in _smoke:
		var a: float = 0.55 * (1.0 - s.t / 3.2) * minf(1.0, s.t * 4.0)
		draw_circle(s.pos, s.r, Color(0.55, 0.53, 0.5, a))

func _ellipse_ring(c: Vector2, r: float, col: Color) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, 0.7))
	draw_arc(Vector2.ZERO, r, 0, TAU, 24, col, 1.2, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)

## Утка сверху: след на воде, тело, крылья, голова с клювом. Селезень — с зелёной головой.
func _duck(d: Dictionary) -> void:
	var s: float = d.size * T * 0.27
	var dir := Vector2.from_angle(d.head)
	var p: Vector2 = d.pos
	# расходящиеся волны позади — дуги, которые «уплывают» и тают
	var back := dir.angle() + PI
	for k in 2:
		var ph := fmod(_time * 0.8 + k * 0.5 + p.x * 0.01, 1.0)
		var rr := s * (0.9 + ph * 1.6)
		draw_arc(p - dir * s * 0.3, rr, back - 0.75, back + 0.75, 12, Color(0.85, 0.92, 0.95, 0.35 * (1.0 - ph)), 1.3, true)
	draw_set_transform(p, d.head, Vector2.ONE)
	var body := Color(0.55, 0.45, 0.33) if not d.drake else Color(0.7, 0.68, 0.62)
	if d.size < 0.8:
		body = Color(0.95, 0.85, 0.45)  # утёнок жёлтенький
	Pawn._ellipse(self, Vector2(0.6, 0.6), Vector2(s * 1.3, s * 0.8), Color(0, 0, 0, 0.18))
	Pawn._ellipse(self, Vector2.ZERO, Vector2(s * 1.3, s * 0.8), body)
	if d.size >= 0.8:
		Pawn._ellipse(self, Vector2(-s * 0.2, 0), Vector2(s * 0.8, s * 0.55), body.darkened(0.2))  # крылья
		draw_circle(Vector2(-s * 1.15, 0), s * 0.25, Color(0.15, 0.13, 0.12))  # хвостик
	var head := Color(0.13, 0.45, 0.25) if d.drake else body.lightened(0.05)
	draw_circle(Vector2(s * 1.1, 0), s * 0.5, head)
	draw_circle(Vector2(s * 1.65, 0), s * 0.22, Color(0.95, 0.65, 0.15))  # клюв
	draw_set_transform_matrix(Transform2D.IDENTITY)
