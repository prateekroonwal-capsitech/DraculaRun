shader_type spatial;
// Additive fresnel rim used as a next_pass on Dracula's body/head.
// intensity is driven from DraculaController (0 = invisible, ~2.4 = fully burning, 7 = death flare).
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_back;

uniform vec4 rim_color : source_color = vec4(1.0, 0.42, 0.06, 1.0);
uniform float intensity : hint_range(0.0, 10.0) = 0.0;
uniform float rim_power : hint_range(0.5, 8.0) = 2.2;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = rim_color.rgb * intensity * (rim + 0.12);
}
