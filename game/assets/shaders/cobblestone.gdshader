shader_type spatial;
render_mode diffuse_toon, specular_disabled;

// Flat-colour cobblestones for the village road (no textures): staggered rounded stones
// in world space, so road segments tile seamlessly wherever they are placed.

uniform vec4 stone_color : source_color = vec4(0.46, 0.44, 0.46, 1.0);
uniform vec4 stone_color_alt : source_color = vec4(0.38, 0.37, 0.4, 1.0);
uniform vec4 joint_color : source_color = vec4(0.24, 0.22, 0.24, 1.0);
uniform float stone_size = 0.3;
uniform float joint_width : hint_range(0.0, 0.5) = 0.08;
uniform float corner_radius : hint_range(0.0, 0.4) = 0.2;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = world_pos.xz / stone_size;
	float row = floor(uv.y);
	uv.x += mod(row, 2.0) * 0.5;
	vec2 cell = floor(uv);
	vec2 f = fract(uv) - 0.5;
	float h = hash(cell);
	// Rounded stone (slightly varied size per stone); d > 0 = mortar joint.
	float r = corner_radius;
	vec2 q = abs(f) - vec2(0.5 - joint_width - r - 0.03 * h);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
	vec3 stone = mix(stone_color.rgb, stone_color_alt.rgb, h);
	ALBEDO = d > 0.0 ? joint_color.rgb : stone;
	ROUGHNESS = 1.0;
}
