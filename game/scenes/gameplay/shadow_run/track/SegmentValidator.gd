class_name SegmentValidator
extends Resource

## SegmentValidator — proves a TrackSegment is fair AND that the sun matters.
## Settings are saved in track/segment_validator.tres (keep burn/heal rates and
## sample heights in sync with ShadowSensor / Dracula.tscn).
##
## It samples the real physics world (same ray test as ShadowSensor) on a grid of
##   distance (z_resolution m) × lane × sun angle (azimuth × elevation)
## and records the lit fraction of Dracula's 3 sample points per cell, plus which
## lane cells are blocked by obstacles. A time-stepped search then simulates the
## exposure meter (burn_rate / heal_rate) while Dracula may change one lane (then must stay min_lane_dwell s) and the
## sun may move one grid step per tick (tick = az grid step / max sun speed).
##
## Errors (validation fails):
##   * unsolvable          — no lane+sun path keeps exposure < 100 (optional obstacles ON).
##   * sun_irrelevant      — a lane path survives even under the WORST sun angle at every
##                           step, i.e. the sun can be ignored (optional obstacles OFF).
##   * lane_always_safe    — one lane, ridden straight through, survives the worst sun
##                           angle (the narrow 3-lane road makes this the easy failure).
##   * all_lanes_blocked   — at some distance every lane is physically blocked
##                           (optional obstacles ON = worst case).
##   * sun_optional        — every single fixed sun angle solves the segment.
##   * needs_sun_move      — requires_sun_move is set but some fixed angle solves it.
##   * bad_window          — a declared SegmentSafeWindow is not actually shaded.
##   * no_windows          — no safe window declared.
## Warnings:
##   * all_shaded          — some angle shades >90% of the road (sun parks there).
##   * lane_mostly_shaded  — a lane is shaded at EVERY sun angle for > always_shaded_warn
##                           of its length.

const INF_EXPOSURE: float = 1.0e9

## Lane layout (track/lane_config.tres) — the same resource Dracula uses.
@export var lanes: LaneConfig
@export var sample_heights: PackedFloat32Array = PackedFloat32Array([0.2, 1.0, 1.65])
@export var azimuths: PackedFloat32Array = PackedFloat32Array([-70, -60, -50, -40, -30, -20, -10, 0, 10, 20, 30, 40, 50, 60, 70])
@export var elevations: PackedFloat32Array = PackedFloat32Array([18.0, 28.5, 39.0, 49.5, 60.0])
@export var z_resolution: float = 0.5
@export var ray_length: float = 60.0
@export_flags_3d_physics var caster_mask: int = ShadowSensor.CASTER_LAYER_BIT
@export_flags_3d_physics var obstacle_mask: int = 1 << 2   # project layer 3 "obstacle"
@export var hitbox_size: Vector3 = Vector3(0.7, 1.5, 0.5)
@export var burn_rate: float = 100.0 / 1.2
@export var heal_rate: float = 32.0
## Exposure Dracula is assumed to carry into the segment.
@export var entry_exposure: float = 25.0
@export var min_speed: float = 9.0
@export var max_speed: float = 17.0
@export var max_azimuth_speed: float = 135.0
@export var max_elevation_speed: float = 135.0
## Seconds Dracula must stay in a lane after switching (models human reaction time).
@export var min_lane_dwell: float = 0.3
## Fraction of a safe window's samples that must be shaded.
@export var window_tolerance: float = 0.85
## Warn when a lane is shaded at every sun angle for more than this fraction of its length.
@export var always_shaded_warn: float = 0.4

class Grid:
	var z_count: int
	var lanes: int
	var angles: int
	var frac: PackedFloat32Array      # [z][lane][angle]
	var blocked: PackedByteArray      # [z][lane]

	func idx(z: int, lane: int, angle: int) -> int:
		return (z * lanes + lane) * angles + angle

	func is_blocked(z: int, lane: int) -> bool:
		return blocked[z * lanes + lane] != 0

func angle_count() -> int:
	return azimuths.size() * elevations.size()

func angle_index(az_i: int, el_i: int) -> int:
	return az_i * elevations.size() + el_i

## Expected run speed when a segment of this difficulty shows up.
func speed_for(segment: TrackSegment) -> float:
	return lerpf(min_speed, max_speed, segment.difficulty)

## Samples the physics world. The segment must be in the tree and its bodies synced
## (wait ≥2 physics frames after adding it / toggling obstacles).
func sample_grid(segment: TrackSegment, space: PhysicsDirectSpaceState3D) -> Grid:
	var g := Grid.new()
	g.z_count = int(ceil(segment.length / z_resolution))
	var lane_x := lanes.positions()
	g.lanes = lane_x.size()
	g.angles = angle_count()
	g.frac.resize(g.z_count * g.lanes * g.angles)
	g.blocked.resize(g.z_count * g.lanes)
	var xf := segment.global_transform
	var ray := PhysicsRayQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = hitbox_size
	var shape_q := PhysicsShapeQueryParameters3D.new()
	shape_q.shape = box
	shape_q.collision_mask = obstacle_mask
	var dirs: Array[Vector3] = []
	for az_i in azimuths.size():
		for el_i in elevations.size():
			dirs.append(SunRig.direction_from_angles(azimuths[az_i], elevations[el_i]))
	var inv_samples := 1.0 / float(sample_heights.size())
	for z in g.z_count:
		var d := (z + 0.5) * z_resolution
		for lane in g.lanes:
			shape_q.transform = Transform3D(Basis.IDENTITY, xf * Vector3(lane_x[lane], 0.85, -d))
			g.blocked[z * g.lanes + lane] = 1 if not space.intersect_shape(shape_q, 1).is_empty() else 0
			for a in g.angles:
				var lit := 0
				for h in sample_heights:
					var p := xf * Vector3(lane_x[lane], h, -d)
					if not ShadowSensor.is_point_shaded(space, ray, p, dirs[a], ray_length, caster_mask):
						lit += 1
				g.frac[g.idx(z, lane, a)] = lit * inv_samples
	return g

## grid_all: optional obstacles enabled. grid_required: optional obstacles disabled.
func analyze(segment: TrackSegment, grid_all: Grid, grid_required: Grid) -> Dictionary:
	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []
	var speed := speed_for(segment)

	var solvable := _solve(grid_all, speed, -1, false)
	if not solvable:
		errors.append("unsolvable: no lane+sun path keeps exposure below 100 at %.1f m/s" % speed)

	var irrelevant := _solve(grid_required, speed, -1, true)
	if irrelevant:
		errors.append("sun_irrelevant: a lane path survives under the worst sun angle everywhere")

	for lane in grid_required.lanes:
		if _lane_survives_worst_case(grid_required, speed, lane):
			errors.append("lane_always_safe: lane %d is safe at every sun angle all the way through" % lane)
		var always := _always_shaded_fraction(grid_required, lane)
		if always > always_shaded_warn:
			warnings.append("lane_mostly_shaded: lane %d is shaded at every sun angle for %.0f%% of the segment" % [lane, always * 100.0])
	var blocked_at := _first_fully_blocked(grid_all)
	if blocked_at >= 0.0:
		errors.append("all_lanes_blocked: every lane is blocked at %.1f m" % blocked_at)

	var fixed_ok := 0
	var fixed_solutions: PackedStringArray = []
	for az_i in azimuths.size():
		for el_i in elevations.size():
			if _solve(grid_required, speed, angle_index(az_i, el_i), false):
				fixed_ok += 1
				fixed_solutions.append("%d/%d" % [int(azimuths[az_i]), int(elevations[el_i])])
	if fixed_ok == angle_count():
		errors.append("sun_optional: every fixed sun angle solves the segment")
	elif segment.requires_sun_move and fixed_ok > 0:
		errors.append("needs_sun_move: fixed angles solve it: %s" % ", ".join(fixed_solutions))

	if segment.safe_windows.is_empty():
		errors.append("no_windows: declare at least one SegmentSafeWindow")
	for w in segment.safe_windows:
		var ratio := _window_shaded_ratio(grid_required, w)
		if ratio < window_tolerance:
			errors.append("bad_window: %s only %.0f%% shaded" % [w.describe(), ratio * 100.0])

	var coverage := _coverage(grid_required)
	if coverage.y > 0.9:
		warnings.append("all_shaded: one sun angle shades %.0f%% of the road" % (coverage.y * 100.0))

	return {
		"id": String(segment.segment_id),
		"speed": speed,
		"solvable": solvable,
		"sun_irrelevant": irrelevant,
		"fixed_angle_solutions": fixed_ok,
		"angle_count": angle_count(),
		"coverage_min": coverage.x,
		"coverage_max": coverage.y,
		"errors": errors,
		"warnings": warnings,
		"passed": errors.is_empty(),
	}

# ── Search ────────────────────────────────────────────────────────────────
# fixed_angle >= 0 : sun locked to that angle.   worst_case : per cell use the
# maximum lit fraction over all angles (the sun is ignored / adversarial).

func _solve(g: Grid, speed: float, fixed_angle: int, worst_case: bool) -> bool:
	var dt := (azimuths[1] - azimuths[0]) / max_azimuth_speed
	var dz := speed * dt
	var el_every := maxi(1, int(ceil(((elevations[1] - elevations[0]) / max_elevation_speed) / dt)))
	# Humans cannot weave every tick: after a lane change Dracula stays put for `dwell` ticks.
	var dwell := maxi(1, int(ceil(min_lane_dwell / dt)))
	var steps := int(ceil(g.z_count * z_resolution / dz))
	var sun_moves := fixed_angle < 0 and not worst_case
	var n_angles := g.angles if sun_moves else 1
	var n_az := azimuths.size()
	var n_el := elevations.size()
	# state = (lane, angle, cooldown) -> lowest exposure reachable
	var cur := PackedFloat32Array()
	cur.resize(g.lanes * n_angles * dwell)
	cur.fill(INF_EXPOSURE)
	for lane in g.lanes:
		for s in n_angles:
			cur[(lane * n_angles + s) * dwell] = entry_exposure
	var nxt := PackedFloat32Array()
	nxt.resize(cur.size())
	for step in steps:
		var z := mini(int(((step + 0.5) * dz) / z_resolution), g.z_count - 1)
		nxt.fill(INF_EXPOSURE)
		var any := false
		var el_moves := (step % el_every) == 0
		for lane in g.lanes:
			for s in n_angles:
				for c in dwell:
					var e := cur[(lane * n_angles + s) * dwell + c]
					if e >= INF_EXPOSURE:
						continue
					var lo := lane if c > 0 else maxi(0, lane - 1)
					var hi := lane if c > 0 else mini(g.lanes - 1, lane + 1)
					for nl in range(lo, hi + 1):
						if g.is_blocked(z, nl):
							continue
						var nc := maxi(0, c - 1) if nl == lane else dwell - 1
						if not sun_moves:
							var ne := _step_exposure(e, _frac(g, z, nl, fixed_angle, worst_case), dt)
							var k := nl * dwell + nc
							if ne < 100.0 and ne < nxt[k]:
								nxt[k] = ne
								any = true
							continue
						@warning_ignore("integer_division")
						var az_i := s / n_el
						var el_i := s % n_el
						for daz in range(-1, 2):
							var na := az_i + daz
							if na < 0 or na >= n_az:
								continue
							for d_el in range(-1, 2):
								if d_el != 0 and not el_moves:
									continue
								var ne_i := el_i + d_el
								if ne_i < 0 or ne_i >= n_el:
									continue
								var a := na * n_el + ne_i
								var ne := _step_exposure(e, g.frac[g.idx(z, nl, a)], dt)
								var k := (nl * n_angles + a) * dwell + nc
								if ne < 100.0 and ne < nxt[k]:
									nxt[k] = ne
									any = true
		if not any:
			return false
		var tmp := cur
		cur = nxt
		nxt = tmp
	return true

func _frac(g: Grid, z: int, lane: int, fixed_angle: int, worst_case: bool) -> float:
	if not worst_case:
		return g.frac[g.idx(z, lane, fixed_angle)]
	var worst := 0.0
	for a in g.angles:
		worst = maxf(worst, g.frac[g.idx(z, lane, a)])
	return worst

func _step_exposure(e: float, frac: float, dt: float) -> float:
	if frac > 0.0:
		return e + burn_rate * frac * dt
	return maxf(0.0, e - heal_rate * dt)

## Straight run down one lane under the worst sun angle at every sample.
func _lane_survives_worst_case(g: Grid, speed: float, lane: int) -> bool:
	var dt := (azimuths[1] - azimuths[0]) / max_azimuth_speed
	var dz := speed * dt
	var e := entry_exposure
	for step in int(ceil(g.z_count * z_resolution / dz)):
		var z := mini(int(((step + 0.5) * dz) / z_resolution), g.z_count - 1)
		if g.is_blocked(z, lane):
			return false
		e = _step_exposure(e, _frac(g, z, lane, -1, true), dt)
		if e >= 100.0:
			return false
	return true

func _always_shaded_fraction(g: Grid, lane: int) -> float:
	var count := 0
	for z in g.z_count:
		if _frac(g, z, lane, -1, true) <= 0.34:
			count += 1
	return float(count) / float(g.z_count)

## Distance (m) of the first sample where every lane is blocked, or -1.
func _first_fully_blocked(g: Grid) -> float:
	for z in g.z_count:
		var free := false
		for lane in g.lanes:
			if not g.is_blocked(z, lane):
				free = true
				break
		if not free:
			return (z + 0.5) * z_resolution
	return -1.0

func _window_shaded_ratio(g: Grid, w: SegmentSafeWindow) -> float:
	var total := 0
	var shaded := 0
	for z in g.z_count:
		var d := (z + 0.5) * z_resolution
		if d < w.start_m or d > w.end_m:
			continue
		for az_i in azimuths.size():
			if azimuths[az_i] < w.azimuth_min or azimuths[az_i] > w.azimuth_max:
				continue
			for el_i in elevations.size():
				if elevations[el_i] < w.elevation_min or elevations[el_i] > w.elevation_max:
					continue
				total += 1
				# "Shaded" = at most one of three sample points lit.
				if g.frac[g.idx(z, w.lane, angle_index(az_i, el_i))] <= 0.34:
					shaded += 1
	return float(shaded) / float(total) if total > 0 else 0.0

## x = least-shaded angle's road coverage, y = most-shaded angle's coverage.
func _coverage(g: Grid) -> Vector2:
	var lo := 1.0
	var hi := 0.0
	var cells := float(g.z_count * g.lanes)
	for a in g.angles:
		var shaded := 0
		for z in g.z_count:
			for lane in g.lanes:
				if g.frac[g.idx(z, lane, a)] <= 0.34:
					shaded += 1
		var c := shaded / cells
		lo = minf(lo, c)
		hi = maxf(hi, c)
	return Vector2(lo, hi)
