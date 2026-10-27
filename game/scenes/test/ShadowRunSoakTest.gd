extends Node

## Retry soak test for Shadow Run: boots GameService (like Boot.tscn would), then
## loads ShadowRun.tscn through SceneManager, pauses/resumes, dies and presses
## Retry `iterations` times, checking that the node count, GameBus connections
## and orphan nodes stay flat. Run headless:
##   godot --headless --path . res://game/scenes/test/ShadowRunSoakTest.tscn
## Exit code 0 = stable. Run WITHOUT --headless to also check two-touch arbitration
## (headless has no window, so injected touch positions are meaningless there).
## Test harness only: it is allowed to use ServiceRegistry.

const RUN_SCENE := "res://game/scenes/gameplay/shadow_run/ShadowRun.tscn"

@export var iterations: int = 10
@export var run_seconds: float = 2.0
## Allowed node-count drift between the first and the last iteration.
@export var node_tolerance: int = 4

var _registry: Node
var _logger: Node

func _ready() -> void:
	# The current scene is freed by every SceneManager.go_to(); run the driver from a
	# root-level node instead.
	var driver := Node.new()
	driver.name = "SoakDriver"
	driver.set_script(get_script())
	driver.set_meta("is_driver", true)
	if not has_meta("is_driver"):
		get_tree().root.add_child.call_deferred(driver)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

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
	var runs_before := save.stats_data.matches_played
	Engine.time_scale = 3.0
	var counts: PackedInt32Array = []
	var failures := 0

	scene.go_to(RUN_SCENE)
	var previous_id := 0
	for i in iterations:
		var feature := await _wait_for_feature(previous_id)
		if feature == null:
			_logger.error("Soak: ShadowRunFeature never appeared")
			get_tree().quit(1)
			return
		# Wait for the countdown to finish and the run to start.
		while not feature.is_running():
			await get_tree().process_frame
		previous_id = feature.get_instance_id()
		var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		counts.append(nodes)
		_logger.info("Soak %d: nodes %d  orphans %d  game_started conns %d  exposure conns %d" % [
			i, nodes, orphans, bus.game_started.get_connections().size(),
			bus.sun_exposure_changed.get_connections().size()])
		if i == 0:
			# Exercise pause → resume once.
			feature.request_pause()
			await get_tree().process_frame
			if not (ui.current() is PausePanel) or not get_tree().paused:
				_logger.error("Soak: pause panel did not open / tree not paused")
				failures += 1
			else:
				(ui.current() as PausePanel)._on_resume_pressed()
				await get_tree().process_frame
				if get_tree().paused:
					_logger.error("Soak: tree still paused after resume")
					failures += 1
			failures += await _check_two_touch(feature)
			failures += await _check_lane_edges(feature)
		await get_tree().create_timer(run_seconds).timeout
		feature.force_death("sunlight" if i % 2 == 0 else "obstacle")
		var panel: GameOverPanel = null
		var waited := 0.0
		while panel == null and waited < 6.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
			panel = ui.current() as GameOverPanel
		if panel == null:
			_logger.error("Soak: Game Over panel never opened")
			failures += 1
			break
		panel.retry_requested.emit()
		await get_tree().process_frame

	var runs_after := save.stats_data.matches_played
	if runs_after - runs_before != iterations:
		_logger.error("Soak: expected %d saved runs, got %d" % [iterations, runs_after - runs_before])
		failures += 1
	if counts.size() >= 2 and absi(counts[counts.size() - 1] - counts[1]) > node_tolerance:
		_logger.error("Soak: node count drifted %d -> %d" % [counts[1], counts[counts.size() - 1]])
		failures += 1
	if bus.game_started.get_connections().size() > 1:
		_logger.error("Soak: leaked GameBus.game_started connections")
		failures += 1
	_logger.info("Soak: best_distance=%s runs=%d" % [str(save.stats_data.custom.get("best_distance")), runs_after])
	if failures == 0:
		_logger.info("Soak: PASS (%d retries, node counts %s)" % [iterations, str(counts)])
	else:
		_logger.error("Soak: FAIL (%d problem(s))" % failures)
	Engine.time_scale = 1.0
	get_tree().quit(1 if failures > 0 else 0)

## Touch arbitration: finger 0 starts in the sun strip and drags right while finger 1
## swipes right in the play view. Expect: sun target moves right, Dracula moves
## exactly ONE lane (finger 0's long horizontal drag must not count as a swipe).
func _check_two_touch(feature: ShadowRunFeature) -> int:
	# Headless has a 0x0 window, so the stretch transform scrambles touch positions.
	# Run this soak in a window (no --headless) to exercise touch arbitration.
	if DisplayServer.get_name() == "headless":
		_logger.info("Soak: two-touch check SKIPPED (headless has no real window)")
		return 0
	var win := Vector2(DisplayServer.window_get_size())
	var lane_before := feature.dracula.get_lane()
	_touch(0, win * Vector2(0.5, 0.88), true)
	_touch(1, win * Vector2(0.3, 0.5), true)
	await get_tree().process_frame
	for k in 6:
		_drag(0, win * Vector2(0.5 + 0.06 * (k + 1), 0.86))
		_drag(1, win * Vector2(0.3 + 0.015 * (k + 1), 0.5))
		await get_tree().process_frame
	_touch(0, win * Vector2(0.86, 0.86), false)
	_touch(1, win * Vector2(0.39, 0.5), false)
	await get_tree().process_frame
	var problems := 0
	if feature.sun_rig.target_azimuth < 20.0:
		_logger.error("Soak: sun strip drag did not move the sun right (target az %.1f)" % feature.sun_rig.target_azimuth)
		problems += 1
	if feature.dracula.get_lane() != lane_before + 1:
		_logger.error("Soak: expected one lane change, got %d -> %d" % [lane_before, feature.dracula.get_lane()])
		problems += 1
	if problems == 0:
		_logger.info("Soak: two-touch OK (sun target az %.1f, lane %d -> %d)" % [feature.sun_rig.target_azimuth, lane_before, feature.dracula.get_lane()])
	return problems

## Edge cases: bursts of key presses past both road edges (one starts a slide, the
## rest hit the input buffer). Dracula must end on the outermost lane, exactly on its
## center, with no overshoot. Lane count/positions come from the scene's LaneConfig.
func _check_lane_edges(feature: ShadowRunFeature) -> int:
	var lanes := feature.dracula.lanes
	var problems := 0
	for dir in [-1, 1]:
		for _i in lanes.lane_count + 2:
			var e := InputEventAction.new()
			e.action = "move_left" if dir < 0 else "move_right"
			e.pressed = true
			Input.parse_input_event(e)
			await get_tree().create_timer(0.06).timeout
		await get_tree().create_timer(0.5).timeout
		var want := 0 if dir < 0 else lanes.lane_count - 1
		var lane := feature.dracula.get_lane()
		var x := feature.dracula.position.x
		if lane != want or absf(x - lanes.lane_x(want)) > 0.01:
			_logger.error("Soak: edge test dir %d ended in lane %d at x %.2f (want lane %d at x %.2f)" % [dir, lane, x, want, lanes.lane_x(want)])
			problems += 1
	if problems == 0:
		_logger.info("Soak: lane edges OK (%d lanes, clamped at 0 and %d)" % [lanes.lane_count, lanes.lane_count - 1])
	return problems

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)

func _drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	Input.parse_input_event(e)

## Waits for a NEW ShadowRunFeature (not the one from the scene being replaced).
func _wait_for_feature(previous_id: int) -> ShadowRunFeature:
	for _i in 600:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and cs.name == "ShadowRun":
			var f := cs.get_node_or_null("ShadowRunFeature") as ShadowRunFeature
			if f and f.is_inside_tree() and f.get_instance_id() != previous_id:
				return f
	return null
