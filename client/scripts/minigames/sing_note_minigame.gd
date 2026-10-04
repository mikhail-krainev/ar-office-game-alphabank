class_name SingNoteMinigame
extends Minigame
## "Sing the note": a tuner. Hold each target note (any octave) within the tolerance for a moment.
## Pitch comes from YIN on the raw microphone buffer; audio never leaves the phone.

const DEFAULT_NOTES: Array[int] = [0, 4, 7]
const DEFAULT_TIME_LIMIT: float = 60.0
const HOLD_SECONDS: float = 1.0
const TOLERANCE_CENTS: float = 50.0
const TARGET_RATE: float = 12000.0
const ANALYSIS_SAMPLES: int = 512
const ANALYSIS_INTERVAL: float = 0.1
const MAX_READ_FRAMES: int = 8192
const GAUGE_CENTER: Vector2 = Vector2(160, 250)
const GAUGE_RADIUS: float = 90.0
const GAUGE_RANGE_CENTS: float = 100.0
## The pitch is the median of this many latest estimates: single octave slips do not move the needle.
const SMOOTHING_WINDOW: int = 5

var _notes: Array[int] = DEFAULT_NOTES.duplicate()
var _index: int = 0
var _hold: float = 0.0
var _time_left: float = DEFAULT_TIME_LIMIT
var _time_limit: float = DEFAULT_TIME_LIMIT
var _buffer: PackedFloat32Array = PackedFloat32Array()
var _analysis_left: float = 0.0
var _frequency: float = 0.0
var _cents: float = 0.0
var _accuracy_sum: float = 0.0
var _accuracy_count: int = 0
var _estimates: Array[float] = []
var _heard_label: Label

var _note_label: Label
var _status: Label


func _ready() -> void:
	if task != null and task.params.get("notes") is Array:
		_notes.clear()
		for note: Variant in task.params["notes"]:
			_notes.append(int(note))
		_time_limit = float(task.params.get("time_limit", DEFAULT_TIME_LIMIT))
	_time_left = _time_limit
	add_hint(tr("MG_SING_HINT"))
	_note_label = add_big_label(48, 40, UiStyle.RED)
	_heard_label = add_big_label(GAUGE_CENTER.y + 34.0, 12, UiStyle.MUTED)
	_status = add_status()
	PlatformServices.start_microphone()


func _process(delta: float) -> void:
	super(delta)
	_read_microphone()
	if not is_done():
		_time_left -= delta
		_analysis_left -= delta
		if _analysis_left <= 0.0:
			_analysis_left = ANALYSIS_INTERVAL
			_analyze()
		var in_tune: bool = _frequency > 0.0 and absf(_cents) <= TOLERANCE_CENTS
		_hold = _hold + delta if in_tune else maxf(0.0, _hold - delta * 2.0)
		if _hold >= HOLD_SECONDS:
			_hold = 0.0
			_index += 1
			if _index >= _notes.size():
				var accuracy: float = _accuracy_sum / maxi(_accuracy_count, 1)
				set_score(accuracy)
				finish(true)
		if _time_left <= 0.0 and not is_done():
			finish(false)
	var current: int = _notes[mini(_index, _notes.size() - 1)]
	_note_label.text = tr(PitchDetector.note_key(current))
	var heard: String = "%d Hz" % roundi(_frequency) if _frequency > 0.0 else tr("MG_SING_SILENCE")
	_heard_label.text = tr("MG_SING_HEARD") % tr(PitchDetector.note_key(roundi(PitchDetector.frequency_to_midi(_frequency)))) if _frequency > 0.0 else ""
	_status.text = "%s   %s   %s" % [tr("MG_ROUND") % [mini(_index + 1, _notes.size()), _notes.size()], heard, tr("MG_TIME") % ceili(maxf(_time_left, 0.0))]
	queue_redraw()


func _read_microphone() -> void:
	var samples: PackedFloat32Array = PlatformServices.read_microphone(MAX_READ_FRAMES)
	if samples.is_empty() or PlatformServices.get_microphone_sample_rate() <= 0.0:
		# Samples without a known rate would mix with later ones at another rate.
		return
	var factor: int = maxi(1, roundi(PlatformServices.get_microphone_sample_rate() / TARGET_RATE))
	# Box-filter downsampling keeps YIN cheap enough for GDScript.
	for i: int in range(0, samples.size() - factor + 1, factor):
		var sum: float = 0.0
		for j: int in factor:
			sum += samples[i + j]
		_buffer.append(sum / factor)
	if _buffer.size() > ANALYSIS_SAMPLES:
		_buffer = _buffer.slice(_buffer.size() - ANALYSIS_SAMPLES)


func _analyze() -> void:
	if _buffer.size() < ANALYSIS_SAMPLES:
		return
	var factor: int = maxi(1, roundi(PlatformServices.get_microphone_sample_rate() / TARGET_RATE))
	var rate: float = PlatformServices.get_microphone_sample_rate() / factor
	var estimate: float = PitchDetector.detect(_buffer, rate)
	if estimate <= 0.0:
		_estimates.clear()
		_frequency = 0.0
		return
	_estimates.append(estimate)
	if _estimates.size() > SMOOTHING_WINDOW:
		_estimates.remove_at(0)
	var sorted: Array[float] = _estimates.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	_frequency = sorted[sorted.size() / 2]
	_cents = PitchDetector.cents_off_pitch_class(_frequency, _notes[mini(_index, _notes.size() - 1)])
	if absf(_cents) <= TOLERANCE_CENTS:
		_accuracy_sum += 1.0 - absf(_cents) / TOLERANCE_CENTS
		_accuracy_count += 1


func _draw() -> void:
	# Tuner gauge: the needle points at the cents offset from the target note.
	var start: float = PI + 0.25
	var end: float = TAU - 0.25
	draw_arc(GAUGE_CENTER, GAUGE_RADIUS, start, end, 40, UiStyle.SHADE, 14.0)
	var zone: float = (end - start) * TOLERANCE_CENTS / (GAUGE_RANGE_CENTS * 2.0)
	var middle: float = (start + end) / 2.0
	draw_arc(GAUGE_CENTER, GAUGE_RADIUS, middle - zone, middle + zone, 12, Color("#3f9e4a"), 14.0)
	var offset: float = clampf(_cents / GAUGE_RANGE_CENTS, -1.0, 1.0) if _frequency > 0.0 else 0.0
	var angle: float = middle + offset * (end - start) / 2.0
	var needle_color: Color = UiStyle.RED if _frequency > 0.0 else UiStyle.MUTED
	draw_line(GAUGE_CENTER, GAUGE_CENTER + Vector2.from_angle(angle) * (GAUGE_RADIUS + 8.0), needle_color, 3.0)
	draw_circle(GAUGE_CENTER, 6.0, UiStyle.INK)
	var hold_rect: Rect2 = Rect2(60, GAUGE_CENTER.y + 20, 200, 8)
	draw_rect(hold_rect.grow(2), UiStyle.INK)
	draw_rect(hold_rect, UiStyle.PAPER)
	draw_rect(Rect2(hold_rect.position, Vector2(hold_rect.size.x * _hold / HOLD_SECONDS, hold_rect.size.y)), UiStyle.RED)
