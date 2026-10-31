class_name WorldLayout
extends RefCounted
## Раскладка карты города по клеткам (клетка = TILE мировых единиц).
## Город — деревня без стен: площадь с колодцем, главные мощёные улицы с изломами, переулки-тропинки,
## дома и районы вдоль улиц дверью к дороге, мастерские (кузница, столярная, лавка, пекарня, рынок).
## Район (подпапка с подпапками) — такая же деревня поменьше. Вокруг — природа: луга, рощи, озёра, река,
## у берега океана — океан; из ворот дороги к краю карты, у дорог поля, у воды мостки для рыбалки.
## build_city() -> {n, ground, walk, walls, floors, decor, furniture, items, radius, origin, town, work, signs,
##   dry — клетки мостков на суше (под ними берег, не вода)}
##   ground: коды G (n*n); walk: 1 = по клетке можно ходить по улице (n*n)
##   walls: [[клетка, текстура, поворот A]]; floors: [[клетка, текстура]]; decor: [{c: центр в клетках, tex, s: размер}]
##   furniture: [{c: центр в клетках, tex, size: в клетках, rot}]
##   items (родитель раньше детей): {folder, kind, mat, depth, path, parent, cell, size, rect, pos, r,
##     door, door_side; у дома interior и furniture (занятые клетки); у города plaza (мир. Rect2)}

const TILE := 32.0
enum G { WATER, GRASS_1, GRASS_2, GRASS_3, GRASS_4, DIRT, SAND, PATH, STREET, PLAZA, YARD, PIER, FIELD }
const G_TEX := ["", "ground_grass_1", "ground_grass_2", "ground_grass_3", "ground_grass_4",
	"ground_dirt", "ground_sand", "ground_path", "ground_street", "ground_plaza", "ground_yard", "ground_pier", "ground_field"]
const MARGIN := 32     # клеток природы вокруг города
## Мастерские: двор у улицы, у задней стороны — рабочие места [текстура, чем там занят житель].
const WORK := {
	"smithy": {"name": "Кузница", "go": "идёт в кузницу", "size": Vector2i(6, 4), "ground": G.YARD,
		"stuff": [["decor_forge", "раздувает горн"], ["decor_anvil", "куёт подкову"], ["decor_barrel", "остужает железо в бочке"]]},
	"carpenter": {"name": "Столярная", "go": "идёт в столярную мастерскую", "size": Vector2i(6, 4), "ground": G.YARD,
		"stuff": [["decor_workbench", "строгает доски"], ["decor_logs", "колет дрова"], ["decor_workbench", "мастерит табурет"]]},
	"shop": {"name": "Лавка", "go": "идёт в лавку", "size": Vector2i(5, 4), "ground": G.YARD,
		"stuff": [["furn_shelf", "выбирает товар"], ["furn_table", "расплачивается у прилавка"], ["decor_barrel", "покупает квас"]]},
	"bakery": {"name": "Пекарня", "go": "идёт в пекарню", "size": Vector2i(5, 4), "ground": G.YARD,
		"stuff": [["furn_stove", "печёт хлеб"], ["furn_table", "месит тесто"], ["decor_crate", "таскает мешки с мукой"]]},
	"market": {"name": "Рынок", "go": "идёт на рынок", "size": Vector2i(9, 5), "ground": G.PLAZA,
		"stuff": [["decor_stall_1", "торгуется за овощи"], ["decor_stall_2", "приценивается к зельям"], ["decor_stall_1", "покупает яблоки"]]},
}

## По клетке можно ходить (улицы, площади, дворы, мостки, поля).
static func walkable(g: int) -> bool:
	return g == G.PATH or g == G.STREET or g == G.PLAZA or g == G.YARD or g == G.PIER or g == G.FIELD
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
static func make_node(f, seed_value: int, top := true) -> Dictionary:
	var k := kind(f)
	if k != "city":
		return {"folder": f, "kind": k, "mat": material(f, seed_value), "size": house_interior(f) + Vector2i(2, 2)}
	var kids := []
	for c in f.children:
		kids.append(make_node(c, seed_value, false))
	# мастерские: в городе все, в районе одна
	var types := ["market", "smithy", "carpenter", "shop", "bakery"]
	if not top:
		types = [types.slice(1)[absi(hash(f.name + str(seed_value))) % 4]]
	for t in types:
		kids.append({"folder": null, "kind": "work", "type": t, "size": WORK[t].size})
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

## Карта одного города (папки верхнего уровня) с окрестностями. env — что вокруг по месту на планете:
## {coast: Vector2 — в какой стороне океан (ZERO — нет), lakes: сколько озёр, river: есть ли река,
## dry: 0..1 — суше (меньше травы и леса)}. Чего нет в env — решает seed.
## Город в середине карты, вода его не задевает: озёра и река обходят город, дома и улицы целы.
static func build_city(root, city, seed_value: int, env := {}) -> Dictionary:
	var nd := make_node(city, seed_value)
	var sz: Vector2i = nd.size
	var n := maxi(sz.x, sz.y) + MARGIN * 2
	var cell := (Vector2i(n, n) - sz) / 2
	var town := Rect2i(cell, nd.size)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + absi(hash(String(city.name)))
	var dry: float = env.get("dry", 0.0)
	var ter := _terrain(n, town, rng, env)
	var ctx := {"n": n, "ground": _paint_ground(ter.land, n, seed_value, dry), "walls": [], "floors": [],
		"decor": [], "furniture": [], "block": [], "work": [], "signs": [], "ocean": ter.ocean, "dry": [],
		"origin": -Vector2(n, n) * TILE / 2}
	var items := []
	_flatten(nd, cell, 1, [root], items, ctx, Vector2i.DOWN)
	if nd.kind == "city":
		_exits(nd, cell, ctx)
	if ter.through:
		_river_through(items, town, ctx, rng, env.get("coast", Vector2.ZERO))
	_fields(town, ctx, rng)
	_fishing(town, ctx, rng)
	var decor: Array = ctx.decor + _decor(items, ctx, seed_value, dry)
	var walk := PackedByteArray()
	walk.resize(n * n)
	for i in n * n:
		walk[i] = 1 if walkable(ctx.ground[i]) else 0
	for c in ctx.block:
		walk[c.y * n + c.x] = 0
	return {"n": n, "ground": ctx.ground, "walk": walk, "walls": ctx.walls, "floors": ctx.floors, "decor": decor,
		"furniture": ctx.furniture, "items": items, "radius": n * TILE * 0.4, "origin": ctx.origin,
		"town": town, "work": ctx.work, "signs": ctx.signs, "dry": ctx.dry}

## Суша и вода n*n: {land: 1 — суша, ocean: 1 — океан}. Вода не ближе 3 клеток к городу.
static func _terrain(n: int, town: Rect2i, rng: RandomNumberGenerator, env: Dictionary) -> Dictionary:
	var land := PackedByteArray()
	land.resize(n * n)
	land.fill(1)
	var ocean := PackedByteArray()
	ocean.resize(n * n)
	var safe := town.grow(3)
	var center := Vector2(town.get_center())
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.05
	var coast: Vector2 = env.get("coast", Vector2.ZERO)
	if coast.length() > 0.01:
		# океан с одной стороны: берег неровный, но не ближе нескольких клеток к городу
		var dir := coast.normalized()
		var reach := -INF
		for c in [safe.position, safe.end, Vector2i(safe.position.x, safe.end.y), Vector2i(safe.end.x, safe.position.y)]:
			reach = maxf(reach, (Vector2(c) - center).dot(dir))
		var shore := reach + rng.randf_range(9.0, 14.0)
		for y in n:
			for x in n:
				if (Vector2(x, y) - center).dot(dir) > shore + noise.get_noise_2d(x, y) * 7.0:
					land[y * n + x] = 0
					ocean[y * n + x] = 1
	var lakes: int = env.get("lakes", rng.randi_range(1, 3))
	for k in lakes:
		for attempt in 60:
			var r := rng.randf_range(4.0, 9.0)
			var c := Vector2(rng.randf_range(r + 3, n - r - 3), rng.randf_range(r + 3, n - r - 3))
			if Rect2(safe).grow(r * 1.5 + 2).has_point(c) or ocean[int(c.y) * n + int(c.x)] == 1:
				continue
			_blob(land, n, c, r, noise, safe)
			break
	var river: bool = env.get("river", rng.randf() < 0.6)
	var through: bool = river and env.get("through", rng.randf() < 0.4)  # река через город — после домов
	if river and not through:
		_river(land, n, safe, rng, noise, coast)
	_clean_water(land, ocean, n, safe)
	return {"land": land, "ocean": ocean, "through": through}

## Берега без «крошек»: сглаживание большинством 3x3, мелкие лужи и островки — прочь. Возле города суша.
static func _clean_water(land: PackedByteArray, ocean: PackedByteArray, n: int, safe: Rect2i) -> void:
	var src := land.duplicate()
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			var k := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					k += src[(y + dy) * n + x + dx]
			land[y * n + x] = 1 if k >= 5 else 0
	for v in [0, 1]:
		for comp in _parts(land, n, v):
			if comp.size() < 8:
				for i in comp:
					land[i] = 1 - v
	for y in range(safe.position.y, safe.end.y):
		for x in range(safe.position.x, safe.end.x):
			land[y * n + x] = 1
	for i in n * n:
		if land[i] == 1:
			ocean[i] = 0

## Связные области клеток со значением v (4 соседа): массив массивов индексов.
static func _parts(m: PackedByteArray, n: int, v: int) -> Array:
	var seen := PackedByteArray()
	seen.resize(n * n)
	var out := []
	for start in n * n:
		if m[start] != v or seen[start] == 1:
			continue
		var comp := []
		var stack := [start]
		seen[start] = 1
		while not stack.is_empty():
			var i: int = stack.pop_back()
			comp.append(i)
			var x := i % n
			for nb in [i - 1 if x > 0 else -1, i + 1 if x < n - 1 else -1, i - n, i + n]:
				if nb >= 0 and nb < n * n and m[nb] == v and seen[nb] == 0:
					seen[nb] = 1
					stack.append(nb)
		out.append(comp)
	return out

## Озеро: круг с неровным берегом.
static func _blob(land: PackedByteArray, n: int, c: Vector2, r: float, noise: FastNoiseLite, safe: Rect2i) -> void:
	for y in range(maxi(0, int(c.y - r * 1.5)), mini(n, int(c.y + r * 1.5) + 1)):
		for x in range(maxi(0, int(c.x - r * 1.5)), mini(n, int(c.x + r * 1.5) + 1)):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d < r * (1.0 + noise.get_noise_2d(x * 1.6, y * 1.6) * 0.35) and not safe.has_point(Vector2i(x, y)):
				land[y * n + x] = 0

## Река от края карты к другому краю (или в океан), петляет и обходит город.
static func _river(land: PackedByteArray, n: int, safe: Rect2i, rng: RandomNumberGenerator, noise: FastNoiseLite, coast: Vector2) -> void:
	var center := Vector2(safe.get_center())
	var dir := coast.normalized() if coast.length() > 0.01 else Vector2.from_angle(rng.randf() * TAU)
	var side := dir.orthogonal()
	var lo := Vector2.ZERO
	var hi := Vector2(n - 1, n - 1)
	var a := (center - dir * n + side * rng.randf_range(-0.3, 0.3) * n).clamp(lo, hi)
	var b := (center + dir * n + side * rng.randf_range(-0.3, 0.3) * n).clamp(lo, hi)
	var pts := [a]
	var box := Rect2(safe.grow(7))
	if _crosses(a, b, box):
		# в обход города: через угол (или два угла) подальше от него
		var corners := [box.position, box.end, Vector2(box.position.x, box.end.y), Vector2(box.end.x, box.position.y)]
		var best := []
		var bl := INF
		for c in corners:
			if not _crosses(a, c, box.grow(-0.5)) and not _crosses(c, b, box.grow(-0.5)) and a.distance_to(c) + c.distance_to(b) < bl:
				bl = a.distance_to(c) + c.distance_to(b)
				best = [c]
		if best.is_empty():
			for c1 in corners:
				for c2 in corners:
					if c1 == c2 or _crosses(a, c1, box.grow(-0.5)) or _crosses(c1, c2, box.grow(-0.5)) or _crosses(c2, b, box.grow(-0.5)):
						continue
					var l: float = a.distance_to(c1) + c1.distance_to(c2) + c2.distance_to(b)
					if l < bl:
						bl = l
						best = [c1, c2]
		pts.append_array(best)
	pts.append(b)
	var width := rng.randf_range(1.6, 2.4)
	var phase := rng.randf() * TAU
	var t := 0.0
	for k in pts.size() - 1:
		var p0: Vector2 = pts[k]
		var p1: Vector2 = pts[k + 1]
		var steps := int(p0.distance_to(p1) * 2.0) + 1
		var nrm := (p1 - p0).normalized().orthogonal()
		for s in steps + 1:
			t += 0.5
			var wob := sin(t * 0.09 + phase) * 2.5 + noise.get_noise_1d(t * 2.0) * 2.0
			var p := p0.lerp(p1, float(s) / steps) + nrm * wob
			var w := width + noise.get_noise_1d(t * 3.0 + 50.0) * 0.5
			for y in range(int(p.y - w - 1), int(p.y + w + 2)):
				for x in range(int(p.x - w - 1), int(p.x + w + 2)):
					var c := Vector2i(x, y)
					if x >= 0 and y >= 0 and x < n and y < n and not safe.has_point(c) and Vector2(x + 0.5, y + 0.5).distance_to(p) <= w:
						land[y * n + x] = 0

## Река через город: путь от края до края (к океану, если он есть) по свободной земле между домами —
## самый дешёвый (Дейкстра). Дома, дворы, площади, поля, колодцы не трогает; улицы и переулки пересекает
## мостами (по мостам ходят, как по улице). В городе река уже, за городом шире. Деревья и фонари из воды убирает.
static func _river_through(items: Array, town: Rect2i, ctx: Dictionary, rng: RandomNumberGenerator, coast: Vector2) -> void:
	var n: int = ctx.n
	var hard := PackedByteArray()  # нельзя: дома и всё твёрдое
	hard.resize(n * n)
	var near := PackedByteArray()  # клетка у стены дома: можно, но дороже и не расширяем
	near.resize(n * n)
	for it in items:
		if it.kind == "city":
			continue
		var r := Rect2i(it.cell, it.size)
		for y in range(maxi(r.position.y - 1, 0), mini(r.end.y + 1, n)):
			for x in range(maxi(r.position.x - 1, 0), mini(r.end.x + 1, n)):
				if r.has_point(Vector2i(x, y)):
					hard[y * n + x] = 1
				else:
					near[y * n + x] = 1
	for c in ctx.block:
		hard[c.y * n + c.x] = 1
	for i in n * n:
		var g: int = ctx.ground[i]
		if g == G.PLAZA or g == G.YARD or g == G.FIELD or g == G.PIER:
			hard[i] = 1
	var dir := coast.normalized() if coast.length() > 0.01 else Vector2.from_angle(rng.randf() * TAU)
	var center := Vector2(town.get_center())
	var side := dir.orthogonal()
	var lim := Vector2(n - 1, n - 1)
	var a := Vector2i((center - dir * n + side * rng.randf_range(-0.12, 0.12) * n).clamp(Vector2.ZERO, lim))
	var b := Vector2i((center + dir * n + side * rng.randf_range(-0.12, 0.12) * n).clamp(Vector2.ZERO, lim))
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.08
	# Дейкстра с «вёдрами» (цены целые и небольшие)
	const SPAN := 25
	var dist := PackedInt32Array()
	dist.resize(n * n)
	dist.fill(1 << 30)
	var prev := PackedInt32Array()
	prev.resize(n * n)
	prev.fill(-1)
	var buckets := []
	for k in SPAN:
		buckets.append([])
	var start := a.y * n + a.x
	var goal := b.y * n + b.x
	dist[start] = 0
	buckets[0].append(start)
	var pending := 1
	var cur := 0
	while pending > 0:
		var bk: Array = buckets[cur % SPAN]
		if bk.is_empty():
			cur += 1
			continue
		var i: int = bk.pop_back()
		pending -= 1
		if dist[i] != cur:
			continue
		if i == goal:
			break
		var x := i % n
		@warning_ignore("integer_division")
		var y := i / n
		for k in 4:
			var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < 0 or ny < 0 or nx >= n or ny >= n:
				continue
			var j := ny * n + nx
			if hard[j] == 1:
				continue
			var g: int = ctx.ground[j]
			var step := 1 if g == G.WATER else 3 + int((noise.get_noise_2d(nx, ny) + 1.0) * 1.5)
			if walkable(g):
				step = 18  # через улицу — мост: можно, но поменьше
			if near[j] == 1:
				step += 6
			if cur + step < dist[j]:
				dist[j] = cur + step
				prev[j] = i
				buckets[(cur + step) % SPAN].append(j)
				pending += 1
	if prev[goal] < 0:
		return  # не прошла — значит, без реки
	var inside := town.grow(2)
	var i := goal
	while i >= 0:
		@warning_ignore("integer_division")
		var c := Vector2i(i % n, i / n)
		var rad := 1 if inside.has_point(c) else 2
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var q := c + Vector2i(dx, dy)
				if dx * dx + dy * dy > rad * rad or q.x < 0 or q.y < 0 or q.x >= n or q.y >= n:
					continue
				var j := q.y * n + q.x
				if hard[j] == 1 or (near[j] == 1 and q != c):
					continue
				var g: int = ctx.ground[j]
				if g == G.STREET or g == G.PATH:
					ctx.ground[j] = G.PIER  # мост
				elif g != G.PIER:
					ctx.ground[j] = G.WATER
		i = prev[i]
	var keep := []
	for d in ctx.decor:
		var dc := Vector2i(d.c.floor())
		if ctx.ground[dc.y * n + dc.x] != G.WATER:
			keep.append(d)
	ctx.decor = keep

## Отрезок задевает прямоугольник?
static func _crosses(a: Vector2, b: Vector2, r: Rect2) -> bool:
	for k in 41:
		if r.has_point(a.lerp(b, k / 40.0)):
			return true
	return false

## Главные улицы из ворот — дальше дорогами до края карты; узкая вода — мост, океан — дорога кончается.
static func _exits(nd: Dictionary, cell: Vector2i, ctx: Dictionary) -> void:
	var n: int = ctx.n
	var s: Vector2i = nd.size
	var inside := func(c: Vector2i) -> bool: return c.x >= 0 and c.y >= 0 and c.x < n and c.y < n
	for d in DIRS4:
		var side := Vector2i(absi(d.y), absi(d.x))
		var e: int = nd.entr[d]
		var gate := cell + Vector2i(e, 0)
		if d == Vector2i.DOWN:
			gate = cell + Vector2i(e, s.y - 1)
		elif d == Vector2i.LEFT:
			gate = cell + Vector2i(0, e)
		elif d == Vector2i.RIGHT:
			gate = cell + Vector2i(s.x - 1, e)
		var c: Vector2i = gate + d
		while inside.call(c) and inside.call(c + side):
			if ctx.ground[c.y * n + c.x] == G.WATER or ctx.ground[(c + side).y * n + (c + side).x] == G.WATER:
				var run := 0
				var p := c
				while inside.call(p) and inside.call(p + side) and (ctx.ground[p.y * n + p.x] == G.WATER or ctx.ground[(p + side).y * n + (p + side).x] == G.WATER):
					if ctx.ocean[p.y * n + p.x] == 1 or ctx.ocean[(p + side).y * n + (p + side).x] == 1:
						run = 99
						break
					run += 1
					p += d
				if run > 12 or not inside.call(p):
					break  # океан или слишком широко — дальше не идём
				for k in run:
					_set_g(ctx, c + d * k, G.PIER)  # мост
					_set_g(ctx, c + d * k + side, G.PIER)
				c += d * run
				continue
			_set_g(ctx, c, G.STREET)
			_set_g(ctx, c + side, G.STREET)
			c += d

## Природная клетка суши (не вода, не дорога, не поле...).
static func _wild(ctx: Dictionary, c: Vector2i) -> bool:
	var n: int = ctx.n
	if c.x < 0 or c.y < 0 or c.x >= n or c.y >= n:
		return false
	var g: int = ctx.ground[c.y * n + c.x]
	return g != G.WATER and not walkable(g)

## Поля у дорог за городом: грядки, стог сена в углу.
static func _fields(town: Rect2i, ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var n: int = ctx.n
	var roads: Array[Vector2i] = []
	for y in n:
		for x in n:
			if ctx.ground[y * n + x] == G.STREET and not town.grow(4).has_point(Vector2i(x, y)):
				roads.append(Vector2i(x, y))
	if roads.is_empty():
		return
	var made: Array[Rect2i] = []
	var texts := ["пропалывает грядки", "собирает урожай", "поливает капусту", "копает картошку"]
	for k in rng.randi_range(2, 4):
		for attempt in 80:
			var rc: Vector2i = roads[rng.randi_range(0, roads.size() - 1)]
			var dd: Vector2i = DIRS4[rng.randi_range(0, 3)]
			var sz := Vector2i(rng.randi_range(5, 8), rng.randi_range(4, 6))
			var r := _rect_from_door(rc + dd, dd, sz, rng.randi_range(1, (sz.x if dd.y != 0 else sz.y) - 2))
			var ok := not r.intersects(town.grow(3))
			for m in made:
				ok = ok and not m.grow(2).intersects(r)
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					ok = ok and _wild(ctx, Vector2i(x, y))
			if not ok:
				continue
			made.append(r)
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					_set_g(ctx, Vector2i(x, y), G.FIELD)
			var far: Vector2i = r.position if (r.position - rc).length_squared() > (r.end - Vector2i.ONE - rc).length_squared() else r.end - Vector2i.ONE
			ctx.decor.append({"c": Vector2(far) + Vector2(0.5, 0.5), "tex": "decor_haybale", "s": 1.0})
			ctx.block.append(far)
			for t in 3:
				var c := Vector2i(rng.randi_range(r.position.x, r.end.x - 1), rng.randi_range(r.position.y, r.end.y - 1))
				if c != far:
					ctx.work.append({"cells": [c], "go": "идёт в поле", "at": texts[rng.randi_range(0, texts.size() - 1)], "w": 0.6})
			break

## Мостки для рыбалки у озёр, реки и океана рядом с городом: тропинка от дороги, мостки в воду, лодка.
static func _fishing(town: Rect2i, ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var n: int = ctx.n
	var cands := []
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			var c := Vector2i(x, y)
			if not _wild(ctx, c) or town.grow(3).has_point(c):
				continue
			for w in DIRS4:
				var o: Vector2i = c + w
				if ctx.ground[o.y * n + o.x] == G.WATER:
					var d := Vector2(c).distance_to(Vector2(town.get_center())) + rng.randf() * 6.0
					cands.append([c, w, d])
					break
	cands.sort_custom(func(a, b): return a[2] < b[2])
	var piers: Array[Vector2i] = []
	for cd in cands:
		if piers.size() >= 3:
			break
		var c: Vector2i = cd[0]
		var w: Vector2i = cd[1]
		var near := false
		for pp in piers:
			near = near or Vector2(pp).distance_to(Vector2(c)) < 14.0
		if near:
			continue
		# мостки — до 3 досок в воду; кончаются в воде (на том берегу не упираются, это не мост)
		var run := 0
		var p := c + w
		while run < 8 and p.x > 0 and p.y > 0 and p.x < n - 1 and p.y < n - 1 and ctx.ground[p.y * n + p.x] == G.WATER:
			run += 1
			p += w
		var pier: Array[Vector2i] = []
		for k in mini(3, run - 2):
			pier.append(c + w * (k + 1))
		if pier.is_empty():
			continue
		var path := _path_to_road(c, ctx, town)
		if path.is_empty():
			continue
		for q in path:
			_set_g(ctx, q, G.PATH)
		_set_g(ctx, c, G.PIER)  # мостки начинаются на берегу
		ctx.dry.append(c)
		for q in pier:
			_set_g(ctx, q, G.PIER)
		piers.append(c)
		var end: Vector2i = pier[-1]
		var where := "к океану" if ctx.ocean[end.y * n + end.x] == 1 else "к воде"
		ctx.work.append({"cells": [end], "go": "идёт на рыбалку " + where, "at": "рыбачит с мостков", "w": 0.3})
		ctx.work.append({"cells": [c], "go": "идёт на рыбалку " + where, "at": "закидывает удочку с берега", "w": 0.3})
		# лодка у мостков
		var sd := Vector2i(w.y, w.x)
		for b in [end + sd, end - sd]:
			if ctx.ground[b.y * n + b.x] == G.WATER:
				ctx.decor.append({"c": Vector2(b) + Vector2(0.5, 0.5), "tex": "decor_boat", "s": 1.6})
				break

## Тропинка от клетки берега до ближайшей дороги (обход в ширину по природной суше вне города);
## клетки тропинки без начала и без дороги; [] — дороги рядом нет.
static func _path_to_road(start: Vector2i, ctx: Dictionary, town: Rect2i) -> Array[Vector2i]:
	var n: int = ctx.n
	var prev := {start: start}
	var q: Array[Vector2i] = [start]
	var head := 0
	while head < q.size() and head < 4000:
		var c := q[head]
		head += 1
		for d in DIRS4:
			var nb: Vector2i = c + d
			if prev.has(nb) or nb.x < 0 or nb.y < 0 or nb.x >= n or nb.y >= n:
				continue
			var g: int = ctx.ground[nb.y * n + nb.x]
			if walkable(g) and g != G.FIELD and g != G.PIER:
				var out: Array[Vector2i] = []
				var p := c
				while p != start:
					out.append(p)
					p = prev[p]
				return out
			if _wild(ctx, nb) and not town.grow(1).has_point(nb) and (nb - start).length_squared() < 50 * 50:
				prev[nb] = c
				q.append(nb)
	return []

## Мастерская: двор у улицы, у задней стороны рабочие места, перед каждым — где стоит работник.
static func _paint_work(nd: Dictionary, cell: Vector2i, d: Vector2i, ctx: Dictionary) -> void:
	var w: Dictionary = WORK[nd.type]
	var s: Vector2i = nd.size
	for y in s.y:
		for x in s.x:
			_set_g(ctx, cell + Vector2i(x, y), w.ground)
	var along := Vector2i(absi(d.y), absi(d.x))
	var length := s.x if along.x != 0 else s.y
	var b0 := cell  # первая клетка задней стороны
	if d == Vector2i.UP:
		b0.y = cell.y + s.y - 1
	elif d == Vector2i.LEFT:
		b0.x = cell.x + s.x - 1
	var k := 0
	for st in w.stuff:
		var big := String(st[0]).begins_with("decor_stall")
		var wide := 2 if big else 1
		var deep := 2 if big else 1
		if k + wide > length:
			break
		var cells: Array[Vector2i] = []
		var spots: Array[Vector2i] = []
		for a in wide:
			for b in deep:
				cells.append(b0 + along * (k + a) + d * b)
			spots.append(b0 + along * (k + a) + d * deep)
		var mid := Vector2.ZERO
		for c in cells:
			mid += Vector2(c) + Vector2(0.5, 0.5)
			ctx.block.append(c)
		mid /= cells.size()
		if String(st[0]).begins_with("furn_"):
			ctx.furniture.append({"c": mid, "tex": st[0], "size": Vector2.ONE, "rot": WALL_ROT[-d]})
		else:
			ctx.decor.append({"c": mid, "tex": st[0], "s": float(wide)})
		ctx.work.append({"cells": spots, "go": w.go, "at": st[1], "w": 1.0})
		k += wide + 1
	ctx.signs.append({"c": Vector2(cell) + Vector2(s) / 2.0, "text": w.name})

## Земля: песок у берега, дальше почва с пятнами травы — густота плавно меняется по шуму.
static func _paint_ground(land: PackedByteArray, n: int, seed_value: int, dry := 0.0) -> PackedByteArray:
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
				var v := grass.get_noise_2d(x, y) + (absi(hash(i * 7919 + seed_value)) % 100) / 100.0 * 0.08 - dry * 0.35
				g[i] = G.GRASS_1 if v > 0.22 else (G.GRASS_2 if v > 0.08 else (G.GRASS_3 if v > -0.06 \
					else (G.GRASS_4 if v > -0.2 else G.DIRT)))
	return g

## Деревья, кусты, камни, цветы на свободной земле вне деревень и домов.
static func _decor(items: Array, ctx: Dictionary, seed_value: int, dry := 0.0) -> Array:
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
			if blocked[i] == 1 or g == G.WATER or walkable(g):
				continue
			var h := absi(hash(i * 2654435 + seed_value)) % 1000
			var f := forest.get_noise_2d(x, y)
			var tex := ""
			if g != G.SAND and ((f > 0.25 + dry * 0.35 and h < 170) or h < 12) and not _tree_near(trees, Vector2i(x, y)):
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
	if nd.kind == "work":
		_paint_work(nd, cell, door_side, ctx)
		return
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
