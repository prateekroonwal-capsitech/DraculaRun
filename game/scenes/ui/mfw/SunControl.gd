class_name SunControl
extends UIController

## SunControl — the bottom sun strip (portrait layout).
##
## A wide, shallow arc seen "from the front", like the real sky ahead of Dracula:
##   * horizontal drag = AZIMUTH   (left edge = sun far left, right edge = far right)
##   * vertical drag   = ELEVATION (up = high sun / short shadows, down = low sun / long shadows)
## The sun icon follows a shallow arc (it dips toward the strip's ends like a real
## sun path) and is at least 140 px across. A small ground line shows Dracula and
## the side his shadow falls on.
##
## Touch arbitration: a touch that STARTS inside this strip belongs to the sun until
## it lifts; it is consumed in _input() so DraculaController never sees it as a swipe.
## Touches starting anywhere else are left alone (swipe candidates). Two touches at
## once work: one thumb here, the other swiping in the play view.
## Desktop: mouse drag here, Q/E (azimuth), R/F (elevation).
## The strip only sets the SunRig *target*; the rig enforces the max angular speed.

## Sun icon radius in px (>= 70 → icon >= 140 px wide).
@export var sun_radius: float = 74.0
## Horizontal inset so the icon stays inside the strip at ±max azimuth.
@export var side_margin: float = 96.0
## Vertical travel of the sun center, as fractions of the strip height.
@export_range(0.0, 1.0) var high_y: float = 0.3
@export_range(0.0, 1.0) var low_y: float = 0.72
## Arc sag (fraction of strip height) at the ends: the "shallow arc".
@export_range(0.0, 0.5) var arc_sag: float = 0.12
## Ground line (Dracula + shadow hint), fraction of the strip height.
@export_range(0.0, 1.0) var ground_y: float = 0.93
@export var key_azimuth_speed: float = 90.0
@export var key_elevation_speed: float = 45.0
@export var strip_color: Color = Color(0.07, 0.04, 0.12, 0.82)
@export var guide_color: Color = Color(1.0, 0.86, 0.55, 0.35)
@export var sun_color: Color = Color(1.0, 0.8, 0.28, 1.0)
@export var shadow_hint_color: Color = Color(0.32, 0.34, 0.8, 0.9)
@export var label_font_size: int = 26

var _sun: SunRig
var _owned_touches: Dictionary = {}   # touch index (-1 = mouse) -> true
var _enabled: bool = true

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
	_owned_touches.clear()
	set_process(false)
	set_process_input(enabled)

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
			set_process(true)   # PDF §4: tick only while a sun key may be held
		return
	# Ignore mouse<->touch emulation duplicates; real touch and real mouse are handled below.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and _is_inside(st.position):
			_owned_touches[st.index] = true
			_drag_to(st.position)
			get_viewport().set_input_as_handled()
		elif not st.pressed and _owned_touches.erase(st.index):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _owned_touches.has(sd.index):
			_drag_to(sd.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed and _is_inside(mb.position):
			_owned_touches[-1] = true
			_drag_to(mb.position)
			get_viewport().set_input_as_handled()
		elif not mb.pressed and _owned_touches.erase(-1):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _owned_touches.has(-1):
		_drag_to((event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var d_az := Input.get_axis("sun_left", "sun_right") * key_azimuth_speed * delta
	var d_el := Input.get_axis("sun_down", "sun_up") * key_elevation_speed * delta
	if is_zero_approx(d_az) and is_zero_approx(d_el):
		set_process(false)   # PDF §4: no key held — stop ticking
		return
	_sun.nudge_target(d_az, d_el)
	queue_redraw()

# ── Geometry ──────────────────────────────────────────────────────────────

func _to_local(viewport_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_pos

func _is_inside(viewport_pos: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(_to_local(viewport_pos))

## u in 0..1 across the usable width.
func _x_for(u: float) -> float:
	return lerpf(side_margin, size.x - side_margin, u)

func _sag(u: float) -> float:
	var c := 2.0 * u - 1.0
	return arc_sag * size.y * c * c

## el_t in 0..1 (0 = lowest elevation, 1 = highest).
func _y_for(u: float, el_t: float) -> float:
	return lerpf(low_y, high_y, el_t) * size.y + _sag(u)

func _drag_to(viewport_pos: Vector2) -> void:
	var p := _to_local(viewport_pos)
	var u := clampf(inverse_lerp(side_margin, size.x - side_margin, p.x), 0.0, 1.0)
	var el_t := clampf(inverse_lerp(low_y * size.y, high_y * size.y, p.y - _sag(u)), 0.0, 1.0)
	_sun.set_target(lerpf(_sun.azimuth_min, _sun.azimuth_max, u), lerpf(_sun.elevation_min, _sun.elevation_max, el_t))
	queue_redraw()

func _angles_to_local(az: float, el: float) -> Vector2:
	var u := inverse_lerp(_sun.azimuth_min, _sun.azimuth_max, az)
	var el_t := inverse_lerp(_sun.elevation_min, _sun.elevation_max, el)
	return Vector2(_x_for(u), _y_for(u, el_t))

# ── Drawing ───────────────────────────────────────────────────────────────

func _on_sun_moved(_az: float, _el: float) -> void:
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), strip_color)
	if _sun == null:
		return
	# Guide arcs: high and low sun paths, plus the zenith line.
	for el_t in [1.0, 0.0]:
		var pts := PackedVector2Array()
		for i in 25:
			var u := i / 24.0
			pts.append(Vector2(_x_for(u), _y_for(u, el_t)))
		draw_polyline(pts, guide_color, 3.0, true)
	draw_line(Vector2(size.x * 0.5, _y_for(0.5, 1.0)), Vector2(size.x * 0.5, _y_for(0.5, 0.0)), Color(guide_color, guide_color.a * 0.5), 2.0, true)
	var font := get_theme_default_font()
	draw_string(font, Vector2(16, _y_for(0.0, 1.0) + 8), "HIGH", HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size, guide_color)
	draw_string(font, Vector2(16, _y_for(0.0, 0.0) + 8), "LOW", HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size, guide_color)

	# Ground line: Dracula and the side/length of his shadow.
	var gy := ground_y * size.y
	var cx := size.x * 0.5
	draw_line(Vector2(side_margin, gy), Vector2(size.x - side_margin, gy), Color(guide_color, 0.25), 2.0)
	var el_t := inverse_lerp(_sun.elevation_min, _sun.elevation_max, _sun.elevation)
	var shadow_len := lerpf(150.0, 40.0, el_t)
	var side := -signf(_sun.azimuth) if absf(_sun.azimuth) > 2.0 else 0.0
	var tip := Vector2(cx + side * shadow_len, gy)
	draw_line(Vector2(cx, gy), tip, shadow_hint_color, 12.0, true)
	draw_circle(Vector2(cx, gy - 14.0), 14.0, Color(0.12, 0.02, 0.05))
	draw_circle(Vector2(cx, gy - 14.0), 7.0, Color(0.75, 0.05, 0.08))

	# Target (ghost) and live sun.
	var sun_pos := _angles_to_local(_sun.azimuth, _sun.elevation)
	var target_pos := _angles_to_local(_sun.target_azimuth, _sun.target_elevation)
	if target_pos.distance_to(sun_pos) > 3.0:
		draw_line(sun_pos, target_pos, Color(sun_color, 0.35), 4.0, true)
		draw_arc(target_pos, sun_radius * 0.7, 0.0, TAU, 32, Color(sun_color, 0.6), 4.0, true)
	for i in 12:
		var a := TAU * i / 12.0
		var d := Vector2(cos(a), sin(a))
		draw_line(sun_pos + d * (sun_radius * 0.72), sun_pos + d * sun_radius, sun_color, 7.0, true)
	draw_circle(sun_pos, sun_radius * 0.6, sun_color)
	draw_circle(sun_pos, sun_radius * 0.36, Color(1.0, 0.97, 0.82))
