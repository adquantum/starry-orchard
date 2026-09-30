shader_type spatial;
uniform sampler2D meadow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 court_center;
uniform float court_radius = 22.0;
varying vec3 world_position;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 uv = p * 0.03575;
	vec3 grass_color = texture(meadow, uv).rgb * vec3(0.91, 0.98, 0.88);
	vec3 earth_color = texture(soil, uv).rgb * vec3(0.94, 0.98, 0.92);
	float broad = hash21(floor(p * 0.095));
	float fine = hash21(floor(p * 0.34 + vec2(7.0, 13.0)));
	float worn = smoothstep(0.62, 0.91, broad * 0.7 + fine * 0.3);
	float distance_to_center = distance(p, court_center);
	float center_fade = 1.0 - smoothstep(court_radius * 0.52, court_radius * 1.04, distance_to_center);
	ALBEDO = mix(grass_color, earth_color, worn * center_fade * 0.16);
	ROUGHNESS = 0.98;
	SPECULAR = 0.16;
}
