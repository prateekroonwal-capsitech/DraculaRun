class_name RunCameraController
extends Camera3D

## RunCameraController — Angled follow camera for Shadow Run (portrait).
## Features:
##   1. Lower, closer default view (~45° pitch, KEEP_WIDTH aspect, framing Dracula in lower-middle).
##   2. Two-finger pinch to zoom & two-finger drag to pan across the level with auto-return.
##   3. Planning view: smoothly pulls back and up while adjusting the sun.
##   4. Level intro: frames the Goal, holds, then smoothly pans across to Dracula.
##   5. Occlusion fade: dynamically fades obstacles between camera and Dracula.

signal intro_finished

enum Mode {
	FOLLOW,
	MANUAL,
	PLANNING,
	INTRO,
	DEATH
}

@export_group("Framing & Follow")
## Camera height above the ground, meters.
@export var height: float = 9.5
## Distance behind the target along +Z, meters.
@export var distance: float = 5.2
## Downward pitch in degrees (40.0–50.0). Default 45.0.
@export_range(40.0, 50.0) var pitch_degrees: float = 45.0
## How much of the target's sideways offset (from center_x) the camera follows (0 = locked).
@export_range(0.0, 1.0) var lateral_follow: float = 0.35
## Lateral smoothing (higher = snappier) when lateral_follow > 0.
@export var lateral_smoothing: float = 8.0
## Forward smoothing.
@export var forward_smoothing: float = 14.0

@export_group("Pinch & Pan")
## Minimum zoom distance.
@export var min_distance: float = 3.5
## Maximum zoom distance.
@export var max_distance: float = 12.0
## Idle time before manual pan/zoom eases back to following Dracula (seconds).
@export var pan_idle_timeout: float = 2.0
## Time taken to smoothly ease back to following Dracula (seconds).
@export var return_to_follow_time: float = 0.5
## Screen-to-world pan speed multiplier.
@export var pan_speed: float = 0.014

@export_group("Planning View")
## Extra distance behind Dracula when pulling back for sun adjustment.
@export var planning_extra_distance: float = 3.5
## Extra height when pulling back for sun adjustment.
@export var planning_extra_height: float = 2.5
## Extra pitch in degrees when pulling back for sun adjustment.
@export var planning_extra_pitch: float = 6.0
## Ease time in/out of planning view (seconds).
@export var planning_ease_time: float = 0.4

@export_group("Level Intro")
## Time to hold camera on the Goal at level start (seconds).
@export var intro_hold_time: float = 0.6
## Time to smoothly pan from Goal to Dracula (seconds).
@export var intro_pan_time: float = 1.5
## Option to automatically skip intro after first play.
@export var skip_intro_after_first_play: bool = true

@export_group("Death cam")
@export var death_height: float = 6.0
@export var death_distance: float = 6.5
@export var death_pitch_degrees: float = 30.0

@export_group("Occlusion Fade")
## Enable fading occluding objects between camera and Dracula.
@export var enable_occlusion_fade: bool = true
## Target transparency for occluding objects (0 = opaque, 1 = transparent).
@export_range(0.0, 1.0) var occluded_transparency: float = 0.65

@export_group("Debug")
@export var debug_logs: bool = false

# ── State ──────────────────────────────────────────────────────────────────
var _target: Node3D = null
var _mode: Mode = Mode.FOLLOW
var _bounds: Rect2 = Rect2(-15.0, -80.0, 30.0, 100.0)

## Level centre line world X.
var center_x: float = 0.0

# Current active parameters
var _base_distance: float = 5.2
var _base_height: float = 9.5
var _base_pitch: float = 45.0

var _cur_distance: float = 5.2
var _cur_height: float = 9.5
var _cur_pitch: float = 45.0

# Focus point on the ground (XZ)
var _focus_pos: Vector3 = Vector3.ZERO
var _target_focus_pos: Vector3 = Vector3.ZERO

# Manual pan/zoom tracking
var _manual_idle_timer: float = 0.0
var _return_tween: Tween = null
var _planning_tween: Tween = null
var _intro_tween: Tween = null
var _is_planning_active: bool = false
var _intro_ended: bool = false
var _save_mgr: SaveManager = null
var _level_id: String = ""

# Shake state
var _shake_strength: float = 0.0
var _shake_time: float = 0.0

# Occlusion cache: Dictionary of [MeshInstance3D -> original_transparency: float]
var _faded_meshes: Dictionary = {}
var _ray_query: PhysicsRayQueryParameters3D = null

func _log(msg: String) -> void:
	if debug_logs or OS.is_debug_build():
		print("[CAM %dms] %s" % [Time.get_ticks_msec(), msg])

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	keep_aspect = Camera3D.KEEP_WIDTH
	fov = 40.0
	_base_distance = distance
	_base_height = height
	_base_pitch = pitch_degrees
	_cur_distance = distance
	_cur_height = height
	_cur_pitch = pitch_degrees
	_ray_query = PhysicsRayQueryParameters3D.new()
	# Mask 12: Layer 3 (obstacle, 4) | Layer 4 (shadow_caster, 8)
	_ray_query.collision_mask = 12
	set_physics_process(false)

# ── Level configuration ───────────────────────────────────────────────────

func apply_level_overrides(pitch: float, dist: float, h: float) -> void:
	if pitch > 0.0:
		pitch_degrees = pitch
	if dist > 0.0:
		distance = dist
	if h > 0.0:
		height = h
	_base_distance = distance
	_base_height = height
	_base_pitch = pitch_degrees
	_cur_distance = distance
	_cur_height = height
	_cur_pitch = pitch_degrees

func set_bounds(bounds: Rect2) -> void:
	_bounds = bounds

# ── Follow API ────────────────────────────────────────────────────

func follow(target: Node3D) -> void:
	_target = target
	var tp := target.global_position
	var target_x := center_x + (tp.x - center_x) * lateral_follow
	if _mode != Mode.INTRO and _mode != Mode.MANUAL:
		_focus_pos = Vector3(target_x, 0.0, tp.z)
	_apply()
	set_physics_process(true)

func stop_follow() -> void:
	_target = null
	_check_idle()

# ── Level Intro API ───────────────────────────────────────────────────────

func play_intro(goal_pos: Vector3, start_pos: Vector3, save_mgr: SaveManager = null, level_id: String = "") -> void:
	_save_mgr = save_mgr
	_level_id = level_id
	_intro_ended = false
	_log("play_intro: goal=%s start=%s level_id=%s" % [str(goal_pos), str(start_pos), level_id])

	if skip_intro_after_first_play and save_mgr != null and level_id != "":
		var seen_key := "intro_seen_level_" + level_id
		if save_mgr.get_custom_data(seen_key, false) == true:
			_log("intro already seen, skipping to Dracula")
			_mode = Mode.FOLLOW
			_focus_pos = Vector3(center_x, 0.0, start_pos.z)
			_apply()
			_intro_ended = true
			intro_finished.emit()
			return

	_mode = Mode.INTRO
	set_physics_process(true)

	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()

	# Start framing the Goal
	_focus_pos = Vector3(center_x, 0.0, goal_pos.z)
	_apply()

	# Safety watchdog timer: guarantees intro ends even if tween is interrupted or fails
	var timeout: float = intro_hold_time + intro_pan_time + 1.0
	get_tree().create_timer(timeout, false, false, true).timeout.connect(func() -> void:
		if _mode == Mode.INTRO and not _intro_ended:
			_log("intro safety watchdog timeout fired!")
			_end_intro()
	)

	_intro_tween = create_tween()
	_intro_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_intro_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_intro_tween.tween_interval(intro_hold_time)
	_intro_tween.tween_method(
		func(val: float) -> void:
			_focus_pos.z = val
			_apply(),
		goal_pos.z,
		start_pos.z,
		intro_pan_time
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	_intro_tween.finished.connect(_end_intro)

func skip_intro() -> void:
	if _mode != Mode.INTRO or _intro_ended:
		return
	_log("skip_intro called by player tap")
	_end_intro()

func _end_intro() -> void:
	if _intro_ended or _mode != Mode.INTRO:
		return
	_intro_ended = true
	_mode = Mode.FOLLOW
	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
		_intro_tween = null
	if _target:
		_focus_pos.z = _target.global_position.z
		_focus_pos.x = center_x + (_target.global_position.x - center_x) * lateral_follow
	_apply()
	if _save_mgr != null and _level_id != "":
		_save_mgr.set_custom_data("intro_seen_level_" + _level_id, true)
		_save_mgr.save_local()
	_log("intro finished -> FOLLOW")
	intro_finished.emit()

func is_intro_playing() -> bool:
	return _mode == Mode.INTRO and not _intro_ended

# ── Planning View API ─────────────────────────────────────────────────────

func set_planning_active(active: bool) -> void:
	if _mode == Mode.DEATH or _mode == Mode.INTRO:
		return
	_is_planning_active = active

	if _planning_tween and _planning_tween.is_valid():
		_planning_tween.kill()

	_planning_tween = create_tween().set_parallel(true)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)

	var target_dist := _base_distance + (planning_extra_distance if active else 0.0)
	var target_h := _base_height + (planning_extra_height if active else 0.0)
	var target_pitch := _base_pitch + (planning_extra_pitch if active else 0.0)

	_planning_tween.tween_property(self, "_cur_distance", target_dist, planning_ease_time)
	_planning_tween.tween_property(self, "_cur_height", target_h, planning_ease_time)
	_planning_tween.tween_property(self, "_cur_pitch", target_pitch, planning_ease_time)

	set_physics_process(true)

# ── Manual Pinch & Pan API ────────────────────────────────────────────────

func pan_by(delta_screen: Vector2) -> void:
	if _mode == Mode.DEATH or _mode == Mode.INTRO:
		return
	_mode = Mode.MANUAL
	_manual_idle_timer = pan_idle_timeout

	if _return_tween and _return_tween.is_valid():
		_return_tween.kill()
		_return_tween = null

	var sin_pitch := maxf(0.3, sin(deg_to_rad(_cur_pitch)))
	var dx := delta_screen.x * pan_speed * (_cur_height / 9.5)
	var dz := delta_screen.y * pan_speed * (_cur_height / 9.5) / sin_pitch

	_focus_pos.x = clampf(_focus_pos.x - dx, _bounds.position.x, _bounds.position.x + _bounds.size.x)
	_focus_pos.z = clampf(_focus_pos.z - dz, _bounds.position.y, _bounds.position.y + _bounds.size.y)
	_apply()
	set_physics_process(true)

func zoom_delta(delta: float) -> void:
	if _mode == Mode.DEATH or _mode == Mode.INTRO:
		return
	_base_distance = clampf(_base_distance + delta, min_distance, max_distance)
	_cur_distance = clampf(_cur_distance + delta, min_distance, max_distance)
	_manual_idle_timer = pan_idle_timeout
	_apply()
	set_physics_process(true)

func zoom_by(factor: float) -> void:
	if _mode == Mode.DEATH or _mode == Mode.INTRO or absf(factor - 1.0) < 0.001:
		return
	var new_dist := clampf(_base_distance * factor, min_distance, max_distance)
	var diff := new_dist - _base_distance
	zoom_delta(diff)

func notify_dracula_moving() -> void:
	if _mode == Mode.MANUAL:
		_ease_back_to_follow()

func _ease_back_to_follow() -> void:
	if _mode != Mode.MANUAL or _target == null:
		return
	_manual_idle_timer = 0.0
	if _return_tween and _return_tween.is_valid():
		return

	var target_x := center_x + (_target.global_position.x - center_x) * lateral_follow
	var target_z := _target.global_position.z

	_return_tween = create_tween().set_parallel(true)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)

	_return_tween.tween_property(self, "_focus_pos:x", target_x, return_to_follow_time)
	_return_tween.tween_property(self, "_focus_pos:z", target_z, return_to_follow_time)
	_return_tween.chain().tween_callback(func() -> void:
		_mode = Mode.FOLLOW
		_return_tween = null
	)

# ── Death cam & Shake ─────────────────────────────────────────────────────

func focus_death(duration: float = 1.5) -> void:
	_mode = Mode.DEATH
	var tw := create_tween().set_parallel(true)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_cur_height", death_height, duration)
	tw.tween_property(self, "_cur_distance", death_distance, duration)
	tw.tween_property(self, "_cur_pitch", death_pitch_degrees, duration)
	set_physics_process(true)

func shake(strength: float, duration: float) -> void:
	_shake_strength = strength
	_shake_time = duration
	set_physics_process(true)

# ── Physics Process & Occlusion ───────────────────────────────────────────

func _physics_process(delta: float) -> void:
	match _mode:
		Mode.FOLLOW:
			if _target:
				var tp := _target.global_position
				var tx := center_x + (tp.x - center_x) * lateral_follow
				_focus_pos.x = lerpf(_focus_pos.x, tx, minf(1.0, lateral_smoothing * delta))
				_focus_pos.z = lerpf(_focus_pos.z, tp.z, minf(1.0, forward_smoothing * delta))
				_apply()

		Mode.MANUAL:
			if _manual_idle_timer > 0.0:
				_manual_idle_timer -= delta
				if _manual_idle_timer <= 0.0:
					_ease_back_to_follow()
			_apply()

		Mode.INTRO:
			_apply()

		Mode.DEATH:
			_apply()

	# Shake decay
	if _shake_time > 0.0:
		h_offset = randf_range(-_shake_strength, _shake_strength)
		v_offset = randf_range(-_shake_strength, _shake_strength)
		_shake_time -= delta
	else:
		_shake_time = 0.0
		h_offset = 0.0
		v_offset = 0.0

	# Occlusion fade check
	if enable_occlusion_fade and _target:
		_update_occlusion_fade()

	_check_idle()

func _apply() -> void:
	global_position = Vector3(_focus_pos.x, _focus_pos.y + _cur_height, _focus_pos.z + _cur_distance)
	global_rotation = Vector3(deg_to_rad(-_cur_pitch), 0.0, 0.0)

func _update_occlusion_fade() -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return

	var start := global_position
	var end := _target.global_position + Vector3(0.0, 0.8, 0.0)
	_ray_query.from = start
	_ray_query.to = end

	var hit := space.intersect_ray(_ray_query)
	var active_mesh: MeshInstance3D = null

	if not hit.is_empty() and hit.collider != null:
		var col: Node = hit.collider
		active_mesh = _find_mesh_in(col)

	# Restore transparency on meshes no longer hit
	var to_remove: Array[MeshInstance3D] = []
	for mesh in _faded_meshes.keys():
		if mesh != active_mesh:
			if is_instance_valid(mesh):
				mesh.transparency = lerpf(mesh.transparency, _faded_meshes[mesh], 0.2)
				if absf(mesh.transparency - _faded_meshes[mesh]) < 0.05:
					mesh.transparency = _faded_meshes[mesh]
					to_remove.append(mesh)
			else:
				to_remove.append(mesh)

	for m in to_remove:
		_faded_meshes.erase(m)

	# Fade in occluding mesh
	if active_mesh != null and is_instance_valid(active_mesh):
		if not _faded_meshes.has(active_mesh):
			_faded_meshes[active_mesh] = active_mesh.transparency
		active_mesh.transparency = lerpf(active_mesh.transparency, occluded_transparency, 0.25)

func _find_mesh_in(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
	if node.get_parent():
		if node.get_parent() is MeshInstance3D:
			return node.get_parent() as MeshInstance3D
		for sib in node.get_parent().get_children():
			if sib is MeshInstance3D:
				return sib as MeshInstance3D
	return null

func _check_idle() -> void:
	if _target == null and _shake_time <= 0.0 and _mode == Mode.FOLLOW and not _is_planning_active:
		set_physics_process(false)
