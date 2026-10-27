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

@export_group("Scene parts")
@export var start: Marker3D
@export var goal: LevelGoal
@export var grid: ShadeGrid

## World X of the grid's centre line (the camera centres here so the whole width shows).
func center_x() -> float:
	return grid.to_global(Vector3(grid.size.x * 0.5, 0.0, 0.0)).x
