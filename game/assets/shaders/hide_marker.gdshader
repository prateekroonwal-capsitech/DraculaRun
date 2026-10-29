shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

// Ground ring marking where Dracula slips into a hiding spot (its Entry point), so the
// player can read which props are hiding spots. Gently pulses.

uniform vec4 ring_color : source_color = vec4(0.78, 0.7, 1.0, 1.0);
uniform float ring_alpha : hint_range(0.0, 1.0) = 0.5;
uniform float pulse_speed = 1.6;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = 1.0 - smoothstep(0.0, 0.08, abs(r - 0.82));
	// Dashed: 8 dashes around the ring.
	float dash = step(0.35, fract(atan(p.y, p.x) / 6.2831853 * 8.0));
	float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed);
	ALBEDO = ring_color.rgb;
	ALPHA = ring * dash * ring_alpha * pulse;
}
