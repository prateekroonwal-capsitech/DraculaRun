class_name LevelSolver
extends Resource

## LevelSolver — proves a level is completable and that it needs the sun.
## Settings live in level/level_solver.tres.
##
## The sun's range is sampled on a grid: `azimuth_samples` × `elevation_samples` angles
## across the level's azimuth/elevation ranges (the samples nearest the start angle are
## snapped onto it exactly). For each angle the level's ShadeGrid gives the walkable
## cells (same ray test as the game) and the connected shadow regions (walking + hops).
## The search runs over states (azimuth sample, elevation sample, region):
##   * inside a region Dracula can walk anywhere;
##   * the sun may move one sample step on either axis only while Dracula stands on a
##     PIVOT cell — a cell that, with its left/right neighbours (his ±0.12 m footprint
##     plus margin), stays walkable at both angles AND halfway between them (the in-game
##     guard checks the sun continuously).
## Results: solvable, whether the goal is reachable WITHOUT touching the sun (must be
## false), whether ONE sun sweep without walking already connects start and goal
## ("trivial", must be false), the number of sun steps, and a plan (move / sun steps) that
## ShadowRunSoakTest replays for real. Masks are computed lazily and cached.

@export var azimuth_samples: int = 21
@export var elevation_samples: int = 6
## Cells within this distance of the goal's origin count as "at the goal".
@export var goal_radius: float = 0.8

var _grid: ShadeGrid
var _azs: PackedFloat32Array
var _els: PackedFloat32Array
var _masks: Dictionary = {}    # Vector2i(ai, ei) -> PackedByteArray
var _labels: Dictionary = {}   # Vector2i(ai, ei) -> PackedInt32Array
var _mids: Dictionary = {}     # "ai,ei>ai2,ei2" -> PackedByteArray

## Returns {solvable, needs_sun, sun_steps, plan: Array[Dictionary], error}.
## plan entries: {"type": "move", "cell": Vector2i} or
##               {"type": "sun", "azimuth": float, "elevation": float}.
## The level's ShadeGrid must have build_static() done and be in a physics space.
func solve(level: ShadowLevel) -> Dictionary:
	_grid = level.grid
	_masks.clear()
	_labels.clear()
	_mids.clear()
	_azs = _samples(level.azimuth_min, level.azimuth_max, azimuth_samples, level.sun_start_azimuth)
	_els = _samples(level.elevation_min, level.elevation_max, elevation_samples, level.sun_start_elevation)
	var start_angle := Vector2i(_nearest_index(_azs, level.sun_start_azimuth), _nearest_index(_els, level.sun_start_elevation))
	var start_cell := _nearest(_mask(start_angle), _grid.cell_at(level.start.global_position), 2)
	if start_cell.x < 0:
		return {"solvable": false, "needs_sun": true, "sun_steps": -1, "plan": [], "error": "start is not in shade at the start angle"}
	var goal_cells := _goal_cells(level.goal.global_position)
	var start_state := Vector3i(start_angle.x, start_angle.y, _label(start_angle)[_grid.index_of(start_cell)])
	var parent := {start_state: null}
	var via := {}   # state -> {"pivot", "azimuth", "elevation"}
	var queue: Array[Vector3i] = [start_state]
	var found := Vector3i(-1, -1, -1)
	var found_goal := Vector2i(-1, -1)
	while not queue.is_empty():
		var st: Vector3i = queue.pop_front()
		var a := Vector2i(st.x, st.y)
		var g := _goal_in(_label(a), st.z, goal_cells)
		if g.x >= 0:
			found = st
			found_goal = g
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var b: Vector2i = a + d
			if b.x < 0 or b.y < 0 or b.x >= _azs.size() or b.y >= _els.size():
				continue
			var pivots := _pivots(a, b, st.z)
			for dest in pivots:
				var nxt := Vector3i(b.x, b.y, dest)
				if parent.has(nxt):
					continue
				parent[nxt] = st
				via[nxt] = {"pivot": pivots[dest], "azimuth": _azs[b.x], "elevation": _els[b.y]}
				queue.append(nxt)
	if found.x < 0:
		return {"solvable": false, "needs_sun": true, "sun_steps": -1, "plan": [], "error": "goal unreachable at every sun angle"}
	var chain: Array[Vector3i] = []
	var s: Variant = found
	while s != null:
		chain.push_front(s)
		s = parent[s]
	var plan: Array[Dictionary] = []
	var last_pivot := Vector2i(-1, -1)
	for i in range(1, chain.size()):
		var v: Dictionary = via[chain[i]]
		if v.pivot == last_pivot and not plan.is_empty():
			plan[plan.size() - 1].azimuth = v.azimuth   # same pivot: one continuous sun move
			plan[plan.size() - 1].elevation = v.elevation
			continue
		plan.append({"type": "move", "cell": v.pivot})
		plan.append({"type": "sun", "azimuth": v.azimuth, "elevation": v.elevation})
		last_pivot = v.pivot
	plan.append({"type": "move", "cell": found_goal})
	var needs_sun := _goal_in(_label(start_angle), start_state.z, goal_cells).x < 0
	var trivial := _sweep_from_start_reaches_goal(start_angle, start_cell, goal_cells)
	return {"solvable": true, "needs_sun": needs_sun, "trivial": trivial, "sun_steps": chain.size() - 1, "plan": plan, "error": ""}

## True when Dracula can stay on his start cell, sweep the sun (guard-safe) to some
## angle, and from there walk straight to the goal — the puzzle collapses to one move.
func _sweep_from_start_reaches_goal(start_angle: Vector2i, start_cell: Vector2i, goal_cells: Array[Vector2i]) -> String:
	var seen := {start_angle: true}
	var queue: Array[Vector2i] = [start_angle]
	var si := _grid.index_of(start_cell)
	while not queue.is_empty():
		var a: Vector2i = queue.pop_front()
		if _goal_in(_label(a), _label(a)[si], goal_cells).x >= 0:
			return "az %.0f el %.0f" % [_azs[a.x], _els[a.y]]
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var b: Vector2i = a + d
			if b.x < 0 or b.y < 0 or b.x >= _azs.size() or b.y >= _els.size() or seen.has(b):
				continue
			if _footprint_ok(_mask(b), start_cell) and _footprint_ok(_mid(a, b), start_cell):
				seen[b] = true
				queue.append(b)
	return ""

# ── Angle samples / cached masks ──────────────────────────────────────────

func _samples(lo: float, hi: float, count: int, snap: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := maxi(1, count)
	for k in n:
		out.append(lo if n == 1 else lerpf(lo, hi, float(k) / float(n - 1)))
	out[_nearest_index(out, snap)] = snap
	return out

func _nearest_index(values: PackedFloat32Array, v: float) -> int:
	var best := 0
	for k in values.size():
		if absf(values[k] - v) < absf(values[best] - v):
			best = k
	return best

func _mask(a: Vector2i) -> PackedByteArray:
	if not _masks.has(a):
		_masks[a] = _grid.compute_walkable_for(SunRig.direction_from_angles(_azs[a.x], _els[a.y]))
	return _masks[a]

func _label(a: Vector2i) -> PackedInt32Array:
	if not _labels.has(a):
		_labels[a] = _grid.label_regions(_mask(a))
	return _labels[a]

func _mid(a: Vector2i, b: Vector2i) -> PackedByteArray:
	var key := "%d,%d>%d,%d" % [mini(a.x, b.x), mini(a.y, b.y), maxi(a.x, b.x), maxi(a.y, b.y)]
	if not _mids.has(key):
		var az := (_azs[a.x] + _azs[b.x]) * 0.5
		var el := (_els[a.y] + _els[b.y]) * 0.5
		_mids[key] = _grid.compute_walkable_for(SunRig.direction_from_angles(az, el))
	return _mids[key]

## One pivot cell per destination region: {label_in_b: pivot}.
func _pivots(a: Vector2i, b: Vector2i, label: int) -> Dictionary:
	var out := {}
	var ma := _mask(a)
	var mb := _mask(b)
	var la := _label(a)
	var lb := _label(b)
	var mid := PackedByteArray()
	for i in _grid.cell_count():
		if la[i] != label or mb[i] == 0 or out.has(lb[i]):
			continue
		@warning_ignore("integer_division")
		var c := Vector2i(i % _grid.cols, i / _grid.cols)
		if not _footprint_ok(ma, c) or not _footprint_ok(mb, c):
			continue
		if mid.is_empty():
			mid = _mid(a, b)
		if _footprint_ok(mid, c):
			out[lb[i]] = c
	return out

func _footprint_ok(mask: PackedByteArray, c: Vector2i) -> bool:
	for dx in range(-1, 2):
		var nb := c + Vector2i(dx, 0)
		if not _grid.in_bounds(nb) or mask[_grid.index_of(nb)] == 0:
			return false
	return true

func _goal_cells(goal: Vector3) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := int(ceil(goal_radius / _grid.cell_size))
	var gc := _grid.cell_at(goal)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := gc + Vector2i(dx, dy)
			if _grid.in_bounds(c) and _grid.cell_center(c).distance_to(Vector3(goal.x, _grid.global_position.y, goal.z)) <= goal_radius:
				out.append(c)
	return out

func _goal_in(labels: PackedInt32Array, label: int, goal_cells: Array[Vector2i]) -> Vector2i:
	for c in goal_cells:
		if labels[_grid.index_of(c)] == label:
			return c
	return Vector2i(-1, -1)

func _nearest(mask: PackedByteArray, c: Vector2i, radius: int) -> Vector2i:
	for r in range(0, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var nb := c + Vector2i(dx, dy)
				if _grid.in_bounds(nb) and mask[_grid.index_of(nb)] != 0:
					return nb
	return Vector2i(-1, -1)
