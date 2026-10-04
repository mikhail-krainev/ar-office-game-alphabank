class_name TongueTwisterMinigame
extends Minigame
## "Tongue twister": read the phrase aloud; the system speech recognizer (Russian) must hear it
## close enough. A recognizer may work through the cloud, so the game needs a network.

const DEFAULT_PHRASES: Array[String] = [
	"Шла Саша по шоссе и сосала сушку",
	"Карл у Клары украл кораллы",
	"Ехал Грека через реку",
]
const DEFAULT_ROUNDS: int = 2
const MAX_MISTAKES: int = 3

var _phrases: Array[String] = []
var _rounds: int = DEFAULT_ROUNDS
var _round: int = 0
var _mistakes: int = 0
var _listening: bool = false
var _score_sum: float = 0.0
var _pulse: float = 0.0

var _phrase_label: Label
var _heard_label: Label
var _status: Label
var _speak: Button


func _ready() -> void:
	var pool: Array[String] = DEFAULT_PHRASES.duplicate()
	if task != null and task.params.get("phrases") is Array:
		pool.clear()
		for phrase: Variant in task.params["phrases"]:
			pool.append(str(phrase))
		_rounds = int(task.params.get("rounds", DEFAULT_ROUNDS))
	pool.shuffle()
	_rounds = mini(_rounds, pool.size())
	_phrases = pool.slice(0, _rounds)
	add_hint(tr("MG_TWISTER_HINT"))
	_phrase_label = add_big_label(60, 18)
	_phrase_label.size.y = 90
	_heard_label = add_big_label(170, 12, UiStyle.MUTED)
	_heard_label.size.y = 50
	_status = add_status()
	_speak = UiStyle.make_button(tr("MG_TWISTER_SPEAK"), true, 14)
	_speak.custom_minimum_size = Vector2(180, 40)
	_speak.position = Vector2((AREA_SIZE.x - 180.0) / 2.0, 240)
	_speak.pressed.connect(_listen)
	add_child(_speak)
	PlatformServices.speech_recognized.connect(_on_speech)
	PlatformServices.speech_failed.connect(_on_speech_failed)
	_update_labels()
	PlatformServices.prepare_speech("ru-RU")


func _exit_tree() -> void:
	super()
	PlatformServices.speech_recognized.disconnect(_on_speech)
	PlatformServices.speech_failed.disconnect(_on_speech_failed)


func _listen() -> void:
	if _listening or is_done():
		return
	_listening = true
	_heard_label.text = ""
	_speak.disabled = true
	_speak.text = tr("MG_TWISTER_LISTENING")
	PlatformServices.start_speech("ru-RU")


func _on_speech(text: String, is_final: bool) -> void:
	if not _listening:
		return
	_heard_label.text = "«%s»" % text
	if not is_final:
		return
	_stop_listening()
	var score: float = PhraseMatcher.score(_phrases[_round], text)
	if score >= PhraseMatcher.PASS_SCORE:
		_score_sum += score
		_round += 1
		if _round >= _rounds:
			set_score(_score_sum / _rounds)
			finish(true)
			return
		_heard_label.text = tr("MG_TWISTER_GOOD")
	else:
		_register_mistake()
	_update_labels()


func _on_speech_failed(error: String) -> void:
	if not _listening:
		return
	_stop_listening()
	_heard_label.text = tr("MG_TWISTER_ERROR") % error
	if error == "unsupported":
		finish(false)


func _register_mistake() -> void:
	_mistakes += 1
	_heard_label.text += "\n" + tr("MG_TWISTER_AGAIN")
	if _mistakes >= MAX_MISTAKES:
		finish(false)


func _stop_listening() -> void:
	_listening = false
	PlatformServices.stop_speech()
	_speak.disabled = is_done()
	_speak.text = tr("MG_TWISTER_SPEAK")
	if not is_done():
		PlatformServices.prepare_speech("ru-RU")


func _update_labels() -> void:
	_phrase_label.text = _phrases[mini(_round, _phrases.size() - 1)]
	_status.text = "%s   %s" % [tr("MG_ROUND") % [mini(_round + 1, _rounds), _rounds], tr("MG_MISTAKES") % [_mistakes, MAX_MISTAKES]]


func _process(delta: float) -> void:
	super(delta)
	_pulse = fmod(_pulse + delta * 3.0, TAU) if _listening else 0.0
	queue_redraw()


func _draw() -> void:
	if not _listening:
		return
	var center: Vector2 = _speak.position + Vector2(_speak.size.x + 28.0, _speak.size.y / 2.0)
	for i: int in 3:
		var radius: float = 6.0 + i * 6.0 + sin(_pulse - i) * 2.0
		draw_arc(center, radius, 0.0, TAU, 24, Color(UiStyle.RED, 1.0 - i * 0.3), 2.0)
