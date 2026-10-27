class_name TrackSpawner
extends Node3D

## TrackSpawner — pooled, recycling road. Every segment copy is instantiated once
## in prewarm() at load time; during the run segments are only moved, never
## instantiated or freed. ~active_count segments are live; a segment whose far
## end is recycle_distance behind Dracula goes back to the pool and the next
## segment is pulled to the front.
## PDF §4 CPU: pooled segments are hidden + PROCESS_MODE_DISABLED (no ticking, no physics).
## PDF §6: free lists per segment id → O(1) checkout/return.
## "Never block every lane": segments never overlap in Z, so a lane can only be fully
## blocked inside one segment. SegmentValidator rejects any segment where all lanes are
## blocked at the same distance with ALL optional obstacles on (the worst roll), so no
## density roll here can ever close the road.

@export var segment_scenes: Array[PackedScene] = []
## Lane layout (track/lane_config.tres); pushed into the road material's dividers.
@export var lanes: LaneConfig
## road_cobbles.tres, shared by every segment's road mesh.
@export var road_material: ShaderMaterial
@export var copies_per_scene: int = 2
@export var active_count: int = 7
## Meters behind Dracula before a passed segment is recycled (camera sits ~8 m behind).
@export var recycle_distance: float = 14.0

var _difficulty: RunDifficulty
var _logger: Node
var _rng := RandomNumberGenerator.new()
var _free: Dictionary = {}            # StringName -> Array[TrackSegment]
var _ids: Array[StringName] = []
var _active: Array[TrackSegment] = []  # ordered: [0] is the one Dracula is on / just passed
var _next_start_z: float = 0.0
var _onboarding_index: int = 0
var _last_id: StringName = &""
var _last_exit_azimuth: float = 0.0
var _prewarmed: bool = false

func _ready() -> void:
	set_process(false)
	set_physics_process(false)   # PDF §4: driven by ShadowRunFeature.update(), no own tick

func setup(difficulty: RunDifficulty, logger: Node, rng_seed: int = -1) -> void:
	_difficulty = difficulty
	_logger = logger
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()

## Instantiates every pooled copy. Call once while the scene loads.
func prewarm() -> void:
	if _prewarmed:
		return
	_prewarmed = true
	if lanes and road_material:
		road_material.set_shader_parameter("lane_count", lanes.lane_count)
		road_material.set_shader_parameter("lane_width", lanes.lane_width)
	for packed in segment_scenes:
		for i in copies_per_scene:
			var seg := packed.instantiate() as TrackSegment
			add_child(seg)
			seg.set_pooled(true)
			if not _free.has(seg.segment_id):
				_free[seg.segment_id] = []
				_ids.append(seg.segment_id)
			(_free[seg.segment_id] as Array).append(seg)
	if _logger:
		_logger.info("TrackSpawner: prewarmed", {"segments": _ids.size(), "copies": get_child_count()})

## Lays out the first active_count segments starting at world z = 0.
func reset_track() -> void:
	while not _active.is_empty():
		_recycle(_active.pop_front())
	_next_start_z = 0.0
	_onboarding_index = 0
	_last_id = &""
	_last_exit_azimuth = 0.0
	for i in active_count:
		_spawn_next(0.0, 0.0, _difficulty.speed_min if _difficulty else 9.0)

## Called every physics frame by the feature.
func update(player_z: float, run_time: float, speed: float) -> void:
	while not _active.is_empty() and (_active[0].position.z - _active[0].length) > player_z + recycle_distance:
		_recycle(_active.pop_front())
		_spawn_next(player_z, run_time, speed)

func segment_at(z: float) -> TrackSegment:
	for seg in _active:
		if z <= seg.position.z and z > seg.position.z - seg.length:
			return seg
	return null

func active_segments() -> Array[TrackSegment]:
	return _active

# ── Internals ─────────────────────────────────────────────────────────────

func _spawn_next(player_z: float, run_time: float, speed: float) -> void:
	# Predict when Dracula will reach this segment so difficulty matches that moment.
	var eta := run_time + maxf(0.0, player_z - _next_start_z) / maxf(speed, 1.0)
	var seg := _pick(eta)
	if seg == null:
		if _logger:
			_logger.error("TrackSpawner: pool exhausted — raise copies_per_scene")
		return
	(_free[seg.segment_id] as Array).erase(seg)
	seg.position = Vector3(0.0, 0.0, _next_start_z)
	seg.set_pooled(false)
	var density := _difficulty.obstacle_density_at(eta) if _difficulty else 0.0
	seg.roll_optional_obstacles(density, _rng)
	_next_start_z -= seg.length
	_active.append(seg)
	_last_id = seg.segment_id
	_last_exit_azimuth = seg.exit_azimuth()

func _recycle(seg: TrackSegment) -> void:
	seg.set_pooled(true)
	(_free[seg.segment_id] as Array).append(seg)

func _pick(eta: float) -> TrackSegment:
	if _difficulty == null:
		return _take_any()
	# Onboarding: fixed gentle sequence.
	if eta < _difficulty.onboarding_duration_s and _onboarding_index < _difficulty.onboarding_sequence.size():
		var id := _difficulty.onboarding_sequence[_onboarding_index]
		_onboarding_index += 1
		var seg := _take(id)
		if seg:
			return seg
	var max_d := _difficulty.max_difficulty_at(eta)
	var min_d := max_d - _difficulty.difficulty_window
	var want_delta := _difficulty.desired_sun_delta_at(eta)
	var candidates: Array[TrackSegment] = []
	var weights: PackedFloat32Array = []
	var total := 0.0
	for id in _ids:
		if id == _last_id:
			continue
		var pool: Array = _free[id]
		if pool.is_empty():
			continue
		var seg := pool[0] as TrackSegment
		if seg.difficulty > max_d + 0.001 or seg.difficulty < min_d:
			continue
		# Prefer segments whose entry sun angle is ~want_delta away from the last exit.
		var delta := absf(seg.entry_azimuth() - _last_exit_azimuth)
		var w := seg.weight / (1.0 + absf(delta - want_delta) / 30.0)
		candidates.append(seg)
		weights.append(w)
		total += w
	if candidates.is_empty():
		return _take_any()
	var r := _rng.randf() * total
	for i in candidates.size():
		r -= weights[i]
		if r <= 0.0:
			return candidates[i]
	return candidates[candidates.size() - 1]

func _take(id: StringName) -> TrackSegment:
	var pool: Array = _free.get(id, [])
	return pool[0] as TrackSegment if not pool.is_empty() else null

func _take_any() -> TrackSegment:
	for id in _ids:
		if id != _last_id and not (_free[id] as Array).is_empty():
			return (_free[id] as Array)[0] as TrackSegment
	for id in _ids:
		if not (_free[id] as Array).is_empty():
			return (_free[id] as Array)[0] as TrackSegment
	return null
