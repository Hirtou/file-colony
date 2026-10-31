extends Camera2D
## WASD или стрелки — движение, средняя кнопка мыши — тащить карту, колёсико — приближение к курсору.

@export var speed := 600.0
@export var zoom_step := 1.1
@export var min_zoom := 0.05
@export var max_zoom := 5.0
## Куда можно смотреть (мировые координаты); пусто — без ограничений. Центр кадра не уходит
## за этот прямоугольник, а отдалить можно, пока он целиком помещается в кадр (с запасом).
var bounds := Rect2()
var locked := false   # открыто окно поверх карты (древо, статистика) — камера стоит
var _panning := false

func _process(delta: float) -> void:
	if locked or get_viewport().gui_get_focus_owner() is LineEdit:
		_clamp()
		return  # печатают в поиске — WASD не двигает камеру
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	position += dir.normalized() * speed * delta / zoom.x
	_clamp()

## Ограничить камеру картой (и полёты твинами тоже — они двигают position).
func _clamp() -> void:
	if bounds.size == Vector2.ZERO:
		return
	position = position.clamp(bounds.position, bounds.end)
	var fit := get_viewport_rect().size / (bounds.size * 1.15)
	var zmin := maxf(min_zoom, minf(fit.x, fit.y))
	if zoom.x < zmin:
		zoom = Vector2(zmin, zmin)

func _unhandled_input(event: InputEvent) -> void:
	if locked:
		_panning = false
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(zoom.x * zoom_step, event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(zoom.x / zoom_step, event.position)
	elif event is InputEventMouseMotion and _panning:
		position -= event.relative / zoom.x
		_clamp()

## Новый масштаб; at — точка экрана, которая остаётся на месте (курсор). INF — центр.
func _set_zoom(z: float, at := Vector2.INF) -> void:
	z = clampf(z, min_zoom, max_zoom)
	if at.is_finite():
		var off := at - get_viewport_rect().size / 2
		position += off / zoom.x - off / z  # точка под курсором не уезжает
	zoom = Vector2(z, z)
