class_name HideSpot
extends Node3D

## HideSpot — a prop Dracula can slip into (barrels, haystack, covered cart, crate stack).
## Tapping the HideZone (physics layer 5 "hide_spot"), or ending a drag on it, sends him
## along the normal shade path to `entry`; there he hides: villagers can't see him and
## the sun can't burn him. ShadowRunFeature owns the hide / leave flow; this node only
## describes the spot and runs its own timer and icon.
##
## Scene contract (see props/village/hide/*.tscn):
##   HideZone (Area3D, layer 5, monitorable)  covers the prop and its entry, used for taps
##   Entry (Marker3D)                         a non-solid ground point beside the prop
##   EntryMarker (MeshInstance3D)             dashed ground ring at Entry (hide_marker.tres)
##   HiddenIcon (MeshInstance3D)              billboard shown while he hides (hidden_icon.tres)

## The hide time ran out: the feature pushes Dracula back out at `entry`.
signal expired

const HIDE_LAYER_BIT: int = 1 << 4   # project layer 5 "hide_spot"

## Seconds he may stay hidden here. 0 = unlimited.
@export var max_hide_time: float = 0.0
## Fade time of the hidden icon (s).
@export var icon_fade_time: float = 0.2

@export_group("Scene parts")
@export var hide_zone: Area3D
@export var entry: Marker3D
@export var entry_marker: MeshInstance3D
@export var hidden_icon: MeshInstance3D

var _occupied: bool = false
var _time_left: float = 0.0
var _icon_tween: Tween

func _ready() -> void:
	set_process(false)
	if hidden_icon:
		hidden_icon.visible = false
		hidden_icon.set_instance_shader_parameter("time_left", 1.0)

## Ground point Dracula walks to before hiding.
func entry_position() -> Vector3:
	return entry.global_position if entry else global_position

func is_occupied() -> bool:
	return _occupied

## 0..1 of the max hide time left (1 when unlimited).
func time_left_fraction() -> float:
	if max_hide_time <= 0.0:
		return 1.0
	return clampf(_time_left / max_hide_time, 0.0, 1.0)

## Called by ShadowRunFeature when Dracula hides here (true) or leaves (false).
func set_occupied(on: bool) -> void:
	if on == _occupied:
		return
	_occupied = on
	_time_left = max_hide_time
	set_process(on and max_hide_time > 0.0)
	if entry_marker:
		entry_marker.visible = not on
	if hidden_icon == null:
		return
	if _icon_tween and _icon_tween.is_valid():
		_icon_tween.kill()
	hidden_icon.set_instance_shader_parameter("time_left", 1.0)
	if on:
		hidden_icon.visible = true
		hidden_icon.set_instance_shader_parameter("icon_alpha", 0.0)
	_icon_tween = create_tween()
	_icon_tween.tween_method(func(a: float) -> void: hidden_icon.set_instance_shader_parameter("icon_alpha", a),
		0.0 if on else 1.0, 1.0 if on else 0.0, icon_fade_time)
	if not on:
		_icon_tween.tween_callback(func() -> void: hidden_icon.visible = false)

func _process(delta: float) -> void:
	_time_left -= delta
	if hidden_icon:
		hidden_icon.set_instance_shader_parameter("time_left", time_left_fraction())
	if _time_left <= 0.0:
		set_process(false)
		expired.emit()
