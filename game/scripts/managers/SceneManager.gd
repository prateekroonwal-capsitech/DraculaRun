class_name SceneManager
extends Node

# SceneManager — async threaded loading with preload cache
# PDF §5 (Big scenes): preload_scene() loads the resource into memory without
#   instantiating it. go_to() reuses the cached resource so the scene tree
#   change happens with zero disk-read stall.
# PDF §6 Time Complexity: _preloaded is a Dictionary → O(1) lookup.

signal transition_started(scene_path: String)
signal transition_finished(scene_path: String)

# PDF §5 + §6: Dictionary cache — O(1) lookup, resource held in memory only
var _preloaded: Dictionary = {}
var _loading:   bool       = false
var _logger: Node
var _registry: Node

func configure(logger: Node, registry: Node = null) -> void:
	_logger = logger
	_registry = registry

func _ready() -> void:
	pass

# ── PDF §5: Preload API ────────────────────────────────────────────────────
# Call this from a loading screen to warm up the next scene.
# Stores the PackedScene resource without touching the scene tree.

func preload_scene(path: String) -> void:
	if _preloaded.has(path):
		return  # PDF §6: already cached, skip the request
	ResourceLoader.load_threaded_request(path)
	# Poll until loaded, then store — runs async on the background thread
	while true:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_preloaded[path] = ResourceLoader.load_threaded_get(path)
			if _logger:
				_logger.info("SceneManager: preloaded", { "path": path })
			return
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			if _logger:
				_logger.error("SceneManager: preload failed", { "path": path })
			return
		await get_tree().process_frame

# ── Main navigation ────────────────────────────────────────────────────────

func go_to(scene_path: String) -> void:
	if _loading:
		if _logger:
			_logger.warn("SceneManager: already loading")
		return

	_loading = true
	transition_started.emit(scene_path)
	if _logger:
		_logger.info("SceneManager: going to", { "path": scene_path })

	# PDF §5: use cached resource if available, else load async
	var packed: PackedScene
	if _preloaded.has(scene_path):
		packed = _preloaded[scene_path]          # O(1) — no disk hit
		_preloaded.erase(scene_path)             # free the cache slot
		if _logger:
			_logger.debug("SceneManager: using preloaded resource")
	else:
		packed = await _load_async(scene_path)  # fallback threaded load

	if packed == null:
		_loading = false
		if _logger:
			_logger.error("Scene load failed", { "path": scene_path })
		return

	get_tree().change_scene_to_packed(packed)
	await get_tree().process_frame
	_auto_inject_scene(get_tree().current_scene)
	_loading = false
	transition_finished.emit(scene_path)

func is_loading() -> bool:
	return _loading

func _auto_inject_scene(scene: Node) -> void:
	if not scene:
		return
	if not _registry:
		_registry = get_tree().root.get_node_or_null("ServiceRegistry")
	if not _registry:
		return

	# Pattern 2: Convention-based dependency auto-wiring.
	# Check the scene root itself, then all descendants in the loaded tree.
	if scene.has_method("inject_services"):
		scene.inject_services(_registry)

	for node in scene.find_children("*", "", true, false):
		if node.has_method("inject_services"):
			node.inject_services(_registry)


# ── Internals ──────────────────────────────────────────────────────────────

func _load_async(path: String) -> PackedScene:
	ResourceLoader.load_threaded_request(path)
	while true:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				return ResourceLoader.load_threaded_get(path)
			ResourceLoader.THREAD_LOAD_FAILED:
				return null
		await get_tree().process_frame
	return null
