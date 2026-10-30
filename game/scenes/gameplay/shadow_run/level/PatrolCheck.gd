class_name PatrolCheck
extends Resource

## PatrolCheck — debug tool run by LevelValidatorRunner after LevelSolver: checks that the
## solver's route can be walked past the level's villagers. Settings live in
## level/patrol_check.tres. Never used by gameplay code.
##
## What it proves (the "gaps + hiding spots" check, not a full time-expanded search):
##   1. Patrols are sane: every patrol leg stays off solid cells; every HideSpot's Entry
##      is on the grid and not solid.
##   2. Each villager's patrol is simulated over one full cycle (patrol_pose_at, the same
##      timeline the game plays) every `time_step` seconds. A cell is WATCHED at a time if
##      it is inside the vision cone (or the lantern's instant-spot radius) and the
##      line of sight from the eye to Dracula's chest height over that cell is clear.
##   3. The solver's plan is turned into a cell route (shortest walk in each step's shade).
##      Consecutive watched route cells form a CHOKEPOINT. Each chokepoint must have
##        • a GAP: an unwatched window at least as long as running through it
##          (length / dracula_speed + margin_time), on every villager watching it, and
##        • a HIDING SPOT whose Entry is reachable in the same shade within
##          max_hide_distance of the chokepoint, to wait in while the villager passes.
## Detection is not instant in the game (the meter needs time), so this is conservative.

## Patrol simulation step (s).
@export var time_step: float = 0.1
## Dracula's run speed used for crossing times (DraculaController.run_speed).
@export var dracula_speed: float = 8.0
## Extra time required on top of the crossing time (s).
@export var margin_time: float = 0.5
## Path distance (m) from a chokepoint to the hiding spot that covers it.
@export var max_hide_distance: float = 8.0

var _grid: ShadeGrid
var _query: PhysicsRayQueryParameters3D

## level: in the tree, grid.build_static() done. plan_result: LevelSolver.solve() output.
## Returns {"ok": bool, "lines": Array[String]}.
func check(level: ShadowLevel, plan_result: Dictionary, solver: LevelSolver) -> Dictionary:
	_grid = level.grid
	_query = PhysicsRayQueryParameters3D.new()
	var lines: Array[String] = []
	var ok := true
	var villagers: Array[VillagerController] = []
	var hide_cells: Dictionary = {}   # cell index -> name
	for node in level.find_children("*", "Node3D", true, false):
		if not (node as Node3D).is_visible_in_tree():
			continue   # hidden in the editor = not in the level
		if node is VillagerController:
			villagers.append(node)
		elif node is HideSpot:
			var hc := _grid.cell_at((node as HideSpot).entry_position())
			if not _grid.in_bounds(hc) or _grid.is_solid(hc):
				lines.append("FAIL hiding spot %s: Entry is off the grid or on a solid cell" % level.get_path_to(node))
				ok = false
			else:
				hide_cells[_grid.index_of(hc)] = str(level.get_path_to(node))
	if villagers.is_empty():
		lines.append("no villagers")
		return {"ok": ok, "lines": lines}
	if not plan_result.get("solvable", false):
		lines.append("FAIL no solver route to check")
		return {"ok": false, "lines": lines}

	# 1 + 2: patrol legs, watched cells over time.
	var watch: Array = []   # per villager: Array[PackedByteArray] (one per time sample)
	for v in villagers:
		var period := v.patrol_period()
		var samples := maxi(1, int(ceil(period / time_step))) if period > 0.0 else 1
		var per_t: Array[PackedByteArray] = []
		var solid_hits := 0
		for k in samples:
			var pose := v.patrol_pose_at(k * time_step)
			var c := _grid.cell_at(pose.position)
			if _grid.is_solid(c):
				solid_hits += 1
			per_t.append(_watched_cells(level, v, pose))
		watch.append(per_t)
		var cover := 0
		var union := PackedByteArray()
		union.resize(_grid.cell_count())
		for m in per_t:
			for i in m.size():
				if m[i] != 0:
					union[i] = 1
		for i in union.size():
			cover += union[i]
		if solid_hits > 0:
			lines.append("FAIL %s: patrol walks through solid cells (%d samples)" % [v.name, solid_hits])
			ok = false
		lines.append("%s: patrol cycle %.1f s, watches %d cells over a cycle" % [v.name, period, cover])

	# 3: the route, phase by phase.
	var route := _route(plan_result, solver)
	if route.is_empty():
		lines.append("FAIL could not rebuild the solver route")
		return {"ok": false, "lines": lines}
	var chokepoints := 0
	var i := 0
	while i < route.size():
		var r: Dictionary = route[i]
		if not _is_watched(watch, r.cell):
			i += 1
			continue
		var j := i
		while j + 1 < route.size() and _is_watched(watch, route[j + 1].cell) and route[j + 1].phase == r.phase:
			j += 1
		chokepoints += 1
		var cells: Array[Vector2i] = []
		for k in range(i, j + 1):
			cells.append(route[k].cell)
		var length := float(cells.size()) * _grid.cell_size
		var need := length / dracula_speed + margin_time
		var desc := "chokepoint %d (cells %s → %s, %.1f m)" % [chokepoints, str(cells[0]), str(cells[-1]), length]
		var gap_ok := true
		var parts: Array[String] = []
		for vi in villagers.size():
			var gap := _longest_gap(watch[vi], cells)
			if gap < 0.0:
				continue   # this villager never sees these cells
			var good := gap >= need
			gap_ok = gap_ok and good
			parts.append("%s gap %s (need %.1f s)" % [villagers[vi].name, "%.1f s" % gap, need])
		var hide := _nearest_hide(r.mask, route[maxi(0, i - 1)].cell, hide_cells)
		var hide_ok: bool = not hide.is_empty() and float(hide.distance) <= max_hide_distance
		var hide_txt := "hiding spot %s at %.1f m" % [hide.name, hide.distance] if not hide.is_empty() else "no hiding spot reachable"
		var pass_ := gap_ok and hide_ok
		ok = ok and pass_
		lines.append("%s %s: %s; %s" % ["PASS" if pass_ else "FAIL", desc, ", ".join(parts), hide_txt])
		i = j + 1
	if chokepoints == 0:
		lines.append("note: no villager ever watches the solver route")
	return {"ok": ok, "lines": lines}

## Cells a villager at `pose` sees (cone or lantern radius, line of sight clear).
func _watched_cells(level: ShadowLevel, v: VillagerController, pose: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(_grid.cell_count())
	var space := level.get_world_3d().direct_space_state
	var pos: Vector3 = pose.position
	var fwd: Vector3 = pose.forward
	var eye := pos + Basis(Vector3.UP, VillagerController._yaw_of(fwd)) * v.eye_offset()
	var lantern := pos + Vector3(0.0, 1.0, 0.0)
	var reach := maxf(v.vision_range, v.lantern_spot_radius) + _grid.cell_size
	var c0 := _grid.cell_at(pos - Vector3(reach, 0.0, -reach))
	var c1 := _grid.cell_at(pos + Vector3(reach, 0.0, -reach))
	var half := deg_to_rad(v.vision_angle * 0.5)
	for y in range(maxi(0, mini(c0.y, c1.y)), mini(_grid.rows, maxi(c0.y, c1.y) + 1)):
		for x in range(maxi(0, mini(c0.x, c1.x)), mini(_grid.cols, maxi(c0.x, c1.x) + 1)):
			var c := Vector2i(x, y)
			if _grid.is_solid(c):
				continue
			var p := _grid.cell_center(c)
			var target := p + Vector3(0.0, v.target_height, 0.0)
			var to := p - pos
			to.y = 0.0
			var d := to.length()
			var in_cone := d <= v.vision_range and (d < 0.3 or fwd.angle_to(to / maxf(d, 0.0001)) <= half)
			var in_lantern := lantern.distance_to(target) <= v.lantern_spot_radius
			if (in_cone or in_lantern) and VillagerController.has_line_of_sight(space, _query, eye, target):
				out[_grid.index_of(c)] = 1
	return out

func _is_watched(watch: Array, c: Vector2i) -> bool:
	var i := _grid.index_of(c)
	for per_t in watch:
		for m in per_t:
			if m[i] != 0:
				return true
	return false

## Longest cyclic run (s) during which none of `cells` is watched by this villager,
## or -1 when this villager never watches them at all.
func _longest_gap(per_t: Array, cells: Array[Vector2i]) -> float:
	var n := per_t.size()
	var blocked := PackedByteArray()
	blocked.resize(n)
	var any := false
	for k in n:
		for c in cells:
			if (per_t[k] as PackedByteArray)[_grid.index_of(c)] != 0:
				blocked[k] = 1
				any = true
				break
	if not any:
		return -1.0
	var best := 0
	var run := 0
	for k in 2 * n:   # twice round the cycle for wrap-around gaps
		if blocked[k % n] == 0:
			run += 1
			best = maxi(best, mini(run, n))
		else:
			run = 0
	return float(best) * time_step

## Route cells in order: [{cell, phase, mask}], following the plan's moves in each phase's shade.
func _route(plan_result: Dictionary, solver: LevelSolver) -> Array:
	var out := []
	var cur: Vector2i = plan_result.start_cell
	var level_angle: Vector2 = plan_result.start_angle
	var phase := 0
	for step in plan_result.plan:
		if step.type == "sun":
			level_angle = Vector2(step.azimuth, step.elevation)
			continue
		var mask := solver.mask_for(level_angle.x, level_angle.y)
		var cells := _bfs_path(mask, cur, step.cell)
		if cells.is_empty() and cur != step.cell:
			return []
		for c in cells:
			out.append({"cell": c, "phase": phase, "mask": mask})
		cur = step.cell
		phase += 1
	return out

## Shortest walk (with hops) over `mask` from a to b, excluding a.
func _bfs_path(mask: PackedByteArray, a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	if a == b:
		return res
	var walk := func(c: Vector2i) -> bool: return _grid.in_bounds(c) and mask[_grid.index_of(c)] != 0
	var parent := {}
	parent[a] = a
	var queue: Array[Vector2i] = [a]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if c == b:
			break
		for nb in _grid._neighbours(c, walk, true):
			var n: Vector2i = nb[0]
			if not parent.has(n):
				parent[n] = c
				queue.append(n)
	if not parent.has(b):
		return res
	var c := b
	while c != a:
		res.push_front(c)
		c = parent[c]
	return res

## Nearest hiding-spot Entry (path distance in m) from `from` within `mask`.
func _nearest_hide(mask: PackedByteArray, from: Vector2i, hide_cells: Dictionary) -> Dictionary:
	if hide_cells.is_empty():
		return {}
	var walk := func(c: Vector2i) -> bool: return _grid.in_bounds(c) and mask[_grid.index_of(c)] != 0
	var dist := {from: 0.0}
	var queue: Array[Vector2i] = [from]
	var head := 0
	var limit := max_hide_distance * 3.0 / _grid.cell_size
	while head < queue.size():
		var c := queue[head]
		head += 1
		var i := _grid.index_of(c)
		if hide_cells.has(i):
			return {"name": hide_cells[i], "distance": float(dist[c]) * _grid.cell_size}
		if float(dist[c]) > limit:
			continue
		for nb in _grid._neighbours(c, walk, true):
			var n: Vector2i = nb[0]
			if not dist.has(n):
				dist[n] = float(dist[c]) + float(nb[1])
				queue.append(n)
	return {}
