class_name GameOverPanel
extends UIController

## Game Over panel (pushed by ShadowRunFeature through UIManager.push_packed).
## Dumb view: shows which level was lost and emits intents; the feature owns scene changes.

signal retry_requested
signal home_requested

@onready var _title: Label = %Title
@onready var _level: Label = %Subtitle
@onready var _detail: Label = %Detail
@onready var _retry: Button = %RetryButton
@onready var _home: Button = %HomeButton

func _ready() -> void:
	super._ready()
	process_mode = Node.PROCESS_MODE_ALWAYS

func _on_ready() -> void:
	_retry.pressed.connect(func() -> void: retry_requested.emit())
	_home.pressed.connect(func() -> void: home_requested.emit())
	_retry.grab_focus.call_deferred()

func show_results(level_title: String, level_number: int, cause: String) -> void:
	_title.text = "BURNED TO ASH" if cause == "sunlight" else ("CAUGHT!" if cause == "caught" else "DEFEATED")
	_level.text = "Level %d · %s" % [level_number, level_title]
	_detail.text = "Hide until the villagers pass." if cause == "caught" else "Stay in the shadows."
