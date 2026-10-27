extends Node3D

## Level validator. Run LevelValidatorRunner.tscn with F6, or headless:
##   godot --headless --path . res://game/scenes/gameplay/shadow_run/level/LevelValidatorRunner.tscn
## Add `-- --verbose=1` to print level 1's walkable map at a few sun azimuths (at the
## start elevation, or `--el=<deg>`)
## ('o' walkable shade, '.' sunlit, '#' solid, 'S' start, 'G' goal).
## A level PASSES when it is solvable, needs at least one sun adjustment, and is not
## trivial (one sun sweep from the start spot must not connect straight to the goal).
## Exit code 0 = all levels pass. Each level is loaded WITHOUT its gameplay shell
## ("Game" child is removed before it enters the tree), so nothing boots.

@export_file("*.tscn") var level_scenes: PackedStringArray = PackedStringArray()
@export var solver: LevelSolver
@export var logger: Node
@export var quit_when_done: bool = true
@export var verbose_level: int = 0
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
	_run.call_deferred()

func _run() -> void:
	var failed := 0
	for path in level_scenes:
		var level := (load(path) as PackedScene).instantiate() as ShadowLevel
		var game := level.get_node_or_null("Game")
		if game:
			level.remove_child(game)
			game.free()
		add_child(level)
		await get_tree().physics_frame
		await get_tree().physics_frame
		level.grid.build_static()
		var t0 := Time.get_ticks_msec()
		var r := solver.solve(level)
		var ok: bool = r.solvable and r.needs_sun and String(r.get("trivial", "")) == ""
		if not ok:
			failed += 1
		logger.info("%s Level %d '%s': solvable=%s needs_sun=%s trivial=%s sun_steps=%d plan_steps=%d (%d ms) %s" % [
			"PASS" if ok else "FAIL", level.level_number, level.level_title, str(r.solvable), str(r.needs_sun),
			String(r.get("trivial", "")) if String(r.get("trivial", "")) != "" else "no",
			r.sun_steps, (r.plan as Array).size(), Time.get_ticks_msec() - t0, r.error])
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
