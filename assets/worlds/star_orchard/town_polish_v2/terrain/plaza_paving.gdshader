shader_type spatial;

// A material-only overlay on the existing terrain mesh. It keeps the tile's
// original UV, height, lighting and collision; no new geometry is generated.
uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D paving_texture : source_color, filter_linear, repeat_enable;

// All XZ coordinates are local to the StarOrchard scene root, as in world.json.
uniform vec2 tile_origin_xz = vec2(0.0, 0.0);
uniform float tile_size = 533.333313;
uniform vec2 plaza_center_xz = vec2(0.0, 0.0);
uniform float inner_radius = 0.0;
uniform float outer_radius = 0.0;
uniform float inner_feather = 1.5;
uniform float outer_feather = 3.0;
uniform float paving_repeats_per_tile = 16.0;
uniform float paving_strength : hint_range(0.0, 1.0, 0.01) = 0.62;
uniform vec3 paving_tint = vec3(1.16, 1.13, 1.10);

void fragment() {
	vec3 original_color = texture(base_texture, UV).rgb;
	vec3 final_color = original_color;

	if (outer_radius > inner_radius && paving_strength > 0.0) {
		vec2 scene_xz = tile_origin_xz + UV * tile_size;
		float radius = distance(scene_xz, plaza_center_xz);
		float inside = smoothstep(inner_radius - inner_feather,
			inner_radius + inner_feather, radius);
		float outside = 1.0 - smoothstep(outer_radius - outer_feather,
			outer_radius + outer_feather, radius);
		float amount = paving_strength * inside * outside;
		if (amount > 0.0) {
			// Scene-root coordinates keep the existing stone texture continuous
			// when the mask eventually extends over a neighboring terrain tile.
			vec2 paving_uv = scene_xz * (paving_repeats_per_tile / tile_size);
			vec3 existing_stones = texture(paving_texture, paving_uv).rgb;
			// Preserve the source stone pattern while bringing its brown/green
			// cast toward the fountain's light warm-gray paving.
			float stone_luminance = dot(existing_stones, vec3(0.2126, 0.7152, 0.0722));
			vec3 softened_stones = mix(existing_stones, vec3(stone_luminance), 0.55);
			final_color = mix(original_color,
				clamp(softened_stones * paving_tint, vec3(0.0), vec3(1.0)), amount);
		}
	}

	ALBEDO = final_color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
