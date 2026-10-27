class_name ShadowRunHUD
extends UIController

## In-level HUD (portrait): top bar (~10%: pause, level, exposure meter), play view
## (~75%: the level; taps here move Dracula; only transient labels) and the SunControl
## strip (~15%). Layout is containers + stretch ratios in ShadowRunHUD.tscn; this script
## pads the SafeArea container by the device's safe-area insets (notch / home indicator).
## Listens to GameBus for exposure; everything else is called directly by ShadowRunFeature.
## All non-button controls use MOUSE_FILTER_IGNORE so desktop clicks reach the feature.

signal pause_requested
signal debug_toggle_requested
## Forwarded from SunControl: a finger / mouse / Q-E key started or stopped moving the sun.
signal sun_drag_started
signal sun_drag_ended

## MarginContainer padded with the display safe area (mobile only).
@export var safe_area: MarginContainer
## Minimum padding in viewport pixels, even on devices without insets.
@export var min_safe_margin: int = 0
## Show the faint "dbg" button (toggles the F3 overlay). Only ever shown in debug builds.
@export var show_debug_button: bool = false

@onready var _meter: ExposureMeter = %ExposureMeter
@onready var _level_label: Label = %LevelLabel
@onready var _pause_button: Button = %PauseButton
@onready var _debug_button: Button = %DebugButton
@onready var _vignette: ColorRect = %BurnVignette
@onready var _title: Label = %TitleLabel
@onready var _hint: Label = %HintLabel
@onready var _play_view: Control = %PlayView
@onready var _sun_control: SunControl = %SunControl

var _bus: Node
var _hint_tween: Tween
var _title_tween: Tween

func inject_services(registry: Node) -> void:
	if not registry:
		return
	super.inject_services(registry)
	_bus = registry.get_service(&"bus") as Node
	if _bus and not _bus.sun_exposure_changed.is_connected(_on_exposure_changed):
		_bus.sun_exposure_changed.connect(_on_exposure_changed)

func _on_ready() -> void:
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_pause_button.pressed.connect(func() -> void: pause_requested.emit())
	_debug_button.pressed.connect(func() -> void: debug_toggle_requested.emit())
	_debug_button.visible = show_debug_button and OS.is_debug_build()
	_sun_control.drag_started.connect(func() -> void: sun_drag_started.emit())
	_sun_control.drag_ended.connect(func() -> void: sun_drag_ended.emit())
	_title.hide()
	_hint.modulate.a = 0.0
	_on_exposure_changed(0.0)

func _exit_tree() -> void:
	if get_viewport().size_changed.is_connected(_apply_safe_area):
		get_viewport().size_changed.disconnect(_apply_safe_area)
	if _bus and _bus.sun_exposure_changed.is_connected(_on_exposure_changed):
		_bus.sun_exposure_changed.disconnect(_on_exposure_changed)

func bind_sun(sun: SunRig) -> void:
	_sun_control.bind_sun(sun)

func set_controls_enabled(enabled: bool) -> void:
	_sun_control.set_controls_enabled(enabled)
	_pause_button.disabled = not enabled

func set_level_title(title: String, number: int) -> void:
	_level_label.text = "%d · %s" % [number, title]

## True when a viewport position is inside the play view (taps elsewhere are ignored).
func is_in_play_view(viewport_pos: Vector2) -> bool:
	return _play_view.get_global_rect().has_point(viewport_pos)

func play_sun_blocked() -> void:
	_sun_control.play_blocked()

func show_title(text: String, seconds: float) -> void:
	_title.text = text
	_title.show()
	_title.modulate.a = 1.0
	if _title_tween:
		_title_tween.kill()
	_title_tween = create_tween()
	_title_tween.tween_interval(seconds)
	_title_tween.tween_property(_title, "modulate:a", 0.0, 0.4)
	_title_tween.tween_callback(_title.hide)

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

func _on_exposure_changed(value: float) -> void:
	if not is_node_ready():
		return
	_meter.set_value(value)
	(_vignette.material as ShaderMaterial).set_shader_parameter("strength", clampf(value / 100.0, 0.0, 1.0))
