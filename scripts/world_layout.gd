class_name WorldLayout
extends RefCounted
## Раскладка материка по клеткам (клетка = TILE мировых единиц).
## Город — деревня без стен: площадь с колодцем, главные мощёные улицы с изломами, переулки-тропинки,
## дома и районы вдоль улиц дверью к дороге. Район (подпапка с подпапками) — такая же деревня поменьше.
## build() -> {n, ground, walk, walls, floors, decor, items, radius, origin}
##   ground: коды G (n*n); walk: 1 = по клетке можно ходить по улице (n*n)
##   walls: [[клетка, текстура, поворот A]]; floors: [[клетка, текстура]]; decor: [{c: центр в клетках, tex, s: размер}]
##   furniture: [{c: центр в клетках, tex, size: в клетках, rot}]
##   items (родитель раньше детей): {folder, kind, mat, depth, path, parent, cell, size, rect, pos, r,
##     door, door_side; у дома interior и furniture (занятые клетки); у города plaza (мир. Rect2)}

const TILE := 32.0
enum G { WATER, GRASS_1, GRASS_2, GRASS_3, GRASS_4, DIRT, SAND, PATH, STREET, PLAZA }
const G_TEX := ["", "ground_grass_1", "ground_grass_2", "ground_grass_3", "ground_grass_4",
	"ground_dirt", "ground_sand", "ground_path", "ground_street", "ground_plaza"]
const MATS := ["wood", "stone", "brick", "timber", "timber"]  # фахверк чаще — это деревня
const FLOOR_OF := {"wood": "floor_wood", "stone": "floor_stone", "brick": "floor_stone",
	"timber": "floor_wood", "hut": "floor_dirt"}
## Поворот плитки стены (alternative tile в Tiles.make_tileset).
enum A { NONE, FLIP_H, FLIP_V, FLIP_HV, T, T_FLIP_H }
const GAP := 3         # клеток между объектами на материке
const LABEL_ROWS := 4  # клеток под объектом, свободных для подписи
## Клетки сетки деревни при раскладке.
enum V { FREE, MAIN, LANE, PLAZA, RESERVED, BLOCK }
const DIRS4: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

## city / house / hut
static func kind(f) -> String:
	if f.is_city():
		return "city"
	return "hut" if f.file_count == 0 else "house"

## Пол дома в клетках, растёт с числом файлов.
static func house_interior(f) -> Vector2i:
	if f.file_count == 0:
		return Vector2i(2, 2)
	var s := sqrt(float(f.file_count))
	return Vector2i(3 + ceili(s * 0.9), 2 + ceili(s * 0.7))

## Материал стен по seed; пустая папка — хижина.
static func material(f, seed_value: int) -> String:
	if kind(f) == "hut":
		return "hut"
	return MATS[absi(hash(f.name + str(seed_value))) % MATS.size()]

## Узел раскладки. Дом: {folder, kind, mat, size}. Город/район — деревня:
## {folder, kind, size, plaza, roads: [[клетка, V]], kids: [{node, off, door_side}], entr: {сторона: смещение}, decor, block}.
## Все клетки — от левого верхнего угла узла.
static func make_node(f, seed_value: int) -> Dictionary:
	var k := kind(f)
	if k != "city":
		return {"folder": f, "kind": k, "mat": material(f, seed_value), "size": house_interior(f) + Vector2i(2, 2)}
	var kids := []
	for c in f.children:
		kids.append(make_node(c, seed_value))
	kids.sort_custom(func(a, b): return a.size.x * a.size.y > b.size.x * b.size.y)
	var front := 0
	for kd in kids:
		front += maxi(kd.size.x, kd.size.y) + 2
	var arm := maxi(5, ceili(front / 8.0) + 1)  # короче улицы — плотнее деревня
	var base := absi(hash(f.name)) + seed_value
	for attempt in 12:
		var v := _village(f, kids, arm, base + attempt)
		if not v.is_empty():
			return v
		arm += 4  # не влезли — улицы длиннее
	push_error("WorldLayout: деревня %s не сложилась" % f.name)
	return {}

# --- сетка деревни (клетки могут быть отрицательными) ---

static func _grid(r: int) -> Dictionary:
	var m := PackedByteArray()
	m.resize(4 * r * r)
	return {"r": r, "s": 2 * r, "m": m}

static func _gv(g: Dictionary, c: Vector2i) -> int:
	var x: int = c.x + g.r
	var y: int = c.y + g.r
	if x < 0 or y < 0 or x >= g.s or y >= g.s:
		return V.BLOCK
	return g.m[y * g.s + x]

static func _gs(g: Dictionary, c: Vector2i, v: int) -> void:
	var x: int = c.x + g.r
	var y: int = c.y + g.r
	if x >= 0 and y >= 0 and x < g.s and y < g.s:
		g.m[y * g.s + x] = v

static func _fill(g: Dictionary, r: Rect2i, v: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_gs(g, Vector2i(x, y), v)

## Клетка улицы. Главная улица может пройти по переулку и коридору, переулок — только по свободному.
static func _road(g: Dictionary, c: Vector2i, v: int, roads: Array[Vector2i]) -> void:
	var cur := _gv(g, c)
	if cur == V.FREE or cur == V.RESERVED or (v == V.MAIN and cur == V.LANE):
		_gs(g, c, v)
		if cur != V.LANE:
			roads.append(c)

## Деревня: площадь, 4 главные улицы с изломами и переулками, дома дверью к дороге.
## Пустой результат — не всё влезло (нужны улицы длиннее).
static func _village(f, kids: Array, arm: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ps := 5 + mini(5, kids.size() / 2)  # площадь 5..10 клеток
	var big := 0
	for kd in kids:
		big = maxi(big, maxi(kd.size.x, kd.size.y))
	var g := _grid(arm + ps + big * 2 + 16)
	var plaza := Rect2i(-ps / 2, -ps / 2, ps, ps)
	_fill(g, plaza, V.PLAZA)
	var cx := plaza.position.x + ps / 2
	var cy := plaza.position.y + ps / 2
	var starts := {Vector2i.UP: Vector2i(cx - 1, plaza.position.y - 1), Vector2i.DOWN: Vector2i(cx - 1, plaza.end.y),
		Vector2i.LEFT: Vector2i(plaza.position.x - 1, cy - 1), Vector2i.RIGHT: Vector2i(plaza.end.x, cy - 1)}
	var roads: Array[Vector2i] = []
	var tips := {}
	# главные улицы (2 клетки) из середин сторон площади
	for d in DIRS4:
		var side := Vector2i(absi(d.y), absi(d.x))
		var c: Vector2i = starts[d]
		var since := 0
		for i in arm:
			_road(g, c, V.MAIN, roads)
			_road(g, c + side, V.MAIN, roads)
			tips[d] = c
			# переулок вбок
			if i % 6 == 3 and rng.randf() < 0.75:
				var e := side if rng.randf() < 0.5 else -side
				var lc := c + side * 2 if e == side else c - side
				for j in rng.randi_range(4, 9):
					if _gv(g, lc) != V.FREE:
						break
					_road(g, lc, V.LANE, roads)
					lc += e
			var nxt := c + d
			if since > 2 and i < arm - 3 and rng.randf() < 0.4:
				# излом: улица плавно сдвигается вбок на клетку
				_road(g, nxt, V.MAIN, roads)
				_road(g, nxt + side, V.MAIN, roads)
				nxt += side if rng.randf() < 0.5 else -side
				since = 0
			c = nxt
			since += 1
		# коридор дальше по прямой: туда не ставим дома, потом улица дойдёт до края деревни
		var rc: Vector2i = tips[d] + d
		while _gv(g, rc) != V.BLOCK:
			for w in [rc, rc + side]:
				if _gv(g, w) == V.FREE:
					_gs(g, w, V.RESERVED)
			rc += d

	# места для дверей: свободная клетка рядом с улицей; ближе к площади — раньше
	var cand := []
	var edge_cells: Array[Vector2i] = []
	for y in range(plaza.position.y, plaza.end.y):
		for x in range(plaza.position.x, plaza.end.x):
			if x == plaza.position.x or y == plaza.position.y or x == plaza.end.x - 1 or y == plaza.end.y - 1:
				edge_cells.append(Vector2i(x, y))
	# колодец и лавки площади: к ним дверью не выходят
	var solid := {}
	for c in _plaza_solid(plaza, cx, cy):
		solid[c] = true
	for rc in roads + edge_cells:
		if solid.has(rc):
			continue
		var lane := _gv(g, rc) == V.LANE
		for s in DIRS4:
			var dc: Vector2i = rc + s
			if _gv(g, dc) == V.FREE:
				cand.append({"d": dc, "s": s, "k": Vector2(dc).length() + rng.randf() * 3.0 + (3.0 if lane else 0.0)})
	cand.sort_custom(func(a, b): return a.k < b.k)

	var placed: Array[Rect2i] = []
	var kids_out := []
	for kd in kids:
		var ok := false
		for cd in cand:
			var dc: Vector2i = cd.d
			var s: Vector2i = cd.s
			if _gv(g, dc) != V.FREE:
				continue
			var nd: Dictionary = kd
			var sz: Vector2i = kd.size
			var off: int
			if kd.kind == "city":
				off = kd.entr[-s]  # район примыкает своей улицей
			else:
				# дом длинной стороной вдоль улицы, дверь посередине
				var lo := mini(sz.x, sz.y)
				var hi := maxi(sz.x, sz.y)
				sz = Vector2i(hi, lo) if s.y != 0 else Vector2i(lo, hi)
				off = (sz.x if s.y != 0 else sz.y) / 2
				if sz != kd.size:
					nd = kd.duplicate()
					nd.size = sz
			var r := _rect_from_door(dc, s, sz, off)
			if not _fits(g, r, placed):
				continue
			placed.append(r)
			_fill(g, r, V.BLOCK)
			kids_out.append({"node": nd, "off": r.position, "door_side": -s})
			ok = true
			break
		if not ok:
			return {}

	# граница деревни и выходы главных улиц на все 4 стороны
	var b := plaza
	for c in roads:
		b = b.merge(Rect2i(c, Vector2i.ONE))
	for r in placed:
		b = b.merge(r)
	b = b.grow(1)
	var entr := {}
	for d in DIRS4:
		var side := Vector2i(absi(d.y), absi(d.x))
		var c: Vector2i = tips[d] + d
		while b.has_point(c):
			_road(g, c, V.MAIN, roads)
			_road(g, c + side, V.MAIN, roads)
			c += d
		var last: Vector2i = c - d
		entr[d] = (last.x - b.position.x) if d.y != 0 else (last.y - b.position.y)

	var deco := _village_decor(g, plaza, cx, cy, placed, roads, b, rng)
	var road_cells := []
	for y in range(b.position.y, b.end.y):
		for x in range(b.position.x, b.end.x):
			var v := _gv(g, Vector2i(x, y))
			if v == V.MAIN or v == V.LANE or v == V.PLAZA:
				road_cells.append([Vector2i(x, y) - b.position, v])
	for k in kids_out:
		k.off -= b.position
	for d in deco.decor:
		d.c -= Vector2(b.position)
	var block := []
	for c in deco.block:
		block.append(c - b.position)
	return {"folder": f, "kind": "city", "size": b.size, "plaza": Rect2i(plaza.position - b.position, plaza.size),
		"roads": road_cells, "kids": kids_out, "entr": entr, "decor": deco.decor, "block": block}

## Прямоугольник объекта размера sz, лежащего в сторону s от улицы; dc — его клетка у дороги (дверь/въезд),
## off — смещение dc вдоль примыкающей стороны.
static func _rect_from_door(dc: Vector2i, s: Vector2i, sz: Vector2i, off: int) -> Rect2i:
	if s == Vector2i.DOWN:
		return Rect2i(dc.x - off, dc.y, sz.x, sz.y)
	if s == Vector2i.UP:
		return Rect2i(dc.x - off, dc.y - sz.y + 1, sz.x, sz.y)
	if s == Vector2i.RIGHT:
		return Rect2i(dc.x, dc.y - off, sz.x, sz.y)
	return Rect2i(dc.x - sz.x + 1, dc.y - off, sz.x, sz.y)

static func _fits(g: Dictionary, r: Rect2i, placed: Array[Rect2i]) -> bool:
	for p in placed:
		if p.grow(1).intersects(r):
			return false  # между домами проулок в клетку
	for c in [r.position, r.end - Vector2i.ONE, Vector2i(r.position.x, r.end.y - 1), Vector2i(r.end.x - 1, r.position.y), r.get_center()]:
		if _gv(g, c) != V.FREE:
			return false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if _gv(g, Vector2i(x, y)) != V.FREE:
				return false
	return true

## Колодец, лавки, фонари, бочки/ящики/сено у домов, деревья и цветы во дворах.
static func _village_decor(g: Dictionary, plaza: Rect2i, cx: int, cy: int, placed: Array[Rect2i],
		roads: Array[Vector2i], b: Rect2i, rng: RandomNumberGenerator) -> Dictionary:
	var decor := []
	var block: Array[Vector2i] = _plaza_solid(plaza, cx, cy)
	var used := {}
	# колодец в центре площади, рыночные лавки по углам большой площади
	decor.append({"c": Vector2(cx, cy), "tex": "decor_well", "s": 2.0})
	if plaza.size.x >= 8:
		decor.append({"c": Vector2(plaza.position) + Vector2.ONE, "tex": "decor_stall_1", "s": 2.0})
		decor.append({"c": Vector2(plaza.end) - Vector2.ONE, "tex": "decor_stall_2", "s": 2.0})
	# фонари вдоль главных улиц
	for i in range(0, roads.size(), 9):
		var rc: Vector2i = roads[i]
		if _gv(g, rc) != V.MAIN:
			continue
		for s in DIRS4:
			var lc: Vector2i = rc + s
			if _gv(g, lc) == V.FREE and not used.has(lc):
				used[lc] = true
				decor.append({"c": Vector2(lc) + Vector2(0.5, 0.5), "tex": "decor_lamp", "s": 1.0})
				break
	# бочки, ящики, сено у стен домов
	var props := ["decor_barrel", "decor_crate", "decor_haybale"]
	for r in placed:
		for k in rng.randi_range(0, 2):
			var around: Array[Vector2i] = []
			for x in range(r.position.x, r.end.x):
				around.append(Vector2i(x, r.position.y - 1))
				around.append(Vector2i(x, r.end.y))
			for y in range(r.position.y, r.end.y):
				around.append(Vector2i(r.position.x - 1, y))
				around.append(Vector2i(r.end.x, y))
			var c: Vector2i = around[rng.randi_range(0, around.size() - 1)]
			if _gv(g, c) == V.FREE and not used.has(c):
				used[c] = true
				decor.append({"c": Vector2(c) + Vector2(0.5, 0.5), "tex": props[rng.randi_range(0, 2)], "s": 1.0})
	# зелень во дворах: деревья только там, где крона никого не задевает
	for y in range(b.position.y + 1, b.end.y - 1):
		for x in range(b.position.x + 1, b.end.x - 1):
			var c := Vector2i(x, y)
			if _gv(g, c) != V.FREE or used.has(c):
				continue
			var roll := rng.randf()
			if roll < 0.03 and _clear_around(g, c, used):
				used[c] = true
				decor.append({"c": Vector2(c) + Vector2(0.5, 0.5), "tex": "decor_tree_%d" % rng.randi_range(1, 3), "s": 2.0})
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						used[c + Vector2i(dx, dy)] = true
			elif roll < 0.06:
				used[c] = true
				decor.append({"c": Vector2(c) + Vector2(0.5, 0.5), "tex": "decor_bush_%d" % rng.randi_range(1, 2), "s": 1.0})
			elif roll < 0.11:
				used[c] = true
				decor.append({"c": Vector2(c) + Vector2(0.5, 0.5), "tex": "decor_flowers_%d" % rng.randi_range(1, 2), "s": 1.0})
	return {"decor": decor, "block": block}

## Непроходимые клетки площади: колодец 2x2 в центре и лавки 2x2 по углам площади от 8 клеток
## (между ними и колодцем остаётся проход, площадь не делится).
static func _plaza_solid(plaza: Rect2i, cx: int, cy: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var corners: Array[Vector2i] = [Vector2i(cx - 1, cy - 1)]
	if plaza.size.x >= 8:
		corners.append(plaza.position)
		corners.append(plaza.end - Vector2i(2, 2))
	for c0 in corners:
		for dy in 2:
			for dx in 2:
				out.append(c0 + Vector2i(dx, dy))
	return out

static func _clear_around(g: Dictionary, c: Vector2i, used: Dictionary) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			if _gv(g, n) != V.FREE or used.has(n):
				return false
	return true

## Весь материк для корня диска.
static func build(root, seed_value: int) -> Dictionary:
	var nodes := []
	var area := 0
	for c in root.children:
		var nd := make_node(c, seed_value)
		nodes.append(nd)
		area += (nd.size.x + GAP * 2) * (nd.size.y + GAP * 2 + LABEL_ROWS)
	nodes.sort_custom(func(a, b): return a.size.x * a.size.y > b.size.x * b.size.y)
	var n := ceili(sqrt(area * 2.6)) + 16  # материк компактнее — меньше клеток, быстрее
	for attempt in 30:
		var land := make_land(seed_value + attempt, n)
		var spots := _place_on_land(nodes, land, n, seed_value + attempt)
		if spots.size() == nodes.size():
			return _finish(root, nodes, spots, land, n, seed_value)
		n = int(n * 1.12)  # не влезло — материк побольше
	push_error("WorldLayout: объекты не поместились")
	return {}

## Маска суши n*n (1 = суша): размытый шум, сглаженный берег, один материк, без мелких озёр.
static func make_land(seed_value: int, n: int) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 3.5 / n
	noise.fractal_octaves = 5
	var warp := FastNoiseLite.new()
	warp.seed = seed_value + 7
	warp.frequency = 2.0 / n
	var m := PackedByteArray()
	m.resize(n * n)
	for y in n:
		for x in n:
			if x < 3 or y < 3 or x >= n - 3 or y >= n - 3:
				continue  # край карты — море
			var p := Vector2(x + 0.5, y + 0.5) / n - Vector2(0.5, 0.5)
			p += Vector2(warp.get_noise_2d(x, y), warp.get_noise_2d(x + 999, y)) * 0.12
			var s := 1.0 - p.length() / 0.38 + noise.get_noise_2d(x, y) * 0.5
			m[y * n + x] = 1 if s > 0.0 else 0
	m = _smooth(m, n)
	m = _smooth(m, n)
	# только самый большой кусок суши
	var comps := _components(m, n, 1)
	var best: Array = []
	for c in comps:
		if c.size() > best.size():
			best = c
	for c in comps:
		if c != best:
			for i in c:
				m[i] = 0
	# мелкие озёра засыпаем
	for c in _components(m, n, 0):
		if c.size() < 25 and not _touches_border(c, n):
			for i in c:
				m[i] = 1
	return m

## Клетка становится сушей, если в окрестности 3x3 суши больше половины (суммы по строкам — быстро).
static func _smooth(m: PackedByteArray, n: int) -> PackedByteArray:
	var out := m.duplicate()
	var rows := PackedInt32Array()  # сумма трёх соседей по горизонтали
	rows.resize(n * n)
	for y in n:
		for x in range(1, n - 1):
			var i := y * n + x
			rows[i] = m[i - 1] + m[i] + m[i + 1]
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			var i := y * n + x
			out[i] = 1 if rows[i - n] + rows[i] + rows[i + n] >= 5 else 0
	return out

## Связные области клеток со значением value (4 соседа): массив массивов индексов.
static func _components(m: PackedByteArray, n: int, value: int) -> Array:
	var seen := PackedByteArray()
	seen.resize(n * n)
	var out := []
	for start in n * n:
		if m[start] != value or seen[start] == 1:
			continue
		var comp := []
		var stack := [start]
		seen[start] = 1
		while not stack.is_empty():
			var i: int = stack.pop_back()
			comp.append(i)
			var x := i % n
			for nb in [i - 1 if x > 0 else -1, i + 1 if x < n - 1 else -1, i - n, i + n]:
				if nb >= 0 and nb < n * n and m[nb] == value and seen[nb] == 0:
					seen[nb] = 1
					stack.append(nb)
		out.append(comp)
	return out

static func _touches_border(comp: Array, n: int) -> bool:
	for i in comp:
		var x: int = i % n
		var y: int = i / n
		if x == 0 or y == 0 or x == n - 1 or y == n - 1:
			return true
	return false

static func _all_land(m: PackedByteArray, n: int, r: Rect2i) -> bool:
	if r.position.x < 0 or r.position.y < 0 or r.end.x > n or r.end.y > n:
		return false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if m[y * n + x] == 0:
				return false
	return true

## Случайные места на суше без наложений; меньше мест = не влезло.
static func _place_on_land(nodes: Array, m: PackedByteArray, n: int, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var placed: Array[Rect2i] = []
	var out := []
	for nd in nodes:
		var s: Vector2i = nd.size
		if n - s.x - 3 <= 2 or n - s.y - 4 <= 2:
			return out
		var ok := false
		for t in 800:
			var c := Vector2i(rng.randi_range(2, n - s.x - 3), rng.randi_range(2, n - s.y - 4))
			var r := Rect2i(c, s)
			if not _all_land(m, n, r.grow(1)):
				continue
			# снизу место под подпись
			var taken := r.grow_individual(0, 0, 0, LABEL_ROWS)
			var free := true
			for p in placed:
				if p.grow(GAP).intersects(taken):
					free = false
					break
			if free:
				placed.append(taken)
				out.append(c)
				ok = true
				break
		if not ok:
			return out
	return out

static func _finish(root, nodes: Array, spots: Array, land: PackedByteArray, n: int, seed_value: int) -> Dictionary:
	var ctx := {"n": n, "ground": _paint_ground(land, n, seed_value), "walls": [], "floors": [], "decor": [],
		"furniture": [], "block": [], "origin": -Vector2(n, n) * TILE / 2}
	var items := []
	for i in nodes.size():
		_flatten(nodes[i], spots[i], 1, [root], items, ctx, Vector2i.DOWN)
	_paths(items, ctx)
	var decor: Array = ctx.decor + _decor(items, ctx, seed_value)
	# где можно ходить по улице: мостовые, площади, тропинки (кроме колодцев и лавок)
	var walk := PackedByteArray()
	walk.resize(n * n)
	for i in n * n:
		var g: int = ctx.ground[i]
		walk[i] = 1 if g == G.PATH or g == G.STREET or g == G.PLAZA else 0
	for c in ctx.block:
		walk[c.y * n + c.x] = 0
	return {"n": n, "ground": ctx.ground, "walk": walk, "walls": ctx.walls, "floors": ctx.floors, "decor": decor,
		"furniture": ctx.furniture, "items": items, "radius": n * TILE * 0.4, "origin": ctx.origin}

## Земля: песок у берега, дальше почва с пятнами травы — густота плавно меняется по шуму.
static func _paint_ground(land: PackedByteArray, n: int, seed_value: int) -> PackedByteArray:
	var dist := _dist_to_water(land, n)
	var grass := FastNoiseLite.new()
	grass.seed = seed_value + 3
	grass.frequency = 0.06
	grass.fractal_octaves = 3
	var sand := FastNoiseLite.new()
	sand.seed = seed_value + 4
	sand.frequency = 0.15
	var g := PackedByteArray()
	g.resize(n * n)
	for y in n:
		for x in n:
			var i := y * n + x
			if land[i] == 0:
				g[i] = G.WATER
			elif dist[i] <= 1 or (dist[i] == 2 and sand.get_noise_2d(x, y) > 0.0):
				g[i] = G.SAND
			else:
				# чуть дрожи, чтобы границы пятен были неровными
				var v := grass.get_noise_2d(x, y) + (absi(hash(i * 7919 + seed_value)) % 100) / 100.0 * 0.08
				g[i] = G.GRASS_1 if v > 0.22 else (G.GRASS_2 if v > 0.08 else (G.GRASS_3 if v > -0.06 \
					else (G.GRASS_4 if v > -0.2 else G.DIRT)))
	return g

## Деревья, кусты, камни, цветы на свободной земле вне деревень и домов.
static func _decor(items: Array, ctx: Dictionary, seed_value: int) -> Array:
	var n: int = ctx.n
	var blocked := PackedByteArray()
	blocked.resize(n * n)
	for it in items:
		if it.depth != 1:
			continue
		var r := Rect2i(it.cell, it.size).grow(2).grow_individual(0, 0, 0, LABEL_ROWS)
		for y in range(maxi(r.position.y, 0), mini(r.end.y, n)):
			for x in range(maxi(r.position.x, 0), mini(r.end.x, n)):
				blocked[y * n + x] = 1
	var forest := FastNoiseLite.new()
	forest.seed = seed_value + 11
	forest.frequency = 0.05
	var cells := []
	var trees := {}  # клетки с деревьями — проверка соседей за O(1)
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			var i := y * n + x
			var g: int = ctx.ground[i]
			if blocked[i] == 1 or g == G.WATER or g == G.PATH or g == G.STREET or g == G.PLAZA:
				continue
			var h := absi(hash(i * 2654435 + seed_value)) % 1000
			var f := forest.get_noise_2d(x, y)
			var tex := ""
			if g != G.SAND and ((f > 0.25 and h < 170) or h < 12) and not _tree_near(trees, Vector2i(x, y)):
				tex = "decor_tree_%d" % (h % 3 + 1)  # рощи и одиночные деревья
				trees[Vector2i(x, y)] = true
			elif h < 30:
				tex = "decor_rock_%d" % (h % 3 + 1)
			elif g != G.SAND and h < 70:
				tex = "decor_bush_%d" % (h % 2 + 1)
			elif (g == G.GRASS_1 or g == G.GRASS_2) and h < 110:
				tex = "decor_flowers_%d" % (h % 2 + 1)
			if tex != "":
				cells.append([Vector2i(x, y), tex])
	var out := []
	for c in cells:
		out.append({"c": Vector2(c[0]) + Vector2(0.5, 0.5), "tex": c[1], "s": 2.0 if String(c[1]).begins_with("decor_tree") else 1.0})
	return out

## Рядом (в 1 клетке) уже есть дерево — кроны не слипаются в кашу.
static func _tree_near(trees: Dictionary, c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if trees.has(c + Vector2i(dx, dy)):
				return true
	return false

## Расстояние от суши до воды в клетках (обход в ширину, не дальше 3).
static func _dist_to_water(land: PackedByteArray, n: int) -> PackedInt32Array:
	var d := PackedInt32Array()
	d.resize(n * n)
	d.fill(99)
	var q := []
	for i in n * n:
		if land[i] == 0:
			d[i] = 0
			q.append(i)
	var head := 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		if d[i] >= 3:
			continue
		var x := i % n
		for nb in [i - 1 if x > 0 else -1, i + 1 if x < n - 1 else -1, i - n, i + n]:
			if nb >= 0 and nb < n * n and d[nb] > d[i] + 1:
				d[nb] = d[i] + 1
				q.append(nb)
	return d

static func _set_g(ctx: Dictionary, c: Vector2i, code: int) -> void:
	ctx.ground[c.y * ctx.n + c.x] = code

## Клетка двери в стене дома размера size на стороне side.
static func door_cell(cell: Vector2i, size: Vector2i, side: Vector2i) -> Vector2i:
	if side == Vector2i.UP:
		return cell + Vector2i(size.x / 2, 0)
	if side == Vector2i.DOWN:
		return cell + Vector2i(size.x / 2, size.y - 1)
	if side == Vector2i.LEFT:
		return cell + Vector2i(0, size.y / 2)
	return cell + Vector2i(size.x - 1, size.y / 2)

static func _flatten(nd: Dictionary, cell: Vector2i, depth: int, path: Array, items: Array, ctx: Dictionary, door_side: Vector2i) -> void:
	var f = nd.folder
	var my_path := path.duplicate()
	my_path.append(f)
	var rect := Rect2(ctx.origin + Vector2(cell) * TILE, Vector2(nd.size) * TILE)
	var it := {"folder": f, "kind": nd.kind, "depth": depth, "path": my_path, "parent": path[-1],
		"cell": cell, "size": nd.size, "rect": rect, "pos": rect.get_center(), "r": rect.size.length() / 2}
	if nd.kind == "city":
		it.mat = "stone"
		var pl: Rect2i = nd.plaza
		it.plaza = Rect2(ctx.origin + Vector2(cell + pl.position) * TILE, Vector2(pl.size) * TILE)
		it.door = cell + Vector2i(nd.entr[Vector2i.DOWN], nd.size.y - 1)
		it.door_side = Vector2i.DOWN
		_paint_village(nd, cell, ctx)
	else:
		it.mat = nd.mat
		it.interior = rect.grow(-TILE)  # пол без стен
		it.door_side = door_side
		it.door = door_cell(cell, nd.size, door_side)
		_paint_house(nd, cell, door_side, ctx)
		var fu := _furnish(nd, cell, door_side, ctx)
		it.furniture = fu.blocked
		it.spots = fu.spots
	items.append(it)
	for kd in nd.get("kids", []):
		_flatten(kd.node, cell + kd.off, depth + 1, my_path, items, ctx, kd.door_side)

## Деревня: мостовые, переулки, площадь; декор и непроходимые клетки (колодец, лавки).
static func _paint_village(nd: Dictionary, cell: Vector2i, ctx: Dictionary) -> void:
	for rc in nd.roads:
		var code: int = G.PLAZA
		if rc[1] == V.MAIN:
			code = G.STREET
		elif rc[1] == V.LANE:
			code = G.PATH
		_set_g(ctx, cell + rc[0], code)
	for d in nd.decor:
		ctx.decor.append({"c": d.c + Vector2(cell), "tex": d.tex, "s": d.s})
	for c in nd.block:
		ctx.block.append(cell + c)

## Дом: пол внутри, стены по краю (углы, прямые), дверь на стороне door_side.
static func _paint_house(nd: Dictionary, cell: Vector2i, door_side: Vector2i, ctx: Dictionary) -> void:
	var s: Vector2i = nd.size
	var mat: String = nd.mat
	var door := door_cell(Vector2i.ZERO, s, door_side)
	for y in s.y:
		for x in s.x:
			var p := Vector2i(x, y)
			var g := cell + p
			var edge := x == 0 or y == 0 or x == s.x - 1 or y == s.y - 1
			if not edge or p == door:
				ctx.floors.append([g, FLOOR_OF[mat]])
			if not edge:
				continue
			var tex := "wall_" + mat
			var alt := A.NONE
			if (x == 0 or x == s.x - 1) and (y == 0 or y == s.y - 1):
				tex += "_corner"
				alt = [A.NONE, A.FLIP_H, A.FLIP_V, A.FLIP_HV][int(x > 0) + 2 * int(y > 0)]
			else:
				if y == s.y - 1:
					alt = A.FLIP_V
				elif x == 0 and y > 0:
					alt = A.T
				elif x == s.x - 1 and y > 0:
					alt = A.T_FLIP_H
				if p == door:
					tex += "_door"
			ctx.walls.append([g, tex, alt])

## Поворот предмета, стоящего спиной к стене side (на картинке спина сверху).
const WALL_ROT := {Vector2i.UP: 0.0, Vector2i.RIGHT: PI / 2, Vector2i.DOWN: PI, Vector2i.LEFT: -PI / 2}

## Мебель дома: кровати изголовьем к стене (лучше напротив двери), очаг, сундуки, шкафы, растения вдоль стен,
## посередине коврик и стол со стульями. Свободный пол остаётся связным (от двери дойти до любой
## свободной клетки) и вмещает всех жителей. Пишет в ctx.furniture {c: центр в клетках, tex, size, rot};
## возвращает {blocked: занятые мебелью клетки, spots: {клетка: чем там занят житель}} (клетки мировые).
## Стулья и коврик не мешают ходить.
static func _furnish(nd: Dictionary, cell: Vector2i, door_side: Vector2i, ctx: Dictionary) -> Dictionary:
	var f = nd.folder
	var s: Vector2i = nd.size
	var st := {"inner": Rect2i(Vector2i.ONE, s - Vector2i(2, 2)), "used": {}, "soft": {}, "items": [],
		"entry": door_cell(Vector2i.ZERO, s, door_side) - door_side}
	var people := WorldMap.drawn_count(f)
	st.need = people + maxi(2, people / 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(String(f.name) + "/furniture"))
	var inner: Rect2i = st.inner
	# места у стен: [клетка, сторона стены]
	var spots := []
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			for w in DIRS4:
				if not inner.has_point(Vector2i(x, y) + w):
					spots.append([Vector2i(x, y), w])
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	if nd.kind == "hut":
		_along_wall(st, spots, "decor_crate", rng)
	else:
		var area := inner.size.x * inner.size.y
		# середина: коврик, стол, стулья вокруг стола
		if inner.size.x >= 5 and inner.size.y >= 4:
			var mid := inner.position + inner.size / 2 - Vector2i.ONE
			if inner.size.x >= 6 and inner.size.y >= 5:
				_put(st, [mid, mid + Vector2i.RIGHT, mid + Vector2i.DOWN, mid + Vector2i.ONE], "furn_rug", 0.0, Vector2(2, 2), false)
			var table := mid + Vector2i(rng.randi_range(0, 1), rng.randi_range(0, 1))
			if _put(st, [table], "furn_table", 0.0, Vector2.ONE, true):
				for w in DIRS4:
					if rng.randf() < 0.6:
						_put(st, [table + w], "furn_chair", WALL_ROT[w], Vector2.ONE, false)  # лицом к столу
		# кровати: спальные места напротив двери ставим первыми
		var bed_spots := spots.duplicate()
		bed_spots.sort_custom(func(a, b): return int(a[1] != -door_side) < int(b[1] != -door_side))
		for k in clampi(ceili(f.file_count / 10.0), 1, 3):
			for sp in bed_spots:
				if _put(st, [sp[0], sp[0] - sp[1]], "furn_bed", WALL_ROT[sp[1]], Vector2(1, 2), true):
					break
		var rest := ["furn_stove", "furn_chest", "furn_plant"]
		if f.file_count >= 5:
			rest.append("furn_shelf")
		if area >= 20:
			rest.append("furn_wardrobe")
		if f.file_count > 20:
			rest += ["furn_chest", "decor_barrel", "furn_shelf"]
		if rng.randf() < 0.5:
			rest.append("furn_plant")
		for tex in rest:
			_along_wall(st, spots, tex, rng)
	var out: Array[Vector2i] = []
	for c in st.used:
		out.append(cell + c)
	var busy := {}  # клетка -> занятие
	for d in st.items:
		ctx.furniture.append({"c": d.c + Vector2(cell), "tex": d.tex, "size": d.size, "rot": d.rot})
		if not SPOT_TEXT.has(d.tex):
			continue
		for c in d.cells:
			if d.tex == "furn_chair":
				busy[cell + c] = SPOT_TEXT[d.tex]  # на стул садятся
				continue
			for w in DIRS4:
				var nb: Vector2i = c + w
				if inner.has_point(nb) and not st.used.has(nb) and not busy.has(cell + nb):
					busy[cell + nb] = SPOT_TEXT[d.tex]
	return {"blocked": out, "spots": busy}

## Чем занят житель у предмета мебели.
const SPOT_TEXT := {"furn_chair": "сидит за столом", "furn_stove": "греется у очага", "furn_shelf": "читает книгу у полки",
	"furn_chest": "роется в сундуке", "furn_wardrobe": "выбирает одежду в шкафу", "furn_plant": "поливает цветок",
	"furn_bed": "заправляет кровать", "furn_table": "накрывает на стол", "decor_barrel": "черпает воду из бочки",
	"decor_crate": "разбирает ящик"}

## Поставить предмет 1x1 спиной к стене в первое подходящее место.
static func _along_wall(st: Dictionary, spots: Array, tex: String, rng: RandomNumberGenerator) -> void:
	var start := rng.randi_range(0, spots.size() - 1)
	for k in spots.size():
		var sp = spots[(start + k) % spots.size()]
		if _put(st, [sp[0]], tex, WALL_ROT[sp[1]], Vector2.ONE, true):
			return

## Занять клетки предметом. block — ходить нельзя: тогда свободный пол должен остаться связным и просторным.
static func _put(st: Dictionary, cells: Array, tex: String, rot: float, size: Vector2, block: bool) -> bool:
	var used: Dictionary = st.used
	var lo := Vector2(cells[0])
	var hi := lo
	for c in cells:
		if not st.inner.has_point(c) or used.has(c) or st.soft.has(c) or (block and c == st.entry):
			return false
		lo = lo.min(Vector2(c))
		hi = hi.max(Vector2(c))
	if block:
		for c in cells:
			used[c] = true
		if not _floor_ok(st):
			for c in cells:
				used.erase(c)
			return false
	elif tex != "furn_rug":
		for c in cells:
			st.soft[c] = true  # стул: ходить можно, но на нём больше ничего не ставим
	st.items.append({"c": (lo + hi) / 2 + Vector2(0.5, 0.5), "tex": tex, "size": size, "rot": rot, "cells": cells})
	return true

## Свободный пол связен (обход от клетки у двери) и вмещает жителей.
static func _floor_ok(st: Dictionary) -> bool:
	var inner: Rect2i = st.inner
	var used: Dictionary = st.used
	var free := inner.size.x * inner.size.y - used.size()
	if free < st.need:
		return false
	var seen := {st.entry: true}
	var q: Array[Vector2i] = [st.entry]
	var head := 0
	while head < q.size():
		var c := q[head]
		head += 1
		for w in DIRS4:
			var nb := c + w
			if inner.has_point(nb) and not used.has(nb) and not seen.has(nb):
				seen[nb] = true
				q.append(nb)
	return q.size() == free

## Тропинки между входами объектов верхнего уровня (минимальное остовное дерево).
static func _paths(items: Array, ctx: Dictionary) -> void:
	var n: int = ctx.n
	var blocked := PackedByteArray()
	blocked.resize(n * n)
	var doors: Array[Vector2i] = []
	for it in items:
		if it.depth != 1:
			continue
		doors.append(it.door + it.door_side)
		for y in range(it.cell.y, it.cell.y + it.size.y):
			for x in range(it.cell.x, it.cell.x + it.size.x):
				blocked[y * n + x] = 1
	if doors.size() < 2:
		return
	var in_tree := [0]
	while in_tree.size() < doors.size():
		var best := [-1, -1, INF]
		for a in in_tree:
			for b in doors.size():
				if b in in_tree:
					continue
				var d := Vector2(doors[a]).distance_to(Vector2(doors[b]))
				if d < best[2]:
					best = [a, b, d]
		in_tree.append(best[1])
		_highway(doors[best[0]], doors[best[1]], ctx, blocked)

## Дорога между воротами двух городов: мощёная, в две клетки по суше в обход городов и озёр,
## с редкими поворотами (идём прямо, пока это приближает к цели). Не нашлась — прямая линия.
static func _highway(a: Vector2i, b: Vector2i, ctx: Dictionary, blocked: PackedByteArray) -> void:
	var n: int = ctx.n
	var dist := PackedInt32Array()
	for grow in [24, n]:
		var box := Rect2i(a, Vector2i.ZERO).expand(b).grow(grow).intersection(Rect2i(0, 0, n, n))
		dist = _road_dist(b, box, ctx, blocked)
		if dist[a.y * n + a.x] >= 0:
			break
	if dist[a.y * n + a.x] < 0:
		_line(a, b, ctx, blocked)
		return
	var p := a
	var dir := Vector2i(signi(b.x - a.x), 0) if absi(b.x - a.x) > absi(b.y - a.y) else Vector2i(0, signi(b.y - a.y))
	var guard := n * 4
	_road_cell(p, ctx, blocked)
	while p != b and guard > 0:
		guard -= 1
		var d := dist[p.y * n + p.x]
		var nx := p + dir
		if not _road_step(nx, d, n, dist):
			# поворот: сначала туда, где цель
			var opts: Array[Vector2i] = [Vector2i(signi(b.x - p.x), 0), Vector2i(0, signi(b.y - p.y))]
			opts.append_array(DIRS4)
			for o in opts:
				if o != Vector2i.ZERO and _road_step(p + o, d, n, dist):
					# угол поворота заполняем, чтобы ширина не рвалась
					_road_cell(p + Vector2i(-dir.y, dir.x), ctx, blocked)
					dir = o
					break
			nx = p + dir
		p = nx
		_road_cell(p, ctx, blocked)
		_road_cell(p + Vector2i(-dir.y, dir.x), ctx, blocked)  # вторая полоса

static func _road_step(c: Vector2i, d: int, n: int, dist: PackedInt32Array) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < n and c.y < n and dist[c.y * n + c.x] == d - 1 and d > 0

static func _road_cell(c: Vector2i, ctx: Dictionary, blocked: PackedByteArray) -> void:
	var n: int = ctx.n
	if c.x < 0 or c.y < 0 or c.x >= n or c.y >= n:
		return
	var i := c.y * n + c.x
	var g: int = ctx.ground[i]
	if blocked[i] == 0 and g != G.WATER and g != G.PLAZA:
		ctx.ground[i] = G.STREET  # мощёная: грунтовая тропинка сливалась с землёй

## Расстояния (в шагах) до клетки b по суше внутри box; -1 — не дойти.
static func _road_dist(b: Vector2i, box: Rect2i, ctx: Dictionary, blocked: PackedByteArray) -> PackedInt32Array:
	var n: int = ctx.n
	var dist := PackedInt32Array()
	dist.resize(n * n)
	dist.fill(-1)
	var start := b.y * n + b.x
	dist[start] = 0
	var q := PackedInt32Array([start])
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var x := i % n
		var y := i / n
		for k in 4:
			var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
			if not box.has_point(Vector2i(nx, ny)):
				continue
			var j := ny * n + nx
			if dist[j] < 0 and blocked[j] == 0 and ctx.ground[j] != G.WATER:
				dist[j] = dist[i] + 1
				q.append(j)
	return dist

## Линия из клеток с шагами только по осям.
static func _line(a: Vector2i, b: Vector2i, ctx: Dictionary, blocked: PackedByteArray) -> void:
	var p := a
	var n: int = ctx.n
	while true:
		var i := p.y * n + p.x
		var g: int = ctx.ground[i]
		if blocked[i] == 0 and g != G.WATER and g != G.STREET and g != G.PLAZA:
			ctx.ground[i] = G.PATH
		if p == b:
			break
		var d := b - p
		# шаг по той оси, где отставание больше
		if absi(d.x) * absi(b.y - a.y) >= absi(d.y) * absi(b.x - a.x) and d.x != 0:
			p.x += signi(d.x)
		elif d.y != 0:
			p.y += signi(d.y)
		else:
			p.x += signi(d.x)
