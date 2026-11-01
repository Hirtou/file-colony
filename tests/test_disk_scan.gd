extends GutTest
## DiskScan на своей тестовой папке в user:// (настоящие файлы пользователя не трогаются).

const DIR := "user://scan_test"

func before_all() -> void:
	for p in ["Фото/Отпуск", "Фото/Семья", "Код", "Пустая"]:
		DirAccess.make_dir_recursive_absolute(DIR + "/" + p)
	for p in ["Фото/Отпуск/море.jpg", "Фото/обложка.png", "Код/main.gd", "Код/notes.unknownext"]:
		var f := FileAccess.open(DIR + "/" + p, FileAccess.WRITE)
		f.store_string("12345")

func after_all() -> void:
	for p in ["Фото/Отпуск/море.jpg", "Фото/обложка.png", "Код/main.gd", "Код/notes.unknownext",
			"Фото/Отпуск", "Фото/Семья", "Фото", "Код", "Пустая", ""]:
		DirAccess.remove_absolute(DIR + "/" + p)

func _kid(f, n: String):
	for c in f.children:
		if c.name == n:
			return c
	return null

func test_scan_tree() -> void:
	var root := DiskScan.scan(ProjectSettings.globalize_path(DIR))
	assert_eq(root.children.size(), 3, "три города")
	var photo = _kid(root, "Фото")
	assert_not_null(_kid(photo, "Отпуск"))
	var loose = _kid(photo, I18n.t("Файлы"))
	assert_not_null(loose, "файлы рядом с подпапками — в доме «Файлы»")
	assert_eq(loose.files[0].name, "обложка.png")
	assert_eq(loose.files[0].size, 5)
	var code = _kid(root, "Код")
	assert_true(code.is_city(), "город из одних файлов получает дом")
	assert_eq(code.children[0].file_count, 2)
	assert_true(_kid(root, "Пустая").is_city())

func test_type_of() -> void:
	assert_eq(DiskScan.type_of("a.JPG"), FakeTree.Type.IMAGE)
	assert_eq(DiskScan.type_of("b.dll"), FakeTree.Type.PROGRAM)
	assert_eq(DiskScan.type_of("c.xyz"), FakeTree.Type.OTHER)
