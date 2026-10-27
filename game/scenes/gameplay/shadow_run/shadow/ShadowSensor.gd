class_name ShadowSensor
extends Node3D

## ShadowSensor — gameplay truth for "is Dracula in shade?".
## Never reads the shadow map or rendered pixels. Each physics frame it casts one
## ray per sample point (feet, torso, head) toward the sun, masked to the
## `shadow_caster` physics layer. A blocked ray = that point is shaded.
##   exposure_fraction = lit_points / sample_points
## The exposure meter (0..100) rises at burn_rate * exposure_fraction per second
## and recovers at heal_rate in full shade. At 100 `burned_out` fires once.
## Casters must therefore carry a simplified collision shape on the
## shadow_caster layer that matches their visible, shadow-casting mesh.

## Meaningful exposure change (≥ emit_step, or touching 0/100). Not every frame.
signal exposure_changed(value: float)
## Exposure reached 100. Fires once until reset().
signal burned_out

const CASTER_LAYER_BIT: int = 1 << 3   # project layer 4 "shadow_caster"

@export var ray_length: float = 60.0
@export_flags_3d_physics var caster_mask: int = CASTER_LAYER_BIT
## Exposure per second at full exposure. 100 / 1.2 → empty-to-dead in ~1.2 s.
@export var burn_rate: float = 100.0 / 1.2
## Recovery per second in full shade (slower than burning).
@export var heal_rate: float = 32.0
## Minimum change before exposure_changed is emitted.
@export var emit_step: float = 1.0

var exposure: float = 0.0
var exposure_fraction: float = 0.0

# Debug data for ShadowDebugOverlay (filled every sample; no allocations per frame).
var debug_from: PackedVector3Array = PackedVector3Array()
var debug_to: PackedVector3Array = PackedVector3Array()
var debug_lit: Array[bool] = []

var _points: Array[Node3D] = []
var _sun: SunRig
var _query: PhysicsRayQueryParameters3D
var _last_emitted: float = -100.0
var _burned: bool = false

func _ready() -> void:
	# Run after Dracula has moved and the sun has rotated this physics frame.
	process_physics_priority = 10
	_query = PhysicsRayQueryParameters3D.new()
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	set_physics_process(false)   # PDF §4: idle until the run starts

## Dependencies: the sample points on Dracula and the sun rig.
func setup(sample_points: Array[Node3D], sun_rig: SunRig) -> void:
	_points = sample_points
	_sun = sun_rig
	debug_from.resize(_points.size())
	debug_to.resize(_points.size())
	debug_lit.resize(_points.size())

func set_active(active: bool) -> void:
	set_physics_process(active)

func reset() -> void:
	exposure = 0.0
	exposure_fraction = 0.0
	_burned = false
	_last_emitted = -100.0
	_emit_if_meaningful(true)

## True when the segment from `point` toward the sun hits a shadow caster.
static func is_point_shaded(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D,
		point: Vector3, toward_sun: Vector3, length: float, mask: int) -> bool:
	query.from = point
	query.to = point + toward_sun * length
	query.collision_mask = mask
	return not space.intersect_ray(query).is_empty()

## Samples all points now and returns the lit fraction (0 = fully shaded).
func sample() -> float:
	if _sun == null or _points.is_empty():
		return 0.0
	var space := get_world_3d().direct_space_state
	var toward := _sun.get_toward_sun()
	var lit := 0
	for i in _points.size():
		var p := _points[i].global_position
		var shaded := is_point_shaded(space, _query, p, toward, ray_length, caster_mask)
		debug_from[i] = p
		debug_to[i] = p + toward * ray_length
		debug_lit[i] = not shaded
		if not shaded:
			lit += 1
	exposure_fraction = float(lit) / float(_points.size())
	return exposure_fraction

## Advances the meter by delta seconds using the latest exposure_fraction.
func integrate(delta: float) -> void:
	if exposure_fraction > 0.0:
		exposure += burn_rate * exposure_fraction * delta
	else:
		exposure -= heal_rate * delta
	exposure = clampf(exposure, 0.0, 100.0)
	_emit_if_meaningful(false)
	if exposure >= 100.0 and not _burned:
		_burned = true
		burned_out.emit()

func _physics_process(delta: float) -> void:
	sample()
	integrate(delta)

func _emit_if_meaningful(force: bool) -> void:
	var at_edge := (exposure <= 0.0 or exposure >= 100.0) and exposure != _last_emitted
	if force or at_edge or absf(exposure - _last_emitted) >= emit_step:
		_last_emitted = exposure
		exposure_changed.emit(exposure)
