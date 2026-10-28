class_name ShadowDebugOverlay
extends Node3D

## F3 (or the optional "dbg" HUD button) toggles this overlay in DEBUG builds only;
## it starts hidden and cannot be opened in release builds.
## It shows the ShadeGrid's gameplay truth on top of the rendered level so the two can
## be compared at a glance:
##   * every cell as a small quad — GREEN walkable (shaded), ORANGE sunlit, GREY solid,
##     BLUE outline = the region Dracula can currently reach
##   * the path Dracula is following (white line) and ShadowSensor's foot rays
##     (green = shaded, red = lit)
##   * sun angles, grid size / variable cells, exposure, fps
## Rendered shadows and green cells must coincide; a red ray under a green cell = bug.
## Nodes live in ShadowDebugOverlay.tscn; at runtime only per-instance colours and the
## debug line geometry (ImmediateMesh) are written.
## PDF §4 CPU: _process runs only while the overlay is visible.

@export var draw_length: float = 6.0
@export var walkable_color: Color = Color(0.2, 0.95, 0.35, 0.45)
@export var lit_color: Color = Color(1.0, 0.55, 0.1, 0.35)
@export var solid_color: Color = Color(0.5, 0.5, 0.55, 0.45)
@export var region_color: Color = Color(0.3, 0.6, 1.0, 0.6)
@export var path_color: Color = Color.WHITE
@export var raw_path_color: Color = Color(0.6, 0.6, 0.6, 0.7)
## Draw raw grid path in grey alongside smoothed path in white (toggleable with F4).
@export var show_raw_path: bool = false
@export var cell_mesh: MultiMeshInstance3D
@export var ray_mesh: MeshInstance3D
@export var info_layer: CanvasLayer
@export var info_label: Label

var _grid: ShadeGrid
var _sensor: ShadowSensor
var _sun: SunRig
var _dracula: DraculaController
var _feature: Node   # ShadowRunFeature (current_path / region_mask getters)
var _cells_dirty: bool = true

func _ready() -> void:
	_set_shown(false)

func setup(grid: ShadeGrid, sensor: ShadowSensor, sun: SunRig, dracula: DraculaController, feature: Node) -> void:
	_grid = grid
	_sensor = sensor
	_sun = sun
	_dracula = dracula
	_feature = feature
	_cells_dirty = true

func mark_dirty() -> void:
	_cells_dirty = true

func toggle() -> void:
	if OS.is_debug_build():
		_set_shown(not visible)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_overlay"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if visible and event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_F4:
			show_raw_path = not show_raw_path
			get_viewport().set_input_as_handled()

func _set_shown(shown: bool) -> void:
	visible = shown
	info_layer.visible = shown
	set_process(shown)   # PDF §4
	_cells_dirty = true
	if not shown:
		(ray_mesh.mesh as ImmediateMesh).clear_surfaces()

func _process(_delta: float) -> void:
	if _grid == null or _grid.cols == 0:
		return
	if _cells_dirty:
		_cells_dirty = false
		_draw_cells()
	_draw_lines()
	info_label.text = "\n".join([
		"sun az %6.1f (target %6.1f)  el %4.1f" % [_sun.azimuth, _sun.target_azimuth, _sun.elevation],
		"grid %dx%d @ %.2fm  variable %d" % [_grid.cols, _grid.rows, _grid.cell_size, _grid.variable_cell_count()],
		"exposure %5.1f%%  lit points %d/%d" % [_sensor.exposure, roundi(_sensor.exposure_fraction * _sensor.debug_lit.size()), _sensor.debug_lit.size()],
		"fps %d  nodes %d" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)],
		"paths: white smoothed | [F4] raw grey: %s" % ["ON" if show_raw_path else "OFF"],
	])

func _draw_cells() -> void:
	var mm := cell_mesh.multimesh
	if mm.instance_count != _grid.cell_count():
		mm.instance_count = _grid.cell_count()
	var region: PackedByteArray = _feature.region_mask()
	for i in _grid.cell_count():
		@warning_ignore("integer_division")
		var c := Vector2i(i % _grid.cols, i / _grid.cols)
		var col := solid_color if _grid.is_solid(c) else (walkable_color if _grid.is_shaded(c) else lit_color)
		if region.size() == _grid.cell_count() and region[i] != 0:
			col = region_color
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * _grid.cell_size * 0.85), _grid.cell_center(c) + Vector3(0.0, 0.05, 0.0)))
		mm.set_instance_color(i, col)

func _draw_lines() -> void:
	var mesh := ray_mesh.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	if show_raw_path and _feature != null and _feature.has_method("raw_path"):
		var raw: PackedVector3Array = _feature.raw_path()
		var rprev := _dracula.global_position
		for p in raw:
			mesh.surface_set_color(raw_path_color)
			mesh.surface_add_vertex(rprev + Vector3(0.0, 0.08, 0.0))
			mesh.surface_add_vertex(p + Vector3(0.0, 0.08, 0.0))
			rprev = p
	var path: PackedVector3Array = _feature.current_path()
	var prev := _dracula.global_position
	for p in path:
		mesh.surface_set_color(path_color)
		mesh.surface_add_vertex(prev + Vector3(0.0, 0.12, 0.0))
		mesh.surface_add_vertex(p + Vector3(0.0, 0.12, 0.0))
		prev = p
	for i in _sensor.debug_from.size():
		var from := _sensor.debug_from[i]
		var dir := (_sensor.debug_to[i] - from).normalized()
		mesh.surface_set_color(Color.RED if _sensor.debug_lit[i] else Color.GREEN)
		mesh.surface_add_vertex(from)
		mesh.surface_add_vertex(from + dir * draw_length)
	# Keep the surface valid even with nothing to draw.
	mesh.surface_set_color(path_color)
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_end()
