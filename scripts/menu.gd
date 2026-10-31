extends Node2D
## Главное меню: «Мои диски», «Песочница», «Настройки», «Выход».
## Фон — 3D-космос как в игре: звёздное небо, далёкое солнце и медленно вращающаяся планета.
## Всё выдуманное, файлы не читаются.

const SPACE := "res://scenes/space.tscn"
const VERSION := "0.3"
const SUN_DIR := Vector3(-0.9, 0.3, 0.3)  # солнце слева сбоку — освещена сторона к заголовку
const CAM_SHIFT := -2.6      # планета правее центра; с открытой панелью — ещё правее
const CAM_SHIFT_PANEL := -4.6

var _globe: Globe
var _cam: Camera3D
var _sandbox: PanelContainer
var _settings: PanelContainer
var _seed: LineEdit
var _count: SpinBox
var _preview: Label
var _tw: Tween
static var _reopen := ""  # после смены языка меню перестраивается — снова открыть эту панель

func _ready() -> void:
	_build_world()
	_build_ui()
	Game.play_music("space")
	if _reopen != "":
		_toggle(_reopen)
		_tw.custom_step(5.0)
		_reopen = ""

## 3D-фон: небо со звёздами (тот же шейдер, что в космосе), солнце за кадром слева, планета C:.
func _build_world() -> void:
	var world := Node3D.new()
	add_child(world)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/space_sky.gdshader")
	sky_mat.set_shader_parameter("sun_dir", SUN_DIR.normalized())
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.08, 0.09, 0.12)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var wenv := WorldEnvironment.new()
	wenv.environment = env
	world.add_child(wenv)
	var light := DirectionalLight3D.new()
	light.light_energy = 1.3
	world.add_child(light)
	light.look_at_from_position(SUN_DIR.normalized() * 10.0, Vector3.ZERO)
	_globe = Globe.new()
	world.add_child(_globe)
	_globe.setup("C:", 5.0, 256)
	_globe.set_sun(SUN_DIR.normalized())
	_globe.face_land(Vector3(-0.2, 0.25, 1.0) + SUN_DIR.normalized() * 0.6)
	_globe.show_moon(false)  # луна близко к камере закрыла бы полэкрана
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.h_offset = CAM_SHIFT
	world.add_child(_cam)
	_cam.look_at_from_position(Vector3(-2.2, 2.0, 16.5), Vector3.ZERO)
	_cam.make_current()

func _process(delta: float) -> void:
	_globe.rotate_y(delta * 0.035)  # планета медленно вращается

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ContinentUI.make_theme()
	layer.add_child(root)

	# слева — затемнение под текстом, чтобы он читался на любом фоне
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.025, 0.04, 0.85))
	grad.set_color(1, Color(0.02, 0.025, 0.04, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.anchor_bottom = 1.0
	shade.offset_right = 620
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	# заголовок и кнопки слева, по центру высоты
	var col := VBoxContainer.new()
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.offset_left = 90
	col.add_theme_constant_override("separation", 12)
	root.add_child(col)
	var kicker := _label(col, "FILE COLONY" if not I18n.en() else "ФАЙЛОВАЯ КОЛОНИЯ", 14)
	kicker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	kicker.add_theme_color_override("font_color", ContinentUI.ACCENT)
	kicker.add_theme_constant_override("line_spacing", 0)
	var title := _label(col, "ФАЙЛОВАЯ\nКОЛОНИЯ", 60)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.86))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("line_spacing", -12)
	var line := ColorRect.new()
	line.color = ContinentUI.ACCENT
	line.custom_minimum_size = Vector2(64, 3)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(line)
	_label(col, "твои папки — города, файлы — жители", 18).modulate.a = 0.75
	var gap := Control.new()
	gap.custom_minimum_size.y = 22
	col.add_child(gap)
	ContinentUI.make_primary(_button(col, "Мои диски", _my_disks))
	_button(col, "Песочница", _toggle.bind("sandbox"))
	_button(col, "Настройки", _toggle.bind("settings"))
	_button(col, "Выход", func(): get_tree().quit())

	_sandbox = _make_sandbox(root)
	_settings = _make_settings(root)

	var note := _label(root, "Все диски, папки и файлы выдуманные — настоящие файлы не читаются и не меняются.", 13)
	note.modulate.a = 0.5
	note.anchor_top = 1.0
	note.anchor_bottom = 1.0
	note.offset_left = 90
	note.offset_top = -40
	var ver := _label(root, "v" + VERSION, 13)
	ver.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ver.modulate.a = 0.4
	ver.anchor_left = 1.0
	ver.anchor_right = 1.0
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.offset_left = -24
	ver.offset_right = -24
	ver.offset_top = -40

# --- песочница ---

func _make_sandbox(root: Control) -> PanelContainer:
	var p := _panel(root)
	var v := _vbox(p)
	_label(v, "Песочница", 26)
	var info := _label(v, "Выдуманный мир по зерну: одно и то же зерно — один и тот же мир. Зерно — число или любое слово.", 14)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.modulate.a = 0.8
	var row := HBoxContainer.new()
	v.add_child(row)
	_label(row, "Зерно:", 16).custom_minimum_size.x = 80
	_seed = LineEdit.new()
	_seed.text = str(randi_range(1, 999999))
	_seed.custom_minimum_size.x = 150
	_seed.text_changed.connect(func(_t): _update_preview())
	row.add_child(_seed)
	var dice := Button.new()
	dice.text = "Случайное"
	dice.pressed.connect(func():
		_seed.text = str(randi_range(1, 999999))
		_update_preview())
	row.add_child(dice)
	var row2 := HBoxContainer.new()
	v.add_child(row2)
	_label(row2, "Планет:", 16).custom_minimum_size.x = 80
	_count = SpinBox.new()
	_count.min_value = 1
	_count.max_value = 5
	_count.value = 3
	_count.value_changed.connect(func(_v): _update_preview())
	row2.add_child(_count)
	_preview = _label(v, "", 15)
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_button(v, "Создать мир", _start_sandbox)
	_update_preview()
	return p

func _seed_value() -> int:
	var t := _seed.text.strip_edges()
	return int(t) if t.is_valid_int() else absi(t.hash())

func _update_preview() -> void:
	var parts := []
	for d in Game.sandbox_disks(_seed_value(), int(_count.value)):
		parts.append("%s %s" % [d.name, Planet.format_size(d.gb)])
	_preview.text = I18n.t("Планеты: ") + ", ".join(parts)

func _start_sandbox() -> void:
	Game.use_sandbox(_seed_value(), int(_count.value))
	Game.switch(self, SPACE)

func _my_disks() -> void:
	Game.use_my_disks()
	Game.switch(self, SPACE)

# --- настройки ---

func _make_settings(root: Control) -> PanelContainer:
	var p := _panel(root)
	var v := _vbox(p)
	_label(v, "Настройки", 26)
	var rl := HBoxContainer.new()
	v.add_child(rl)
	_label(rl, "Язык / Language", 16).custom_minimum_size.x = 170
	var lang := OptionButton.new()
	lang.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for n in I18n.LANG_NAMES:
		lang.add_item(n)
	lang.selected = I18n.LANGS.find(I18n.lang())
	lang.item_selected.connect(_set_lang)
	rl.add_child(lang)
	_check(v, "Полный экран", "fullscreen")
	_check(v, "Вертикальная синхронизация", "vsync")
	_check(v, "Показывать FPS", "show_fps")
	_check(v, "Смена дня и ночи", "day_night")
	_check(v, "Тени от домов и деревьев", "shadows")
	_check(v, "Погода (дождь)", "weather")
	var row := HBoxContainer.new()
	v.add_child(row)
	_label(row, "Скорость камеры", 16).custom_minimum_size.x = 170
	var cam := HSlider.new()
	cam.min_value = 300
	cam.max_value = 1500
	cam.step = 50
	cam.value = Game.settings.cam_speed
	cam.custom_minimum_size.x = 170
	cam.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cam.value_changed.connect(func(x): Game.set_setting("cam_speed", x))
	row.add_child(cam)
	var rm := HBoxContainer.new()
	v.add_child(rm)
	_label(rm, "Музыка", 16).custom_minimum_size.x = 170
	var mus := HSlider.new()
	mus.min_value = 0
	mus.max_value = 100
	mus.step = 5
	mus.value = Game.settings.music
	mus.custom_minimum_size.x = 170
	mus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mus.value_changed.connect(func(x): Game.set_setting("music", x))
	rm.add_child(mus)
	var row2 := HBoxContainer.new()
	v.add_child(row2)
	_label(row2, "Скорость времени", 16).custom_minimum_size.x = 170
	var speed := OptionButton.new()
	for s in Game.TIME_SPEEDS:
		speed.add_item("×%d" % s)
	speed.selected = Game.settings.time_speed
	speed.item_selected.connect(func(i): Game.set_setting("time_speed", i))
	row2.add_child(speed)
	_button(v, "Готово", _toggle.bind(""))
	return p

## Сменить язык: выдуманные миры строятся заново (имена папок на новом языке), меню — тоже.
func _set_lang(i: int) -> void:
	Game.set_setting("lang", I18n.LANGS[i])
	Game.forget_worlds()
	_reopen = "settings"
	get_tree().reload_current_scene()

func _check(parent: Control, text: String, key: String) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = Game.settings[key]
	c.add_theme_font_size_override("font_size", 16)
	c.toggled.connect(func(on): Game.set_setting(key, on))
	parent.add_child(c)

# --- общее ---

## Открыть панель (sandbox / settings), повторное нажатие или "" — закрыть; планета отъезжает вправо.
func _toggle(which: String) -> void:
	var open_sandbox := which == "sandbox" and not _sandbox.visible
	var open_settings := which == "settings" and not _settings.visible
	_sandbox.visible = open_sandbox
	_settings.visible = open_settings
	if _tw:
		_tw.kill()
	_tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_property(_cam, "h_offset", CAM_SHIFT_PANEL if open_sandbox or open_settings else CAM_SHIFT, 0.6)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (_sandbox.visible or _settings.visible):
		_toggle("")

func _panel(root: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.anchor_top = 0.5  # по центру высоты — высокая панель не уходит за низ экрана
	p.anchor_bottom = 0.5
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.offset_left = 520
	p.offset_right = 520
	p.custom_minimum_size.x = 440
	p.visible = false
	root.add_child(p)
	return p

func _vbox(p: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	return v

func _label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l

func _button(parent: Control, text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 50)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(fn)
	parent.add_child(b)
	return b

## Для скриншотов: menu / sandbox / settings; иное — «Мои диски» и дальше вид космоса/материка.
func debug_view(view: String) -> void:
	if view == "menu":
		return
	if view == "sandbox" or view == "settings":
		_toggle(view)
		if _tw:
			_tw.custom_step(5.0)
		return
	if view.begins_with("sandbox_"):
		Game.use_sandbox(12345, 5)  # sandbox_space / sandbox_map — песочница из 5 планет
		view = view.trim_prefix("sandbox_")
	else:
		Game.use_my_disks()
	var space := Game.switch(self, SPACE)
	space.debug_view(view)
