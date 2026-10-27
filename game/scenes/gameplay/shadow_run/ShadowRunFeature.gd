class_name ShadowRunFeature
extends GameFeature

## ShadowRunFeature — one puzzle level's lifecycle. Core loop:
##   adjust the sun → shadows (and the ShadeGrid's walkable cells) change →
##   tap a shaded spot (or press and drag to lead him) → Dracula walks the A* path
##   → repeat until the goal.
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
## SaveManager key for the player's sun control choice ("joystick" / "slider").
const SUN_MODE_KEY := "sun_control_mode"

## The level root (set by each levels/LevelNN.tscn on its Game/ShadowRunFeature node).
@export var level: ShadowLevel
@export var dracula: DraculaController
@export var sun_rig: SunRig
@export var sensor: ShadowSensor
@export var run_camera: RunCameraController
@export var hud: ShadowRunHUD
@export var debug_overlay: ShadowDebugOverlay
## One yellow ring for both tap and drag moves (fx/MoveMarker.tscn).
@export var move_marker: MoveMarker
@export var level_complete_panel: PackedScene
@export var game_over_panel: PackedScene
@export var pause_panel: PackedScene

@export_group("Touch")
## A press in the play view becomes a DRAG once it moves more than this (viewport px,
## canvas is 1080 wide) or is held longer than drag_start_time; otherwise it is a TAP.
@export var drag_start_distance: float = 25.0
@export var drag_start_time: float = 0.15
## Path updates per second while dragging (only when the target cell changes).
@export var drag_repath_rate: float = 12.0
## The finger must stay over shade across a small sunlit gap this long before he hops.
@export var drag_hop_hold_time: float = 0.2
## Where he waits / stops: each lit neighbour of a cell costs this many cells of distance,
## so he stands a step inside the shadow rather than on its sunny edge (0 = off).
@export var edge_penalty: float = 2.0

@export_group("Sun control")
## Used until the player picks a mode in the Pause panel (then the saved choice wins).
@export var default_sun_mode: SunInput.Mode = SunInput.Mode.JOYSTICK
## Camera distance behind Dracula per mode, so he sits in the lower-middle of the
## visible play view (joystick: view runs to the bottom; slider: view ends above the strip).
@export var camera_distance_joystick: float = 3.6
@export var camera_distance_slider: float = 5.5

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
var _sun_dragging: bool = false
var _pending_tap: Variant = null
var _clock: float = 0.0
var _last_block_time: float = -10.0
var _sun_mode: SunInput.Mode = SunInput.Mode.JOYSTICK
# Move finger: the one touch (-1 = mouse) that started in the play view.
const NO_FINGER := -99
var _finger: int = NO_FINGER
var _finger_start: Vector2
var _finger_pos: Vector2
var _finger_time: float = 0.0
var _move_dragging: bool = false
var _drag_dest: Vector2i = Vector2i(-1, -1)
var _repath_wait: float = 0.0
var _hop_label: int = -1          # walk region the finger is held over across a gap
var _hop_since: float = 0.0
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
	if level == null:
		level = _find_ancestor_level()   # editor re-saves can drop the Game/ShadowRunFeature.level override
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

func _find_ancestor_level() -> ShadowLevel:
	var node := get_parent()
	while node:
		if node is ShadowLevel:
			return node as ShadowLevel
		node = node.get_parent()
	return null

# ── Setup ─────────────────────────────────────────────────────────────────

func _setup() -> void:
	var grid := level.grid
	sun_rig.configure(level.azimuth_min, level.azimuth_max, level.elevation_min, level.elevation_max,
		level.sun_start_azimuth, level.sun_start_elevation)
	dracula.place_at(level.start.global_position, level.start.global_rotation.y)
	_apply_sun_mode(_load_sun_mode())
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

func _physics_process(delta: float) -> void:
	if not _running:
		return
	_clock += delta
	dracula.set_burn_state(sensor.exposure, sensor.exposure_fraction)
	if _finger == NO_FINGER:
		return
	if not _move_dragging:
		if _clock - _finger_time >= drag_start_time:
			_begin_move_drag()
		return
	_repath_wait -= delta
	if _repath_wait <= 0.0:
		_repath_wait = 1.0 / maxf(1.0, drag_repath_rate)
		_drag_update()

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

func _load_sun_mode() -> SunInput.Mode:
	if _save == null:
		return default_sun_mode
	return SunInput.mode_from_key(str(_save.get_value(SUN_MODE_KEY, SunInput.MODE_KEYS[default_sun_mode])), default_sun_mode)

## Shows the chosen control, re-frames the camera for that play view.
func _apply_sun_mode(mode: SunInput.Mode) -> void:
	_sun_mode = mode
	hud.set_sun_mode(mode)
	run_camera.distance = camera_distance_joystick if mode == SunInput.Mode.JOYSTICK else camera_distance_slider

## Pause panel switch: apply now (visible on resume) and persist across levels / restarts.
func _on_sun_mode_chosen(mode: SunInput.Mode) -> void:
	if mode == _sun_mode:
		return
	_apply_sun_mode(mode)
	if _save:
		_save.set_value(SUN_MODE_KEY, SunInput.MODE_KEYS[mode])
		_save.save_game()
	if _logger:
		_logger.info("ShadowRun: sun control mode", {"mode": SunInput.MODE_KEYS[mode]})

func get_sun_mode() -> SunInput.Mode:
	return _sun_mode

func _on_guard_blocked() -> void:
	# A held joystick pushes into the guard every frame: flinch / flash at most every 0.4 s.
	if _clock - _last_block_time < 0.4:
		return
	_last_block_time = _clock
	dracula.play_flinch()
	hud.play_sun_blocked()

func _on_sun_drag_started() -> void:
	_sun_dragging = true
	dracula.stop_at_next_waypoint()   # he stands still while the sun moves

func _on_sun_drag_ended() -> void:
	_sun_dragging = false
	_drag_dest = Vector2i(-1, -1)     # a move-drag still held resumes once shade is exact
	if sun_rig.is_settled():
		_on_sun_settled()

# ── Tap / drag to move ────────────────────────────────────────────────────
# Touches that start on the sun joystick are consumed by SunJoystick in _input() and never
# arrive here, so the sun and Dracula never steal each other's touches. One finger
# leads Dracula; extra fingers in the play view are ignored.

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_run"):
		request_pause()
		get_viewport().set_input_as_handled()
		return
	if not _running or _finished:
		return
	# Ignore mouse<->touch emulation duplicates so one finger is one touch.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		_on_finger(st.index, st.position, st.pressed)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		_on_finger(-1, mb.position, mb.pressed)
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _finger:
		_on_finger_moved((event as InputEventScreenDrag).position)
	elif event is InputEventMouseMotion and _finger == -1:
		_on_finger_moved((event as InputEventMouseMotion).position)

func _on_finger(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if _finger != NO_FINGER or not hud.is_in_play_view(pos):
			return
		_finger = index
		_finger_start = pos
		_finger_pos = pos
		_finger_time = _clock
		_move_dragging = false
		get_viewport().set_input_as_handled()
		return
	if index != _finger:
		return
	_finger = NO_FINGER
	get_viewport().set_input_as_handled()
	if _move_dragging:
		_end_move_drag(pos)
	else:
		handle_tap(pos)

func _on_finger_moved(pos: Vector2) -> void:
	_finger_pos = pos
	if not _move_dragging and pos.distance_to(_finger_start) > drag_start_distance:
		_begin_move_drag()
	get_viewport().set_input_as_handled()

## A tap at a viewport position (public so tests can drive it).
func handle_tap(viewport_pos: Vector2) -> void:
	if _sun_dragging or not hud.is_in_play_view(viewport_pos):
		return
	var world: Variant = ground_point(viewport_pos)
	if world != null:
		move_to(world)

## Ground point under a viewport position, or null when the ray misses the ground plane.
func ground_point(viewport_pos: Vector2) -> Variant:
	var cam := get_viewport().get_camera_3d()
	var origin := cam.project_ray_origin(viewport_pos)
	var normal := cam.project_ray_normal(viewport_pos)
	if absf(normal.y) < 0.0001:
		return null
	var t := (level.grid.global_position.y - origin.y) / normal.y
	if t <= 0.0:
		return null
	return origin + normal * t

## Test hooks: the same press / move / release path a finger takes (mouse index).
func begin_drag_at(viewport_pos: Vector2) -> void:
	_on_finger(-1, viewport_pos, true)
	if _finger == -1:
		_begin_move_drag()

func drag_to(viewport_pos: Vector2) -> void:
	if _finger != NO_FINGER:
		_on_finger_moved(viewport_pos)

func end_drag_at(viewport_pos: Vector2) -> void:
	if _finger != NO_FINGER:
		_on_finger(_finger, viewport_pos, false)

func is_move_dragging() -> bool:
	return _move_dragging

func _begin_move_drag() -> void:
	_move_dragging = true
	_drag_dest = Vector2i(-1, -1)
	_hop_label = -1
	_repath_wait = 1.0 / maxf(1.0, drag_repath_rate)
	_drag_update()

## One drag re-path: lead Dracula toward the cell under the finger, staying in his
## connected shade. Over sun / walls / other shade he heads for the nearest cell of his
## own shade region and waits there; across a small gap he hops only after the finger
## has been held over the far shade for drag_hop_hold_time.
func _drag_update() -> void:
	if _sun_dragging or not sun_rig.is_settled() or level.grid.is_busy():
		return   # he stands still while the sun moves; shade must be exact
	if dracula.is_moving() and dracula.has_pending_hop():
		return   # never re-route mid-hop
	var world: Variant = ground_point(_finger_pos)
	if world == null:
		return
	var grid := level.grid
	var from := grid.nearest_walkable(grid.cell_at(dracula.global_position), 1)
	if not grid.in_bounds(from):
		return
	var labels := grid.walk_labels()
	var mine := labels[grid.index_of(from)]
	var target := grid.cell_at(world)
	var target_label := labels[grid.index_of(target)] if grid.in_bounds(target) else -1
	var dest := grid.nearest_with_label(target, labels, mine, edge_penalty)
	var snapped := target_label != mine
	var hop := false
	if snapped:
		var edge := grid.nearest_with_label(target, labels, mine)
		var gap := Vector2(edge - target).length() * grid.cell_size
		if target_label >= 0 and grid.in_bounds(edge) and gap <= grid.max_hop_distance + 0.001:
			if _hop_label != target_label:
				_hop_label = target_label
				_hop_since = _clock
			elif _clock - _hop_since >= drag_hop_hold_time:
				hop = true
		else:
			_hop_label = -1
	else:
		_hop_label = -1
	if hop:
		var landing := grid.nearest_with_label(target, labels, target_label, edge_penalty)
		if landing == _drag_dest or _walk_cells(from, landing, true, true):
			_drag_dest = landing
			move_marker.hold_at(grid.cell_center(landing))
			return
	if not grid.in_bounds(dest):
		return
	move_marker.hold_at(grid.cell_center(dest))   # where he is going, not under a sunlit finger
	if dest == _drag_dest:
		return
	_drag_dest = dest
	if dest == from and not dracula.is_moving():
		return
	_walk_cells(from, dest, false, true)

func _end_move_drag(viewport_pos: Vector2) -> void:
	_move_dragging = false
	var grid := level.grid
	var world: Variant = ground_point(viewport_pos) if hud.is_in_play_view(viewport_pos) else null
	if world == null:
		_settle_marker_on_drag_dest()
		dracula.play_no_cue()
		return
	if _sun_dragging or not sun_rig.is_settled() or grid.is_busy():
		move_marker.fade_out()
		_pending_tap = world   # answered (or refused) once the shade is exact
		return
	var target := grid.cell_at(world)
	var from := grid.nearest_walkable(grid.cell_at(dracula.global_position), 1)
	# Release over reachable shade = final destination (a short hop is fine: it was
	# deliberate), nudged off the sunny edge. Anything else: he finishes at the last
	# valid point and shakes his head.
	if grid.is_walkable(target) and grid.in_bounds(from):
		var labels := grid.walk_labels()
		var final := grid.nearest_with_label(target, labels, labels[grid.index_of(target)], edge_penalty)
		if final == _drag_dest or _walk_cells(from, final, true, true):
			_drag_dest = final
			move_marker.play_at(grid.cell_center(final), true)
			return
	# Invalid release: he finishes at the last valid point; the ring settles there.
	_settle_marker_on_drag_dest()
	dracula.play_no_cue()

func _settle_marker_on_drag_dest() -> void:
	if level.grid.in_bounds(_drag_dest):
		move_marker.play_at(level.grid.cell_center(_drag_dest), true)
	else:
		move_marker.fade_out()

func _cancel_move_drag() -> void:
	_finger = NO_FINGER
	if _move_dragging:
		_move_dragging = false
		move_marker.fade_out()

## A* from → to and hand the path to Dracula. Returns false when there is no route.
func _walk_cells(from: Vector2i, to: Vector2i, allow_hops: bool, run: bool) -> bool:
	var grid := level.grid
	var path := grid.find_path(from, to, allow_hops)
	if path.is_empty():
		return false
	var cells: Array[Vector2i] = path.cells
	var hops: Array[bool] = path.hops
	if cells.is_empty():
		cells = [to]
		hops = [false]
	_path_points = PackedVector3Array()
	for c in cells:
		_path_points.append(grid.cell_center(c))
	dracula.follow_path(_path_points, hops, run)
	return true

## Walk to a world point if a shaded route exists; otherwise show the "no" cue.
func move_to(world: Vector3) -> void:
	if not _running or _finished or _sun_dragging:
		return
	if not sun_rig.is_settled() or level.grid.is_busy():
		_pending_tap = world   # shade still updating: answer as soon as it is exact
		return
	var grid := level.grid
	var target := grid.cell_at(world)
	var from := grid.nearest_walkable(grid.cell_at(dracula.global_position), 1)
	if target == from and not dracula.is_moving():
		move_marker.play_at(grid.cell_center(target), true)
		return
	if not grid.in_bounds(from) or not grid.is_walkable(target) or not _walk_cells(from, target, true, false):
		move_marker.play_at(world, false)
		dracula.play_no_cue()
		return
	move_marker.play_at(grid.cell_center(target), true)

## True when nothing is pending: no finger down, Dracula still, no queued tap, sun at rest, shade exact.
func is_idle() -> bool:
	return _finger == NO_FINGER and not dracula.is_moving() and _pending_tap == null \
		and sun_rig.is_settled() and not level.grid.is_busy()

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
	_cancel_move_drag()
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
	_cancel_move_drag()
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
	_cancel_move_drag()   # the release would arrive while paused and be lost
	_game.pause()   # tree paused → all gameplay nodes stop processing
	_ui.push_packed(pause_panel)
	var panel := _ui.current() as PausePanel
	if panel:
		panel.home_requested.connect(_leave.bind(HOME_SCENE))
		panel.set_sun_mode(_sun_mode)
		panel.sun_mode_changed.connect(_on_sun_mode_chosen)

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
