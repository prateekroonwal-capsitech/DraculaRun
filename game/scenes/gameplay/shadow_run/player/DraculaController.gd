class_name DraculaController
extends PlayerController3D

## Dracula — auto-runs along −Z, switches between the lanes in LaneConfig, shows burn feedback
## and plays the two death animations. Run speed is driven by ShadowRunFeature;
## Dracula never decides on his own that he is dead — he reports obstacle hits
## and the feature orders the matching death animation.
## Every visual part lives in Dracula.tscn / BurnFX.tscn / DeathFX.tscn and is
## assigned through the exported references below; this script only animates them.

signal lane_committed(lane: int)
signal obstacle_hit(body: Node3D)
## Emitted after the death animation completes. cause is "sunlight" or "obstacle".
signal death_finished(cause: String)

enum RunState { IDLE, RUNNING, DYING, DEAD }

@export_group("Lanes")
## Lane count, width and start lane (track/lane_config.tres).
@export var lanes: LaneConfig
## Seconds for one lane slide.
@export var lane_switch_time: float = 0.12

@export_group("Swipe")
## Minimum horizontal travel, as a fraction of the viewport WIDTH, before a drag
## counts as a swipe (0.056 = ~60 px on a 1080-wide portrait screen).
@export_range(0.01, 0.2) var swipe_threshold_fraction: float = 0.056
## A drag is horizontal when |dx| >= |dy| * this ratio.
@export var swipe_horizontal_ratio: float = 1.2

@export_group("Scene parts")
@export var visual: Node3D
@export var hitbox: Area3D
@export var smoke: CPUParticles3D
@export var embers: CPUParticles3D
@export var flare_light: OmniLight3D
@export var ash: CPUParticles3D
@export var bats: CPUParticles3D
## Feet, torso, head — the points ShadowSensor ray-casts from.
@export var sample_points: Array[Node3D] = []
## burn_rim.tres (next_pass of the body/head materials); its intensity is animated.
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
@export var stumble_time: float = 0.35
@export var stumble_pitch_degrees: float = -80.0

@export_group("Feel")
@export var bob_height: float = 0.09
@export var bob_cycles_per_meter: float = 0.42
@export var lean_degrees: float = 9.0

@export_group("Audio")
@export var whoosh_sfx: AudioStream
@export var sizzle_sfx: AudioStream
@export var death_sting_sfx: AudioStream
@export var stumble_sfx: AudioStream

## Meters per second, set every physics frame by ShadowRunFeature.
var run_speed: float = 0.0

var _haptics: HapticsManager
var _state: RunState = RunState.IDLE
var _lane: int = 1
var _from_x: float = 0.0
var _to_x: float = 0.0
var _switch_elapsed: float = 0.0
var _switching: bool = false
var _queued_dir: int = 0
var _bob_phase: float = 0.0
var _exposure: float = 0.0
var _exposure_rising: bool = false
var _sizzle_timer: float = 0.0
var _haptic_timer: float = 0.0
# touch index (-1 for desktop mouse) -> drag anchor in screen space
var _swipe_anchors: Dictionary = {}

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_haptics = registry.get_service(&"haptics") as HapticsManager
	super.inject_services(registry)

## Explicit wiring for tests / runtime creation (HapticsManager is not in the base contract).
func inject_haptics(haptics: HapticsManager) -> void:
	_haptics = haptics

func _on_ready() -> void:
	# burn_rim.tres is a shared resource that survives scene reloads: reset it.
	rim_material.set_shader_parameter("intensity", 0.0)
	flare_light.light_energy = 0.0
	_lane = lanes.clamp_lane(lanes.start_lane)
	position.x = lanes.lane_x(_lane)
	_to_x = position.x
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	set_process_unhandled_input(true)

# ── Public API (called by ShadowRunFeature) ───────────────────────────────

func start_running() -> void:
	if _state == RunState.IDLE:
		_state = RunState.RUNNING

func is_running() -> bool:
	return _state == RunState.RUNNING

func is_dead_or_dying() -> bool:
	return _state == RunState.DYING or _state == RunState.DEAD

func get_lane() -> int:
	return _lane

func get_sample_points() -> Array[Node3D]:
	return sample_points

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

## Lane request from input (dir = -1 left, +1 right). Public so tests/bots can drive Dracula.
func request_lane_change(dir: int) -> void:
	if _state != RunState.RUNNING and _state != RunState.IDLE:
		return
	if _switching:
		_queued_dir = dir   # buffer exactly one extra move
		return
	_begin_switch(dir)

func play_burn_death() -> void:
	if is_dead_or_dying():
		return
	_enter_dying()
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

func play_obstacle_death() -> void:
	if is_dead_or_dying():
		return
	_enter_dying()
	if _haptics:
		_haptics.heavy()
	if _audio and stumble_sfx:
		_audio.play_sfx(stumble_sfx)
	var tw := create_tween()
	tw.tween_property(visual, "rotation:x", deg_to_rad(stumble_pitch_degrees), stumble_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(visual, "position:z", -0.5, stumble_time)
	tw.tween_property(visual, "position:y", 0.12, 0.12)
	tw.tween_property(visual, "position:y", 0.0, 0.12)
	tw.tween_interval(0.25)
	tw.tween_callback(_finish_death.bind("obstacle"))

# ── Movement ──────────────────────────────────────────────────────────────

func _move(delta: float) -> void:
	if _state != RunState.RUNNING:
		velocity = Vector3.ZERO
		return
	velocity = Vector3(0.0, 0.0, -run_speed)
	_update_lane_slide(delta)
	_update_bob(delta)
	_update_burn_pulses(delta)

func _begin_switch(dir: int) -> void:
	var target := lanes.clamp_lane(_lane + dir)
	if target == _lane:
		return   # swipe past the road edge: ignored, no slide, no feedback
	_lane = target
	_from_x = position.x
	_to_x = lanes.lane_x(_lane)
	_switch_elapsed = 0.0
	_switching = true
	# Registers immediately (same frame as the input); the slide is cosmetic.
	lane_committed.emit(_lane)
	if _haptics:
		_haptics.light()
	if _audio and whoosh_sfx:
		_audio.play_sfx(whoosh_sfx, -6.0, randf_range(0.92, 1.08))

func _update_lane_slide(delta: float) -> void:
	if not _switching:
		visual.rotation.z = lerpf(visual.rotation.z, 0.0, minf(1.0, delta * 14.0))
		return
	_switch_elapsed += delta
	var t := clampf(_switch_elapsed / lane_switch_time, 0.0, 1.0)
	position.x = lerpf(_from_x, _to_x, smoothstep(0.0, 1.0, t))
	visual.rotation.z = -signf(_to_x - _from_x) * deg_to_rad(lean_degrees) * sin(t * PI)
	if t >= 1.0:
		_switching = false
		if _queued_dir != 0:
			var dir := _queued_dir
			_queued_dir = 0
			_begin_switch(dir)

func _update_bob(delta: float) -> void:
	_bob_phase += delta * run_speed * bob_cycles_per_meter * TAU
	visual.position.y = absf(sin(_bob_phase)) * bob_height

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

func _enter_dying() -> void:
	_state = RunState.DYING
	_switching = false
	_queued_dir = 0
	velocity = Vector3.ZERO
	hitbox.set_deferred("monitoring", false)

func _finish_death(cause: String) -> void:
	_state = RunState.DEAD
	die()
	death_finished.emit(cause)

func _on_hitbox_body_entered(body: Node3D) -> void:
	if _state == RunState.RUNNING:
		obstacle_hit.emit(body)

# ── Input: keys + swipe (touch and desktop mouse) ─────────────────────────
# Touches that start inside the SunControl strip are consumed in its _input(),
# so everything that reaches _unhandled_input here is a swipe candidate.

func _unhandled_input(event: InputEvent) -> void:
	if _state != RunState.RUNNING:
		return
	if event.is_action_pressed("move_left", false, true):
		request_lane_change(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("move_right", false, true):
		request_lane_change(1)
		get_viewport().set_input_as_handled()
		return
	# Skip mouse<->touch emulation duplicates so one finger is never two swipes.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_swipe_anchors[st.index] = st.position
		else:
			_swipe_anchors.erase(st.index)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_track_swipe(sd.index, sd.position)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_swipe_anchors[-1] = mb.position
		else:
			_swipe_anchors.erase(-1)
	elif event is InputEventMouseMotion and _swipe_anchors.has(-1):
		_track_swipe(-1, (event as InputEventMouseMotion).position)

func _track_swipe(index: int, pos: Vector2) -> void:
	if not _swipe_anchors.has(index):
		return
	var anchor: Vector2 = _swipe_anchors[index]
	var d := pos - anchor
	var threshold := get_viewport().get_visible_rect().size.x * swipe_threshold_fraction
	if absf(d.x) >= threshold and absf(d.x) >= absf(d.y) * swipe_horizontal_ratio:
		request_lane_change(1 if d.x > 0.0 else -1)
		# Re-anchor so one long drag can switch two lanes without lifting the finger.
		_swipe_anchors[index] = pos
		get_viewport().set_input_as_handled()
