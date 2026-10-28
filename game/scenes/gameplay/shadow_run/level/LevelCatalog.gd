class_name LevelCatalog
extends Resource

## LevelCatalog — Data-driven registry of puzzle levels.
## Adding a new level requires only a new entry here, no code changes.

const LevelCatalogEntry = preload("res://game/scenes/gameplay/shadow_run/level/LevelCatalogEntry.gd")

@export var entries: Array[LevelCatalogEntry] = []

func get_level_count() -> int:
	return entries.size()

func get_entry(index: int) -> LevelCatalogEntry:
	if index >= 0 and index < entries.size():
		return entries[index]
	return null

func get_entry_by_id(id: String) -> LevelCatalogEntry:
	for entry in entries:
		if entry and entry.id == id:
			return entry
	return null

func get_entry_by_scene(scene_path: String) -> LevelCatalogEntry:
	for entry in entries:
		if entry and entry.scene_path == scene_path:
			return entry
	return null

func get_index_by_scene(scene_path: String) -> int:
	for i in range(entries.size()):
		if entries[i] and entries[i].scene_path == scene_path:
			return i
	return -1

func get_next_scene(current_scene: String) -> String:
	var idx := get_index_by_scene(current_scene)
	if idx >= 0 and idx + 1 < entries.size() and entries[idx + 1]:
		return entries[idx + 1].scene_path
	return ""
