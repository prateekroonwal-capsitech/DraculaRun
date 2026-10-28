shader_type spatial;
// Fresnel rim, used as the next_pass of every Dracula surface material
// (game/assets/materials/dracula/*.tres) — it ADDS light at the silhouette edge and never
// replaces the surface colour.
//   * rim: always on, a cool pale-violet edge so his shape reads against near-black shade;
//   * burn: `intensity` is driven by DraculaController (0 = none, ~2.4 = fully burning,
//     7 = death flare).
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_back;

uniform vec4 rim_color : source_color = vec4(0.78, 0.72, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 4.0) = 0.6;
// Fraction of the fresnel range that glows: 0.15 = thin edge, 0.6 = broad.
uniform float rim_width : hint_range(0.02, 1.0) = 0.28;
uniform vec4 burn_color : source_color = vec4(1.0, 0.42, 0.06, 1.0);
uniform float intensity : hint_range(0.0, 10.0) = 0.0;
uniform float burn_power : hint_range(0.5, 8.0) = 2.2;

void fragment() {
	float f = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float rim = smoothstep(1.0 - rim_width, 1.0, f);
	vec3 burn = burn_color.rgb * intensity * (pow(f, burn_power) + 0.12);
	ALBEDO = rim_color.rgb * rim_strength * rim + burn;
}
