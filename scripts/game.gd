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
	"cam_speed": 600.0,
	"time_speed": 0,  # индекс в TIME_SPEEDS
}

var mode := "disks"            # disks / sandbox
var disks: Array = MY_DISKS    # [{name, gb}]
var salt := 0                  # 0 — «Мои диски», иначе зерно песочницы
var settings := DEFAULTS.duplicate()
var _worlds := {}              # кэш построенных материков
var clipboard = null           # скопированный файл (FileItem, выдуманный), общий для всех планет
var _fps: Label

func _ready() -> void:
	_load()
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fps = Label.new()
	_fps.position = Vector2(8, 4)
	_fps.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps.add_theme_constant_override("outline_size", 4)
	layer.add_child(_fps)
	apply()

func _process(_delta: float) -> void:
	if _fps.visible:
		_fps.text = "FPS %d" % Engine.get_frames_per_second()

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

## Построенный материк диска (или {}): второй вход на планету — мгновенно.
func cached_world(disk_name: String) -> Dictionary:
	return _worlds.get("%s|%d" % [disk_name, salt], {})

func cache_world(disk_name: String, data: Dictionary) -> void:
	_worlds["%s|%d" % [disk_name, salt]] = data

func time_speed() -> int:
	return TIME_SPEEDS[settings.time_speed]

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
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	if _fps:
		_fps.visible = settings.show_fps

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) != OK:
		return
	for k in DEFAULTS:
		settings[k] = cfg.get_value("settings", k, DEFAULTS[k])

func _save() -> void:
	var cfg := ConfigFile.new()
	for k in settings:
		cfg.set_value("settings", k, settings[k])
	cfg.save(SETTINGS_FILE)
