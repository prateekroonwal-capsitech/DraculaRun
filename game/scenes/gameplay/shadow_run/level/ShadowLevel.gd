class_name ShadowLevel
extends Node3D

## ShadowLevel — root of a hand-authored level scene (levels/LevelNN.tscn).
## Everything about the puzzle is set here in the inspector:
##   * sun: azimuth and elevation ranges (override them when a puzzle needs it) and
##     the starting angle
##   * Start marker (Dracula's spawn, must be in shade at the starting angle)
##   * Goal (LevelGoal, e.g. the crypt door) and the ShadeGrid covering the floor
## The level scene also instances the shared gameplay shell (ShadowRun.tscn) as its
## "Game" child; the shell's ShadowRunFeature reads this node through its `level` export.

@export var level_number: int = 1
@export var level_title: String = "Level"
## Next level scene (empty = this is the last level → Home).
@export_file("*.tscn") var next_level: String = ""
## One-line hint shown when the level starts (empty = none).
@export_multiline var hint: String = ""

@export_group("Sun")
@export_range(-80.0, 80.0) var sun_start_azimuth: float = -40.0
@export_range(10.0, 80.0) var sun_start_elevation: float = 40.0
@export_range(-80.0, 80.0) var azimuth_min: float = -80.0
@export_range(-80.0, 80.0) var azimuth_max: float = 80.0
## Low = long shadows, high = short shadows.
@export_range(10.0, 80.0) var elevation_min: float = 15.0
@export_range(10.0, 80.0) var elevation_max: float = 65.0
## Design floor checked by LevelValidatorRunner: the fewest sun adjustments a solution
## may need (1 = the sun must be used at all; raise it for harder levels).
@export_range(1, 6) var min_sun_adjustments: int = 1

@export_group("Auto sun")
## The sun runs by itself on a loop (the player can't steer it): it holds at each angle of
## auto_sun_keys for auto_sun_hold_time, then sweeps to the next one in auto_sun_move_time,
## and after the last key back to the first. The sun controls are shown chained.
## sun_start_azimuth / elevation should equal the first key.
@export var auto_sun: bool = false
## (azimuth, elevation) in degrees, inside the level's ranges.
@export var auto_sun_keys: PackedVector2Array = PackedVector2Array()
@export var auto_sun_hold_time: float = 8.0
@export var auto_sun_move_time: float = 3.0
## Extra hold time on the first key when the level starts (time to read the tutorial).
@export var auto_sun_first_hold_bonus: float = 4.0

@export_group("Tutorial")
## Shown one after another in the hint banner at level start (replaces `hint`).
@export_multiline var tutorial_steps: PackedStringArray = PackedStringArray()
@export var tutorial_step_time: float = 4.0

@export_group("Camera overrides")
## Pitch override in degrees (40.0–50.0). 0.0 uses camera default (45°).
@export_range(0.0, 60.0) var camera_pitch: float = 0.0
## Distance override in meters. 0.0 uses camera default.
@export var camera_distance: float = 0.0
## Height override in meters. 0.0 uses camera default.
@export var camera_height: float = 0.0
## Optional explicit camera pan bounds (X min, X max, Z min, Z max). If zero, computed from ShadeGrid.
@export var pan_bounds: Vector4 = Vector4.ZERO

@export_group("Scene parts")
@export var start: Marker3D
@export var goal: LevelGoal
@export var grid: ShadeGrid

## Auto sun: the angle (az, el) at schedule time t (s, from level start), whether the sun is
## sweeping, the key it is holding at / sweeping from, and the seconds until the next change.
func auto_sun_state(t: float) -> Dictionary:
	var n := auto_sun_keys.size()
	if n == 0:
		return {"angle": Vector2(sun_start_azimuth, sun_start_elevation), "moving": false, "key": 0, "time_left": INF}
	var first := auto_sun_hold_time + auto_sun_first_hold_bonus
	if t < first or n == 1:
		return {"angle": auto_sun_keys[0], "moving": false, "key": 0, "time_left": first - t if n > 1 else INF}
	var step := auto_sun_hold_time + auto_sun_move_time
	var u := fposmod(t - first, step * n)
	var k := int(u / step)          # sweeping from key k to key k+1, then holding at k+1
	var local := u - k * step
	var a := auto_sun_keys[k]
	var b := auto_sun_keys[(k + 1) % n]
	if local < auto_sun_move_time:
		var f := smoothstep(0.0, 1.0, local / maxf(auto_sun_move_time, 0.001))
		return {"angle": a.lerp(b, f), "moving": true, "key": k, "time_left": auto_sun_move_time - local}
	return {"angle": b, "moving": false, "key": (k + 1) % n, "time_left": step - local}

## World X of the grid's centre line (the camera centres here so the whole width shows).
func center_x() -> float:
	return grid.to_global(Vector3(grid.size.x * 0.5, 0.0, 0.0)).x

## Level bounding rectangle in the XZ ground plane (X: horizontal, Y: along -Z).
func get_level_bounds() -> Rect2:
	if pan_bounds != Vector4.ZERO:
		return Rect2(pan_bounds.x, pan_bounds.z, pan_bounds.y - pan_bounds.x, pan_bounds.w - pan_bounds.z)
	if grid:
		var origin := grid.global_position
		var min_x := origin.x - 3.0
		var max_x := origin.x + grid.size.x + 3.0
		var min_z := origin.z - grid.size.y - 5.0
		var max_z := origin.z + 5.0
		return Rect2(min_x, min_z, max_x - min_x, max_z - min_z)
	return Rect2(-10.0, -60.0, 20.0, 70.0)
