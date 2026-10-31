extends Node2D
## Главное меню: «Мои диски», «Песочница», «Настройки», «Выход».
## Фон — звёзды, солнце слева и большая медленно вращающаяся планета. Всё выдуманное, файлы не читаются.

const SPACE := "res://scenes/space.tscn"
const STARS := preload("res://scripts/stars.gd")
const SUN := preload("res://scripts/sun.gd")

var _planet: Planet
var _sandbox: PanelContainer
var _settings: PanelContainer
var _seed: LineEdit
var _count: SpinBox
var _preview: Label
var _tw: Tween

func _ready() -> void:
	var sun_layer := CanvasLayer.new()
	sun_layer.layer = -1
	add_child(sun_layer)
	var sun := Node2D.new()
	sun.set_script(SUN)
	sun_layer.add_child(sun)
	var stars := Node2D.new()
	stars.set_script(STARS)
	add_child(stars)
	_planet = Planet.new()
	_planet.show_caption = false
	add_child(_planet)
	_planet.position = _planet_pos(false)
	_planet.setup("Проводник", 210.0, 0.0)
	_build_ui()

func _planet_pos(panel_open: bool) -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x * (0.86 if panel_open else 0.7), vp.y * 0.52)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ContinentUI.make_theme()
	layer.add_child(root)

	# заголовок и кнопки слева
	var col := VBoxContainer.new()
	col.position = Vector2(90, 110)
	col.add_theme_constant_override("separation", 14)
	root.add_child(col)
	var title := _label(col, "ПРОВОДНИК", 64)
	title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.82))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03))
	title.add_theme_constant_override("outline_size", 10)
	_label(col, "твои папки — города, файлы — жители", 18).modulate.a = 0.75
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	col.add_child(gap)
	_button(col, "Мои диски", _my_disks)
	_button(col, "Песочница", _toggle.bind("sandbox"))
	_button(col, "Настройки", _toggle.bind("settings"))
	_button(col, "Выход", func(): get_tree().quit())

	_sandbox = _make_sandbox(root)
	_settings = _make_settings(root)

	var note := _label(root, "Все диски, папки и файлы выдуманные — настоящие файлы не читаются и не меняются.", 13)
	note.modulate.a = 0.55
	note.anchor_top = 1.0
	note.anchor_bottom = 1.0
	note.offset_left = 90
	note.offset_top = -40

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
	_preview.text = "Планеты: " + ", ".join(parts)

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
	_check(v, "Полный экран", "fullscreen")
	_check(v, "Вертикальная синхронизация", "vsync")
	_check(v, "Показывать FPS", "show_fps")
	_check(v, "Смена дня и ночи", "day_night")
	_check(v, "Тени от домов и деревьев", "shadows")
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
	_tw.tween_property(_planet, "position", _planet_pos(open_sandbox or open_settings), 0.6)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (_sandbox.visible or _settings.visible):
		_toggle("")

func _panel(root: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = Vector2(545, 190)
	p.custom_minimum_size.x = 430
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
