shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

// Villager vision cone on the ground: a flat PlaneMesh (2 × 2 m, scaled to the vision
// range by VillagerController) draws a sector around local +Z. Range is the mesh scale;
// the angle, colour and alertness are per-instance parameters, so all villagers share
// one material (materials/villager/vision_cone.tres).

instance uniform float half_angle = 0.61;          // radians (70° cone → 0.61)
instance uniform vec4 cone_color : source_color = vec4(1.0, 0.86, 0.45, 1.0);
instance uniform float alertness = 0.0;            // 0..1, brightens the cone as the meter fills

uniform float base_alpha : hint_range(0.0, 1.0) = 0.16;
uniform float alert_alpha : hint_range(0.0, 1.0) = 0.34;
uniform float edge_width : hint_range(0.0, 0.2) = 0.035;
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.55;
uniform float ring_count = 3.0;

void fragment() {
	// UV (0..1) → local XZ in −1..1; PlaneMesh UV.y grows toward +Z.
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = abs(atan(p.x, p.y));
	if (r > 1.0 || ang > half_angle) {
		discard;
	}
	float fade = 1.0 - smoothstep(0.75, 1.0, r);
	float a = mix(base_alpha, alert_alpha, alertness) * (0.45 + 0.55 * fade);
	// Outline along both edges and the arc so the shape reads on bright and dark ground.
	float side = (half_angle - ang) * r;
	float arc = 1.0 - r;
	float edge = 1.0 - smoothstep(0.0, edge_width, min(side, arc));
	// Faint distance rings.
	float ring = smoothstep(0.92, 1.0, fract(r * ring_count)) * 0.35;
	a = max(a, edge * edge_alpha) + ring * a;
	ALBEDO = cone_color.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
