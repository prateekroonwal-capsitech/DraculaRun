class_name DraculaController
extends PlayerController3D

## Dracula — moves only when told to: ShadowRunFeature hands him a path of world
## points (from ShadeGrid A*) and he walks it (runs if it is long), hopping over
## flagged sunlit gaps, turning smoothly toward his heading. He never decides on his
## own where to go. Burn feedback and the sunlight death (flare → ash and bats) are
## driven from the exposure meter by the feature.
## Visual parts live in Dracula.tscn / BurnFX.tscn / DeathFX.tscn (assigned via exports).
## The animated model is DraculaVisual.tscn (under Visual): each physics frame it gets his
## real ground speed and blends Idle / Walk / Run; turning is done here (turn_speed_degrees).

## Reached the last point of the current path.
signal arrived
## Emitted after the death animation completes. cause is "sunlight".
signal death_finished(cause: String)

enum State { IDLE, ACTIVE, DYING, DEAD }

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var run_speed: float = 8.0
## Paths longer than this (meters) are run instead of walked.
@export var run_threshold: float = 2.0
## Speed gained/lost per second (m/s²): snappy start, short brake into the last cell.
@export var acceleration: float = 45.0
## Seconds per hop, whatever its length (keeps hops quick at any speed).
@export var hop_time: float = 0.3
@export var hop_height: float = 0.55

@export_group("Turning")
## Max turn rate toward his path direction, degrees per second (no lean, no tilt).
@export var turn_speed_degrees: float = 720.0
## Direction changes bigger than this (degrees) are turned almost in place first,
## so he never runs sideways or swings wide.
@export_range(30.0, 180.0) var turn_in_place_angle: float = 100.0
## ...and he sets off again once he faces within this many degrees of the path.
@export_range(1.0, 90.0) var turn_in_place_release: float = 20.0
## He faces a point this far ahead along the path (m): smooths the 8-way grid zigzag
## and drag re-paths so his facing never jitters.
@export var facing_lookahead: float = 0.8
## Light smoothing of that facing target (1/s; higher = snappier).
@export var facing_smoothing: float = 14.0

@export_group("Scene parts")
## Heading, hop, flinch and death transforms are applied to this node.
@export var visual: Node3D
## The animated model (child of `visual`).
@export var body_visual: DraculaVisual
@export var smoke: CPUParticles3D
@export var embers: CPUParticles3D
@export var flare_light: OmniLight3D
@export var ash: CPUParticles3D
@export var bats: CPUParticles3D
## Foot-level footprint the ShadowSensor ray-casts from (matches ShadeGrid's
## ground-point rule, so "standing on a shaded cell" = "not burning").
@export var sample_points: Array[Node3D] = []
## dracula_rim.tres (material_overlay on the model); its burn `intensity` is animated.
@export var rim_material: ShaderMaterial

@export_group("Burn feedback")
@export var burn_rim_max: float = 2.4
@export var burn_light_max: float = 2.5
## Seconds between sizzle bursts while burning (AudioManager has pooled one-shots, no loop handle).
@export var sizzle_interval: float = 0.32
@export var burn_haptic_interval: float = 0.4

@export_group("Death animation")
@export var flare_time: float = 0.35
@export var flare_rim_intensity: float = 7.0
@export var flare_light_energy: float = 9.0
@export var disintegrate_time: float = 0.75
@export var ash_linger_time: float = 0.4

@export_group("Feel")
@export var no_cue_degrees: float = 22.0
@export var flinch_degrees: float = 14.0

@export_group("Audio")
@export var hop_sfx: AudioStream
@export var sizzle_sfx: AudioStream
@export var death_sting_sfx: AudioStream

var _haptics: HapticsManager
var _state: State = State.IDLE
var _points: PackedVector3Array = PackedVector3Array()
var _hops: Array[bool] = []
var _index: int = 0             # next point to reach
var _speed: float = 0.0          # cruise speed for the current path
var _cur_speed: float = 0.0      # actual speed (accelerates toward _speed)
var _seg_from: Vector3
var _seg_len: float = 0.0
var _seg_travel: float = 0.0
var _heading: float = 0.0
var _turning_in_place: bool = false
var _exposure: float = 0.0
var _exposure_rising: bool = false
var _sizzle_timer: float = 0.0
var _haptic_timer: float = 0.0
var _cue_tween: Tween

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_haptics = registry.get_service(&"haptics") as HapticsManager
	super.inject_services(registry)

## Explicit wiring for tests / runtime creation (HapticsManager is not in the base contract).
func inject_haptics(haptics: HapticsManager) -> void:
	_haptics = haptics

func _on_ready() -> void:
	# dracula_rim.tres is a shared resource that survives scene reloads: reset it.
	rim_material.set_shader_parameter("intensity", 0.0)
	flare_light.light_energy = 0.0

# ── Public API (called by ShadowRunFeature) ───────────────────────────────

func activate() -> void:
	if _state == State.IDLE:
		_state = State.ACTIVE

func is_active() -> bool:
	return _state == State.ACTIVE

func is_dead_or_dying() -> bool:
	return _state == State.DYING or _state == State.DEAD

func is_moving() -> bool:
	return _index < _points.size()

func get_sample_points() -> Array[Node3D]:
	return sample_points

## Places Dracula without animation (level start).
func place_at(world: Vector3, facing_radians: float = 0.0) -> void:
	global_position = world
	_heading = facing_radians
	visual.rotation.y = _heading
	_points.clear()
	_index = 0
	body_visual.reset_to_idle()

## Follow `points` (world positions, first = the first cell to step into).
## hops[i] = true makes the step into points[i] a hop. `run` forces run speed
## (drag-to-move); otherwise long paths run and short ones walk.
## Calling it while moving re-routes in place: speed and heading carry over, so
## frequent re-paths (drag-to-move) stay smooth.
func follow_path(points: PackedVector3Array, hops: Array[bool], run: bool = false) -> void:
	if _state != State.ACTIVE or points.is_empty():
		return
	var length := 0.0
	var prev := global_position
	for p in points:
		length += prev.distance_to(p)
		prev = p
	_speed = run_speed if run or length > run_threshold else walk_speed
	if not is_moving():
		_cur_speed = 0.0   # re-routes keep their momentum
	_points = points
	_hops = hops
	_index = 0
	_begin_segment()

## True while a hop is still ahead on the current path (or under way).
func has_pending_hop() -> bool:
	for i in range(_index, _hops.size()):
		if _hops[i]:
			return true
	return false

## Stop at the next waypoint (used when a sun drag starts mid-move).
func stop_at_next_waypoint() -> void:
	if is_moving():
		_points.resize(_index + 1)
		_hops.resize(_index + 1)

## Short head-shake: "can't go there".
func play_no_cue() -> void:
	var base := _heading
	var a := deg_to_rad(no_cue_degrees)
	_kick_cue(func(tw: Tween) -> void:
		tw.tween_property(visual, "rotation:y", base + a, 0.07)
		tw.tween_property(visual, "rotation:y", base - a, 0.12)
		tw.tween_property(visual, "rotation:y", base, 0.08))
	if _haptics:
		_haptics.light()

## Recoil from the sun (the guard refused a sun move).
func play_flinch() -> void:
	_kick_cue(func(tw: Tween) -> void:
		tw.tween_property(visual, "rotation:x", deg_to_rad(flinch_degrees), 0.06)
		tw.tween_property(visual, "rotation:x", 0.0, 0.18))
	if _haptics:
		_haptics.light()

## exposure 0..100, fraction = lit sample points / total this frame.
func set_burn_state(exposure: float, exposure_fraction: float) -> void:
	_exposure_rising = exposure_fraction > 0.0 and exposure > 0.5
	_exposure = exposure
	var k := clampf(exposure / 100.0, 0.0, 1.0)
	rim_material.set_shader_parameter("intensity", k * burn_rim_max)
	flare_light.light_energy = k * burn_light_max
	smoke.emitting = k > 0.04
	embers.emitting = k > 0.25
	# CPUParticles3D has no amount_ratio: scale intensity through the color multiplier
	# (multiplies the color ramp authored in BurnFX.tscn) and the emission speed.
	smoke.color = Color(1.0, 1.0, 1.0, clampf(0.3 + k, 0.0, 1.0))
	embers.color = Color(1.0, 1.0, 1.0, k)
	smoke.speed_scale = 0.6 + k

func play_burn_death() -> void:
	if is_dead_or_dying():
		return
	_state = State.DYING
	_points.clear()
	_index = 0
	body_visual.set_motion(0.0)
	if _haptics:
		_haptics.heavy()
	if _audio and death_sting_sfx:
		_audio.play_sfx(death_sting_sfx)
	smoke.emitting = true
	embers.emitting = true
	var tw := create_tween()
	# 1) flare bright
	tw.tween_method(func(v: float) -> void: rim_material.set_shader_parameter("intensity", v), burn_rim_max, flare_rim_intensity, flare_time)
	tw.parallel().tween_property(flare_light, "light_energy", flare_light_energy, flare_time)
	tw.parallel().tween_property(visual, "scale", Vector3.ONE * 1.12, flare_time)
	# 2) disintegrate into ash, embers and bats
	tw.tween_callback(func() -> void:
		ash.restart()
		bats.restart()
		smoke.emitting = false
	)
	tw.tween_property(visual, "scale", Vector3(0.05, 0.02, 0.05), disintegrate_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(flare_light, "light_energy", 0.0, disintegrate_time + 0.15)
	tw.tween_interval(ash_linger_time)
	tw.tween_callback(_finish_death.bind("sunlight"))

# ── Movement ──────────────────────────────────────────────────────────────

func _move(delta: float) -> void:
	velocity = Vector3.ZERO
	if _state != State.ACTIVE:
		return
	_update_burn_pulses(delta)
	var prev_pos := global_position
	_step_path(delta)
	# Animation: real ground speed (0 while turning in place → Idle; hops keep Run playing).
	var ground := Vector2(global_position.x - prev_pos.x, global_position.z - prev_pos.z).length() / maxf(delta, 0.0001)
	if is_moving() and _hops[_index] and _seg_travel > 0.0:
		ground = maxf(ground, run_speed)
	body_visual.set_motion(ground)

func _step_path(delta: float) -> void:
	if not is_moving():
		_turning_in_place = false
		visual.position.y = lerpf(visual.position.y, 0.0, minf(1.0, delta * 12.0))
		return
	var hopping: bool = _hops[_index]
	if _face_path(delta, hopping and _seg_travel > 0.0):
		_cur_speed = 0.0   # turning almost in place before setting off
		return
	# Accelerate toward cruise speed; brake so he arrives at the last point, not past it.
	var brake := sqrt(2.0 * acceleration * _remaining_distance())
	_cur_speed = minf(move_toward(_cur_speed, _speed, acceleration * delta), maxf(brake, 1.0))
	var speed := _seg_len / maxf(hop_time, 0.05) if hopping else _cur_speed
	_seg_travel = minf(_seg_travel + speed * delta, _seg_len)
	var t := _seg_travel / _seg_len if _seg_len > 0.0001 else 1.0
	var target := _points[_index]
	var flat := _seg_from.lerp(target, t)
	global_position = Vector3(flat.x, target.y, flat.z)
	visual.position.y = sin(t * PI) * hop_height if hopping else 0.0
	if t >= 1.0:
		_index += 1
		if is_moving():
			_begin_segment()
		else:
			_points.clear()
			_index = 0
			_cur_speed = 0.0
			arrived.emit()

## Turns toward the path direction at turn_speed_degrees. Returns true while he must hold
## still to turn (a change bigger than turn_in_place_angle; never in mid-hop).
func _face_path(delta: float, mid_hop: bool) -> bool:
	var desired := _path_heading()
	var err := absf(angle_difference(visual.rotation.y, desired))
	if not mid_hop and err > deg_to_rad(turn_in_place_angle):
		_turning_in_place = true
	if _turning_in_place and (mid_hop or err < deg_to_rad(turn_in_place_release)):
		_turning_in_place = false
	if _turning_in_place:
		_heading = desired
	else:
		_heading = lerp_angle(_heading, desired, 1.0 - exp(-facing_smoothing * delta))
	visual.rotation.y = rotate_toward(visual.rotation.y, _heading, deg_to_rad(turn_speed_degrees) * delta)
	return _turning_in_place

## Facing target: the point facing_lookahead metres ahead along the remaining path
## (never past a hop; during a hop, the landing point).
func _path_heading() -> float:
	var pos := global_position
	var look := _points[_index]
	if not _hops[_index]:
		var left := facing_lookahead
		var from := pos
		for i in range(_index, _points.size()):
			if i > _index and _hops[i]:
				break
			var p := _points[i]
			var dd := Vector2(p.x - from.x, p.z - from.z).length()
			if dd >= left:
				look = from.lerp(p, left / dd)
				break
			left -= dd
			from = p
			look = p
	var d := look - pos
	if Vector2(d.x, d.z).length() < 0.05:
		return _heading
	return atan2(-d.x, -d.z)

func _remaining_distance() -> float:
	var d := _seg_len - _seg_travel
	for i in range(_index + 1, _points.size()):
		d += _points[i - 1].distance_to(_points[i])
	return d

func _begin_segment() -> void:
	_seg_from = global_position
	_seg_len = _seg_from.distance_to(_points[_index])
	_seg_travel = 0.0
	if _hops[_index] and _audio and hop_sfx:
		_audio.play_sfx(hop_sfx, -4.0)

func _update_burn_pulses(delta: float) -> void:
	if not _exposure_rising:
		_sizzle_timer = 0.0
		_haptic_timer = 0.0
		return
	_sizzle_timer -= delta
	_haptic_timer -= delta
	if _sizzle_timer <= 0.0:
		_sizzle_timer = sizzle_interval
		if _audio and sizzle_sfx:
			_audio.play_sfx(sizzle_sfx, lerpf(-14.0, -2.0, _exposure / 100.0), randf_range(0.9, 1.15))
	if _haptic_timer <= 0.0:
		_haptic_timer = burn_haptic_interval
		if _haptics:
			_haptics.medium()

func _kick_cue(build: Callable) -> void:
	if _cue_tween and _cue_tween.is_valid():
		_cue_tween.kill()
	_cue_tween = create_tween()
	build.call(_cue_tween)

func _finish_death(cause: String) -> void:
	_state = State.DEAD
	die()
	death_finished.emit(cause)
