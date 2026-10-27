extends Node

## End-to-end test for the Shadow Run puzzle levels. Boots GameService (like Boot.tscn),
## loads Level01 through SceneManager and then:
##   1. Level 1: pause/resume, a real tap via handle_tap(), an unreachable tap (no move),
##      and the sun exposure guard (dragging toward an exposing angle must stop short
##      and Dracula must take no exposure).
##   2. Plays all levels by replaying LevelSolver's plan through the real game: moves go
##      through ShadowRunFeature.move_to (same path as a tap), sun steps through SunRig with
##      the drag start/end brackets SunControl uses. Each goal → Level Complete → Next.
##   3. Death → Retry `retries` times on Level01, checking node count / GameBus connections.
## Also checks the saved progression. Exit code 0 = everything passed.
##   godot --headless --path . res://game/scenes/test/ShadowRunSoakTest.tscn
## Test harness only: it is allowed to use ServiceRegistry.

const FIRST_LEVEL := "res://game/scenes/gameplay/shadow_run/levels/Level01.tscn"
const SOLVER := preload("res://game/scenes/gameplay/shadow_run/level/level_solver.tres")

@export var retries: int = 5
@export var level_count: int = 3
@export var node_tolerance: int = 4
@export var step_timeout: float = 25.0

var _registry: Node
var _logger: Node
var _failures: int = 0

func _ready() -> void:
	# The current scene is freed by every SceneManager.go_to(); run the driver from a
	# root-level node instead.
	if not has_meta("is_driver"):
		var driver := Node.new()
		driver.name = "SoakDriver"
		driver.set_meta("is_driver", true)
		driver.set_script(get_script())
		get_tree().root.add_child.call_deferred(driver)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _fail(msg: String) -> void:
	_failures += 1
	_logger.error("Soak: " + msg)

func _run() -> void:
	_registry = get_tree().root.get_node_or_null("ServiceRegistry")
	if not _registry.has_service(&"game"):
		var services: Node = load("res://game/autoloads/GameService.gd").new()
		services.name = "GameService"
		get_tree().root.add_child(services)
	_logger = _registry.get_service(&"logger") as Node
	var scene := _registry.get_service(&"scene") as SceneManager
	var ui := _registry.get_service(&"ui") as UIManager
	var bus: Node = _registry.get_service(&"bus")
	var save := _registry.get_service(&"save") as SaveManager
	Engine.time_scale = 3.0

	scene.go_to(FIRST_LEVEL)
	var prev_id := 0
	for li in level_count:
		var feature := await _wait_for_feature(prev_id)
		if feature == null:
			_fail("level %d never started" % (li + 1))
			break
		prev_id = feature.get_instance_id()
		if li == 0:
			await _check_basics(feature, ui)
		await _play_level(feature)
		var panel := await _wait_for_panel(ui, "LevelCompletePanel") as LevelCompletePanel
		if panel == null:
			_fail("Level Complete panel did not open on level %d" % (li + 1))
			break
		_logger.info("Soak: level %d complete" % (li + 1))
		panel.next_requested.emit()
	if save.get_level() < level_count + 1:
		_fail("progression not saved (current_level %d)" % save.get_level())

	# "Finish" on the last level returns Home: wait for that load, then check stability.
	while scene.is_loading() or not (get_tree().current_scene is HomeScene):
		await get_tree().process_frame
	# Death → Retry stability.
	scene.go_to(FIRST_LEVEL)
	var counts: PackedInt32Array = []
	for i in retries:
		var feature := await _wait_for_feature(prev_id)
		if feature == null:
			_fail("retry %d: level never started" % i)
			break
		prev_id = feature.get_instance_id()
		counts.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		feature.force_death()
		var panel := await _wait_for_panel(ui, "GameOverPanel") as GameOverPanel
		if panel == null:
			_fail("Game Over panel never opened")
			break
		panel.retry_requested.emit()
	if counts.size() >= 2 and absi(counts[counts.size() - 1] - counts[0]) > node_tolerance:
		_fail("node count drifted %s" % str(counts))
	if bus.game_started.get_connections().size() > 1:
		_fail("leaked GameBus.game_started connections")
	Engine.time_scale = 1.0
	if _failures == 0:
		_logger.info("Soak: PASS (levels played: %d, retry node counts %s)" % [level_count, str(counts)])
	else:
		_logger.error("Soak: FAIL (%d problem(s))" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

# ── Level 1 basics ────────────────────────────────────────────────────────

func _check_basics(f: ShadowRunFeature, ui: UIManager) -> void:
	# Pause / resume.
	f.request_pause()
	await get_tree().process_frame
	if not (ui.current() is PausePanel) or not get_tree().paused:
		_fail("pause panel did not open / tree not paused")
	else:
		(ui.current() as PausePanel)._on_resume_pressed()
		await get_tree().process_frame
	# Unreachable tap: the goal is in sun at the start angle → no move.
	f.move_to(f.level.goal.global_position)
	await _wait_still(f)
	if f.dracula.global_position.distance_to(f.level.start.global_position) > 0.6:
		_fail("unreachable tap moved Dracula")
	# Real tap through the input path: a walkable cell 2 m ahead, projected to the screen.
	var grid := f.level.grid
	var target := grid.nearest_walkable(grid.cell_at(f.dracula.global_position + Vector3(0.6, 0, -2.0)), 3)
	var cam := get_viewport().get_camera_3d()
	var screen := cam.unproject_position(grid.cell_center(target))
	if f.hud.is_in_play_view(screen):
		f.handle_tap(screen)
		await _wait_still(f)
		if f.dracula.global_position.distance_to(grid.cell_center(target)) > 0.35:
			_fail("tap on a walkable cell did not move Dracula there")
	else:
		_logger.info("Soak: tap check skipped (target not in play view in this viewport)")
	# Exposure guard: drag toward the far end; the sun must stop short, no exposure.
	var blocked := [false]
	var cb := func() -> void: blocked[0] = true
	f.sun_rig.guard_blocked.connect(cb)
	f._on_sun_drag_started()
	f.sun_rig.set_target(f.level.azimuth_max, f.sun_rig.target_elevation)
	await _wait_settled(f)
	f._on_sun_drag_ended()
	f.sun_rig.guard_blocked.disconnect(cb)
	if not blocked[0] or f.sun_rig.azimuth >= f.level.azimuth_max - 0.5:
		_fail("guard did not stop the sun (az %.1f)" % f.sun_rig.azimuth)
	if f.sensor.exposure > 0.5:
		_fail("Dracula took exposure while the guard was active (%.1f)" % f.sensor.exposure)
	_logger.info("Soak: guard stopped the sun at az %.1f, exposure %.1f" % [f.sun_rig.azimuth, f.sensor.exposure])
	# Back to the level's start angle (moving back toward safety is allowed).
	f._on_sun_drag_started()
	f.sun_rig.set_target(f.level.sun_start_azimuth, f.level.sun_start_elevation)
	await _wait_settled(f)
	f._on_sun_drag_ended()
	await _wait_still(f)

# ── Playthrough ───────────────────────────────────────────────────────────

func _play_level(f: ShadowRunFeature) -> void:
	var r := SOLVER.solve(f.level)
	if not r.solvable:
		_fail("level %d unsolvable in game: %s" % [f.level.level_number, r.error])
		return
	var peak := 0.0
	for step in r.plan:
		if step.type == "move":
			var cell: Vector2i = step.cell
			var dest := f.level.grid.cell_center(cell)
			f.move_to(dest)
			peak = maxf(peak, await _wait_still(f))
			if f._finished:
				break
			if f.dracula.global_position.distance_to(dest) > 0.35:
				_fail("level %d: could not walk to %s (stuck at %s)" % [f.level.level_number, str(cell), str(f.dracula.global_position)])
				return
		else:
			f._on_sun_drag_started()
			f.sun_rig.set_target(step.azimuth, step.elevation)
			await _wait_settled(f)
			f._on_sun_drag_ended()
			await _wait_still(f)
			if absf(f.sun_rig.azimuth - step.azimuth) > 0.5 or absf(f.sun_rig.elevation - step.elevation) > 0.5:
				_fail("level %d: guard stopped the planned sun move at %.1f/%.1f (wanted %.1f/%.1f)" % [
					f.level.level_number, f.sun_rig.azimuth, f.sun_rig.elevation, step.azimuth, step.elevation])
				return
	_logger.info("Soak: level %d played (%d plan steps, peak exposure %.1f)" % [f.level.level_number, (r.plan as Array).size(), peak])

## Waits until Dracula stops moving; returns the peak exposure seen meanwhile.
func _wait_still(f: ShadowRunFeature) -> float:
	var peak := 0.0
	var t := 0.0
	await get_tree().physics_frame
	while not f.is_idle() and t < step_timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		peak = maxf(peak, f.sensor.exposure)
	return peak

func _wait_settled(f: ShadowRunFeature) -> void:
	var t := 0.0
	await get_tree().physics_frame
	while not f.sun_rig.is_settled() and t < step_timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _wait_for_panel(ui: UIManager, cls: String) -> Control:
	var t := 0.0
	while t < step_timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
		var c := ui.current()
		if c and c.get_class() != "" and c.get_script() and (c.get_script() as Script).get_global_name() == cls:
			return c
	return null

## Waits for a NEW, running ShadowRunFeature (not the one from the scene being replaced).
func _wait_for_feature(previous_id: int) -> ShadowRunFeature:
	for _i in 900:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and cs is ShadowLevel:
			var f := cs.get_node_or_null("Game/ShadowRunFeature") as ShadowRunFeature
			if f and f.get_instance_id() != previous_id and f.is_running():
				return f
	return null
