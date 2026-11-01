extends PanelContainer
## Окно «Корзина»: сюда попадают удалённые жители (Game.trash). Можно вернуть жителя в его дом
## или очистить корзину. Всё выдуманное (дерево FakeTree), реальный диск не читается.

signal restored(entry)  # житель вернулся в свой дом

const W := 620
var _body: VBoxContainer
var _list: VBoxContainer

func _init() -> void:
	custom_minimum_size = Vector2(W, 0)
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)

func open() -> void:
	_fill()
	show()

func _fill() -> void:
	for c in _body.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	_body.add_child(head)
	var t := _label(head, I18n.t("Корзина"), 20)
	t.add_theme_color_override("font_color", Color(1.0, 0.95, 0.86))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = I18n.t("Закрыть  (Esc)")
	close.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	close.pressed.connect(hide)
	head.add_child(close)
	var total := 0
	for e in Game.trash:
		total += e.file.size
	var sum := _label(_body, I18n.t("Жителей: %d  ·  всего: %s") % [Game.trash.size(), FakeTree.format_size(total)], 14)
	sum.modulate.a = 0.7
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.08)
	r.custom_minimum_size.y = 1
	_body.add_child(r)
	if Game.trash.is_empty():
		var empty := _label(_body, I18n.t("Корзина пуста. Удалённые жители попадают сюда."), 14)
		empty.modulate.a = 0.6
		return
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = mini(Game.trash.size(), 10) * 30 + 4
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)
	for e in Game.trash:
		_row(e)
	var foot := HBoxContainer.new()
	_body.add_child(foot)
	var hint := _label(foot, I18n.t("«Вернуть» — житель идёт обратно в свой дом"), 12)
	hint.modulate.a = 0.5
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var clear := Button.new()
	clear.text = I18n.t("Очистить корзину")
	clear.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	clear.pressed.connect(func():
		Game.trash.clear()
		_fill())
	foot.add_child(clear)

func _row(e: Dictionary) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.add_child(ContinentUI.Dot.new(WorldMap.TYPE_COLORS[e.file.type]))
	var n := _label(line, e.file.name, 13)
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.custom_minimum_size.x = 150
	var from := _label(line, "%s %s / %s" % [e.disk, e.city, e.house.name], 12)
	from.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	from.custom_minimum_size.x = 200
	from.modulate.a = 0.6
	var s := _label(line, FakeTree.format_size(e.file.size), 12)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.custom_minimum_size.x = 70
	s.modulate.a = 0.6
	var b := Button.new()
	b.text = I18n.t("Вернуть")
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(func():
		Game.restore(e)
		restored.emit(e)
		_fill())
	line.add_child(b)
	_list.add_child(line)

func _label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l
