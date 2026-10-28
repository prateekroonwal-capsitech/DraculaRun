shader_type spatial;
// Inverted-hull outline (next_pass of dracula_rim.tres): back faces pushed out along the
// normal in SCREEN space, so the line stays `outline_width` pixels wide at any distance
// (readable at phone size). Drawn in the transparent pass (ALPHA is written), so it never
// casts a shadow and never changes the ground shadows.
render_mode unshaded, cull_front, shadows_disabled, depth_draw_never;

uniform vec4 outline_color : source_color = vec4(0.62, 0.54, 0.86, 1.0);
// Line width in screen pixels.
uniform float outline_width : hint_range(0.0, 8.0) = 1.6;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 dir = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	if (length(dir) > 0.0001) {
		clip.xy += normalize(dir) * outline_width * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
