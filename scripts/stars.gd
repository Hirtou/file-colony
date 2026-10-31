extends Node2D
## Звёздный фон: случайные точки с фиксированным seed. Звёзды очень далеко: при движении камеры
## сдвигаются слабо (параллакс), при приближении почти не растут; часть тихо мерцает.

const PARALLAX := 0.05
const GROW := 0.1

var _home = null   # [центр камеры, масштаб] в начале
var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var c := cam.get_screen_center_position()
	var z := cam.zoom.x
	if _home == null:
		_home = [c, z]
	# на экране звезда p стоит в (p - сдвиг) * zf от центра: zf почти не меняется с приближением
	var zf: float = _home[1] * pow(z / _home[1], GROW)
	var shift: Vector2 = (c - _home[0]) * PARALLAX
	scale = Vector2.ONE * zf / z
	position = c - shift * zf / z
	queue_redraw()

func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 500:
		var p := Vector2(rng.randf_range(-1600, 1600), rng.randf_range(-1000, 1000))
		var b := rng.randf_range(0.4, 1.0)
		var r := rng.randf_range(0.8, 2.0)
		if i % 6 == 0:
			b *= 0.7 + 0.3 * sin(_t * rng.randf_range(1.0, 3.0) + i)  # мерцает
		draw_circle(p, r, Color(b, b, b))
