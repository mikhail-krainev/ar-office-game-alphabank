extends SceneTree
## Synthesises intro sound effects and ambience loops into assets/audio/*.wav (16-bit mono).
## Run: godot --headless --path client --script res://tools/generate_audio.gd

const RATE: int = 22050
const DIR: String = "res://assets/audio/"

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 850
	_save("alarm", _alarm())
	_save("rain_loop", _rain())
	_save("engine_loop", _engine())
	_save("engine_start", _engine_start())
	_save("city_loop", _city())
	_save("horn", _horn(392.0, 494.0, 0.45))
	_save("horn2", _horn(523.0, 659.0, 0.28))
	_save("car_door", _car_door())
	_save("brush_loop", _brush())
	_save("thunder", _thunder())
	_save("whoosh", _whoosh())
	_save("clink", _clink())
	_save("chime", _chime())
	_save("door_slide", _door_slide())
	_save_life_sounds()
	quit()


## Home, office and commute-stop sounds (LocationLife, the commute errands). A separate seed keeps
## the sounds above unchanged when this list grows.
func _save_life_sounds() -> void:
	var synth: LifeSoundSynth = LifeSoundSynth.new()
	synth.rng.seed = 4242
	for sound: String in LifeSoundSynth.SOUNDS:
		_save(sound, synth.make(sound))


func _save(sound: String, samples: PackedFloat32Array) -> void:
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	var path: String = ProjectSettings.globalize_path(DIR + sound + ".wav")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error: Error = wav.save_to_wav(path)
	if error != OK:
		push_error("Failed to save %s: %s" % [sound, error_string(error)])
	else:
		print("Saved ", DIR + sound + ".wav")


func _buffer(seconds: float) -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(int(seconds * RATE))
	return samples


func _noise() -> float:
	return rng.randf_range(-1.0, 1.0)


func _square(phase: float) -> float:
	return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0


## Short linear fades at both ends so loops and one-shots never click.
func _declick(samples: PackedFloat32Array, fade_seconds: float = 0.005) -> PackedFloat32Array:
	var fade: int = mini(int(fade_seconds * RATE), samples.size() / 2)
	for i: int in fade:
		var k: float = float(i) / fade
		samples[i] *= k
		samples[samples.size() - 1 - i] *= k
	return samples


func _alarm() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(1.2)
	for i: int in s.size():
		var t: float = float(i) / RATE
		var on: bool = fmod(t, 0.3) < 0.12 and t < 0.9
		s[i] = _square(t * 1760.0) * 0.28 if on else 0.0
	return _declick(s)


func _rain() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(4.0)
	var bright: float = 0.0
	var dark: float = 0.0
	var drop: float = 0.0
	for i: int in s.size():
		var n: float = _noise()
		bright += (n - bright) * 0.35
		dark += (n - dark) * 0.03
		if rng.randf() < 45.0 / RATE:
			drop = rng.randf_range(0.25, 0.6)
		drop *= 0.992
		s[i] = bright * 0.28 + dark * 0.9 + _noise() * drop * 0.4
	return _declick(s, 0.02)


func _engine() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(2.0)
	var rumble: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		var value: float = 0.0
		for k: int in range(1, 9):
			value += sin(TAU * 55.0 * k * t + k * 0.7) / k
		value += 0.5 * sin(TAU * 27.5 * t)
		rumble += (_noise() - rumble) * 0.08
		s[i] = tanh(value * 0.45 + rumble * 0.5) * 0.45
	return s


func _engine_start() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(1.4)
	var phase: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		var value: float = 0.0
		if t < 0.5:
			value = _square(t * 18.0) * 0.15 + _noise() * 0.08
		else:
			var freq: float = lerpf(30.0, 62.0, clampf((t - 0.5) / 0.3, 0.0, 1.0)) - maxf(0.0, t - 0.8) * 12.0
			phase += freq / RATE
			value = tanh((sin(TAU * phase) + 0.5 * sin(TAU * phase * 2.0) + 0.3 * _noise()) * 0.9) * 0.5
		s[i] = value
	return _declick(s, 0.02)


func _city() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(6.0)
	var brown: float = 0.0
	var hiss: float = 0.0
	var chirps: Array[float] = [0.7, 2.4, 2.55, 4.1, 5.3]
	for i: int in s.size():
		var t: float = float(i) / RATE
		brown = clampf(brown + _noise() * 0.02, -1.0, 1.0) * 0.998
		hiss += (_noise() - hiss) * 0.12
		var value: float = brown * 0.6 + hiss * 0.12
		for start: float in chirps:
			var local: float = t - start
			if local > 0.0 and local < 0.09:
				value += sin(TAU * (3200.0 + local * 12000.0) * local) * 0.08 * sin(PI * local / 0.09)
		var distant: float = t - 3.2
		if distant > 0.0 and distant < 0.35:
			value += _square(distant * 440.0) * 0.03 * sin(PI * distant / 0.35)
		s[i] = value
	return _declick(s, 0.05)


func _horn(f1: float, f2: float, seconds: float) -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(seconds)
	var smooth: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		var env: float = minf(1.0, t / 0.01) * minf(1.0, (seconds - t) / 0.05)
		smooth += ((_square(t * f1) + _square(t * f2)) * 0.5 - smooth) * 0.3
		s[i] = smooth * env * 0.4
	return s


func _car_door() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(0.35)
	var low: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		low += (_noise() - low) * 0.05
		var thump: float = sin(TAU * 70.0 * t) * exp(-t / 0.06) * 0.7
		var body: float = low * exp(-t / 0.08) * 1.4
		var latch: float = _noise() * 0.5 if t > 0.02 and t < 0.028 else 0.0
		s[i] = thump + body + latch
	return s


func _brush() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(0.8)
	var a: float = 0.0
	var b: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		var n: float = _noise()
		a += (n - a) * 0.5
		b += (n - b) * 0.1
		var stroke: float = pow(0.5 + 0.5 * sin(TAU * 7.5 * t), 2.0)
		s[i] = (a - b) * stroke * 0.35
	return _declick(s, 0.01)


func _thunder() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(3.0)
	var brown: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		brown = clampf(brown + _noise() * 0.05, -1.0, 1.0) * 0.997
		var env: float = minf(1.0, t / 0.03) * exp(-t / 1.1)
		var crackle: float = _noise() * 0.6 if t < 0.6 and rng.randf() < 0.02 else 0.0
		s[i] = (brown * 1.2 + crackle) * env
	return _declick(s)


func _whoosh() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(0.9)
	var low: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / 0.9 / RATE
		low += (_noise() - low) * lerpf(0.03, 0.4, sin(PI * t))
		s[i] = low * pow(sin(PI * t), 2.0) * 0.8
	return _declick(s)


func _clink() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(0.25)
	for i: int in s.size():
		var t: float = float(i) / RATE
		s[i] = (sin(TAU * 2200.0 * t) + 0.6 * sin(TAU * 3310.0 * t)) * exp(-t / 0.05) * 0.25
	return _declick(s, 0.001)


func _chime() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(1.0)
	for i: int in s.size():
		var t: float = float(i) / RATE
		var first: float = sin(TAU * 880.0 * t) * exp(-t / 0.25)
		var second: float = sin(TAU * 659.0 * (t - 0.3)) * exp(-(t - 0.3) / 0.35) if t > 0.3 else 0.0
		s[i] = (first + second) * 0.3
	return _declick(s, 0.002)


func _door_slide() -> PackedFloat32Array:
	var s: PackedFloat32Array = _buffer(0.6)
	var low: float = 0.0
	for i: int in s.size():
		var t: float = float(i) / RATE
		low += (_noise() - low) * 0.06
		var env: float = sin(PI * t / 0.6)
		s[i] = (low * 0.9 + sin(TAU * 120.0 * t) * 0.15) * env * 0.6
	return _declick(s)
