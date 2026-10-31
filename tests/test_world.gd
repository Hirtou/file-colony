extends GutTest
## Мир: фейковое дерево, деревни (улицы, дома дверью к дороге), жители, гуляющие по посёлку.

const SEEDS := [1, 7, 42, 999, 2024]
const ROADS := [WorldLayout.G.STREET, WorldLayout.G.PATH, WorldLayout.G.PLAZA]

var _worlds := {}

func before_all():
	I18n.use("ru")  # проверки ниже — по русским строкам, какой бы язык ни стоял в настройках

## Английский: имена папок и надписи на английском, тот же seed — то же дерево.
func test_english():
	var ru := FakeTree.generate(5)
	I18n.use("en")
	var en := FakeTree.generate(5)
	assert_eq(en.children.size(), ru.children.size(), "язык не меняет устройство мира")
	assert_true(FakeTree.FOLDER_NAMES_EN.has(en.children[0].name.split(" ")[0]), "папки по-английски: " + en.children[0].name)
	assert_eq(I18n.t("Копировать"), "Copy")
	assert_eq(I18n.t("Посадка на «%s»…") % "C:", "Landing on “C:”…")
	assert_eq(FakeTree.format_size(2048), "2.0 KB")
	assert_eq(TranslationServer.translate("Настройки"), "Settings", "кнопки переводятся сами")
	I18n.use("ru")
	assert_eq(String(TranslationServer.translate("Настройки")), "Настройки", "в русском — без перевода")

## Окрестности для разных seed: у берега океана, с рекой, с озёрами, сухо.
const ENVS := [{"coast": Vector2(1, 0), "river": true, "through": false}, {"lakes": 3, "river": false},
	{"coast": Vector2(-0.6, 0.8), "lakes": 2, "through": false},
	{"river": true, "through": true, "dry": 0.8}, {"river": true, "through": true, "coast": Vector2(0, 1)}]

## Карта первого города мира seed s.
func _city(s: int) -> Dictionary:
	var root := FakeTree.generate(s)
	return WorldLayout.build_city(root, root.children[0], s, ENVS[SEEDS.find(s) % ENVS.size()] if SEEDS.has(s) else {})

func _w(s: int) -> Dictionary:
	if not _worlds.has(s):
		_worlds[s] = _city(s)
	return _worlds[s]

func _all(f, out: Array) -> Array:
	for c in f.children:
		out.append(c)
		_all(c, out)
	return out

func test_same_seed_same_tree():
	var a := FakeTree.generate(FakeTree.seed_for("C:"), "C:")
	var b := FakeTree.generate(FakeTree.seed_for("C:"), "C:")
	assert_eq(str(a.to_dict()), str(b.to_dict()))

func test_same_seed_same_world():
	var a := _city(5)
	var b := _city(5)
	assert_true(a.ground == b.ground and str(a.walls) == str(b.walls) and str(a.work) == str(b.work), "одинаковый seed — одинаковый город")

## Вода (озёра, река, океан) не задевает город; у берега — океан; всё рабочее (мастерские, поля, рыбалка)
## достижимо от площади; к каждому месту работы ведёт дорога.
func test_city_water_and_work():
	for s in SEEDS:
		var w := _w(s)
		var n: int = w.n
		var town: Rect2i = w.town
		var water := 0
		var in_town := 0
		for i in n * n:
			if w.ground[i] == WorldLayout.G.WATER:
				water += 1
				@warning_ignore("integer_division")
				if town.has_point(Vector2i(i % n, i / n)):
					in_town += 1
		assert_gt(water, 0, "seed %d: вокруг города есть вода" % s)
		# вода не заходит в дома (река через город обходит их, улицы — мостами)
		for it in w.items:
			if it.kind == "city":
				continue
			for y in range(it.cell.y, it.cell.y + it.size.y):
				for x in range(it.cell.x, it.cell.x + it.size.x):
					assert_ne(w.ground[y * n + x], WorldLayout.G.WATER, "seed %d: вода в доме %s" % [s, it.folder.name])
		if ENVS[SEEDS.find(s)].get("through", false):
			assert_gt(in_town, 0, "seed %d: река течёт через город" % s)
		else:
			assert_eq(in_town, 0, "seed %d: вода в городе без реки через него" % s)
		if ENVS[SEEDS.find(s)].has("coast"):
			var dir: Vector2 = ENVS[SEEDS.find(s)].coast
			# самый дальний в сторону берега угол карты
			var edge := Vector2i(n - 1 if dir.x > 0 else 0, n - 1 if dir.y > 0 else 0)
			if absf(dir.y) < 0.01:
				edge.y = n / 2
			assert_eq(w.ground[edge.y * n + edge.x], WorldLayout.G.WATER, "seed %d: со стороны берега океан" % s)
		# от площади по проходимым клеткам — всё рабочее
		var top: Dictionary = w.items[0]
		var p0 := Vector2i(((top.plaza.position - w.origin) / WorldLayout.TILE).round())
		var pc := p0
		for k in 64:
			pc = p0 + Vector2i(k % 8, k / 8)
			if w.walk[pc.y * n + pc.x] == 1:
				break
		var seen := {pc: true}
		var q: Array[Vector2i] = [pc]
		while not q.is_empty():
			var c: Vector2i = q.pop_back()
			for d in WorldLayout.DIRS4:
				var nb: Vector2i = c + d
				if nb.x >= 0 and nb.y >= 0 and nb.x < n and nb.y < n and not seen.has(nb) and w.walk[nb.y * n + nb.x] == 1:
					seen[nb] = true
					q.append(nb)
		var kinds := {}
		for wk in w.work:
			for c in wk.cells:
				assert_true(seen.has(c), "seed %d: до места «%s» не дойти" % [s, wk.at])
			kinds[wk.go] = true
		for go in ["идёт в кузницу", "идёт на рынок", "идёт в лавку"]:
			assert_true(kinds.has(go), "seed %d: в городе есть «%s»" % [s, go])
		var fishing := false
		for go in kinds:
			fishing = fishing or String(go).begins_with("идёт на рыбалку")
		assert_true(fishing, "seed %d: есть где рыбачить" % s)

## Улицы районов не обрываются в траве: каждый выход главной улицы района ведёт на дорогу.
func test_district_roads_connected():
	for s in SEEDS:
		var w := _w(s)
		var n: int = w.n
		for it in w.items:
			if it.kind != "city" or it.depth < 2:
				continue
			for d in WorldLayout.DIRS4:
				var gate := WorldLayout._gate(it.cell, it.size, it.entr, d)
				assert_false(WorldLayout.dead_end(w.ground, n, gate, d), "seed %d: улица района %s обрывается (%s)" % [s, it.folder.name, d])

## Жители ходят на работу и рыбачить — и не заходят куда нельзя.
func test_residents_go_to_work():
	var w := _w(1)
	var homes := []
	for h in w.items:
		if h.kind == "house":
			homes.append(h)
	var t := Residents.new(homes, Rect2i(0, 0, w.n, w.n), w, 9)
	var texts := ""
	var ok := t.check()
	for k in 2400:  # 8 минут игры
		t.step(0.2)
		ok = ok and t.check()
		if k % 5 == 0:
			for r in t.files.size():
				texts += t.where(r) + "|"
	assert_true(ok, "жители стоят только где можно")
	assert_true(texts.contains("куёт") or texts.contains("горн") or texts.contains("строгает") or texts.contains("прилавк"), "работают в мастерских")
	assert_true(texts.contains("рыбалк") or texts.contains("рыбачит") or texts.contains("удочку"), "кто-то ходит рыбачить")

func test_tree_shape():
	for s in SEEDS:
		var root := FakeTree.generate(s)
		assert_between(root.children.size(), 4, 8, "seed %d: верхний уровень" % s)
		for f in _all(root, []):
			assert_eq(f.file_count, f.files.size())
			for fi in f.files:
				assert_true(fi.name != "" and fi.size > 0 and fi.type >= 0 and fi.type < FakeTree.TYPE_NAMES.size())

func test_every_city_has_subfolder():
	for s in SEEDS:
		for it in _w(s).items:
			if it.kind == "city":
				assert_gt(it.folder.children.size(), 0, "seed %d: город %s без подпапок" % [s, it.folder.name])

func test_no_overlap():
	for s in SEEDS:
		var w := _w(s)
		var items: Array = w.items
		var bad := 0
		var outside := 0
		var on_road := 0
		for i in items.size():
			var a: Dictionary = items[i]
			for j in range(i + 1, items.size()):
				var b: Dictionary = items[j]
				# соседи (один родитель) не пересекаются
				if a.parent == b.parent and Rect2i(a.cell, a.size).intersects(Rect2i(b.cell, b.size)):
					bad += 1
				# район и дом целиком внутри своей деревни
				if b.parent == a.folder and not Rect2i(a.cell, a.size).encloses(Rect2i(b.cell, b.size)):
					outside += 1
			# дом не стоит на улице
			if a.kind != "city":
				for y in range(a.cell.y, a.cell.y + a.size.y):
					for x in range(a.cell.x, a.cell.x + a.size.x):
						if w.ground[y * w.n + x] in ROADS:
							on_road += 1
		assert_eq(bad, 0, "seed %d: наложений" % s)
		assert_eq(outside, 0, "seed %d: вылезли из деревни" % s)
		assert_eq(on_road, 0, "seed %d: клеток дома на улице" % s)

## Каждая дверь в деревне выходит на улицу, и от площади до неё можно дойти.
func test_doors_on_streets_and_connected():
	for s in SEEDS:
		var w := _w(s)
		var n: int = w.n
		for top in w.items:
			if top.depth != 1 or top.kind != "city":
				continue
			var area := Rect2i(top.cell, top.size)
			# старт — любая проходимая клетка площади (в углах лавки, в центре колодец)
			var p0 := Vector2i(((top.plaza.position - w.origin) / WorldLayout.TILE).round())
			var pc := p0
			for k in 64:
				pc = p0 + Vector2i(k % 8, k / 8)
				if w.walk[pc.y * n + pc.x] == 1:
					break
			var seen := {pc: true}
			var q: Array[Vector2i] = [pc]
			while not q.is_empty():
				var c: Vector2i = q.pop_back()
				for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					var nb: Vector2i = c + d
					if area.has_point(nb) and not seen.has(nb) and w.walk[nb.y * n + nb.x] == 1:
						seen[nb] = true
						q.append(nb)
			for it in w.items:
				if it.kind == "city" or not it.path.has(top.folder):
					continue
				var out: Vector2i = it.door + it.door_side
				assert_eq(w.walk[out.y * n + out.x], 1, "seed %d: дверь дома %s не на улицу" % [s, it.folder.name])
				assert_true(seen.has(out), "seed %d: до дома %s не дойти от площади" % [s, it.folder.name])

## Жители гуляют только по улицам своего посёлка, своему полу и своей двери; дома клетки не делят.
func test_residents_walk_only_where_allowed():
	for s in [1, 42]:
		var w := _w(s)
		for top in w.items:
			if top.depth != 1 or top.kind == "hut":
				continue
			var homes := []
			for h in w.items:
				if h.kind == "house" and h.path.has(top.folder):
					homes.append(h)
			var area := Rect2i(top.cell, top.size)
			if top.kind != "city":
				area = area.grow(WorldMap.ROAM)
			var t := Residents.new(homes, area, w, s)
			var expect := 0
			for h in homes:
				expect += WorldMap.drawn_count(h.folder)
			assert_eq(t.files.size(), expect, "все жители влезли в свои дома")
			var ok := t.check()
			var went_out := false
			for k in 900:  # полторы минуты игры
				t.step(0.1)
				ok = ok and t.check()
				for r in t.files.size():
					went_out = went_out or t.state[r] != Residents.State.HOME
			assert_true(ok, "seed %d: житель посёлка %s зашёл, куда нельзя" % [s, top.folder.name])
			assert_true(went_out, "seed %d: в посёлке %s никто не гуляет" % [s, top.folder.name])

## Ночью все расходятся по домам (и никто не выходит), утром снова гуляют.
func test_night_everyone_goes_home():
	var w := _w(42)
	for top in w.items:
		if top.depth != 1 or top.kind != "city":
			continue
		var homes := []
		for h in w.items:
			if h.kind == "house" and h.path.has(top.folder):
				homes.append(h)
		var t := Residents.new(homes, Rect2i(top.cell, top.size), w, 3)
		t.night = true
		for k in 600:  # 5 минут игры
			t.step(0.5)
		var outside := 0
		for r in t.files.size():
			if t.state[r] != Residents.State.HOME:
				outside += 1
		assert_eq(outside, 0, "ночью на улице остались жители посёлка %s" % top.folder.name)
		assert_true(t.check())
		t.night = false
		var went_out := false
		for k in 600:
			t.step(0.5)
			for r in t.files.size():
				went_out = went_out or t.state[r] != Residents.State.HOME
		assert_true(went_out, "утром никто не вышел")
		return

func test_pawn_look_per_file():
	var rng := RandomNumberGenerator.new()
	var a := FakeTree._file(rng)
	assert_eq(str(Pawn.look(a)), str(Pawn.look(a)), "одна и та же одежда у одного файла")
	var styles := {}
	for i in 60:
		styles[Pawn.look(FakeTree._file(rng)).style] = true
	assert_gt(styles.size(), 5, "одежда разная у разных файлов")

func test_hats():
	var rng := RandomNumberGenerator.new()
	var hats := {}
	for i in 80:
		var lk := Pawn.look(FakeTree._file(rng))
		assert_between(int(lk.hat), 0, Pawn.HATS.size() - 1)
		hats[lk.hat] = true
	assert_true(hats.has(0), "есть жители без шапки")
	assert_gt(hats.size(), 5, "головные уборы разные")

## Посёлок первого города нового мира (свой, чтобы удаления не портили общие миры).
func _town(s: int) -> Residents:
	var w := _city(s)
	for top in w.items:
		if top.depth == 1 and top.kind == "city":
			var homes := []
			for h in w.items:
				if h.kind == "house" and h.path.has(top.folder):
					homes.append(h)
			return Residents.new(homes, Rect2i(top.cell, top.size), w, s)
	return null

func _indices_ok(t: Residents) -> bool:
	for r in t.files.size():
		if t.homes[t.home[r]].folder.files[t.file_index[r]] != t.files[r]:
			return false
		if t.rid[Vector2i(t.home[r], t.file_index[r])] != r:
			return false
	return true

func test_delete_by_killers():
	var t := _town(3)
	var r := 0
	var item: Dictionary = t.homes[t.home[r]]
	var file = t.files[r]
	var before: int = item.folder.files.size()
	var hunt := Hunt.new(t, item, r)
	assert_eq(t.state[r], Residents.State.DOOMED, "жертва замерла")
	var removed := false
	var caught := false
	for i in 30 * 60:  # до минуты по 1/30 с
		t.step(1.0 / 30.0)
		hunt.update(1.0 / 30.0)
		caught = caught or hunt.mode == Hunt.V.CAUGHT
		if not hunt.shot:
			assert_true(t.can_stand(t.files.find(file), t.cell[t.files.find(file)]), "жертва бегает только где можно")
		if hunt.shot and not removed:
			removed = true
			item.folder.files.erase(file)
			item.folder.file_count = item.folder.files.size()
			t.remove(t.files.find(file))
			assert_true(t.check() and _indices_ok(t), "после удаления жители и номера в порядке")
		if hunt.over:
			break
	assert_true(caught, "киллеры догнали жертву")
	assert_true(removed, "киллеры дошли и выстрелили")
	assert_true(hunt.over, "киллеры ушли")
	assert_eq(item.folder.files.size(), before - 1)
	assert_false(t.files.has(file))

func test_move_to_other_house():
	var t := _town(6)
	var r := 0
	var h1: int = t.home[r]
	var h2 := (h1 + 1) % t.homes.size()
	var src: Dictionary = t.homes[h1]
	var dst: Dictionary = t.homes[h2]
	var file = t.files[r]
	src.folder.files.erase(file)
	dst.folder.files.append(file)
	assert_true(t.relocate(r, h2), "в новом доме есть место")
	assert_true(_indices_ok(t), "номера файлов пересчитаны")
	var was_carrying := t.carry[t.files.find(file)] == 1
	for i in 600:  # 2 минуты
		t.step(0.2)
	var r2 := t.files.find(file)
	assert_eq(t.home[r2], h2, "живёт в новом доме")
	assert_eq(t.carry[r2], 0, "донёс вещи")
	assert_true(was_carrying or t.state[r2] == Residents.State.HOME, "нёс коробку")
	assert_true(t.check() and _indices_ok(t))

func test_music_loops():
	for track in ["space", "village"]:
		var s: AudioStreamWAV = load("res://assets/music/%s.wav" % track)
		assert_not_null(s, "трек %s есть" % track)
		assert_eq(s.loop_mode, AudioStreamWAV.LOOP_FORWARD, "трек %s играет по кругу" % track)
		assert_gt(s.get_length(), 20.0)

func test_residents_have_things_to_do():
	var t := _town(5)
	var seen := {}
	var chats := 0
	for i in 600:  # 2 минуты по 0.2 с
		t.step(0.2)
		for r in t.files.size():
			seen[t.where(r)] = true
			if t.chat[r] != null:
				chats += 1
	assert_true(t.check())
	assert_gt(chats, 0, "жители болтают друг с другом")
	var texts := " ".join(seen.keys())
	assert_true(texts.contains("колодц") or texts.contains("лавк") or texts.contains("в гости"), "ходят по делам: " + texts)
	t.night = true
	for i in 600:
		t.step(0.2)
	var sleepers := 0
	for r in t.files.size():
		if t.sleeping(r):
			sleepers += 1
	assert_gt(sleepers, 0, "ночью спят")

func test_family_tree():
	var root := FakeTree.generate(11)
	var ft := FamilyTree.new()
	ft._index(root)
	var checked := 0
	for f in _all(root, []):
		assert_eq(FamilyTree.kids(f).size(), f.children.size() + f.files.size(), "дети папки — подпапки и файлы")
		for x in f.files:
			assert_eq(ft.parent_of(x), f, "файл — ребёнок своей папки")
			assert_true(ft.role(x).begins_with("сын") or ft.role(x).begins_with("дочь"))
			checked += 1
		for c in f.children:
			assert_eq(ft.parent_of(c), f, "подпапка — тоже ребёнок")
	assert_eq(ft.role(root), "родоначальник")
	assert_gt(checked, 0)
	assert_eq(FamilyTree.female(root.children[0]), FamilyTree.female(root.children[0]), "пол не меняется")
	ft.free()

func test_paste_copy():
	var t := _town(4)
	var h := 0
	var item: Dictionary = t.homes[h]
	var src = item.folder.files[0]
	var f = src.copy_as(FakeTree.copy_name(item.folder, src.name))
	assert_ne(f.name, src.name, "в той же папке — «копия»")
	assert_true(f.name.contains(" - копия"))
	assert_eq(str(Pawn.look(f)), str(Pawn.look(src)), "копия выглядит как оригинал")
	item.folder.files.append(f)
	item.folder.file_count = item.folder.files.size()
	var r := t.add_file(h, f)
	if r >= 0:
		assert_true(_indices_ok(t) and t.check())
		for i in 300:
			t.step(0.1)
		assert_true(t.check(), "новый житель ходит где можно")
	assert_eq(FakeTree.copy_name(FakeTree.Folder.new(), "a.txt"), "a.txt", "в пустой папке имя то же")

func test_furniture_leaves_room():
	for s in SEEDS:
		var w := _w(s)
		var furn := 0
		for it in w.items:
			if it.kind == "city":
				continue
			var inner := Rect2i(it.cell + Vector2i.ONE, it.size - Vector2i(2, 2))
			var used := {}
			for c in it.furniture:
				assert_true(inner.has_point(c), "мебель внутри дома")
				used[c] = true
			furn += used.size()
			var entry: Vector2i = it.door - it.door_side
			assert_false(used.has(entry), "у двери не загорожено")
			# свободный пол связен от двери и вмещает всех жителей
			var seen := {entry: true}
			var q: Array[Vector2i] = [entry]
			var head := 0
			while head < q.size():
				var c := q[head]
				head += 1
				for d in WorldLayout.DIRS4:
					var nb := c + d
					if inner.has_point(nb) and not used.has(nb) and not seen.has(nb):
						seen[nb] = true
						q.append(nb)
			assert_eq(q.size(), inner.size.x * inner.size.y - used.size(), "весь свободный пол достижим")
			assert_true(q.size() >= WorldMap.drawn_count(it.folder), "жителям хватает места")
		assert_gt(furn, 0, "в домах есть мебель")
		assert_gt(w.furniture.size(), 0)

func test_max_40_residents():
	var f := FakeTree.Folder.new()
	var rng := RandomNumberGenerator.new()
	for i in 100:
		f.files.append(FakeTree._file(rng))
	f.file_count = f.files.size()
	assert_eq(WorldMap.drawn_count(f), 40)
	for s in SEEDS:
		for it in _w(s).items:
			assert_true(WorldMap.drawn_count(it.folder) <= 40)


## Дождь: для города и дня всегда одинаков, сила 0..1, идёт не каждый день, но бывает.
func test_rain():
	var C := load("res://scripts/continent.gd")
	var rainy := 0
	for d in range(1, 61):
		var top := 0.0
		for h in 24:
			var a: float = C.rain_of(1234, d, h + 0.5)
			assert_between(a, 0.0, 1.0)
			assert_eq(a, C.rain_of(1234, d, h + 0.5))
			top = maxf(top, a)
		if top > 0.0:
			rainy += 1
	assert_between(rainy, 8, 35, "дождь примерно в каждый третий день")