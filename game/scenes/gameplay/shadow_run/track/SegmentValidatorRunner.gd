extends Node3D

## Debug validator for every authored segment. Run SegmentValidatorRunner.tscn
## with F6, or headless from the command line:
##   godot --headless --path . res://game/scenes/gameplay/shadow_run/track/SegmentValidatorRunner.tscn
## Exit code 0 = all segments pass, 1 = at least one failed.
## Standalone dev tool (not part of the boot flow): its Logger is a node in the
## scene and its settings come from segment_validator.tres.

@export_dir var segment_dir: String = "res://game/scenes/gameplay/shadow_run/track/segments"
@export var quit_when_done: bool = true
## Segment id ("*" = all) whose shade map is dumped: one row per azimuth/elevation,
## one character per meter per lane ('#' shaded, '+' partly lit, '.' lit, 'X' obstacle).
## Also settable from the command line: `-- --verbose=seg_arcade`.
@export var verbose_segment: String = ""

@export var validator: SegmentValidator
@export var logger: Node

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--verbose="):
			verbose_segment = arg.trim_prefix("--verbose=")
	_run.call_deferred()

func _run() -> void:
	var paths := _segment_paths()
	var failed := 0
	for path in paths:
		var segment := (load(path) as PackedScene).instantiate() as TrackSegment
		add_child(segment)
		segment.set_optional_obstacles_enabled(true)
		await _settle()
		var grid_all := validator.sample_grid(segment, get_world_3d().direct_space_state)
		segment.set_optional_obstacles_enabled(false)
		await _settle()
		var grid_req := validator.sample_grid(segment, get_world_3d().direct_space_state)
		var r := validator.analyze(segment, grid_all, grid_req)
		_report(path, r)
		if String(segment.segment_id) == verbose_segment or verbose_segment == "*":
			_dump(validator, grid_req)
		if not r.passed:
			failed += 1
		segment.queue_free()
		await _settle()
	if failed == 0:
		logger.info("SegmentValidator: all %d segments PASS" % paths.size())
	else:
		logger.error("SegmentValidator: %d of %d segments FAILED" % [failed, paths.size()])
	if quit_when_done:
		get_tree().quit(1 if failed > 0 else 0)

func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

func _segment_paths() -> PackedStringArray:
	var out: PackedStringArray = []
	for f in DirAccess.get_files_at(segment_dir):
		var name := f.trim_suffix(".remap")
		if name.ends_with(".tscn"):
			out.append(segment_dir.path_join(name))
	out.sort()
	return out

func _dump(v: SegmentValidator, g: SegmentValidator.Grid) -> void:
	var per_m := int(round(1.0 / v.z_resolution))
	for az_i in v.azimuths.size():
		for el_i in v.elevations.size():
			var a := v.angle_index(az_i, el_i)
			var row := "  az %4d el %4.1f |" % [int(v.azimuths[az_i]), v.elevations[el_i]]
			for lane in g.lanes:
				for z in range(0, g.z_count, per_m):
					var f := g.frac[g.idx(z, lane, a)]
					row += "X" if g.is_blocked(z, lane) else ("#" if f <= 0.0 else ("+" if f < 1.0 else "."))
				row += "|"
			logger.info(row)

func _report(path: String, r: Dictionary) -> void:
	var line := "%s %s  speed %.1f  fixed-angle solutions %d/%d  coverage %.0f-%.0f%%" % [
		"PASS" if r.passed else "FAIL", r.id, r.speed, r.fixed_angle_solutions, r.angle_count,
		r.coverage_min * 100.0, r.coverage_max * 100.0]
	# info level keeps the report readable (warn/error add engine backtraces per line).
	logger.info(line if r.passed else line + "  (" + path + ")")
	for e in r.errors:
		logger.info("    error: " + e)
	for w in r.warnings:
		logger.info("    warning: " + w)
