class_name Sfx
## Звуки, собранные из чисел (без файлов): шум дождя (петля), выстрел мушкета, «щелчок» копирования,
## «звон» вставки. Каждый строится один раз и кэшируется.

const RATE := 22050
static var _cache := {}

static func get_stream(sound: String) -> AudioStreamWAV:
	if not _cache.has(sound):
		match sound:
			"rain":
				_cache[sound] = _rain()
			"shot":
				_cache[sound] = _shot()
			"copy":
				_cache[sound] = _blip(880.0, 0.07, 0.25)
			"paste":
				_cache[sound] = _chime()
			_:
				_cache[sound] = _blip(660.0, 0.05, 0.2)
	return _cache[sound]

## Отсчёты -1..1 -> 16-битный WAV.
static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

## Дождь: шум через два фильтра (шелест + низкий гул), редкие капли-щелчки; конец плавно
## перетекает в начало — петля без щелчка.
static func _rain() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var n := RATE * 3
	var s := PackedFloat32Array()
	s.resize(n)
	var lo := 0.0
	var hi := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		lo += (w - lo) * 0.05
		hi += (w - hi) * 0.45
		s[i] = hi * 0.22 + lo * 0.5
		if rng.randf() < 0.0009:
			s[i] += rng.randf_range(0.2, 0.45) * (1.0 if rng.randf() < 0.5 else -1.0)
	var fade := RATE / 4
	for i in fade:
		var k := float(i) / fade
		s[i] = s[i] * k + s[n - fade + i] * (1.0 - k)
	return _wav(s.slice(0, n - fade), true)

## Выстрел: резкий шумовой удар и затухающий низкий хлопок.
static func _shot() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := int(RATE * 0.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var lo := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		lo += (w - lo) * 0.12
		s[i] = (w * exp(-t * 60.0) * 0.9 + lo * exp(-t * 7.0) * 1.6 + sin(TAU * 70.0 * t) * exp(-t * 12.0) * 0.5)
	return _wav(s)

## Короткий мягкий «тык» на частоте f.
static func _blip(f: float, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(t * 400.0, 1.0) * exp(-t * 45.0)
		s[i] = sin(TAU * f * t) * env * vol
	return _wav(s)

## Вставка: две ноты вверх.
static func _chime() -> AudioStreamWAV:
	var n := int(RATE * 0.32)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var a := sin(TAU * 784.0 * t) * minf(t * 300.0, 1.0) * exp(-t * 18.0)
		var t2 := maxf(t - 0.09, 0.0)
		var b := sin(TAU * 1175.0 * t2) * minf(t2 * 300.0, 1.0) * exp(-t2 * 14.0) if t > 0.09 else 0.0
		s[i] = (a + b) * 0.2
	return _wav(s)
