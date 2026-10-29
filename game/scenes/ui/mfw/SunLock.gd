class_name SunLock
extends Control

## SunLock — "the sun is not yours to move" overlay on a sun control (SunJoystick /
## SunControl strip): two chains crossing the control and a padlock in the middle, plus a
## countdown label ("Sun moves in 3", "The sun is moving…"). Shown by
## ShadowRunHUD.set_sun_locked() on levels whose sun runs on a schedule (ShadowLevel
## auto_sun). Drawn with _draw (no textures); redraws only when shown or resized.

@export var chain_color: Color = Color(0.72, 0.7, 0.74, 1.0)
@export var chain_shadow: Color = Color(0.05, 0.03, 0.08, 0.85)
@export var lock_color: Color = Color(0.86, 0.66, 0.3, 1.0)
@export var lock_dark: Color = Color(0.2, 0.12, 0.06, 1.0)
@export var dim_color: Color = Color(0.04, 0.02, 0.06, 0.45)
## Link length / width in px.
@export var link_length: float = 34.0
@export var link_width: float = 18.0
@export var link_thickness: float = 5.0
## Strip (round_backdrop off): chains run between the corners of this fraction of the
## control (0.5 = full size).
@export_range(0.1, 0.5) var chain_extent: float = 0.42
@export var lock_size: float = 60.0
## Dial (on): everything fits inside a circle of `fit_radius` px (the dial's ring; 0 = auto,
## 44% of the control's shorter side). Off: a band across the whole control (strip).
@export var round_backdrop: bool = true
@export var fit_radius: float = 0.0
@export var moving_text: String = "The sun is moving…"
@export var countdown_text: String = "Sun moves in %d"

@export var countdown_label: Label

func _ready() -> void:
	resized.connect(queue_redraw)
	visibility_changed.connect(queue_redraw)

## seconds_left: time until the sun's next move; moving: it is moving now.
func set_countdown(seconds_left: float, moving: bool) -> void:
	if countdown_label == null:
		return
	countdown_label.text = moving_text if moving else countdown_text % int(ceil(seconds_left))
	countdown_label.modulate = Color(1.0, 0.55, 0.3) if moving or seconds_left <= 2.0 else Color.WHITE

func _draw() -> void:
	var c := size * 0.5
	var half := size * chain_extent
	if round_backdrop:
		var r := fit_radius if fit_radius > 0.0 else minf(size.x, size.y) * 0.44
		draw_circle(c, r, dim_color)
		half = Vector2.ONE * r * 0.68   # chain ends stay inside the ring (45° diagonals)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), dim_color)
	_chain(c - half, c + half)
	_chain(Vector2(c.x + half.x, c.y - half.y), Vector2(c.x - half.x, c.y + half.y))
	_padlock(c)

func _chain(a: Vector2, b: Vector2) -> void:
	var dir := (b - a).normalized()
	var count := int((b - a).length() / (link_length * 0.72))
	for i in count + 1:
		var p := a + dir * (i * link_length * 0.72)
		draw_set_transform(p, dir.angle(), Vector2.ONE)
		if i % 2 == 0:
			_link(Vector2(link_length, link_width), link_thickness)
		else:   # edge-on link: a thick bar
			draw_rect(Rect2(-link_length * 0.5, -link_thickness * 0.8, link_length, link_thickness * 1.6), chain_shadow)
			draw_rect(Rect2(-link_length * 0.5 + 1.0, -link_thickness * 0.5, link_length - 2.0, link_thickness), chain_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## One flat link: a rounded oval ring centred on the current transform.
func _link(s: Vector2, t: float) -> void:
	var r := s.y * 0.5
	var straight := s.x * 0.5 - r
	for pass_ in 2:
		var col := chain_shadow if pass_ == 0 else chain_color
		var w := t + 3.0 if pass_ == 0 else t
		draw_line(Vector2(-straight, -r), Vector2(straight, -r), col, w)
		draw_line(Vector2(-straight, r), Vector2(straight, r), col, w)
		draw_arc(Vector2(straight, 0.0), r, -PI * 0.5, PI * 0.5, 10, col, w)
		draw_arc(Vector2(-straight, 0.0), r, PI * 0.5, PI * 1.5, 10, col, w)

func _padlock(c: Vector2) -> void:
	var w := lock_size
	var h := lock_size * 0.78
	var body := Rect2(c.x - w * 0.5, c.y - h * 0.25, w, h)
	# Shackle.
	var sr := w * 0.3
	var sc := Vector2(c.x, body.position.y)
	draw_arc(sc, sr, PI, TAU, 16, lock_dark, w * 0.16 + 4.0)
	draw_arc(sc, sr, PI, TAU, 16, chain_color, w * 0.16)
	# Body.
	draw_rect(body.grow(3.0), lock_dark)
	draw_rect(body, lock_color)
	draw_rect(Rect2(body.position + Vector2(4, 4), Vector2(body.size.x - 8, body.size.y * 0.18)), lock_color.lightened(0.25))
	# Keyhole.
	var k := body.get_center() + Vector2(0.0, -h * 0.08)
	draw_circle(k, w * 0.09, lock_dark)
	draw_colored_polygon(PackedVector2Array([k + Vector2(-w * 0.05, 0), k + Vector2(w * 0.05, 0), k + Vector2(0, h * 0.28)]), lock_dark)
