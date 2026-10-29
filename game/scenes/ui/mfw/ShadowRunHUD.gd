class_name ShadowRunHUD
extends UIController

## In-level HUD (portrait): top bar (~10%: pause, level name), play view (the level;
## taps / drags here move Dracula; only transient labels) and ONE sun control (SunInput):
##   * joystick mode: the play view runs to the bottom edge, SunJoystick floats bottom-right;
##   * slider mode: the SunControl strip takes the bottom ~15%, the play view ends above it.
## set_sun_mode() switches instantly; ShadowRunFeature picks the mode (saved setting). Layout is containers + stretch ratios in ShadowRunHUD.tscn; this script
## The SafeArea node is a SafeAreaMargin (ui/common): notch / gesture-bar insets + padding.
## Listens to GameBus for exposure (drives the burn vignette only); everything else is called directly by ShadowRunFeature.
## All non-button controls use MOUSE_FILTER_IGNORE so desktop clicks reach the feature.

signal pause_requested
signal debug_toggle_requested
## Forwarded from SunJoystick: a finger / mouse / Q-E-R-F key started or stopped moving the sun.
signal sun_drag_started
signal sun_drag_ended

## Show the faint "dbg" button (toggles the F3 overlay). Only ever shown in debug builds.
@export var show_debug_button: bool = false
## Play view stretch ratio per sun mode (top bar 10, strip 15).
@export var play_view_ratio_joystick: float = 90.0
@export var play_view_ratio_slider: float = 75.0

@onready var _level_label: Label = %LevelLabel
@onready var _pause_button: Button = %PauseButton
@onready var _debug_button: Button = %DebugButton
@onready var _vignette: ColorRect = %BurnVignette
@onready var _title: Label = %TitleLabel
@onready var _hint: Label = %HintLabel
@onready var _play_view: Control = %PlayView
@onready var _joystick: SunJoystick = %SunJoystick
@onready var _strip: SunControl = %SunControl

var _bus: Node
var _hint_tween: Tween
var _mode: SunInput.Mode = SunInput.Mode.JOYSTICK
var _controls_enabled: bool = true
var _title_tween: Tween

func inject_services(registry: Node) -> void:
	if not registry:
		return
	super.inject_services(registry)
	_bus = registry.get_service(&"bus") as Node
	if _bus and not _bus.sun_exposure_changed.is_connected(_on_exposure_changed):
		_bus.sun_exposure_changed.connect(_on_exposure_changed)

func _on_ready() -> void:
	_pause_button.pressed.connect(func() -> void: pause_requested.emit())
	_debug_button.pressed.connect(func() -> void: debug_toggle_requested.emit())
	_debug_button.visible = show_debug_button and OS.is_debug_build()
	for control: SunInput in [_joystick, _strip]:
		control.drag_started.connect(func() -> void: sun_drag_started.emit())
		control.drag_ended.connect(func() -> void: sun_drag_ended.emit())
	set_sun_mode(_mode)
	_title.hide()
	_hint.modulate.a = 0.0
	_on_exposure_changed(0.0)

func _exit_tree() -> void:
	if _bus and _bus.sun_exposure_changed.is_connected(_on_exposure_changed):
		_bus.sun_exposure_changed.disconnect(_on_exposure_changed)

func bind_sun(sun: SunRig) -> void:
	_joystick.bind_sun(sun)
	_strip.bind_sun(sun)

func set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled
	active_sun_input().set_controls_enabled(enabled)
	_pause_button.disabled = not enabled

func set_level_title(title: String, number: int) -> void:
	_level_label.text = "%d · %s" % [number, title]

## True when a viewport position is inside the play view and not on the sun joystick
## (taps / drags elsewhere are ignored).
func is_in_play_view(viewport_pos: Vector2) -> bool:
	return _play_view.get_global_rect().has_point(viewport_pos) and not active_sun_input().contains(viewport_pos)

func get_play_view_rect() -> Rect2:
	return _play_view.get_global_rect() if _play_view else get_viewport().get_visible_rect()

func get_joystick() -> SunJoystick:
	return _joystick

func get_strip() -> SunControl:
	return _strip

func active_sun_input() -> SunInput:
	return _joystick if _mode == SunInput.Mode.JOYSTICK else _strip

func get_sun_mode() -> SunInput.Mode:
	return _mode

## Show / enable one sun control, hide / disable the other, and resize the play view.
func set_sun_mode(mode: SunInput.Mode) -> void:
	_mode = mode
	var joystick := mode == SunInput.Mode.JOYSTICK
	var off: SunInput = _strip if joystick else _joystick
	off.set_controls_enabled(false)   # ends a held interaction (emits drag_ended)
	off.visible = false
	_joystick.visible = joystick
	_strip.visible = not joystick
	_play_view.size_flags_stretch_ratio = play_view_ratio_joystick if joystick else play_view_ratio_slider
	active_sun_input().set_controls_enabled(_controls_enabled)

func play_sun_blocked() -> void:
	active_sun_input().play_blocked()

func show_title(text: String, seconds: float) -> void:
	_title.text = text
	_title.show()
	_title.modulate.a = 1.0
	if _title_tween:
		_title_tween.kill()
	_title_tween = create_tween()
	_title_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_title_tween.tween_interval(seconds)
	_title_tween.tween_property(_title, "modulate:a", 0.0, 0.4)
	_title_tween.tween_callback(_title.hide)

func show_hint(text: String, seconds: float = 3.5) -> void:
	_hint.text = text
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hint_tween.tween_property(_hint, "modulate:a", 1.0, 0.25)
	_hint_tween.tween_interval(seconds)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.4)

func _on_exposure_changed(value: float) -> void:
	if not is_node_ready():
		return
	(_vignette.material as ShaderMaterial).set_shader_parameter("strength", clampf(value / 100.0, 0.0, 1.0))
