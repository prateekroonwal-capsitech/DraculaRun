class_name HomeScene
extends UIController

## HomeScene — Default landing scene transitioned to by BootScene.

## First puzzle level (a level-select screen can replace this later).
const FIRST_LEVEL_SCENE := "res://game/scenes/gameplay/shadow_run/levels/Level01.tscn"

## Level select panel opened by the Play button.
@export var level_select_panel: PackedScene = preload("res://game/scenes/ui/mfw/LevelSelectPanel.tscn")

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
	if _save and _save.get_level() > 1:
		sub_label.text = "Levels cleared: %d" % (_save.get_level() - 1)

func _on_play_pressed() -> void:
	if _ui_manager and level_select_panel:
		_ui_manager.push_packed(level_select_panel)
	elif _scene:
		play_button.disabled = true
		_scene.go_to(FIRST_LEVEL_SCENE)
