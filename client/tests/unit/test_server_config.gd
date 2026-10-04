extends GdUnitTestSuite


func test_defaults_come_from_project_settings() -> void:
	var config: ServerConfig = ServerConfig.from_environment(PackedStringArray(), "")
	assert_str(config.host).is_equal(str(ProjectSettings.get_setting("office_game/server/host")))
	assert_int(config.port).is_equal(int(ProjectSettings.get_setting("office_game/server/port")))


func test_web_build_uses_the_page_host_with_the_configured_port() -> void:
	var config: ServerConfig = ServerConfig.from_environment(PackedStringArray(), "http://10.20.30.20")
	assert_str(config.host).is_equal("10.20.30.20")
	assert_int(config.port).is_equal(int(ProjectSettings.get_setting("office_game/server/port")))


func test_https_page_uses_the_tls_proxy() -> void:
	var config: ServerConfig = ServerConfig.from_environment(PackedStringArray(), "https://10.20.30.20")
	assert_str(config.describe()).is_equal("https://10.20.30.20:%d" % int(ProjectSettings.get_setting("office_game/server/tls_port")))


func test_server_argument_wins_over_the_page_host() -> void:
	var config: ServerConfig = ServerConfig.from_environment(PackedStringArray(["--server=https://game.local:8443"]), "https://10.0.0.1")
	assert_str(config.describe()).is_equal("https://game.local:8443")


func test_apply_url_parses_scheme_host_and_port() -> void:
	var config: ServerConfig = ServerConfig.new()
	assert_bool(config.apply_url("http://10.0.0.5:7350/")).is_true()
	assert_str(config.describe()).is_equal("http://10.0.0.5:7350")
	assert_bool(config.apply_url("https://example.org")).is_true()
	assert_int(config.port).is_equal(443)


func test_apply_url_rejects_malformed_urls_and_keeps_the_old_address() -> void:
	var config: ServerConfig = ServerConfig.new()
	config.apply_url("http://10.0.0.5:7350")
	for url: String in ["10.0.0.9:7350", "ftp://host:21", "http://", "http://host:port"]:
		assert_bool(config.apply_url(url)).override_failure_message(url).is_false()
	assert_str(config.describe()).is_equal("http://10.0.0.5:7350")
