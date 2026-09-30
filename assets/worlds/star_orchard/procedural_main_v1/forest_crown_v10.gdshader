shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// The source is an eight-leaf atlas (4 columns x 2 rows). Only the interior
// of the green first/seventh cells is sampled; the multicolour sheet is never
// wrapped onto a crown. Existing detailed trees keep their original leaf UVs.
uniform sampler2D leaves_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float wind_strength : hint_range(0.0, 0.3) = 0.12;
uniform float color_strength : hint_range(0.0, 1.0) = 1.0;
varying vec4 tree_variation;
varying float crown_height;

void vertex() {
	tree_variation = INSTANCE_CUSTOM;
	crown_height = clamp((VERTEX.y + 2.1) / 4.2, 0.0, 1.0);
	float phase = INSTANCE_CUSTOM.g * 6.2831853;
	float breeze = sin(TIME * 0.74 + phase) + sin(TIME * 1.19 + phase * 1.71) * 0.27;
	float weight = smoothstep(0.04, 0.90, crown_height);
	VERTEX.x += breeze * wind_strength * weight;
	VERTEX.z += sin(TIME * 0.56 + phase + 0.8) * wind_strength * 0.55 * weight;
}

void fragment() {
	vec2 cell = tree_variation.b < 0.3 ? vec2(2.0, 1.0) : vec2(0.0, 0.0);
	// Read an interior patch to avoid atlas seams and oversized central veins.
	vec2 inside_leaf = vec2(0.08, 0.12) + clamp(UV, vec2(0.0), vec2(1.0)) * vec2(0.33, 0.70);
	vec2 atlas_uv = (cell + inside_leaf) * vec2(0.25, 0.50);
	vec3 leaf = texture(leaves_atlas, atlas_uv).rgb;
	float pigment = clamp(dot(leaf, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
	vec3 base_green = mix(vec3(0.105, 0.235, 0.048), vec3(0.275, 0.365, 0.082), tree_variation.r);
	float canopy_light = mix(0.77, 1.09, smoothstep(0.0, 1.0, crown_height));
	vec3 original_color = base_green * (0.90 + pigment * 0.32) * canopy_light;
	// The sign of the existing per-instance custom alpha selects the color family.
	// Both families keep broad local-height color; scene lights still shade them.
	vec3 green_tint = mix(vec3(0.65, 0.79, 0.94), vec3(1.04, 1.11, 0.94), smoothstep(0.10, 0.58, crown_height));
	green_tint = mix(green_tint, vec3(1.43, 1.34, 0.72), smoothstep(0.52, 0.94, crown_height));
	vec3 green_color = original_color * green_tint;
	vec3 red_base = mix(vec3(0.32, 0.055, 0.052), vec3(0.48, 0.105, 0.075), tree_variation.r);
	vec3 red_tint = mix(vec3(0.69, 0.72, 0.86), vec3(1.06, 1.00, 0.94), smoothstep(0.10, 0.58, crown_height));
	red_tint = mix(red_tint, vec3(1.32, 1.18, 0.86), smoothstep(0.52, 0.94, crown_height));
	vec3 red_color = red_base * (0.90 + pigment * 0.32) * canopy_light * red_tint;
	float red_species = step(tree_variation.a, -0.001);
	ALBEDO = mix(original_color, mix(green_color, red_color, red_species), color_strength);
	ROUGHNESS = 0.96;
	SPECULAR = 0.14;
}
