class_name Tiles
extends RefCounted
## Текстуры из assets/textures/ (имена — контракт с дизайнером, файлы можно заменить своими)
## и TileSet из них: у стен повороты (alternative tiles) и коллизия.

const DIR := "res://assets/textures/"
const SIZE := Vector2i(64, 64)  # пикселей в текстуре клетки (в мире клетка — WorldLayout.TILE)

static var _cache := {}

## Текстура по имени без .png; нет файла — розовая заглушка.
static func tex(name: String) -> Texture2D:
	if not _cache.has(name):
		var path := DIR + name + ".png"
		var img: Image = null
		# через импорт Godot: так текстуры есть и в собранной игре (.exe), где папки assets нет
		if ResourceLoader.exists(path):
			var t: Texture2D = load(path)
			img = t.get_image() if t else null
		if img == null:
			img = Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
			img.fill(Color.MAGENTA)
		elif img.get_size() != SIZE and not name.begins_with("decor") and not name.begins_with("ui_"):
			img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_BILINEAR)  # чужой ассет другого размера
		img.generate_mipmaps()  # чтобы издалека не рябило
		_cache[name] = ImageTexture.create_from_image(img)
	return _cache[name]

static func exists(name: String) -> bool:
	return ResourceLoader.exists(DIR + name + ".png")

## {tileset, ids: имя -> source id}. Альтернативы стен по порядку WorldLayout.A.
static func make_tileset(names: Array, wall_names: Array) -> Dictionary:
	var ts := TileSet.new()
	ts.tile_size = SIZE
	ts.add_physics_layer()
	var ids := {}
	for name in names + wall_names:
		var src := TileSetAtlasSource.new()
		src.texture = tex(name)
		src.texture_region_size = SIZE
		src.create_tile(Vector2i.ZERO)
		ids[name] = ts.add_source(src)
		if not name in wall_names:
			continue
		# FLIP_H, FLIP_V, FLIP_HV, T, T_FLIP_H
		for t in [[true, false, false], [false, true, false], [true, true, false], [false, false, true], [true, false, true]]:
			var td := src.get_tile_data(Vector2i.ZERO, src.create_alternative_tile(Vector2i.ZERO))
			td.flip_h = t[0]
			td.flip_v = t[1]
			td.transpose = t[2]
		for k in src.get_alternative_tiles_count(Vector2i.ZERO):
			_add_collision(src.get_tile_data(Vector2i.ZERO, src.get_alternative_tile_id(Vector2i.ZERO, k)), name.ends_with("_door"))
	return {"tileset": ts, "ids": ids}

## Стена — сплошной квадрат; дверной проём — только косяки по краям.
static func _add_collision(td: TileData, door: bool) -> void:
	var h := SIZE.x / 2.0
	var shapes := [[-h, h]] if not door else [[-h, -h + 12], [h - 12, h]]
	for i in shapes.size():
		var a: float = shapes[i][0]
		var b: float = shapes[i][1]
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, i, PackedVector2Array([Vector2(a, -h), Vector2(b, -h), Vector2(b, h), Vector2(a, h)]))
