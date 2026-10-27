class_name ShadowDebugOverlay
extends Node3D

## F3 (or the faint "dbg" HUD button) toggles this overlay; it starts hidden.
## It draws ShadowSensor's sample rays toward the sun — GREEN = blocked by a shadow
## caster (shaded), RED = reaches the sky (lit) — and lists exposure, sun angles,
## speed and the current segment, plus a marker line down the center of every lane
## (from LaneConfig; Dracula's current lane is highlighted). Use it to confirm rendered shadows and gameplay
## shade agree: when Dracula's body sits in a visible shadow every ray must be green.
## The nodes live in ShadowDebugOverlay.tscn; the only thing built at runtime is the
## per-frame ray line geometry (debug-only ImmediateMesh surfaces).
## PDF §4 CPU: _process runs only while the overlay is visible.

## Drawn ray length (the sensor itself uses ShadowSensor.ray_length).
@export var draw_length: float = 9.0
@export var shaded_color: Color = Color.GREEN
@export var lit_color: Color = Color.RED
## Lane layout (track/lane_config.tres) for the lane-center markers.
@export var lanes: LaneConfig
@export var lane_color: Color = Color(0.3, 0.8, 1.0, 0.8)
@export var current_lane_color: Color = Color(1.0, 1.0, 0.3, 1.0)
## How far ahead of Dracula the lane markers are drawn, meters.
@export var lane_marker_length: float = 40.0
@export var ray_mesh: MeshInstance3D
@export var info_layer: CanvasLayer
@export var info_label: Label

var _sensor: ShadowSensor
var _sun: SunRig
var _dracula: DraculaController
var _spawner: TrackSpawner
var _feature: Node   # ShadowRunFeature (speed / run time / distance getters)

func _ready() -> void:
	_set_shown(false)

func setup(sensor: ShadowSensor, sun: SunRig, dracula: DraculaController, spawner: TrackSpawner, feature: Node) -> void:
	_sensor = sensor
	_sun = sun
	_dracula = dracula
	_spawner = spawner
	_feature = feature

func toggle() -> void:
	_set_shown(not visible)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_overlay"):
		toggle()
		get_viewport().set_input_as_handled()

func _set_shown(shown: bool) -> void:
	visible = shown
	info_layer.visible = shown
	set_process(shown)   # PDF §4
	if not shown:
		(ray_mesh.mesh as ImmediateMesh).clear_surfaces()

func _process(_delta: float) -> void:
	if _sensor == null:
		return
	var mesh := ray_mesh.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	if lanes and _dracula:
		var z := _dracula.global_position.z
		for i in lanes.lane_count:
			var x := lanes.lane_x(i)
			mesh.surface_set_color(current_lane_color if i == _dracula.get_lane() else lane_color)
			mesh.surface_add_vertex(Vector3(x, 0.05, z + 2.0))
			mesh.surface_add_vertex(Vector3(x, 0.05, z - lane_marker_length))
	if not _sensor.debug_from.is_empty():
		for i in _sensor.debug_from.size():
			var from := _sensor.debug_from[i]
			var dir := (_sensor.debug_to[i] - from).normalized()
			mesh.surface_set_color(lit_color if _sensor.debug_lit[i] else shaded_color)
			mesh.surface_add_vertex(from)
			mesh.surface_add_vertex(from + dir * draw_length)
	mesh.surface_end()
	var seg := _spawner.segment_at(_dracula.global_position.z) if _spawner else null
	info_label.text = "\n".join([
		"exposure %5.1f%%  lit %d/%d" % [_sensor.exposure, roundi(_sensor.exposure_fraction * _sensor.debug_lit.size()), _sensor.debug_lit.size()],
		"sun az %6.1f el %5.1f (target %6.1f / %5.1f)" % [_sun.azimuth, _sun.elevation, _sun.target_azimuth, _sun.target_elevation],
		"speed %5.2f m/s  t %6.1f s  d %7.1f m" % [_feature.current_speed(), _feature.run_time(), _feature.distance()],
		"lane %d/%d  segment %s" % [_dracula.get_lane(), lanes.lane_count - 1 if lanes else 0, String(seg.segment_id) if seg else "-"],
		"fps %d  nodes %d" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)],
	])
