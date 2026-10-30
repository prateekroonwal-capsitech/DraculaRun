class_name LevelSolver
extends Resource

## LevelSolver — debug tool: proves a level is completable, finds the MINIMUM number of
## sun adjustments, and measures how forgiving each needed sun angle is.
## Settings live in level/level_solver.tres. Never used by gameplay code.
##
## The sun's range is sampled every `angle_step` degrees on both axes (the samples nearest
## the start angle are snapped onto it). For each angle the level's ShadeGrid gives the
## walkable cells (same rays and the same variable-cell mask as the game) and the
## connected shadow regions (walking + hops ≤ max_hop_distance, solids block).
##
## State = (sun angle, Dracula's region). Inside a region he walks anywhere. One SUN
## ADJUSTMENT = Dracula stands on a PIVOT cell and the sun moves through any chain of
## neighbouring angle samples while that cell and its left/right neighbours (his
## footprint) stay shaded — the in-game exposure guard.
##   1) Backwards from the goal, layer k = states that need k adjustments (an adjustment
##      is reversible), until the start state is reached: that k is the minimum.
##   2) Forwards from the start, each step picks the pivot and stopping angle with the
##      widest WINDOW: the angles around it that are still reachable on that pivot and
##      still finish in the remaining adjustments. Its azimuth / elevation spans say
##      whether the angle is comfortable or pixel-perfect.
##
## Results: solvable, needs_sun, trivial (one sweep from the start spot reaches the goal),
## adjustments, windows, readable steps and a replayable plan:
##   {"type": "move", "cell": Vector2i} / {"type": "sun", "azimuth": float, "elevation": float}
## (consecutive "sun" entries are the waypoints of one adjustment).
## Hiding spots: a HideSpot's Entry cell is a pivot whose footprint never needs shade (a
## hidden Dracula is safe from the sun), so the sun may sweep through angles that light it;
## he still has to be able to walk in (shaded at the start angle) and out (shaded at the
## final angle). Such moves carry "hide": the HideSpot's path relative to the level.

## Sun sampling step on both axes, degrees.
@export var angle_step: float = 2.5
## Also require the footprint to be shaded halfway between neighbouring samples.
@export var check_midpoints: bool = false
## Cells within this distance of the goal's origin count as "at the goal".
@export var goal_radius: float = 0.8
## Give up after this many adjustments.
@export var max_adjustments: int = 8
## Auto-sun levels: Dracula's run speed (m/s) for "can he get there within the hold".
@export var run_speed: float = 8.0
## Auto-sun levels: give up after this many full loops of the sun schedule.
@export var max_cycles: int = 3

var _grid: ShadeGrid
var _azs: PackedFloat32Array
var _els: PackedFloat32Array
var _na: int = 0
var _ne: int = 0
var _n: int = 0
var _masks: Array = []   # angle index -> PackedByteArray (walkable)
var _fps: Array = []     # angle index -> PackedByteArray (footprint shaded)
var _labs: Array = []    # angle index -> PackedInt32Array (region labels)
var _mid_cache: Dictionary = {}
var _hide: PackedByteArray = PackedByteArray()   # cell -> 1 if a HideSpot's Entry
var _hide_paths: Dictionary = {}                 # cell index -> NodePath (relative to the level)
var _sched_cache: Dictionary = {}                # auto sun: Vector2 angle -> walkable mask

## The level's ShadeGrid must have build_static() done and be in a physics space.
func solve(level: ShadowLevel) -> Dictionary:
	_grid = level.grid
	_grid.prepare_variable_mask(level.azimuth_min, level.azimuth_max, level.elevation_min, level.elevation_max)
	_azs = _samples(level.azimuth_min, level.azimuth_max, level.sun_start_azimuth)
	_els = _samples(level.elevation_min, level.elevation_max, level.sun_start_elevation)
	_na = _azs.size()
	_ne = _els.size()
	_n = _grid.cell_count()
	_masks.clear()
	_fps.clear()
	_labs.clear()
	_masks.resize(_na * _ne)
	_fps.resize(_na * _ne)
	_labs.resize(_na * _ne)
	_mid_cache.clear()
	_collect_hide_spots(level)
	var a0 := _nearest_index(_els, level.sun_start_elevation) * _na + _nearest_index(_azs, level.sun_start_azimuth)
	var start_cell := _nearest_open(_mask(a0), _grid.cell_at(level.start.global_position), 2)
	var fail := {"solvable": false, "needs_sun": true, "trivial": "", "adjustments": -1, "plan": [],
		"steps": [], "windows": [], "angles": _na * _ne}
	if start_cell.x < 0:
		fail.error = "start is not in shade at the start angle"
		return fail
	var goal_cells := _goal_cells(level.goal.global_position)
	var s0 := _state(a0, _lab(a0)[_grid.index_of(start_cell)])
	# 1) Adjustments-to-goal, backwards from every state that contains the goal.
	var dist := {}
	var frontier: Array[int] = []
	for a in _na * _ne:
		var lab := _lab(a)
		for c in goal_cells:
			var l := lab[_grid.index_of(c)]
			if l >= 0 and not dist.has(_state(a, l)):
				dist[_state(a, l)] = 0
				frontier.append(_state(a, l))
	var k := 0
	while not dist.has(s0) and k < max_adjustments and not frontier.is_empty():
		k += 1
		frontier = _expand(frontier, dist, k)
	if not dist.has(s0):
		fail.error = "goal unreachable within %d sun adjustments" % max_adjustments
		return fail
	var adjustments: int = dist[s0]
	# 2) Forwards: widest window at every step.
	var plan: Array[Dictionary] = []
	var steps: Array[String] = []
	var windows: Array[Dictionary] = []
	var st := s0
	for left in range(adjustments, 0, -1):
		var best := _best_adjustment(st, dist, left - 1)
		if best.is_empty():
			fail.error = "internal: no adjustment found from a state %d away" % left
			return fail
		var move := {"type": "move", "cell": best.pivot}
		var pi := _grid.index_of(best.pivot)
		if _hide[pi] != 0 and _needs_hiding(best.path, pi):
			move["hide"] = _hide_paths[pi]
		plan.append(move)
		for a in _compress(best.path):
			plan.append({"type": "sun", "azimuth": _az_of(a), "elevation": _el_of(a)})
		var w: Dictionary = best.window
		windows.append(w)
		steps.append(("hide at %s (cell %s) → sun" % [str(move.hide), str(best.pivot)] if move.has("hide") else "walk to cell %s → sun" % str(best.pivot)) + " to az %.1f° el %.1f° (window: az %.1f…%.1f° at that elevation, el %.1f…%.1f° at that azimuth)" % [
			_az_of(best.angle), _el_of(best.angle),
			w.azimuth_range.x, w.azimuth_range.y, w.elevation_range.x, w.elevation_range.y])
		st = _state(best.angle, _lab(best.angle)[_grid.index_of(best.pivot)])
	var goal_cell := _goal_in(st, goal_cells)
	plan.append({"type": "move", "cell": goal_cell})
	steps.append("walk to the goal (cell %s)" % str(goal_cell))
	return {"solvable": true, "needs_sun": adjustments > 0, "trivial": _sweep_reaches_goal(a0, start_cell, goal_cells),
		"adjustments": adjustments, "plan": plan, "steps": steps, "windows": windows, "error": "",
		"angles": _na * _ne, "start_cell": start_cell,
		"start_angle": Vector2(level.sun_start_azimuth, level.sun_start_elevation)}

# ── Auto-sun levels (ShadowLevel.auto_sun) ────────────────────────────────

## Solver for levels whose sun runs on a fixed loop. The player only chooses where Dracula
## is. State = (hold key k, cell he stands on when the hold starts). During a hold he may
## run (at `run_speed`) anywhere in his shade region that he reaches before the hold ends;
## when the sun sweeps to key k+1 he must be on a cell whose footprint stays shaded at
## every sampled angle of the sweep (or on a hiding spot's Entry, then hidden), and that
## cell must be walkable at key k+1. The goal must be reached during some hold.
## Same result format as solve(); "sun" plan entries carry "key" (the hold they start).
func solve_schedule(level: ShadowLevel) -> Dictionary:
	_grid = level.grid
	_grid.prepare_variable_mask(level.azimuth_min, level.azimuth_max, level.elevation_min, level.elevation_max)
	_n = _grid.cell_count()
	_sched_cache.clear()
	_collect_hide_spots(level)
	var keys := level.auto_sun_keys
	var fail := {"solvable": false, "needs_sun": true, "trivial": "", "adjustments": -1, "plan": [],
		"steps": [], "windows": [], "angles": 0}
	if keys.size() < 2:
		fail.error = "auto_sun needs at least two auto_sun_keys"
		return fail
	var m0 := _sched_mask(keys[0])
	var start_cell := _nearest_open(m0, _grid.cell_at(level.start.global_position), 2)
	if start_cell.x < 0:
		fail.error = "start is not in shade at the first key"
		return fail
	var goal_cells := _goal_cells(level.goal.global_position)
	var nk := keys.size()
	# Cells that survive each sweep k → k+1 (footprint shaded throughout, or a hiding spot).
	var survive: Array = []
	for k in nk:
		survive.append(_sweep_survivors(keys[k], keys[(k + 1) % nk]))
	var start_state := Vector2i(0, _grid.index_of(start_cell))
	var came := {start_state: null}
	var queue: Array[Vector2i] = [start_state]
	var head := 0
	var found := Vector2i(-1, -1)
	var goal_hit := -1
	var max_holds := nk * maxi(1, max_cycles)
	var depth := {start_state: 0}
	while head < queue.size():
		var st := queue[head]
		head += 1
		var k := st.x
		var budget := (level.auto_sun_hold_time + (level.auto_sun_first_hold_bonus if depth[st] == 0 else 0.0)) * run_speed
		var dist := _walk_dist(_sched_mask(keys[k]), _cell(st.y), budget)
		for g in goal_cells:
			if dist.has(_grid.index_of(g)):
				found = st
				goal_hit = _grid.index_of(g)
				break
		if found.x >= 0:
			break
		if int(depth[st]) >= max_holds:
			continue
		var next_mask := _sched_mask(keys[(k + 1) % nk])
		var surv: PackedByteArray = survive[k]
		for c in dist:
			if surv[c] == 0 or next_mask[c] == 0:
				continue
			var nst := Vector2i((k + 1) % nk, c)
			if came.has(nst):
				continue
			came[nst] = st
			depth[nst] = int(depth[st]) + 1
			queue.append(nst)
	if found.x < 0:
		fail.error = "goal unreachable within %d holds" % max_holds
		return fail
	# Rebuild the chain of states.
	var chain: Array[Vector2i] = []
	var s: Variant = found
	while s != null:
		chain.push_front(s)
		s = came[s]
	var plan: Array[Dictionary] = []
	var steps: Array[String] = []
	for i in range(1, chain.size()):
		var prev := chain[i - 1]
		var cur := chain[i]
		var cell := _cell(cur.y)
		var move := {"type": "move", "cell": cell}
		if _hide[cur.y] != 0 and not _sweep_survivors(keys[prev.x], keys[cur.x], false)[cur.y]:
			move["hide"] = _hide_paths[cur.y]
		plan.append(move)
		var a := keys[cur.x]
		plan.append({"type": "sun", "azimuth": a.x, "elevation": a.y, "key": cur.x})
		steps.append("hold %d (sun az %.1f° el %.1f°): %s %s, wait for the sun to sweep to az %.1f° el %.1f°" % [
			prev.x, keys[prev.x].x, keys[prev.x].y, "hide at %s on" % str(move.hide) if move.has("hide") else "go to",
			str(cell), a.x, a.y])
	plan.append({"type": "move", "cell": _cell(goal_hit)})
	steps.append("hold %d: walk to the goal (cell %s)" % [found.x, str(_cell(goal_hit))])
	return {"solvable": true, "needs_sun": chain.size() > 1, "trivial": "" if chain.size() > 1 else "goal reachable in the first hold",
		"adjustments": chain.size() - 1, "plan": plan, "steps": steps, "windows": [], "error": "", "angles": nk,
		"start_cell": start_cell, "start_angle": keys[0]}

func _collect_hide_spots(level: ShadowLevel) -> void:
	_hide = PackedByteArray()
	_hide.resize(_n)
	_hide_paths.clear()
	for node in level.find_children("*", "Node3D", true, false):
		if node is HideSpot and (node as Node3D).is_visible_in_tree():   # hidden in the editor = not in the level
			var hc := _grid.cell_at((node as HideSpot).entry_position())
			if _grid.in_bounds(hc):
				_hide[_grid.index_of(hc)] = 1
				_hide_paths[_grid.index_of(hc)] = level.get_path_to(node)

## Walkable mask at an exact angle (cached).
func _sched_mask(angle: Vector2) -> PackedByteArray:
	if not _sched_cache.has(angle):
		_sched_cache[angle] = _grid.compute_walkable_fast(SunRig.direction_from_angles(angle.x, angle.y))
	return _sched_cache[angle]

## 1 for cells whose footprint stays shaded at every sample of the sweep a → b
## (sampled every angle_step degrees); hiding-spot entries count when `with_hide`.
func _sweep_survivors(a: Vector2, b: Vector2, with_hide: bool = true) -> PackedByteArray:
	var samples := maxi(2, int(ceil(maxf(absf(b.x - a.x), absf(b.y - a.y)) / maxf(0.5, angle_step))) + 1)
	var out := PackedByteArray()
	out.resize(_n)
	out.fill(1)
	for i in samples:
		var fp := _footprint(_sched_mask(a.lerp(b, float(i) / float(samples - 1))))
		for c in _n:
			if out[c] != 0 and fp[c] == 0:
				out[c] = 0
	if with_hide:
		for c in _n:
			if _hide[c] != 0:
				out[c] = 1
	return out

## Running distance (m) from `from` to every cell of its shade region within `limit` m.
func _walk_dist(mask: PackedByteArray, from: Vector2i, limit: float) -> Dictionary:
	var dist := {_grid.index_of(from): 0.0}
	var walk := func(c: Vector2i) -> bool: return _grid.in_bounds(c) and mask[_grid.index_of(c)] != 0
	if not walk.call(from):
		return dist
	var heap_f := PackedFloat32Array()
	var heap_i := PackedInt32Array()
	ShadeGrid._heap_push(heap_f, heap_i, 0.0, _grid.index_of(from))
	while heap_i.size() > 0:
		var cur := ShadeGrid._heap_pop(heap_f, heap_i)
		var d: float = dist[cur]
		for nb in _grid._neighbours(_cell(cur), walk, true):
			var ni := _grid.index_of(nb[0])
			var nd: float = d + float(nb[1]) * _grid.cell_size
			if nd <= limit and nd < float(dist.get(ni, INF)):
				dist[ni] = nd
				ShadeGrid._heap_push(heap_f, heap_i, nd, ni)
	return dist

# ── Search ────────────────────────────────────────────────────────────────

## One adjustment from every frontier state: flood (angle, pivot) pairs over the angle
## grid while the pivot's footprint stays shaded. New states get dist = layer.
func _expand(frontier: Array[int], dist: Dictionary, layer: int) -> Array[int]:
	var seen := PackedByteArray()
	seen.resize(_na * _ne * _n)
	var queue := PackedInt32Array()
	for st in frontier:
		var a := _angle_of(st)
		var lab := _lab(a)
		var fp := _fp(a)
		var r := _label_of(st)
		for c in _n:
			if lab[c] == r and (fp[c] != 0 or _hide[c] != 0) and seen[a * _n + c] == 0:
				seen[a * _n + c] = 1
				queue.append(a * _n + c)
	var out: Array[int] = []
	var head := 0
	while head < queue.size():
		var pk := queue[head]
		head += 1
		@warning_ignore("integer_division")
		var a := pk / _n
		var c := pk % _n
		var ax := a % _na
		@warning_ignore("integer_division")
		var ey := a / _na
		for d in 4:
			var bx := ax + _step_x(d)
			var by := ey + _step_y(d)
			if bx < 0 or by < 0 or bx >= _na or by >= _ne:
				continue
			var b := by * _na + bx
			var q := b * _n + c
			if seen[q] != 0 or not _pivot_ok(b, c):
				continue
			if check_midpoints and _hide[c] == 0 and not _mid_ok(a, b, c):
				continue
			seen[q] = 1
			queue.append(q)
			var l := _lab(b)[c]
			if l < 0:
				continue   # hidden through a lit angle: he can't step out here
			var nst := _state(b, l)
			if not dist.has(nst):
				dist[nst] = layer
				out.append(nst)
	return out

## From state `st`: every pivot in its region, every angle reachable on that pivot whose
## resulting state is ≤ `need` adjustments from the goal. Picks the angle with the widest
## window ((azimuth span + step) × (elevation span + step)); returns
## {pivot, angle, path, window} or {} when none.
func _best_adjustment(st: int, dist: Dictionary, need: int) -> Dictionary:
	var a0 := _angle_of(st)
	var lab0 := _lab(a0)
	var fp0 := _fp(a0)
	var r := _label_of(st)
	var best := {}
	var best_score := -1.0
	for c in _n:
		if lab0[c] != r or (fp0[c] == 0 and _hide[c] == 0):
			continue
		var came := PackedByteArray()   # 0 unseen, 1..4 via direction, 5 = start
		came.resize(_na * _ne)
		came[a0] = 5
		var good := PackedByteArray()
		good.resize(_na * _ne)
		var any := false
		var queue := PackedInt32Array([a0])
		var head := 0
		while head < queue.size():
			var x := queue[head]
			head += 1
			if _lab(x)[c] >= 0 and int(dist.get(_state(x, _lab(x)[c]), 999)) <= need:
				good[x] = 1
				any = true
			var ax := x % _na
			@warning_ignore("integer_division")
			var ey := x / _na
			for d in 4:
				var bx := ax + _step_x(d)
				var by := ey + _step_y(d)
				if bx < 0 or by < 0 or bx >= _na or by >= _ne:
					continue
				var y := by * _na + bx
				if came[y] == 0 and _pivot_ok(y, c) and (not check_midpoints or _hide[c] != 0 or _mid_ok(x, y, c)):
					came[y] = d + 1
					queue.append(y)
		if not any:
			continue
		for x in _na * _ne:
			if good[x] == 0:
				continue
			var w := _spans(good, x)
			var score: float = (w.azimuth_span + angle_step) * (w.elevation_span + angle_step)
			if score > best_score:
				best_score = score
				best = {"pivot": _cell(c), "angle": x, "path": _trace(came, x), "window": w}
	return best

func _trace(came: PackedByteArray, b: int) -> PackedInt32Array:
	var path := PackedInt32Array([b])
	var a := b
	while came[a] != 5:
		var d := came[a] - 1
		var ax := a % _na - _step_x(d)
		@warning_ignore("integer_division")
		var ey := a / _na - _step_y(d)
		a = ey * _na + ax
		path.append(a)
	path.reverse()
	return path

## Contiguous runs of `good` angles through x: along azimuth and along elevation.
func _spans(good: PackedByteArray, x: int) -> Dictionary:
	var bx := x % _na
	@warning_ignore("integer_division")
	var by := x / _na
	var lo := bx
	var hi := bx
	while lo > 0 and good[by * _na + lo - 1] != 0:
		lo -= 1
	while hi < _na - 1 and good[by * _na + hi + 1] != 0:
		hi += 1
	var lo_e := by
	var hi_e := by
	while lo_e > 0 and good[(lo_e - 1) * _na + bx] != 0:
		lo_e -= 1
	while hi_e < _ne - 1 and good[(hi_e + 1) * _na + bx] != 0:
		hi_e += 1
	return {"azimuth_span": _azs[hi] - _azs[lo], "elevation_span": _els[hi_e] - _els[lo_e],
		"azimuth_range": Vector2(_azs[lo], _azs[hi]), "elevation_range": Vector2(_els[lo_e], _els[hi_e])}

## Trivial: standing on the start cell, one guard-safe sweep reaches an angle where the
## start region contains the goal. Returns that angle as text, or "".
func _sweep_reaches_goal(a0: int, start_cell: Vector2i, goal_cells: Array[Vector2i]) -> String:
	var sc := _grid.index_of(start_cell)
	var seen := PackedByteArray()
	seen.resize(_na * _ne)
	seen[a0] = 1
	var queue := PackedInt32Array([a0])
	var head := 0
	while head < queue.size():
		var x := queue[head]
		head += 1
		if _goal_in(_state(x, _lab(x)[sc]), goal_cells).x >= 0:
			return "az %.1f el %.1f" % [_az_of(x), _el_of(x)]
		var ax := x % _na
		@warning_ignore("integer_division")
		var ey := x / _na
		for d in 4:
			var bx := ax + _step_x(d)
			var by := ey + _step_y(d)
			if bx < 0 or by < 0 or bx >= _na or by >= _ne:
				continue
			var y := by * _na + bx
			if seen[y] == 0 and _fp(y)[sc] != 0:
				seen[y] = 1
				queue.append(y)
	return ""

## Drop the middle of straight runs so the plan's sun waypoints are corners only.
func _compress(path: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(1, path.size()):
		if i == path.size() - 1 or path[i] - path[i - 1] != path[i + 1] - path[i]:
			out.append(path[i])
	return out

# ── Angles, states, cached masks ──────────────────────────────────────────

## Walkable mask at the sampled angle nearest (az, el) (after solve(); used by PatrolCheck).
## After solve_schedule() it is the mask at exactly (az, el).
func mask_for(az: float, el: float) -> PackedByteArray:
	if _sched_cache.has(Vector2(az, el)):
		return _sched_cache[Vector2(az, el)]
	return _mask(_nearest_index(_els, el) * _na + _nearest_index(_azs, az))

static func _step_x(d: int) -> int:
	return 1 if d == 0 else (-1 if d == 1 else 0)

static func _step_y(d: int) -> int:
	return 1 if d == 2 else (-1 if d == 3 else 0)

func _samples(lo: float, hi: float, snap: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := maxi(2, int(round((hi - lo) / maxf(0.1, angle_step))) + 1)
	for k in n:
		out.append(lerpf(lo, hi, float(k) / float(n - 1)))
	out[_nearest_index(out, snap)] = snap
	return out

func _nearest_index(values: PackedFloat32Array, v: float) -> int:
	var best := 0
	for k in values.size():
		if absf(values[k] - v) < absf(values[best] - v):
			best = k
	return best

func _az_of(a: int) -> float:
	return _azs[a % _na]

func _el_of(a: int) -> float:
	@warning_ignore("integer_division")
	return _els[a / _na]

func _state(a: int, label: int) -> int:
	return a * 65536 + label

func _angle_of(st: int) -> int:
	@warning_ignore("integer_division")
	return st / 65536

func _label_of(st: int) -> int:
	return st % 65536

func _cell(i: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(i % _grid.cols, i / _grid.cols)

func _mask(a: int) -> PackedByteArray:
	if _masks[a] == null:
		_masks[a] = _grid.compute_walkable_fast(SunRig.direction_from_angles(_az_of(a), _el_of(a)))
	return _masks[a]

## Dracula may stay on cell c while the sun is at angle a: his footprint is shaded, or c is
## a hiding spot's Entry (hidden = safe from the sun).
func _pivot_ok(a: int, c: int) -> bool:
	return _hide[c] != 0 or _fp(a)[c] != 0

## True when the adjustment along `path` lights the footprint at c somewhere, i.e. he
## must actually hide for it (otherwise standing there is enough).
func _needs_hiding(path: PackedInt32Array, c: int) -> bool:
	for a in path:
		if _fp(a)[c] == 0:
			return true
	return false

## Footprint shaded = the cell and its left/right neighbours are walkable.
func _fp(a: int) -> PackedByteArray:
	if _fps[a] == null:
		_fps[a] = _footprint(_mask(a))
	return _fps[a]

func _footprint(m: PackedByteArray) -> PackedByteArray:
	var fp := PackedByteArray()
	fp.resize(_n)
	var cols := _grid.cols
	for i in _n:
		var x := i % cols
		if x > 0 and x < cols - 1 and m[i] != 0 and m[i - 1] != 0 and m[i + 1] != 0:
			fp[i] = 1
	return fp

func _lab(a: int) -> PackedInt32Array:
	if _labs[a] == null:
		_labs[a] = _grid.label_regions(_mask(a))
	return _labs[a]

func _mid_ok(a: int, b: int, c: int) -> bool:
	var key := mini(a, b) * 100000 + maxi(a, b)
	if not _mid_cache.has(key):
		var dir := SunRig.direction_from_angles((_az_of(a) + _az_of(b)) * 0.5, (_el_of(a) + _el_of(b)) * 0.5)
		_mid_cache[key] = _footprint(_grid.compute_walkable_fast(dir))
	return (_mid_cache[key] as PackedByteArray)[c] != 0

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

func _goal_in(st: int, goal_cells: Array[Vector2i]) -> Vector2i:
	var lab := _lab(_angle_of(st))
	var label := _label_of(st)
	for c in goal_cells:
		if lab[_grid.index_of(c)] == label:
			return c
	return Vector2i(-1, -1)

func _nearest_open(mask: PackedByteArray, c: Vector2i, radius: int) -> Vector2i:
	for r in range(0, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var nb := c + Vector2i(dx, dy)
				if _grid.in_bounds(nb) and mask[_grid.index_of(nb)] != 0:
					return nb
	return Vector2i(-1, -1)
