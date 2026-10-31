class_name WorldMap
extends Node2D
## Карта материка: земля, тени, полы, стены (TileMapLayer, стены с коллизией), декор
## и оверлей поверх: жители-человечки, гуляющие по своим посёлкам, подписи, выбор, затемнение.
## Выбран дом — видно, где каждый его житель и куда он идёт. Крыш нет — внутрь видно всегда.

const MAX_RESIDENTS := 40     # жителей на дом, остальные — «+N»
const TYPE_COLORS := [
	Color(0.35, 0.80, 0.35),  # картинка
	Color(0.30, 0.55, 0.95),  # документ
	Color(0.90, 0.30, 0.30),  # видео
	Color(0.65, 0.40, 0.90),  # музыка
	Color(0.95, 0.60, 0.20),  # архив
	Color(0.95, 0.85, 0.25),  # программа
	Color(0.60, 0.60, 0.62),  # другое
	Color(0.20, 0.70, 0.55),  # таблица
	Color(0.95, 0.45, 0.65),  # презентация
	Color(0.35, 0.85, 0.90),  # код
	Color(0.80, 0.55, 0.35),  # 3D-модель
	Color(0.85, 0.85, 0.95),  # шрифт
	Color(0.55, 0.35, 0.25),  # книга
	Color(0.55, 0.65, 0.20),  # сохранение
]
const SEA := Color(0.16, 0.25, 0.3)
const SELECT := Color(1.0, 0.9, 0.3)
const SHADOW := Color(0, 0, 0, 0.36)
const FLOORS := ["floor_wood", "floor_stone", "floor_dirt"]
const WALL_MATS := ["wood", "stone", "brick", "timber", "hut"]
const HIDE_PX := 4.0    # клетка меньше этого на экране — жителей не рисуем и не двигаем
const PAWN_PX := 12.0   # меньше этого — житель рисуется точкой
const SIMPLE_PX := 24.0 # меньше этого — человечек без деталей одежды
const CHUNK := 16       # клеток в куске неподвижного рисунка
const FAR_PX := 4.5     # клетка меньше этого на экране — показываем обзорную карту
const ROAM := 6         # отдельный дом: на сколько клеток вокруг гуляют жители

var world: Dictionary
var items: Array = []
var by_folder := {}          # Folder -> item
var land_rect := Rect2()     # где суша (мир. координаты) — дальше камера не уходит
var type_filter := -1        # показать на карте файлы одного типа (-1 — выкл)
var _hl := {}                # подсвеченные файлы (поиск или тип) -> true
var _hl_color := Color.WHITE
var _pins: Array = []        # [дом, сколько там подсвеченных файлов]

## Подсветить файлы на карте: метки над их домами, кольца вокруг жителей. Возвращает [файлов, домов].
func highlight(files: Array, color: Color) -> Vector2i:
	if files.is_empty():
		type_filter = -1
	_hl.clear()
	for f in files:
		_hl[f] = true
	_hl_color = color
	_update_pins()
	var n := 0
	for p in _pins:
		n += p[1]
	return Vector2i(n, _pins.size())

## Подсветить все файлы одного типа (-1 — снять).
func set_type_filter(t: int) -> Vector2i:
	type_filter = t
	var files := []
	if t >= 0:
		for it in items:
			for f in it.folder.files:
				if f.type == t:
					files.append(f)
	var n := highlight(files, TYPE_COLORS[t] if t >= 0 else Color.WHITE)
	type_filter = t
	return n

func _update_pins() -> void:
	if type_filter >= 0:
		# по типу: новые файлы (вставленные копии) тоже должны светиться
		for it in items:
			for f in it.folder.files:
				if f.type == type_filter:
					_hl[f] = true
	_pins.clear()
	if _hl.is_empty():
		return
	for it in items:
		if it.kind != "house":
			continue
		var k := 0
		for f in it.folder.files:
			if _hl.has(f):
				k += 1
		if k > 0:
			_pins.append([it, k])
var expanded := {}           # раскрытые города: Folder -> true
var focus = null             # самый глубокий раскрытый город (остальное темнее)
var selected := {}           # {type: "folder"/"file", item, index}
var _towns := {}             # Folder верхнего уровня -> Residents
var _visible_towns: Array = []  # посёлки в кадре (их двигаем и рисуем)
var _decor: Array = []       # [{pos, tex, size, tree, shadow}]
var _furniture: Array = []   # [{pos, tex, size, rot, rug}] мебель в домах
var _shadows: Node2D
var _decor_node: Node2D
var _rug_node: Node2D        # коврики — под остальной мебелью
var _furn_node: Node2D
var _overlay: Node2D
var _night_node: Node2D
var _glow_node: Node2D
var _labels: Node2D
var _font := ThemeDB.fallback_font
var night := 0.0             # 0 — день, 1 — глубокая ночь
var time_scale := 1.0        # ускорение времени для жителей
var dusk := 0.0              # 0..1 — тёплый закатный/рассветный оттенок
var _lamps := PackedVector2Array()
var _glow_tex: Texture2D
var _tile_layers: Array = []
var _step_acc := 0.0
var _overview: Sprite2D
var _far := false
var shadows_enabled := true:   # настройка «Тени»
	set(v):
		shadows_enabled = v
		if _shadows:
			_shadows.visible = v and not _far
		if _clouds:
			_clouds.visible = v
var _sel_t: Residents = null  # посёлок выбранного дома/жителя (для слоя подписей)
var _hunts: Array = []        # идущие удаления (Hunt)
var _hunt_node: Node2D
const WILDLIFE := preload("res://scripts/wildlife.gd")  # напрямую: не зависит от кэша классов редактора
var _wild: Node2D             # утки, круги от рыб, дым кузницы (Wildlife)
var _clouds: Sprite2D         # тени облаков (днём)

signal file_deleted(item: Dictionary)  # файл дома удалён (киллеры выстрелили)
signal files_changed(item: Dictionary) # в доме поменялись файлы (переселение)
var _marked: Array = []

## Сколько жителей рисуется в доме.
static func drawn_count(f) -> int:
	return mini(f.file_count, MAX_RESIDENTS)

## Радиус «попадания» жителя (для подсказки и выбора).
static func resident_radius(_file) -> float:
	return WorldLayout.TILE * 0.4

## Карта города city (папка верхнего уровня; null — первый) с окрестностями env (см. WorldLayout.build_city).
## prebuilt — уже построенная карта (из кэша Game), чтобы не строить заново.
func setup(root, seed_value: int, prebuilt := {}, city = null, env := {}) -> void:
	world = prebuilt if not prebuilt.is_empty() else WorldLayout.build_city(root, city if city != null else root.children[0], seed_value, env)
	items = world.items
	for it in items:
		by_folder[it.folder] = it
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_add_terrain()
	var walls := ["city_wall"]
	for m in WALL_MATS:
		for s in ["", "_corner", "_door"]:
			walls.append("wall_" + m + s)
	var t := Tiles.make_tileset(WorldLayout.G_TEX.slice(1) + FLOORS, walls)
	var ground := _layer(t.tileset, "Ground")
	_shadows = _container("Shadows")
	var floors := _layer(t.tileset, "Floors")
	var wall_layer := _layer(t.tileset, "Walls")
	_rug_node = _container("Rugs")
	_furn_node = _container("Furniture")
	_decor_node = _container("Decor")
	_wild = WILDLIFE.new()
	_wild.name = "Wildlife"
	add_child(_wild)
	_wild.setup(world, seed_value)
	_overlay = _canvas("Overlay", _draw_overlay)
	_hunt_node = _canvas("Hunts", _draw_hunts)
	_clouds = Sprite2D.new()
	_clouds.name = "CloudShadows"
	var cm := ShaderMaterial.new()
	cm.shader = preload("res://shaders/cloud_shadows.gdshader")
	cm.set_shader_parameter("n", float(world.n))
	_clouds.material = cm
	var white := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	_clouds.texture = ImageTexture.create_from_image(white)
	_clouds.scale = Vector2.ONE * WorldLayout.TILE * world.n  # вся карта, центр в (0, 0)
	add_child(_clouds)
	_night_node = _canvas("Night", _draw_night)
	_glow_node = _container("Glow")
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD  # свет складывается с цветом под ним
	_glow_node.material = add
	_glow_node.visible = false
	_labels = _canvas("Labels", _draw_labels)
	_glow_tex = _make_glow()
	var n: int = world.n
	for i in n * n:
		var code: int = world.ground[i]
		if not soft_ground(code):  # улицы, площади, дворы, мостки, поля — плитками поверх мягкой земли
			@warning_ignore("integer_division")  # номер клетки -> строка: деление нацело и нужно
			ground.set_cell(Vector2i(i % n, i / n), t.ids[WorldLayout.G_TEX[code]], Vector2i.ZERO)
	for fl in world.floors:
		floors.set_cell(fl[0], t.ids[fl[1]], Vector2i.ZERO)
	for w in world.walls:
		wall_layer.set_cell(w[0], t.ids[w[1]], Vector2i.ZERO, w[2])
	_tile_layers = [ground, floors, wall_layer]
	_build_overview()
	# суша целиком (для ограничения камеры)
	var lo := Vector2i(n, n)
	var hi := Vector2i(-1, -1)
	for i in n * n:
		if world.ground[i] != WorldLayout.G.WATER:
			@warning_ignore("integer_division")  # номер клетки -> строка: деление нацело и нужно
			var c := Vector2i(i % n, i / n)
			lo = lo.min(c)
			hi = hi.max(c)
	land_rect = Rect2(world.origin + Vector2(lo) * WorldLayout.TILE, Vector2(hi - lo + Vector2i.ONE) * WorldLayout.TILE)
	for d in world.decor:
		var tex := String(d.tex)
		var c: Vector2 = world.origin + d.c * WorldLayout.TILE
		var tree := tex.begins_with("decor_tree")
		if d.s < 2.0 or tree:
			# лёгкий сдвиг внутри клетки, чтобы не стояли ровным строем
			var h := absi(hash(d.c))
			@warning_ignore("integer_division")  # цифры хэша — сдвиг декора внутри клетки
			c += Vector2((h % 7 - 3), (h / 7 % 7 - 3)) * 1.5
		_decor.append({"pos": c, "tex": Tiles.tex(tex), "size": WorldLayout.TILE * d.s, "tree": tree, "shadow": d.s >= 2.0})
		if tex == "decor_lamp":
			_lamps.append(c)
	for d in world.get("furniture", []):
		_furniture.append({"pos": world.origin + d.c * WorldLayout.TILE, "tex": Tiles.tex(d.tex),
			"size": d.size * WorldLayout.TILE, "rot": d.rot, "rug": d.tex == "furn_rug"})
	_build_chunks()

## Неподвижное (тени, декор, ночной свет) рисуется ОДИН раз кусками 16x16 клеток;
## куски вне экрана движок отсекает сам — каждый кадр ничего не пересчитываем.
func _build_chunks() -> void:
	var size := WorldLayout.TILE * CHUNK
	var groups := {}
	var group := func(p: Vector2) -> Dictionary:
		var k := Vector2i((p / size).floor())
		if not groups.has(k):
			groups[k] = {"decor": [], "shadow_rects": [], "shadow_decor": [], "lamps": [], "houses": [], "rugs": [], "furn": []}
		return groups[k]
	for d in _furniture:
		group.call(d.pos)["rugs" if d.rug else "furn"].append(d)
	for d in _decor:
		var g: Dictionary = group.call(d.pos)
		g.decor.append(d)
		if d.shadow:
			g.shadow_decor.append(d)
	for it in items:
		if it.kind == "city":
			continue
		var g: Dictionary = group.call(it.pos)
		g.shadow_rects.append(it.rect)
		if it.kind == "house":
			g.houses.append(it.rect)
	for p in _lamps:
		group.call(p).lamps.append(p)
	for k in groups:
		var g: Dictionary = groups[k]
		_chunk(_shadows, _draw_shadow_chunk, g)
		if not g.rugs.is_empty():
			_chunk(_rug_node, _draw_furniture_chunk, g.rugs)
		if not g.furn.is_empty():
			_chunk(_furn_node, _draw_furniture_chunk, g.furn)
		_chunk(_decor_node, _draw_decor_chunk, g)
		_chunk(_glow_node, _draw_glow_chunk, g).use_parent_material = true

## Обзорная карта (клетка = пиксель) для дальнего плана: вместо сотен тысяч тайлов — одна картинка.
func _build_overview() -> void:
	var n: int = world.n
	var cols := {}
	for code in range(1, WorldLayout.G_TEX.size()):
		cols[code] = _avg_color(WorldLayout.G_TEX[code])
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)  # природная земля прозрачная — под ней шейдер земли
	for i in n * n:
		var code: int = world.ground[i]
		if not soft_ground(code):
			@warning_ignore("integer_division")  # номер клетки -> строка: деление нацело и нужно
			img.set_pixel(i % n, i / n, cols[code])
	var tree_col := Color(0.22, 0.34, 0.18)
	for d in world.decor:
		if String(d.tex).begins_with("decor_tree"):
			var c := Vector2i(d.c.floor())
			img.set_pixel(c.x, c.y, tree_col)
	for fl in world.floors:
		img.set_pixelv(fl[0], _avg_color(fl[1]))
	for w in world.walls:
		img.set_pixelv(w[0], _avg_color(w[1]).darkened(0.25))
	_overview = Sprite2D.new()
	_overview.name = "Overview"
	_overview.texture = ImageTexture.create_from_image(img)
	_overview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_overview.scale = Vector2.ONE * WorldLayout.TILE
	_overview.visible = false
	add_child(_overview)
	move_child(_overview, _tile_layers[0].get_index())  # под тенями и декором, над морем

## Картинка для мини-карты: клетка — пиксель, земля и вода тоже (обзор их не рисует — там шейдер).
func minimap_image() -> Image:
	var img := (_overview.texture as ImageTexture).get_image()
	img.convert(Image.FORMAT_RGBA8)
	var n: int = world.n
	var cols := []
	for t in TERRAIN_TEX:
		cols.append(_avg_color(t))
	var water := Color(0.2, 0.37, 0.46)
	var deep := Color(0.13, 0.26, 0.36)
	for y in n:
		for x in n:
			if img.get_pixel(x, y).a > 0.5:
				continue
			var code: int = world.ground[y * n + x]
			if code == WorldLayout.G.WATER:
				img.set_pixel(x, y, deep if _water_inside(x, y, n) else water)
			else:
				img.set_pixel(x, y, cols[terrain_layer(code)])
	return img

func _water_inside(x: int, y: int, n: int) -> bool:
	for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var c: Vector2i = Vector2i(x, y) + d
		if c.x < 0 or c.y < 0 or c.x >= n or c.y >= n or world.ground[c.y * n + c.x] != WorldLayout.G.WATER:
			return false
	return true

## Мировые координаты всей карты (для мини-карты).
func map_rect() -> Rect2:
	return Rect2(world.origin, Vector2(world.n, world.n) * WorldLayout.TILE)

var _avg_cache := {}

## Средний цвет текстуры (для обзорной карты).
func _avg_color(tex_name: String) -> Color:
	if not _avg_cache.has(tex_name):
		var img: Image = Tiles.tex(tex_name).get_image()
		var sum := Color(0, 0, 0, 0)
		var k := 0
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				sum += img.get_pixel(x, y)
				k += 1
		_avg_cache[tex_name] = Color(sum.r / k, sum.g / k, sum.b / k, 1.0)
	return _avg_cache[tex_name]

## Дальний план: обзорная карта вместо тайлов, теней и декора.
func _update_lod() -> void:
	var far := WorldLayout.TILE * _zoom() < FAR_PX
	if far == _far or _overview == null:
		return
	_far = far
	for l in _tile_layers:
		l.visible = not far
	_shadows.visible = not far and shadows_enabled
	_decor_node.visible = not far
	_wild.visible = not far
	_rug_node.visible = not far
	_furn_node.visible = not far
	_overview.visible = far

func _chunk(parent: Node2D, fn: Callable, g) -> Node2D:
	var c := Node2D.new()
	parent.add_child(c)
	c.draw.connect(fn.bind(c, g))
	c.queue_redraw()
	return c

func _container(node_name: String) -> Node2D:
	var c := Node2D.new()
	c.name = node_name
	add_child(c)
	return c

## Тени стен (вправо-вниз), деревьев, колодцев и лавок — на земле, под полом и стенами.
func _draw_shadow_chunk(c: Node2D, g: Dictionary) -> void:
	var off := Vector2(0.35, 0.45) * WorldLayout.TILE
	for r in g.shadow_rects:
		c.draw_rect(Rect2(r.position + off, r.size), SHADOW)
	for d in g.shadow_decor:
		Pawn._ellipse(c, d.pos + Vector2(0.25, 0.35) * d.size * 0.5, Vector2(0.42, 0.34) * d.size, SHADOW)

func _draw_decor_chunk(c: Node2D, g: Dictionary) -> void:
	for d in g.decor:
		var s: float = d.size
		c.draw_texture_rect(d.tex, Rect2(d.pos - Vector2(s, s) / 2, Vector2(s, s)), false)

## Мебель: каждый предмет повёрнут спиной к своей стене.
func _draw_furniture_chunk(c: Node2D, list: Array) -> void:
	for d in list:
		var s: Vector2 = d.size
		c.draw_set_transform(d.pos, d.rot, Vector2.ONE)
		c.draw_texture_rect(d.tex, Rect2(-s / 2, s), false)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)

## Ночной свет на полную яркость; силу задаёт modulate слоя (ночью 1, днём слой скрыт).
func _draw_glow_chunk(c: Node2D, g: Dictionary) -> void:
	var r := WorldLayout.TILE * 3.2
	for p in g.lamps:
		c.draw_texture_rect(_glow_tex, Rect2(p - Vector2(r, r), Vector2(r, r) * 2), false, Color(1.0, 0.72, 0.38) * 0.6)
	for h in g.houses:
		c.draw_texture_rect(_glow_tex, h.grow(WorldLayout.TILE * 1.5), false, Color(1.0, 0.68, 0.36) * 0.75)

## Мягкое круглое пятно света (белый центр -> чёрный край) для сложения.
static func _make_glow() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color.BLACK)
	g.add_point(0.45, Color(0.35, 0.35, 0.35))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 128
	t.height = 128
	return t

func _layer(ts: TileSet, layer_name: String) -> TileMapLayer:
	var l := TileMapLayer.new()
	l.name = layer_name
	l.tile_set = ts
	l.position = world.origin
	l.scale = Vector2.ONE * WorldLayout.TILE / Tiles.SIZE.x  # текстура 64 px -> клетка TILE
	add_child(l)
	return l

func _canvas(node_name: String, fn: Callable) -> Node2D:
	var c := Node2D.new()
	c.name = node_name
	add_child(c)
	c.draw.connect(fn)
	return c

## Природная земля и вода — одним шейдером (terrain.gdshader): слои плавно перетекают, без квадратов.
## Слой клетки: трава 1-4, земля, песок, тропа. Под улицами, дворами, площадями — тропа (земля вокруг
## натоптана), под полями — земля, под водой и мостками — песок; сами они — плитки сверху.
## Вода — отдельно: размытая маска, берег — её линия уровня (гладкий, без зубцов).
const TERRAIN_TEX := ["ground_grass_1", "ground_grass_2", "ground_grass_3", "ground_grass_4", "ground_dirt", "ground_sand", "ground_path"]
static var _grounds: Texture2DArray

## Слой шейдера земли для кода клетки.
static func terrain_layer(code: int) -> int:
	match code:
		WorldLayout.G.GRASS_1, WorldLayout.G.GRASS_2, WorldLayout.G.GRASS_3, WorldLayout.G.GRASS_4:
			return code - WorldLayout.G.GRASS_1
		WorldLayout.G.DIRT, WorldLayout.G.FIELD:
			return 4
		WorldLayout.G.SAND, WorldLayout.G.WATER, WorldLayout.G.PIER:
			return 5
	return 6  # тропа; под улицами, площадями, дворами

static func is_water(code: int) -> bool:
	return code == WorldLayout.G.WATER or code == WorldLayout.G.PIER

## Клетку рисует шейдер земли (плиткой сверху не кладём).
static func soft_ground(code: int) -> bool:
	return code <= WorldLayout.G.PATH

func _add_terrain() -> void:
	var n: int = world.n
	var splat := Image.create_empty(n, n, false, Image.FORMAT_R8)
	var water: Array[int] = []
	var dry := {}  # клетки мостков на берегу
	for c in world.get("dry", []):
		dry[c.y * n + c.x] = true
	var dist := PackedInt32Array()
	dist.resize(n * n)
	dist.fill(-1)
	for i in n * n:
		var code: int = world.ground[i]
		var l := terrain_layer(code)
		@warning_ignore("integer_division")  # номер клетки -> строка: деление нацело и нужно
		splat.set_pixel(i % n, i / n, Color8(l, 0, 0))
		if not is_water(code) or dry.has(i):
			dist[i] = 0
			water.append(i)
	# глубина воды: шагов до суши (обход в ширину), не дальше 6
	var head := 0
	while head < water.size():
		var i: int = water[head]
		head += 1
		if dist[i] >= 6:
			continue
		var x := i % n
		for nb in [i - 1 if x > 0 else -1, i + 1 if x < n - 1 else -1, i - n, i + n]:
			if nb >= 0 and nb < n * n and dist[nb] < 0:
				dist[nb] = dist[i] + 1
				water.append(nb)
	var depth := Image.create_empty(n, n, false, Image.FORMAT_R8)
	for i in n * n:
		@warning_ignore("integer_division")  # номер клетки -> строка: деление нацело и нужно
		depth.set_pixel(i % n, i / n, Color(minf(1.0, (dist[i] if dist[i] >= 0 else 6) / 6.0), 0, 0))
	# маска воды, размытая [1 2 1] по строкам и столбцам: у одиночных выступов берег скругляется
	var m := PackedFloat32Array()
	m.resize(n * n)
	for i in n * n:
		m[i] = 1.0 if is_water(world.ground[i]) else 0.0
	for i in dry:
		m[i] = 0.0  # начало мостков — на берегу
	var h := m.duplicate()
	for y in n:
		for x in n:
			h[y * n + x] = (m[y * n + maxi(x - 1, 0)] + 2.0 * m[y * n + x] + m[y * n + mini(x + 1, n - 1)]) / 4.0
	var mask := Image.create_empty(n, n, false, Image.FORMAT_R8)
	for y in n:
		for x in n:
			var v := (h[maxi(y - 1, 0) * n + x] + 2.0 * h[y * n + x] + h[mini(y + 1, n - 1) * n + x]) / 4.0
			mask.set_pixel(x, y, Color(v, 0, 0))
	if _grounds == null:
		var imgs: Array[Image] = []
		for t in TERRAIN_TEX:
			imgs.append(Tiles.tex(t).get_image())
		_grounds = Texture2DArray.new()
		_grounds.create_from_images(imgs)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("splat", ImageTexture.create_from_image(splat))
	mat.set_shader_parameter("depth", ImageTexture.create_from_image(depth))
	mat.set_shader_parameter("water_mask", ImageTexture.create_from_image(mask))
	mat.set_shader_parameter("grounds", _grounds)
	mat.set_shader_parameter("n", float(n))
	var s := Sprite2D.new()
	s.name = "Terrain"
	s.texture = ImageTexture.create_from_image(splat)
	s.material = mat
	s.scale = Vector2.ONE * WorldLayout.TILE
	add_child(s)  # центр карты в (0, 0)

func _process(delta: float) -> void:
	_update_lod()
	# издалека (жители — точки) двигаем их 12 раз в секунду, вблизи — каждый кадр
	_step_acc += delta
	var hz := 1000.0 if WorldLayout.TILE * _zoom() >= PAWN_PX else 12.0
	var stepped := _step_acc >= 1.0 / hz
	if stepped:
		for t in _visible_towns:
			t.step(_step_acc * time_scale)
		_step_acc = 0.0
	queue_redraw()
	if _wild and not _far:
		_wild.update(delta, view_rect())
	# тени, декор и ночной свет неподвижны — нарисованы один раз кусками;
	# жителей перерисовываем, только когда они сдвинулись
	if _overlay and (stepped or _visible_towns.is_empty()):
		_overlay.queue_redraw()
	# удаления идут в реальном времени (не зависят от скорости времени)
	for h in _hunts:
		h.update(delta)
		if h.shot and not h.applied:
			h.applied = true
			remove_file(h.item, h.file)
	_hunts = _hunts.filter(func(h): return not h.over)
	if _hunt_node:
		_hunt_node.queue_redraw()
	for c in [_night_node, _labels]:
		if c:
			c.queue_redraw()

## Время суток: ночью жители расходятся по домам.
func set_daylight(night_amount: float, dusk_amount: float) -> void:
	night = night_amount
	dusk = dusk_amount
	if _glow_node:
		_glow_node.visible = night > 0.01
		_glow_node.modulate = Color(night, night, night)
	for t in _towns.values():
		t.night = night > 0.5
	if _clouds:
		(_clouds.material as ShaderMaterial).set_shader_parameter("strength", 0.22 * (1.0 - night))  # ночью теней облаков нет

func _zoom() -> float:
	var cam := get_viewport().get_camera_2d()
	return cam.zoom.x if cam else 1.0

func view_rect() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	var size := get_viewport_rect().size / _zoom()
	var c := cam.get_screen_center_position() if cam else Vector2.ZERO
	return Rect2(c - size / 2, size)

## Можно кликнуть: верхний уровень или родитель раскрыт.
func _open(it: Dictionary) -> bool:
	return it.depth == 1 or expanded.has(it.parent)

func _dim(it: Dictionary) -> bool:
	return focus != null and not it.path.has(focus)

# --- посёлки и жители ---

## Посёлок, в котором живёт дом (или любой объект): деревня верхнего уровня или отдельный дом.
func town_of(it: Dictionary) -> Residents:
	var top: Dictionary = by_folder[it.path[1]]
	if not _towns.has(top.folder):
		var homes := []
		for h in items:
			if h.kind == "house" and h.path.has(top.folder):
				homes.append(h)
		var area := Rect2i(top.cell, top.size)
		if world.has("town"):
			area = Rect2i(0, 0, world.n, world.n)  # по делам ходят и за город: в поле, на рыбалку
		elif top.kind != "city":
			area = area.grow(ROAM)
		_towns[top.folder] = Residents.new(homes, area, world, absi(hash(top.folder.name)) + top.cell.x)
		_towns[top.folder].night = night > 0.5
	return _towns[top.folder]

## Номер жителя по дому и файлу (-1 — не нарисован).
func resident_id(item: Dictionary, index: int) -> int:
	var t := town_of(item)
	return t.rid.get(Vector2i(t.home_of[item.folder], index), -1)

func file_where(item: Dictionary, index: int) -> String:
	for h in _hunts:
		if h.file == item.folder.files[index] and h.fall < 0.0:
			return h.status  # убегает / прячется / попался
	var r := resident_id(item, index)
	return town_of(item).where(r) if r >= 0 else I18n.t("в доме (за «+N»)")

## Где сейчас житель файла; Vector2.INF — не нарисован (за «+N»).
func resident_pos(item: Dictionary, index: int) -> Vector2:
	var r := resident_id(item, index)
	return town_of(item).pos[r] if r >= 0 else Vector2.INF

## [на улице, всего нарисовано] у дома.
func house_out(item: Dictionary) -> Vector2i:
	var t := town_of(item)
	var h: int = t.home_of[item.folder]
	var out := Vector2i.ZERO
	for r in t.files.size():
		if t.home[r] == h:
			out.y += 1
			if t.state[r] != Residents.State.HOME:
				out.x += 1
	return out

## Удалить файл: за жителем идут киллеры. false — жителя не видно (за «+N») или за ним уже идут.
func hunt(item: Dictionary, index: int) -> bool:
	var r := resident_id(item, index)
	if r < 0 or is_hunted(item, index):
		return false
	_hunts.append(Hunt.new(town_of(item), item, r))
	return true

func is_hunted(item: Dictionary, index: int) -> bool:
	var r := resident_id(item, index)
	return r >= 0 and town_of(item).state[r] == Residents.State.DOOMED

## Убрать файл из дома (выдуманное дерево) и его жителя; ждавший за «+N» файл выходит на его место.
func remove_file(item: Dictionary, file) -> void:
	var t := town_of(item)
	item.folder.files.erase(file)
	item.folder.file_count = item.folder.files.size()
	var r := t.files.find(file)
	if r >= 0:
		t.remove(r)
	_fill_from_hidden(item)
	_update_pins()
	file_deleted.emit(item)

## В доме освободилось место — ждавший за «+N» файл выходит жителем.
func _fill_from_hidden(item: Dictionary) -> void:
	var t := town_of(item)
	var h: int = t.home_of[item.folder]
	for f in item.folder.files:
		if t.count(h) >= drawn_count(item.folder):
			break
		if not t.files.has(f):
			t.add_file(h, f, false)

## Переселить файл в другой дом (выдуманное дерево): житель выходит из старого дома и несёт
## коробку с вещами к новому. Дом в другом городе — уходит из своего и входит в дверь нового.
## Имя занято — как в проводнике: «Имя - копия». Возвращает новое имя; "" — нельзя (за ним киллеры).
func move_file(src: Dictionary, file, dst: Dictionary) -> String:
	if src == dst or is_hunted(src, src.folder.files.find(file)):
		return ""
	var t1 := town_of(src)
	var t2 := town_of(dst)
	src.folder.files.erase(file)
	src.folder.file_count = src.folder.files.size()
	file.name = FakeTree.copy_name(dst.folder, file.name)
	dst.folder.files.append(file)
	dst.folder.file_count = dst.folder.files.size()
	var r := t1.files.find(file)
	var h2: int = t2.home_of[dst.folder]
	if t1 == t2 and r >= 0:
		if not t1.relocate(r, h2):
			t1.remove(r)  # в новом доме нет места — будет за «+N»
	else:
		if r >= 0:
			t1.remove(r)
		t1._reindex()
		var r2 := t2.add_file(h2, file)
		if r2 >= 0:
			t2.carry[r2] = 1
	t2._reindex()
	_fill_from_hidden(src)
	_update_pins()
	files_changed.emit(src)
	files_changed.emit(dst)
	return file.name

## Вставить копию файла в дом: новый житель входит через дверь. Возвращает копию.
func paste(item: Dictionary, src):
	var f = src.copy_as(FakeTree.copy_name(item.folder, src.name))
	item.folder.files.append(f)
	item.folder.file_count = item.folder.files.size()
	var t := town_of(item)
	t.add_file(t.home_of[item.folder], f)
	_update_pins()
	return f

## Где сейчас жители дома (для камеры).
func member_positions(item: Dictionary) -> PackedVector2Array:
	var t := town_of(item)
	var h: int = t.home_of[item.folder]
	var pts := PackedVector2Array()
	for r in t.files.size():
		if t.home[r] == h:
			pts.append(t.pos[r])
	return pts

# --- рисование ---

func _draw() -> void:
	draw_rect(view_rect().grow(64), SEA)  # открытое море за краем карты

func _draw_overlay() -> void:
	if items.is_empty():
		return
	var z := _zoom()
	var view := view_rect()
	# посёлки в кадре (+ посёлок выбранного дома/жителя, чтобы он жил);
	# совсем издалека жителей не видно — их и не двигаем
	_visible_towns.clear()
	if WorldLayout.TILE * z >= HIDE_PX:
		for it in items:
			if it.depth == 1 and it.kind != "hut" and view.intersects(it.rect.grow(WorldLayout.TILE * ROAM)):
				_visible_towns.append(town_of(it))
	var sel_t: Residents = null
	if not selected.is_empty() and selected.item.kind == "house":
		sel_t = town_of(selected.item)
		if not _visible_towns.has(sel_t):
			_visible_towns.append(sel_t)
	_sel_t = sel_t
	_marked = _marked_residents(sel_t)
	for t in _visible_towns:
		_draw_town(t, z, view, sel_t, _marked)

## Киллеры, выстрелы, дым, падающий житель.
func _draw_hunts() -> void:
	var px := WorldLayout.TILE * _zoom()
	for h in _hunts:
		h.draw(_hunt_node, px >= PAWN_PX, px >= SIMPLE_PX)

## Ночь: тёмно-синяя дымка и тёплый закатный оттенок поверх мира (подписи рисуются выше).
func _draw_night() -> void:
	var v := view_rect().grow(64)
	if dusk > 0.01:
		_night_node.draw_rect(v, Color(1.0, 0.55, 0.25, 0.14 * dusk))
	if night > 0.01:
		_night_node.draw_rect(v, Color(0.02, 0.04, 0.12, 0.62 * night))

## Поверх ночи: нити к жителям выбранного дома, кольца, таблички «+N», подписи, рамка выбора.
func _draw_labels() -> void:
	if items.is_empty():
		return
	var z := _zoom()
	var view := view_rect()
	var sel_t := _sel_t
	var marked := _marked
	_draw_links(sel_t, marked, z)
	if sel_t != null:
		for r in marked:
			_labels.draw_arc(sel_t.pos[r], WorldLayout.TILE * 0.5, 0, TAU, 24, SELECT, 2 / z, true)
	# таблички «+N», подписи
	var labels := []
	for it in items:
		if not view.intersects(it.rect):
			continue
		if it.kind == "house":
			_draw_badge(it, z)
		if _open(it) and it.rect.size.x * z > (40.0 if it.kind == "city" else 60.0):
			labels.append(it)
	for it in labels:
		if it.kind == "city":
			# табличка — посреди площади (там нет домов); вблизи полупрозрачная, чтобы не закрывала жителей
			var near := clampf((WorldLayout.TILE * z - 14.0) / 16.0, 0.0, 1.0)
			_banner(it.plaza.get_center(), it.folder.name, 16 if it.depth == 1 else 13, z, _dim(it), 1.0 - 0.55 * near)
		else:
			_text(Vector2(it.pos.x, it.rect.end.y), it.folder.name, 12, z, 4.0, _dim(it))
	# вывески мастерских — вблизи
	if WorldLayout.TILE * z > 12.0:
		for s in world.get("signs", []):
			var p: Vector2 = world.origin + s.c * WorldLayout.TILE
			if view.has_point(p):
				_text(p - Vector2(0, WorldLayout.TILE * 0.6), I18n.t(s.text), 11, z, 0.0, false)
	_draw_pins(view, z)
	if focus != null:
		_focus_frame(by_folder[focus].rect, z)
	if not selected.is_empty() and not (selected.type == "folder" and selected.item.folder == focus):
		# дом выбранного жителя — бледной рамкой
		var a := 1.0 if selected.type == "folder" else 0.5
		_labels.draw_rect(frame(selected.item).grow(4 / z), Color(SELECT, a), false, 2 / z)

## Метки над домами, где есть файлы выбранного типа: кружок цвета типа с числом, «дышит».
func _draw_pins(view: Rect2, z: float) -> void:
	if _pins.is_empty():
		return
	var col: Color = _hl_color
	var t := Time.get_ticks_msec() / 1000.0
	for p in _pins:
		var it: Dictionary = p[0]
		if not view.grow(40 / z).intersects(it.rect):
			continue
		var at := Vector2(it.rect.get_center().x, it.rect.position.y)
		var bounce := sin(t * 3.0 + at.x * 0.01) * 3.0
		_labels.draw_set_transform(at, 0, Vector2.ONE / z)
		var c := Vector2(0, -22 + bounce)
		_labels.draw_colored_polygon(PackedVector2Array([c + Vector2(-7, 8), c + Vector2(7, 8), Vector2(0, bounce)]), col.darkened(0.3))
		_labels.draw_circle(c, 15.0, Color(0, 0, 0, 0.6))
		_labels.draw_circle(c, 13.0, col)
		_labels.draw_arc(c, 13.0 + 4.0 + 3.0 * (0.5 + 0.5 * sin(t * 4.0)), 0, TAU, 24, Color(col, 0.5), 2.0, true)
		var s := str(p[1])
		var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_labels.draw_string(_font, c + Vector2(-w / 2, 5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.05, 0.05, 0.05))
	_labels.draw_set_transform_matrix(Transform2D.IDENTITY)

## Открытый город: бегущий пунктир по контуру и «дышащие» уголки (вместо затемнения вокруг).
func _focus_frame(r: Rect2, z: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var px := 1.0 / z                        # один пиксель экрана в мире
	var rect := r.grow(6 * px)
	var col := Color(1.0, 0.86, 0.45)
	# пунктир бежит по часовой стрелке
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var dash := 14.0 * px
	var gap := 10.0 * px
	var shift := fmod(t * 40.0 * px, dash + gap)
	var walked := 0.0
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var side := a.distance_to(b)
		var dir := (b - a) / side
		# штрихи начинаются в точках периметра k * (dash + gap) + shift; первый — до начала стороны
		var s := fposmod(shift - walked, dash + gap) - (dash + gap)
		while s < side:
			var s0 := maxf(s, 0.0)
			var s1 := minf(s + dash, side)
			if s1 > s0:
				_labels.draw_line(a + dir * s0, a + dir * s1, Color(col, 0.85), 2.5 * px)
			s += dash + gap
		walked += side
	# уголки пульсируют наружу-внутрь
	var pulse := (sin(t * 3.0) * 0.5 + 0.5)
	var out := (4.0 + pulse * 6.0) * px
	var arm := 26.0 * px
	var w := 4.0 * px
	var glow := Color(col, 0.25 + 0.35 * pulse)
	for i in 4:
		var c: Vector2 = corners[i]
		var sx := -1.0 if i == 0 or i == 3 else 1.0
		var sy := -1.0 if i < 2 else 1.0
		var p := c + Vector2(sx, sy) * out
		var pts := PackedVector2Array([p + Vector2(-sx * arm, 0), p, p + Vector2(0, -sy * arm)])
		_labels.draw_polyline(pts, glow, w * 2.5)
		_labels.draw_polyline(pts, col, w)

## Жители, которых надо показать: все жители выбранного дома или выбранный житель.
func _marked_residents(t: Residents) -> Array:
	var out := []
	if t == null:
		return out
	var it: Dictionary = selected.item
	if selected.type == "file":
		var r := resident_id(it, selected.index)
		if r >= 0:
			out.append(r)
		return out
	var h: int = t.home_of[it.folder]
	for r in t.files.size():
		if t.home[r] == h:
			out.append(r)
	return out

## Нити от двери дома к его жителям и их маршруты (куда идут).
func _draw_links(t: Residents, marked: Array, z: float) -> void:
	if t == null:
		return
	var it: Dictionary = selected.item
	var door := t.center(it.door)
	for r in marked:
		var col: Color = t.looks[r].main
		_labels.draw_line(door, t.pos[r], Color(col, 0.75), 2.0 / z, true)
		var route: Array = t.route[r]
		if route.is_empty():
			continue
		var pts := PackedVector2Array([t.pos[r]])
		for c in route:
			pts.append(t.center(c))
		_labels.draw_polyline(pts, Color(1, 1, 1, 0.5), 1.5 / z, true)
		_labels.draw_circle(pts[pts.size() - 1], WorldLayout.TILE * 0.12, Color(1, 1, 1, 0.7))
	_labels.draw_circle(door, WorldLayout.TILE * 0.15, SELECT)

func _draw_town(t: Residents, z: float, view: Rect2, sel_t: Residents, marked: Array) -> void:
	var u := WorldLayout.TILE
	var only := sel_t == t and not marked.is_empty()
	if u * z < PAWN_PX:
		# издалека — цветные точки
		for r in t.files.size():
			if view.has_point(t.pos[r]):
				var hit: bool = _hl.has(t.files[r])
				var off: bool = not _hl.is_empty() and not hit
				_overlay.draw_circle(t.pos[r], u * (0.45 if hit else 0.3), Pawn._d(t.looks[r].main, off))
		return
	var order := []
	for r in t.files.size():
		if view.grow(u).has_point(t.pos[r]):
			order.append(r)
	order.sort_custom(func(a, b): return t.pos[a].y < t.pos[b].y)  # нижние перекрывают верхних
	@warning_ignore("integer_division")  # смена говорящего раз в 1.6 с — нацело
	var tick := Time.get_ticks_msec() / 1600  # кто сейчас говорит в паре
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 250.0)
	for r in order:
		var dim := only and not marked.has(r)
		if not _hl.is_empty():
			if _hl.has(t.files[r]):
				_overlay.draw_arc(t.pos[r], u * (0.48 + 0.06 * pulse), 0, TAU, 24, _hl_color, u * 0.06, true)
			else:
				dim = true  # остальные темнее
		Pawn.draw(_overlay, t.pos[r], u, t.looks[r], t.facing[r], t.walk[r], dim, u * z >= SIMPLE_PX, t.carry[r] == 1)
		if u * z < SIMPLE_PX:
			continue
		if t.chat[r] != null and (tick % 2 == 0) == (String(t.files[r].name) < String(t.chat[r].name)):
			_bubble(t.pos[r] + Vector2(u * 0.3, -u * 0.62), u, dim)
		elif t.sleeping(r):
			_zzz(t.pos[r] + Vector2(u * 0.22, -u * 0.5), u)

## Облачко разговора с многоточием.
func _bubble(p: Vector2, u: float, dim: bool) -> void:
	var a := 0.5 if dim else 0.95
	Pawn._ellipse(_overlay, p, Vector2(u * 0.3, u * 0.19), Color(0.15, 0.13, 0.12, a))
	Pawn._ellipse(_overlay, p, Vector2(u * 0.27, u * 0.16), Color(1, 1, 1, a))
	_overlay.draw_colored_polygon(PackedVector2Array([p + Vector2(-u * 0.14, u * 0.1), p + Vector2(-u * 0.02, u * 0.12),
		p + Vector2(-u * 0.22, u * 0.27)]), Color(1, 1, 1, a))
	for k in 3:
		_overlay.draw_circle(p + Vector2((k - 1) * u * 0.1, 0), u * 0.035, Color(0.2, 0.2, 0.22, a))

## «z z» над спящим, плывут вверх.
func _zzz(p: Vector2, u: float) -> void:
	var t := fmod(Time.get_ticks_msec() / 1000.0, 2.0) / 2.0
	for k in 2:
		var f := fmod(t + k * 0.5, 1.0)
		var s := u * (0.07 + 0.05 * f)
		var c := p + Vector2(f * u * 0.2, -f * u * 0.35)
		_overlay.draw_polyline(PackedVector2Array([c + Vector2(-s, -s), c + Vector2(s, -s), c + Vector2(-s, s), c + Vector2(s, s)]),
			Color(0.85, 0.9, 1.0, 1.0 - f), u * 0.035)

## «+N» на верхней стене дома, если жителей больше, чем рисуется.
func _draw_badge(it: Dictionary, z: float) -> void:
	var extra: int = it.folder.file_count - drawn_count(it.folder)
	if extra <= 0 or it.rect.size.x * z <= 90.0:
		return
	var u := WorldLayout.TILE
	var at := Vector2(it.rect.end.x - u * 1.5, it.rect.position.y + u / 2)
	var sz := Vector2(40, 18) / z
	_labels.draw_rect(Rect2(at - sz / 2, sz), Color(0.06, 0.07, 0.1, 0.85))
	_labels.draw_rect(Rect2(at - sz / 2, sz), Color(1, 1, 1, 0.5), false, 1.0 / z)
	_text(at - Vector2(0, 9 / z), "+%d" % extra, 12, z, -3.0, _dim(it))

## Всё вокруг раскрытого города темнее (4 прямоугольника вокруг него).
func _draw_dim(r: Rect2, view: Rect2) -> void:
	var v := view.grow(10).merge(r)
	var col := Color(0, 0, 0, 0.55)
	_overlay.draw_rect(Rect2(v.position, Vector2(v.size.x, r.position.y - v.position.y)), col)
	_overlay.draw_rect(Rect2(Vector2(v.position.x, r.end.y), Vector2(v.size.x, v.end.y - r.end.y)), col)
	_overlay.draw_rect(Rect2(Vector2(v.position.x, r.position.y), Vector2(r.position.x - v.position.x, r.size.y)), col)
	_overlay.draw_rect(Rect2(Vector2(r.end.x, r.position.y), Vector2(v.end.x - r.end.x, r.size.y)), col)

## Рамка объекта.
static func frame(it: Dictionary) -> Rect2:
	return it.rect

## Текст постоянного экранного размера под точкой pos.
func _text(pos: Vector2, text: String, size: int, z: float, gap_px: float, dim: bool) -> void:
	_labels.draw_set_transform(pos, 0, Vector2.ONE / z)
	var w := 400.0
	var p := Vector2(-w / 2, size + gap_px)
	_labels.draw_string_outline(_font, p, text, HORIZONTAL_ALIGNMENT_CENTER, w, size, 4, Color(0, 0, 0, 0.75))
	_labels.draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(1, 1, 1, 0.45 if dim else 1.0))
	_labels.draw_set_transform_matrix(Transform2D.IDENTITY)

## Табличка с названием деревни посреди площади (pos — её центр); a — общая прозрачность.
func _banner(pos: Vector2, text: String, size: int, z: float, dim: bool, a := 1.0) -> void:
	_labels.draw_set_transform(pos, 0, Vector2.ONE / z)
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var box := Rect2(Vector2(-tw / 2 - 10, -(size + 12) / 2.0), Vector2(tw + 20, size + 12))
	_labels.draw_rect(box, Color(0.18, 0.12, 0.07, (0.5 if dim else 0.9) * a))
	_labels.draw_rect(box, Color(0.85, 0.7, 0.45, (0.4 if dim else 0.9) * a), false, 1.5)
	_labels.draw_string(_font, Vector2(-tw / 2, box.position.y + 6 + size * 0.82), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Color(1, 0.95, 0.85, (0.45 if dim else 1.0) * maxf(a, 0.6)))
	_labels.draw_set_transform_matrix(Transform2D.IDENTITY)

## Что под точкой m: {} / {type: "file", item (дом), index (файл)} / {type: "folder", item}.
func pick(m: Vector2) -> Dictionary:
	var z := _zoom()
	for t in _visible_towns:
		for r in t.files.size():
			if m.distance_to(t.pos[r]) <= t.radius[r] + 2 / z:
				return {"type": "file", "item": t.homes[t.home[r]], "index": t.file_index[r]}
	for k in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[k]
		if _open(it) and it.rect.has_point(m):
			return {"type": "folder", "item": it}
	return {}
