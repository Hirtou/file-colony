extends Node
## Общее состояние игры (autoload Game): режим «Мои диски» / «Песочница», настройки, кэш построенных миров.
## Все диски и файлы выдуманные; читается только свой файл настроек user://settings.cfg.

const SETTINGS_FILE := "user://settings.cfg"
const MY_DISKS := [{"name": "C:", "gb": 256}, {"name": "D:", "gb": 1024}]
const SANDBOX_SIZES := [64, 128, 256, 512, 1024, 2048, 4096]
const SANDBOX_LETTERS := "EFGHJKLMNPQRSTUVWXYZ"
const TIME_SPEEDS := [1, 10, 60]
const DEFAULTS := {
	"fullscreen": false,
	"vsync": true,
	"show_fps": false,
	"day_night": true,
	"shadows": true,
	"weather": true,  # дождь в городах
	"cam_speed": 600.0,
	"time_speed": 0,  # индекс в TIME_SPEEDS
	"music": 60.0,    # громкость музыки, 0..100
	"sounds": 70.0,   # громкость звуков (дождь, выстрел, вставка), 0..100
	"lang": "",       # ru / en; "" — по языку системы
}
const MUSIC_DIR := "res://assets/music/"
const FADE := 1.5     # секунд на плавную смену трека

var mode := "disks"            # disks / sandbox
var disks: Array = MY_DISKS    # [{name, gb}]
var salt := 0                  # 0 — «Мои диски», иначе зерно песочницы
var settings := DEFAULTS.duplicate()
var _worlds := {}              # кэш построенных карт городов: «диск|соль/город» -> {world}
var _roots := {}               # деревья папок дисков
var _sites := {}               # города на планетах
var clipboard = null           # скопированный файл (FileItem, выдуманный), общий для всех планет
var clip_cut := false          # файл вырезан: «Вставить» переселит его, а не скопирует
var _fps: Label
var _players: Array[AudioStreamPlayer] = []  # два плеера — для плавного перехода между треками
var _cur := 0
var _track := ""
const SFX := preload("res://scripts/sfx.gd")
var _sfx: Array[AudioStreamPlayer] = []
var _rain: AudioStreamPlayer = null

func _ready() -> void:
	_load()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fps = Label.new()  # справа сверху — не закрывает кнопки слева
	_fps.anchor_left = 1.0
	_fps.anchor_right = 1.0
	_fps.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps.offset_left = -8
	_fps.offset_right = -8
	_fps.offset_top = 4
	_fps.add_theme_font_size_override("font_size", 12)
	_fps.modulate.a = 0.7
	_fps.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps.add_theme_constant_override("outline_size", 4)
	layer.add_child(_fps)
	apply()

func _process(_delta: float) -> void:
	if _fps.visible:
		_fps.text = "FPS %d" % Engine.get_frames_per_second()

## F12 — снимок экрана в папку игры (user://screenshots), в любой сцене.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		get_viewport().set_input_as_handled()
		_shot.call_deferred()

func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var t := Time.get_datetime_dict_from_system()
	var path := "user://screenshots/file_colony_%04d%02d%02d_%02d%02d%02d.png" % [t.year, t.month, t.day, t.hour, t.minute, t.second]
	if img.save_png(path) != OK:
		return
	var l := Label.new()
	l.text = I18n.t("Снимок сохранён: %s") % ProjectSettings.globalize_path(path)
	l.anchor_top = 1.0
	l.anchor_bottom = 1.0
	l.offset_left = 16
	l.offset_top = -100
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	_fps.get_parent().add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)

# --- режимы ---

func use_my_disks() -> void:
	mode = "disks"
	salt = 0
	disks = MY_DISKS

func use_sandbox(seed_value: int, count: int) -> void:
	mode = "sandbox"
	salt = seed_value
	disks = sandbox_disks(seed_value, count)

## Выдуманные диски песочницы по зерну: буквы и объёмы.
static func sandbox_disks(seed_value: int, count: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var letters := Array(SANDBOX_LETTERS.split(""))
	var out := []
	for i in clampi(count, 1, 5):
		var k := rng.randi_range(0, letters.size() - 1)
		out.append({"name": letters[k] + ":", "gb": SANDBOX_SIZES[rng.randi_range(0, SANDBOX_SIZES.size() - 1)]})
		letters.remove_at(k)
	return out

func tree_seed(disk_name: String) -> int:
	return FakeTree.seed_for(disk_name) + salt

func planet_seed(disk_name: String) -> int:
	return PlanetTexture.seed_from_name(disk_name) + salt

## Построенная карта (ключ — «диск/город», или {}): второй вход в город — мгновенно и такой же, как был.
func cached_world(disk_name: String) -> Dictionary:
	return _worlds.get("%s|%d" % [disk_name, salt], {})

func cache_world(disk_name: String, data: Dictionary) -> void:
	_worlds["%s|%d" % [disk_name, salt]] = data

## Дерево папок диска (выдуманное) — одно на всю игру: удаления и переселения в нём сохраняются.
func disk_root(disk_name: String):
	var k := "%s|%d" % [disk_name, salt]
	if not _roots.has(k):
		_roots[k] = FakeTree.generate(tree_seed(disk_name), disk_name)
	return _roots[k]

## Где на планете диска стоят города и что вокруг них (CitySites).
func city_sites(disk_name: String) -> Array:
	var k := "%s|%d" % [disk_name, salt]
	if not _sites.has(k):
		var img := PlanetTexture.get_texture(planet_seed(disk_name)).get_image()
		_sites[k] = CitySites.make(disk_root(disk_name), planet_seed(disk_name), img)
	return _sites[k]

## Забыть построенные миры (после смены языка имена папок другие).
func forget_worlds() -> void:
	_worlds.clear()
	_roots.clear()
	_sites.clear()
	clipboard = null
	clip_cut = false

func time_speed() -> int:
	return TIME_SPEEDS[settings.time_speed]

# --- музыка ---

## Включить трек (space / village), плавно сменив текущий. Тот же трек — ничего не делать.
func play_music(track: String) -> void:
	if track == _track:
		return
	_track = track
	var path := MUSIC_DIR + track + ".wav"
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)  # петля включена в настройках импорта (.wav.import)
	var old := _players[_cur]
	_cur = 1 - _cur
	var p := _players[_cur]
	p.stream = stream
	p.volume_db = -80.0
	p.play()
	var tw := create_tween().set_parallel()
	tw.tween_property(p, "volume_db", _music_db(), FADE)
	tw.tween_property(old, "volume_db", -80.0, FADE)
	tw.chain().tween_callback(old.stop)

## Короткий звук (copy / paste / shot ...). Звуки из чисел — scripts/sfx.gd.
func sfx(sound: String, volume := 1.0) -> void:
	if settings.sounds <= 0.0 or DisplayServer.get_name() == "headless":
		return
	var p: AudioStreamPlayer = null
	for q in _sfx:
		if not q.playing:
			p = q
			break
	if p == null:
		if _sfx.size() >= 8:
			return
		p = AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)
	p.stream = SFX.get_stream(sound)
	p.volume_db = linear_to_db(maxf(settings.sounds / 100.0 * volume, 0.0001))
	p.pitch_scale = randf_range(0.94, 1.06)
	p.play()

## Шум дождя: сила 0..1 (0 — тишина). Петля играет, пока идёт дождь.
func set_rain(amount: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _rain == null:
		_rain = AudioStreamPlayer.new()
		_rain.stream = SFX.get_stream("rain")
		add_child(_rain)
	var v: float = amount * settings.sounds / 100.0 * 0.55
	if v < 0.01:
		if _rain.playing:
			_rain.stop()
		return
	_rain.volume_db = linear_to_db(v)
	if not _rain.playing:
		_rain.play()

func _music_db() -> float:
	var v: float = settings.music / 100.0
	return linear_to_db(maxf(v * 0.8, 0.0001))

# --- сцены ---

## Заменить сцену from на новую из файла; вернуть новую.
func switch(from: Node, path: String) -> Node:
	var next: Node = load(path).instantiate()
	from.get_parent().add_child(next)
	get_tree().current_scene = next
	from.queue_free()
	return next

# --- настройки ---

func set_setting(key: String, value) -> void:
	settings[key] = value
	apply()
	_save()

func apply() -> void:
	I18n.use(settings.lang)
	if DisplayServer.get_name() != "headless":
		get_window().title = I18n.t("Файловая колония")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	if _fps:
		_fps.visible = settings.show_fps
	if not _players.is_empty() and _players[_cur].playing:
		_players[_cur].volume_db = _music_db()  # громкость из настроек — сразу

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) != OK:
		_lang_arg()
		return
	for k in DEFAULTS:
		settings[k] = cfg.get_value("settings", k, DEFAULTS[k])
	_lang_arg()

## Запуск с «-- --lang=en»: язык только на этот запуск (для скриншотов).
func _lang_arg() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			settings.lang = a.trim_prefix("--lang=")

func _save() -> void:
	var cfg := ConfigFile.new()
	for k in settings:
		cfg.set_value("settings", k, settings[k])
	cfg.save(SETTINGS_FILE)
