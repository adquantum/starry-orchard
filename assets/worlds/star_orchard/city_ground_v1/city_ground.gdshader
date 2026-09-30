shader_type spatial;

// World coordinates repair ground exported without TEXCOORD attributes, and
// keep texture size consistent across scaled islands, plazas and stair flights.
uniform sampler2D grass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paving_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform int surface_kind = 0; // 0 meadow, 1 paving, 2 rock, 3 soil, 4 masonry, 5 stair.
uniform vec2 stair_across = vec2(1.0, 0.0);
uniform vec3 grass_tint : source_color = vec3(0.91, 0.98, 0.88);
uniform vec3 stone_tint : source_color = vec3(1.0);
uniform vec3 cliff_tint : source_color = vec3(1.0);
uniform float grass_scale = 0.03575;
uniform float paving_scale = 0.26;
uniform float cliff_scale = 0.035;
// R: grass blend at an actual paving/grass contact. GB: 16-bit contact height.
// A: valid. Raw data, no color conversion or mipmaps; no AABB-based edge fades.
uniform sampler2D contact_map : filter_linear, repeat_disable;
uniform bool contact_map_enabled = false;
uniform vec2 contact_origin = vec2(0.0);
uniform vec2 contact_size = vec2(1.0);
uniform float contact_height_min = 0.0;
uniform float contact_height_span = 1.0;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

vec3 projected_cliff(vec3 position, vec3 weights) {
	vec3 p = position * cliff_scale;
	return texture(cliff_texture, p.zy).rgb * weights.x
		+ texture(cliff_texture, p.xz).rgb * weights.y
		+ texture(cliff_texture, p.xy).rgb * weights.z;
}

vec3 continuous_meadow(vec3 position) {
	// The exact same world projection and tint on every city grass surface.
	return texture(grass_texture, position.xz * grass_scale).rgb * grass_tint;
}

vec3 carved_limestone(vec3 position, vec3 normal, bool stairs) {
	// Reuse the painted limestone's color grain at low contrast. Mortar joints
	// belong to cut blocks; the raw coastal-cliff image is never put on steps.
	vec3 grain = texture(paving_texture, position.xz * 0.12 + position.y * 0.019).rgb;
	float luminance = dot(grain, vec3(0.2126, 0.7152, 0.0722));
	vec3 stone = vec3(0.50, 0.50, 0.48) * (0.91 + luminance * 0.16) * mix(vec3(1.0), stone_tint, 0.55);
	vec2 uv;
	if (stairs) {
		// Short staggered cut blocks also read as stone on the sloped entry
		// toes. Unbroken lengthwise lines made the support look like planks.
		vec2 run = vec2(-stair_across.y, stair_across.x);
		float along = dot(position.xz, run);
		uv = vec2(dot(position.xz, stair_across) / 2.8,
			(normal.y > 0.48 ? along / 1.15 : position.y / 0.7));
		uv.x += mod(floor(uv.y), 2.0) * 0.5;
		vec2 cell = floor(uv);
		float block_tone = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
		vec2 edge = min(fract(uv), 1.0 - fract(uv));
		vec2 antialias = max(fwidth(uv), vec2(0.001));
		vec2 joint = vec2(1.0) - smoothstep(vec2(0.006, 0.012), vec2(0.006, 0.012) + antialias, edge);
		stone *= (0.96 + block_tone * 0.08) * (1.0 - max(joint.x, joint.y) * 0.16);
		stone *= mix(0.83, 1.04, smoothstep(0.25, 0.85, normal.y));
	} else {
		uv = vec2((abs(normal.x) > abs(normal.z) ? position.z : position.x) / 2.4, position.y / 1.1);
		uv.x += mod(floor(uv.y), 2.0) * 0.5;
		vec2 edge = min(fract(uv), 1.0 - fract(uv));
		vec2 antialias = max(fwidth(uv), vec2(0.001));
		vec2 joint = vec2(1.0) - smoothstep(vec2(0.012), vec2(0.012) + antialias, edge);
		stone *= 1.0 - max(joint.x, joint.y) * 0.22;
	}
	return stone;
}

float paving_grass_contact(vec3 position) {
	if (!contact_map_enabled) {
		return 0.0;
	}
	vec2 uv = (position.xz - contact_origin) / max(contact_size, vec2(0.001));
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 0.0;
	}
	vec4 contact = texture(contact_map, uv);
	float packed_height = (contact.g * 256.0 + contact.b) / 257.0;
	float contact_height = contact_height_min + packed_height * contact_height_span;
	float same_level = 1.0 - smoothstep(0.22, 0.75, abs(position.y - contact_height));
	return contact.r * contact.a * same_level;
}

void fragment() {
	vec3 normal = normalize(world_normal);
	vec3 weights = pow(abs(normal), vec3(4.0));
	weights /= max(weights.x + weights.y + weights.z, 0.001);
	float broad_variation = sin(world_position.x * 0.033 + sin(world_position.z * 0.026) * 1.4)
		* sin(world_position.z * 0.041 + world_position.x * 0.013);
	vec3 color;
	if (surface_kind == 1) {
		vec3 paving = texture(paving_texture, world_position.xz * paving_scale).rgb * stone_tint;
		vec3 masonry = carved_limestone(world_position, normal, false);
		// The cities include walkable sloped approaches. A 52-degree ramp is
		// still a path; the former 0.82 cutoff painted it like an exposed cliff.
		float top_amount = smoothstep(0.48, 0.62, normal.y);
		// Color blending is confined to coplanar ground contact. The opaque
		// geometry and physics remain fully present throughout the transition.
		float contact = paving_grass_contact(world_position) * top_amount;
		paving = mix(paving, continuous_meadow(world_position), contact);
		// Paving belongs to the walking surface; bridge sides and stair risers
		// use natural stone instead of wrapping floor tiles down vertical faces.
		color = mix(masonry, paving, top_amount);
	} else if (surface_kind == 4 || surface_kind == 5) {
		color = carved_limestone(world_position, normal, surface_kind == 5);
	} else if (surface_kind == 2) {
		color = projected_cliff(world_position, weights) * cliff_tint;
		color *= 0.99 + broad_variation * 0.045;
	} else {
		vec3 top_color = continuous_meadow(world_position);
		if (surface_kind == 3) {
			vec3 earth = texture(soil_texture, world_position.xz * grass_scale).rgb * vec3(0.94, 0.98, 0.92);
			top_color = mix(top_color, earth, 0.63);
		}
		vec3 cliff_color = projected_cliff(world_position, weights) * cliff_tint;
		float top_amount = smoothstep(0.54, 0.88, normal.y);
		color = mix(cliff_color, top_color, top_amount);
	}
	ALBEDO = color;
	ROUGHNESS = surface_kind == 0 ? 0.98 : 0.94;
	SPECULAR = 0.16;
}
