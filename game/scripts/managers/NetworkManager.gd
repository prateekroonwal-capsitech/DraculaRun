class_name NetworkManager
extends Node

# NetworkManager — wraps all Firebase Cloud Function calls
# In PROTOTYPE stage all methods return instant mock data (no network)

var _id_token: String = ""
var _config: Node
var _logger: Node
var _bus: Node

func configure(config: Node, logger: Node, bus: Node) -> void:
	_config = config
	_logger = logger
	_bus = bus

func _ready() -> void:
	pass

func set_auth_token(token: String) -> void:
	_id_token = token

# ── Version Check ─────────────────────────────────────────────────────────

func check_version() -> Dictionary:
	if _config and _config.is_prototype():
		return { "status": "ok" }
	var game_id: String = _config.GAME_ID if _config else "game-template"
	var app_ver: String = _config.APP_VERSION if _config else "1.0.0"
	return await _call("config_versionCheck", {
		"gameId":   game_id,
		"platform": PlatformUtils.get_platform(),
		"version":  app_ver,
	})

# ── Player ────────────────────────────────────────────────────────────────

func get_profile() -> Dictionary:
	if _config and _config.is_prototype():
		return { "uid": "proto-uid", "displayName": "Prototype Player" }
	var game_id: String = _config.GAME_ID if _config else "game-template"
	return await _call("player_getProfile", {
		"gameId": game_id,
	})

func sync_progress(progress: Dictionary) -> Dictionary:
	if _config and _config.is_prototype():
		return { "version": 1, "accepted": true }
	var game_id: String = _config.GAME_ID if _config else "game-template"
	return await _call("player_syncProgress", {
		"gameId":   game_id,
		"progress": progress,
	})

# ── Internal HTTP ─────────────────────────────────────────────────────────

func _call(fn_name: String, payload: Dictionary) -> Dictionary:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)

	var base_url: String = str(_config.get_functions_url()) if _config else ""
	var url: String = base_url + "/" + fn_name
	var body: String = JSON.stringify({ "data": payload })
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + _id_token,
	])

	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		if _logger:
			_logger.error("NetworkManager: request error", { "fn": fn_name, "err": err })
		if _bus:
			_bus.sync_failed.emit("request error")
		return {}

	var result: Array = await http.request_completed
	http.queue_free()

	var status: int    = result[1]
	var raw:    String = result[3].get_string_from_utf8()

	if status != 200:
		if _logger:
			_logger.error("NetworkManager: HTTP error", { "fn": fn_name, "status": status })
		if _bus:
			_bus.sync_failed.emit("HTTP " + str(status))
		return {}

	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed.get("result", {})

	if _logger:
		_logger.error("NetworkManager: bad response", { "fn": fn_name })
	return {}

