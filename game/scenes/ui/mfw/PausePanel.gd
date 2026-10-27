class_name PausePanel
extends UIController

## Pause panel. Runs while the tree is paused (PROCESS_MODE_ALWAYS).
## Resume is handled here (GameManager.resume + close); leaving the run is an
## intent for ShadowRunFeature, which owns scene changes.
## The "Sun control: Joystick / Slider" switch is a dumb view: it shows the mode the
## feature passes in and emits the player's choice; the feature applies and saves it.

signal home_requested
signal sun_mode_changed(mode: SunInput.Mode)

@onready var _resume: Button = %ResumeButton
@onready var _home: Button = %HomeButton
@onready var _joystick_toggle: Button = %JoystickToggle
@onready var _slider_toggle: Button = %SliderToggle

func _ready() -> void:
	super._ready()
	# Keeps this UI receiving input while the scene tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _on_ready() -> void:
	_resume.pressed.connect(_on_resume_pressed)
	_home.pressed.connect(func() -> void: home_requested.emit())
	_joystick_toggle.pressed.connect(func() -> void: sun_mode_changed.emit(SunInput.Mode.JOYSTICK))
	_slider_toggle.pressed.connect(func() -> void: sun_mode_changed.emit(SunInput.Mode.SLIDER))
	_resume.grab_focus.call_deferred()

## Shows the current mode (no signal).
func set_sun_mode(mode: SunInput.Mode) -> void:
	_joystick_toggle.set_pressed_no_signal(mode == SunInput.Mode.JOYSTICK)
	_slider_toggle.set_pressed_no_signal(mode == SunInput.Mode.SLIDER)

## Test hook: choose a mode as if its toggle was tapped.
func choose_sun_mode(mode: SunInput.Mode) -> void:
	(_joystick_toggle if mode == SunInput.Mode.JOYSTICK else _slider_toggle).pressed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if _initialized and event.is_action_pressed("pause_run"):
		get_viewport().set_input_as_handled()
		_on_resume_pressed()

func _on_resume_pressed() -> void:
	if _game_manager:
		_game_manager.resume()
	close()
