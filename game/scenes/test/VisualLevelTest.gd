extends Node2D

@onready var player: PlayerController = $Player

func _ready() -> void:
	await get_tree().process_frame
	if player:
		player.die()
