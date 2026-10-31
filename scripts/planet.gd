class_name Planet
extends Node2D
## Одна планета-диск. Шар рисует шейдер (дочерний спрайт): суша, облака (крутятся быстрее),
## огни городов на ночной стороне, блик на воде. Планета чуть парит, у многих есть луна.
## Наведение — светится атмосфера и бегут дуги кольца; выбор — кольцо ярче, клик — «пружинка».

const SHADER := preload("res://shaders/planet.gdshader")
const MAX_TILT := 0.5  # предел наклона, рад

var disk_name := ""
var rot := 0.0          # поворот вокруг оси, рад
var tilt := 0.0         # наклон, рад
var spin_speed := 0.1   # своя скорость самовращения, рад/с
var vel := 0.0          # текущая скорость (инерция после перетаскивания)
var dragging := false
var _prev_rot := 0.0
var _globe: Sprite2D
var _mat: ShaderMaterial
var radius := 100.0
var texture: ImageTexture
var hovered := false:
	set(v):
		if v != hovered:
			hovered = v
			queue_redraw()

var size_text := ""
var disk_gb := 0.0
var show_caption := true  # в главном меню планета без подписи
var selected := false     # к ней приблизились в космосе
var _t := 0.0
var _phase := 0.0         # своя фаза парения
var _clouds := 0.0
var _glow := 0.0
var _pulse := 0.0         # «пружинка» после клика
var _moon: Node2D = null
var _moon_a := 0.0
var _moon_speed := 0.0

func setup(n: String, r: float, gb: float) -> void:
	disk_name = n
	radius = r
	disk_gb = gb
	size_text = format_size(gb)
	var seed_value := Game.planet_seed(n)
	texture = PlanetTexture.get_texture(seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	spin_speed = rng.randf_range(0.06, 0.18)
	vel = spin_speed
	rot = rng.randf() * TAU
	_phase = rng.randf() * TAU
	# луна: у больших дисков всегда, у остальных — через раз
	if _moon == null and (gb >= 512 or rng.randf() < 0.5):
		_moon = Node2D.new()
		_moon.show_behind_parent = true
		_moon.draw.connect(_draw_moon)
		add_child(_moon)
		_moon_a = rng.randf() * TAU
		_moon_speed = rng.randf_range(0.25, 0.45)
	if _globe == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_globe = Sprite2D.new()
		_globe.material = _mat
		_globe.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_globe.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # вблизи берега без «лесенки»
		_globe.show_behind_parent = true  # рамка наведения поверх шара
		add_child(_globe)
	_globe.texture = texture
	# шар занимает 90% квадрата, снаружи — атмосфера
	var half := radius / 0.9
	_globe.scale = Vector2(half * 2 / texture.get_width(), half * 2 / texture.get_height())
	_update_shader()
	queue_redraw()

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	if dragging:
		# запоминаем скорость руки для инерции
		vel = lerpf(vel, (rot - _prev_rot) / delta, 0.3)
	else:
		# инерция плавно затухает до своей медленной скорости
		vel = lerpf(vel, spin_speed, 1.0 - exp(-1.5 * delta))
		rot += vel * delta
	_prev_rot = rot
	_t += delta
	_clouds += delta * 0.05
	_glow = lerpf(_glow, 1.0 if selected else (0.6 if hovered else 0.0), 1.0 - exp(-6.0 * delta))
	_pulse = maxf(0.0, _pulse - delta * 2.5)
	# парение и «пружинка»
	var bob := sin(_t * 0.9 + _phase) * radius * 0.025
	if _globe:
		_globe.position.y = bob
	scale = Vector2.ONE * (1.0 + 0.03 * _glow + 0.07 * sin(_pulse * PI) * _pulse)
	if _moon:
		_moon_a += _moon_speed * delta
		var p := Vector2(cos(_moon_a) * radius * 1.55, sin(_moon_a) * radius * 0.32 + bob - radius * 0.1)
		_moon.position = p
		# за планетой — под шаром, перед ней — поверх
		var behind := sin(_moon_a) < 0.0
		if behind != (_moon.get_index() < _globe.get_index()):
			move_child(_moon, 0 if behind else get_child_count() - 1)
		_moon.queue_redraw()
	_update_shader()
	if hovered or selected or _glow > 0.01:
		queue_redraw()

## Откуда светит солнце: направление на экране (от планеты к солнцу).
func set_sun(dir: Vector2) -> void:
	if _mat and dir.length() > 0.001:
		var d := dir.normalized()
		_mat.set_shader_parameter("sun", Vector3(d.x, -d.y, 0.3))

## Клик по планете — пружинит и быстрее крутится.
func pulse() -> void:
	_pulse = 1.0
	vel += 1.2

## Нырок на планету: раскручивается.
func spin_up() -> void:
	vel = 4.0

## Луна: серый шар с тенью со стороны, противоположной солнцу, и кратерами.
func _draw_moon() -> void:
	var r := radius * 0.13
	_moon.draw_circle(Vector2.ZERO, r + 1.5, Color(0.05, 0.05, 0.08, 0.6))
	_moon.draw_circle(Vector2.ZERO, r, Color(0.78, 0.77, 0.74))
	for c in [[Vector2(-0.35, -0.2), 0.22], [Vector2(0.2, 0.3), 0.16], [Vector2(0.1, -0.45), 0.12]]:
		_moon.draw_circle(c[0] * r, c[1] * r, Color(0.6, 0.59, 0.57))
	# тень: светит слева — правая сторона в тени
	var pts := PackedVector2Array()
	for k in 25:
		var a := -PI / 2 + PI * k / 24.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	for k in 25:
		var a := PI / 2 - PI * k / 24.0
		pts.append(Vector2(cos(a) * 0.25, sin(a)) * r)
	_moon.draw_colored_polygon(pts, Color(0.05, 0.05, 0.1, 0.65))

## Повернуть мышью; v — сдвиг в радиусах планеты на экране.
func drag(v: Vector2) -> void:
	rot -= v.x
	tilt = clampf(tilt + v.y, -MAX_TILT, MAX_TILT)

func _update_shader() -> void:
	if _mat:
		_mat.set_shader_parameter("rot", rot)
		_mat.set_shader_parameter("tilt", tilt)
		_mat.set_shader_parameter("clouds", _clouds)
		_mat.set_shader_parameter("glow", _glow)
		_mat.set_shader_parameter("seed", fmod(absf(disk_name.hash()) / 1000.0, 1.0))

func _draw() -> void:
	var bob := _globe.position.y if _globe else 0.0
	if _glow > 0.01:
		# кольцо из трёх дуг, бегут по кругу; у выбранной — ярче и с точками-«спутниками»
		var a0 := _t * 0.8
		var rr := radius + 10 + sin(_t * 3.0) * 2.0
		var col := Color(1.0, 0.92, 0.6, _glow)
		for k in 3:
			var s := a0 + k * TAU / 3
			draw_arc(Vector2(0, bob), rr, s, s + TAU / 5, 32, col, 3.0, true)
			if selected:
				draw_circle(Vector2(0, bob) + Vector2.from_angle(s + TAU / 5) * rr, 4.0, col)
		if selected:
			draw_arc(Vector2(0, bob), rr + 9, -a0 * 0.6, -a0 * 0.6 + TAU * 0.7, 64, Color(col, 0.35 * _glow), 1.5, true)
	# подпись под планетой (в мировых координатах — масштабируется с камерой)
	if not show_caption:
		return
	var font := ThemeDB.fallback_font
	var w := radius * 4
	var y := radius + 16 + bob
	draw_string(font, Vector2(-w / 2, y + 24), disk_name, HORIZONTAL_ALIGNMENT_CENTER, w, 26)
	draw_string(font, Vector2(-w / 2, y + 44), size_text, HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color(0.75, 0.75, 0.8))

## «256 ГБ», «1 ТБ».
static func format_size(gb: float) -> String:
	if gb >= 1024:
		return "%s %s" % [str(snappedf(gb / 1024.0, 0.1)).trim_suffix(".0"), I18n.t("ТБ")]
	return "%d %s" % [int(gb), I18n.t("ГБ")]

## Точка (в мировых координатах) над планетой?
func has_point(p: Vector2) -> bool:
	return to_local(p).length() <= radius
