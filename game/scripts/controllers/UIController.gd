class_name UIController
extends Control

# UIController — base class for every screen/panel.
# Dependencies are supplied by the feature or UI composition root.

var _ui_manager:   UIManager
var _audio:        AudioManager
var _game_manager: GameManager
var _initialized:  bool = false

func _ready() -> void:
	# UI screens don't need per-frame ticking by default.
	set_process(false)
	set_physics_process(false)
	if _ui_manager != null and not _initialized:
		_initialized = true
		_on_ready()

## Convention-based auto-wiring for visually placed scenes (Pattern 2).
func inject_services(registry: Node) -> void:
	if not registry:
		return
	inject_dependencies(
		registry.get_service(&"ui") as UIManager,
		registry.get_service(&"audio") as AudioManager,
		registry.get_service(&"game") as GameManager
	)

func inject_dependencies(ui_manager: UIManager, audio: AudioManager, game_manager: GameManager) -> void:
	_ui_manager = ui_manager
	_audio = audio
	_game_manager = game_manager
	if is_inside_tree() and not _initialized:
		_initialized = true
		_on_ready()

## Override this instead of _ready() — dependencies are already injected.
func _on_ready() -> void:
	pass

## Closes this panel. UIManager.pop() calls queue_free() immediately (PDF §5).
func close() -> void:
	_ui_manager.pop()
