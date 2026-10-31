class_name PlanetTexture
extends RefCounted
## Генерирует развёртку планеты (equirectangular): океан и один материк.

const OCEAN := Color(0.12, 0.35, 0.70)
const OCEAN_DEEP := Color(0.05, 0.18, 0.45)
const GREEN := Color(0.25, 0.55, 0.20)
const BROWN := Color(0.55, 0.42, 0.25)
const LAND_TARGET := 0.36  # доля суши до удаления мелких островов

static var _cache := {}  # готовые текстуры в памяти

## Seed из имени диска: один диск = одна и та же планета.
static func seed_from_name(disk_name: String) -> int:
	return disk_name.hash()

## Текстура создаётся один раз и берётся из кэша.
static func get_texture(seed_value: int, size := 512) -> ImageTexture:
	var key := "%d_%d" % [seed_value, size]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(make_image(seed_value, size))
	return _cache[key]

## Точка на сфере для пикселя развёртки (x — долгота, y — широта).
static func sphere_point(x: int, y: int, w: int, h: int) -> Vector3:
	var lon := (x + 0.5) / w * TAU - PI
	var lat := PI / 2 - (y + 0.5) / h * PI
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))

## Площадь пикселя строки y (у полюсов пиксели меньше).
static func row_weight(y: int, h: int) -> float:
	return sin((y + 0.5) / h * PI)

## Маска развёртки w × w/2: 1 = океан, 2 = суша.
## Шум берётся в 3D по точкам сферы, поэтому левый и правый край стыкуются.
static func make_mask(seed_value: int, w: int) -> PackedByteArray:
	var h := w / 2
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.0
	noise.fractal_octaves = 4
	# центр материка: случайная точка на сфере, не у самого полюса
	var c_lon := rng.randf() * TAU
	var c_lat := rng.randf_range(-0.6, 0.6)
	var land_c := Vector3(cos(c_lat) * cos(c_lon), sin(c_lat), cos(c_lat) * sin(c_lon))

	var scores := PackedFloat32Array()
	scores.resize(w * h)
	var lo := INF
	var hi := -INF
	for y in h:
		for x in w:
			var p := sphere_point(x, y, w, h)
			# ближе к центру материка = выше; шум делает берег неровным
			var s := p.dot(land_c) + noise.get_noise_3dv(p * 1.8) * 0.6
			scores[y * w + x] = s
			lo = minf(lo, s)
			hi = maxf(hi, s)

	# порог так, чтобы суши по площади было ~LAND_TARGET (через гистограмму)
	const BINS := 1024
	var hist := PackedFloat32Array()
	hist.resize(BINS)
	var total := 0.0
	for y in h:
		var wt := row_weight(y, h)
		for x in w:
			hist[mini(int((scores[y * w + x] - lo) / (hi - lo) * BINS), BINS - 1)] += wt
			total += wt
	var threshold := hi
	var acc := 0.0
	for b in range(BINS - 1, -1, -1):
		acc += hist[b]
		if acc >= total * LAND_TARGET:
			threshold = lo + (hi - lo) * b / BINS
			break

	var mask := PackedByteArray()
	mask.resize(w * h)
	for i in w * h:
		mask[i] = 2 if scores[i] >= threshold else 1
	return _keep_biggest_land(mask, w)

## Куски суши: [метки пикселей, площади кусков по id]. Край по x замкнут, полюс связан.
static func _label_land(mask: PackedByteArray, w: int) -> Array:
	var h := mask.size() / w
	var labels := PackedInt32Array()
	labels.resize(mask.size())  # 0 = ещё не помечен
	var areas := [0.0]
	for start in mask.size():
		if mask[start] != 2 or labels[start] != 0:
			continue
		var id := areas.size()
		var area := 0.0
		var stack := [start]
		labels[start] = id
		while not stack.is_empty():
			var i: int = stack.pop_back()
			var x := i % w
			var y := i / w
			area += row_weight(y, h)
			var nbs := [y * w + (x + w - 1) % w, y * w + (x + 1) % w]
			nbs.append(i - w if y > 0 else (x + w / 2) % w)
			nbs.append(i + w if y < h - 1 else y * w + (x + w / 2) % w)
			for n in nbs:
				if mask[n] == 2 and labels[n] == 0:
					labels[n] = id
					stack.append(n)
		areas.append(area)
	return [labels, areas]

## Оставляет только самый большой кусок суши (один материк).
static func _keep_biggest_land(mask: PackedByteArray, w: int) -> PackedByteArray:
	var res := _label_land(mask, w)
	var labels: PackedInt32Array = res[0]
	var areas: Array = res[1]
	var best_id := 0
	for id in areas.size():
		if areas[id] > areas[best_id]:
			best_id = id
	var out := mask.duplicate()
	for i in out.size():
		if out[i] == 2 and labels[i] != best_id:
			out[i] = 1
	return out

## Доля самого большого куска среди всей суши.
static func biggest_land_share(mask: PackedByteArray, w: int) -> float:
	var areas: Array = _label_land(mask, w)[1]
	var total := 0.0
	var best := 0.0
	for a in areas:
		total += a
		best = maxf(best, a)
	return best / total if total > 0 else 0.0

## Доля суши по площади сферы.
static func land_ratio(mask: PackedByteArray, w: int) -> float:
	var h := mask.size() / w
	var land := 0.0
	var total := 0.0
	for y in h:
		var wt := row_weight(y, h)
		for x in w:
			total += wt
			if mask[y * w + x] == 2:
				land += wt
	return land / total

## Цветная развёртка планеты w × w/2 по маске.
static func make_image(seed_value: int, w: int) -> Image:
	var h := w / 2
	var mask := make_mask(seed_value, w)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value + 1
	noise.frequency = 1.0
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var n := noise.get_noise_3dv(sphere_point(x, y, w, h) * 5.0) * 0.5 + 0.5
			var col := GREEN.lerp(BROWN, n) if mask[y * w + x] == 2 else OCEAN_DEEP.lerp(OCEAN, n)
			img.set_pixel(x, y, col)
	return img
