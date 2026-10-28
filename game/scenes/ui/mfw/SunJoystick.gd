class_name SunJoystick
extends SunInput

## SunJoystick — the sun-position DIAL in the bottom-right corner (bottom-left with
## left_handed). SunInput "joystick" mode; the slider strip is the other mode.
##
## The bright sun knob always sits at the sun's CURRENT angle:
##   knob X = azimuth (left edge of the ring = the level's minimum, right edge = maximum),
##   knob Y = elevation (top = HIGH / short shadows, bottom = LOW / long shadows).
## The level's (azimuth, elevation) rectangle is mapped onto the round dial with an
## elliptical square↔disc mapping, so every point inside the ring is a valid angle and
## the edge midpoints are the range limits.
##
## Touch / drag anywhere inside the ring = "put the sun there": that angle becomes the
## SunRig target and the sun turns toward it at the rig's max speed and smoothing. While
## it catches up, a dim marker shows where the finger is aiming. Releasing leaves the
## target where it was left (no spring-back). Q/E and R/F nudge the target; the knob follows.
## Exposure guard: the rig stops the sun at the last safe angle — the knob stays there, the
## ring flashes red and the dim marker lingers on the angle the player tried to reach.
##
## Touch arbitration: a touch that STARTS on the dial belongs to the sun until it lifts
## (consumed in _input(), so the play view never sees it); every other touch is free for
## tap / drag movement — multi-touch works. drag_started / drag_ended bracket every sun
## interaction: Dracula stands still meanwhile.

@export_group("Feel")
## Q/E and R/F speeds in °/s.
@export var key_azimuth_speed: float = 180.0
@export var key_elevation_speed: float = 180.0
## How long the dim "tried here" marker stays after a blocked move, seconds.
@export var blocked_marker_time: float = 0.8

@export_group("Layout")
## Mirror to the bottom-left corner.
@export var left_handed: bool = false
## Distance from the safe-area edges, px (the dial is anchored to a bottom corner).
@export var corner_margin: float = 24.0
## Touches up to this far outside the ring (px) still grab the dial.
@export var grab_slop: float = 28.0

@export_group("Blocked feedback")
@export var shake_pixels: float = 10.0
@export var shake_time: float = 0.3

@export_group("Parts")
## Holds ring, labels, knob and marker; shaken on a blocked move (the root keeps its anchors).
@export var body: Control
@export var ring: DialRing
@export var knob: Control
@export var target_marker: Control
@export var blocked_rim: Control

var _enabled: bool = true
var _touch: int = -99          # owning touch index (-1 = mouse), -99 = none
var _key_dragging: bool = false
var _aim: Vector2 = Vector2.ZERO          # last finger aim, dial-local px from the ring centre
var _aim_visible_until: float = 0.0
var _clock: float = 0.0
var _fx_tween: Tween

func bind_sun(sun: SunRig) -> void:
	if _sun and _sun.sun_moved.is_connected(_on_sun_moved):
		_sun.sun_moved.disconnect(_on_sun_moved)
	super.bind_sun(sun)
	if _sun:
		_sun.sun_moved.connect(_on_sun_moved)
	_place_parts()

func set_controls_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled and is_dragging():
		_touch = -99
		_key_dragging = false
		drag_ended.emit()
	set_process_input(enabled)

func is_dragging() -> bool:
	return _touch != -99 or _key_dragging

## True when a viewport position is on the dial (ring + grab slop).
func contains(viewport_pos: Vector2) -> bool:
	return is_visible_in_tree() and _to_ring(viewport_pos).length() <= ring.radius() + grab_slop

## The guard refused a sun move: red ring flash + small shake; the aim marker lingers.
func play_blocked() -> void:
	_aim_visible_until = _clock + blocked_marker_time
	set_process(true)
	if _fx_tween and _fx_tween.is_valid():
		return
	_fx_tween = create_tween()
	_fx_tween.tween_method(_set_fx, 1.0, 0.0, shake_time)

func _on_ready() -> void:
	if left_handed:
		anchor_left = 0.0
		anchor_right = 0.0
		offset_left = corner_margin
		offset_right = corner_margin + custom_minimum_size.x
	blocked_rim.modulate.a = 0.0
	target_marker.visible = false
	ring.resized.connect(_place_parts)
	_place_parts()
	set_process(false)   # PDF §4: tick only while a key is held or the aim marker is shown
	set_process_input(true)

func _exit_tree() -> void:
	if _sun and _sun.sun_moved.is_connected(_on_sun_moved):
		_sun.sun_moved.disconnect(_on_sun_moved)

# ── Input ─────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _enabled or _sun == null or not is_visible_in_tree():   # hidden mode never reads input
		return
	if event is InputEventKey:
		if event.is_action("sun_left") or event.is_action("sun_right") or event.is_action("sun_up") or event.is_action("sun_down"):
			if event.is_pressed() and not _key_dragging:
				_key_dragging = true
				if _touch == -99:
					drag_started.emit()
			set_process(true)
		return
	# Ignore mouse<->touch emulation duplicates; real touch and real mouse are handled below.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and _touch == -99 and contains(st.position):
			_grab(st.index, st.position)
		elif not st.pressed and st.index == _touch:
			_let_go()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _touch:
			_aim_at(sd.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed and _touch == -99 and contains(mb.position):
			_grab(-1, mb.position)
		elif not mb.pressed and _touch == -1:
			_let_go()
	elif event is InputEventMouseMotion and _touch == -1:
		_aim_at((event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()

## Test hooks: the same grab / move / release path a finger takes.
func press_at(viewport_pos: Vector2) -> void:
	if _enabled and _sun and _touch == -99 and contains(viewport_pos):
		_grab(-1, viewport_pos)

func move_to(viewport_pos: Vector2) -> void:
	if _touch != -99:
		_aim_at(viewport_pos)

func release() -> void:
	if _touch != -99:
		_let_go()

## Viewport position of the dial point for an angle (for tests and tutorials).
func point_for_angles(azimuth: float, elevation: float) -> Vector2:
	return ring.get_global_transform_with_canvas() * (ring.size * 0.5 + _angles_to_ring(azimuth, elevation))

## Viewport position of the bright knob (the sun's current angle).
func knob_center_global() -> Vector2:
	return knob.get_global_transform_with_canvas() * (knob.size * 0.5)

func _grab(index: int, viewport_pos: Vector2) -> void:
	var first := not is_dragging()
	_touch = index
	get_viewport().set_input_as_handled()
	if first:
		drag_started.emit()
	_aim_at(viewport_pos)

func _let_go() -> void:
	_touch = -99
	get_viewport().set_input_as_handled()
	_place_parts()
	if not _key_dragging:
		drag_ended.emit()

## Finger → target angle (absolute: the sun goes where the finger points).
func _aim_at(viewport_pos: Vector2) -> void:
	var r := ring.radius()
	_aim = _to_ring(viewport_pos).limit_length(r)
	var a := _ring_to_angles(_aim)
	_sun.set_target(a.x, a.y)
	set_process(true)
	_place_parts()

# ── Keys / marker timing ──────────────────────────────────────────────────

func _process(delta: float) -> void:
	_clock += delta
	if _sun == null:
		set_process(false)
		return
	var d_az := Input.get_axis("sun_left", "sun_right") * key_azimuth_speed * delta
	var d_el := Input.get_axis("sun_down", "sun_up") * key_elevation_speed * delta
	if _key_dragging and is_zero_approx(d_az) and is_zero_approx(d_el):
		_key_dragging = false
		if _touch == -99:
			drag_ended.emit()
	if _key_dragging:
		_sun.nudge_target(d_az, d_el)
	_place_parts()
	if not is_dragging() and _clock >= _aim_visible_until and _sun.is_settled():
		set_process(false)   # PDF §4: nothing left to animate

func _on_sun_moved(_az: float, _el: float) -> void:
	_place_parts()

# ── Mapping: (azimuth, elevation) square ↔ dial disc ─────────────────────

## Angles → dial offset from the ring centre (px, screen axes: +y down).
func _angles_to_ring(azimuth: float, elevation: float) -> Vector2:
	if _sun == null:
		return Vector2.ZERO
	var x := remap(azimuth, _sun.azimuth_min, _sun.azimuth_max, -1.0, 1.0)
	var y := remap(elevation, _sun.elevation_min, _sun.elevation_max, -1.0, 1.0)   # +1 = HIGH
	x = clampf(x, -1.0, 1.0)
	y = clampf(y, -1.0, 1.0)
	# Elliptical grid mapping square → disc.
	var u := x * sqrt(1.0 - y * y * 0.5)
	var v := y * sqrt(1.0 - x * x * 0.5)
	return Vector2(u, -v) * ring.radius()

## Dial offset (px from the ring centre, clamped inside the ring) → (azimuth, elevation).
func _ring_to_angles(p: Vector2) -> Vector2:
	var r := maxf(1.0, ring.radius())
	var u := clampf(p.x / r, -1.0, 1.0)
	var v := clampf(-p.y / r, -1.0, 1.0)
	var n := Vector2(u, v)
	if n.length() > 1.0:
		n = n.normalized()
	u = n.x
	v = n.y
	# Inverse elliptical grid mapping disc → square.
	var s2 := 2.0 * sqrt(2.0)
	var uu := u * u
	var vv := v * v
	var x := 0.5 * sqrt(maxf(0.0, 2.0 + uu - vv + s2 * u)) - 0.5 * sqrt(maxf(0.0, 2.0 + uu - vv - s2 * u))
	var y := 0.5 * sqrt(maxf(0.0, 2.0 - uu + vv + s2 * v)) - 0.5 * sqrt(maxf(0.0, 2.0 - uu + vv - s2 * v))
	return Vector2(remap(clampf(x, -1.0, 1.0), -1.0, 1.0, _sun.azimuth_min, _sun.azimuth_max),
		remap(clampf(y, -1.0, 1.0), -1.0, 1.0, _sun.elevation_min, _sun.elevation_max))

# ── Visuals ───────────────────────────────────────────────────────────────

func _place_parts() -> void:
	if knob == null or ring == null or _sun == null:
		return
	var c := ring.position + ring.size * 0.5
	knob.position = c + _angles_to_ring(_sun.azimuth, _sun.elevation) - knob.size * 0.5
	# Dim marker: where the finger aims while the sun catches up (or a refused angle).
	var aiming := _touch != -99 or _clock < _aim_visible_until
	var aim_pos := c + _aim - target_marker.size * 0.5
	target_marker.position = aim_pos
	target_marker.visible = aiming and aim_pos.distance_to(knob.position + (knob.size - target_marker.size) * 0.5) > 6.0

func _set_fx(k: float) -> void:
	blocked_rim.modulate.a = k
	body.position = Vector2(sin(k * 40.0) * shake_pixels * k, 0.0)

## Viewport position → offset from the ring centre in dial-local px.
func _to_ring(viewport_pos: Vector2) -> Vector2:
	return ring.get_global_transform_with_canvas().affine_inverse() * viewport_pos - ring.size * 0.5
