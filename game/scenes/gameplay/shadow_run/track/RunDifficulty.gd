class_name RunDifficulty
extends Resource

## Data-driven difficulty ramp for a Shadow Run session (tune in run_difficulty.tres).
## Every curve maps normalized run time (0 = start, 1 = ramp_duration_s) to 0..1.
## A missing curve falls back to a straight line.

@export var ramp_duration_s: float = 360.0

@export_group("Speed")
@export var speed_min: float = 9.0
@export var speed_max: float = 17.0
@export var speed_curve: Curve

@export_group("Segments")
## Hardest segment difficulty allowed at a given time.
@export var max_difficulty_curve: Curve
## Segments easier than (max − window) are phased out, so shade coverage drops over time.
@export var difficulty_window: float = 0.5
## Probability that each optional obstacle in a segment is enabled.
@export var obstacle_density_curve: Curve
## Desired azimuth change (0..1 → 0..max_sun_delta degrees) between consecutive segments.
@export var sun_delta_curve: Curve
@export var max_sun_delta: float = 140.0

@export_group("Onboarding")
## Gentle stretch at the start: only these segments, in this order.
@export var onboarding_duration_s: float = 30.0
@export var onboarding_sequence: Array[StringName] = [
	&"seg_gate_start", &"seg_left_row", &"seg_left_row", &"seg_right_row", &"seg_right_row", &"seg_sun_swing"]

func t_norm(run_time: float) -> float:
	return clampf(run_time / ramp_duration_s, 0.0, 1.0)

func speed_at(run_time: float) -> float:
	return lerpf(speed_min, speed_max, _sample(speed_curve, run_time))

func max_difficulty_at(run_time: float) -> float:
	return _sample(max_difficulty_curve, run_time)

func obstacle_density_at(run_time: float) -> float:
	return _sample(obstacle_density_curve, run_time)

func desired_sun_delta_at(run_time: float) -> float:
	return _sample(sun_delta_curve, run_time) * max_sun_delta

func _sample(curve: Curve, run_time: float) -> float:
	var t := t_norm(run_time)
	return clampf(curve.sample_baked(t), 0.0, 1.0) if curve else t
