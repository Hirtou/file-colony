class_name Pawn
extends RefCounted
## Житель-человечек, вид сверху: туловище в одежде, голова, причёска. Всё рисуется кодом.
## Внешность детерминирована по имени файла; основной цвет одежды — цвет типа файла.

const STYLES := ["футболка", "рубашка", "куртка", "комбинезон", "мантия", "свитер", "костюм", "жилет", "камзол"]
const RANDOM_STYLES := 8  # камзол — только у киллеров
const BELT := Color(0.86, 0.82, 0.72)
const SKINS := [Color(0.98, 0.85, 0.72), Color(0.93, 0.76, 0.6), Color(0.82, 0.62, 0.45),
	Color(0.62, 0.44, 0.3), Color(0.45, 0.31, 0.21)]
const HAIR_COLORS := [Color(0.13, 0.11, 0.1), Color(0.33, 0.22, 0.13), Color(0.52, 0.34, 0.17),
	Color(0.84, 0.68, 0.4), Color(0.62, 0.27, 0.13), Color(0.72, 0.72, 0.7)]
const ACCENTS := [Color(0.93, 0.91, 0.86), Color(0.27, 0.29, 0.33), Color(0.55, 0.42, 0.3),
	Color(0.36, 0.43, 0.56), Color(0.62, 0.57, 0.42)]
const HAIR_STYLES := 6  # короткая, длинная, лысый, пучок, ёжик, хвост
const HATS := ["", "соломенная шляпа", "вязаная шапка", "кепка", "колпак", "цилиндр", "повязка", "треуголка"]
const RANDOM_HATS := 6  # треуголка — только у киллеров
const HAT_COLORS := [Color(0.7, 0.2, 0.18), Color(0.22, 0.32, 0.55), Color(0.3, 0.45, 0.25),
	Color(0.85, 0.72, 0.3), Color(0.42, 0.28, 0.5), Color(0.2, 0.2, 0.22), Color(0.88, 0.86, 0.8)]
const STRAW := Color(0.88, 0.76, 0.47)
const OUTLINE := Color(0.11, 0.09, 0.08)
const SHIRT := Color(0.94, 0.93, 0.9)

## Внешность по файлу.
static func look(file) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = String(file.origin if file.origin != "" else file.name).hash()  # копия — как оригинал
	var main: Color = WorldMap.TYPE_COLORS[file.type].lerp(Color(0.45, 0.45, 0.45), 0.25)
	return {
		"style": rng.randi_range(0, RANDOM_STYLES - 1),
		"main": main.darkened(rng.randf_range(0.0, 0.15)),
		"accent": ACCENTS[rng.randi_range(0, ACCENTS.size() - 1)],
		"skin": SKINS[rng.randi_range(0, SKINS.size() - 1)],
		"hair": rng.randi_range(0, HAIR_STYLES - 1),
		"hair_color": HAIR_COLORS[rng.randi_range(0, HAIR_COLORS.size() - 1)],
		"width": rng.randf_range(0.9, 1.12),
		# головной убор (0 — без него); выбирается последним, чтобы прежняя внешность не менялась
		"hat": 0 if rng.randf() < 0.4 else rng.randi_range(1, RANDOM_HATS),
		"hat_color": HAT_COLORS[rng.randi_range(0, HAT_COLORS.size() - 1)],
		"chest": file.type == FakeTree.Type.ARCHIVE,  # архив носит сундучок за спиной
	}

## Нарисовать жителя в клетке с центром p (u — размер клетки). facing — Residents.Facing.
## detail = false — издалека: без тени, одежды и мелочей (быстрее). carry — несёт коробку с вещами.
static func draw(ci: CanvasItem, p: Vector2, u: float, lk: Dictionary, facing: int, walk: float, dim: bool, detail := true, carry := false) -> void:
	var back := facing == Residents.Facing.UP
	var has_chest: bool = lk.get("chest", false) and detail
	if has_chest and not back:
		_chest(ci, p, u, facing, walk, dim)  # спереди сундучок выглядывает из-за спины
	_draw_body(ci, p, u, lk, facing, walk, dim, detail)
	if has_chest and back:
		_chest(ci, p, u, facing, walk, dim)
	if carry and not back:
		_box(ci, p, u, lk, facing, walk, dim)

## Сундучок архива на спине.
static func _chest(ci: CanvasItem, p: Vector2, u: float, facing: int, walk: float, dim: bool) -> void:
	var bob := -absf(sin(walk * TAU)) * u * 0.04
	var side := -1.0 if facing == Residents.Facing.LEFT else (1.0 if facing == Residents.Facing.RIGHT else 0.0)
	var c := p + Vector2(-side * u * 0.2, (u * 0.08 if facing == Residents.Facing.UP else -u * 0.06) + bob)
	var r := Rect2(c - Vector2(u * 0.17, u * 0.13), Vector2(u * 0.34, u * 0.26))
	ci.draw_rect(r.grow(u * 0.03), _d(OUTLINE, dim))
	ci.draw_rect(r, _d(Color(0.55, 0.36, 0.18), dim))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), _d(Color(0.65, 0.44, 0.22), dim))  # крышка
	ci.draw_rect(Rect2(Vector2(c.x - u * 0.025, r.position.y), Vector2(u * 0.05, r.size.y)), _d(Color(0.72, 0.6, 0.3), dim))
	ci.draw_rect(Rect2(c + Vector2(-u * 0.035, -u * 0.02), Vector2(u * 0.07, u * 0.06)), _d(Color(0.85, 0.7, 0.3), dim))  # замок

## Коробка с вещами в руках у переезжающего.
static func _box(ci: CanvasItem, p: Vector2, u: float, lk: Dictionary, facing: int, walk: float, dim: bool) -> void:
	var bob := -absf(sin(walk * TAU)) * u * 0.04
	var side := -1.0 if facing == Residents.Facing.LEFT else (1.0 if facing == Residents.Facing.RIGHT else 0.0)
	var c := p + Vector2(side * u * 0.18, u * 0.12 + bob)
	var r := Rect2(c - Vector2(u * 0.2, u * 0.15), Vector2(u * 0.4, u * 0.3))
	ci.draw_rect(r.grow(u * 0.03), _d(OUTLINE, dim))
	ci.draw_rect(r, _d(Color(0.78, 0.6, 0.38), dim))
	ci.draw_line(Vector2(r.position.x, c.y - u * 0.02), Vector2(r.end.x, c.y - u * 0.02), _d(Color(0.6, 0.44, 0.26), dim), u * 0.03)
	ci.draw_rect(Rect2(Vector2(c.x - u * 0.04, r.position.y), Vector2(u * 0.08, r.size.y)), _d(Color(0.9, 0.82, 0.6), dim))  # скотч
	for s in [-1.0, 1.0]:  # руки
		_outlined_ellipse(ci, c + Vector2(s * u * 0.2, u * 0.02), Vector2.ONE * u * 0.055, u * 0.025, _d(lk.skin, dim), dim)

static func _draw_body(ci: CanvasItem, p: Vector2, u: float, lk: Dictionary, facing: int, walk: float, dim: bool, detail: bool) -> void:
	var o := u * 0.045  # обводка
	var bob := -absf(sin(walk * TAU)) * u * 0.04  # покачивание при ходьбе
	var front := facing != Residents.Facing.UP
	var side := -1.0 if facing == Residents.Facing.LEFT else (1.0 if facing == Residents.Facing.RIGHT else 0.0)
	var style: int = lk.style
	var flare := 1.14 if style == 4 or style == 8 else 1.0  # мантия и камзол расширяются книзу
	var bc := p + Vector2(0, u * 0.14 + bob)
	var w: float = u * 0.3 * lk.width
	var h := u * 0.27
	var hc := p + Vector2(side * u * 0.03, -u * 0.21 + bob)
	var hr := Vector2(u * 0.165, u * 0.175)
	var hair: int = lk.hair
	var hair_col: Color = lk.hair_color

	if not detail:
		var base0: Color = lk.accent if style == 3 or style == 7 else lk.main
		ci.draw_colored_polygon(_body(bc, w + o, h + o, flare), _d(OUTLINE, dim))
		ci.draw_colored_polygon(_body(bc, w, h, flare), _d(base0, dim))
		_outlined_ellipse(ci, hc, hr, o, _d(lk.skin, dim), dim)
		if hair != 2:
			ci.draw_colored_polygon(_cap(hc, hr * 1.06, -0.05 if front else 1.0), _d(hair_col, dim))
		_hat(ci, hc, hr, o, lk, front, side, dim, false)
		return
	_ellipse(ci, p + Vector2(0, u * 0.38), Vector2(u * 0.3, u * 0.08), Color(0, 0, 0, 0.22))  # тень
	# волосы за спиной
	if hair == 1:
		_outlined_ellipse(ci, hc + Vector2(0, hr.y * 0.55), Vector2(hr.x * 1.18, hr.y * 1.3), o, _d(hair_col, dim), dim)
	elif hair == 5 and side == 0.0:
		_outlined_ellipse(ci, hc + Vector2(hr.x * 0.95, hr.y * 0.45), hr * 0.42, o, _d(hair_col, dim), dim)
	# туловище
	var base: Color = lk.main
	if style == 3 or style == 7:
		base = lk.accent  # под комбинезоном / жилетом рубашка
	elif style == 6:
		base = (lk.main as Color).darkened(0.45)  # пиджак
	ci.draw_colored_polygon(_body(bc, w + o, h + o, flare), _d(OUTLINE, dim))
	ci.draw_colored_polygon(_body(bc, w, h, flare), _d(base, dim))
	_clothes(ci, bc, w, h, flare, u, lk, front, dim)
	if style == 2:  # капюшон за головой
		_outlined_ellipse(ci, hc + Vector2(0, u * 0.05), hr * 1.18, o, _d((lk.main as Color).darkened(0.25), dim), dim)
	# голова
	_outlined_ellipse(ci, hc, hr, o, _d(lk.skin, dim), dim)
	if lk.get("mask", false) and front:  # чёрный платок на лице (киллер)
		_ellipse(ci, hc + Vector2(side * hr.x * 0.15, hr.y * 0.4), Vector2(hr.x * 0.92, hr.y * 0.5), _d(Color(0.08, 0.08, 0.09), dim))
	var hat: int = lk.get("hat", 0)
	if hair != 2 and not front:  # лысый — без волос
		_ellipse(ci, hc, hr * 1.03, _d(hair_col, dim))  # со спины волосы закрывают голову
	elif hair != 2:
		var cap_c := hc + Vector2(-side * hr.x * 0.12, 0)
		if hair == 3 and (hat == 0 or hat == 1 or hat == 6):  # пучок (под шапкой не виден)
			_outlined_ellipse(ci, cap_c + Vector2(0, -hr.y * 1.02), hr * 0.42, o, _d(hair_col, dim), dim)
		var fringe := -0.3 if hair == 4 else (0.08 if hair == 1 else -0.05)
		ci.draw_colored_polygon(_cap(cap_c, hr * 1.06 + Vector2(o, o), fringe), _d(OUTLINE, dim))
		ci.draw_colored_polygon(_cap(cap_c, hr * 1.06, fringe), _d(hair_col, dim))
		if hair == 4 and hat == 0:  # ёжик: светлые штрихи
			for k in 3:
				var x := (k - 1) * hr.x * 0.45
				ci.draw_line(cap_c + Vector2(x, -hr.y * 0.95), cap_c + Vector2(x * 1.1, -hr.y * 0.55), _d(hair_col.lightened(0.25), dim), u * 0.025)
	_hat(ci, hc, hr, o, lk, front, side, dim, true)

## Головной убор поверх волос (hc, hr — центр и радиусы головы). detail = false — без мелочей.
static func _hat(ci: CanvasItem, hc: Vector2, hr: Vector2, o: float, lk: Dictionary, front: bool, side: float, dim: bool, detail: bool) -> void:
	var col: Color = lk.get("hat_color", Color.WHITE)
	match int(lk.get("hat", 0)):
		1:  # соломенная шляпа: широкие поля, тулья с лентой
			_outlined_ellipse(ci, hc + Vector2(0, -hr.y * 0.35), Vector2(hr.x * 1.7, hr.y * 0.75), o, _d(STRAW, dim), dim)
			if detail:
				_ellipse(ci, hc + Vector2(0, -hr.y * 0.42), Vector2(hr.x * 0.9, hr.y * 0.52), _d(col, dim))
			_ellipse(ci, hc + Vector2(0, -hr.y * 0.6), Vector2(hr.x * 0.8, hr.y * 0.44), _d(STRAW.darkened(0.12), dim))
		2:  # вязаная шапка: отворот и помпон
			ci.draw_colored_polygon(_cap(hc, hr * 1.1 + Vector2(o, o), -0.1), _d(OUTLINE, dim))
			ci.draw_colored_polygon(_cap(hc, hr * 1.1, -0.1), _d(col, dim))
			if detail:
				_ellipse(ci, hc + Vector2(0, -hr.y * 0.2), Vector2(hr.x * 1.08, hr.y * 0.2), _d(col.darkened(0.2), dim))
			_outlined_ellipse(ci, hc + Vector2(0, -hr.y * 1.12), hr * 0.3, o, _d(col.lightened(0.35), dim), dim)
		3:  # кепка: козырёк смотрит туда же, куда житель
			ci.draw_colored_polygon(_cap(hc, hr * 1.08 + Vector2(o, o), -0.25), _d(OUTLINE, dim))
			ci.draw_colored_polygon(_cap(hc, hr * 1.08, -0.25), _d(col, dim))
			if front and side == 0.0:
				_outlined_ellipse(ci, hc + Vector2(0, -hr.y * 0.22), Vector2(hr.x * 0.78, hr.y * 0.26), o, _d(col.darkened(0.25), dim), dim)
			elif front:
				_outlined_ellipse(ci, hc + Vector2(side * hr.x * 0.95, -hr.y * 0.32), Vector2(hr.x * 0.55, hr.y * 0.22), o, _d(col.darkened(0.25), dim), dim)
			if detail:
				_ellipse(ci, hc + Vector2(0, -hr.y * 1.0), hr * 0.12, _d(col.lightened(0.3), dim))  # пуговка
		4:  # колпак: поля и высокий конус, кончик чуть набок
			_outlined_ellipse(ci, hc + Vector2(0, -hr.y * 0.45), Vector2(hr.x * 1.35, hr.y * 0.5), o, _d(col.darkened(0.15), dim), dim)
			var tip := hc + Vector2(hr.x * 0.45 * (side if side != 0.0 else 1.0), -hr.y * 2.15)
			var l := hc + Vector2(-hr.x * 0.85, -hr.y * 0.55)
			var r := hc + Vector2(hr.x * 0.85, -hr.y * 0.55)
			ci.draw_colored_polygon(PackedVector2Array([l + Vector2(-o, o), tip + Vector2(0, -o * 1.5), r + Vector2(o, o)]), _d(OUTLINE, dim))
			ci.draw_colored_polygon(PackedVector2Array([l, tip, r]), _d(col, dim))
			if detail:
				_ellipse(ci, hc.lerp(tip, 0.45), hr * 0.13, _d(Color(1.0, 0.9, 0.5), dim))  # звёздочка
		5:  # цилиндр: поля, высокая тулья, лента
			var dark := Color(0.13, 0.12, 0.13)
			_outlined_ellipse(ci, hc + Vector2(0, -hr.y * 0.5), Vector2(hr.x * 1.3, hr.y * 0.45), o, _d(dark, dim), dim)
			var w := hr.x * 0.75
			var y0 := hc.y - hr.y * 0.55
			var y1 := hc.y - hr.y * 1.65
			ci.draw_rect(Rect2(Vector2(hc.x - w - o, y1), Vector2((w + o) * 2, y0 - y1 + o)), _d(OUTLINE, dim))
			ci.draw_rect(Rect2(Vector2(hc.x - w, y1), Vector2(w * 2, y0 - y1)), _d(dark.lightened(0.08), dim))
			if detail:
				ci.draw_rect(Rect2(Vector2(hc.x - w, y0 - hr.y * 0.32), Vector2(w * 2, hr.y * 0.22)), _d(col, dim))
			_outlined_ellipse(ci, Vector2(hc.x, y1), Vector2(w, hr.y * 0.28), o, _d(dark.lightened(0.15), dim), dim)
		7:  # треуголка: три загнутых края с золотой каймой
			var pts := PackedVector2Array()
			for k in 3:
				var a := PI / 2 + TAU * k / 3.0  # передний угол — к зрителю
				pts.append(hc + Vector2(cos(a) * hr.x * 1.45, sin(a) * hr.y * 1.05 - hr.y * 0.45))
			var mid := (pts[0] + pts[1] + pts[2]) / 3.0
			var outer := PackedVector2Array()
			for p in pts:
				outer.append(mid + (p - mid) * 1.12)
			ci.draw_colored_polygon(outer, _d(Color(0.75, 0.6, 0.25), dim))
			ci.draw_colored_polygon(pts, _d(col, dim))
			_ellipse(ci, mid, hr * 0.42, _d(col.lightened(0.12), dim))  # тулья
			if detail:  # перо и кокарда
				var fp := mid.lerp(pts[1], 0.55)
				ci.draw_colored_polygon(PackedVector2Array([fp, fp + Vector2(-hr.x * 0.5, -hr.y * 0.75),
					fp + Vector2(-hr.x * 0.05, -hr.y * 0.35)]), _d(Color(0.92, 0.9, 0.85), dim))
				ci.draw_line(fp, fp + Vector2(-hr.x * 0.4, -hr.y * 0.6), _d(Color(0.7, 0.15, 0.12), dim), hr.x * 0.08)
				_ellipse(ci, mid.lerp(pts[0], 0.6), hr * 0.12, _d(Color(0.7, 0.15, 0.12), dim))
		6:  # повязка на лбу, концы узла
			_outlined_ellipse(ci, hc + Vector2(0, -hr.y * 0.42), Vector2(hr.x * 1.04, hr.y * 0.2), o, _d(col, dim), dim)
			if detail:
				var k := hc + (Vector2(hr.x * 1.0, -hr.y * 0.3) if front else Vector2(0, -hr.y * 0.3))
				_ellipse(ci, k + Vector2(hr.x * 0.12, hr.y * 0.22), Vector2(hr.x * 0.14, hr.y * 0.24), _d(col.darkened(0.15), dim))
				_ellipse(ci, k + Vector2(hr.x * 0.3, hr.y * 0.12), Vector2(hr.x * 0.14, hr.y * 0.22), _d(col.darkened(0.15), dim))

## Детали одежды поверх туловища.
static func _clothes(ci: CanvasItem, bc: Vector2, w: float, h: float, flare: float, u: float, lk: Dictionary, front: bool, dim: bool) -> void:
	var main: Color = lk.main
	var acc: Color = lk.accent
	var dark := main.darkened(0.25)
	match int(lk.style):
		0:  # футболка: рукава темнее, круглый вырез
			for s in [-1.0, 1.0]:
				_ellipse(ci, bc + Vector2(s * w * 0.8, -h * 0.4), Vector2(w * 0.24, h * 0.32), _d(main.darkened(0.12), dim))
			if front:
				_ellipse(ci, bc + Vector2(0, -h * 0.8), Vector2(w * 0.26, h * 0.2), _d(lk.skin, dim))
		1:  # рубашка: воротник, пуговицы, карман
			if front:
				for s in [-1.0, 1.0]:
					ci.draw_colored_polygon(PackedVector2Array([bc + Vector2(0, -h * 0.95), bc + Vector2(s * w * 0.42, -h * 0.98),
						bc + Vector2(s * w * 0.16, -h * 0.55)]), _d(SHIRT, dim))
				for k in 3:
					_ellipse(ci, bc + Vector2(0, -h * 0.35 + k * h * 0.4), Vector2.ONE * u * 0.022, _d(main.darkened(0.45), dim))
				ci.draw_rect(Rect2(bc + Vector2(-w * 0.62, -h * 0.35), Vector2(w * 0.3, h * 0.28)), _d(dark, dim))
		2:  # куртка: молния и карманы
			if front:
				ci.draw_line(bc + Vector2(0, -h * 0.85), bc + Vector2(0, h * 0.95), _d(main.darkened(0.45), dim), u * 0.03)
				for s in [-1.0, 1.0]:
					ci.draw_rect(Rect2(bc + Vector2(s * w * 0.55 - w * 0.17, h * 0.2), Vector2(w * 0.34, h * 0.07)), _d(dark, dim))
		3:  # комбинезон: нагрудник и лямки поверх рубашки
			_band(ci, bc, w, h, flare, -0.35, 1.0, _d(main, dim))
			if front:
				for s in [-1.0, 1.0]:
					ci.draw_line(bc + Vector2(s * w * 0.35, -h * 0.35), bc + Vector2(s * w * 0.45, -h * 0.9), _d(main, dim), u * 0.06)
					_ellipse(ci, bc + Vector2(s * w * 0.3, -h * 0.25), Vector2.ONE * u * 0.025, _d(acc.lightened(0.3), dim))
		4:  # мантия: пояс и тёмный подол
			_band(ci, bc, w, h, flare, 0.1, 0.25, _d(acc, dim))
			_band(ci, bc, w, h, flare, 0.78, 1.0, _d(dark, dim))
		5:  # свитер в полоску
			for t in [-0.45, 0.0, 0.45]:
				_band(ci, bc, w, h, flare, t, t + 0.16, _d(acc, dim))
		6:  # костюм: белая рубашка и галстук цвета типа
			if front:
				ci.draw_colored_polygon(PackedVector2Array([bc + Vector2(-w * 0.32, -h * 0.97), bc + Vector2(w * 0.32, -h * 0.97),
					bc + Vector2(0, h * 0.15)]), _d(SHIRT, dim))
				ci.draw_colored_polygon(PackedVector2Array([bc + Vector2(-w * 0.07, -h * 0.85), bc + Vector2(w * 0.07, -h * 0.85),
					bc + Vector2(w * 0.1, h * 0.05), bc + Vector2(0, h * 0.2), bc + Vector2(-w * 0.1, h * 0.05)]), _d(main.lightened(0.1), dim))
		8:  # камзол: полы, перевязь через плечо с сумкой, пояс с пряжкой, два ряда пуговиц, шейный платок
			_band(ci, bc, w, h, flare, 0.55, 1.0, _d(dark, dim))  # полы
			ci.draw_line(bc + Vector2(0, h * 0.55), bc + Vector2(0, h * 0.98), _d(OUTLINE, dim), u * 0.02)  # разрез
			_band(ci, bc, w, h, flare, 0.28, 0.42, _d(Color(0.25, 0.16, 0.1), dim))
			var s := 1.0 if front else -1.0
			ci.draw_colored_polygon(PackedVector2Array([bc + Vector2(-s * w * 0.75, -h * 0.85), bc + Vector2(-s * w * 0.48, -h * 0.95),
				bc + Vector2(s * w * 0.85, h * 0.45), bc + Vector2(s * w * 0.6, h * 0.62)]), _d(BELT, dim))
			ci.draw_rect(Rect2(bc + Vector2(s * w * 0.5 - w * 0.17, h * 0.42), Vector2(w * 0.34, h * 0.3)), _d(Color(0.35, 0.22, 0.12), dim))
			if front:
				ci.draw_rect(Rect2(bc + Vector2(-w * 0.1, h * 0.27), Vector2(w * 0.2, h * 0.17)), _d(Color(0.85, 0.66, 0.28), dim))
				for k in 3:
					for sx in [-1.0, 1.0]:
						_ellipse(ci, bc + Vector2(sx * w * 0.3, -h * 0.45 + k * h * 0.3), Vector2.ONE * u * 0.02, _d(Color(0.9, 0.72, 0.3), dim))
				ci.draw_colored_polygon(PackedVector2Array([bc + Vector2(-w * 0.25, -h * 0.98), bc + Vector2(w * 0.25, -h * 0.98),
					bc + Vector2(0, -h * 0.5)]), _d(SHIRT, dim))
		7:  # жилет с V-вырезом
			_band(ci, bc, w, h, flare, -0.62, 1.0, _d(main, dim))
			if front:
				ci.draw_colored_polygon(PackedVector2Array([bc + Vector2(-w * 0.3, -h * 0.66), bc + Vector2(w * 0.3, -h * 0.66),
					bc + Vector2(0, h * 0.05)]), _d(acc, dim))
				for k in 2:
					_ellipse(ci, bc + Vector2(0, h * 0.3 + k * h * 0.3), Vector2.ONE * u * 0.022, _d(main.darkened(0.45), dim))

## Форма туловища: округлые плечи, книзу чуть уже (или шире — flare).
static func _body(c: Vector2, w: float, h: float, flare: float) -> PackedVector2Array:
	# форма единичного размера считается один раз, дальше только масштаб и сдвиг (быстро)
	if not _bodies.has(flare):
		var pts := PackedVector2Array()
		for k in 28:
			var a := TAU * k / 28.0
			var sx := signf(cos(a)) * pow(absf(cos(a)), 0.65)
			var sy := signf(sin(a)) * pow(absf(sin(a)), 0.85)
			pts.append(Vector2(sx * _widen(sy, flare), sy))
		_bodies[flare] = pts
	return Transform2D(0.0, Vector2(w, h), 0.0, c) * (_bodies[flare] as PackedVector2Array)

static var _bodies := {}   # flare -> единичное туловище
static var _caps := {}     # fringe -> единичная шапка волос
static var _circle := PackedVector2Array()

static func _widen(t: float, flare: float) -> float:
	return lerpf(1.0, 0.86 * flare, maxf(t, 0.0))

## Полуширина туловища на высоте t (-1 верх .. 1 низ).
static func _hw(t: float, w: float, flare: float) -> float:
	var y := pow(absf(t), 1.0 / 0.85)
	return pow(sqrt(maxf(0.0, 1.0 - y * y)), 0.65) * w * _widen(t, flare)

## Полоса туловища между высотами t0..t1 (повторяет контур).
static func _band(ci: CanvasItem, c: Vector2, w: float, h: float, flare: float, t0: float, t1: float, col: Color) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for k in 7:
		var t := lerpf(t0, minf(t1, 0.98), k / 6.0)
		var hw := _hw(t, w, flare) * 0.97
		left.append(c + Vector2(-hw, t * h))
		right.append(c + Vector2(hw, t * h))
	right.reverse()
	ci.draw_colored_polygon(left + right, col)

## Шапка волос: верх головы и пряди по бокам до линии чёлки (fringe — доля радиуса, минус = выше центра).
static func _cap(c: Vector2, r: Vector2, fringe: float) -> PackedVector2Array:
	if not _caps.has(fringe):
		var pts := PackedVector2Array()
		for k in 17:
			var a := PI + PI * k / 16.0
			pts.append(Vector2(cos(a), sin(a)))
		for k in 5:
			var x := lerpf(0.9, -0.9, k / 4.0)
			var dip := 0.08 if k % 2 == 1 else 0.0  # неровная чёлка
			pts.append(Vector2(x, fringe + dip))
		_caps[fringe] = pts
	return Transform2D(0.0, r, 0.0, c) * (_caps[fringe] as PackedVector2Array)

static func _ellipse(ci: CanvasItem, c: Vector2, r: Vector2, col: Color) -> void:
	if _circle.is_empty():
		for k in 20:
			_circle.append(Vector2.from_angle(TAU * k / 20.0))
	ci.draw_colored_polygon(Transform2D(0.0, r, 0.0, c) * _circle, col)

static func _outlined_ellipse(ci: CanvasItem, c: Vector2, r: Vector2, o: float, col: Color, dim: bool) -> void:
	_ellipse(ci, c, r + Vector2(o, o), _d(OUTLINE, dim))
	_ellipse(ci, c, r, col)

static func _d(col: Color, dim: bool) -> Color:
	return col.darkened(0.6) if dim else col
