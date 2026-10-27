class_name TrackSegment
extends Node3D

## A pooled 30 m road segment (lanes per LaneConfig; 3 by default). The segment origin is its start edge;
## the road runs from local z = 0 to z = -length (the run direction is −Z).
##
## Authoring rules (enforced by SegmentValidator):
##   * Every shadow-casting mesh has a matching collision shape on the
##     `shadow_caster` layer (props in props/casters already do).
##   * Declare at least one SegmentSafeWindow (lane + sun-angle box that is shaded).
##   * The segment must be solvable, no lane may be safe at every sun angle, and
##     no single fixed sun angle may solve the whole segment.
##   * Children of OptionalObstacles are toggled by the spawner for density.

@export var segment_id: StringName = &""
@export var length: float = 30.0
## 0 = easiest. The spawner only offers segments up to the current difficulty.
@export_range(0.0, 1.0) var difficulty: float = 0.0
## Eligible during the onboarding stretch (first ~30 s).
@export var onboarding: bool = false
@export var weight: float = 1.0
@export var safe_windows: Array[SegmentSafeWindow] = []
## If true the validator also demands that no fixed sun angle solves the segment
## (the sun must move *within* the segment).
@export var requires_sun_move: bool = false
@export_multiline var design_notes: String = ""

@onready var _optional: Node3D = get_node_or_null("OptionalObstacles") as Node3D

## Pooled segments are hidden and disabled. PROCESS_MODE_DISABLED also removes
## their physics bodies from the space (CollisionObject3D DISABLE_MODE_REMOVE).
## PDF §4 CPU: nothing in the pool ticks or collides.
func set_pooled(pooled: bool) -> void:
	visible = not pooled
	process_mode = Node.PROCESS_MODE_DISABLED if pooled else Node.PROCESS_MODE_INHERIT

func set_optional_obstacles_enabled(enabled: bool) -> void:
	if _optional == null:
		return
	for child in _optional.get_children():
		_set_node_enabled(child, enabled)

## Enables each optional obstacle independently with probability `density`.
func roll_optional_obstacles(density: float, rng: RandomNumberGenerator) -> void:
	if _optional == null:
		return
	for child in _optional.get_children():
		_set_node_enabled(child, rng.randf() < density)

## Azimuth the segment wants on entry / exit (from the first / last safe window).
func entry_azimuth() -> float:
	return safe_windows[0].azimuth_center() if not safe_windows.is_empty() else 0.0

func exit_azimuth() -> float:
	return safe_windows[safe_windows.size() - 1].azimuth_center() if not safe_windows.is_empty() else 0.0

func _set_node_enabled(node: Node, enabled: bool) -> void:
	if node is Node3D:
		(node as Node3D).visible = enabled
	node.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
