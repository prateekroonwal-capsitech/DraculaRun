class_name RunCameraController
extends Camera3D

## RunCameraController — Angled follow camera for Shadow Run (portrait).
## Features:
##   1. Analytical screen-space follow: frames Dracula inside a guaranteed safe box.
##   2. Soft zone before hard clamp: raises follow speed smoothly as Dracula enters margin.
##   3. Safe box hard clamp: mathematical guarantee that Dracula never leaves screen in any direction.
##   4. Level bounds clamp with safe-box priority: respects level bounds unless Dracula would leave screen.
##   5. Two-finger pinch to zoom.
##   6. Planning view: smoothly pulls back and up while adjusting the sun.
##   7. Level intro: frames the Goal, holds, then smoothly pans across to Dracula.
##   8. Occlusion fade: dynamically fades obstacles between camera and Dracula.

signal intro_finished

enum Mode {
	FOLLOW,
	PLANNING,
	INTRO,
	DEATH
}

@export_group("Framing & Safe Box")
## Camera height above the ground, meters.
@export var height: float = 9.5
## Distance behind the target along +Z, meters.
@export var distance: float = 5.2
## Downward pitch in degrees (40.0–50.0). Default 45.0.
@export_range(40.0, 50.0) var pitch_degrees: float = 45.0
## Default screen-space anchor X fraction of play view (0.50 = center).
@export_range(0.0, 1.0) var base_anchor_x: float = 0.50
## Default screen-space anchor Y fraction of play view (0.60 = lower-middle, more view ahead).
@export_range(0.0, 1.0) var base_anchor_y: float = 0.60
## Safe box horizontal margin fraction of play view (default 0.15 = 15%).
@export_range(0.05, 0.30) var safe_box_margin_h: float = 0.15
## Safe box vertical margin fraction of play view (default 0.15 = 15%).
@export_range(0.05, 0.30) var safe_box_margin_v: float = 0.15
## Soft margin inside safe box (~8% of play view) for smooth follow speed boost.
@export_range(0.02, 0.15) var soft_zone_margin: float = 0.08

@export_group("Follow Speed & Smoothing")
## Base follow speed (1/s) when idling or walking.
@export var base_follow_speed: float = 8.0
## Follow speed (1/s) when Dracula is running.
@export var run_follow_speed: float = 14.0
## Maximum boosted follow speed (1/s) when Dracula penetrates deep into the soft zone.
@export var max_boosted_follow_speed: float = 36.0
## How much of target's sideways offset camera follows (1.0 = full lateral follow).
@export_range(0.0, 1.0) var lateral_follow: float = 1.0
## Deadzone in meters: movements smaller than this don't nudge the camera.
@export var follow_dead_zone: float = 0.04

@export_group("Screen-space Lookahead")
## Max screen-space lookahead offset fraction horizontally.
@export_range(0.0, 0.20) var lookahead_max_screen_x: float = 0.10
## Max screen-space lookahead offset fraction vertically.
@export_range(0.0, 0.20) var lookahead_max_screen_y: float = 0.10
## Smoothing speed for engaging / disengaging look-ahead (1/s).
@export var lookahead_smoothing: float = 4.0

@export_group("Level Bounds")
## Clamp camera to level bounds (rect in XZ plane). Safe box always wins!
@export var enable_level_bounds: bool = true

@export_group("Pinch & Zoom")
## Minimum zoom distance.
@export var min_distance: float = 3.5
## Maximum zoom distance.
@export var max_distance: float = 12.0

@export_group("Planning View")
## Enable camera pull-back planning view while adjusting the sun (disabled by default).
@export var enable_planning_view: bool = false
## Extra distance behind Dracula when pulling back for sun adjustment.
@export var planning_extra_distance: float = 0.0
## Extra height when pulling back for sun adjustment.
@export var planning_extra_height: float = 0.0
## Extra pitch in degrees when pulling back for sun adjustment.
@export var planning_extra_pitch: float = 0.0
## Ease time in/out of planning view (seconds).
@export var planning_ease_time: float = 0.4

@export_group("Level Intro")
## Time to hold camera on the Goal at level start (seconds).
@export var intro_hold_time: float = 0.6
## Time to smoothly pan from Goal to Dracula (seconds).
@export var intro_pan_time: float = 1.5
## Time to blend from current intro pose to start pose when player taps to skip (seconds).
@export var intro_skip_blend_time: float = 0.3

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

## Level centre line world X.
var center_x: float = 0.0
## Level bounding box in world XZ ground plane.
var level_bounds: Rect2 = Rect2()
## Optional reference to HUD for exact play view rect.
var hud: Node = null

# Current active parameters
var _base_distance: float = 5.2
var _base_height: float = 9.5
var _base_pitch: float = 45.0

var _cur_distance: float = 5.2
var _cur_height: float = 9.5
var _cur_pitch: float = 45.0

# Focus point on the ground (XZ)
var _focus_pos: Vector3 = Vector3.ZERO
var _cam_world_pos: Vector3 = Vector3.ZERO
var _cur_la_offset_x: float = 0.0
var _cur_la_offset_y: float = 0.0
var _prev_target_pos: Vector3 = Vector3.ZERO

# Debug metrics exposed for overlays / tests
var debug_screen_pos: Vector2 = Vector2.ZERO
var debug_screen_pct: Vector2 = Vector2.ZERO
var debug_soft_depth: float = 0.0
var debug_hard_clamp: bool = false
var debug_effective_speed: float = 0.0
var debug_safe_rect: Rect2 = Rect2()
var debug_soft_rect: Rect2 = Rect2()
var debug_target_anchor: Vector2 = Vector2.ZERO

# Tween tracking
var _planning_tween: Tween = null
var _intro_tween: Tween = null
var _is_planning_active: bool = false
var _intro_ended: bool = false
var _is_skipping_intro: bool = false
var _start_pose: Dictionary = {}
var _goal_pose: Dictionary = {}
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
	process_priority = 100 # Late update: runs after Dracula and scene updates
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
	set_process(true)
	set_physics_process(false)

func _exit_tree() -> void:
	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
		_intro_tween = null
	if _planning_tween and _planning_tween.is_valid():
		_planning_tween.kill()
		_planning_tween = null

# ── Screen & Projection Math ───────────────────────────────────────────────

func get_play_view_rect() -> Rect2:
	if hud != null and is_instance_valid(hud) and hud.has_method("get_play_view_rect"):
		var r: Rect2 = hud.get_play_view_rect()
		if r.size.x > 0.0 and r.size.y > 0.0:
			return r
	var vp := get_viewport()
	if vp:
		return vp.get_visible_rect()
	return Rect2(0.0, 0.0, 1080.0, 1920.0)

## Closed-form inverse camera placement: computes exact camera 3D position
## placing a world point on the ground (y=0) at screen pixel coordinate (target_sx, target_sy).
func camera_pos_for_screen_target(drac_pos: Vector3, target_sx: float, target_sy: float, cam_height: float, pitch_r: float) -> Vector3:
	var vp_rect := get_viewport().get_visible_rect()
	var vp_w := vp_rect.size.x
	var vp_h := vp_rect.size.y
	if vp_w <= 0.0 or vp_h <= 0.0:
		vp_w = 1080.0
		vp_h = 1920.0

	var aspect_ratio := vp_w / vp_h
	var hfov_rad := deg_to_rad(fov)
	var vfov_rad := 2.0 * atan(tan(hfov_rad * 0.5) / aspect_ratio)

	var tan_h := tan(hfov_rad * 0.5)
	var tan_v := tan(vfov_rad * 0.5)

	var cos_t := cos(pitch_r)
	var sin_t := sin(pitch_r)

	var ndc_x := (2.0 * target_sx - vp_w) / vp_w
	var ndc_y := (vp_h - 2.0 * target_sy) / vp_h

	var kx := ndc_x * tan_h
	var ky := ndc_y * tan_v

	var denom := sin_t - ky * cos_t
	if absf(denom) < 0.0001:
		denom = 0.0001

	var delta_z := -cam_height * (cos_t + ky * sin_t) / denom
	var z_depth := cam_height * sin_t - delta_z * cos_t

	var cam_x := drac_pos.x - kx * z_depth
	var cam_z := drac_pos.z - delta_z
	var cam_y := cam_height

	return Vector3(cam_x, cam_y, cam_z)

## Projects a 3D ground point to screen viewport pixels given camera position and pitch.
func project_to_screen(cam_pos: Vector3, point_3d: Vector3, pitch_r: float) -> Vector2:
	var vp_rect := get_viewport().get_visible_rect()
	var vp_w := vp_rect.size.x
	var vp_h := vp_rect.size.y
	if vp_w <= 0.0 or vp_h <= 0.0:
		vp_w = 1080.0
		vp_h = 1920.0

	var aspect_ratio := vp_w / vp_h
	var hfov_rad := deg_to_rad(fov)
	var vfov_rad := 2.0 * atan(tan(hfov_rad * 0.5) / aspect_ratio)

	var tan_h := tan(hfov_rad * 0.5)
	var tan_v := tan(vfov_rad * 0.5)

	var cos_t := cos(pitch_r)
	var sin_t := sin(pitch_r)

	var rel := point_3d - cam_pos
	var vx := rel.x
	var vy := rel.y * cos_t - rel.z * sin_t
	var vz := rel.y * sin_t + rel.z * cos_t
	var z_depth := -vz
	if z_depth <= 0.001:
		return Vector2(-9999.0, -9999.0)

	var ndc_x := (vx / z_depth) / tan_h
	var ndc_y := (vy / z_depth) / tan_v

	var sx := (ndc_x + 1.0) * 0.5 * vp_w
	var sy := (1.0 - ndc_y) * 0.5 * vp_h
	return Vector2(sx, sy)

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

# ── Gameplay Pose Calculation ──────────────────────────────────────────────

## Computes the exact camera pose that frames target_pos in gameplay mode
## (taking into account screen-space anchor, safe box, soft zone, lateral follow, and level bounds).
func get_gameplay_start_pose(target_pos: Vector3) -> Dictionary:
	var play_rect := get_play_view_rect()
	var S_min_x := play_rect.position.x + play_rect.size.x * safe_box_margin_h
	var S_max_x := play_rect.end.x - play_rect.size.x * safe_box_margin_h
	var S_min_y := play_rect.position.y + play_rect.size.y * safe_box_margin_v
	var S_max_y := play_rect.end.y - play_rect.size.y * safe_box_margin_v

	var soft_w := play_rect.size.x * soft_zone_margin
	var soft_h := play_rect.size.y * soft_zone_margin
	var Z_min_x := S_min_x + soft_w
	var Z_max_x := S_max_x - soft_w
	var Z_min_y := S_min_y + soft_h
	var Z_max_y := S_max_y - soft_h

	var target_anchor_x := clampf(play_rect.position.x + play_rect.size.x * base_anchor_x, Z_min_x, Z_max_x)
	var target_anchor_y := clampf(play_rect.position.y + play_rect.size.y * base_anchor_y, Z_min_y, Z_max_y)

	var pitch_r := deg_to_rad(_cur_pitch)
	var cam_pos := camera_pos_for_screen_target(target_pos, target_anchor_x, target_anchor_y, _cur_height, pitch_r)

	if lateral_follow < 0.99:
		var center_cam := camera_pos_for_screen_target(Vector3(center_x, 0.0, target_pos.z), target_anchor_x, target_anchor_y, _cur_height, pitch_r)
		cam_pos.x = lerpf(center_cam.x, cam_pos.x, lateral_follow)

	if enable_level_bounds and level_bounds.size.x > 0.0 and level_bounds.size.y > 0.0:
		cam_pos.x = clampf(cam_pos.x, level_bounds.position.x, level_bounds.end.x)
		cam_pos.z = clampf(cam_pos.z, level_bounds.position.y + _cur_distance, level_bounds.end.y + _cur_distance)

	# Safe box ALWAYS wins!
	var proj_screen := project_to_screen(cam_pos, target_pos, pitch_r)
	var clamped_sx := clampf(proj_screen.x, S_min_x, S_max_x)
	var clamped_sy := clampf(proj_screen.y, S_min_y, S_max_y)
	if absf(clamped_sx - proj_screen.x) > 0.01 or absf(clamped_sy - proj_screen.y) > 0.01:
		var req_cam := camera_pos_for_screen_target(target_pos, clamped_sx, clamped_sy, _cur_height, pitch_r)
		cam_pos.x = req_cam.x
		cam_pos.z = req_cam.z

	cam_pos.y = _cur_height
	var focus := Vector3(cam_pos.x, 0.0, cam_pos.z - _cur_distance)
	var rot := Vector3(-pitch_r, 0.0, 0.0)

	return {
		"position": cam_pos,
		"rotation": rot,
		"distance": _cur_distance,
		"pitch": _cur_pitch,
		"height": _cur_height,
		"focus_pos": focus,
		"anchor": Vector2(target_anchor_x, target_anchor_y)
	}

func _apply_intro_step(pos: Vector3, pitch: float, dist: float, h: float) -> void:
	_cam_world_pos = pos
	_cur_pitch = pitch
	_cur_distance = dist
	_cur_height = h
	_focus_pos.x = pos.x
	_focus_pos.y = 0.0
	_focus_pos.z = pos.z - dist
	_apply()

# ── Follow API ────────────────────────────────────────────────────

func follow(target: Node3D) -> void:
	_target = target
	var tp: Vector3 = _get_target_pos()
	_prev_target_pos = tp
	var pose: Dictionary = get_gameplay_start_pose(tp)
	_start_pose = pose
	var s_pos: Vector3 = pose.get("position", _cam_world_pos)
	var s_pitch: float = pose.get("pitch", _cur_pitch)
	var s_dist: float = pose.get("distance", _cur_distance)
	var s_h: float = pose.get("height", _cur_height)
	_apply_intro_step(s_pos, s_pitch, s_dist, s_h)
	_cur_la_offset_x = 0.0
	_cur_la_offset_y = 0.0
	set_process(true)

func stop_follow() -> void:
	_target = null
	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
		_intro_tween = null
	_check_idle()

func _get_target_pos() -> Vector3:
	if _target == null:
		return Vector3.ZERO
	# Use physics-interpolated global transform origin for smooth 60/120Hz tracking
	return _target.get_global_transform_interpolated().origin

# ── Level Intro API ───────────────────────────────────────────────────────

func play_intro(goal_pos: Vector3, start_pos: Vector3, save_mgr: SaveManager = null, level_id: String = "") -> void:
	_save_mgr = save_mgr
	_level_id = level_id
	_intro_ended = false
	_is_skipping_intro = false
	_log("play_intro: goal=%s start=%s level_id=%s" % [str(goal_pos), str(start_pos), level_id])

	_mode = Mode.INTRO
	set_process(true)

	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()

	var actual_start_pos := start_pos
	if _target != null and is_instance_valid(_target):
		actual_start_pos = _get_target_pos()

	_start_pose = get_gameplay_start_pose(actual_start_pos)
	_goal_pose = get_gameplay_start_pose(goal_pos)

	# Frame the Goal at the start of the intro
	var g_pos: Vector3 = _goal_pose.get("position", Vector3.ZERO)
	var g_pitch: float = _goal_pose.get("pitch", _cur_pitch)
	var g_dist: float = _goal_pose.get("distance", _cur_distance)
	var g_h: float = _goal_pose.get("height", _cur_height)
	_apply_intro_step(g_pos, g_pitch, g_dist, g_h)

	# Safety watchdog timer: guarantees intro will finish even if tweens fail or stall
	var timeout: float = intro_hold_time + intro_pan_time + intro_skip_blend_time + 1.5
	get_tree().create_timer(timeout, false, false, true).timeout.connect(func() -> void:
		if _mode == Mode.INTRO and not _intro_ended:
			_log("intro safety watchdog timeout fired!")
			_end_intro()
	)

	var s_pos: Vector3 = _start_pose.get("position", Vector3.ZERO)
	var s_pitch: float = _start_pose.get("pitch", _cur_pitch)
	var s_dist: float = _start_pose.get("distance", _cur_distance)
	var s_h: float = _start_pose.get("height", _cur_height)

	_intro_tween = create_tween()
	_intro_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if intro_hold_time > 0.0:
		_intro_tween.tween_interval(intro_hold_time)

	var pan_dur: float = maxf(intro_pan_time, 0.05)
	_intro_tween.tween_method(
		func(t: float) -> void:
			var p: Vector3 = g_pos.lerp(s_pos, t)
			var pitch: float = lerpf(g_pitch, s_pitch, t)
			var dist: float = lerpf(g_dist, s_dist, t)
			var h: float = lerpf(g_h, s_h, t)
			_apply_intro_step(p, pitch, dist, h),
		0.0,
		1.0,
		pan_dur
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	_intro_tween.finished.connect(_end_intro)

func skip_intro() -> void:
	if _mode != Mode.INTRO or _intro_ended or _is_skipping_intro:
		return
	_log("skip_intro called by player tap (blend_time=%.2f)" % intro_skip_blend_time)
	_is_skipping_intro = true

	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()

	if intro_skip_blend_time <= 0.01:
		_end_intro()
		return

	var from_pos: Vector3 = _cam_world_pos
	var from_pitch: float = _cur_pitch
	var from_dist: float = _cur_distance
	var from_h: float = _cur_height
	var s_pos: Vector3 = _start_pose.get("position", _cam_world_pos)
	var s_pitch: float = _start_pose.get("pitch", _cur_pitch)
	var s_dist: float = _start_pose.get("distance", _cur_distance)
	var s_h: float = _start_pose.get("height", _cur_height)

	_intro_tween = create_tween()
	_intro_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_intro_tween.tween_method(
		func(t: float) -> void:
			var p: Vector3 = from_pos.lerp(s_pos, t)
			var pitch: float = lerpf(from_pitch, s_pitch, t)
			var dist: float = lerpf(from_dist, s_dist, t)
			var h: float = lerpf(from_h, s_h, t)
			_apply_intro_step(p, pitch, dist, h),
		0.0,
		1.0,
		intro_skip_blend_time
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_intro_tween.finished.connect(_end_intro)

func _end_intro() -> void:
	if _intro_ended or _mode != Mode.INTRO:
		return
	_intro_ended = true
	_is_skipping_intro = false
	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
		_intro_tween = null

	# Initialize follow camera internal state to exact start pose
	if not _start_pose.is_empty():
		var s_pos: Vector3 = _start_pose.get("position", _cam_world_pos)
		var s_pitch: float = _start_pose.get("pitch", _cur_pitch)
		var s_dist: float = _start_pose.get("distance", _cur_distance)
		var s_h: float = _start_pose.get("height", _cur_height)
		_apply_intro_step(s_pos, s_pitch, s_dist, s_h)
	elif _target:
		_start_pose = get_gameplay_start_pose(_get_target_pos())
		var s_pos: Vector3 = _start_pose.get("position", _cam_world_pos)
		var s_pitch: float = _start_pose.get("pitch", _cur_pitch)
		var s_dist: float = _start_pose.get("distance", _cur_distance)
		var s_h: float = _start_pose.get("height", _cur_height)
		_apply_intro_step(s_pos, s_pitch, s_dist, s_h)

	# Reset look-ahead to zero
	_cur_la_offset_x = 0.0
	_cur_la_offset_y = 0.0

	# Reset previous target position so initial velocity is 0
	if _target:
		_prev_target_pos = _get_target_pos()

	_mode = Mode.FOLLOW
	_apply()

	_log("intro finished -> Mode.FOLLOW at %s" % str(_cam_world_pos))
	intro_finished.emit()

func is_intro_playing() -> bool:
	return _mode == Mode.INTRO and not _intro_ended

# ── Planning View API ─────────────────────────────────────────────────────

func set_planning_active(active: bool) -> void:
	if not enable_planning_view:
		_is_planning_active = false
		return
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

	set_process(true)

# ── Pinch & Zoom API ───────────────────────────────────────────────────────

func zoom_delta(delta: float) -> void:
	if _mode == Mode.DEATH or _mode == Mode.INTRO:
		return
	_base_distance = clampf(_base_distance + delta, min_distance, max_distance)
	_cur_distance = clampf(_cur_distance + delta, min_distance, max_distance)
	_apply()
	set_process(true)

func zoom_by(factor: float) -> void:
	if _mode == Mode.DEATH or _mode == Mode.INTRO or absf(factor - 1.0) < 0.001:
		return
	var new_dist := clampf(_base_distance * factor, min_distance, max_distance)
	var diff := new_dist - _base_distance
	zoom_delta(diff)

func notify_dracula_moving() -> void:
	pass

# ── Death cam & Shake ─────────────────────────────────────────────────────

func focus_death(duration: float = 1.5) -> void:
	_mode = Mode.DEATH
	var tw := create_tween().set_parallel(true)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_cur_height", death_height, duration)
	tw.tween_property(self, "_cur_distance", death_distance, duration)
	tw.tween_property(self, "_cur_pitch", death_pitch_degrees, duration)
	set_process(true)

func shake(strength: float, duration: float) -> void:
	_shake_strength = strength
	_shake_time = duration
	set_process(true)

# ── Process & Follow Updates ──────────────────────────────────────────────

func _process(delta: float) -> void:
	match _mode:
		Mode.FOLLOW:
			if _target:
				_update_follow(delta)

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

func _update_follow(delta: float) -> void:
	var tp := _get_target_pos()

	# 1. Detect ground velocity
	var move_vec := Vector2.ZERO
	var current_speed := 0.0
	if _target.has_method("get_ground_velocity"):
		var gv: Vector3 = _target.get_ground_velocity()
		move_vec = Vector2(gv.x, gv.z)
		current_speed = move_vec.length()
		if current_speed > 0.01:
			move_vec = move_vec.normalized()

	if current_speed < 0.01:
		var delta_pos := tp - _prev_target_pos
		var d2 := Vector2(delta_pos.x, delta_pos.z)
		current_speed = d2.length() / maxf(delta, 0.0001)
		if current_speed > 0.15:
			move_vec = d2.normalized()

	_prev_target_pos = tp

	# 2. Compute screen layout (safe box, soft zone, anchor)
	var play_rect := get_play_view_rect()
	var S_min_x := play_rect.position.x + play_rect.size.x * safe_box_margin_h
	var S_max_x := play_rect.end.x - play_rect.size.x * safe_box_margin_h
	var S_min_y := play_rect.position.y + play_rect.size.y * safe_box_margin_v
	var S_max_y := play_rect.end.y - play_rect.size.y * safe_box_margin_v

	var soft_w := play_rect.size.x * soft_zone_margin
	var soft_h := play_rect.size.y * soft_zone_margin
	var Z_min_x := S_min_x + soft_w
	var Z_max_x := S_max_x - soft_w
	var Z_min_y := S_min_y + soft_h
	var Z_max_y := S_max_y - soft_h

	debug_safe_rect = Rect2(S_min_x, S_min_y, S_max_x - S_min_x, S_max_y - S_min_y)
	debug_soft_rect = Rect2(Z_min_x, Z_min_y, Z_max_x - Z_min_x, Z_max_y - Z_min_y)

	# 3. Screen-space lookahead
	# Movement directions in world XZ map to screen space:
	#   World -Z (UP on screen)    -> Shift anchor DOWN (larger screen Y) -> Reveals more room UP
	#   World +Z (DOWN on screen)  -> Shift anchor UP (smaller screen Y)  -> Reveals more room DOWN
	#   World +X (RIGHT on screen) -> Shift anchor LEFT (smaller screen X) -> Reveals more room RIGHT
	#   World -X (LEFT on screen)  -> Shift anchor RIGHT (larger screen X) -> Reveals more room LEFT
	var k_speed := clampf(current_speed / 8.0, 0.0, 1.0)
	var tgt_la_x := -move_vec.x * (play_rect.size.x * lookahead_max_screen_x) * k_speed
	var tgt_la_y := -move_vec.y * (play_rect.size.y * lookahead_max_screen_y) * k_speed

	var la_decay := 1.0 - exp(-lookahead_smoothing * delta)
	_cur_la_offset_x = lerpf(_cur_la_offset_x, tgt_la_x, la_decay)
	_cur_la_offset_y = lerpf(_cur_la_offset_y, tgt_la_y, la_decay)

	var target_anchor_x := play_rect.position.x + play_rect.size.x * base_anchor_x + _cur_la_offset_x
	var target_anchor_y := play_rect.position.y + play_rect.size.y * base_anchor_y + _cur_la_offset_y

	# User Addition 3: Cap screen-space lookahead so anchor NEVER exits safe box or enters soft zone
	target_anchor_x = clampf(target_anchor_x, Z_min_x, Z_max_x)
	target_anchor_y = clampf(target_anchor_y, Z_min_y, Z_max_y)
	debug_target_anchor = Vector2(target_anchor_x, target_anchor_y)

	# 4. Ideal camera position from screen anchor
	var pitch_r := deg_to_rad(_cur_pitch)
	var ideal_cam := camera_pos_for_screen_target(tp, target_anchor_x, target_anchor_y, _cur_height, pitch_r)

	if lateral_follow < 0.99:
		var center_cam := camera_pos_for_screen_target(Vector3(center_x, 0.0, tp.z), target_anchor_x, target_anchor_y, _cur_height, pitch_r)
		ideal_cam.x = lerpf(center_cam.x, ideal_cam.x, lateral_follow)

	# 5. Soft Zone speed boost (User Addition 1)
	var cur_screen := project_to_screen(_cam_world_pos, tp, pitch_r)
	var depth_x := 0.0
	if cur_screen.x < Z_min_x:
		depth_x = (Z_min_x - cur_screen.x) / maxf(soft_w, 1.0)
	elif cur_screen.x > Z_max_x:
		depth_x = (cur_screen.x - Z_max_x) / maxf(soft_w, 1.0)

	var depth_y := 0.0
	if cur_screen.y < Z_min_y:
		depth_y = (Z_min_y - cur_screen.y) / maxf(soft_h, 1.0)
	elif cur_screen.y > Z_max_y:
		depth_y = (cur_screen.y - Z_max_y) / maxf(soft_h, 1.0)

	var soft_depth := clampf(maxf(depth_x, depth_y), 0.0, 1.0)
	debug_soft_depth = soft_depth

	var active_speed := run_follow_speed if current_speed > 2.0 else base_follow_speed
	var effective_speed := lerpf(active_speed, max_boosted_follow_speed, soft_depth * soft_depth)
	debug_effective_speed = effective_speed

	# 6. Smooth camera movement
	var step_decay := 1.0 - exp(-effective_speed * delta)
	if (_cam_world_pos - ideal_cam).length_squared() > follow_dead_zone * follow_dead_zone:
		_cam_world_pos.x = lerpf(_cam_world_pos.x, ideal_cam.x, step_decay)
		_cam_world_pos.z = lerpf(_cam_world_pos.z, ideal_cam.z, step_decay)
	_cam_world_pos.y = _cur_height

	# 7. Level bounds clamp (User Addition 2)
	if enable_level_bounds and level_bounds.size.x > 0.0 and level_bounds.size.y > 0.0:
		_cam_world_pos.x = clampf(_cam_world_pos.x, level_bounds.position.x, level_bounds.end.x)
		_cam_world_pos.z = clampf(_cam_world_pos.z, level_bounds.position.y + _cur_distance, level_bounds.end.y + _cur_distance)

	# 8. Hard Clamp Guarantee: Safe box ALWAYS wins!
	var proj_screen := project_to_screen(_cam_world_pos, tp, pitch_r)
	var clamped_sx := clampf(proj_screen.x, S_min_x, S_max_x)
	var clamped_sy := clampf(proj_screen.y, S_min_y, S_max_y)
	if absf(clamped_sx - proj_screen.x) > 0.01 or absf(clamped_sy - proj_screen.y) > 0.01:
		debug_hard_clamp = true
		var req_cam := camera_pos_for_screen_target(tp, clamped_sx, clamped_sy, _cur_height, pitch_r)
		_cam_world_pos.x = req_cam.x
		_cam_world_pos.z = req_cam.z
		proj_screen = Vector2(clamped_sx, clamped_sy)
	else:
		debug_hard_clamp = false

	# 9. Update state & apply
	debug_screen_pos = proj_screen
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x > 0.0 and vp_size.y > 0.0:
		debug_screen_pct = Vector2((proj_screen.x / vp_size.x) * 100.0, (proj_screen.y / vp_size.y) * 100.0)

	_focus_pos.x = _cam_world_pos.x
	_focus_pos.z = _cam_world_pos.z - _cur_distance
	_apply()

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
		set_process(false)
