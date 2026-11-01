class_name DiskScan
extends RefCounted
## Настоящие диски компьютера для режима «Мои диски». Читаются ТОЛЬКО имена папок и файлов и размеры
## файлов: игра файлы не читает, ничего не меняет и не удаляет (удаление в игре — только в мире игры).
## Игрок сам может открыть файл (не программу) или показать его в проводнике — это делает Windows.
## Скрытые и системные папки пропускаются. Дерево обрезается, чтобы город строился быстро.

const MAX_CITIES := 18      # городов на диск (папки пользователя + папки верхнего уровня)
const MAX_KIDS_TOP := 14    # подпапок в городе
const MAX_KIDS := 6         # подпапок глубже (как в выдуманных районах)
const MAX_FILES := 25       # жителей в доме (как в выдуманных домах)
const MAX_FOLDERS := 900    # папок на весь диск
## Папки пользователя (как слева в проводнике) — на своём диске это первые города, сразу, без «Users/имя/…».
const USER_DIRS := [[OS.SYSTEM_DIR_DESKTOP, "Рабочий стол"], [OS.SYSTEM_DIR_DOWNLOADS, "Загрузки"],
	[OS.SYSTEM_DIR_DOCUMENTS, "Документы"], [OS.SYSTEM_DIR_PICTURES, "Изображения"],
	[OS.SYSTEM_DIR_MUSIC, "Музыка"], [OS.SYSTEM_DIR_MOVIES, "Видео"]]
static var _skip := {}      # папки пользователя: глубже в «Users» их не берём второй раз
const FALLBACK_GB := 256

## Диски компьютера: [{name: "C:", gb}]. Пустые (без носителя) и недоступные пропускаются.
static func drives() -> Array:
	var sizes := _sizes()
	var out := []
	for i in DirAccess.get_drive_count():
		var d := DirAccess.get_drive_name(i)
		if DirAccess.open(d + "/") == null:
			continue
		out.append({"name": d, "gb": sizes.get(d.left(1).to_upper(), FALLBACK_GB)})
	return out

## Объём дисков в ГБ (буква -> ГБ) через PowerShell; не вышло — {} (будет FALLBACK_GB).
static func _sizes() -> Dictionary:
	var lines := []
	var cmd := "Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name + ';' + ($_.Used + $_.Free) }"
	if OS.execute("powershell", ["-NoProfile", "-NonInteractive", "-Command", cmd], lines) != 0 or lines.is_empty():
		return {}
	var out := {}
	for line in String(lines[0]).split("\n"):
		var p := line.strip_edges().split(";")
		if p.size() == 2 and p[1].is_valid_int() and int(p[1]) > 0:
			out[p[0].to_upper()] = maxi(1, int(round(int(p[1]) / 1073741824.0)))
	return out

## Дерево папок диска (обрезанное), в том же виде, что FakeTree: город — папка с подпапками,
## дом — только файлы, хижина — пустая. Файлы папки, где есть и подпапки, живут в доме «Файлы».
static func scan(drive: String) -> FakeTree.Folder:
	var root := FakeTree.Folder.new()
	root.name = drive
	root.path = drive + "/"
	var budget := [MAX_FOLDERS]
	var queue := []  # обход по уровням — бюджет папок делится между городами поровну
	_skip.clear()
	for u in USER_DIRS:
		var p := OS.get_system_dir(u[0]).replace("\\", "/").trim_suffix("/")
		if p == "" or _skip.has(_norm(p)) or not _norm(p).begins_with(_norm(drive)) or not DirAccess.dir_exists_absolute(p):
			continue
		_skip[_norm(p)] = true
		var f := FakeTree.Folder.new()
		f.name = I18n.t(u[1])
		f.path = p
		root.children.append(f)
		queue.append([f, p, 1])
	for n in _dirs(drive + "/").slice(0, MAX_CITIES - root.children.size()):
		var f := FakeTree.Folder.new()
		f.name = n
		f.path = drive + "/" + n
		root.children.append(f)
		queue.append([f, drive + "/" + n, 1])
	budget[0] -= root.children.size()
	while not queue.is_empty():
		var q: Array = queue.pop_front()
		_fill(q[0], q[1], q[2], queue, budget)
	if root.children.is_empty():
		var only := FakeTree.Folder.new()  # пустой диск — один город, иначе негде приземлиться
		only.name = drive
		only.path = root.path
		root.children.append(only)
	# город — всегда папка с подпапками: файлы верхней папки — в дом «Файлы», пустая — одна хижина
	for c in root.children:
		if c.children.is_empty():
			var h := FakeTree.Folder.new()
			h.name = I18n.t("Файлы")
			h.path = c.path  # дом «Файлы» — это файлы самой папки
			h.files = c.files
			h.file_count = c.files.size()
			c.files = []
			c.file_count = 0
			c.children.append(h)
	return root

static func _fill(f: FakeTree.Folder, path: String, depth: int, queue: Array, budget: Array) -> void:
	var dirs := _dirs(path) if depth < FakeTree.MAX_DEPTH else []
	var files := _files(path)
	if dirs.is_empty() or budget[0] <= 0:
		f.files = files
		f.file_count = files.size()
		return
	var cap := (MAX_KIDS_TOP if depth == 1 else MAX_KIDS) - (1 if not files.is_empty() else 0)
	for n in dirs.slice(0, mini(cap, budget[0])):
		var c := FakeTree.Folder.new()
		c.name = n
		c.path = path + "/" + n
		f.children.append(c)
		queue.append([c, path + "/" + n, depth + 1])
		budget[0] -= 1
	if not files.is_empty():
		var h := FakeTree.Folder.new()
		h.name = _free_name(f, I18n.t("Файлы"))
		h.path = path
		h.files = files
		h.file_count = files.size()
		f.children.append(h)

## Видимые подпапки (без скрытых, системных и ссылок).
static func _dirs(path: String) -> Array:
	var d := DirAccess.open(path)
	if d == null:
		return []
	d.include_hidden = false
	var out := []
	for n in d.get_directories():
		var p := path.path_join(n)
		if not n.begins_with("$") and not d.is_link(p) and not _skip.has(_norm(p)):
			out.append(n)
	return out

## Путь для сравнения: прямые слэши, нижний регистр, без слэша в конце.
static func _norm(p: String) -> String:
	return p.replace("\\", "/").trim_suffix("/").to_lower()

## Файлы папки: имя, тип по расширению, размер (файл не открывается).
static func _files(path: String) -> Array:
	var d := DirAccess.open(path)
	if d == null:
		return []
	d.include_hidden = false
	var out := []
	var loud := Engine.print_error_messages
	Engine.print_error_messages = false  # файл без доступа — размер 0, без красных строк в логе
	for n in d.get_files().slice(0, MAX_FILES):
		var fi := FakeTree.FileItem.new()
		fi.name = n
		fi.type = type_of(n)
		fi.path = path.path_join(n)
		fi.size = maxi(0, FileAccess.get_size(fi.path))
		out.append(fi)
	Engine.print_error_messages = loud
	return out

# --- действия игрока с настоящими файлами (только по его клику; сами файлы игра не читает) ---

## Что из игры не запускаем: программы и скрипты (двойной клик по ним — запуск, а не просмотр).
const NO_RUN := ["exe", "msi", "bat", "cmd", "com", "scr", "ps1", "vbs", "vbe", "js", "jse", "wsf", "wsh",
	"lnk", "reg", "hta", "cpl", "jar", "msc", "pif", "appx", "msix", "url", "inf", "sys", "dll"]

## Можно ли открыть файл из игры: он с настоящего диска и это не программа.
static func can_open(file) -> bool:
	return file.path != "" and not NO_RUN.has(String(file.path).get_extension().to_lower())

## Открыть файл программой по умолчанию (как двойной клик в проводнике). "" — открыт, иначе причина.
static func open_file(file) -> String:
	if file.path == "":
		return "Этого файла нет на диске — он живёт только в игре"
	if not can_open(file):
		return "Программы и скрипты из игры не запускаются — «Показать в проводнике»"
	if not FileAccess.file_exists(file.path):
		return "Файла на диске уже нет"
	return "" if OS.shell_open(file.path) == OK else "Не удалось открыть"

## Показать в проводнике: файл — выделенным в его папке, папку — открыть.
static func reveal(path: String, is_file: bool) -> String:
	if path == "":
		return "Этого нет на диске — оно живёт только в игре"
	if is_file:
		if not FileAccess.file_exists(path):
			return "Файла на диске уже нет"
		OS.create_process("explorer.exe", ["/select,", path.replace("/", "\\")])
		return ""
	if not DirAccess.dir_exists_absolute(path):
		return "Папки на диске уже нет"
	return "" if OS.shell_open(path) == OK else "Не удалось открыть"

## Когда файл или папка менялись на диске: «12.03.2025 14:07» по местному времени; "" — неизвестно.
static func modified(path: String) -> String:
	if path == "" or not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)):
		return ""
	var loud := Engine.print_error_messages
	Engine.print_error_messages = false
	var t := FileAccess.get_modified_time(path)
	Engine.print_error_messages = loud
	if t <= 0:
		return ""
	var d := Time.get_datetime_dict_from_unix_time(t + Time.get_time_zone_from_system().bias * 60)
	return "%02d.%02d.%04d %02d:%02d" % [d.day, d.month, d.year, d.hour, d.minute]

const EXTRA_EXT := {"jpeg": 0, "bmp": 0, "ico": 0, "svg": 0, "tif": 0, "heic": 0, "doc": 1, "md": 1,
	"wmv": 2, "webm": 2, "m4a": 3, "aac": 3, "gz": 4, "tar": 4, "dll": 5, "bat": 5, "cmd": 5, "lnk": 5,
	"xls": 7, "ppt": 8, "ts": 9, "cs": 9, "java": 9, "c": 9, "h": 9, "css": 9, "rs": 9, "go": 9, "tscn": 9,
	"glb": 10, "gltf": 10, "mobi": 12}

## Тип файла по расширению (как в FakeTree.TYPE_EXT); неизвестное — «другое».
static func type_of(file_name: String) -> int:
	var ext := file_name.get_extension().to_lower()
	for t in FakeTree.TYPE_EXT.size():
		if FakeTree.TYPE_EXT[t].has(ext):
			return t
	return EXTRA_EXT.get(ext, FakeTree.Type.OTHER)

static func _free_name(parent: FakeTree.Folder, n: String) -> String:
	var used := {}
	for c in parent.children:
		used[c.name] = true
	var out := n
	var k := 2
	while used.has(out):
		out = "%s %d" % [n, k]
		k += 1
	return out
