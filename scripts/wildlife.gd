class_name Wildlife
extends Node2D
## Живая природа на карте города: от рыб по воде расходятся круги, над горном кузницы вьётся дым.
## Только рисунок — на жителей не влияет. Рисуется и двигается только то, что в кадре; издалека слой прячется.

const T := WorldLayout.TILE
const SMOKE_EVERY := 0.28     # секунд между клубами дыма

var _ground: PackedByteArray
var _n := 0
var _origin := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
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

func _cell_pos(c: Vector2i) -> Vector2:
	return _origin + (Vector2(c) + Vector2(0.5, 0.5)) * T

func _is_water(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _n and c.y < _n and _ground[c.y * _n + c.x] == WorldLayout.G.WATER

func _deep(c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not _is_water(c + Vector2i(dx, dy)):
				return false
	return true

## Двигаем всё, что в кадре view (мир. координаты).
func update(delta: float, view: Rect2) -> void:
	_time += delta
	var wide := view.grow(T * 4)
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

func _draw() -> void:
	for r in _ripples:
		var k: float = r.t / 1.8
		for j in 2:
			var rr: float = (k * 0.55 + j * 0.12) * T
			_ellipse_ring(r.pos, rr, Color(0.85, 0.92, 0.95, 0.45 * (1.0 - k)))
	for s in _smoke:
		var a: float = 0.55 * (1.0 - s.t / 3.2) * minf(1.0, s.t * 4.0)
		draw_circle(s.pos, s.r, Color(0.55, 0.53, 0.5, a))

func _ellipse_ring(c: Vector2, r: float, col: Color) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, 0.7))
	draw_arc(Vector2.ZERO, r, 0, TAU, 24, col, 1.2, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)
