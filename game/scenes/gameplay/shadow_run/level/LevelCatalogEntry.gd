class_name LevelCatalogEntry
extends Resource

## LevelCatalogEntry — Single level entry in the LevelCatalog.

@export var id: String = ""
@export var display_name: String = ""
@export_file("*.tscn") var scene_path: String = ""
@export var thumbnail: Texture2D = null
