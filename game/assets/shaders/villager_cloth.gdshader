shader_type spatial;
render_mode diffuse_toon, specular_disabled;

// Recolourable villager clothing. Every villager shares the four cloth materials
// (materials/villager/villager_<part>.tres, which only differ in `part`); the colours
// are per-instance shader parameters set by VillagerController's colour exports, so
// each placed villager can have its own outfit without duplicating materials.

instance uniform vec4 tunic_color : source_color = vec4(0.42, 0.29, 0.17, 1.0);
instance uniform vec4 vest_color : source_color = vec4(0.3, 0.36, 0.2, 1.0);
instance uniform vec4 cap_color : source_color = vec4(0.24, 0.21, 0.18, 1.0);
instance uniform vec4 trousers_color : source_color = vec4(0.2, 0.16, 0.13, 1.0);

// 0 = tunic, 1 = vest, 2 = cap, 3 = trousers.
uniform int part : hint_range(0, 3) = 0;

void fragment() {
	vec4 c = tunic_color;
	if (part == 1) {
		c = vest_color;
	} else if (part == 2) {
		c = cap_color;
	} else if (part == 3) {
		c = trousers_color;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
}
