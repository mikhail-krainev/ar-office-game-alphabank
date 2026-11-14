extends GdUnitTestSuite

const SCRIPTS: Array[String] = [
	"res://scripts/main.gd",
	"res://scripts/home.gd",
	"res://scripts/world/world_scene.gd",
	"res://scripts/ui/chat/chat_panel.gd",
	"res://scripts/services/api/backend_chat.gd",
	"res://scripts/ui/profile/colleague_profile_panel.gd",
	"res://scripts/ui/unread_dot.gd",
]


func test_chat_and_world_scripts_compile() -> void:
	for path: String in SCRIPTS:
		var script: GDScript = load(path) as GDScript
		assert_object(script).is_not_null()
		assert_bool(script.can_instantiate()).is_true()


func test_overview_counts_unread_in_every_chat() -> void:
	var overview: BackendChat.Overview = BackendChat.Overview.new()
	overview.office = _channel(2)
	overview.direct = [_channel(1), _channel(0)]
	assert_int(overview.total_unread()).is_equal(3)
	overview.department = _channel(4)
	assert_int(overview.total_unread()).is_equal(7)


func test_only_new_unread_direct_messages_are_announced() -> void:
	var chat: BackendChat = auto_free(BackendChat.new(null))
	var announced: Array[String] = []
	chat.direct_message_received.connect(func(channel: BackendChat.Channel) -> void: announced.append(channel.last.id))
	# The first overview after launch only remembers what is already there.
	chat._announce_direct([_direct("anna", "m1", 1, false)])
	assert_array(announced).is_empty()
	# Same message again, a new one from Anna, an own message and a read one from Oleg.
	chat._announce_direct([_direct("anna", "m1", 1, false)])
	assert_array(announced).is_empty()
	chat._announce_direct([_direct("anna", "m2", 2, false), _direct("ivan", "m3", 0, true), _direct("oleg", "m4", 0, false)])
	assert_array(announced).contains_exactly(["m2"])


func _direct(user_id: String, message_id: String, unread: int, mine: bool) -> BackendChat.Channel:
	var channel: BackendChat.Channel = _channel(unread)
	channel.user_id = user_id
	channel.last = BackendChat.Message.new()
	channel.last.id = message_id
	channel.last.mine = mine
	return channel


func _channel(unread: int) -> BackendChat.Channel:
	var channel: BackendChat.Channel = BackendChat.Channel.new()
	channel.unread = unread
	return channel
