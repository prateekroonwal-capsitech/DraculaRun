extends Node

## Villager stealth test on Level04, through the real game (Boot services,
## SceneManager, ShadowRunFeature):
##   1. Detection meter speed: in shade ≈ time_to_spot / shade_multiplier, in sun
##      ≈ time_to_spot / sun_multiplier (sun is faster).
##   2. Instant spot inside the lantern radius.
##   3. Hiding: a hidden Dracula in plain view is never noticed and takes no sun.
##   4. Escape: once chasing, hiding sends the villager to SEARCH, then RETURN → PATROL.
##   5. Caught: SUSPICIOUS → ALERT → CHASE → ATTACK → GameBus.game_over("caught") and the
##      Game Over panel says "CAUGHT!".
## The villager under test is made a stationary guard facing a chosen direction; the other
## one is switched off. Exit code 0 = pass.
##   godot --headless --path . res://game/scenes/test/VillagerStealthTest.tscn
## Test harness only: it is allowed to use ServiceRegistry and private members.

const LEVEL := "res://game/scenes/gameplay/shadow_run/levels/Level04.tscn"

## Allowed relative error on the measured fill times.
@export var tolerance: float = 0.2

var _logger: Node
var _failures: int = 0
var _game_over_reason: String = ""

func _ready() -> void:
	if not has_meta("is_driver"):
		var driver := Node.new()
		driver.name = "StealthDriver"
		driver.set_meta("is_driver", true)
		driver.set_script(get_script())
		get_tree().root.add_child.call_deferred(driver)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _fail(msg: String) -> void:
	_failures += 1
	_logger.error("Stealth: " + msg)

func _run() -> void:
	var registry := get_tree().root.get_node_or_null("ServiceRegistry")
	if not registry.has_service(&"game"):
		var services: Node = load("res://game/autoloads/GameService.gd").new()
		services.name = "GameService"
		get_tree().root.add_child(services)
	_logger = registry.get_service(&"logger") as Node
	var scene := registry.get_service(&"scene") as SceneManager
	var ui := registry.get_service(&"ui") as UIManager
	var bus: Node = registry.get_service(&"bus")
	bus.game_over.connect(func(reason: String) -> void: _game_over_reason = reason)
	scene.go_to(LEVEL)
	var f := await _wait_for_feature()
	if f == null:
		_fail("level never started")
		return _finish()
	var v := f.level.get_node("Villagers/VillagerRed") as VillagerController
	var other := f.level.get_node("Villagers/VillagerBlue") as VillagerController
	other.set_active(false)
	if f.villagers().size() != 2 or f.hide_spots().size() < 4:
		_fail("feature found %d villagers / %d hiding spots" % [f.villagers().size(), f.hide_spots().size()])
	var spot := f.level.get_node("Props/haystack_hide_1") as HideSpot
	var entry := spot.entry_position()
	# Guard post: 5 m from the haystack's entry, looking straight at it.
	var post := Vector3(0.0, 0.0, -19.0)
	var look := (entry - post) * Vector3(1, 0, 1)
	_make_guard(v, post, look.normalized())
	var in_view := post + look.normalized() * 3.5
	f.sensor.set_active(false)   # exposure_fraction is set by hand below

	# 1. Meter speed in shade and in sun.
	var t_shade := await _time_to_full(f, v, in_view, 0.0)
	var t_sun := await _time_to_full(f, v, in_view, 1.0)
	var exp_shade := v.time_to_spot / v.shade_multiplier
	var exp_sun := v.time_to_spot / v.sun_multiplier
	_logger.info("Stealth: meter full in shade %.2f s (expected %.2f), in sun %.2f s (expected %.2f)" % [t_shade, exp_shade, t_sun, exp_sun])
	if absf(t_shade - exp_shade) > exp_shade * tolerance + 0.1:
		_fail("shade fill time %.2f s, expected %.2f s" % [t_shade, exp_shade])
	if absf(t_sun - exp_sun) > exp_sun * tolerance + 0.1:
		_fail("sun fill time %.2f s, expected %.2f s" % [t_sun, exp_sun])
	if t_sun >= t_shade:
		_fail("sun is not faster than shade")

	# 2. Lantern: right beside the lantern, outside the cone → spotted at once.
	_reset(v, post, look.normalized())
	var lantern := v.lantern_attach.global_position
	var side := (lantern - post) * Vector3(1, 0, 1)
	var beside := post + side.normalized() * 0.9
	f.dracula.place_at(beside)
	await _physics_frames(2)
	_logger.info("Stealth: beside the lantern (%.2f m from it): meter %.2f, state %s" % [
		lantern.distance_to(beside + Vector3(0, v.target_height, 0)), v.meter_value, VillagerController.State.keys()[v.state]])
	if v.meter_value < 1.0:
		_fail("lantern did not spot him instantly (meter %.2f)" % v.meter_value)

	# 3. Hidden in plain view (inside the cone, 5 m away): never noticed, no sun.
	_reset(v, post, look.normalized())
	f.dracula.place_at(entry)
	f.go_hide(spot)
	await _physics_frames(5)
	if f.hidden_spot() != spot or not f.dracula.is_hidden() or not f.sensor.shielded:
		_fail("did not hide at the haystack")
	f.sensor.exposure_fraction = 1.0
	var peak := 0.0
	for _i in 120:
		await get_tree().physics_frame
		peak = maxf(peak, v.meter_value)
	_logger.info("Stealth: hidden in the cone for 2 s: peak meter %.2f, sensor sample %.2f" % [peak, f.sensor.sample()])
	if peak > 0.0:
		_fail("a hidden Dracula was noticed (meter %.2f)" % peak)
	if f.sensor.sample() != 0.0:
		_fail("a hidden Dracula is not shielded from the sun")

	# 4. Escape: spotted → chase → he hides → SEARCH → RETURN → PATROL.
	_reset(v, post, look.normalized())
	f.dracula.place_at(entry)   # leaves the spot: in view again
	f._leave_hide()
	var states: Array[String] = []
	var rec := func(_v: VillagerController, s: VillagerController.State) -> void: states.append(VillagerController.State.keys()[s])
	v.state_changed.connect(rec)
	f.sensor.exposure_fraction = 1.0
	await _wait_state(v, VillagerController.State.CHASE, 5.0)
	f.go_hide(spot)
	await _wait_state(v, VillagerController.State.PATROL, v.search_time + 15.0)
	v.state_changed.disconnect(rec)
	_logger.info("Stealth: escape states %s" % str(states))
	for need in ["ALERT", "CHASE", "SEARCH", "RETURN", "PATROL"]:
		if not states.has(need):
			_fail("escape: never reached %s (%s)" % [need, str(states)])

	# 5. Caught.
	_reset(v, post, look.normalized())
	f.dracula.place_at(in_view)
	f._leave_hide()
	states.clear()
	v.state_changed.connect(rec)
	f.sensor.exposure_fraction = 0.0
	var panel := await _wait_for_panel(ui, "GameOverPanel", 15.0) as GameOverPanel
	_logger.info("Stealth: caught states %s, game_over(%s)" % [str(states), _game_over_reason])
	if str(states.slice(0, 4)) != str(["SUSPICIOUS", "ALERT", "CHASE", "ATTACK"]):
		_fail("caught: unexpected state order %s" % str(states))
	if _game_over_reason != "caught":
		_fail("GameBus.game_over reason was '%s', expected 'caught'" % _game_over_reason)
	if panel == null:
		_fail("Game Over panel never opened")
	elif (panel.get_node("%Title") as Label).text != "CAUGHT!":
		_fail("Game Over title is '%s'" % (panel.get_node("%Title") as Label).text)
	_finish()

func _finish() -> void:
	if _failures == 0:
		_logger.info("Stealth: PASS")
	else:
		_logger.error("Stealth: FAIL (%d problem(s))" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

## Stationary guard at `pos` looking along `fwd`, meter empty, patrolling.
func _make_guard(v: VillagerController, pos: Vector3, fwd: Vector3) -> void:
	v.patrol_path = null
	v._points = PackedVector3Array()
	v._period = 0.0
	v._home_pos = pos
	v._home_basis = Basis(Vector3.UP, VillagerController._yaw_of(fwd))
	v.set_active(false)
	_reset(v, pos, fwd)
	v.set_active(true)

func _reset(v: VillagerController, pos: Vector3, fwd: Vector3) -> void:
	v.global_position = pos
	v.rotation.y = VillagerController._yaw_of(fwd)
	v.meter_value = 0.0
	v._resume_pos = pos
	v._set_state(VillagerController.State.PATROL)

## Seconds until the meter fills with Dracula at `where` and the given sun exposure.
func _time_to_full(f: ShadowRunFeature, v: VillagerController, where: Vector3, sun: float) -> float:
	_reset(v, v._home_pos, v._home_basis.z)
	f.dracula.place_at(where)
	f.sensor.exposure_fraction = sun
	var t := 0.0
	await get_tree().physics_frame
	while v.meter_value < 1.0 and t < 10.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	# Don't let it chase: put him out of view and calm the villager down.
	f.dracula.place_at(where + Vector3(0, 0, 30))
	return t

func _wait_state(v: VillagerController, s: VillagerController.State, timeout: float) -> void:
	var t := 0.0
	while v.state != s and t < timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _physics_frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

func _wait_for_panel(ui: UIManager, cls: String, timeout: float) -> Control:
	var t := 0.0
	while t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
		var c := ui.current()
		if c and c.get_script() and (c.get_script() as Script).get_global_name() == cls:
			return c
	return null

func _wait_for_feature() -> ShadowRunFeature:
	for _i in 1200:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and cs is ShadowLevel:
			var f := cs.get_node_or_null("Game/ShadowRunFeature") as ShadowRunFeature
			if f and f.is_running():
				return f
	return null
