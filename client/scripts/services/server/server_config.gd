class_name ServerConfig
extends RefCounted
## Where the Nakama server is. Defaults come from the project settings (office_game/server/*).
## The game always needs the server. Overrides, strongest first:
##   --server=http://10.20.30.5:7350  another server;
##   web build                       the host the page was opened from; over HTTPS the TLS proxy port
##                                   (office_game/server/tls_port, Caddy in front of Nakama).

const SETTING_PREFIX: String = "office_game/server/"
const DEFAULT_PORT: int = 7350
const DEFAULT_TLS_PORT: int = 7443

var scheme: String = "http"
var host: String = "127.0.0.1"
var port: int = DEFAULT_PORT
var server_key: String = "defaultkey"


static func from_environment(user_args: PackedStringArray, page_origin: String) -> ServerConfig:
	var config: ServerConfig = ServerConfig.new()
	config.scheme = str(ProjectSettings.get_setting(SETTING_PREFIX + "scheme", config.scheme))
	config.host = str(ProjectSettings.get_setting(SETTING_PREFIX + "host", config.host))
	config.port = int(ProjectSettings.get_setting(SETTING_PREFIX + "port", config.port))
	config.server_key = str(ProjectSettings.get_setting(SETTING_PREFIX + "key", config.server_key))
	if not page_origin.is_empty():
		var parts: PackedStringArray = page_origin.split("://", true, 1)
		if parts.size() == 2 and not parts[1].is_empty():
			config.host = parts[1]
			# A page opened over HTTPS may call only HTTPS: the proxy serves Nakama there.
			if parts[0] == "https":
				config.scheme = "https"
				config.port = int(ProjectSettings.get_setting(SETTING_PREFIX + "tls_port", DEFAULT_TLS_PORT))
	for arg: String in user_args:
		if arg.begins_with("--server="):
			config.apply_url(arg.trim_prefix("--server="))
	return config


## Takes scheme, host and port from "scheme://host:port". Returns false when the url is malformed.
func apply_url(url: String) -> bool:
	var parts: PackedStringArray = url.split("://", true, 1)
	if parts.size() != 2 or not parts[0] in ["http", "https"] or parts[1].is_empty():
		return false
	var address: String = parts[1].trim_suffix("/")
	var next_port: int = 443 if parts[0] == "https" else DEFAULT_PORT
	var colon: int = address.rfind(":")
	if colon > 0:
		if not address.substr(colon + 1).is_valid_int():
			return false
		next_port = address.substr(colon + 1).to_int()
		address = address.left(colon)
	scheme = parts[0]
	host = address
	port = next_port
	return true


func describe() -> String:
	return "%s://%s:%d" % [scheme, host, port]
