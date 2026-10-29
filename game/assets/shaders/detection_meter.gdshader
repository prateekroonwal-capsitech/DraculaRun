shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled, blend_mix;

// Detection meter above a villager's head: a billboarded quad drawing an eye that fills
// from the bottom as the villager notices Dracula (white → amber → red).
// `fill` and `meter_alpha` are per-instance, set by VillagerController.

instance uniform float fill = 0.0;
instance uniform float meter_alpha = 1.0;

uniform vec4 empty_color : source_color = vec4(0.08, 0.06, 0.1, 0.75);
uniform vec4 low_color : source_color = vec4(1.0, 0.92, 0.6, 1.0);
uniform vec4 high_color : source_color = vec4(1.0, 0.52, 0.12, 1.0);
uniform vec4 full_color : source_color = vec4(0.95, 0.12, 0.08, 1.0);
uniform vec4 outline_color : source_color = vec4(1.0, 0.96, 0.88, 1.0);

void vertex() {
	// Spherical billboard, keeps the quad's size.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	// Almond eye: intersection of two circles.
	float d1 = length(p - vec2(0.0, -0.62)) - 1.05;
	float d2 = length(p - vec2(0.0, 0.62)) - 1.05;
	float eye = max(d1, d2);
	if (eye > 0.06) {
		discard;
	}
	float level = (p.y + 0.43) / 0.86;   // 0 at the bottom of the eye, 1 at the top
	vec3 fill_col = fill >= 0.999 ? full_color.rgb : mix(low_color.rgb, high_color.rgb, fill);
	vec4 col = level <= fill ? vec4(fill_col, 1.0) : empty_color;
	// Pupil.
	if (length(p) < 0.17) {
		col = vec4(0.05, 0.03, 0.05, 1.0);
	}
	// Outline.
	if (eye > -0.06) {
		col = outline_color;
	}
	ALBEDO = col.rgb;
	ALPHA = col.a * meter_alpha;
}
