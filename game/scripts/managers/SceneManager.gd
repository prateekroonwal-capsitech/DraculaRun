class_name SceneManager
extends Node

# SceneManager — async threaded loading with preload cache
# PDF §5 (Big scenes): preload_scene() loads the resource into memory without
#   instantiating it. go_to() reuses the cached resource so the scene tree
#   change happens with zero disk-read stall.
# PDF §6 Time Complexity: _preloaded is a Dictionary → O(1) lookup.

signal transition_started(scene_path: String)
signal transition_finished(scene_path: String)

const LevelCatalog = preload("res://game/scenes/gameplay/shadow_run/level/LevelCatalog.gd")
const LoadingScreen = preload("res://game/scenes/loading/LoadingScreen.gd")

# PDF §5 + §6: Dictionary cache — O(1) lookup, resource held in memory only
var _preloaded: Dictionary = {}
var _loading:   bool       = false
var _logger: Node
var _registry: Node

@export var loading_screen_scene: PackedScene = preload("res://game/scenes/loading/LoadingScreen.tscn")
@export var catalog: LevelCatalog = preload("res://game/scenes/gameplay/shadow_run/level/level_catalog.tres")
## Fade in duration for the dark gothic transition curtain (seconds).
@export var fade_in_time: float = 0.2
## Fade out duration revealing the prepared gameplay frame (seconds).
@export var fade_out_time: float = 0.25

var _loading_screen: LoadingScreen = null

func _get_or_create_loading_screen() -> LoadingScreen:
	if _loading_screen != null and is_instance_valid(_loading_screen):
		return _loading_screen
	if loading_screen_scene == null:
		return null
	_loading_screen = loading_screen_scene.instantiate() as LoadingScreen
	if is_inside_tree():
		add_child.call_deferred(_loading_screen)
	elif get_tree() and get_tree().root:
		get_tree().root.add_child.call_deferred(_loading_screen)
	return _loading_screen

func configure(logger: Node, registry: Node = null) -> void:
	_logger = logger
	_registry = registry

func _ready() -> void:
	if loading_screen_scene != null and _loading_screen == null:
		_loading_screen = loading_screen_scene.instantiate() as LoadingScreen
		add_child.call_deferred(_loading_screen)

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

	var loader := _get_or_create_loading_screen()
	if loader:
		if not loader.is_inside_tree():
			await loader.tree_entered
		var num_str := ""
		var name_str := ""
		if catalog:
			var entry := catalog.get_entry_by_scene(scene_path)
			if entry:
				var idx := catalog.get_index_by_scene(scene_path)
				num_str = "LEVEL %d" % (idx + 1)
				name_str = entry.display_name
		loader.set_level_info(num_str, name_str)
		await loader.fade_in(fade_in_time)

	# Clear any panels on UIManager behind the loading screen so menus don't linger
	var ui: UIManager = null
	if _registry:
		ui = _registry.get_service(&"ui") as UIManager
	if ui == null and get_tree() and get_tree().root:
		var reg: Node = get_tree().root.get_node_or_null("ServiceRegistry")
		if reg:
			ui = reg.get_service(&"ui") as UIManager
	if ui:
		ui.clear_all()

	# PDF §5: use cached resource if available, else load async
	var packed: PackedScene
	if _preloaded.has(scene_path):
		packed = _preloaded[scene_path]          # O(1) — no disk hit
		_preloaded.erase(scene_path)             # free the cache slot
		if _logger:
			_logger.debug("SceneManager: using preloaded resource")
	else:
		packed = await _load_async(scene_path, loader)  # fallback threaded load

	if packed == null:
		_loading = false
		if loader:
			await loader.fade_out(0.1)
		if _logger:
			_logger.error("Scene load failed", { "path": scene_path })
		return

	get_tree().change_scene_to_packed(packed)
	await get_tree().process_frame
	var cur_scene := get_tree().current_scene
	_auto_inject_scene(cur_scene)

	# If the target scene is a level with ShadowRunFeature, wait for its warm-up and shade grid build
	var feature: Node = null
	if cur_scene:
		feature = cur_scene.find_child("ShadowRunFeature", true, false)
	if feature and feature.has_signal("level_ready"):
		if feature.has_method("is_ready") and not feature.is_ready():
			var timer := get_tree().create_timer(3.0)
			var ready_box := [false]
			var on_ready_cb := func() -> void: ready_box[0] = true
			feature.level_ready.connect(on_ready_cb, CONNECT_ONE_SHOT)
			while not ready_box[0] and timer.time_left > 0.0:
				await get_tree().process_frame

	# Ensure at least one fully composed frame renders behind the loading screen
	await get_tree().process_frame

	if loader:
		await loader.fade_out(fade_out_time)

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

func _load_async(path: String, loader: LoadingScreen = null) -> PackedScene:
	ResourceLoader.load_threaded_request(path)
	var progress: Array = []
	while true:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path, progress)
		if loader and progress.size() > 0:
			loader.set_progress(progress[0])
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				return ResourceLoader.load_threaded_get(path)
			ResourceLoader.THREAD_LOAD_FAILED:
				return null
		await get_tree().process_frame
	return null
