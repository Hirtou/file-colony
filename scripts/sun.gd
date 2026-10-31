extends Node2D
## Солнце вдалеке слева (рисуется в экранных координатах, на своём слое под миром).
## Оно далеко, поэтому при движении камеры смещается медленно (параллакс), а при приближении
## почти не растёт. Корона мягко «дышит», лучи медленно вращаются.
## center — где солнце сейчас на экране (по нему планеты считают, откуда свет).

const PARALLAX := 0.2  # насколько сдвигается за камерой (1 — как планеты, 0 — стоит на месте)
const GROW := 0.12       # насколько растёт при приближении (степень)

var center := Vector2.ZERO
var _t := 0.0
var _k := 1.0            # во сколько раз солнце выросло от приближения
var _home = null         # с чего начинала камера: [центр, масштаб]

func _process(delta: float) -> void:
	_t += delta
	var vp := get_viewport_rect().size
	var base := Vector2(-260, vp.y * 0.5)
	var k := 1.0
	var cam := get_viewport().get_camera_2d()
	if cam:
		var c := cam.get_screen_center_position()
		if _home == null:
			_home = [c, cam.zoom.x]
		# камера ушла вправо — солнце чуть уехало влево (оно далеко)
		base -= (c - _home[0]) * cam.zoom.x * PARALLAX
		k = pow(cam.zoom.x / _home[1], GROW)
	center = base
	_k = k
	queue_redraw()

func _draw() -> void:
	var h := get_viewport_rect().size.y
	var c := center
	var breathe := 1.0 + sin(_t * 0.8) * 0.025
	# свечение: много полупрозрачных кругов = радиальный градиент
	for i in 40:
		draw_circle(c, lerpf(h * 0.9, 300.0, i / 39.0) * _k * breathe, Color(1.0, 0.85, 0.55, 0.025))
	# лучи короны медленно вращаются
	for i in 12:
		var a := _t * 0.05 + TAU * i / 12.0
		var len := (420.0 + 60.0 * sin(_t * 1.3 + i * 1.7)) * _k
		var dir := Vector2.from_angle(a)
		var side := dir.orthogonal() * 40.0 * _k
		draw_colored_polygon(PackedVector2Array([c + side, c + dir * len, c - side]), Color(1.0, 0.9, 0.6, 0.05))
	draw_circle(c, 300 * _k, Color(1.0, 0.92, 0.7, 0.35))
	draw_circle(c, 290 * _k, Color(1.0, 0.97, 0.85))
