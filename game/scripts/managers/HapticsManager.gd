class_name HapticsManager
extends Node

# HapticsManager — vibration/feedback triggers
# PDF §2 Sub-managers: Haptics sits alongside Sound/Event Bus/Save under the
#   root singleton — isolated so it can be rewritten or disabled per-platform
#   without touching any other system.
# PDF §4 CPU: no per-frame ticking — every call is a single fire-and-forget
#   OS call, nothing idles here.
# PDF §6 SOLID: one job — haptic feedback. No game logic here.

var _enabled: bool = true

func _ready() -> void:
	pass

## Short tap — button presses, UI confirmations.
func light() -> void:
	_vibrate(20)

## Medium pulse — level complete, reward claimed.
func medium() -> void:
	_vibrate(60)

## Strong pulse — damage taken, failure states.
func heavy() -> void:
	_vibrate(120)

func set_enabled(value: bool) -> void:
	_enabled = value

func is_enabled() -> bool:
	return _enabled

func _vibrate(duration_ms: int) -> void:
	if not _enabled:
		return
	if not (PlatformUtils.is_mobile()):
		return
	Input.vibrate_handheld(duration_ms)
