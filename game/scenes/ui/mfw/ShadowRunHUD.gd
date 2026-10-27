class_name ShadowRunHUD
extends UIController

## In-run HUD (portrait): top bar (~10%: pause, distance, exposure meter), play
## view (~68%: road, countdown, hints) and the SunControl strip (~22%). Layout is
## containers + stretch ratios in ShadowRunHUD.tscn; this script only pads the
## SafeArea container by the device's safe-area insets (notch / home indicator).
## Listens to GameBus for exposure/distance; everything else is called directly by ShadowRunFeature.
## All non-button controls use MOUSE_FILTER_IGNORE so desktop mouse swipes reach
## DraculaController._unhandled_input.

signal pause_requested
signal debug_toggle_requested

## MarginContainer padded with the display safe area (mobile only).
@export var safe_area: MarginContainer
## Minimum padding in viewport pixels, even on devices without insets.
@export var min_safe_margin: int = 0

@onready var _meter: ExposureMeter = %ExposureMeter
@onready var _distance: Label = %DistanceLabel
@onready var _pause_button: Button = %PauseButton
@onready var _debug_button: Button = %DebugButton
@onready var _vignette: ColorRect = %BurnVignette
@onready var _countdown: Label = %CountdownLabel
@onready var _hint: Label = %HintLabel
@onready var _sun_control: SunControl = %SunControl

var _bus: Node
var _hint_tween: Tween

func inject_services(registry: Node) -> void:
	if not registry:
		return
	super.inject_services(registry)
	_bus = registry.get_service(&"bus") as Node
	_connect_bus()

func _on_ready() -> void:
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_pause_button.pressed.connect(func() -> void: pause_requested.emit())
	_debug_button.pressed.connect(func() -> void: debug_toggle_requested.emit())
	_countdown.hide()
	_hint.modulate.a = 0.0
	_on_exposure_changed(0.0)
	_on_distance_changed(0.0)

func _exit_tree() -> void:
	if get_viewport().size_changed.is_connected(_apply_safe_area):
		get_viewport().size_changed.disconnect(_apply_safe_area)
	if _bus:
		if _bus.sun_exposure_changed.is_connected(_on_exposure_changed):
			_bus.sun_exposure_changed.disconnect(_on_exposure_changed)
		if _bus.distance_changed.is_connected(_on_distance_changed):
			_bus.distance_changed.disconnect(_on_distance_changed)

func bind_sun(sun: SunRig) -> void:
	_sun_control.bind_sun(sun)

func set_controls_enabled(enabled: bool) -> void:
	_sun_control.set_controls_enabled(enabled)
	_pause_button.disabled = not enabled

func show_countdown(text: String) -> void:
	_countdown.text = text
	_countdown.show()
	_countdown.scale = Vector2.ONE * 1.4
	_countdown.pivot_offset = _countdown.size * 0.5
	var tw := create_tween()
	tw.tween_property(_countdown, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_countdown() -> void:
	_countdown.hide()

func show_hint(text: String, seconds: float = 3.5) -> void:
	_hint.text = text
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(_hint, "modulate:a", 1.0, 0.25)
	_hint_tween.tween_interval(seconds)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.4)

## Converts DisplayServer's safe area (window pixels) into viewport-space margins.
## Desktop windows have no insets, so only mobile reads the display safe area.
func _apply_safe_area() -> void:
	var left := min_safe_margin
	var top := min_safe_margin
	var right := min_safe_margin
	var bottom := min_safe_margin
	if PlatformUtils.is_mobile():
		var win := Vector2(DisplayServer.window_get_size())
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if win.x > 0.0 and win.y > 0.0 and safe.size.x > 0.0:
			var to_view := get_viewport_rect().size / win
			left = maxi(left, int(safe.position.x * to_view.x))
			top = maxi(top, int(safe.position.y * to_view.y))
			right = maxi(right, int((win.x - safe.end.x) * to_view.x))
			bottom = maxi(bottom, int((win.y - safe.end.y) * to_view.y))
	safe_area.add_theme_constant_override("margin_left", left)
	safe_area.add_theme_constant_override("margin_top", top)
	safe_area.add_theme_constant_override("margin_right", right)
	safe_area.add_theme_constant_override("margin_bottom", bottom)

func _connect_bus() -> void:
	if _bus == null:
		return
	if not _bus.sun_exposure_changed.is_connected(_on_exposure_changed):
		_bus.sun_exposure_changed.connect(_on_exposure_changed)
	if not _bus.distance_changed.is_connected(_on_distance_changed):
		_bus.distance_changed.connect(_on_distance_changed)

func _on_exposure_changed(value: float) -> void:
	if not is_node_ready():
		return
	_meter.set_value(value)
	(_vignette.material as ShaderMaterial).set_shader_parameter("strength", clampf(value / 100.0, 0.0, 1.0))

func _on_distance_changed(meters: float) -> void:
	if not is_node_ready():
		return
	_distance.text = "%d m" % int(meters)
