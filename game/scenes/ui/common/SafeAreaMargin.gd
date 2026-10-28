@tool
class_name SafeAreaMargin
extends MarginContainer

## SafeAreaMargin — keeps its children clear of notches, rounded corners and gesture bars.
## Margins = the device's system insets (DisplayServer.get_display_safe_area() against
## the window size, converted to this viewport's canvas px — 1080 × 1920 in portrait)
## PLUS a minimum padding, so controls never sit flush with the screen edge even on
## phones that report zero insets. Re-applied on every viewport size change.
## Editor / debug builds: simulate_insets_* preview a notch or gesture bar (canvas px);
## they are ignored in release builds. Reusable: instance it and put UI inside.

@export_group("Minimum padding (px)")
@export var min_top: int = 16:
	set(v):
		min_top = v
		_queue_apply()
@export var min_bottom: int = 32:
	set(v):
		min_bottom = v
		_queue_apply()
@export var min_left: int = 24:
	set(v):
		min_left = v
		_queue_apply()
@export var min_right: int = 24:
	set(v):
		min_right = v
		_queue_apply()

@export_group("Simulated insets (debug only, px)")
## Preview a notch / gesture bar in the editor or a debug run. Ignored in release builds.
@export var simulate_insets_top: int = 0:
	set(v):
		simulate_insets_top = v
		_queue_apply()
@export var simulate_insets_bottom: int = 0:
	set(v):
		simulate_insets_bottom = v
		_queue_apply()
@export var simulate_insets_left: int = 0:
	set(v):
		simulate_insets_left = v
		_queue_apply()
@export var simulate_insets_right: int = 0:
	set(v):
		simulate_insets_right = v
		_queue_apply()

func _ready() -> void:
	if not Engine.is_editor_hint():
		get_viewport().size_changed.connect(apply)
	apply()

func _exit_tree() -> void:
	if not Engine.is_editor_hint() and get_viewport() and get_viewport().size_changed.is_connected(apply):
		get_viewport().size_changed.disconnect(apply)

## Current margins (left, top, right, bottom) in canvas px.
func get_margins() -> Vector4i:
	var ins := system_insets()
	if OS.is_debug_build() or Engine.is_editor_hint():
		ins += Vector4i(simulate_insets_left, simulate_insets_top, simulate_insets_right, simulate_insets_bottom)
	return ins + Vector4i(min_left, min_top, min_right, min_bottom)

func apply() -> void:
	if not is_inside_tree():
		return
	var m := get_margins()
	add_theme_constant_override("margin_left", m.x)
	add_theme_constant_override("margin_top", m.y)
	add_theme_constant_override("margin_right", m.z)
	add_theme_constant_override("margin_bottom", m.w)

## System insets (left, top, right, bottom) in this viewport's canvas px. Zero on desktop
## and in the editor (windows have no notch).
func system_insets() -> Vector4i:
	if Engine.is_editor_hint() or not (OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")):
		return Vector4i.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if win.x <= 0.0 or win.y <= 0.0 or safe.size.x <= 0.0:
		return Vector4i.ZERO
	var to_view := get_viewport_rect().size / win
	return Vector4i(
		int(maxf(0.0, safe.position.x) * to_view.x),
		int(maxf(0.0, safe.position.y) * to_view.y),
		int(maxf(0.0, win.x - safe.end.x) * to_view.x),
		int(maxf(0.0, win.y - safe.end.y) * to_view.y))

func _queue_apply() -> void:
	if is_inside_tree():
		apply.call_deferred()
