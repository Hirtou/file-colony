class_name MapLayout
extends RefCounted
## Раскладка папок в квадраты без наложений.
## Результат: массив {rect: Rect2, folder: Folder, is_city: bool}

const GAP := 20.0

static func square_size(f) -> float:
	var s := 30.0 + 8.0 * sqrt(float(f.file_count))
	if f.is_city():
		s += 40.0  # города крупнее
	return s

static func build(root) -> Array:
	var out: Array = []
	_place(root, Vector2.ZERO, out)
	return out

## Кладёт папку и её детей начиная с pos, возвращает размер занятого блока.
static func _place(f, pos: Vector2, out: Array) -> Vector2:
	var s := square_size(f)
	out.append({"rect": Rect2(pos, Vector2(s, s)), "folder": f, "is_city": f.is_city()})
	if f.children.is_empty():
		return Vector2(s, s)
	# Дети раскладываются полками (рядами) под квадратом папки.
	var sizes := []
	var area := 0.0
	for c in f.children:
		var sz := _measure(c)
		sizes.append(sz)
		area += sz.x * sz.y
	var max_w := maxf(s, sqrt(area) * 1.5)
	var x := 0.0
	var y := s + GAP
	var row_h := 0.0
	var width := s
	for i in f.children.size():
		var sz: Vector2 = sizes[i]
		if x > 0.0 and x + sz.x > max_w:
			x = 0.0
			y += row_h + GAP
			row_h = 0.0
		_place(f.children[i], pos + Vector2(x, y), out)
		x += sz.x + GAP
		row_h = maxf(row_h, sz.y)
		width = maxf(width, x - GAP)
	return Vector2(width, y + row_h)

static func _measure(f) -> Vector2:
	return _place(f, Vector2.ZERO, [])
