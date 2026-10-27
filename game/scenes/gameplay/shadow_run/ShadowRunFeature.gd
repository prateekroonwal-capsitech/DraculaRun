class_name ShadowRunFeature
extends GameFeature

## ShadowRunFeature — one puzzle level's lifecycle. Core loop:
##   adjust the sun → shadows (and the ShadeGrid's walkable cells) change →
##   tap a shaded spot → Dracula walks the A* path → repeat until the goal.
##
##   SceneManager loads levels/LevelNN.tscn → inject_services() → initialize(deps)
##   → _setup(): configure sun from the level, place Dracula on Start, build the
##     ShadeGrid, arm the sun's exposure guard → GameManager.start()
##   → goal reached: SaveManager.complete_level() → Level Complete panel (Next/Retry/Home)
##   → burned (exposure 100): ash-and-bats death → Game Over panel (Retry/Home)
##
## Gameplay systems (grid, sensor, sun, camera, previews) are scene nodes handed in via
## @export and configured here — they are not shared services. Shared services arrive
## through inject_services()/initialize() only.

const HOME_SCENE := "res://game/scenes/Home/Home.tscn"

## The level root (set by each levels/LevelNN.tscn on its Game/ShadowRunFeature node).
@export var level: ShadowLevel
@export var dracula: DraculaController
@export var sun_rig: SunRig
@export var sensor: ShadowSensor
@export var run_camera: RunCameraController
@export var hud: ShadowRunHUD
@export var debug_overlay: ShadowDebugOverlay
@export var tap_marker: TapMarker
@export var level_complete_panel: PackedScene
@export var game_over_panel: PackedScene
@export var pause_panel: PackedScene

@export_group("Tap")
## A press that moves less than this (px) and lasts less than tap_max_time is a tap.
@export var tap_slop: float = 30.0
@export var tap_max_time: float = 0.45

@export_group("Intro")
@export var title_time: float = 1.2
## EDITOR ONLY: when a level is launched directly (F6) there is no Boot → GameService.
## With this on, the feature boots GameService itself. Never active in exported builds.
@export var editor_f6_fallback: bool = true

var _game: GameManager
var _scene: SceneManager
var _ui: UIManager
var _save: SaveManager
var _audio: AudioManager
var _haptics: HapticsManager
var _bus: Node
var _logger: Node

var _running: bool = false
var _finished: bool = false
var _leaving: bool = false
var _dragging: bool = false
var _pending_tap: Variant = null
var _press: Dictionary = {}       # touch index (-1 mouse) -> {pos, time}
var _ray_query: PhysicsRayQueryParameters3D
var _region: PackedByteArray = PackedByteArray()
var _path_points: PackedVector3Array = PackedVector3Array()

# ── Injection ─────────────────────────────────────────────────────────────

## Adapter for SceneManager's convention-based scene injection.
func inject_services(registry: Node) -> void:
	if not registry:
		return
	initialize({
		"game": registry.get_service(&"game"),
		"scene": registry.get_service(&"scene"),
		"ui": registry.get_service(&"ui"),
		"save": registry.get_service(&"save"),
		"audio": registry.get_service(&"audio"),
		"haptics": registry.get_service(&"haptics"),
		"bus": registry.get_service(&"bus"),
		"logger": registry.get_service(&"logger"),
	})

func initialize(dependencies: Dictionary) -> void:
	if _initialized:
		return
	super.initialize(dependencies)
	_game = dependencies.get("game") as GameManager
	_scene = dependencies.get("scene") as SceneManager
	_ui = dependencies.get("ui") as UIManager
	_save = dependencies.get("save") as SaveManager
	_audio = dependencies.get("audio") as AudioManager
	_haptics = dependencies.get("haptics") as HapticsManager
	_bus = dependencies.get("bus") as Node
	_logger = dependencies.get("logger") as Node
	if _game == null or _scene == null or _ui == null or _bus == null or level == null:
		push_error("ShadowRunFeature: missing required dependency (game/scene/ui/bus/level)")
		return
	# Deferred: SceneManager injects the rest of the scene in this same loop.
	_setup.call_deferred()

func _ready() -> void:
	process_physics_priority = 20   # after Dracula (0) and ShadowSensor (10)
	set_physics_process(false)      # PDF §4: idle until the level starts
	_ray_query = PhysicsRayQueryParameters3D.new()
	if editor_f6_fallback and OS.has_feature("editor"):
		_editor_fallback_boot.call_deferred()

# ── Setup ─────────────────────────────────────────────────────────────────

func _setup() -> void:
	var grid := level.grid
	sun_rig.configure(level.azimuth_min, level.azimuth_max, level.elevation_min, level.elevation_max,
		level.sun_start_azimuth, level.sun_start_elevation)
	dracula.place_at(level.start.global_position, level.start.global_rotation.y)
	run_camera.center_x = level.center_x()
	run_camera.follow(dracula)
	# Level bodies must be in the physics space before the grid ray-casts.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var t0 := Time.get_ticks_msec()
	grid.setup(sun_rig, level.azimuth_min, level.azimuth_max, level.elevation_min, level.elevation_max)
	if _logger:
		_logger.info("ShadowRun: grid ready", {"cells": grid.cell_count(), "variable": grid.variable_cell_count(),
			"ms": Time.get_ticks_msec() - t0})
	sensor.setup(dracula.get_sample_points(), sun_rig)
	sensor.exposure_changed.connect(_on_exposure_changed)
	sensor.burned_out.connect(_on_burned_out)
	sensor.reset()
	sun_rig.guard = _sun_is_safe
	sun_rig.sun_moved.connect(_on_sun_moved)
	sun_rig.settled.connect(_on_sun_settled)
	sun_rig.guard_blocked.connect(_on_guard_blocked)
	grid.shade_updated.connect(_refresh_region)
	level.goal.reached.connect(_on_goal_reached)
	dracula.arrived.connect(_refresh_region)
	dracula.death_finished.connect(_on_death_finished)
	hud.bind_sun(sun_rig)
	hud.set_level_title(level.level_title, level.level_number)
	hud.pause_requested.connect(request_pause)
	hud.debug_toggle_requested.connect(debug_overlay.toggle)
	hud.sun_drag_started.connect(_on_sun_drag_started)
	hud.sun_drag_ended.connect(_on_sun_drag_ended)
	debug_overlay.setup(grid, sensor, sun_rig, dracula, self)
	_bus.game_started.connect(_on_game_started)
	if _game.state != GameManager.State.IDLE:
		_game.reset()   # coming back from a previous level / Home
	_refresh_region()
	hud.show_title("LEVEL %d" % level.level_number, title_time)
	if level.hint != "":
		hud.show_hint(level.hint, 5.0)
	start()

func start() -> void:
	super.start()
	_game.start()   # → GameBus.game_started → _on_game_started

func _on_game_started() -> void:
	_running = true
	dracula.activate()
	sensor.set_active(true)
	set_physics_process(true)
	_bus.level_started.emit(str(level.level_number))
	if _logger:
		_logger.info("ShadowRun: level started", {"level": level.level_number})

func _physics_process(_delta: float) -> void:
	if not _running:
		return
	dracula.set_burn_state(sensor.exposure, sensor.exposure_fraction)

# ── Sun ───────────────────────────────────────────────────────────────────

## Exposure guard: would Dracula's footprint still be fully shaded with the sun at `dir`?
func _sun_is_safe(dir: Vector3) -> bool:
	if not _running or not dracula.is_active():
		return true
	var space := dracula.get_world_3d().direct_space_state
	for p in dracula.get_sample_points():
		if not ShadowSensor.is_point_shaded(space, _ray_query, p.global_position, dir, sensor.ray_length, sensor.caster_mask):
			return false
	return true

func _on_sun_moved(_az: float, _el: float) -> void:
	if level and level.grid.cols > 0:
		level.grid.request_refresh()

func _on_sun_settled() -> void:
	# Exact walkable area once the sun is at rest (a fast pass over a few frames);
	# taps wait for it via _pending_tap and shade_updated.
	level.grid.refresh_soon()

func _on_guard_blocked() -> void:
	dracula.play_flinch()
	hud.play_sun_blocked()

func _on_sun_drag_started() -> void:
	_dragging = true
	dracula.stop_at_next_waypoint()   # he stands still while the sun moves

func _on_sun_drag_ended() -> void:
	_dragging = false
	if sun_rig.is_settled():
		_on_sun_settled()

# ── Tap to move ───────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_run"):
		request_pause()
		get_viewport().set_input_as_handled()
		return
	if not _running or _finished:
		return
	# Ignore mouse<->touch emulation duplicates so one finger is one tap.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var index := -2
	var pos := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch:
		index = (event as InputEventScreenTouch).index
		pos = (event as InputEventScreenTouch).position
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		index = -1
		pos = (event as InputEventMouseButton).position
		pressed = (event as InputEventMouseButton).pressed
	else:
		return
	if pressed:
		_press[index] = {"pos": pos, "time": Time.get_ticks_msec()}
		return
	if not _press.has(index):
		return
	var p: Dictionary = _press[index]
	_press.erase(index)
	if pos.distance_to(p.pos) <= tap_slop and (Time.get_ticks_msec() - int(p.time)) <= int(tap_max_time * 1000.0):
		get_viewport().set_input_as_handled()
		handle_tap(pos)

## A tap at a viewport position (public so tests can drive it).
func handle_tap(viewport_pos: Vector2) -> void:
	if _dragging or not hud.is_in_play_view(viewport_pos):
		return
	var cam := get_viewport().get_camera_3d()
	var origin := cam.project_ray_origin(viewport_pos)
	var normal := cam.project_ray_normal(viewport_pos)
	if absf(normal.y) < 0.0001:
		return
	var t := (level.grid.global_position.y - origin.y) / normal.y
	if t <= 0.0:
		return
	move_to(origin + normal * t)

## Walk to a world point if a shaded route exists; otherwise show the "no" cue.
func move_to(world: Vector3) -> void:
	if not _running or _finished or _dragging:
		return
	if not sun_rig.is_settled() or level.grid.is_busy():
		_pending_tap = world   # shade still updating: answer as soon as it is exact
		return
	var grid := level.grid
	var target := grid.cell_at(world)
	var from := grid.nearest_walkable(grid.cell_at(dracula.global_position), 1)
	var path := {}
	if grid.in_bounds(from) and grid.is_walkable(target):
		path = grid.find_path(from, target)
	if path.is_empty():
		tap_marker.play_at(world, false)
		dracula.play_no_cue()
		return
	var cells: Array[Vector2i] = path.cells
	var hops: Array[bool] = path.hops
	_path_points = PackedVector3Array()
	for c in cells:
		_path_points.append(grid.cell_center(c))
	if _path_points.is_empty():
		return
	tap_marker.play_at(grid.cell_center(target), true)
	dracula.follow_path(_path_points, hops)

## True when nothing is pending: Dracula still, no queued tap, sun at rest, shade exact.
func is_idle() -> bool:
	return not dracula.is_moving() and _pending_tap == null and sun_rig.is_settled() and not level.grid.is_busy()

func current_path() -> PackedVector3Array:
	return _path_points if dracula.is_moving() else PackedVector3Array()

func _try_pending_tap() -> void:
	if _pending_tap == null or not sun_rig.is_settled() or level.grid.is_busy():
		return
	var w: Vector3 = _pending_tap
	_pending_tap = null
	move_to(w)

# ── Region preview / goal ─────────────────────────────────────────────────

func _refresh_region() -> void:
	if level == null or level.grid.cols == 0:
		return
	var grid := level.grid
	var from := grid.nearest_walkable(grid.cell_at(dracula.global_position), 1)
	_region = grid.region_from(from) if grid.in_bounds(from) else PackedByteArray()
	# No outline is drawn in gameplay: the reachable region only drives pathfinding,
	# the goal glow and the F3 debug overlay.
	var connected := false
	if not _region.is_empty():
		var g := grid.nearest_walkable(grid.cell_at(level.goal.global_position), 2)
		connected = grid.in_bounds(g) and _region[grid.index_of(g)] != 0
	level.goal.set_connected(connected)
	debug_overlay.mark_dirty()
	_try_pending_tap()

func region_mask() -> PackedByteArray:
	return _region

func _on_goal_reached() -> void:
	if _finished or not _running:
		return
	_finished = true
	_running = false
	sensor.set_active(false)
	dracula.stop_at_next_waypoint()
	hud.set_controls_enabled(false)
	if _save:
		_save.complete_level(level.level_number, 3, 100)
		_save.save_game()
	_game.game_over("level_complete")   # → GameBus.game_over("level_complete")
	_bus.level_completed.emit(str(level.level_number))
	if _logger:
		_logger.info("ShadowRun: level complete", {"level": level.level_number})
	_ui.push_packed(level_complete_panel)
	var panel := _ui.current() as LevelCompletePanel
	if panel:
		panel.show_result(level.level_title, level.level_number, level.next_level != "")
		panel.next_requested.connect(_leave.bind(level.next_level if level.next_level != "" else HOME_SCENE))
		panel.retry_requested.connect(_leave.bind(level.scene_file_path))
		panel.home_requested.connect(_leave.bind(HOME_SCENE))

# ── Failure ───────────────────────────────────────────────────────────────

func _on_exposure_changed(value: float) -> void:
	_bus.sun_exposure_changed.emit(value)

func _on_burned_out() -> void:
	if not _running:
		return
	_running = false
	sensor.set_active(false)
	hud.set_controls_enabled(false)
	run_camera.focus_death(1.5)
	dracula.play_burn_death()

## Debug/test hook: ends the level as if Dracula burned.
func force_death() -> void:
	_on_burned_out()

func is_running() -> bool:
	return _running

## Dracula's death animation finished (it already emitted GameBus.player_died).
func _on_death_finished(cause: String) -> void:
	if _finished:
		return
	_finished = true
	set_physics_process(false)
	_game.game_over(cause)   # → GameBus.game_over(cause)
	_ui.push_packed(game_over_panel)
	var panel := _ui.current() as GameOverPanel
	if panel:
		panel.show_results(level.level_title, level.level_number, cause)
		panel.retry_requested.connect(_leave.bind(level.scene_file_path))
		panel.home_requested.connect(_leave.bind(HOME_SCENE))

# ── Pause ─────────────────────────────────────────────────────────────────

func request_pause() -> void:
	if not _running or _finished or _leaving or not _game.is_playing():
		return
	_game.pause()   # tree paused → all gameplay nodes stop processing
	_ui.push_packed(pause_panel)
	var panel := _ui.current() as PausePanel
	if panel:
		panel.home_requested.connect(_leave.bind(HOME_SCENE))

func _notification(what: int) -> void:
	# Auto-pause when the app goes to the background. Focus loss only counts on
	# mobile (notification shade, incoming call) so desktop testing isn't interrupted.
	if what == NOTIFICATION_APPLICATION_PAUSED:
		request_pause()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and PlatformUtils.is_mobile():
		request_pause()

# ── Leaving (Next / Retry / Home) ─────────────────────────────────────────

func _leave(scene_path: String) -> void:
	if _leaving:
		return
	_leaving = true
	if _game.state == GameManager.State.PAUSED:
		_game.resume()   # must unpause before changing scenes
	_game.reset()
	while _ui.stack_size() > 0:
		_ui.pop()
	_scene.go_to(scene_path)

func _exit_tree() -> void:
	# GameBus outlives this scene: drop our connections so Retry never leaks them.
	if _bus and _bus.game_started.is_connected(_on_game_started):
		_bus.game_started.disconnect(_on_game_started)
	if sun_rig:
		sun_rig.guard = Callable()
	if _game and _game.is_inside_tree() and _game.state == GameManager.State.PAUSED:
		_game.resume()
	dispose()

# ── Editor-only F6 fallback ───────────────────────────────────────────────

## Boots the composition root when a level is run on its own (F6).
## This is the ONLY place in gameplay code that touches ServiceRegistry / /root,
## and it never runs in exported builds or when launched through Boot → Home → Play.
func _editor_fallback_boot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame   # SceneManager injects one frame after a scene change
	var scene_root := get_tree().current_scene
	if _initialized or not is_inside_tree() or scene_root == null or not scene_root.is_ancestor_of(self):
		return
	var registry := get_tree().root.get_node_or_null("ServiceRegistry")
	if registry == null:
		return
	if not registry.has_service(&"game"):
		var services: Node = load("res://game/autoloads/GameService.gd").new()
		services.name = "GameService"
		get_tree().root.add_child(services)   # registers every service in _ready()
	var logger := registry.get_service(&"logger") as Node
	if logger:
		logger.warn("ShadowRunFeature: editor F6 fallback — booted GameService without Boot.tscn")
	for node in scene_root.find_children("*", "", true, false):
		if node.has_method("inject_services"):
			node.inject_services(registry)
	if scene_root.has_method("inject_services"):
		scene_root.inject_services(registry)
