class_name SunJoystick
extends SunInput

## SunJoystick — rate-based sun control in the bottom-right corner (bottom-left with
## left_handed). SunInput "joystick" mode; the slider strip is the other mode. Push the sun knob: X turns the sun's AZIMUTH, Y its ELEVATION
## (up = higher sun / shorter shadows). Deflection sets the turning SPEED through a
## response curve — a small push is a slow, precise nudge, a full push is max_speed.
## Inside the deadzone nothing moves. On release the knob springs back to the centre and
## the sun stays exactly where it is. Q/E (azimuth) and R/F (elevation) do the same on desktop.
##
## Touch arbitration: a touch that STARTS on the joystick belongs to the sun until it lifts
## (consumed in _input(), so the play view never sees it); every other touch is free for
## tap / drag movement — multi-touch works (one finger on the sun, one leading Dracula).
## drag_started / drag_ended bracket every sun interaction: Dracula stands still meanwhile.
## When the SunRig's exposure guard refuses a move, play_blocked() flashes the base red.
## The joystick only moves the SunRig *target*; the rig enforces range, speed and the guard.
## Visuals (base, rim, knob) are nodes in SunJoystick.tscn.

@export_group("Feel")
## Max sun speed at full deflection, degrees per second (both axes).
@export var max_speed: float = 180.0
## Fraction of the knob travel that does nothing.
@export_range(0.0, 0.5) var deadzone: float = 0.1
## Response curve exponent: speed = max_speed × ((deflection − deadzone) / (1 − deadzone))^exponent.
## 1 = linear, 2 = gentle near the centre (precise), 3 = very gentle.
@export_range(1.0, 4.0) var response_exponent: float = 2.2
## How far the knob centre can travel from the base centre, px.
@export var knob_travel: float = 92.0
## The target never leads the visible sun by more than this (°), so letting go never overshoots.
@export var max_lead_degrees: float = 6.0
## Spring-back time of the knob on release.
@export var return_time: float = 0.12
## Q/E and R/F speeds in °/s.
@export var key_azimuth_speed: float = 180.0
@export var key_elevation_speed: float = 180.0

@export_group("Layout")
## Mirror to the bottom-left corner.
@export var left_handed: bool = false
## Distance from the safe-area edges, px (the joystick is anchored to a bottom corner).
@export var corner_margin: float = 48.0
## Touches up to this far outside the base circle (px) still grab the joystick.
@export var grab_slop: float = 24.0

@export_group("Blocked feedback")
@export var shake_pixels: float = 12.0
@export var shake_time: float = 0.3

@export_group("Parts")
## Holds base, rim and knob; shaken on a blocked move (the root keeps its anchors).
@export var body: Control
@export var knob: Control
@export var blocked_rim: Control

var _enabled: bool = true
var _touch: int = -99          # owning touch index (-1 = mouse), -99 = none
var _key_dragging: bool = false
var _knob_offset: Vector2 = Vector2.ZERO
var _knob_tween: Tween
var _fx_tween: Tween

func set_controls_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled and is_dragging():
		_touch = -99
		_key_dragging = false
		_release_knob()
		drag_ended.emit()
	set_process(is_dragging())
	set_process_input(enabled)

func is_dragging() -> bool:
	return _touch != -99 or _key_dragging

## True when a viewport position is on the joystick (incl. grab slop).
func contains(viewport_pos: Vector2) -> bool:
	return is_visible_in_tree() and _to_local(viewport_pos).distance_to(size * 0.5) <= size.x * 0.5 + grab_slop

## The guard refused a sun move: red rim flash + small shake (not restarted while running).
func play_blocked() -> void:
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
	_center_knob()
	set_process(false)   # PDF §4: tick only while the knob is held or a sun key is down
	set_process_input(true)

func _exit_tree() -> void:
	_sun = null

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
			_move_knob(sd.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed and _touch == -99 and contains(mb.position):
			_grab(-1, mb.position)
		elif not mb.pressed and _touch == -1:
			_let_go()
	elif event is InputEventMouseMotion and _touch == -1:
		_move_knob((event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()

## Test hooks: the same grab / move / release path a finger takes.
func press_at(viewport_pos: Vector2) -> void:
	if _touch == -99 and contains(viewport_pos):
		_grab(-1, viewport_pos)

func move_to(viewport_pos: Vector2) -> void:
	if _touch != -99:
		_move_knob(viewport_pos)

func release() -> void:
	if _touch != -99:
		_let_go()

func knob_center_global() -> Vector2:
	return get_global_transform_with_canvas() * (size * 0.5)

func _grab(index: int, viewport_pos: Vector2) -> void:
	var first := not is_dragging()
	_touch = index
	get_viewport().set_input_as_handled()
	if _knob_tween and _knob_tween.is_valid():
		_knob_tween.kill()
	_move_knob(viewport_pos)
	set_process(true)
	if first:
		drag_started.emit()

func _let_go() -> void:
	_touch = -99
	get_viewport().set_input_as_handled()
	_release_knob()
	if not _key_dragging:
		drag_ended.emit()

func _move_knob(viewport_pos: Vector2) -> void:
	_knob_offset = (_to_local(viewport_pos) - size * 0.5).limit_length(knob_travel)
	_place_knob()

func _release_knob() -> void:
	# The sun stays where it is: drop any lead the target had over the visible sun.
	if _sun:
		_sun.set_target(_sun.azimuth, _sun.elevation)
	if _knob_tween and _knob_tween.is_valid():
		_knob_tween.kill()
	_knob_tween = create_tween()
	_knob_tween.tween_method(func(o: Vector2) -> void:
		_knob_offset = o
		_place_knob(), _knob_offset, Vector2.ZERO, return_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ── Rate control ──────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _sun == null:
		set_process(false)
		return
	var rate := stick_rate(_knob_offset / knob_travel) if _touch != -99 else Vector2.ZERO
	rate += Vector2(Input.get_axis("sun_left", "sun_right") * key_azimuth_speed,
		Input.get_axis("sun_down", "sun_up") * key_elevation_speed)
	if _key_dragging and is_zero_approx(Input.get_axis("sun_left", "sun_right")) and is_zero_approx(Input.get_axis("sun_down", "sun_up")):
		_key_dragging = false
		if _touch == -99:
			_sun.set_target(_sun.azimuth, _sun.elevation)
			drag_ended.emit()
	if not is_dragging():
		set_process(false)
		return
	if rate == Vector2.ZERO:
		return
	var az := clampf(_sun.target_azimuth + rate.x * delta, _sun.azimuth - max_lead_degrees, _sun.azimuth + max_lead_degrees)
	var el := clampf(_sun.target_elevation + rate.y * delta, _sun.elevation - max_lead_degrees, _sun.elevation + max_lead_degrees)
	_sun.set_target(az, el)

## Sun speed (°/s, x = azimuth, y = elevation) for a knob deflection in [-1, 1]²
## (screen axes: +y = down). Public so tests can check the curve.
func stick_rate(v: Vector2) -> Vector2:
	var m := minf(1.0, v.length())
	if m <= deadzone:
		return Vector2.ZERO
	var k := pow((m - deadzone) / (1.0 - deadzone), response_exponent)
	var dir := v / v.length()
	return Vector2(dir.x, -dir.y) * max_speed * k

# ── Visuals ───────────────────────────────────────────────────────────────

func _center_knob() -> void:
	_knob_offset = Vector2.ZERO
	_place_knob()

func _place_knob() -> void:
	knob.position = size * 0.5 - knob.size * 0.5 + _knob_offset

func _set_fx(k: float) -> void:
	blocked_rim.modulate.a = k
	body.position = Vector2(sin(k * 40.0) * shake_pixels * k, 0.0)

func _to_local(viewport_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_pos
