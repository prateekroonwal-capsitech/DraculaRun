shader_type spatial;
// Additive fresnel overlay on Dracula's mesh (material_overlay in DraculaVisual.tscn).
//   * silhouette rim: always on, a cool moonlit edge so his dark shape reads against
//     near-black shadows;
//   * burn rim: `intensity` is driven by DraculaController (0 = none, ~2.4 = fully
//     burning, 7 = death flare).
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_back;

uniform vec4 silhouette_color : source_color = vec4(0.62, 0.66, 1.0, 1.0);
uniform float silhouette_intensity : hint_range(0.0, 4.0) = 0.55;
uniform float silhouette_power : hint_range(0.5, 8.0) = 3.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.42, 0.06, 1.0);
uniform float intensity : hint_range(0.0, 10.0) = 0.0;
uniform float rim_power : hint_range(0.5, 8.0) = 2.2;

void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 silhouette = silhouette_color.rgb * silhouette_intensity * pow(f, silhouette_power);
	vec3 burn = rim_color.rgb * intensity * (pow(f, rim_power) + 0.12);
	ALBEDO = silhouette + burn;
}
