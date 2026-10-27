shader_type canvas_item;
// Warm screen-edge vignette shown while Dracula is exposed to sunlight.
// strength (0..1) is driven by ShadowRunHUD from the exposure meter.

uniform vec4 tint : source_color = vec4(1.0, 0.36, 0.05, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float softness : hint_range(0.05, 1.0) = 0.55;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p * vec2(1.0, 1.25));
	float edge = smoothstep(1.0 - softness, 1.35, d);
	COLOR = vec4(tint.rgb, edge * strength * 0.85);
}
