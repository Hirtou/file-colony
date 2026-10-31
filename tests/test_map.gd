extends GutTest

func _rects(seed_value: int) -> Array:
	var out := []
	for it in MapLayout.build(FakeTree.generate(seed_value)):
		out.append(it.rect)
	return out

func test_same_seed_same_tree():
	assert_eq(str(FakeTree.generate(123).to_dict()), str(FakeTree.generate(123).to_dict()))

func test_same_seed_same_map():
	assert_eq(str(_rects(123)), str(_rects(123)))

func test_different_seed_differs():
	assert_ne(str(FakeTree.generate(1).to_dict()), str(FakeTree.generate(2).to_dict()))

func test_squares_do_not_overlap():
	for s in [1, 7, 42, 999, 2024]:
		var r := _rects(s)
		var bad := 0
		for i in r.size():
			for j in range(i + 1, r.size()):
				if r[i].intersects(r[j]):
					bad += 1
		assert_eq(bad, 0, "seed %d: наложений" % s)

func test_city_bigger_than_house_with_same_files():
	var f := FakeTree.Folder.new()
	f.file_count = 5
	var house := MapLayout.square_size(f)
	f.children.append(FakeTree.Folder.new())
	assert_gt(MapLayout.square_size(f), house)
