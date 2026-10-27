class_name ProgressionFeature
extends GameFeature

## Optional progression feature. Keeps level rules outside SaveManager.

var _save: SaveManager

func initialize(dependencies: Dictionary) -> void:
	super.initialize(dependencies)
	_save = dependencies.get("save") as SaveManager
	if _save == null:
		push_error("ProgressionFeature: missing 'save' dependency")

func current_level() -> int:
	return _save.get_level() if _save else 1

func complete_level(level: int, stars: int = 3, xp_reward: int = 150) -> void:
	if _save:
		_save.complete_level(level, stars, xp_reward)
