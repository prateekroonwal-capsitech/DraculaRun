class_name PausePanel
extends UIController

## Pause panel. Runs while the tree is paused (PROCESS_MODE_ALWAYS).
## Resume is handled here (GameManager.resume + close); leaving the run is an
## intent for ShadowRunFeature, which owns scene changes.

signal home_requested

@onready var _resume: Button = %ResumeButton
@onready var _home: Button = %HomeButton

func _ready() -> void:
	super._ready()
	# Keeps this UI receiving input while the scene tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _on_ready() -> void:
	_resume.pressed.connect(_on_resume_pressed)
	_home.pressed.connect(func() -> void: home_requested.emit())
	_resume.grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if _initialized and event.is_action_pressed("pause_run"):
		get_viewport().set_input_as_handled()
		_on_resume_pressed()

func _on_resume_pressed() -> void:
	if _game_manager:
		_game_manager.resume()
	close()
