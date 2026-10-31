class_name SpaceScene
extends Node2D
## Космос в 3D: планеты-диски висят на месте, камера летает вокруг выбранной — перетаскивание мышью
## крутит её как угодно, колёсико — ближе/дальше. Вдали солнце (тоже шар). Внизу — выбор диска:
## камера отлетает от одной планеты и подлетает к другой. «Войти» — камера приближается, на планете
## проступают очертания городов (папок верхнего уровня); клик по городу — посадка на его карту.

# Фейковые диски (реальный диск не читаем)
const DISKS := [
	{"name": "C:", "gb": 256},
	{"name": "D:", "gb": 1024},
]
const GAP := 30.0           # расстояние между поверхностями планет
const FLY_TIME := 2.6       # перелёт между планетами, с
const SUN_DIR := Vector3(0.8, 0.12, -0.6)   # куда смотреть на солнце (от планет)
const SUN_DIST := 700.0
const VIEW_DIR := Vector3(0.45, 0.3, 1.0)    # откуда камера смотрит на планету: освещено ~40%, солнце справа за кадром
const NEAR := 4.0                            # обычное расстояние камеры, в радиусах планеты
const DRAG_PX := 6.0        # сдвиг мыши, после которого это вращение, а не клик
const CITY_VIEW := 2.1      # расстояние камеры при выборе города, в радиусах планеты
const HINT := "Перетаскивание — крутить камеру · колёсико — ближе/дальше · ←/→ — другой диск"

const CONTINENT := preload("res://scenes/continent.tscn")
var continent: Node = null  # открытый материк (вид сверху)

var planets: Array[Globe] = []
var target: Globe = null    # планета, вокруг которой камера
var busy := false           # идёт анимация
var _world: Node3D
var _wenv: WorldEnvironment
var _env: Environment
var _cam: Camera3D
var _orbit := Basis()       # поворот камеры вокруг планеты
var _focus := Vector3.ZERO
var _dist := 10.0
var _dist_goal := 10.0
var _spin := Vector2.ZERO   # скорость вращения после броска мышью
var _drag := false
var _press := Vector2.ZERO
var _moved := 0.0
var _ui: Control
var _enter: Button
var _card: PanelContainer
var _card_text: Label
var _bar: HBoxContainer
var _names := {}            # Globe -> Label с именем под планетой
var _fade: ColorRect
var _fade_text: Label
var _fade_tip: Label
const TIPS := [
	"Совет: F1 — все клавиши управления.",
	"Совет: I — статистика города: какие файлы занимают больше всего места.",
	"Совет: T — семейное древо: папка — родитель, всё внутри — её дети.",
	"Совет: цвет одежды жителя — тип файла.",
	"Совет: в дождь жители сидят по домам.",
	"Совет: клик по мини-карте переносит камеру.",
	"Совет: Ctrl+F — найти любой файл или папку.",
	"Совет: F12 — снимок экрана.",
]
var _back: Button
var _hint: Label
var _picking := false       # выбираем город на планете
var _sites: Array = []      # города планеты (CitySites)
var _site_labels: Array[Label] = []
var _hover := -1            # город под мышью

## Радиус растёт умеренно: корень 4-й степени от объёма.
static func radius_for(gb: float) -> float:
	return 5.0 * pow(gb / 256.0, 0.25)

## Планеты в ряд вдоль x, по центру, без наложений.
static func layout(disks: Array) -> Array:
	var out := []
	var x := 0.0
	for d in disks:
		var r := radius_for(d.gb)
		out.append({"name": d.name, "gb": d.gb, "pos": Vector3(x + r, 0, 0), "radius": r})
		x += r * 2 + GAP
	var shift := (x - GAP) / 2
	for o in out:
		o.pos -= Vector3(shift, 0, 0)
	return out

func _ready() -> void:
	Game.play_music("space")
	_build_world()
	_build_ui()
	for info in layout(Game.disks):  # «Мои диски» или выдуманные диски песочницы
		var p := Globe.new()
		_world.add_child(p)
		p.position = info.pos
		p.setup(info.name, info.radius, info.gb)
		p.set_sun((SUN_DIR.normalized() * SUN_DIST - p.position).normalized())
		p.face_land(VIEW_DIR.normalized() * 1.6 + SUN_DIR.normalized())  # материк — на светлой стороне к камере
		planets.append(p)
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 6)
		l.text = "%s\n%s" % [p.disk_name, Planet.format_size(p.disk_gb)]
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui.add_child(l)
		_names[p] = l
		var b := Button.new()
		b.text = "  %s   %s  " % [p.disk_name, Planet.format_size(p.disk_gb)]
		b.toggle_mode = true
		b.custom_minimum_size.y = 44
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_fly_to.bind(p))
		_bar.add_child(b)
	_select(planets[0])
	_focus = target.position
	_orbit = _view_basis()
	_dist = target.radius * NEAR
	_dist_goal = _dist
	_update_cam()

## Небо со звёздами, солнце вдали (шар и сияние), свет, камера.
func _build_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/space_sky.gdshader")
	sky_mat.set_shader_parameter("sun_dir", SUN_DIR.normalized())
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.08, 0.09, 0.12)
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_env.glow_enabled = true
	_env.glow_intensity = 0.9
	_env.glow_hdr_threshold = 1.2
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_wenv = WorldEnvironment.new()
	_wenv.environment = _env
	_world.add_child(_wenv)
	var light := DirectionalLight3D.new()  # для луны
	light.light_energy = 1.3
	_world.add_child(light)
	light.look_at_from_position(SUN_DIR.normalized() * 10.0, Vector3.ZERO)
	var sun_pos := SUN_DIR.normalized() * SUN_DIST
	var sun := MeshInstance3D.new()
	sun.mesh = Globe._sphere(34.0, 48, 24)
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/sun3d.gdshader")
	sun.material_override = sm
	sun.position = sun_pos
	_world.add_child(sun)
	var corona := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1400, 1400)  # сияние широкое — видно у края экрана, даже когда солнце за кадром
	corona.mesh = quad
	var cm := ShaderMaterial.new()
	cm.shader = preload("res://shaders/corona.gdshader")
	corona.material_override = cm
	corona.position = sun_pos
	corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(corona)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.05
	_cam.far = 3000.0
	_world.add_child(_cam)
	_cam.make_current()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = ContinentUI.make_theme()
	layer.add_child(_ui)
	var menu := Button.new()
	menu.text = "Меню"
	menu.position = Vector2(16, 16)
	menu.add_theme_font_size_override("font_size", 18)
	menu.pressed.connect(_to_menu)
	_ui.add_child(menu)
	_enter = Button.new()
	_enter.text = "Войти"
	_enter.add_theme_font_size_override("font_size", 22)
	_enter.anchor_left = 1.0
	_enter.anchor_right = 1.0
	_enter.anchor_top = 0.5
	_enter.anchor_bottom = 0.5
	_enter.offset_left = -220
	_enter.offset_right = -60
	_enter.offset_top = -26
	_enter.offset_bottom = 26
	_enter.pressed.connect(_approach)
	_ui.add_child(_enter)
	ContinentUI.make_primary(_enter)
	# карточка диска над «Войти»: имя, объём, сколько городов и жителей
	_card = PanelContainer.new()
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.anchor_top = 0.5
	_card.anchor_bottom = 0.5
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.offset_left = -60
	_card.offset_right = -60
	_card.offset_top = -40
	_card.offset_bottom = -40
	_card.custom_minimum_size.x = 160
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_card)
	_card_text = Label.new()
	_card_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_card_text.add_theme_font_size_override("font_size", 14)
	_card.add_child(_card_text)
	_enter.visibility_changed.connect(func(): _card.visible = _enter.visible)
	_back = Button.new()
	_back.text = "◀ К планетам"
	_back.add_theme_font_size_override("font_size", 18)
	_back.position = Vector2(110, 16)
	_back.visible = false
	_back.pressed.connect(_leave_cities)
	_ui.add_child(_back)
	# выбор диска внизу по центру
	var bp := PanelContainer.new()
	bp.anchor_left = 0.5
	bp.anchor_right = 0.5
	bp.anchor_top = 1.0
	bp.anchor_bottom = 1.0
	bp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bp.offset_bottom = -16
	_ui.add_child(bp)
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 8)
	bp.add_child(_bar)
	_hint = Label.new()
	_hint.text = I18n.t(HINT)
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.modulate.a = 0.55
	_hint.position = Vector2(16, 64)
	_ui.add_child(_hint)
	# затемнение для нырка на планету и обратно (поверх всего)
	var fl := CanvasLayer.new()
	fl.layer = 20
	add_child(fl)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.03, 0.08, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_child(_fade)
	_fade_text = Label.new()
	_fade_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fade_text.add_theme_font_size_override("font_size", 30)
	_fade_text.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	_fade_text.modulate.a = 0.0
	fl.add_child(_fade_text)
	# совет внизу, пока строится город (гаснет вместе с надписью)
	_fade_tip = Label.new()
	_fade_tip.anchor_left = 0.5
	_fade_tip.anchor_right = 0.5
	_fade_tip.anchor_top = 1.0
	_fade_tip.anchor_bottom = 1.0
	_fade_tip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_fade_tip.offset_top = -110
	_fade_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_tip.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_fade_tip.add_theme_font_size_override("font_size", 16)
	_fade_tip.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92, 0.75))
	_fade_text.add_child(_fade_tip)

## В главное меню.
func _to_menu() -> void:
	Game.switch(self, "res://scenes/menu.tscn")

## Вид на планету после перелёта: чуть сверху, солнце сбоку-сзади.
static func _view_basis() -> Basis:
	return Basis.looking_at(-VIEW_DIR.normalized(), Vector3.UP)

func _select(p: Globe) -> void:
	target = p
	for i in planets.size():
		planets[i].selected = planets[i] == p
		(_bar.get_child(i) as Button).set_pressed_no_signal(planets[i] == p)
	var root = Game.disk_root(p.disk_name)
	var folders := [0]
	var count := func(f, me: Callable) -> void:
		folders[0] += 1
		for c in f.children:
			me.call(c, me)
	count.call(root, count)
	_card_text.text = "%s  ·  %s\n%s\n%s\n%s" % [p.disk_name, Planet.format_size(p.disk_gb),
		I18n.t("городов: %d") % root.children.size(), I18n.t("папок: %d") % (folders[0] - 1),
		I18n.t("жителей: %d") % root.total_files()]

func _update_cam() -> void:
	_cam.transform = Transform3D(_orbit, _focus + _orbit.z * _dist)

func _process(delta: float) -> void:
	if continent != null:
		return
	if not busy:
		# бросок мышью — камера ещё немного крутится; колёсико — плавно
		if not _drag and _spin.length() > 0.001:
			_rotate(_spin * delta)
			_spin = _spin.lerp(Vector2.ZERO, 1.0 - exp(-3.0 * delta))
		_dist = lerpf(_dist, _dist_goal, 1.0 - exp(-8.0 * delta))
	_update_cam()
	# наведение мыши на планету
	var m := get_viewport().get_mouse_position()
	var o := _cam.project_ray_origin(m)
	var d := _cam.project_ray_normal(m)
	var over := _planet_at(o, d)
	for p in planets:
		p.hovered = p == over and not busy and not _picking
	if _picking:
		_update_sites(o, d)
	# имена под другими планетами (выбранная — на кнопке внизу)
	for p in planets:
		var l: Label = _names[p]
		var at := p.position - _cam.global_basis.y * p.radius * 1.18
		l.visible = p != target and not _cam.is_position_behind(at) and not busy
		if l.visible:
			l.size = Vector2.ZERO
			l.position = _cam.unproject_position(at) - Vector2(l.get_combined_minimum_size().x / 2.0, 0)

## Выбор города: какой под мышью (луч o, d), подписи городов на видимой стороне планеты.
func _update_sites(o: Vector3, d: Vector3) -> void:
	var hover := -1
	var t := target.hit(o, d)
	if t > 0.0 and not busy:
		var local := target.to_local(o + d * t).normalized()
		var best := INF
		for i in _sites.size():
			var a: float = local.angle_to(_sites[i].dir)
			if a < _sites[i].r * 1.25 and a < best:
				best = a
				hover = i
	if hover != _hover:
		_hover = hover
		target.set_hover_site(hover)
	var cam_pos := _cam.global_position
	for i in _site_labels.size():
		var l := _site_labels[i]
		var at := target.surface(_sites[i].dir, 1.02)
		var facing := (at - target.global_position).normalized().dot((cam_pos - at).normalized())
		l.visible = facing > 0.15 and not busy
		if l.visible:
			l.modulate = Color(1.0, 0.9, 0.5) if i == _hover else Color(1, 1, 1, clampf(facing * 2.5, 0.0, 1.0))
			l.size = Vector2.ZERO
			l.position = _cam.unproject_position(at) - l.get_combined_minimum_size() / 2.0

func _planet_at(o: Vector3, d: Vector3) -> Globe:
	var best: Globe = null
	var bt := INF
	for p in planets:
		var t := p.hit(o, d)
		if t > 0.0 and t < bt:
			bt = t
			best = p
	return best

## Повернуть камеру вокруг планеты: v.x — вокруг её вертикали, v.y — вокруг горизонтали (рад).
func _rotate(v: Vector2) -> void:
	_orbit = Basis(_orbit.y, -v.x) * _orbit
	_orbit = Basis(_orbit.x, -v.y) * _orbit
	_orbit = _orbit.orthonormalized()

## Сколько радиан поворота на пиксель: вблизи медленнее.
func _rad_per_px() -> float:
	return 0.0055 * clampf((_dist - target.radius) / (target.radius * 2.4), 0.15, 1.5)

func _unhandled_input(event: InputEvent) -> void:
	if busy or continent != null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				var k := 1.0 / 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.12
				_dist_goal = clampf(_dist_goal * k, target.radius * 1.35, target.radius * 9.0)
			return
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_drag = true
				_press = event.position
				_moved = 0.0
				_spin = Vector2.ZERO
			else:
				_drag = false
				if _moved < DRAG_PX and event.button_index == MOUSE_BUTTON_LEFT:
					if _picking and _hover >= 0:
						_dive_city(_hover)
						return
					var p := _planet_at(_cam.project_ray_origin(event.position), _cam.project_ray_normal(event.position))
					if p != null and p != target:
						_fly_to(p)
				elif _moved < DRAG_PX and _picking:
					_leave_cities()  # правый клик — назад к планетам
			return
	if event is InputEventMouseMotion and _drag:
		_moved += event.relative.length()
		if _moved >= DRAG_PX:
			var v: Vector2 = event.relative * _rad_per_px()
			_rotate(v)
			_spin = _spin.lerp(v / maxf(get_process_delta_time(), 0.001), 0.5)
		return
	if event is InputEventKey and event.pressed and (event.keycode == KEY_LEFT or event.keycode == KEY_RIGHT):
		var i := planets.find(target) + (1 if event.keycode == KEY_RIGHT else -1)
		_fly_to(planets[(i + planets.size()) % planets.size()])
	elif event.is_action_pressed("ui_cancel"):
		if _picking:
			_leave_cities()
		else:
			_to_menu()
	elif event.is_action_pressed("ui_accept") and not _picking:
		_approach()

## Перелёт к другой планете: камера отлетает назад, поворачивается к виду «солнце сбоку» и подлетает.
func _fly_to(p: Globe) -> void:
	if busy or p == target:
		_select(target)  # кнопку текущего диска не отжимаем
		return
	if _picking:
		_leave_cities(true)
	busy = true
	_spin = Vector2.ZERO
	_enter.visible = false
	var a_focus := _focus
	var b_focus := p.position
	var a_dist := _dist
	var b_dist := p.radius * NEAR
	var a_q := _orbit.get_rotation_quaternion()
	var b_q := _view_basis().get_rotation_quaternion()
	var span := a_focus.distance_to(b_focus)
	_select(p)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var e := smoothstep(0.0, 1.0, t)
		_focus = a_focus.lerp(b_focus, e)
		_dist = lerpf(a_dist, b_dist, e) + sin(PI * t) * span * 0.75
		_orbit = Basis(a_q.slerp(b_q, smoothstep(0.0, 0.55, t))),
		0.0, 1.0, FLY_TIME)
	tw.tween_callback(func():
		busy = false
		_dist_goal = _dist
		_enter.visible = true)

## «Войти»: камера приближается к планете, проступают очертания городов — выбирай, куда садиться.
func _approach() -> void:
	if busy or target == null or _picking:
		return
	busy = true
	_spin = Vector2.ZERO
	_enter.visible = false
	_sites = Game.city_sites(target.disk_name)
	target.show_sites(_sites)
	target.show_moon(false)
	for s in _sites:
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 6)
		l.text = "%s\n%s" % [s.folder.name, I18n.t("жителей: %d") % s.folder.total_files()]
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui.add_child(l)
		_site_labels.append(l)
	# камера разворачивается к городам (к середине суши с ними)
	var mid := Vector3.ZERO
	for s in _sites:
		mid += target.surface(s.dir) - target.global_position
	var a_q := _orbit.get_rotation_quaternion()
	var b_q := a_q
	if mid.length() > 0.01:
		b_q = Basis.looking_at(-mid.normalized(), _orbit.y).get_rotation_quaternion()
	var a_dist := _dist
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var e := smoothstep(0.0, 1.0, t)
		_orbit = Basis(a_q.slerp(b_q, e))
		_dist = lerpf(a_dist, target.radius * CITY_VIEW, e), 0.0, 1.0, 1.2)
	tw.tween_callback(func():
		busy = false
		_dist_goal = _dist
		_picking = true
		_back.visible = true
		_hint.text = I18n.t("Выбери город — клик по нему · перетаскивание — крутить планету · Esc / ПКМ — назад"))

## Назад от выбора города к виду на планету (instant — без анимации, перед перелётом к другой).
func _leave_cities(instant := false) -> void:
	_picking = false
	_hover = -1
	target.set_hover_site(-1)
	target.show_sites([])
	target.show_moon(true)
	for l in _site_labels:
		l.queue_free()
	_site_labels.clear()
	_back.visible = false
	_hint.text = I18n.t(HINT)
	if instant:
		return
	_dist_goal = target.radius * NEAR
	_enter.visible = true

## Посадка в город: камера встаёт над ним и ныряет, экран темнеет; пока строится карта — «Посадка…».
func _dive_city(i: int) -> void:
	if busy:
		return
	busy = true
	_back.visible = false
	var s: Dictionary = _sites[i]
	var up := target.surface(s.dir) - target.global_position
	var a_q := _orbit.get_rotation_quaternion()
	var b_q := Basis.looking_at(-up.normalized(), Vector3.UP if absf(up.normalized().y) < 0.95 else Vector3.RIGHT).get_rotation_quaternion()
	var a_dist := _dist
	target.spin_up()
	_fade_text.text = I18n.t("Посадка в город «%s»…") % s.folder.name
	_fade_tip.text = I18n.t(TIPS[randi() % TIPS.size()])
	var tw := create_tween().set_parallel()
	tw.tween_method(func(t: float):
		_orbit = Basis(a_q.slerp(b_q, smoothstep(0.0, 0.6, t)))
		_dist = lerpf(a_dist, target.radius * 1.03, pow(t, 2.2)), 0.0, 1.0, 1.6)
	tw.tween_property(_fade, "color:a", 1.0, 0.45).set_delay(1.2)
	tw.tween_property(_fade_text, "modulate:a", 1.0, 0.3).set_delay(1.3)
	tw.chain().tween_callback(_land.bind(s))

func _land(s: Dictionary) -> void:
	_open_continent(s)
	if continent.is_built:
		_landed()
	else:
		continent.built.connect(_landed, CONNECT_ONE_SHOT)

## Город готов: затемнение уходит, камера карты опускается сверху.
func _landed() -> void:
	busy = false
	var ccam: Camera2D = continent.cam
	var z := ccam.zoom
	ccam.zoom = z * 0.45
	var tw := create_tween().set_parallel()
	tw.tween_property(ccam, "zoom", z, 1.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_fade, "color:a", 0.0, 0.7)
	tw.tween_property(_fade_text, "modulate:a", 0.0, 0.3)

## Карта города s сверху вместо космоса.
func _open_continent(s: Dictionary) -> void:
	continent = CONTINENT.instantiate()
	continent.disk_name = target.disk_name
	continent.disk_gb = target.disk_gb
	continent.site = s
	continent.exit_requested.connect(_leave)
	_show_space(false)
	add_child(continent)

## Назад из города на планету — к выбору города: экран темнеет, камера «взлетает» над городом.
func _leave() -> void:
	if busy:
		return
	busy = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.3)
	tw.tween_callback(_leave_now)

func _leave_now() -> void:
	continent.queue_free()
	continent = null
	_show_space(true)
	Game.play_music("space")
	_cam.make_current()
	target.spin_up()
	_dist = target.radius * 1.08
	_dist_goal = target.radius * CITY_VIEW
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "_dist", _dist_goal, 1.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_fade, "color:a", 0.0, 0.5)
	tw.chain().tween_callback(func():
		busy = false
		_back.visible = _picking  # снова выбор города
		_enter.visible = not _picking)

func _show_space(v: bool) -> void:
	_world.visible = v
	_wenv.environment = _env if v else null  # в городе звёздное небо не нужно
	_ui.visible = v

## Для скриншотов: space — вид на C:; planet — перелёт к последней; fly — середина перелёта;
## cities — выбор города; dive — середина посадки в город; sun — камера повёрнута к солнцу;
## иначе сразу в первый город (map / city / house ...).
func debug_view(view: String) -> void:
	match view:
		"space":
			return
		"planet", "fly":
			_fly_to(planets[-1])
			_step(FLY_TIME * (0.5 if view == "fly" else 1.1))
		"cities", "dive":
			_approach()
			_step(1.3)
			_hover = 0
			target.set_hover_site(0)
			if view == "dive":
				_dive_city(0)
				_step(1.25)
		"sun":
			_rotate(Vector2(0.75, 0.05))
			_dist_goal = target.radius * 4.5
			_dist = _dist_goal
		_:
			# «river» — город, через который течёт река (на любом диске)
			var site: Dictionary = Game.city_sites(target.disk_name)[0]
			if view == "river":
				for p in planets:
					for s in Game.city_sites(p.disk_name):
						if s.env.through and site.env.get("through") != true:
							site = s
							target = p
			_open_continent(site)
			continent.debug_view(view)

func _step(sec: float) -> void:
	for t in get_tree().get_processed_tweens():
		t.custom_step(sec)
