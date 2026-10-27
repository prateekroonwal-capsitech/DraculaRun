class_name SunControl
extends UIController

## SunControl — the sun widget in the bottom strip.
##
## A shallow arc seen "from the front", like the sky ahead of Dracula:
##   * horizontal drag = AZIMUTH (sun left ↔ right)
##   * vertical drag   = ELEVATION (up = high sun / short shadows, down = low / long)
## Dragging is relative: touching never jumps the sun; finger travel across the arc
## span (or `elevation_drag_span` of the strip height) × drag_sensitivity covers the
## full range. The guide arc stays fixed; the sun icon rises above it for a high sun
## and sinks below it for a low sun. Q/E (azimuth) and R/F (elevation) do the same on desktop.
##
## Touch arbitration: a touch that STARTS inside this strip belongs to the sun until it
## lifts; it is consumed in _input() so the play view never treats it as a tap.
##
## drag_started / drag_ended bracket every sun interaction (finger, mouse or key hold):
## Dracula stands still while the sun moves. When the SunRig's exposure guard refuses
## a move, play_blocked() shakes the widget and flashes its edge red.
## The strip only sets the SunRig *target*; the rig enforces max speed and the guard.

signal drag_started
signal drag_ended

## Sun icon radius in px (>= 70 → icon >= 140 px wide).
@export var sun_radius: float = 70.0
## Horizontal inset so the icon stays inside the strip at the azimuth limits.
@export var side_margin: float = 96.0
## Arc height (fraction of the strip height) and sag toward the ends.
@export_range(0.0, 1.0) var arc_y: float = 0.5
@export_range(0.0, 0.5) var arc_sag: float = 0.06
## How far (fraction of the strip height) the sun icon rises from lowest to highest elevation.
@export_range(0.0, 0.8) var elevation_travel: float = 0.36
## Vertical finger travel (fraction of the strip height) that covers the full elevation range.
@export_range(0.1, 1.0) var elevation_drag_span: float = 0.6
## >1 turns the sun further for the same finger travel (1.0 = span = full range).
@export var drag_sensitivity: float = 1.5
## Q/E and R/F speeds in °/s (match SunRig's max speed).
@export var key_azimuth_speed: float = 180.0
@export var key_elevation_speed: float = 180.0
@export_group("Blocked feedback")
@export var shake_pixels: float = 14.0
@export var shake_time: float = 0.3
@export var blocked_color: Color = Color(0.9, 0.12, 0.1, 0.85)
@export_group("Colours")
@export var strip_color: Color = Color(0.07, 0.04, 0.08, 0.88)
@export var guide_color: Color = Color(1.0, 0.86, 0.55, 0.35)
@export var sun_color: Color = Color(1.0, 0.8, 0.28, 1.0)

var _sun: SunRig
var _owned_touches: Dictionary = {}   # touch index (-1 = mouse) -> grab anchor {pos, az, el}
var _enabled: bool = true
var _key_dragging: bool = false
var _blocked_glow: float = 0.0
var _shake: Vector2 = Vector2.ZERO
var _fx_tween: Tween

## Explicit dependency: the rig this strip steers.
func bind_sun(sun: SunRig) -> void:
	if _sun and _sun.sun_moved.is_connected(_on_sun_moved):
		_sun.sun_moved.disconnect(_on_sun_moved)
	_sun = sun
	if _sun:
		_sun.sun_moved.connect(_on_sun_moved)
	queue_redraw()

func set_controls_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled and (not _owned_touches.is_empty() or _key_dragging):
		_owned_touches.clear()
		_key_dragging = false
		drag_ended.emit()
	set_process(false)
	set_process_input(enabled)

func is_dragging() -> bool:
	return not _owned_touches.is_empty() or _key_dragging

## The guard refused a sun move: shake + red edge glow.
func play_blocked() -> void:
	if _fx_tween and _fx_tween.is_valid():
		_fx_tween.kill()
	_fx_tween = create_tween()
	_fx_tween.tween_method(_set_fx, 1.0, 0.0, shake_time)

func _on_ready() -> void:
	set_process_input(true)

func _exit_tree() -> void:
	bind_sun(null)

# ── Input ─────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _enabled or _sun == null:
		return
	if event is InputEventKey:
		if event.is_action("sun_left") or event.is_action("sun_right") or event.is_action("sun_up") or event.is_action("sun_down"):
			if event.is_pressed() and not _key_dragging:
				_key_dragging = true
				if _owned_touches.is_empty():
					drag_started.emit()
			set_process(true)   # PDF §4: tick only while a sun key may be held
		return
	# Ignore mouse<->touch emulation duplicates; real touch and real mouse are handled below.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and _is_inside(st.position):
			_begin_drag(st.index, st.position)
		elif not st.pressed and _owned_touches.has(st.index):
			_end_drag(st.index)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _owned_touches.has(sd.index):
			_drag_to(sd.index, sd.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed and _is_inside(mb.position):
			_begin_drag(-1, mb.position)
		elif not mb.pressed and _owned_touches.has(-1):
			_end_drag(-1)
	elif event is InputEventMouseMotion and _owned_touches.has(-1):
		_drag_to(-1, (event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var d_az := Input.get_axis("sun_left", "sun_right") * key_azimuth_speed * delta
	var d_el := Input.get_axis("sun_down", "sun_up") * key_elevation_speed * delta
	if is_zero_approx(d_az) and is_zero_approx(d_el):
		set_process(false)   # PDF §4: no key held — stop ticking
		if _key_dragging:
			_key_dragging = false
			if _owned_touches.is_empty():
				drag_ended.emit()
		return
	_sun.nudge_target(d_az, d_el)
	queue_redraw()

func _begin_drag(index: int, viewport_pos: Vector2) -> void:
	var first := _owned_touches.is_empty() and not _key_dragging
	_owned_touches[index] = {"pos": _to_local(viewport_pos), "az": _sun.target_azimuth, "el": _sun.target_elevation}
	get_viewport().set_input_as_handled()
	if first:
		drag_started.emit()

func _end_drag(index: int) -> void:
	_owned_touches.erase(index)
	get_viewport().set_input_as_handled()
	if _owned_touches.is_empty() and not _key_dragging:
		drag_ended.emit()

func _drag_to(index: int, viewport_pos: Vector2) -> void:
	var grab: Dictionary = _owned_touches[index]
	var p := _to_local(viewport_pos)
	var d: Vector2 = p - (grab.pos as Vector2)
	var span_x := maxf(1.0, size.x - 2.0 * side_margin)
	var span_y := maxf(1.0, size.y * elevation_drag_span)
	var az: float = grab.az + d.x / span_x * (_sun.azimuth_max - _sun.azimuth_min) * drag_sensitivity
	var el: float = grab.el - d.y / span_y * (_sun.elevation_max - _sun.elevation_min) * drag_sensitivity
	_sun.set_target(az, el)
	# Clamped at a limit: re-anchor so reversing direction responds immediately.
	if not is_equal_approx(_sun.target_azimuth, az) or not is_equal_approx(_sun.target_elevation, el):
		_owned_touches[index] = {"pos": p, "az": _sun.target_azimuth, "el": _sun.target_elevation}
	queue_redraw()

# ── Geometry ──────────────────────────────────────────────────────────────

func _to_local(viewport_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_pos

func _is_inside(viewport_pos: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(_to_local(viewport_pos))

## u = azimuth 0..1 across the arc, e = elevation 0..1 (0 = lowest).
func _point_for(u: float, e: float = 0.5) -> Vector2:
	var c := 2.0 * u - 1.0
	var y := arc_y + arc_sag * c * c - (e - 0.5) * elevation_travel
	return Vector2(lerpf(side_margin, size.x - side_margin, u), y * size.y) + _shake

func _set_fx(k: float) -> void:
	_blocked_glow = k
	_shake = Vector2(sin(k * 40.0) * shake_pixels * k, 0.0)
	queue_redraw()

# ── Drawing ───────────────────────────────────────────────────────────────

func _on_sun_moved(_az: float, _el: float) -> void:
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), strip_color)
	if _blocked_glow > 0.0:
		var c := blocked_color
		c.a *= _blocked_glow
		draw_rect(Rect2(Vector2.ZERO, size), c, false, 10.0)
	if _sun == null:
		return
	var pts := PackedVector2Array()
	for i in 33:
		pts.append(_point_for(i / 32.0))   # fixed guide line (mid elevation); only the sun moves
	draw_polyline(pts, guide_color, 4.0, true)
	var range_deg := maxf(0.001, _sun.azimuth_max - _sun.azimuth_min)
	var el_range := maxf(0.001, _sun.elevation_max - _sun.elevation_min)
	var e := clampf((_sun.elevation - _sun.elevation_min) / el_range, 0.0, 1.0)
	var te := clampf((_sun.target_elevation - _sun.elevation_min) / el_range, 0.0, 1.0)
	var sun_pos := _point_for((_sun.azimuth - _sun.azimuth_min) / range_deg, e)
	var target_pos := _point_for((_sun.target_azimuth - _sun.azimuth_min) / range_deg, te)
	if target_pos.distance_to(sun_pos) > 3.0:
		draw_arc(target_pos, sun_radius * 0.7, 0.0, TAU, 32, Color(sun_color, 0.5), 4.0, true)
	for i in 12:
		var a := TAU * i / 12.0
		var d := Vector2(cos(a), sin(a))
		draw_line(sun_pos + d * (sun_radius * 0.72), sun_pos + d * sun_radius, sun_color, 7.0, true)
	draw_circle(sun_pos, sun_radius * 0.6, sun_color)
	draw_circle(sun_pos, sun_radius * 0.36, Color(1.0, 0.97, 0.82))
