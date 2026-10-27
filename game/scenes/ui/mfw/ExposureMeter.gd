class_name ExposureMeter
extends Control

## Sun-exposure gauge: a sun icon that fills red from the bottom, plus a bar.
## Redraws only when the value changes (PDF §4: no per-frame work when idle).

@export var safe_color: Color = Color(0.55, 0.6, 0.95, 0.9)
@export var burn_color: Color = Color(0.95, 0.12, 0.05, 1.0)
@export var outline_color: Color = Color(1.0, 0.86, 0.5, 1.0)
@export var back_color: Color = Color(0.05, 0.04, 0.08, 0.65)

var value: float = 0.0

func _ready() -> void:
	set_process(false)

func set_value(v: float) -> void:
	v = clampf(v, 0.0, 100.0)
	if absf(v - value) < 0.1:
		return
	value = v
	queue_redraw()

func _draw() -> void:
	var k := value / 100.0
	var r := size.y * 0.32
	var c := Vector2(size.y * 0.5, size.y * 0.5)
	# Rays
	for i in 8:
		var a := TAU * i / 8.0
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (r + 3.0), c + d * (r + size.y * 0.14), outline_color, 3.0, true)
	# Disc + red fill rising from the bottom (polygon clipped to the circle)
	draw_circle(c, r, back_color)
	if k > 0.01:
		# Circular segment below the fill line: arc from a0 to PI - a0 (y grows downward).
		var a0 := asin(clampf(1.0 - 2.0 * k, -1.0, 1.0))
		var pts := PackedVector2Array()
		var n := 24 if k < 0.99 else 23   # full circle: drop the duplicate closing point
		for i in n + 1:
			var a := lerpf(a0, PI - a0, i / 24.0)
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, burn_color.lerp(Color(1.0, 0.6, 0.1), 1.0 - k))
	draw_arc(c, r, 0.0, TAU, 40, outline_color, 2.5, true)
	# Bar
	var bar := Rect2(Vector2(size.y * 1.05, size.y * 0.36), Vector2(size.x - size.y * 1.1, size.y * 0.28))
	draw_rect(bar, back_color)
	var fill := bar
	fill.size.x *= k
	draw_rect(fill, safe_color.lerp(burn_color, k))
	draw_rect(bar, outline_color, false, 2.0)
