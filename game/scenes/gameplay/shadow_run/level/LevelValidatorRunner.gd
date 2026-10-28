extends Node3D

## Level validator. Run LevelValidatorRunner.tscn with F6, or headless:
##   godot --headless --path . res://game/scenes/gameplay/shadow_run/level/LevelValidatorRunner.tscn
## Add `-- --verbose=1` to print level 1's walkable map at a few sun azimuths (at the
## start elevation, or `--el=<deg>`)
## ('o' walkable shade, '.' sunlit, '#' solid, 'S' start, 'G' goal).
## A level PASSES when it is solvable, needs at least `min_sun_adjustments` sun
## adjustments (ShadowLevel export), is not trivial (one sun sweep from the start spot
## must not connect straight to the goal), and every needed sun angle has a comfortable
## window (≥ min_window_degrees on azimuth or elevation). The report lists one solution
## step by step. Debug tool only: never part of gameplay.
## Exit code 0 = all levels pass. Each level is loaded WITHOUT its gameplay shell
## ("Game" child is removed before it enters the tree), so nothing boots.

const LevelCatalog = preload("res://game/scenes/gameplay/shadow_run/level/LevelCatalog.gd")

@export var catalog: LevelCatalog = preload("res://game/scenes/gameplay/shadow_run/level/level_catalog.tres")
@export_file("*.tscn") var level_scenes: PackedStringArray = PackedStringArray()
@export var solver: LevelSolver
@export var logger: Node
@export var quit_when_done: bool = true
@export var verbose_level: int = 0
## Run only this level number (0 = all). `--only=N`.
@export var only_level: int = 0
## Experiment: `--range=az_min,az_max,el_min,el_max` overrides the sun ranges of the level(s).
var range_override: PackedFloat32Array = PackedFloat32Array()
## Experiments: `--start=az,el`, `--set=Node/Path:x:z;…` (moves nodes), `--hide=Node/Path;…`.
var start_override: PackedFloat32Array = PackedFloat32Array()
var set_overrides: Dictionary = {}
var hide_overrides: PackedStringArray = PackedStringArray()
## Smallest acceptable tolerance window for each needed sun angle, degrees.
@export var min_window_degrees: float = 8.0
## Extra sun azimuths to dump (besides min / start / max) and the row step.
@export var dump_azimuths: PackedFloat32Array = PackedFloat32Array([0.0])
@export var dump_row_step: int = 2
## Elevation for the dump (NAN = the level's start elevation).
@export var dump_elevation: float = NAN

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--verbose="):
			verbose_level = int(arg.trim_prefix("--verbose="))
		elif arg.begins_with("--az="):
			dump_azimuths = PackedFloat32Array(Array(arg.trim_prefix("--az=").split(",")).map(func(v): return float(v)))
		elif arg.begins_with("--el="):
			dump_elevation = float(arg.trim_prefix("--el="))
		elif arg.begins_with("--rows="):
			dump_row_step = int(arg.trim_prefix("--rows="))
		elif arg.begins_with("--only="):
			only_level = int(arg.trim_prefix("--only="))
		elif arg.begins_with("--start="):
			start_override = PackedFloat32Array(Array(arg.trim_prefix("--start=").split(",")).map(func(v): return float(v)))
		elif arg.begins_with("--set="):
			# --set=Props/pillar_6:x:z (repeatable, ';'-separated) moves a node for layout experiments.
			for item in arg.trim_prefix("--set=").split(";"):
				var parts := item.split(":")
				set_overrides[parts[0]] = Vector2(float(parts[1]), float(parts[2]))
		elif arg.begins_with("--hide="):
			hide_overrides = arg.trim_prefix("--hide=").split(";")
		elif arg.begins_with("--range="):
			range_override = PackedFloat32Array(Array(arg.trim_prefix("--range=").split(",")).map(func(v): return float(v)))
	if level_scenes.is_empty() and catalog != null:
		for entry in catalog.entries:
			if entry and entry.scene_path != "":
				level_scenes.append(entry.scene_path)
	_run.call_deferred()

func _run() -> void:
	var failed := 0
	for path in level_scenes:
		var level := (load(path) as PackedScene).instantiate() as ShadowLevel
		var game := level.get_node_or_null("Game")
		if game:
			level.remove_child(game)
			game.free()
		if only_level > 0 and level.level_number != only_level:
			level.free()
			continue
		if range_override.size() == 4:
			level.azimuth_min = range_override[0]
			level.azimuth_max = range_override[1]
			level.elevation_min = range_override[2]
			level.elevation_max = range_override[3]
		if start_override.size() == 2:
			level.sun_start_azimuth = start_override[0]
			level.sun_start_elevation = start_override[1]
		for node_path in set_overrides:
			var n := level.get_node_or_null(NodePath(node_path)) as Node3D
			if n:
				n.position = Vector3(set_overrides[node_path].x, n.position.y, set_overrides[node_path].y)
			else:
				logger.warn("no node %s" % node_path)
		for node_path in hide_overrides:
			var n := level.get_node_or_null(NodePath(node_path))
			if n:
				n.get_parent().remove_child(n)
				n.free()
		add_child(level)
		await get_tree().physics_frame
		await get_tree().physics_frame
		level.grid.build_static()
		var t0 := Time.get_ticks_msec()
		var r := solver.solve(level)
		var narrowest := INF
		for w in r.windows:
			narrowest = minf(narrowest, maxf(w.azimuth_span, w.elevation_span))
		var comfortable: bool = narrowest >= min_window_degrees
		var ok: bool = r.solvable and r.needs_sun and String(r.trivial) == "" 			and r.adjustments >= level.min_sun_adjustments and comfortable
		if not ok:
			failed += 1
		logger.info("%s Level %d '%s': solvable=%s min_sun_adjustments=%d (need >= %d) trivial=%s narrowest_window=%.1f° (%d angles, %d ms) %s" % [
			"PASS" if ok else "FAIL", level.level_number, level.level_title, str(r.solvable), r.adjustments,
			level.min_sun_adjustments, String(r.trivial) if String(r.trivial) != "" else "no",
			narrowest if r.solvable else 0.0, r.angles, Time.get_ticks_msec() - t0, r.error])
		logger.info("  start: az %.1f° el %.1f°, Dracula on cell %s" % [level.sun_start_azimuth, level.sun_start_elevation, str(r.get("start_cell", ""))])
		for i in (r.steps as Array).size():
			logger.info("  %d. %s" % [i + 1, r.steps[i]])
		if level.level_number == verbose_level:
			_dump(level)
		level.queue_free()
		await get_tree().physics_frame
	if failed == 0:
		logger.info("LevelValidator: all %d levels PASS" % level_scenes.size())
	else:
		logger.error("LevelValidator: %d of %d levels FAILED" % [failed, level_scenes.size()])
	if quit_when_done:
		get_tree().quit(1 if failed > 0 else 0)

func _dump(level: ShadowLevel) -> void:
	var g := level.grid
	var s := g.cell_at(level.start.global_position)
	var gl := g.cell_at(level.goal.global_position)
	var el := level.sun_start_elevation if is_nan(dump_elevation) else dump_elevation
	var azs: Array = [level.azimuth_min, level.sun_start_azimuth, level.azimuth_max]
	azs.append_array(Array(dump_azimuths))
	for az in azs:
		var m := g.compute_walkable_for(SunRig.direction_from_angles(az, el))
		logger.info("  az %d el %d  (rows: start z at top, every %d row(s); cols: x left→right)" % [int(az), int(el), dump_row_step])
		for y in range(0, g.rows, maxi(1, dump_row_step)):
			var row := ""
			for x in g.cols:
				var c := Vector2i(x, y)
				if (c - s).length() < 1.5:
					row += "S"
				elif (c - gl).length() < 1.5:
					row += "G"
				elif g.is_solid(c):
					row += "#"
				else:
					row += "o" if m[g.index_of(c)] != 0 else "."
			logger.info("  %3d |%s|" % [y, row])
