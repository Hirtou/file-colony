extends GutTest

const W := 128  # ширина развёртки в тестах (высота W/2)

func _mask(disk_name: String) -> PackedByteArray:
	return PlanetTexture.make_mask(PlanetTexture.seed_from_name(disk_name), W)

func _col_diff(img: Image, a: int, b: int) -> float:
	var s := 0.0
	for y in img.get_height():
		var ca := img.get_pixel(a, y)
		var cb := img.get_pixel(b, y)
		s += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return s / img.get_height()

func test_same_seed_same_picture():
	var a := PlanetTexture.make_image(123, 96).get_data()
	var b := PlanetTexture.make_image(123, 96).get_data()
	assert_true(a == b, "одинаковый seed = одинаковая картинка")

func test_disks_look_different():
	assert_false(_mask("C:") == _mask("D:"), "у C: и D: разные материки")

func test_no_seam():
	# стык правого и левого края не хуже обычного шага между соседними столбцами
	for n in ["C:", "D:"]:
		var img := PlanetTexture.make_image(PlanetTexture.seed_from_name(n), W)
		var avg := 0.0
		for x in W - 1:
			avg += _col_diff(img, x, x + 1)
		avg /= W - 1
		var seam := _col_diff(img, W - 1, 0)
		assert_lt(seam, avg * 2.0 + 0.01, "диск %s: шов %.3f, обычно %.3f" % [n, seam, avg])

func test_land_ratio_25_45():
	for n in ["C:", "D:", "E:", "X:"]:
		var r := PlanetTexture.land_ratio(_mask(n), W)
		assert_between(r, 0.25, 0.45, "диск %s: суша %.2f" % [n, r])

func test_one_continent():
	for n in ["C:", "D:", "E:", "X:"]:
		var s := PlanetTexture.biggest_land_share(_mask(n), W)
		assert_gte(s, 0.9, "диск %s: главный материк %.2f суши" % [n, s])

func test_planets_do_not_overlap():
	var l := SpaceScene.layout(SpaceScene.DISKS)
	for i in l.size():
		for j in range(i + 1, l.size()):
			var a: Dictionary = l[i]
			var b: Dictionary = l[j]
			assert_gt(a.pos.distance_to(b.pos), a.radius + b.radius)
