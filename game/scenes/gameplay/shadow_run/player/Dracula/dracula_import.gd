@tool
extends EditorScenePostImport

## Post-import script for dracula.glb (Import dock → Import Script). Godot's per-animation
## import options have no "skip" switch, so only the clips the game uses are kept here,
## at import time; every other clip in the .glb never reaches the imported scene, the
## AnimationPlayer or the AnimationTree. Editor-only; never runs in the game.

const KEPT_CLIPS: PackedStringArray = ["Idle", "Walk", "Run"]

func _post_import(scene: Node) -> Object:
	for player in scene.find_children("*", "AnimationPlayer", true, false):
		var ap := player as AnimationPlayer
		for lib_name in ap.get_animation_library_list():
			var lib := ap.get_animation_library(lib_name)
			for clip in lib.get_animation_list():
				if not KEPT_CLIPS.has(String(clip)):
					lib.remove_animation(clip)
	return scene
