class_name Globe
extends Node3D
## Планета-диск в 3D-космосе: шар с развёрткой (PlanetTexture), облака, огни городов ночью, свечение
## атмосферы, у многих — луна. Планета стоит на месте — крутится камера (SpaceScene).

const SHADER := preload("res://shaders/globe.gdshader")
const ATMO := preload("res://shaders/atmosphere.gdshader")

var disk_name := ""
var disk_gb := 0.0
var radius := 5.0
var hovered := false
var selected := false
var _mat: ShaderMaterial
var _atmo: ShaderMaterial
var _clouds := 0.0
var _cloud_speed := 0.02
var _glow := 0.0
var _moon: MeshInstance3D = null
var _moon_a := 0.0
var _moon_speed := 0.0
var _moon_tilt := 0.0

func setup(n: String, r: float, gb: float) -> void:
	disk_name = n
	radius = r
	disk_gb = gb
	var seed_value := Game.planet_seed(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("albedo_tex", PlanetTexture.get_texture(seed_value))
	_mat.set_shader_parameter("seed", fmod(absf(n.hash()) / 1000.0, 1.0))
	var ball := MeshInstance3D.new()
	ball.mesh = _sphere(r, 128, 64)
	ball.material_override = _mat
	add_child(ball)
	_atmo = ShaderMaterial.new()
	_atmo.shader = ATMO
	_atmo.set_shader_parameter("planet_r", r)
	_atmo.set_shader_parameter("shell_r", r * 1.13)
	var shell := MeshInstance3D.new()
	shell.mesh = _sphere(r * 1.13, 96, 48)
	shell.material_override = _atmo
	add_child(shell)
	_clouds = rng.randf() * TAU
	# луна: у больших дисков всегда, у остальных — через раз
	if gb >= 512 or rng.randf() < 0.5:
		_moon = MeshInstance3D.new()
		_moon.mesh = _sphere(r * 0.14, 32, 16)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.72, 0.71, 0.68)
		m.roughness = 1.0
		_moon.material_override = m
		add_child(_moon)
		_moon_a = rng.randf() * TAU
		_moon_speed = rng.randf_range(0.06, 0.12)
		_moon_tilt = rng.randf_range(-0.35, 0.35)

static func _sphere(r: float, seg: int, rings: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = rings
	return s

func _process(delta: float) -> void:
	_clouds += delta * _cloud_speed
	_cloud_speed = lerpf(_cloud_speed, 0.02, 1.0 - exp(-0.8 * delta))
	_glow = lerpf(_glow, 1.0 if selected else (0.6 if hovered else 0.0), 1.0 - exp(-6.0 * delta))
	_mat.set_shader_parameter("clouds", _clouds)
	_mat.set_shader_parameter("glow", _glow)
	_atmo.set_shader_parameter("glow", _glow * 0.6)
	if _moon:
		_moon_a += _moon_speed * delta
		var p := Vector3(cos(_moon_a), 0.0, sin(_moon_a)) * radius * 1.9
		_moon.position = p.rotated(Vector3.RIGHT, _moon_tilt)

## Повернуть шар так, чтобы середина материка смотрела в сторону want (мир).
func face_land(want: Vector3) -> void:
	var img: Image = (_mat.get_shader_parameter("albedo_tex") as Texture2D).get_image()
	var w := img.get_width()
	var h := img.get_height()
	var sum := Vector3.ZERO
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var c := img.get_pixel(x, y)
			if not (c.b > c.r * 1.15 and c.b > c.g * 0.95):  # не вода (как в шейдере)
				var lon := (x + 0.5) / w * TAU - PI
				var lat := PI / 2 - (y + 0.5) / h * PI
				sum += Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)) * cos(lat)
	if sum.length() > 0.001:
		quaternion = Quaternion(sum.normalized(), want.normalized())

## Откуда светит солнце (направление в мире, от планеты к солнцу).
func set_sun(dir: Vector3) -> void:
	_mat.set_shader_parameter("sun", dir)
	_atmo.set_shader_parameter("sun", dir)

## Нырок на планету: облака несутся быстрее.
func spin_up() -> void:
	_cloud_speed = 1.5

## Луч (из точки o по направлению d) задевает шар? Расстояние до него или -1.
func hit(o: Vector3, d: Vector3) -> float:
	var oc := o - global_position
	var b := oc.dot(d)
	var c := oc.length_squared() - radius * radius
	var disc := b * b - c
	if disc < 0.0:
		return -1.0
	var t := -b - sqrt(disc)
	return t if t > 0.0 else -1.0
