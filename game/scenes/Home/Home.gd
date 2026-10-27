class_name HomeScene
extends UIController

## HomeScene — Default landing scene transitioned to by BootScene.

const SHADOW_RUN_SCENE := "res://game/scenes/gameplay/shadow_run/ShadowRun.tscn"

@onready var label: Label = $CenterContainer/VBoxContainer/Label
@onready var sub_label: Label = $CenterContainer/VBoxContainer/SubLabel
@onready var play_button: Button = %PlayButton

var _logger: Node
var _scene: SceneManager
var _save: SaveManager

## Convention-based auto-wiring for visually placed scenes (Pattern 2).
func inject_services(registry: Node) -> void:
	if not registry:
		return
	# 1. Base class (UIController) ke core services inject karo:
	# (_ui_manager, _audio, _game_manager, _save, _bus)
	super.inject_services(registry)

	# 2. HomeScene-specific extra services lo:
	_logger = registry.get_service(&"logger") as Node
	_scene = registry.get_service(&"scene") as SceneManager
	_save = registry.get_service(&"save") as SaveManager


##_on_ready() use
func _on_ready() -> void:
	if _logger:
		_logger.info("HomeScene loaded successfully.")
	play_button.pressed.connect(_on_play_pressed)
	play_button.grab_focus.call_deferred()
	if _save and _save.stats_data:
		var best := float(_save.stats_data.custom.get("best_distance", 0.0))
		var runs := _save.stats_data.matches_played
		sub_label.text = "Best  %d m   ·   Runs  %d" % [int(best), runs] if runs > 0 else "Stay in the shade."

func _on_play_pressed() -> void:
	play_button.disabled = true
	if _scene:
		_scene.go_to(SHADOW_RUN_SCENE)
