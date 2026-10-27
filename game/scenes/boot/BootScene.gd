class_name BootScene
extends Node

## BootScene — Entry point bootstrap scene
## Initializes core services and transitions to Home.

@export var next_scene_path: String = "res://game/scenes/Home/Home.tscn"
@onready var services: Node = $GameService

func _ready() -> void:
	if services and services.logger:
		services.logger.info("Bootstrap sequence started...")
	
	# Transition to initial game scene / Home
	_transition_to_game()

func _transition_to_game() -> void:
	if services and services.scene and ResourceLoader.exists(next_scene_path):
		services.scene.go_to(next_scene_path)
	elif services and services.logger:
		services.logger.info("Bootstrap complete. Ready for gameplay scenes.")
