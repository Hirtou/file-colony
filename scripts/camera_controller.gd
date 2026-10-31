extends Camera2D
## WASD — движение, колёсико — приближение.

@export var speed := 600.0
@export var zoom_step := 1.1
@export var min_zoom := 0.05
@export var max_zoom := 5.0
## Куда можно смотреть (мировые координаты); пусто — без ограничений. Центр кадра не уходит
## за этот прямоугольник, а отдалить можно, пока он целиком помещается в кадр (с запасом).
var bounds := Rect2()

func _process(delta: float) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		_clamp()
		return  # печатают в поиске — WASD не двигает камеру
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): dir.y -= 1
	if Input.is_key_pressed(KEY_S): dir.y += 1
	if Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_key_pressed(KEY_D): dir.x += 1
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
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(zoom.x * zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(zoom.x / zoom_step)

func _set_zoom(z: float) -> void:
	z = clampf(z, min_zoom, max_zoom)
	zoom = Vector2(z, z)
