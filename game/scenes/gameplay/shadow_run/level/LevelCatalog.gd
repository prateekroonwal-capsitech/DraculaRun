class_name LevelCatalog
extends Resource

## LevelCatalog — Data-driven registry of puzzle levels.
## Adding a new level requires only a new entry here, no code changes.

const LevelCatalogEntry = preload("res://game/scenes/gameplay/shadow_run/level/LevelCatalogEntry.gd")

@export var entries: Array[LevelCatalogEntry] = []
## Entry ids in the order the levels had when progress was still saved by position
## (save format v1: "stage_N" = the N-th id here). LevelProgress.migrate() uses it once to
## move old saves onto ids. Never reorder or edit it; add new levels to `entries` only.
@export var legacy_v1_order: PackedStringArray = PackedStringArray()

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
	var clean := scene_path.trim_suffix(".remap")
	var file_name := clean.get_file()
	for entry in entries:
		if entry:
			if entry.scene_path == scene_path or entry.scene_path.trim_suffix(".remap") == clean:
				return entry
			if file_name != "" and entry.scene_path.get_file() == file_name:
				return entry
	return null

func get_index_by_scene(scene_path: String) -> int:
	var clean := scene_path.trim_suffix(".remap")
	var file_name := clean.get_file()
	for i in range(entries.size()):
		if entries[i]:
			if entries[i].scene_path == scene_path or entries[i].scene_path.trim_suffix(".remap") == clean:
				return i
			if file_name != "" and entries[i].scene_path.get_file() == file_name:
				return i
	return -1

func get_next_scene(current_scene: String) -> String:
	var idx := get_index_by_scene(current_scene)
	if idx >= 0 and idx + 1 < entries.size() and entries[idx + 1]:
		return entries[idx + 1].scene_path
	return ""
