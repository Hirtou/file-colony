class_name SpaceScene
extends Node2D
## Сцена «Космос»: две планеты-диска, наведение, приближение по клику.

# Фейковые диски (реальный диск не читаем)
const DISKS := [
	{"name": "C:", "gb": 256},
	{"name": "D:", "gb": 1024},
]
const GAP := 140.0       # расстояние между планетами
const ZOOM_TIME := 1.5   # секунды
const DIM := Color(0.25, 0.25, 0.3)

@onready var cam: Camera2D = $Camera
@onready var stars: Node2D = $Stars
@onready var label: Label = $UI/Label
@onready var enter_btn: Button = $UI/Enter

const CONTINENT := preload("res://scenes/continent.tscn")
var continent: Node = null  # открытый материк (вид сверху)

var planets: Array[Planet] = []
var target: Planet = null  # планета, к которой приблизились
var busy := false          # идёт анимация
const DRAG_PX := 6.0       # сдвиг мыши, после которого это вращение, а не клик
var pressed: Planet = null # планета, на которой нажали левую кнопку
var press_pos := Vector2.ZERO
var dragging := false
var base_zoom := Vector2.ONE  # масштаб общего вида (все планеты в кадре)
var _planet_zoom := Vector2.ONE  # масштаб, когда приблизились к планете
var _fade: ColorRect
var _fade_text: Label

## Радиус растёт умеренно: корень 4-й степени от объёма.
static func radius_for(gb: float) -> float:
	return 110.0 * pow(gb / 256.0, 0.25)

## Позиции планет в ряд по центру, без наложений.
static func layout(disks: Array) -> Array:
	var out := []
	var x := 0.0
	for d in disks:
		var r := radius_for(d.gb)
		out.append({"name": d.name, "gb": d.gb, "pos": Vector2(x + r, 0), "radius": r})
		x += r * 2 + GAP
	var shift := (x - GAP) / 2
	for o in out:
		o.pos = o.pos - Vector2(shift, 0)
	return out

func _ready() -> void:
	label.visible = false
	enter_btn.pressed.connect(_dive)
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
	var infos := layout(Game.disks)  # «Мои диски» или выдуманные диски песочницы
	for info in infos:
		var p := Planet.new()
		add_child(p)
		p.position = info.pos
		p.setup(info.name, info.radius, info.gb)
		planets.append(p)
	# все планеты в кадре (в песочнице их до пяти)
	var last: Dictionary = infos[-1]
	var width: float = (last.pos.x + last.radius) * 2.0 + 80.0
	var z := minf(1.0, get_viewport_rect().size.x / width)
	base_zoom = Vector2(z, z)
	cam.zoom = base_zoom
	# кнопка в главное меню
	var menu := Button.new()
	menu.text = "Меню"
	menu.position = Vector2(16, 16)
	menu.add_theme_font_size_override("font_size", 18)
	menu.pressed.connect(_to_menu)
	$UI.add_child(menu)

## В главное меню.
func _to_menu() -> void:
	Game.switch(self, "res://scenes/menu.tscn")

func _process(_delta: float) -> void:
	# свет на планетах — от того места, где сейчас (далёкое) солнце на экране
	var sun = $SunLayer/Sun
	var ct := get_viewport().get_canvas_transform()
	for p in planets:
		p.set_sun(sun.center - ct * p.global_position)
	# подсветка при наведении (только в космосе)
	if busy or target != null or continent != null:
		return
	var m := get_global_mouse_position()
	for p in planets:
		p.hovered = p.has_point(m)

func _unhandled_input(event: InputEvent) -> void:
	if busy or continent != null:
		return
	# левая кнопка: сдвиг больше DRAG_PX = вращение, иначе клик
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_pos = event.position
			pressed = _planet_at(get_global_mouse_position())
			dragging = false
		else:
			if dragging:
				pressed.dragging = false
			elif pressed != null and target == null:
				_zoom_to(pressed)
			pressed = null
			dragging = false
		return
	if event is InputEventMouseMotion and pressed != null:
		if not dragging and event.position.distance_to(press_pos) > DRAG_PX:
			dragging = true
			pressed.dragging = true
		if dragging:
			pressed.drag(event.relative / (pressed.radius * cam.zoom.x))
		return
	var right: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	if target != null and (right or event.is_action_pressed("ui_cancel")):
		_zoom_back()
	elif target == null and event.is_action_pressed("ui_cancel"):
		_to_menu()

## Планета под мышью (после приближения — только выбранная).
func _planet_at(m: Vector2) -> Planet:
	for p in planets:
		if (target == null or p == target) and p.has_point(m):
			return p
	return null

## Камера едет к планете и приближает, остальное темнеет.
func _zoom_to(p: Planet) -> void:
	target = p
	busy = true
	p.hovered = false
	p.selected = true
	p.pulse()
	# в кадр: планета + подпись под ней (~60 px), занимают 80% высоты экрана
	var z := get_viewport_rect().size.y * 0.8 / (p.radius * 2 + 70)
	_planet_zoom = Vector2(z, z)
	var tw := _new_tween()
	tw.tween_property(cam, "position", p.position + Vector2(0, 30), ZOOM_TIME)
	tw.tween_property(cam, "zoom", Vector2(z, z), ZOOM_TIME)
	tw.tween_property(stars, "modulate", DIM, ZOOM_TIME)
	for o in planets:
		if o != p:
			tw.tween_property(o, "modulate", DIM, ZOOM_TIME)
	tw.chain().tween_callback(_on_zoomed)

func _on_zoomed() -> void:
	busy = false  # подпись уже под планетой, отдельный UI-текст не нужен
	enter_btn.visible = true

## «Войти» с анимацией: планета раскручивается, камера ныряет в неё, экран темнеет;
## пока строится мир — надпись «Посадка…», потом материк проявляется и камера «садится».
func _dive() -> void:
	if busy or target == null:
		return
	busy = true
	enter_btn.visible = false
	target.spin_up()
	var tw := create_tween().set_parallel()
	tw.tween_property(cam, "zoom", cam.zoom * 6.0, 1.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_property(cam, "position", target.position, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_fade, "color:a", 1.0, 0.45).set_delay(0.9)
	tw.tween_property(_fade_text, "modulate:a", 1.0, 0.3).set_delay(1.0)
	_fade_text.text = "Посадка на «%s»…" % target.disk_name
	tw.chain().tween_callback(_land)

func _land() -> void:
	_enter()
	if continent.is_built:
		_landed()
	else:
		continent.built.connect(_landed, CONNECT_ONE_SHOT)

## Мир готов: затемнение уходит, камера материка опускается сверху.
func _landed() -> void:
	busy = false
	var ccam: Camera2D = continent.cam
	var z := ccam.zoom
	ccam.zoom = z * 0.45
	var tw := create_tween().set_parallel()
	tw.tween_property(ccam, "zoom", z, 1.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_fade, "color:a", 0.0, 0.7)
	tw.tween_property(_fade_text, "modulate:a", 0.0, 0.3)

## «Войти»: карта материка сверху вместо космоса.
func _enter() -> void:
	continent = CONTINENT.instantiate()
	continent.disk_name = target.disk_name
	continent.disk_gb = target.disk_gb
	continent.exit_requested.connect(_leave)
	_show_space(false)
	add_child(continent)

## Назад в космос (к той же приближенной планете): экран темнеет, камера «взлетает» от планеты.
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
	cam.make_current()
	cam.position = target.position + Vector2(0, 30)
	cam.zoom = _planet_zoom * 5.0
	target.spin_up()
	var tw := create_tween().set_parallel()
	tw.tween_property(cam, "zoom", _planet_zoom, 1.1).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_fade, "color:a", 0.0, 0.5)
	tw.chain().tween_callback(func():
		busy = false
		enter_btn.visible = true)

func _show_space(v: bool) -> void:
	stars.visible = v
	$SunLayer.visible = v
	$UI.visible = v
	for p in planets:
		p.visible = v

## Для скриншотов: space — общий вид; иначе сразу на материк первой планеты (map / city / house ...).
func debug_view(view: String) -> void:
	if view == "space":
		return
	if view == "planet" or view == "dive":
		# выбранная планета (кольцо, луна) / середина нырка
		_zoom_to(planets[-1])
		for t in get_tree().get_processed_tweens():
			t.custom_step(5.0)
		if view == "dive":
			_dive()
			for t in get_tree().get_processed_tweens():
				t.custom_step(1.05)
		return
	target = planets[0]
	_enter()
	continent.debug_view(view)

## Плавно назад в космос.
func _zoom_back() -> void:
	if pressed != null:
		pressed.dragging = false
	pressed = null
	dragging = false
	busy = true
	label.visible = false
	enter_btn.visible = false
	var tw := _new_tween()
	tw.tween_property(cam, "position", Vector2.ZERO, ZOOM_TIME)
	tw.tween_property(cam, "zoom", base_zoom, ZOOM_TIME)
	tw.tween_property(stars, "modulate", Color.WHITE, ZOOM_TIME)
	for o in planets:
		tw.tween_property(o, "modulate", Color.WHITE, ZOOM_TIME)
	if target:
		target.selected = false
	tw.chain().tween_callback(_on_back)

func _on_back() -> void:
	target = null
	busy = false

func _new_tween() -> Tween:
	return create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
