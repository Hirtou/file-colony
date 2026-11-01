extends PanelContainer
## Окно «Свойства» файла или папки: строки [подпись, значение], путь и кнопка «Копировать путь».
## У файла имя можно поменять (Enter или «Переименовать») — только в игре, на диске имя прежнее.

signal rename_requested(file, new_name: String)

const W := 520
var _body: VBoxContainer
var _edit: LineEdit
var _file = null
var _path := ""

func _init() -> void:
	custom_minimum_size = Vector2(W, 0)
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)

## title — имя; rows — [[подпись, значение], ...]; path — что копирует «Копировать путь»;
## file — у файла поле имени редактируется (rename — сразу встать в него).
func open(title: String, rows: Array, path: String, file = null, rename := false) -> void:
	_file = file
	_path = path
	for c in _body.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	_body.add_child(head)
	var t := _label(head, I18n.t("Свойства"), 20)
	t.add_theme_color_override("font_color", Color(1.0, 0.95, 0.86))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = I18n.t("Закрыть  (Esc)")
	close.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	close.pressed.connect(hide)
	head.add_child(close)
	_edit = null
	if file != null:
		var line := HBoxContainer.new()
		_body.add_child(line)
		_edit = LineEdit.new()
		_edit.text = title
		_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_edit.select_all_on_focus = true
		_edit.text_submitted.connect(func(s): rename_requested.emit(_file, s.strip_edges()))
		line.add_child(_edit)
		var rn := Button.new()
		rn.text = I18n.t("Переименовать")
		rn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		rn.pressed.connect(func(): rename_requested.emit(_file, _edit.text.strip_edges()))
		line.add_child(rn)
	else:
		_label(_body, title, 16)
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.08)
	r.custom_minimum_size.y = 1
	_body.add_child(r)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	_body.add_child(grid)
	for row in rows:
		var k := _label(grid, I18n.t(row[0]), 13)
		k.modulate.a = 0.6
		var v := _label(grid, str(row[1]), 13)
		v.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		v.custom_minimum_size.x = W - 150
	var foot := HBoxContainer.new()
	_body.add_child(foot)
	var hint := _label(foot, I18n.t("Переименование — только в игре, на диске имя прежнее") if file != null else "", 12)
	hint.modulate.a = 0.5
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cp := Button.new()
	cp.text = I18n.t("Копировать путь")
	cp.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cp.pressed.connect(func(): DisplayServer.clipboard_set(_path))
	foot.add_child(cp)
	show()
	if rename and _edit:
		_edit.grab_focus.call_deferred()

## Поле имени в фокусе (буквы не уходят в горячие клавиши карты).
func typing() -> bool:
	return visible and _edit != null and _edit.has_focus()

func _label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l
