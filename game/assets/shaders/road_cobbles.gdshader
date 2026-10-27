shader_type spatial;
// World-space cobblestone road with dashed lane dividers. Procedural so the road
// gives a strong sense of speed with zero textures and no extra nodes.
// Dashed dividers sit between lanes. lane_count / lane_width are pushed from
// LaneConfig by TrackSpawner.prewarm(), so they never need editing here.

uniform vec3 stone_a : source_color = vec3(0.64, 0.54, 0.42);
uniform vec3 stone_b : source_color = vec3(0.52, 0.44, 0.35);
uniform vec3 joint_color : source_color = vec3(0.22, 0.19, 0.17);
uniform vec3 lane_color : source_color = vec3(0.86, 0.8, 0.68);
uniform vec2 cobble_size = vec2(0.62, 0.45);
uniform float dash_length = 5.0;
uniform int lane_count = 3;
uniform float lane_width = 2.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 c = p / cobble_size;
	float row = floor(c.y);
	c.x += mod(row, 2.0) * 0.5;
	vec2 id = floor(c);
	vec2 f = fract(c);
	float h = fract(sin(dot(id, vec2(12.9898, 78.233))) * 43758.5453);
	float edge = min(min(f.x, 1.0 - f.x) * cobble_size.x, min(f.y, 1.0 - f.y) * cobble_size.y);
	vec3 col = mix(stone_a, stone_b, h);
	col = mix(joint_color, col, smoothstep(0.012, 0.045, edge));

	float u = p.x / lane_width + float(lane_count) * 0.5;   // position in lane units
	float lx = abs(u - round(u)) * lane_width;
	float dash = step(0.5, fract(p.y / dash_length));
	float interior = step(0.5, u) * step(u, float(lane_count) - 0.5);
	float line = (1.0 - smoothstep(0.06, 0.1, lx)) * dash * interior;
	col = mix(col, lane_color, line * 0.85);

	ALBEDO = col;
	ROUGHNESS = 0.88;
}
