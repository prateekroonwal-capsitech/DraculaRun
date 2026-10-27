class_name SegmentSafeWindow
extends Resource

## Authoring metadata: "standing in `lane` between `start_m` and `end_m` meters
## into the segment is shaded while the sun is inside this angle box".
## SegmentValidator checks every declared window against real physics rays.

## Lane index (0 = leftmost, up to LaneConfig.lane_count - 1).
@export_range(0, 6) var lane: int = 0
@export var start_m: float = 0.0
@export var end_m: float = 30.0
@export_range(-70.0, 70.0) var azimuth_min: float = -70.0
@export_range(-70.0, 70.0) var azimuth_max: float = 70.0
@export_range(18.0, 60.0) var elevation_min: float = 18.0
@export_range(18.0, 60.0) var elevation_max: float = 60.0

func azimuth_center() -> float:
	return (azimuth_min + azimuth_max) * 0.5

func describe() -> String:
	return "lane %d @ %.0f-%.0f m, az %.0f..%.0f, el %.0f..%.0f" % [
		lane, start_m, end_m, azimuth_min, azimuth_max, elevation_min, elevation_max]
