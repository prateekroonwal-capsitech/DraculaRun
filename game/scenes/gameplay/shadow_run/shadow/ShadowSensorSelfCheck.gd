extends Node3D

## Deterministic self-check for ShadowSensor (no rendering involved).
## ShadowSensorSelfCheck.tscn holds one shadow-caster box, one obstacle-only box,
## a SunRig, a probe marker and a ShadowSensor; this script moves the probe and the
## sun to known positions/angles and asserts lit/shaded results.
## Run with F6 or headless:
##   godot --headless --path . res://game/scenes/gameplay/shadow_run/shadow/ShadowSensorSelfCheck.tscn
## Exit code 0 = all cases pass. Standalone dev tool: its Logger is a node in the scene.

@export var sun_rig: SunRig
@export var sensor: ShadowSensor
@export var probe: Marker3D
@export var logger: Node

var _failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var points: Array[Node3D] = [probe]
	sensor.setup(points, sun_rig)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# [azimuth, elevation, probe position, expected shaded, description]
	var cases := [
		[0.0, 45.0, Vector3(0, 1, -5), true, "sun ahead: point in front of the box is shaded"],
		[0.0, 45.0, Vector3(0, 1, 0), false, "sun ahead: point far in front is lit (shadow too short)"],
		[0.0, 20.0, Vector3(0, 1, 0), true, "low sun ahead: long shadow reaches the far point"],
		[60.0, 30.0, Vector3(-4, 1, -10), true, "sun right: point LEFT of the box is shaded"],
		[60.0, 30.0, Vector3(4, 1, -10), false, "sun right: point RIGHT of the box is lit"],
		[-60.0, 30.0, Vector3(4, 1, -10), true, "sun left: point RIGHT of the box is shaded"],
		[-60.0, 30.0, Vector3(-4, 1, -10), false, "sun left: point LEFT of the box is lit"],
		[60.0, 30.0, Vector3(6, 1, -10), false, "obstacle-only body casts no gameplay shade"],
		[0.0, 60.0, Vector3(0, 1, -20), false, "point beyond the box (sun ahead) is lit"],
	]
	for c in cases:
		sun_rig.snap_to(c[0], c[1])
		probe.global_position = c[2]
		var lit := sensor.sample()
		_check((lit == 0.0) == c[3], "%s  (az %d, el %d)" % [c[4], int(c[0]), int(c[1])])

	# Exposure meter: full sun for 1.25 s must burn out; shade must heal.
	sun_rig.snap_to(0.0, 45.0)
	probe.global_position = Vector3(0, 1, 5)
	sensor.reset()
	var burned := [false]
	sensor.burned_out.connect(func() -> void: burned[0] = true)
	var t := 0.0
	while t < 1.25:
		sensor.sample()
		sensor.integrate(1.0 / 60.0)
		t += 1.0 / 60.0
	_check(burned[0] and sensor.exposure >= 100.0, "full exposure burns out within ~1.2 s")
	probe.global_position = Vector3(0, 1, -5)
	sensor.sample()
	sensor.integrate(1.0)
	_check(sensor.exposure < 100.0 and sensor.exposure_fraction == 0.0, "exposure recovers in full shade")

	if _failures == 0:
		logger.info("ShadowSensorSelfCheck: all checks PASS")
	else:
		logger.error("ShadowSensorSelfCheck: %d check(s) FAILED" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
	logger.info(("  PASS " if ok else "  FAIL ") + what)
