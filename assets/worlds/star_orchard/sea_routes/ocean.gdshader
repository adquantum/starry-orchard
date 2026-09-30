shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Compatible with the existing haqi water material parameters. Heights are world Y.
uniform float sea_level = 220.0;
uniform bool has_terrain_height = false;
uniform sampler2D terrain_height : filter_linear, repeat_disable;
uniform vec2 terrain_start = vec2(0.0);
uniform vec2 terrain_extent = vec2(1.0);
uniform vec3 deep_color : source_color = vec3(0.075, 0.28, 0.36);
uniform vec3 shallow_color : source_color = vec3(0.23, 0.57, 0.58);
uniform vec3 reflection_color : source_color = vec3(0.30, 0.44, 0.52);
uniform vec3 foam_color : source_color = vec3(0.69, 0.82, 0.79);

// Forward+ reverse-Z opaque depth sees the new island slopes without a new atlas.
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform bool use_scene_depth = true;
uniform float deep_water_depth : hint_range(1.0, 60.0) = 18.0;
uniform float shallow_transition : hint_range(1.0, 30.0) = 8.0;
uniform float foam_width : hint_range(0.1, 5.0) = 1.2;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.48;
uniform float sparkle_strength : hint_range(0.0, 0.2) = 0.055;

varying highp vec3 world_pos;

float inside_atlas(vec2 uv) {
	return step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
}

void vertex() {
	// The swimming surface remains exactly at the mesh's sea_level. Waves affect normals.
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float water_depth = deep_water_depth;
	vec2 terrain_uv = (world_pos.xz - terrain_start) / max(terrain_extent, vec2(0.001));
	if (has_terrain_height && inside_atlas(terrain_uv) > 0.5) {
		water_depth = clamp(sea_level - texture(terrain_height, terrain_uv).r, 0.0, deep_water_depth);
	}
	if (use_scene_depth) {
		float raw_depth = texture(depth_texture, SCREEN_UV).r;
		// Godot 4.3+ reverse-Z: the sky/far-plane clears to zero, not one.
		if (raw_depth > 0.000001) {
			vec3 ndc;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
			ndc = vec3(SCREEN_UV, raw_depth) * 2.0 - 1.0;
#else
			ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
#endif
			vec4 bottom_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
			bottom_view /= max(abs(bottom_view.w), 0.000001) * sign(bottom_view.w);
			vec3 bottom_world = (INV_VIEW_MATRIX * vec4(bottom_view.xyz, 1.0)).xyz;
			float measured_depth = sea_level - bottom_world.y;
			// Opaque geometry above water is not a seabed and must not cause foam.
			if (measured_depth >= 0.0) {
				// The town heightfield is stable across camera motion. Scene depth
				// only adds closer island/shore geometry, never replaces that coast.
				water_depth = min(water_depth, measured_depth);
			}
		}
	}

	vec2 p = world_pos.xz;
	float phase_a = dot(p, vec2(0.16, 0.09)) + TIME * 0.43;
	float phase_b = dot(p, vec2(-0.10, 0.21)) - TIME * 0.36;
	float phase_c = dot(p, vec2(0.34, -0.16)) + TIME * 0.57;
	// Fade unresolved wave frequencies before they shimmer at grazing angles.
	float aa_a = 1.0 - smoothstep(0.6, 2.5, fwidth(phase_a));
	float aa_b = 1.0 - smoothstep(0.6, 2.5, fwidth(phase_b));
	float aa_c = 1.0 - smoothstep(0.6, 2.5, fwidth(phase_c));
	float ripple = sin(phase_a) * 0.55 * aa_a + sin(phase_b) * 0.30 * aa_b + sin(phase_c) * 0.15 * aa_c;
	vec2 gradient = wave_strength * (vec2(0.16, 0.09) * cos(phase_a) * 0.55 * aa_a
		+ vec2(-0.10, 0.21) * cos(phase_b) * 0.30 * aa_b
		+ vec2(0.34, -0.16) * cos(phase_c) * 0.15 * aa_c);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(-gradient.x, 1.0, -gradient.y)), 0.0)).xyz);
	float facing = clamp(dot(NORMAL, normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 4.0);
	float deep_mix = smoothstep(0.15, shallow_transition, water_depth);
	vec3 water = mix(shallow_color, deep_color, deep_mix) * (0.97 + ripple * 0.025);
	water = mix(water, reflection_color, fresnel * 0.38);

	// Thin, moving depth contours break into broad arcs without lattice/hash noise.
	float shore = 1.0 - smoothstep(0.08, foam_width, water_depth);
	float foam_phase = water_depth * 7.0 - TIME * 0.85 + sin(phase_b * 0.6) * 1.5;
	float foam_band = smoothstep(0.52, 0.92, sin(foam_phase)) * (1.0 - smoothstep(0.6, 2.5, fwidth(foam_phase)));
	float foam_breaks = smoothstep(-0.6, 0.7, sin(phase_a * 1.7) + sin(phase_c * 0.8) * 0.5);
	float foam = shore * foam_band * mix(0.35, 0.85, foam_breaks);
	foam *= smoothstep(0.015, 0.10, water_depth);
	water = mix(water, foam_color, foam * 0.65);
	// Restrained sun flecks use the same smooth wave field and no emissive output.
	float flecks = smoothstep(0.86, 0.99, sin(phase_c + sin(phase_a) * 1.3))
		* smoothstep(0.4, 0.93, sin(phase_b * 1.9)) * (1.0 - fresnel) * 0.7 * aa_c * aa_b;
	ALBEDO = clamp(water + vec3(0.85, 0.92, 0.88) * flecks * sparkle_strength, vec3(0.0), vec3(0.86));
	ROUGHNESS = 0.43;
	METALLIC = 0.0;
	SPECULAR = 0.24;
	ALPHA = clamp(mix(0.42, 0.94, smoothstep(0.0, 4.0, water_depth))
		* smoothstep(0.0, 0.10, water_depth) + foam * 0.08, 0.0, 0.96);
}
