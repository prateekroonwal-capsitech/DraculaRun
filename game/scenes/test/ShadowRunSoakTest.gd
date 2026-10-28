extends Node

## End-to-end test for the Shadow Run puzzle levels. Boots GameService (like Boot.tscn),
## loads Level01 through SceneManager and then:
##   1. Level 1: pause/resume, a real tap via handle_tap(), an unreachable tap (no move),
##      and the sun exposure guard (dragging toward an exposing angle must stop short
##      and Dracula must take no exposure).
##   2. Plays all levels TWICE — joystick mode, then slider mode (the mode is set through
##      SaveManager and must be picked up at level start) — replaying LevelSolver's plan
##      through the real controls: moves are taps on the projected screen point (move_to
##      when the cell is off screen); sun adjustments are joystick grabs steered through
##      the plan's waypoints (rate control, like a thumb) or slider drags to the mapped
##      finger position. After every step Dracula, the next target and the goal must not
##      sit under the active sun control. Each goal → Level Complete → Next.
##      Level 1 also checks the Pause-panel switch (instant swap + saved setting).
##      Run with `--resolution 1080x2400` / `1440x1920` to check other aspect ratios.
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
	_logger.info("Soak: saved sun control mode from the previous run: %s" % str(save.get_value(ShadowRunFeature.SUN_MODE_KEY, "(none)")))

	var prev_id := 0
	for mode: SunInput.Mode in [SunInput.Mode.JOYSTICK, SunInput.Mode.SLIDER]:
		save.set_value(ShadowRunFeature.SUN_MODE_KEY, SunInput.MODE_KEYS[mode])
		scene.go_to(FIRST_LEVEL)
		for li in level_count:
			var feature := await _wait_for_feature(prev_id)
			if feature == null:
				_fail("level %d never started" % (li + 1))
				break
			prev_id = feature.get_instance_id()
			if feature.get_sun_mode() != mode or not feature.hud.active_sun_input().is_visible_in_tree():
				_fail("level %d did not start in the saved %s mode" % [li + 1, SunInput.MODE_KEYS[mode]])
			if li == 0 and mode == SunInput.Mode.JOYSTICK:
				_logger.info("Soak: viewport %s" % str(get_viewport().get_visible_rect().size))
				await _check_basics(feature, ui)
				await _check_mode_switch(feature, ui, save)
				await _check_joystick(feature)
			await _play_level(feature)
			var panel := await _wait_for_panel(ui, "LevelCompletePanel") as LevelCompletePanel
			if panel == null:
				_fail("Level Complete panel did not open on level %d" % (li + 1))
				break
			_logger.info("Soak: level %d complete (%s mode)" % [li + 1, SunInput.MODE_KEYS[mode]])
			panel.next_requested.emit()
		# "Finish" on the last level returns Home: wait for that load.
		while scene.is_loading() or not (get_tree().current_scene is HomeScene):
			await get_tree().process_frame
	if save.get_level() < level_count + 1:
		_fail("progression not saved (current_level %d)" % save.get_level())
	# Leave the player's setting at the default.
	save.set_value(ShadowRunFeature.SUN_MODE_KEY, SunInput.MODE_KEYS[SunInput.Mode.JOYSTICK])
	save.save_game()
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
	# Let the last Retry finish loading so quitting never interrupts a scene load.
	await _wait_for_feature(prev_id)
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
	await _check_turning(f, target)
	await _check_drag(f, target)
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

# ── Turning and animation ─────────────────────────────────────────────────

## A target behind Dracula: he turns (almost) in place first and only sets off once he
## faces the path; Locomotion is past the Walk point while running and back to Idle (0)
## after arriving. Ends back on `home`.
func _check_turning(f: ShadowRunFeature, home: Vector2i) -> void:
	var grid := f.level.grid
	var d := f.dracula
	var tree := d.body_visual.animation_tree
	var region := grid.region_from(grid.cell_at(d.global_position))
	# Walkable cell 2–4 m behind him (toward +Z) in his region.
	var behind := Vector2i(-1, -1)
	for dist in [8, 7, 9, 6, 10, 5]:
		for dx in [0, 1, -1, 2, -2]:
			var c := grid.cell_at(d.global_position) + Vector2i(dx, -dist)
			if grid.in_bounds(c) and region[grid.index_of(c)] != 0 and grid.lit_neighbours(c) == 0:
				behind = c
				break
		if behind.x >= 0:
			break
	if behind.x < 0:
		_logger.info("Soak: turning check skipped (no shade behind Dracula)")
		return
	var start_pos := d.global_position
	f.move_to(grid.cell_center(behind))
	var set_off_err := -1.0
	var peak_blend := 0.0
	for _i in 240:
		await get_tree().physics_frame
		peak_blend = maxf(peak_blend, float(tree.get(&"parameters/Locomotion/blend_position")))
		if set_off_err < 0.0 and d.global_position.distance_to(start_pos) > 0.05:
			var to := grid.cell_center(behind) - start_pos
			set_off_err = rad_to_deg(absf(angle_difference(d.visual.rotation.y, atan2(-to.x, -to.z))))
		if not d.is_moving() and set_off_err >= 0.0:
			break
	await _wait_still(f)
	await _physics_frames(20)
	if set_off_err < 0.0 or set_off_err > d.turn_in_place_release + 25.0:
		_fail("turning: set off %.0f° away from the path (should turn first)" % set_off_err)
	if peak_blend < d.body_visual.walk_clip_speed:
		_fail("turning: Locomotion never reached Walk/Run while moving (peak %.2f)" % peak_blend)
	if float(tree.get(&"parameters/Locomotion/blend_position")) > 0.05:
		_fail("turning: not back to Idle after arriving")
	_logger.info("Soak: turning OK — turned to %.0f° off the path before setting off, Locomotion peak %.2f, Idle after" % [set_off_err, peak_blend])
	f.move_to(grid.cell_center(home))
	await _wait_still(f)

# ── Drag to move ──────────────────────────────────────────────────────────

## Drag checks on level 1, through the same press / move / release path a finger takes:
##   a) drag to connected shade → he follows and stops at the release point;
##   b) drag over sunlight → he waits at the shadow edge, never lit; release there → no move;
##   c) a sun drag mid move-drag pauses him; he resumes after it.
## Ends back on `home` so the solver replay starts where the tap check left him.
func _check_drag(f: ShadowRunFeature, home: Vector2i) -> void:
	var grid := f.level.grid
	var cam := get_viewport().get_camera_3d()
	var here := grid.cell_at(f.dracula.global_position)
	var region := grid.region_from(here)
	var labels := grid.walk_labels()
	var mine := labels[grid.index_of(here)]
	# Candidates within 1.5–4 m that are on screen: shaded+connected, and lit open ground.
	var shade := Vector2i(-1, -1)
	var lit := Vector2i(-1, -1)
	for dy in range(-18, 19):
		for dx in range(-18, 19):
			var c := here + Vector2i(dx, dy)
			var d := Vector2(dx, dy).length() * grid.cell_size
			if not grid.in_bounds(c) or d < 1.2 or d > 7.0:
				continue
			if not f.hud.is_in_play_view(cam.unproject_position(grid.cell_center(c))):
				continue
			if shade.x < 0 and labels[grid.index_of(c)] == mine and region[grid.index_of(c)] != 0 and grid.lit_neighbours(c) == 0:
				shade = c
			if lit.x < 0 and not grid.is_shaded(c) and not grid.is_solid(c):
				lit = c
	var screen := func(c: Vector2i) -> Vector2: return cam.unproject_position(grid.cell_center(c))
	# a) follow through shade
	if shade.x >= 0:
		f.begin_drag_at(screen.call(here))
		var mid := Vector2(screen.call(here)).lerp(screen.call(shade), 0.5)
		f.drag_to(mid)
		await _physics_frames(10)
		f.drag_to(screen.call(shade))
		await _physics_frames(20)
		if not f.is_move_dragging():
			_fail("drag: press-and-move did not start a drag")
		f.end_drag_at(screen.call(shade))
		var peak := await _wait_still(f)
		if f.dracula.global_position.distance_to(grid.cell_center(shade)) > 0.35:
			_fail("drag: he did not end at the release point %s" % str(shade))
		if peak > 0.5:
			_fail("drag: took exposure while following through shade (%.1f)" % peak)
	else:
		_logger.info("Soak: drag follow check skipped (no on-screen shade nearby)")
	# b) finger over sunlight: wait at the edge, never step into the sun
	if lit.x >= 0:
		here = grid.cell_at(f.dracula.global_position)
		f.begin_drag_at(screen.call(here))
		f.drag_to(screen.call(lit))
		var peak := 0.0
		for _i in 90:
			await get_tree().physics_frame
			peak = maxf(peak, f.sensor.exposure)
		# Cost of one re-path: edge-aware snap search + walking A* to the farthest cell of his shade.
		var from := grid.nearest_walkable(grid.cell_at(f.dracula.global_position), 1)
		var far := from
		for i in grid.cell_count():
			@warning_ignore("integer_division")
			var c := Vector2i(i % grid.cols, i / grid.cols)
			if labels[i] == labels[grid.index_of(from)] and Vector2(c - from).length() > Vector2(far - from).length():
				far = c
		var t0 := Time.get_ticks_usec()
		for _k in 10:
			grid.nearest_with_label(lit, labels, labels[grid.index_of(from)], f.edge_penalty)
			grid.find_path(from, far, false)
		_logger.info("Soak: drag re-path cost %.2f ms (snap + A* over %.1f m)" % [
			(Time.get_ticks_usec() - t0) / 10000.0, Vector2(far - from).length() * grid.cell_size])
		var at := grid.cell_at(f.dracula.global_position)
		if not grid.is_walkable(grid.nearest_walkable(at, 0)):
			_fail("drag: Dracula left the shade while the finger was over sunlight (%s)" % str(at))
		f.end_drag_at(screen.call(lit))
		peak = maxf(peak, await _wait_still(f))
		if peak > 0.5:
			_fail("drag: exposure %.1f while dragging over sunlight" % peak)
		if not grid.is_walkable(grid.nearest_walkable(grid.cell_at(f.dracula.global_position), 0)):
			_fail("drag: released over sunlight and he ended in the sun")
		_logger.info("Soak: drag over sunlight waited at %s (peak exposure %.1f)" % [str(grid.cell_at(f.dracula.global_position)), peak])
	else:
		_logger.info("Soak: drag sunlight check skipped (no on-screen lit ground nearby)")
	# c) sun drag during a move-drag: he pauses, then resumes toward the finger
	f.move_to(grid.cell_center(home))
	await _wait_still(f)
	if shade.x >= 0:
		f.begin_drag_at(screen.call(home))
		f.drag_to(screen.call(shade))
		await _physics_frames(3)
		f._on_sun_drag_started()
		await _physics_frames(30)
		if f.dracula.is_moving():
			_fail("drag: Dracula kept moving during a sun drag")
		var paused_at := f.dracula.global_position
		f._on_sun_drag_ended()
		await _physics_frames(40)
		if f.dracula.global_position.distance_to(paused_at) < 0.2 and paused_at.distance_to(grid.cell_center(shade)) > 0.35:
			_fail("drag: he did not resume following after the sun drag")
		f.end_drag_at(screen.call(shade))
		await _wait_still(f)
		if f.dracula.global_position.distance_to(grid.cell_center(shade)) > 0.35:
			_fail("drag: after a sun pause he did not reach the release point")
		f.move_to(grid.cell_center(home))
		await _wait_still(f)
	_logger.info("Soak: drag checks done")

func _physics_frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

# ── Playthrough ───────────────────────────────────────────────────────────

func _play_level(f: ShadowRunFeature) -> void:
	var r := SOLVER.solve(f.level)
	if not r.solvable:
		_fail("level %d unsolvable in game: %s" % [f.level.level_number, r.error])
		return
	var plan: Array = r.plan
	var peak := 0.0
	var taps := 0
	var i := 0
	await _check_overlap(f, plan, 0)
	while i < plan.size():
		var step: Dictionary = plan[i]
		if step.type == "move":
			var cell: Vector2i = step.cell
			var dest := f.level.grid.cell_center(cell)
			var screen := get_viewport().get_camera_3d().unproject_position(dest)
			if f.hud.is_in_play_view(screen) and f.level.grid.cell_at(f.ground_point(screen)) == cell:
				f.handle_tap(screen)
				taps += 1
			else:
				f.move_to(dest)
			peak = maxf(peak, await _wait_still(f))
			if f._finished:
				break
			if f.dracula.global_position.distance_to(dest) > 0.35:
				var g := f.level.grid
				var from := g.nearest_walkable(g.cell_at(f.dracula.global_position), 1)
				_fail("level %d: could not walk to %s (stuck at %s, cell %s / own cell %s shaded=%s; sun %.1f/%.1f settled=%s; grid busy=%s; exposure %.1f; target walkable=%s; path=%s)" % [
					f.level.level_number, str(cell), str(f.dracula.global_position), str(from),
					str(g.cell_at(f.dracula.global_position)), str(g.is_shaded(g.cell_at(f.dracula.global_position))),
					f.sun_rig.azimuth, f.sun_rig.elevation, str(f.sun_rig.is_settled()), str(g.is_busy()), f.sensor.exposure,
					str(g.is_walkable(cell)), str(not g.find_path(from, cell).is_empty())])
				return
			i += 1
		else:
			# One adjustment = one joystick grab through all consecutive sun waypoints.
			var waypoints: Array[Vector2] = []
			while i < plan.size() and plan[i].type == "sun":
				waypoints.append(Vector2(plan[i].azimuth, plan[i].elevation))
				i += 1
			var ok: bool = await _joystick_sun(f, waypoints) if f.get_sun_mode() == SunInput.Mode.JOYSTICK \
				else await _slider_sun(f, waypoints)
			if not ok:
				return
			await _wait_still(f)
		await _check_overlap(f, plan, i)
	_logger.info("Soak: level %d played with the %s (%d plan steps, %d taps, peak exposure %.1f)" % [
		f.level.level_number, SunInput.MODE_KEYS[f.get_sun_mode()], plan.size(), taps, peak])

## One dial grab per adjustment: put the finger on the sun knob, slide it to each
## waypoint's dial point (the dial is absolute: the sun goes where the finger points).
func _joystick_sun(f: ShadowRunFeature, waypoints: Array[Vector2]) -> bool:
	var js := f.hud.get_joystick()
	js.press_at(js.knob_center_global())
	if not js.is_dragging():
		_fail("dial grab failed")
		return false
	for w in waypoints:
		js.move_to(js.point_for_angles(w.x, w.y))
		await _wait_settled(f)
		if absf(f.sun_rig.azimuth - w.x) > 0.6 or absf(f.sun_rig.elevation - w.y) > 0.6:
			js.release()
			_fail("level %d: dial could not bring the sun to %.1f/%.1f (at %.1f/%.1f)" % [
				f.level.level_number, w.x, w.y, f.sun_rig.azimuth, f.sun_rig.elevation])
			return false
	js.release()
	await _wait_settled(f)
	return true

## Slider mode: one strip drag per waypoint, finger placed where the strip maps to it.
func _slider_sun(f: ShadowRunFeature, waypoints: Array[Vector2]) -> bool:
	var strip := f.hud.get_strip()
	for w in waypoints:
		var c := strip.get_global_rect().get_center()
		strip.press_at(c)
		if not strip.is_dragging():
			_fail("slider grab failed")
			return false
		strip.move_to(strip.finger_for(c, f.sun_rig.target_azimuth, f.sun_rig.target_elevation, w.x, w.y))
		await _wait_settled(f)
		strip.release()
		await _wait_settled(f)
		if absf(f.sun_rig.azimuth - w.x) > 1.0 or absf(f.sun_rig.elevation - w.y) > 1.0:
			_fail("level %d: slider could not bring the sun to %.1f/%.1f (at %.1f/%.1f)" % [
				f.level.level_number, w.x, w.y, f.sun_rig.azimuth, f.sun_rig.elevation])
			return false
	return true

## Pause panel switch: swaps the visible control instantly and saves the choice.
func _check_mode_switch(f: ShadowRunFeature, ui: UIManager, save: SaveManager) -> void:
	f.request_pause()
	await get_tree().process_frame
	var panel := ui.current() as PausePanel
	if panel == null:
		_fail("mode switch: pause panel did not open")
		return
	panel.choose_sun_mode(SunInput.Mode.SLIDER)
	await get_tree().process_frame
	if f.get_sun_mode() != SunInput.Mode.SLIDER or not f.hud.get_strip().is_visible_in_tree() or f.hud.get_joystick().is_visible_in_tree():
		_fail("mode switch: slider did not replace the joystick")
	if str(save.get_value(ShadowRunFeature.SUN_MODE_KEY, "")) != "slider":
		_fail("mode switch: choice not saved")
	panel.choose_sun_mode(SunInput.Mode.JOYSTICK)
	await get_tree().process_frame
	if f.get_sun_mode() != SunInput.Mode.JOYSTICK or not f.hud.get_joystick().is_visible_in_tree() or f.hud.get_strip().is_visible_in_tree():
		_fail("mode switch: joystick did not come back")
	panel._on_resume_pressed()
	await _physics_frames(30)   # camera re-frames for the joystick play view
	_logger.info("Soak: pause-panel sun control switch OK (saved as '%s')" % str(save.get_value(ShadowRunFeature.SUN_MODE_KEY, "")))

## Key gameplay points must never sit under the active sun control: Dracula, the next
## move target and the goal (whenever they are on screen). Waits for the camera to settle.
func _check_overlap(f: ShadowRunFeature, plan: Array, next_index: int) -> void:
	await _physics_frames(25)
	var js := f.hud.active_sun_input()
	var cam := get_viewport().get_camera_3d()
	var view := get_viewport().get_visible_rect()
	var points := {"Dracula": f.dracula.global_position, "goal": f.level.goal.global_position}
	for k in range(next_index, plan.size()):
		if plan[k].type == "move":
			points["next target"] = f.level.grid.cell_center(plan[k].cell)
			break
	for key in points:
		var wp: Vector3 = points[key]
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		if view.has_point(sp) and js.contains(sp):
			_fail("level %d: %s is under the sun %s (screen %s, viewport %s)" % [
				f.level.level_number, key, SunInput.MODE_KEYS[f.get_sun_mode()], str(sp.round()), str(view.size)])

## Sun dial (joystick mode) on level 1: the knob shows the real sun angle, the mapping
## hits the range limits at the ring's edges, dragging moves the sun and it stays, release
## keeps the target, keys move the knob, the guard stops the sun with the knob on the safe
## angle and the dim marker on the refused one. Ends back on the level's start angle.
func _check_joystick(f: ShadowRunFeature) -> void:
	var js := f.hud.get_joystick()
	var sun := f.sun_rig
	var near := func(a: Vector2, b: Vector2, tol: float) -> bool: return a.distance_to(b) <= tol
	if not near.call(js.knob_center_global(), js.point_for_angles(sun.azimuth, sun.elevation), 2.0):
		_fail("dial: knob is not on the sun's current angle")
	# Mapping round trip and range limits on the ring.
	var mid_el := (sun.elevation_min + sun.elevation_max) * 0.5
	var mid_az := (sun.azimuth_min + sun.azimuth_max) * 0.5
	for probe in [Vector2(-37.0, 22.0), Vector2(sun.azimuth_max, sun.elevation_max), Vector2(10.0, 58.0)]:
		var back: Vector2 = js._ring_to_angles(js._angles_to_ring(probe.x, probe.y))
		if back.distance_to(probe) > 0.05:
			_fail("dial: mapping round trip %s → %s" % [str(probe), str(back)])
	var r := js.ring.radius()
	if not near.call(js._angles_to_ring(sun.azimuth_min, mid_el), Vector2(-r, 0.0), 0.5) \
			or not near.call(js._angles_to_ring(mid_az, sun.elevation_max), Vector2(0.0, -r), 0.5):
		_fail("dial: range limits are not on the ring's left edge / top")
	# Drag: the sun goes where the finger points and stays after release; Dracula stays put.
	var before := f.dracula.global_position
	var start := Vector2(sun.azimuth, sun.elevation)
	var aim := Vector2(start.x - 12.0, start.y + 4.0)
	js.press_at(js.knob_center_global())
	js.move_to(js.point_for_angles(aim.x, aim.y))
	await _wait_settled(f)
	js.release()
	await _physics_frames(20)
	if not near.call(Vector2(sun.azimuth, sun.elevation), aim, 0.3):
		_fail("dial: sun at %.1f/%.1f, wanted %.1f/%.1f" % [sun.azimuth, sun.elevation, aim.x, aim.y])
	if not near.call(js.knob_center_global(), js.point_for_angles(aim.x, aim.y), 2.0):
		_fail("dial: knob did not stay on the new sun angle")
	if f.dracula.global_position.distance_to(before) > 0.05:
		_fail("dial: using the sun moved Dracula")
	if f.hud.is_in_play_view(js.knob_center_global()):
		_fail("dial area counts as play view (taps there would move Dracula)")
	# Release keeps the target: let go at once, the sun still arrives there.
	js.press_at(js.knob_center_global())
	js.move_to(js.point_for_angles(start.x, start.y))
	js.release()
	await _wait_settled(f)
	if not near.call(Vector2(sun.azimuth, sun.elevation), start, 0.3):
		_fail("dial: release did not keep the target (%.1f/%.1f)" % [sun.azimuth, sun.elevation])
	# Keys move the sun and the knob follows.
	var key := InputEventKey.new()   # Q = sun_left, as a real key press
	key.keycode = KEY_Q
	key.physical_keycode = KEY_Q
	key.pressed = true
	Input.parse_input_event(key)
	await _physics_frames(4)
	var key_up := key.duplicate() as InputEventKey
	key_up.pressed = false
	Input.parse_input_event(key_up)
	await _wait_settled(f)
	if sun.azimuth >= start.x - 0.5 or not near.call(js.knob_center_global(), js.point_for_angles(sun.azimuth, sun.elevation), 2.0):
		_fail("dial: Q key did not move the sun / knob (az %.1f)" % sun.azimuth)
	# Guard: aim where Dracula would be exposed; the sun stops short, the knob stays on the
	# safe angle, the dim marker shows the refused angle, the ring flashes.
	var blocked := [false]
	var cb := func() -> void: blocked[0] = true
	sun.guard_blocked.connect(cb)
	js.press_at(js.knob_center_global())
	js.move_to(js.point_for_angles(sun.azimuth_max, start.y))
	await _wait_settled(f)
	var marker_shown: bool = js.target_marker.visible
	var flash: float = js.blocked_rim.modulate.a
	js.release()
	sun.guard_blocked.disconnect(cb)
	if not blocked[0] or sun.azimuth >= sun.azimuth_max - 0.5:
		_fail("dial: guard did not stop the sun (az %.1f)" % sun.azimuth)
	if not marker_shown or not near.call(js.knob_center_global(), js.point_for_angles(sun.azimuth, sun.elevation), 2.0):
		_fail("dial: after a block the knob must sit on the safe angle and the marker on the refused one")
	if f.sensor.exposure > 0.5:
		_fail("dial: Dracula took exposure while the guard was active (%.1f)" % f.sensor.exposure)
	_logger.info("Soak: dial OK — guard stopped the sun at az %.1f (flash %.2f), knob on the sun, marker on the aim" % [sun.azimuth, flash])
	# Back to the level's start angle through the dial (moving back toward safety is allowed).
	js.press_at(js.knob_center_global())
	js.move_to(js.point_for_angles(f.level.sun_start_azimuth, f.level.sun_start_elevation))
	await _wait_settled(f)
	js.release()
	await _wait_still(f)

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
