class_name LifeSoundSynth
extends RefCounted
## Synthesises the sounds of everyday life for the home and the office (LocationLife) and for the
## commute stops: footsteps, water, dishes, a kettle, muffled voices, the street behind the window,
## office phones and printers. Every function returns 16-bit-ready mono samples at RATE.

const RATE: int = 22050
## Sound id (file name in assets/audio) of every sound make() knows.
const SOUNDS: Array[String] = [
	"step", "water_loop", "sizzle_loop", "kettle", "dishes", "flush", "washer_loop", "typing", "rustle", "hum_loop",
	"office_chatter_loop", "cafe_chatter_loop", "neighbor_voice", "neighbor_voice2", "laugh", "drill", "dog_bark",
	"door_slam", "phone_ring", "printer", "coffee_machine", "birds", "siren", "tram_bell", "street_loop", "guitar",
	"page_flip", "clank", "fire_loop", "tv_loop", "shop_bell", "cash_register", "fuel_pump_loop", "steam",
]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Two-pole band-pass filter (RBJ biquad), used for voice formants and bells.
class Resonator:
	extends RefCounted

	var _b0: float
	var _b2: float
	var _a1: float
	var _a2: float
	var _x1: float = 0.0
	var _x2: float = 0.0
	var _y1: float = 0.0
	var _y2: float = 0.0

	func _init(frequency: float, q: float) -> void:
		tune(frequency, q)

	func tune(frequency: float, q: float) -> void:
		var w: float = TAU * frequency / LifeSoundSynth.RATE
		var alpha: float = sin(w) / (2.0 * q)
		var a0: float = 1.0 + alpha
		_b0 = alpha / a0
		_b2 = -alpha / a0
		_a1 = -2.0 * cos(w) / a0
		_a2 = (1.0 - alpha) / a0

	func process(x: float) -> float:
		var y: float = _b0 * x + _b2 * _x2 - _a1 * _y1 - _a2 * _y2
		_x2 = _x1
		_x1 = x
		_y2 = _y1
		_y1 = y
		return y


## Vowel formants (F1, F2) of a muffled voice behind a wall.
const VOWELS: Array[Vector2] = [
	Vector2(730, 1090), Vector2(530, 1840), Vector2(390, 1990), Vector2(570, 840), Vector2(440, 1020), Vector2(660, 1700),
]



## Samples of the sound `id` from SOUNDS.
func make(id: String) -> PackedFloat32Array:
	match id:
		"office_chatter_loop":
			return _chatter_loop(8.0, 4)
		"cafe_chatter_loop":
			return _chatter_loop(6.0, 6)
		"neighbor_voice":
			return _voice(2.6, 120.0)
		"neighbor_voice2":
			return _voice(2.0, 210.0)
	var method: String = "_" + id
	if not has_method(method):
		push_error("Unknown life sound " + id)
		return PackedFloat32Array()
	return call(method)

func _buffer(seconds: float) -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(int(seconds * RATE))
	return samples


func _noise() -> float:
	return rng.randf_range(-1.0, 1.0)


## Short linear fades at both ends so loops and one-shots never click.
func _declick(samples: PackedFloat32Array, fade_seconds: float = 0.005) -> PackedFloat32Array:
	var fade: int = mini(int(fade_seconds * RATE), samples.size() / 2)
	for i: int in fade:
		var k: float = float(i) / fade
		samples[i] *= k
		samples[samples.size() - 1 - i] *= k
	return samples


## Scales the samples so the loudest one reaches `peak`.
func _normalize(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var top: float = 0.0001
	for value: float in samples:
		top = maxf(top, absf(value))
	for i: int in samples.size():
		samples[i] *= peak / top
	return samples


## Adds a short decaying bell or glass partial set at `start` seconds.
func _add_ping(samples: PackedFloat32Array, start: float, frequency: float, decay: float, gain: float) -> void:
	var first: int = int(start * RATE)
	var ratios: Array[float] = [1.0, 2.76, 5.4]
	for i: int in range(first, mini(samples.size(), first + int(decay * 6.0 * RATE))):
		var t: float = float(i - first) / RATE
		var value: float = 0.0
		for k: int in ratios.size():
			value += sin(TAU * frequency * ratios[k] * t) * exp(-t * (1.0 + k * 1.5) / decay) / (k + 1)
		samples[i] += value * gain


## Muffled speech: a buzzing source through two formants that change every syllable.
func _add_voice(samples: PackedFloat32Array, start: float, seconds: float, pitch: float, gain: float) -> void:
	var f1: Resonator = Resonator.new(500.0, 6.0)
	var f2: Resonator = Resonator.new(1500.0, 8.0)
	var phase: float = 0.0
	var syllable_left: float = 0.0
	var syllable_length: float = 0.2
	var pause: bool = false
	var low: float = 0.0
	var first: int = int(start * RATE)
	var last: int = mini(samples.size(), first + int(seconds * RATE))
	for i: int in range(first, last):
		var t: float = float(i - first) / RATE
		syllable_left -= 1.0 / RATE
		if syllable_left <= 0.0:
			syllable_length = rng.randf_range(0.11, 0.24)
			syllable_left = syllable_length
			pause = rng.randf() < 0.12
			var vowel: Vector2 = VOWELS[rng.randi() % VOWELS.size()]
			f1.tune(vowel.x, 6.0)
			f2.tune(vowel.y, 8.0)
		var intonation: float = pitch * (1.0 + 0.12 * sin(TAU * 0.7 * t) + 0.05 * sin(TAU * 3.1 * t))
		phase = fmod(phase + intonation / RATE, 1.0)
		var source: float = (1.0 - 2.0 * phase) + _noise() * 0.15
		var k: float = 1.0 - syllable_left / syllable_length
		var envelope: float = 0.0 if pause else sin(PI * k) * (0.6 + 0.4 * sin(PI * k))
		var edge: float = minf(1.0, minf(t / 0.05, (seconds - t) / 0.08))
		var voiced: float = (f1.process(source) * 1.4 + f2.process(source) * 0.7) * envelope * edge
		low += (voiced - low) * 0.35
		samples[i] += low * gain


func _step() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(0.12)
	var low: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		low += (_noise() - low) * 0.18
		s[i] = (sin(TAU * 85.0 * t) * 0.8 + low * 1.6) * exp(-t / 0.025)
	return _declick(_normalize(s, 0.5), 0.002)


func _water_loop() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(3.0)
	var band: Resonator = Resonator.new(1400.0, 0.8)
	var gurgle: Resonator = Resonator.new(600.0, 12.0)
	var bubble: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		if rng.randf() < 30.0 / RATE:
			gurgle.tune(rng.randf_range(400.0, 1200.0), 14.0)
			bubble = rng.randf_range(0.4, 1.0)
		bubble *= 0.9993
		var flow: float = band.process(_noise()) * (0.8 + 0.2 * sin(TAU * 2.0 * t))
		s[i] = flow + gurgle.process(_noise()) * bubble * 0.5
	return _declick(_normalize(s, 0.55), 0.03)


func _sizzle_loop() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(3.0)
	var previous: float = 0.0
	var pop: float = 0.0
	for i: int in s.size():
		var n: float = _noise()
		var high: float = n - previous
		previous = n
		if rng.randf() < 25.0 / RATE:
			pop = rng.randf_range(0.5, 1.0)
		pop *= 0.985
		s[i] = high * (0.25 + 0.1 * sin(TAU * 0.67 * float(i) / RATE)) + _noise() * pop * 0.6
	return _declick(_normalize(s, 0.45), 0.03)


func _kettle() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(3.5)
	var rumble: Resonator = Resonator.new(300.0, 1.5)
	var phase: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		var boil: float = rumble.process(_noise()) * clampf(t / 1.5, 0.2, 1.0)
		var whistle_on: float = clampf((t - 1.8) / 0.4, 0.0, 1.0)
		phase += (1700.0 + 300.0 * clampf((t - 1.8) / 1.2, 0.0, 1.0)) / RATE
		var whistle: float = sin(TAU * phase) * whistle_on * (0.8 + 0.2 * _noise())
		s[i] = (boil * 1.2 + whistle * 0.25) * minf(1.0, (3.5 - t) / 0.3)
	return _declick(_normalize(s, 0.5), 0.02)


func _dishes() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(1.6)
	var time_at: float = 0.02
	while time_at < 1.2:
		_add_ping(s, time_at, rng.randf_range(1500.0, 3200.0), rng.randf_range(0.03, 0.09), rng.randf_range(0.3, 0.7))
		time_at += rng.randf_range(0.08, 0.3)
	return _declick(_normalize(s, 0.5), 0.002)


func _flush() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(2.6)
	var low: float = 0.0
	var gurgle: Resonator = Resonator.new(350.0, 6.0)
	for i: int in s.size():
		var t: float = float(i) / RATE
		low += (_noise() - low) * 0.12
		if rng.randf() < 20.0 / RATE:
			gurgle.tune(rng.randf_range(200.0, 600.0), 8.0)
		var swell: float = minf(1.0, t / 0.15) * exp(-maxf(0.0, t - 0.6) / 0.7)
		s[i] = (low * 1.5 + gurgle.process(_noise()) * 0.8) * swell
	return _declick(_normalize(s, 0.5), 0.01)


func _washer_loop() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(2.0)
	var swish: Resonator = Resonator.new(500.0, 1.0)
	for i: int in s.size():
		var t: float = float(i) / RATE
		var drum: float = pow(0.5 + 0.5 * sin(TAU * 1.0 * t), 3.0)
		s[i] = sin(TAU * 50.0 * t) * 0.25 + sin(TAU * 100.0 * t) * 0.1 + swish.process(_noise()) * drum * 0.9
	return _declick(_normalize(s, 0.4), 0.02)


func _typing() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(1.8)
	var time_at: float = 0.02
	while time_at < 1.7:
		var first: int = int(time_at * RATE)
		var previous: float = 0.0
		var gain: float = rng.randf_range(0.5, 1.0) * (1.6 if rng.randf() < 0.1 else 1.0)
		for i: int in range(first, mini(s.size(), first + int(0.02 * RATE))):
			var n: float = _noise()
			s[i] += (n - previous) * exp(-float(i - first) / RATE / 0.004) * gain
			previous = n
		time_at += rng.randf_range(0.06, 0.16) + (0.3 if rng.randf() < 0.08 else 0.0)
	return _declick(_normalize(s, 0.45), 0.002)


func _rustle() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(0.9)
	var band: Resonator = Resonator.new(2500.0, 0.7)
	for i: int in s.size():
		var t: float = float(i) / RATE
		var bumps: float = pow(absf(sin(TAU * 4.5 * t + sin(TAU * 1.3 * t))), 2.0)
		s[i] = band.process(_noise()) * bumps * sin(PI * t / 0.9)
	return _declick(_normalize(s, 0.4), 0.01)


func _hum_loop() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(2.0)
	var air: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		air += (_noise() - air) * 0.02
		s[i] = sin(TAU * 100.0 * t) * 0.3 + sin(TAU * 150.0 * t) * 0.12 + air * 0.6
	return _declick(_normalize(s, 0.3), 0.02)


## Several colleagues talking at once far away: the office or a café.
func _chatter_loop(seconds: float, voices: int) -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(seconds)
	for voice: int in voices:
		var at: float = rng.randf_range(0.0, 0.6)
		while at < seconds - 0.6:
			var length: float = minf(rng.randf_range(0.8, 2.4), seconds - at - 0.1)
			_add_voice(s, at, length, rng.randf_range(100.0, 230.0), rng.randf_range(0.5, 1.0))
			at += length + rng.randf_range(0.2, 1.0)
	var air: float = 0.0
	for i: int in s.size():
		air += (_noise() - air) * 0.03
		s[i] += air * 0.4
	return _declick(_normalize(s, 0.4), 0.04)


## One person talking behind a wall: the neighbours or a colleague on a call.
func _voice(seconds: float, pitch: float) -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(seconds)
	_add_voice(s, 0.05, seconds - 0.1, pitch, 1.0)
	return _declick(_normalize(s, 0.5), 0.02)


func _laugh() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(1.2)
	var f1: Resonator = Resonator.new(750.0, 5.0)
	var f2: Resonator = Resonator.new(1200.0, 6.0)
	var phase: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		var beat: float = fmod(t, 0.17) / 0.17
		var envelope: float = sin(PI * minf(1.0, beat / 0.7)) * exp(-t / 0.7) if beat < 0.7 else 0.0
		phase = fmod(phase + (260.0 - t * 60.0) / RATE, 1.0)
		var source: float = (1.0 - 2.0 * phase) + _noise() * 0.5
		s[i] = (f1.process(source) + f2.process(source) * 0.6) * envelope
	return _declick(_normalize(s, 0.45), 0.01)


func _drill() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(2.2)
	var phase: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		var on: float = 1.0 if (t > 0.1 and t < 0.9) or (t > 1.2 and t < 2.0) else 0.0
		var speed: float = 160.0 + 40.0 * sin(TAU * 0.8 * t)
		phase = fmod(phase + speed / RATE, 1.0)
		var motor: float = (1.0 - 2.0 * phase) * 0.6 + sin(TAU * phase * 3.0) * 0.3
		s[i] = tanh((motor + _noise() * 0.5) * 1.5) * on
	var low: float = 0.0
	for i: int in s.size():
		low += (s[i] - low) * 0.25
		s[i] = low
	return _declick(_normalize(s, 0.4), 0.01)


func _dog_bark() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(0.9)
	var formant: Resonator = Resonator.new(900.0, 3.0)
	var phase: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		var local: float = fmod(t, 0.42)
		var envelope: float = minf(1.0, local / 0.01) * exp(-local / 0.07) if t < 0.84 else 0.0
		phase = fmod(phase + (380.0 - local * 500.0) / RATE, 1.0)
		s[i] = formant.process((1.0 - 2.0 * phase) + _noise() * 0.8) * envelope
	return _declick(_normalize(s, 0.5), 0.005)


func _door_slam() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(0.8)
	var low: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		low += (_noise() - low) * 0.05
		s[i] = sin(TAU * 60.0 * t) * exp(-t / 0.08) + low * 2.0 * exp(-t / 0.2)
	return _declick(_normalize(s, 0.55), 0.002)


func _phone_ring() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(2.4)
	for i: int in s.size():
		var t: float = float(i) / RATE
		var on: bool = fmod(t, 1.2) < 0.8
		var tone: float = 1000.0 if fmod(t, 0.0625) < 0.03125 else 1300.0
		s[i] = (sin(TAU * tone * t) * 0.6 + sin(TAU * tone * 2.0 * t) * 0.15) if on else 0.0
	return _declick(_normalize(s, 0.3), 0.005)


func _printer() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(3.0)
	var band: Resonator = Resonator.new(900.0, 2.0)
	for i: int in s.size():
		var t: float = float(i) / RATE
		var motor: float = sin(TAU * 180.0 * t) * 0.2 + band.process(_noise()) * 0.6
		var clack: float = _noise() * exp(-fmod(t, 0.5) / 0.01) * 0.8
		s[i] = (motor + clack) * minf(1.0, minf(t / 0.1, (3.0 - t) / 0.2))
	return _declick(_normalize(s, 0.4), 0.01)


func _coffee_machine() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(3.2)
	var grind: Resonator = Resonator.new(1800.0, 1.2)
	var hiss: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		var value: float = 0.0
		if t < 1.2:
			value = grind.process(_noise()) * (0.7 + 0.3 * sin(TAU * 31.0 * t))
		elif t < 3.0:
			hiss += (_noise() - hiss) * 0.6
			value = sin(TAU * 50.0 * t) * 0.35 + hiss * 0.2 * (0.5 + 0.5 * sin(TAU * 3.0 * t))
		s[i] = value
	return _declick(_normalize(s, 0.45), 0.02)


func _birds() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(1.6)
	var at: float = 0.05
	while at < 1.4:
		var first: int = int(at * RATE)
		var length: float = rng.randf_range(0.04, 0.1)
		var base: float = rng.randf_range(2800.0, 4200.0)
		var sweep: float = rng.randf_range(-12000.0, 16000.0)
		var phase: float = 0.0
		for i: int in range(first, mini(s.size(), first + int(length * RATE))):
			var t: float = float(i - first) / RATE
			phase += (base + sweep * t) / RATE
			s[i] += sin(TAU * phase) * sin(PI * t / length)
		at += length + rng.randf_range(0.02, 0.25)
	return _declick(_normalize(s, 0.3), 0.002)


func _siren() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(4.0)
	var phase: float = 0.0
	var low: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		phase += (650.0 + 300.0 * (0.5 + 0.5 * sin(TAU * 0.5 * t))) / RATE
		low += (sin(TAU * phase) - low) * 0.3
		s[i] = low * sin(PI * t / 4.0)
	return _declick(_normalize(s, 0.3), 0.02)


func _tram_bell() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(1.0)
	_add_ping(s, 0.0, 1250.0, 0.12, 1.0)
	_add_ping(s, 0.22, 1250.0, 0.16, 1.0)
	return _declick(_normalize(s, 0.35), 0.002)


## Traffic heard through a closed window: low rumble with cars passing by.
func _street_loop() -> PackedFloat32Array:
	var seconds: float = 8.0
	var s: PackedFloat32Array = _buffer(seconds)
	var brown: float = 0.0
	var pass_low: float = 0.0
	var passes: Array[float] = [0.9, 3.1, 4.6, 6.7]
	for i: int in s.size():
		var t: float = float(i) / RATE
		brown = clampf(brown + _noise() * 0.02, -1.0, 1.0) * 0.998
		pass_low += (_noise() - pass_low) * 0.04
		var swell: float = 0.0
		for center: float in passes:
			swell += exp(-pow((t - center) / 0.6, 2.0))
		s[i] = brown * 0.7 + pass_low * swell * 1.2
	return _declick(_normalize(s, 0.4), 0.08)


func _guitar() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(2.0)
	for string_index: int in 4:
		var frequency: float = [196.0, 246.9, 293.7, 392.0][string_index]
		var period: int = int(RATE / frequency)
		var line: PackedFloat32Array = PackedFloat32Array()
		line.resize(period)
		for k: int in period:
			line[k] = _noise()
		var first: int = int(string_index * 0.03 * RATE)
		var index: int = 0
		for i: int in range(first, s.size()):
			var next: int = (index + 1) % period
			var value: float = (line[index] + line[next]) * 0.4985
			line[index] = value
			s[i] += value
			index = next
	return _declick(_normalize(s, 0.4), 0.003)


func _page_flip() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(0.35)
	var band: Resonator = Resonator.new(3500.0, 0.8)
	for i: int in s.size():
		var t: float = float(i) / RATE
		s[i] = band.process(_noise()) * sin(PI * t / 0.35) * (1.0 + 0.5 * sin(TAU * 25.0 * t))
	return _declick(_normalize(s, 0.35), 0.005)


func _clank() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(0.6)
	_add_ping(s, 0.0, 520.0, 0.08, 1.0)
	_add_ping(s, 0.01, 830.0, 0.05, 0.6)
	return _declick(_normalize(s, 0.45), 0.002)


func _fire_loop() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(3.0)
	var roar: float = 0.0
	for i: int in s.size():
		roar += (_noise() - roar) * 0.02
		var crack: float = _noise() * rng.randf_range(0.5, 1.0) if rng.randf() < 12.0 / RATE else 0.0
		s[i] = roar * 1.4 + crack
	var tail: float = 0.0
	for i: int in s.size():
		tail = s[i] if absf(s[i]) > 0.4 else tail * 0.97
		s[i] += tail * 0.6
	return _declick(_normalize(s, 0.4), 0.03)


## The neighbour's TV through the wall: a presenter and a jingle.
func _tv_loop() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(5.0)
	_add_voice(s, 0.2, 2.4, 150.0, 1.0)
	_add_voice(s, 3.0, 1.8, 210.0, 0.8)
	var notes: Array[float] = [523.0, 659.0, 784.0]
	for k: int in notes.size():
		_add_ping(s, 2.65 + k * 0.1, notes[k], 0.1, 0.25)
	return _declick(_normalize(s, 0.4), 0.03)


func _shop_bell() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(1.0)
	for k: int in 4:
		_add_ping(s, k * 0.05, 2100.0 + k * 80.0, 0.12, 0.6)
	return _declick(_normalize(s, 0.35), 0.002)


func _cash_register() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(0.9)
	for i: int in int(0.06 * RATE):
		s[i] += _noise() * exp(-float(i) / RATE / 0.01)
	_add_ping(s, 0.12, 2600.0, 0.15, 0.8)
	_add_ping(s, 0.12, 3300.0, 0.12, 0.5)
	return _declick(_normalize(s, 0.4), 0.002)


func _fuel_pump_loop() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(2.0)
	var flow: Resonator = Resonator.new(700.0, 1.2)
	for i: int in s.size():
		var t: float = float(i) / RATE
		s[i] = sin(TAU * 120.0 * t) * 0.25 + sin(TAU * 240.0 * t) * 0.08 + flow.process(_noise()) * 0.6
	return _declick(_normalize(s, 0.35), 0.02)


func _steam() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(1.4)
	var previous: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		var n: float = _noise()
		s[i] = (n - previous) * minf(1.0, t / 0.1) * minf(1.0, (1.4 - t) / 0.3) * (0.8 + 0.2 * sin(TAU * 7.0 * t))
		previous = n
	return _declick(_normalize(s, 0.3), 0.01)
