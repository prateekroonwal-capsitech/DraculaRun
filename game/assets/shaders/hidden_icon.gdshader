shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled, blend_mix;

// "Hidden" icon above Dracula's hiding spot: a closed eye (lid arc + lashes) on a dark
// disc, billboarded. `time_left` (0..1, per instance) draws a ring that empties when the
// hiding spot has a max hide time; 1 = full ring (unlimited).

instance uniform float time_left = 1.0;
instance uniform float icon_alpha = 1.0;

uniform vec4 disc_color : source_color = vec4(0.1, 0.06, 0.14, 0.8);
uniform vec4 icon_color : source_color = vec4(0.82, 0.76, 1.0, 1.0);
uniform vec4 ring_color : source_color = vec4(0.82, 0.76, 1.0, 1.0);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	vec4 col = disc_color;
	// Remaining-time ring (clockwise from the top).
	float a = fract(atan(p.x, p.y) / 6.2831853 + 1.0);
	if (r > 0.84 && a <= time_left) {
		col = ring_color;
	}
	// Closed eye: a downward lid arc...
	float lid = abs(length(p - vec2(0.0, 0.55)) - 0.62);
	if (lid < 0.07 && p.y < 0.12 && abs(p.x) < 0.52) {
		col = icon_color;
	}
	// ...with three lashes.
	for (int i = -1; i <= 1; i++) {
		vec2 base = vec2(float(i) * 0.3, -0.05 - (i == 0 ? 0.03 : 0.0));
		vec2 dir = normalize(vec2(float(i) * 0.5, -1.0));
		vec2 q = p - base;
		float along = dot(q, dir);
		float across = abs(dot(q, vec2(-dir.y, dir.x)));
		if (along > 0.0 && along < 0.22 && across < 0.05) {
			col = icon_color;
		}
	}
	ALBEDO = col.rgb;
	ALPHA = col.a * icon_alpha;
}
