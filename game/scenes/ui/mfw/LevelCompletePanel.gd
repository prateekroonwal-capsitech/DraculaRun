class_name LevelCompletePanel
extends UIController

## Level Complete panel (pushed by ShadowRunFeature through UIManager.push_packed).
## Dumb view: shows the result and emits intents; the feature owns scene changes.

signal next_requested
signal retry_requested
signal home_requested

@onready var _level: Label = %Subtitle
@onready var _next: Button = %NextButton
@onready var _retry: Button = %RetryButton
@onready var _home: Button = %HomeButton

func _ready() -> void:
	super._ready()
	process_mode = Node.PROCESS_MODE_ALWAYS

func _on_ready() -> void:
	_next.pressed.connect(func() -> void: next_requested.emit())
	_retry.pressed.connect(func() -> void: retry_requested.emit())
	_home.pressed.connect(func() -> void: home_requested.emit())
	_next.grab_focus.call_deferred()

func show_result(level_title: String, level_number: int, has_next: bool) -> void:
	_level.text = "Level %d · %s" % [level_number, level_title]
	_next.text = "Next" if has_next else "Finish"
