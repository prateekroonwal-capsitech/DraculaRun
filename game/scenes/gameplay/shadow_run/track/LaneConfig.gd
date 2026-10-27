class_name LaneConfig
extends Resource

## Single source of truth for the road's lanes (saved as track/lane_config.tres).
## Lane centers are symmetric around x = 0:  x(i) = (i - (lane_count - 1) / 2) * lane_width
## With 3 lanes x 2.5 m: −2.5, 0, +2.5 (indexes 0, 1, 2).
## Used by Dracula, TrackSpawner (road shader dividers), SegmentValidator and the
## debug overlay. The road mesh and lane-spanning props are authored scenes: if you
## change lane_count/lane_width, also re-author TrackSegment.tscn and the segments
## (see docs/SHADOW_RUN_PROTOTYPE.md).

@export_range(1, 7) var lane_count: int = 3
@export var lane_width: float = 2.5
## Lane index Dracula starts in (clamped).
@export var start_lane: int = 1

func lane_x(index: int) -> float:
	return (float(index) - (lane_count - 1) * 0.5) * lane_width

func positions() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in lane_count:
		out.append(lane_x(i))
	return out

func clamp_lane(index: int) -> int:
	return clampi(index, 0, lane_count - 1)

## Half the width covered by the lanes (road edge = this + any margin in the road scene).
func lanes_half_width() -> float:
	return lane_count * lane_width * 0.5
