class_name ShadeGrid
extends Node3D

## ShadeGrid — gameplay truth for "where can Dracula walk?".
##
## The grid lies on the ground in this node's local XZ plane: x from 0 to size.x,
## z from 0 to -size.y (levels run toward −Z). Each cell is:
##   * SOLID   if a box (foot to head height) at the cell overlaps solid_mask bodies
##             (walls, buildings, the wagon, statues…), computed once at setup.
##   * SHADED  if a ray from the cell's ground point toward the sun hits the
##             shadow_caster layer — the exact test ShadowSensor uses, so the
##             rendered shadows, Dracula's exposure meter and walkable cells agree.
##   * WALKABLE = shaded and not solid.
##
## Performance (mobile): at setup every cell is ray-tested at `mask_samples` sun
## azimuths × `mask_elevation_samples` elevations across the level's ranges. Cells that never change are frozen as
## always-lit / always-shaded; only the "variable" cells (dilated by one cell for
## safety) are re-cast when the sun moves. Re-casts are time-sliced (`rays_per_frame`)
## and throttled to `max_updates_per_second` while the sun moves; refresh_soon() starts
## an immediate pass with a bigger budget (`settle_rays_per_frame`) when the sun settles,
## so the exact walkable area is ready within a few frames without a long frame spike.
## refresh_now() is the synchronous version (setup and tools).
##
## Pathfinding: A* over walkable cells with 8-way moves (no corner cutting) plus
## optional hops: a straight jump of up to max_hop_distance across non-solid, lit
## cells to another walkable cell.

## Emitted after a complete shade pass (all variable cells re-cast).
signal shade_updated

const CASTER_LAYER_BIT: int = 1 << 3   # project layer 4 "shadow_caster"

@export_group("Grid")
## Ground area covered by the grid, meters (x = width, y = depth along −Z).
@export var size: Vector2 = Vector2(12.0, 50.0)
## Cell edge length, meters (0.25–0.4 recommended).
@export_range(0.2, 1.0) var cell_size: float = 0.4
## Height above the ground of each cell's shade sample point (keep equal to
## Dracula's foot sample markers).
@export var sample_height: float = 0.15

@export_group("Physics")
@export var ray_length: float = 60.0
@export_flags_3d_physics var caster_mask: int = CASTER_LAYER_BIT
## Layers that make a cell solid (obstacles + shadow casters standing on the ground).
@export_flags_3d_physics var solid_mask: int = (1 << 2) | (1 << 3)
## Solid probe: vertical span (from, to) above the ground, and footprint inset.
@export var solid_probe_heights: Vector2 = Vector2(0.15, 1.9)
@export var solid_probe_inset: float = 0.04

@export_group("Movement")
## Longest sunlit gap Dracula may hop across, meters (0 = hops disabled).
@export var max_hop_distance: float = 1.0
## Extra path cost per hop (prefer walking when possible).
@export var hop_penalty: float = 2.0

@export_group("Performance")
## Sun azimuth × elevation samples used at setup to find cells that can change shade.
@export var mask_samples: int = 7
@export var mask_elevation_samples: int = 3
## Ray budget per physics frame for incremental re-casts.
@export var rays_per_frame: int = 300
## Ray budget per frame for the pass that runs when the sun settles.
@export var settle_rays_per_frame: int = 1200
## Throttle for incremental passes while the sun is moving.
@export var max_updates_per_second: float = 10.0

var cols: int = 0
var rows: int = 0

var _solid: PackedByteArray = PackedByteArray()
var _shaded: PackedByteArray = PackedByteArray()
var _variable: PackedInt32Array = PackedInt32Array()   # cell indices that can change shade
var _sun: SunRig
var _query: PhysicsRayQueryParameters3D
var _dirty: bool = false
var _sweep_pos: int = -1          # -1 = idle
var _sweep_dir: Vector3
var _last_sweep_start: float = -100.0
var _clock: float = 0.0
var _hop_cells: int = 0
var _budget: int = 300

func _ready() -> void:
	_query = PhysicsRayQueryParameters3D.new()
	_query.collide_with_areas = false
	set_physics_process(false)   # PDF §4: idle until setup()

## Builds the solid map, the variable-cell mask and the first shade pass.
## Call after the level's bodies are in the physics space (≥1 physics frame).
func setup(sun: SunRig, azimuth_min: float, azimuth_max: float, elevation_min: float, elevation_max: float) -> void:
	_sun = sun
	build_static()
	_build_variable_mask(azimuth_min, azimuth_max, elevation_min, elevation_max)
	refresh_now()
	set_physics_process(true)

## Grid dimensions + solid map only (no sun needed). Used by setup() and LevelSolver.
func build_static() -> void:
	cols = maxi(1, int(ceil(size.x / cell_size)))
	rows = maxi(1, int(ceil(size.y / cell_size)))
	_hop_cells = int(floor(max_hop_distance / cell_size)) + 1 if max_hop_distance > 0.0 else 0
	_build_solid()

# ── Queries ───────────────────────────────────────────────────────────────

func cell_count() -> int:
	return cols * rows

func index_of(c: Vector2i) -> int:
	return c.y * cols + c.x

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows

func cell_at(world: Vector3) -> Vector2i:
	var l := to_local(world)
	return Vector2i(int(floor(l.x / cell_size)), int(floor(-l.z / cell_size)))

func cell_center(c: Vector2i) -> Vector3:
	return to_global(Vector3((c.x + 0.5) * cell_size, 0.0, -(c.y + 0.5) * cell_size))

func is_solid(c: Vector2i) -> bool:
	return in_bounds(c) and _solid[index_of(c)] != 0

func is_shaded(c: Vector2i) -> bool:
	return in_bounds(c) and _shaded[index_of(c)] != 0

func is_walkable(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	var i := index_of(c)
	return _shaded[i] != 0 and _solid[i] == 0

func is_busy() -> bool:
	return _sweep_pos >= 0 or _dirty

## Nearest walkable cell within `radius` cells (for a start position on a cell edge).
func nearest_walkable(c: Vector2i, radius: int = 2) -> Vector2i:
	if is_walkable(c):
		return c
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var n := c + Vector2i(dx, dy)
			var d := dx * dx + dy * dy
			if d < best_d and is_walkable(n):
				best = n
				best_d = d
	return best

# ── Shade updates ─────────────────────────────────────────────────────────

## Ask for a re-cast (throttled, time-sliced). Call whenever the sun moves.
func request_refresh() -> void:
	_dirty = true

## Immediate (un-throttled) pass with the settle budget; is_busy() stays true until done.
func refresh_soon() -> void:
	_dirty = false
	_sweep_pos = 0
	_budget = settle_rays_per_frame
	_sweep_dir = _sun.get_toward_sun()

## Full synchronous re-cast of all variable cells at the sun's current angle.
func refresh_now() -> void:
	_dirty = false
	_sweep_pos = -1
	var dir := _sun.get_toward_sun()
	var space := get_world_3d().direct_space_state
	for i in _variable:
		_shaded[i] = 1 if _ray_shaded(space, i, dir) else 0
	shade_updated.emit()

func _physics_process(delta: float) -> void:
	_clock += delta
	if _sweep_pos < 0:
		if not _dirty or _clock - _last_sweep_start < 1.0 / max_updates_per_second:
			return
		_dirty = false
		_last_sweep_start = _clock
		_sweep_pos = 0
		_budget = rays_per_frame
		_sweep_dir = _sun.get_toward_sun()
	var space := get_world_3d().direct_space_state
	var end := mini(_sweep_pos + _budget, _variable.size())
	for k in range(_sweep_pos, end):
		var i := _variable[k]
		_shaded[i] = 1 if _ray_shaded(space, i, _sweep_dir) else 0
	_sweep_pos = end
	if _sweep_pos >= _variable.size():
		_sweep_pos = -1
		shade_updated.emit()

## Shade test for an arbitrary sun direction (used by the level validator).
func compute_walkable_for(dir: Vector3) -> PackedByteArray:
	var space := get_world_3d().direct_space_state
	var out := PackedByteArray()
	out.resize(cell_count())
	for i in cell_count():
		out[i] = 1 if _solid[i] == 0 and _ray_shaded(space, i, dir) else 0
	return out

func _ray_shaded(space: PhysicsDirectSpaceState3D, i: int, dir: Vector3) -> bool:
	@warning_ignore("integer_division")
	var c := Vector2i(i % cols, i / cols)
	var p := cell_center(c) + Vector3(0.0, sample_height, 0.0)
	return ShadowSensor.is_point_shaded(space, _query, p, dir, ray_length, caster_mask)

func _build_solid() -> void:
	_solid.resize(cell_count())
	_shaded.resize(cell_count())
	var space := get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	var span := solid_probe_heights.y - solid_probe_heights.x
	box.size = Vector3(cell_size - 2.0 * solid_probe_inset, span, cell_size - 2.0 * solid_probe_inset)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = solid_mask
	for i in cell_count():
		@warning_ignore("integer_division")
		var c := Vector2i(i % cols, i / cols)
		q.transform = Transform3D(global_basis, cell_center(c) + Vector3(0.0, solid_probe_heights.x + span * 0.5, 0.0))
		_solid[i] = 1 if not space.intersect_shape(q, 1).is_empty() else 0

func _build_variable_mask(az_min: float, az_max: float, el_min: float, el_max: float) -> void:
	var space := get_world_3d().direct_space_state
	var n := cell_count()
	var lit_seen := PackedByteArray()
	var shade_seen := PackedByteArray()
	lit_seen.resize(n)
	shade_seen.resize(n)
	var samples := maxi(2, mask_samples)
	var el_samples := maxi(1, mask_elevation_samples)
	for s in samples * el_samples:
		@warning_ignore("integer_division")
		var az := lerpf(az_min, az_max, float(s % samples) / float(samples - 1))
		@warning_ignore("integer_division")
		var el := el_min if el_samples == 1 else lerpf(el_min, el_max, float(s / samples) / float(el_samples - 1))
		var dir := SunRig.direction_from_angles(az, el)
		for i in n:
			if _solid[i] != 0:
				continue
			if _ray_shaded(space, i, dir):
				shade_seen[i] = 1
			else:
				lit_seen[i] = 1
	var variable := PackedByteArray()
	variable.resize(n)
	for i in n:
		if _solid[i] == 0 and lit_seen[i] != 0 and shade_seen[i] != 0:
			variable[i] = 1
		_shaded[i] = 1 if shade_seen[i] != 0 and lit_seen[i] == 0 else 0
	# Dilate by one cell: shade edges between samples may sit next to a variable cell.
	_variable = PackedInt32Array()
	for i in n:
		if _solid[i] != 0:
			continue
		@warning_ignore("integer_division")
		var c := Vector2i(i % cols, i / cols)
		var take := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nb := c + Vector2i(dx, dy)
				if in_bounds(nb) and variable[index_of(nb)] != 0:
					take = true
		if take:
			_variable.append(i)

func variable_cell_count() -> int:
	return _variable.size()

# ── Pathfinding ───────────────────────────────────────────────────────────

const _DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

## Neighbours of a walkable cell: [cell, cost, is_hop] triples.
func _neighbours(c: Vector2i, walkable: Callable) -> Array:
	var out := []
	for d in _DIRS:
		var n := c + d
		if not walkable.call(n):
			continue
		if d.x != 0 and d.y != 0 and (not walkable.call(c + Vector2i(d.x, 0)) or not walkable.call(c + Vector2i(0, d.y))):
			continue   # no corner cutting past sunlight / walls
		out.append([n, d.length(), false])
	if _hop_cells >= 2:
		for d in _DIRS:
			for k in range(2, _hop_cells + 1):
				var n := c + d * k
				if not in_bounds(n):
					break
				var blocked := false
				for m in range(1, k):
					if is_solid(c + d * m):
						blocked = true
						break
				if blocked:
					break
				if walkable.call(n) and not walkable.call(c + d):
					if (d * k).length() * cell_size <= max_hop_distance + 0.001:
						out.append([n, (d * k).length() + hop_penalty, true])
					break
	return out

## A* from `from` to `to` over walkable cells (+ hops). Returns
## {"cells": Array[Vector2i], "hops": Array[bool]} (hops[i] = the step INTO cells[i]
## is a hop), or an empty Dictionary when unreachable.
func find_path(from: Vector2i, to: Vector2i) -> Dictionary:
	var walk := Callable(self, "is_walkable")
	if not is_walkable(from) or not is_walkable(to):
		return {}
	var n := cell_count()
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(1.0e9)
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	var via_hop := PackedByteArray()
	via_hop.resize(n)
	var closed := PackedByteArray()
	closed.resize(n)
	var heap_f := PackedFloat32Array()
	var heap_i := PackedInt32Array()
	var start := index_of(from)
	var goal := index_of(to)
	g[start] = 0.0
	_heap_push(heap_f, heap_i, Vector2(from - to).length(), start)
	while heap_i.size() > 0:
		var cur := _heap_pop(heap_f, heap_i)
		if closed[cur] != 0:
			continue
		if cur == goal:
			break
		closed[cur] = 1
		@warning_ignore("integer_division")
		var c := Vector2i(cur % cols, cur / cols)
		for nb in _neighbours(c, walk):
			var ni := index_of(nb[0])
			if closed[ni] != 0:
				continue
			var ng: float = g[cur] + nb[1]
			if ng < g[ni]:
				g[ni] = ng
				parent[ni] = cur
				via_hop[ni] = 1 if nb[2] else 0
				_heap_push(heap_f, heap_i, ng + Vector2(nb[0] - to).length(), ni)
	if parent[goal] < 0 and goal != start:
		return {}
	var cells: Array[Vector2i] = []
	var hops: Array[bool] = []
	var i := goal
	while i != start:
		cells.push_front(Vector2i(i % cols, i / cols))
		hops.push_front(via_hop[i] != 0)
		i = parent[i]
	return {"cells": cells, "hops": hops}

## Connected-region labels for an arbitrary walkable mask (walking + hops).
## Returns one label per cell (-1 = not walkable). Used by LevelSolver.
func label_regions(mask: PackedByteArray) -> PackedInt32Array:
	var labels := PackedInt32Array()
	labels.resize(cell_count())
	labels.fill(-1)
	var walk := func(c: Vector2i) -> bool: return in_bounds(c) and mask[index_of(c)] != 0
	var next_label := 0
	for i in cell_count():
		if mask[i] == 0 or labels[i] >= 0:
			continue
		@warning_ignore("integer_division")
		var stack: Array[Vector2i] = [Vector2i(i % cols, i / cols)]
		labels[i] = next_label
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for nb in _neighbours(c, walk):
				var ni := index_of(nb[0])
				if labels[ni] < 0:
					labels[ni] = next_label
					stack.append(nb[0])
		next_label += 1
	return labels

## Flood fill of every cell reachable from `from` (walking + hops).
## Returns a byte mask (1 = reachable).
func region_from(from: Vector2i) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(cell_count())
	if not is_walkable(from):
		return mask
	var walk := Callable(self, "is_walkable")
	var stack: Array[Vector2i] = [from]
	mask[index_of(from)] = 1
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for nb in _neighbours(c, walk):
			var ni := index_of(nb[0])
			if mask[ni] == 0:
				mask[ni] = 1
				stack.append(nb[0])
	return mask

static func _heap_push(f: PackedFloat32Array, ids: PackedInt32Array, pri: float, id: int) -> void:
	f.append(pri)
	ids.append(id)
	var i := f.size() - 1
	while i > 0:
		@warning_ignore("integer_division")
		var p := (i - 1) / 2
		if f[p] <= f[i]:
			break
		var tf := f[p]
		f[p] = f[i]
		f[i] = tf
		var ti := ids[p]
		ids[p] = ids[i]
		ids[i] = ti
		i = p

static func _heap_pop(f: PackedFloat32Array, ids: PackedInt32Array) -> int:
	var top := ids[0]
	var last := f.size() - 1
	f[0] = f[last]
	ids[0] = ids[last]
	f.resize(last)
	ids.resize(last)
	var i := 0
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < last and f[l] < f[m]:
			m = l
		if r < last and f[r] < f[m]:
			m = r
		if m == i:
			break
		var tf := f[m]
		f[m] = f[i]
		f[i] = tf
		var ti := ids[m]
		ids[m] = ids[i]
		ids[i] = ti
		i = m
	return top
