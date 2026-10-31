extends Node2D
## Дождь над картой города: косые струи, брызги на земле и кружки на воде, небо темнее.
## amount — сила дождя 0..1 (плавно растёт и спадает, решает continent.gd). Рисуется только то, что в кадре.

const DROPS_PER_MPX := 900.0  # струй на миллион пикселей экрана при полном дожде
const WIND := Vector2(-0.28, 1.0)

var amount := 0.0
var _view := Rect2()
var _zoom := 1.0
var _drops: Array = []    # [{p (доля экрана 0..1), len, speed}]
var _splash: Array = []   # [{pos (мир), t}]
var _rng := RandomNumberGenerator.new()
var _ground: PackedByteArray
var _n := 0
var _origin := Vector2.ZERO

func setup(world: Dictionary) -> void:
	_ground = world.ground
	_n = world.n
	_origin = world.origin
	_rng.seed = 7311

func update(delta: float, view: Rect2, zoom: float) -> void:
	_view = view
	_zoom = zoom
	visible = amount > 0.01
	if not visible:
		_drops.clear()
		_splash.clear()
		return
	# струи живут в долях экрана: на любом масштабе их плотность одинакова
	var want := int(DROPS_PER_MPX * amount * view.size.x * view.size.y * zoom * zoom / 1e6)
	while _drops.size() < want:
		_drops.append({"p": Vector2(_rng.randf(), _rng.randf()), "len": _rng.randf_range(0.018, 0.032), "speed": _rng.randf_range(1.6, 2.2)})
	if _drops.size() > want:
		_drops.resize(want)
	var aspect := view.size.x / maxf(view.size.y, 1.0)
	for d in _drops:
		d.p += Vector2(WIND.x / aspect, WIND.y) * d.speed * delta
		if d.p.y > 1.0 or d.p.x < 0.0:
			d.p = Vector2(_rng.randf_range(0.0, 1.2), _rng.randf_range(-0.1, 0.0))
			if _rng.randf() < 0.35:
				# капля долетела — брызги в случайном месте кадра
				_splash.append({"pos": view.position + Vector2(_rng.randf(), _rng.randf()) * view.size, "t": 0.0})
	for s in _splash:
		s.t += delta
	_splash = _splash.filter(func(s): return s.t < 0.45)
	queue_redraw()

func _is_water(p: Vector2) -> bool:
	var c := Vector2i(((p - _origin) / WorldLayout.TILE).floor())
	return c.x >= 0 and c.y >= 0 and c.x < _n and c.y < _n and WorldMap.is_water(_ground[c.y * _n + c.x])

func _draw() -> void:
	var px := 1.0 / maxf(_zoom, 0.0001)  # один пиксель экрана в мировых единицах
	draw_rect(_view, Color(0.06, 0.08, 0.12, 0.22 * amount))  # пасмурно
	var col := Color(0.78, 0.84, 0.92, 0.35 * amount)
	for d in _drops:
		var a: Vector2 = _view.position + d.p * _view.size
		var b: Vector2 = a + WIND.normalized() * d.len * _view.size.y
		draw_line(a, b, col, 1.2 * px)
	for s in _splash:
		var k: float = s.t / 0.45
		var on_water := _is_water(s.pos)
		var r: float = (2.0 + k * (9.0 if on_water else 5.0)) * px
		var c := Color(0.85, 0.9, 0.97, (0.5 if on_water else 0.35) * (1.0 - k) * amount)
		draw_set_transform(s.pos, 0.0, Vector2(1.0, 0.6))
		draw_arc(Vector2.ZERO, r, 0, TAU, 14, c, 1.0 * px, true)
		draw_set_transform_matrix(Transform2D.IDENTITY)
