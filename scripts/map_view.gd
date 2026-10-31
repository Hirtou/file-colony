extends Node2D
## Рисует карту: папка = квадрат. Город (есть подпапки) крупнее и другого цвета.

@export var map_seed := 42

const HOUSE_COLOR := Color(0.85, 0.65, 0.35)
const CITY_COLOR := Color(0.3, 0.55, 0.85)

var items: Array = []

func _ready() -> void:
	items = MapLayout.build(FakeTree.generate(map_seed))
	queue_redraw()

func _draw() -> void:
	for it in items:
		var col: Color = CITY_COLOR if it.is_city else HOUSE_COLOR
		draw_rect(it.rect, col)
		draw_rect(it.rect, Color.BLACK, false, 2.0)

func bounds() -> Rect2:
	var r := Rect2()
	for it in items:
		r = it.rect if r.size == Vector2.ZERO else r.merge(it.rect)
	return r
