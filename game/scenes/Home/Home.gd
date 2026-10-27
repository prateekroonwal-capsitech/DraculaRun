class_name HomeScene
extends UIController

## HomeScene — Default landing scene transitioned to by BootScene.

@onready var label: Label = $CenterContainer/VBoxContainer/Label
@onready var sub_label: Label = $CenterContainer/VBoxContainer/SubLabel

var _logger: Node
var _scene: SceneManager

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


##_on_ready() use 
func _on_ready() -> void:
	if _logger:
		_logger.info("HomeScene loaded successfully.")
	
	# Example usage:
	# if label:
	#     label.text = "Welcome!"
