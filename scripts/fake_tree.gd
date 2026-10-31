class_name FakeTree
extends RefCounted
## Генератор ФЕЙКОВОГО дерева папок (в памяти). Один seed = одно дерево.

enum Type { IMAGE, DOC, VIDEO, MUSIC, ARCHIVE, PROGRAM, OTHER, TABLE, SLIDES, CODE, MODEL, FONT, BOOK, SAVE }
const TYPE_NAMES := ["картинка", "документ", "видео", "музыка", "архив", "программа", "другое",
	"таблица", "презентация", "код", "3D-модель", "шрифт", "книга", "сохранение"]
const TYPE_EXT := [["jpg", "png", "gif", "webp", "psd"], ["docx", "txt", "rtf", "odt"], ["mp4", "mkv", "avi", "mov"],
	["mp3", "flac", "wav", "ogg"], ["zip", "rar", "7z", "iso"], ["exe", "msi", "apk"], ["dat", "log", "tmp", "bak"],
	["xlsx", "csv", "ods"], ["pptx", "key", "odp"], ["py", "js", "gd", "cpp", "html"], ["blend", "obj", "fbx", "stl"],
	["ttf", "otf", "woff"], ["pdf", "epub", "fb2", "djvu"], ["sav", "save", "dat"]]
const TYPE_SIZE := [[1e5, 8e6], [1e4, 5e6], [5e7, 4e9], [3e6, 1.5e7], [1e6, 2e9], [1e6, 2e8], [1e3, 1e7],
	[1e4, 2e7], [5e5, 1e8], [5e2, 2e5], [1e5, 3e8], [3e4, 2e6], [2e5, 5e7], [1e3, 5e7]]  # байты, мин/макс
const MAX_DEPTH := 3

class FileItem:
	var name: String
	var type: int
	var size: int
	var origin := ""  # копия: имя оригинала (житель-копия выглядит так же)

	## Копия файла с новым именем.
	func copy_as(new_name: String) -> FileItem:
		var f := FileItem.new()
		f.name = new_name
		f.type = type
		f.size = size
		f.origin = origin if origin != "" else name
		return f

## Имя копии в папке: то же имя, если свободно, иначе «Имя - копия.ext», «Имя - копия (2).ext»...
static func copy_name(folder: Folder, file_name: String) -> String:
	var dot := file_name.rfind(".")
	var base := file_name.left(dot) if dot > 0 else file_name
	var ext := file_name.substr(dot) if dot > 0 else ""
	var used := {}
	for f in folder.files:
		used[f.name] = true
	if not used.has(file_name):
		return file_name  # в другой папке имя свободно — как в проводнике
	var n := base + I18n.t(" - копия") + ext
	var k := 2
	while used.has(n):
		n = "%s%s (%d)%s" % [base, I18n.t(" - копия"), k, ext]
		k += 1
	return n

class Folder:
	var name: String
	var file_count: int  # = files.size()
	var files: Array = []
	var children: Array = []
	var has_roof := true  # у дома есть крыша (пока ни на что не влияет: крыши не рисуются)

	func is_city() -> bool:
		return children.size() > 0

	## Файлов во всей папке с подпапками.
	func total_files() -> int:
		var n := file_count
		for c in children:
			n += c.total_files()
		return n

	## Размер всей папки с подпапками, байты.
	func total_size() -> int:
		var s := 0
		for f in files:
			s += f.size
		for c in children:
			s += c.total_size()
		return s

	func to_dict() -> Dictionary:
		var kids := []
		for c in children:
			kids.append(c.to_dict())
		var fs := []
		for f in files:
			fs.append([f.name, f.type, f.size])
		return {"name": name, "files": fs, "children": kids}

const SYL := ["ka", "ra", "to", "mi", "su", "len", "dor", "va", "ze", "nu", "bek", "al", "tan", "or", "is"]
const FOLDER_NAMES := ["Документы", "Проекты", "Фото", "Музыка", "Видео", "Загрузки", "Игры", "Работа",
	"Учёба", "Архив", "Отчёты", "Отпуск", "Семья", "Книги", "Программы", "Рисунки", "Заметки", "Старое",
	"Разное", "Сканы", "Черновики", "Шаблоны", "Фильмы", "Сериалы", "Курсы", "Код", "Сайт", "Ресурсы"]
const FOLDER_NAMES_EN := ["Documents", "Projects", "Photos", "Music", "Videos", "Downloads", "Games", "Work",
	"Study", "Archive", "Reports", "Vacation", "Family", "Books", "Programs", "Drawings", "Notes", "Old",
	"Misc", "Scans", "Drafts", "Templates", "Movies", "Series", "Courses", "Code", "Website", "Assets"]

## Seed дерева по имени диска.
static func seed_for(disk_name: String) -> int:
	return ("tree:" + disk_name).hash()

## Фейковое дерево диска: 4-8 папок верхнего уровня, глубина до MAX_DEPTH.
static func generate(seed_value: int, root_name := "C:") -> Folder:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var root := Folder.new()
	root.name = root_name
	# каждая папка верхнего уровня — свой город, внутри районы и дома
	for i in rng.randi_range(4, 8):
		var f := Folder.new()
		f.name = _folder_name(rng, root)
		_make_city(f, rng, 1)
		root.children.append(f)
	return root

## Папка: город (подпапки), дом (только файлы) или пустая хижина.
static func _folder(rng: RandomNumberGenerator, depth: int, parent: Folder) -> Folder:
	var f := Folder.new()
	f.name = _folder_name(rng, parent)
	if depth < MAX_DEPTH and rng.randf() < 0.4:
		_make_city(f, rng, depth)
	elif rng.randf() >= 0.12:
		# в основном домики на одного-трёх жителей, изредка дом побольше (до 25)
		var n := 1 if rng.randf() < 0.4 else int(pow(rng.randf(), 2.5) * 24) + 1
		for i in n:
			f.files.append(_file(rng))
		f.file_count = f.files.size()
	return f

static func _make_city(f: Folder, rng: RandomNumberGenerator, depth: int) -> void:
	f.files.clear()
	f.file_count = 0
	# деревня: на верхнем уровне 6-11 домов/районов, в районе 3-6
	for i in rng.randi_range(6, 11) if depth == 1 else rng.randi_range(3, 6):
		f.children.append(_folder(rng, depth + 1, f))

static func _file(rng: RandomNumberGenerator) -> FileItem:
	var fi := FileItem.new()
	fi.type = rng.randi_range(0, TYPE_NAMES.size() - 1)
	var ext: Array = TYPE_EXT[fi.type]
	fi.name = _name(rng) + "." + ext[rng.randi_range(0, ext.size() - 1)]
	var lim: Array = TYPE_SIZE[fi.type]
	fi.size = int(exp(lerpf(log(lim[0]), log(lim[1]), rng.randf())))
	return fi

## Имя папки, не повторяющееся среди соседей.
static func _folder_name(rng: RandomNumberGenerator, parent: Folder) -> String:
	var used := {}
	for c in parent.children:
		used[c.name] = true
	var n: String = (FOLDER_NAMES_EN if I18n.en() else FOLDER_NAMES)[rng.randi_range(0, FOLDER_NAMES.size() - 1)]
	var k := 2
	var base := n
	while used.has(n):
		n = "%s %d" % [base, k]
		k += 1
	return n

## «256 ГБ», «3.4 МБ».
static func format_size(bytes: int) -> String:
	var units := ["Б", "КБ", "МБ", "ГБ", "ТБ"]
	var v := float(bytes)
	var i := 0
	while v >= 1024.0 and i < units.size() - 1:
		v /= 1024.0
		i += 1
	if i == 0 or v >= 100.0:
		return "%d %s" % [int(v), I18n.t(units[i])]
	return "%.1f %s" % [v, I18n.t(units[i])]

static func _name(rng: RandomNumberGenerator) -> String:
	var s := ""
	for i in rng.randi_range(2, 3):
		s += SYL[rng.randi_range(0, SYL.size() - 1)]
	return s.capitalize()
