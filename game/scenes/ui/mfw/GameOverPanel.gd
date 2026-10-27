class_name GameOverPanel
extends UIController

## Game Over panel (pushed by ShadowRunFeature through UIManager.push_packed).
## Dumb view: shows results and emits intents; the feature owns scene changes.

signal retry_requested
signal home_requested

@onready var _title: Label = %Title
@onready var _distance: Label = %Distance
@onready var _best: Label = %Best
@onready var _retry: Button = %RetryButton
@onready var _home: Button = %HomeButton

func _ready() -> void:
	super._ready()
	process_mode = Node.PROCESS_MODE_ALWAYS

func _on_ready() -> void:
	_retry.pressed.connect(func() -> void: retry_requested.emit())
	_home.pressed.connect(func() -> void: home_requested.emit())
	_retry.grab_focus.call_deferred()

func show_results(distance_m: float, best_m: float, is_new_best: bool, cause: String) -> void:
	_title.text = "BURNED TO ASH" if cause == "sunlight" else "CRASHED"
	_distance.text = "Distance  %d m" % int(distance_m)
	_best.text = ("NEW BEST!  %d m" if is_new_best else "Best  %d m") % int(best_m)
	_best.modulate = Color(1.0, 0.8, 0.3) if is_new_best else Color.WHITE
