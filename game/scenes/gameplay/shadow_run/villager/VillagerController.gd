@tool
class_name VillagerController
extends Node3D

## VillagerController — a patrolling villager (root of villager/Villager.tscn, an inherited
## scene of assets/models/Villager/villager.glb).
##
##   PATROL ──meter rising──► SUSPICIOUS ──meter full──► ALERT ──► CHASE ──in range──► ATTACK
##     ▲                         │ meter empty                        │ lost him / he hid      │
##     │                         ▼                                    ▼                        ▼
##     └──────────── RETURN ◄── SEARCH (search_time at the last seen spot) ◄──┘     `caught` → run fails
##
## Patrol: walks the points of `patrol_path` (a Path3D placed in the level) at walk_speed,
## waiting wait_time at each point (LookAround). The patrol is a fixed timeline
## (patrol_pose_at), so LevelValidatorRunner can simulate exactly where the villager looks.
## Vision: a cone (vision_range, vision_angle) from the eye plus a line-of-sight ray that
## walls and props (obstacle + shadow_caster layers) block. A hidden Dracula is never seen.
## Detection meter: fills while he is seen (faster in sun, slower in shade), fills
## instantly inside the lantern's light radius, drains when he is out of view.
##
## Everything visual is in the scene: the lantern light on a BoneAttachment3D, the ground
## cone (vision_cone.tres, sized by the mesh scale), the meter (detection_meter.tres) and
## its "?" / "!" label. Clothing colours are per-instance shader parameters
## (villager_cloth.gdshader), so placed villagers can be recoloured in the inspector.
## Gameplay wiring (Dracula, ShadeGrid, sensor, bus) arrives through setup() from
## ShadowRunFeature; until then the villager stands still.

## The attack landed: the run fails with reason "caught".
signal caught(villager: VillagerController)
signal state_changed(villager: VillagerController, new_state: State)

enum State { IDLE, PATROL, SUSPICIOUS, ALERT, CHASE, ATTACK, SEARCH, RETURN }
enum PatrolMode { LOOP, PING_PONG }

## Walls and props block sight: project layers 3 "obstacle" and 4 "shadow_caster".
const SIGHT_MASK: int = (1 << 2) | (1 << 3)

@export_group("Clothing")
@export var tunic_color: Color = Color(0.42, 0.29, 0.17):
	set(v):
		tunic_color = v
		_apply_looks()
@export var vest_color: Color = Color(0.3, 0.36, 0.2):
	set(v):
		vest_color = v
		_apply_looks()
@export var cap_color: Color = Color(0.24, 0.21, 0.18):
	set(v):
		cap_color = v
		_apply_looks()
@export var trousers_color: Color = Color(0.2, 0.16, 0.13):
	set(v):
		trousers_color = v
		_apply_looks()

@export_group("Patrol")
## Path3D in the level; its curve points are the patrol points (in order). Empty = guard
## who stands where placed, looking around.
@export var patrol_path: Path3D
## LOOP: last point → first point. PING_PONG: walk back along the points.
@export var patrol_mode: PatrolMode = PatrolMode.LOOP
@export var walk_speed: float = 1.5
## Seconds spent at each patrol point, playing LookAround.
@export var wait_time: float = 2.0
## Patrol clock at level start (s): shifts villagers that share a timing.
@export var start_time_offset: float = 0.0
@export var turn_speed_degrees: float = 300.0

@export_group("Vision")
@export var vision_range: float = 6.0:
	set(v):
		vision_range = v
		_apply_looks()
@export_range(10.0, 180.0) var vision_angle: float = 70.0:
	set(v):
		vision_angle = v
		_apply_looks()
## Once alerted (chasing / searching) the cone widens by this factor (capped at 180°).
@export var alert_angle_multiplier: float = 1.8
## Height of the line-of-sight target on Dracula (his chest).
@export var target_height: float = 1.1

@export_group("Detection")
## Seconds of continuous sight to fill the meter at multiplier 1.
@export var time_to_spot: float = 1.2
## Meter speed while Dracula stands in sunlight.
@export var sun_multiplier: float = 2.0
## Meter speed while Dracula stands in shade.
@export var shade_multiplier: float = 0.5
## Inside this distance of the lantern (and in line of sight) he is spotted instantly.
@export var lantern_spot_radius: float = 1.8
## Meter drained per second while he is out of view.
@export var drain_rate: float = 0.4
## Meter level at which the villager stops and turns toward him.
@export var suspicious_threshold: float = 0.05

@export_group("Chase")
@export var run_speed: float = 3.8
@export var attack_range: float = 1.2
## Seconds into the Attack clip when the hit lands.
@export var attack_hit_time: float = 0.45
## Seconds spent looking around the last seen spot.
@export var search_time: float = 3.0
## Seconds between chase re-paths (ShadeGrid ground A*, sunlight ignored).
@export var repath_interval: float = 0.25

@export_group("Lantern")
@export var lantern_range: float = 3.5:
	set(v):
		lantern_range = v
		_apply_looks()
@export var lantern_energy: float = 1.4:
	set(v):
		lantern_energy = v
		_apply_looks()

@export_group("Animation")
## Ground speed the Walk / Run clips were authored for (m/s); playback is scaled to match.
@export var walk_clip_speed: float = 1.4
@export var run_clip_speed: float = 3.6
@export var blend_time: float = 0.2

@export_group("Cone colours")
@export var calm_color: Color = Color(1.0, 0.86, 0.45)
@export var suspicious_color: Color = Color(1.0, 0.6, 0.2)
@export var alert_color: Color = Color(1.0, 0.18, 0.12)

@export_group("Scene parts")
@export var body_mesh: MeshInstance3D
@export var anim: AnimationPlayer
@export var lantern_attach: Node3D
@export var lantern_light: OmniLight3D
@export var eye: Node3D
@export var vision_cone: MeshInstance3D
@export var meter: MeshInstance3D
@export var meter_label: Label3D

var state: State = State.IDLE
var meter_value: float = 0.0

var _dracula: Node3D
var _grid: ShadeGrid
var _sensor: ShadowSensor
var _bus: Node
var _active: bool = false
var _target_hidden: bool = false
var _query: PhysicsRayQueryParameters3D

var _points: PackedVector3Array = PackedVector3Array()
var _seg_times: PackedFloat32Array = PackedFloat32Array()   # walk time of leg i (point i → next)
var _legs: PackedInt32Array = PackedInt32Array()            # leg i ends at point _legs[i]
var _period: float = 0.0
var _home_basis: Basis
var _home_pos: Vector3

var _patrol_clock: float = 0.0
var _resume_pos: Vector3
var _state_time: float = 0.0
var _last_seen: Vector3
var _seen: bool = false
var _in_lantern: bool = false
var _path: PackedVector3Array = PackedVector3Array()
var _path_i: int = 0
var _repath_wait: float = 0.0
var _hit_done: bool = false

func _ready() -> void:
	_apply_looks()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	process_physics_priority = 15   # after Dracula (0) and ShadowSensor (10), before the feature (20)
	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = SIGHT_MASK
	_query.collide_with_areas = false
	_home_pos = global_position
	_home_basis = global_basis
	_build_patrol()
	_place_on_timeline(start_time_offset)
	_play("Idle")
	_update_meter_visual()
	set_physics_process(false)

## Wiring from ShadowRunFeature (the level's composition point).
func setup(dracula: Node3D, grid: ShadeGrid, sensor: ShadowSensor, bus: Node) -> void:
	_dracula = dracula
	_grid = grid
	_sensor = sensor
	_bus = bus

## PLAYING → true; won / dead / leaving → false (stands still, Idle).
func set_active(on: bool) -> void:
	if Engine.is_editor_hint() or on == _active:
		return
	_active = on
	set_physics_process(on)
	if on:
		if state == State.IDLE:
			_set_state(State.PATROL)
	elif state != State.ATTACK:
		_play("Idle")

## Dracula hid (true) / left his hiding spot (false). Hidden = never seen.
func set_target_hidden(hidden: bool) -> void:
	_target_hidden = hidden

func is_alerted() -> bool:
	return state == State.ALERT or state == State.CHASE or state == State.ATTACK

# ── Patrol timeline (also used by LevelValidatorRunner's patrol check) ─────

## One full patrol cycle in seconds (0 for a standing guard).
func patrol_period() -> float:
	_build_patrol()
	return _period

## Where the villager is and which way it faces at patrol time t (seconds):
## {"position": Vector3, "forward": Vector3 (flat, unit), "moving": bool}.
func patrol_pose_at(t: float) -> Dictionary:
	_build_patrol()
	if _points.size() < 2 or _period <= 0.0:
		var fwd := _home_basis.z
		fwd.y = 0.0
		return {"position": _home_pos, "forward": fwd.normalized() if fwd.length() > 0.001 else Vector3.BACK, "moving": false}
	t = fposmod(t, _period)
	var from := _points[0]
	for i in _legs.size():
		var to := _points[_legs[i]]
		var dir := to - from
		dir.y = 0.0
		var fwd := dir.normalized() if dir.length() > 0.001 else Vector3.BACK
		var walk := _seg_times[i]
		if t < walk:
			return {"position": from.lerp(to, t / maxf(walk, 0.0001)), "forward": fwd, "moving": true}
		t -= walk
		if t < wait_time:
			return {"position": to, "forward": fwd, "moving": false}
		t -= wait_time
		from = to
	return {"position": _points[0], "forward": Vector3.BACK, "moving": false}

## Eye position for a villager standing at `ground` (validator + live sight).
func eye_offset() -> Vector3:
	return (eye.position if eye else Vector3(0.0, 1.6, 0.0))

## Line of sight from `from` to `to` through walls / props (obstacle + shadow_caster).
static func has_line_of_sight(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D, from: Vector3, to: Vector3) -> bool:
	query.from = from
	query.to = to
	query.collision_mask = SIGHT_MASK
	return space.intersect_ray(query).is_empty()

func _build_patrol() -> void:
	if not _points.is_empty() or patrol_path == null or patrol_path.curve == null or not is_inside_tree():
		return
	var curve := patrol_path.curve
	for i in curve.point_count:
		var p := patrol_path.to_global(curve.get_point_position(i))
		_points.append(p)
	if _points.size() < 2:
		return
	var order := PackedInt32Array()
	for i in range(1, _points.size()):
		order.append(i)
	if patrol_mode == PatrolMode.LOOP:
		order.append(0)
	else:
		for i in range(_points.size() - 2, -1, -1):
			order.append(i)
	_legs = order
	_seg_times.clear()
	_period = 0.0
	var from := _points[0]
	for i in _legs:
		var walk := from.distance_to(_points[i]) / maxf(walk_speed, 0.05)
		_seg_times.append(walk)
		_period += walk + wait_time
		from = _points[i]

func _place_on_timeline(t: float) -> void:
	_patrol_clock = t
	var pose := patrol_pose_at(t)
	global_position = pose.position
	rotation.y = _yaw_of(pose.forward)
	_resume_pos = global_position

# ── Per frame ─────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not _active:
		return
	_state_time += delta
	_sense(delta)
	match state:
		State.PATROL:
			_patrol(delta)
		State.SUSPICIOUS:
			_suspicious(delta)
		State.ALERT:
			_face(_last_seen - global_position, delta)
			if _state_time >= _clip_length("Alert"):
				_set_state(State.CHASE)
		State.CHASE:
			_chase(delta)
		State.ATTACK:
			_face(_dracula.global_position - global_position, delta)
			if not _hit_done and _state_time >= attack_hit_time:
				_hit_done = true
				caught.emit(self)
		State.SEARCH:
			if meter_value >= 1.0:
				_set_state(State.ALERT)
			elif _state_time >= search_time:
				_set_state(State.RETURN)
		State.RETURN:
			_return(delta)
	_update_meter_visual()

## Vision + detection meter.
func _sense(delta: float) -> void:
	_seen = false
	_in_lantern = false
	if state == State.ATTACK:
		return
	if _dracula == null or _target_hidden:
		if not _is_alert_state():
			meter_value = maxf(0.0, meter_value - drain_rate * delta)
		return
	var target := _dracula.global_position + Vector3(0.0, target_height, 0.0)
	var to := _dracula.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var lantern_pos := lantern_attach.global_position if lantern_attach else global_position
	_in_lantern = lantern_pos.distance_to(target) <= lantern_spot_radius
	var half := deg_to_rad(minf(180.0, vision_angle * (alert_angle_multiplier if _is_alert_state() else 1.0)) * 0.5)
	var fwd := global_basis.z
	fwd.y = 0.0
	var in_cone := dist <= vision_range and (dist < 0.3 or fwd.normalized().angle_to(to / maxf(dist, 0.0001)) <= half)
	if in_cone or _in_lantern:
		var space := get_world_3d().direct_space_state
		_seen = has_line_of_sight(space, _query, global_position + eye_offset(), target)
	if _seen:
		_last_seen = _dracula.global_position
		if _in_lantern:
			meter_value = 1.0
		else:
			var in_sun := _sensor != null and _sensor.exposure_fraction > 0.0
			meter_value += delta * (sun_multiplier if in_sun else shade_multiplier) / maxf(time_to_spot, 0.05)
	elif not _is_alert_state():
		meter_value -= drain_rate * delta
	meter_value = clampf(meter_value, 0.0, 1.0)
	_in_lantern = _in_lantern and _seen

func _is_alert_state() -> bool:
	return state == State.ALERT or state == State.CHASE or state == State.SEARCH

func _patrol(delta: float) -> void:
	if _seen and meter_value > suspicious_threshold:
		_set_state(State.SUSPICIOUS)
		return
	_patrol_clock += delta
	var pose := patrol_pose_at(_patrol_clock)
	global_position = pose.position
	_face(pose.forward, delta)
	if pose.moving:
		_play("Walk", walk_speed / maxf(walk_clip_speed, 0.05))
	else:
		_play("LookAround")

func _suspicious(delta: float) -> void:
	_face(_last_seen - global_position, delta)
	if meter_value >= 1.0:
		_set_state(State.ALERT)
	elif meter_value <= 0.0:
		_set_state(State.PATROL)   # never left the timeline: resume where it stopped

func _chase(delta: float) -> void:
	var target := _dracula.global_position if _seen else _last_seen
	var flat := target - global_position
	flat.y = 0.0
	if _seen and flat.length() <= attack_range:
		_set_state(State.ATTACK)
		return
	_repath_wait -= delta
	if _repath_wait <= 0.0:
		_repath_wait = repath_interval
		_repath(target)
	if not _seen and (flat.length() < 0.5 or _path_i >= _path.size()):
		_set_state(State.SEARCH)
		return
	_walk_path(delta, run_speed)

func _return(delta: float) -> void:
	if _seen and meter_value > suspicious_threshold:
		_set_state(State.SUSPICIOUS)
		return
	_repath_wait -= delta
	if _repath_wait <= 0.0 and _path.is_empty():
		_repath(_resume_pos)
		_repath_wait = 1.0
	var flat := _resume_pos - global_position
	flat.y = 0.0
	if flat.length() < 0.15 or (_path_i >= _path.size() and flat.length() < 0.6):
		global_position = _resume_pos
		_set_state(State.PATROL)
		return
	if _path_i >= _path.size():
		_path = PackedVector3Array([_resume_pos])
		_path_i = 0
	_walk_path(delta, walk_speed)

func _repath(target: Vector3) -> void:
	_path = PackedVector3Array()
	_path_i = 0
	if _grid and _grid.cols > 0:
		var cells := _grid.find_ground_path(_grid.cell_at(global_position), _grid.cell_at(target))
		for c in cells:
			_path.append(_grid.cell_center(c))
	if _path.is_empty():
		_path.append(target)
	else:
		_path[_path.size() - 1] = Vector3(target.x, _path[_path.size() - 1].y, target.z)

func _walk_path(delta: float, speed: float) -> void:
	if _path_i >= _path.size():
		_play("Idle")
		return
	var step := speed * delta
	var dir := Vector3.ZERO
	while _path_i < _path.size() and step > 0.0:
		var to := _path[_path_i] - global_position
		to.y = 0.0
		var d := to.length()
		if d <= step:
			global_position += to
			step -= d
			_path_i += 1
		else:
			dir = to / d
			global_position += dir * step
			step = 0.0
	if dir != Vector3.ZERO:
		_face(dir, delta)
	var running := speed > walk_speed + 0.01
	_play("Run" if running else "Walk", speed / maxf(run_clip_speed if running else walk_clip_speed, 0.05))

func _set_state(s: State) -> void:
	if s == state:
		return
	var old := state
	state = s
	_state_time = 0.0
	match s:
		State.SUSPICIOUS:
			if old == State.PATROL:
				_resume_pos = global_position
			_play("LookAround")
		State.ALERT:
			if old == State.PATROL:
				_resume_pos = global_position
			meter_value = 1.0
			_play("Alert", 1.0, 0.1)
			if _bus and _bus.has_signal("villager_alerted"):
				_bus.villager_alerted.emit(name)
		State.CHASE:
			_repath_wait = 0.0
		State.ATTACK:
			_hit_done = false
			_play("Attack", 1.0, 0.1)
		State.SEARCH:
			meter_value = minf(meter_value, 0.6)
			_play("LookAround")
		State.RETURN:
			_path = PackedVector3Array()
			_repath_wait = 0.0
	state_changed.emit(self, s)

# ── Visuals ───────────────────────────────────────────────────────────────

func _face(dir: Vector3, delta: float) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	rotation.y = rotate_toward(rotation.y, _yaw_of(dir), deg_to_rad(turn_speed_degrees) * delta)

## Model faces +Z: yaw that turns +Z toward `dir`.
static func _yaw_of(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)

func _play(clip: StringName, speed: float = 1.0, blend: float = -1.0) -> void:
	if anim == null:
		return
	if anim.current_animation != String(clip):
		anim.play(clip, blend_time if blend < 0.0 else blend)
	anim.speed_scale = speed

func _clip_length(clip: StringName) -> float:
	return anim.get_animation(clip).length if anim and anim.has_animation(clip) else 0.9

func _update_meter_visual() -> void:
	var col := calm_color
	if _is_alert_state() or state == State.ATTACK:
		col = alert_color
	elif state == State.SUSPICIOUS or meter_value > suspicious_threshold:
		col = calm_color.lerp(suspicious_color, clampf(meter_value * 1.5, 0.0, 1.0))
	if vision_cone:
		vision_cone.set_instance_shader_parameter("cone_color", col)
		vision_cone.set_instance_shader_parameter("alertness", 1.0 if state == State.CHASE or state == State.ATTACK else meter_value)
		vision_cone.set_instance_shader_parameter("half_angle",
			deg_to_rad(minf(180.0, vision_angle * (alert_angle_multiplier if _is_alert_state() else 1.0)) * 0.5))
	var show := meter_value > 0.01 or (state != State.PATROL and state != State.IDLE and state != State.RETURN)
	if meter:
		meter.visible = show
		meter.set_instance_shader_parameter("fill", meter_value)
	if meter_label:
		meter_label.visible = show and state != State.PATROL
		meter_label.text = "!" if is_alerted() else "?"
		meter_label.modulate = alert_color if is_alerted() else suspicious_color

## Clothing colours, cone size/angle and lantern light: in the editor too (@tool).
func _apply_looks() -> void:
	if not is_node_ready():
		return
	if body_mesh:
		body_mesh.set_instance_shader_parameter("tunic_color", tunic_color)
		body_mesh.set_instance_shader_parameter("vest_color", vest_color)
		body_mesh.set_instance_shader_parameter("cap_color", cap_color)
		body_mesh.set_instance_shader_parameter("trousers_color", trousers_color)
	if vision_cone:
		vision_cone.scale = Vector3(vision_range, 1.0, vision_range)
		vision_cone.set_instance_shader_parameter("half_angle", deg_to_rad(vision_angle * 0.5))
		vision_cone.set_instance_shader_parameter("cone_color", calm_color)
	if lantern_light:
		lantern_light.omni_range = lantern_range
		lantern_light.light_energy = lantern_energy
