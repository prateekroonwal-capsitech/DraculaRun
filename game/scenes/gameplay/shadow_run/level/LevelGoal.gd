class_name LevelGoal
extends Area3D

## LevelGoal — the level's exit (props/goal/CryptDoor.tscn). Fires `reached` when
## Dracula's body enters the area. `set_connected(true)` lights the glow ring when
## the shadow region Dracula stands in reaches the goal.

signal reached

## Glow shown while a shaded route to the goal exists.
@export var connected_glow: Node3D
## Seconds for the glow to fade in/out.
@export var glow_fade_time: float = 0.25

var _connected: bool = false
var _tween: Tween

func _ready() -> void:
	body_entered.connect(func(_body: Node3D) -> void: reached.emit())
	if connected_glow:
		connected_glow.visible = false
		connected_glow.scale = Vector3.ONE * 0.6

func set_connected(on: bool) -> void:
	if on == _connected or connected_glow == null:
		return
	_connected = on
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	if on:
		connected_glow.visible = true
		_tween.tween_property(connected_glow, "scale", Vector3.ONE, glow_fade_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_tween.tween_property(connected_glow, "scale", Vector3.ONE * 0.6, glow_fade_time)
		_tween.tween_callback(func() -> void: connected_glow.visible = false)
