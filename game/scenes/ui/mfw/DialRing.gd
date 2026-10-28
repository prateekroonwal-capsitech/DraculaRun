class_name DialRing
extends Control

## DialRing — draws the sun dial's thin golden ring, the four tick marks and the faint
## dashed inner circle (the only custom drawing in SunJoystick.tscn; everything else is
## nodes). Centred in its own rect; radius = half the smaller side minus ring_width.

@export var ring_color: Color = Color(1.0, 0.84, 0.48, 0.85)
@export var ring_width: float = 4.0
@export var tick_length: float = 18.0
@export var tick_width: float = 4.0
@export var inner_color: Color = Color(1.0, 0.84, 0.48, 0.25)
## Inner dashed circle radius as a fraction of the ring radius.
@export_range(0.1, 0.95) var inner_fraction: float = 0.55
@export var inner_dashes: int = 24
@export var inner_width: float = 2.0
@export var backdrop_color: Color = Color(0.07, 0.04, 0.08, 0.55)

func radius() -> float:
	return minf(size.x, size.y) * 0.5 - ring_width

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var c := size * 0.5
	var r := radius()
	draw_circle(c, r, backdrop_color)
	draw_arc(c, r, 0.0, TAU, 96, ring_color, ring_width, true)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * (r - tick_length), c + d * (r + ring_width * 0.5), ring_color, tick_width, true)
	var ri := r * inner_fraction
	var step := TAU / float(maxi(4, inner_dashes))
	for i in maxi(4, inner_dashes):
		draw_arc(c, ri, i * step, i * step + step * 0.5, 6, inner_color, inner_width, true)
