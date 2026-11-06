extends GdUnitTestSuite

const SCRIPTS: Array[String] = [
	"res://scripts/main.gd",
	"res://scripts/home.gd",
	"res://scripts/world/world_scene.gd",
	"res://scripts/ui/chat/chat_panel.gd",
	"res://scripts/services/api/backend_chat.gd",
	"res://scripts/ui/profile/colleague_profile_panel.gd",
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


func _channel(unread: int) -> BackendChat.Channel:
	var channel: BackendChat.Channel = BackendChat.Channel.new()
	channel.unread = unread
	return channel
