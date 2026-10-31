class_name CitySites
extends RefCounted
## Где на планете стоят города (папки верхнего уровня диска) и что вокруг них.
## Точки — на суше развёртки планеты, подальше друг от друга. Место решает окрестности карты города:
## рядом океан — с той стороны на карте океан; на бурой суше — суше (меньше травы и леса).

## [{folder, dir: Vector3 — точка на шаре (координаты планеты), r: угловой радиус очертаний,
##   env: {coast: Vector2 (x — восток, y — юг; ZERO — океана рядом нет), lakes, river, dry}}]
static func make(root, seed_value: int, img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 99
	var land: Array[Vector2i] = []
	for y in range(h / 8, h * 7 / 8, 2):  # не у полюсов
		for x in range(0, w, 2):
			if not water(img.get_pixel(x, y)):
				land.append(Vector2i(x, y))
	var out := []
	if land.is_empty():
		return out
	var gap := 0.55  # угол между городами, рад; не влезают — ближе
	for f in root.children:
		var pick := Vector2i(-1, -1)
		for attempt in 600:
			if attempt % 150 == 149:
				gap *= 0.75
			var p: Vector2i = land[rng.randi_range(0, land.size() - 1)]
			var d := PlanetTexture.sphere_point(p.x, p.y, w, h)
			var ok := true
			for o in out:
				ok = ok and o.dir.angle_to(d) >= gap
			if ok:
				pick = p
				break
		if pick.x < 0:
			pick = land[rng.randi_range(0, land.size() - 1)]
		var size := sqrt(float(f.total_files()) / 120.0)
		out.append({"folder": f, "dir": PlanetTexture.sphere_point(pick.x, pick.y, w, h),
			"r": clampf(0.045 + 0.03 * size, 0.045, 0.1), "env": _env(img, pick, rng)})
	return out

## Вода на развёртке (как в шейдере планеты).
static func water(c: Color) -> bool:
	return c.b > c.r * 1.15 and c.b > c.g * 0.95

## Окрестности по пикселям вокруг p: где вода (океан), насколько сухо.
static func _env(img: Image, p: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var R := 14
	var sum := Vector2.ZERO
	var near := INF
	var brown := 0
	var green := 0
	for dy in range(-R, R + 1):
		for dx in range(-R, R + 1):
			var y := p.y + dy
			if y < 0 or y >= h or dx * dx + dy * dy > R * R:
				continue
			var c := img.get_pixel(posmod(p.x + dx, w), y)
			if water(c):
				var dist := Vector2(dx, dy).length()
				sum += Vector2(dx, dy) / maxf(dist, 1.0) / maxf(dist, 1.0)
				near = minf(near, dist)
			elif c.r > c.g * 0.9:
				brown += 1
			else:
				green += 1
	var coast := sum.normalized() if near < 11.0 and sum.length() > 0.001 else Vector2.ZERO
	var river := rng.randf() < (0.75 if coast != Vector2.ZERO else 0.55)
	return {"coast": coast, "lakes": rng.randi_range(1, 3), "river": river, "through": river and rng.randf() < 0.45,
		"dry": clampf(float(brown) / maxf(1.0, brown + green) * 1.2 - 0.1, 0.0, 1.0)}
