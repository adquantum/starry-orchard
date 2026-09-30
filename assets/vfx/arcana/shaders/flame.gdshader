shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec3 uColor : source_color = vec3(1.0, 0.3, 0.1);
uniform vec3 uHot : source_color = vec3(1.0, 0.8, 0.35);
uniform float uOpacity = 1.0;
uniform float uTime = 0.0;
uniform sampler2D uDetail : source_color, filter_linear_mipmap;

float hash_value(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise_value(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_value(cell), hash_value(cell + vec2(1.0, 0.0)), f.x),
		mix(hash_value(cell + vec2(0.0, 1.0)), hash_value(cell + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float y = UV.y;
	float first_noise = noise_value(vec2(UV.x * 6.0, y * 6.0 - uTime * 3.5));
	float second_noise = noise_value(vec2(UV.x * 12.0, y * 12.0 - uTime * 6.0));
	float sway = sin(y * 7.0 - uTime * 3.0) * y * 0.12;
	float x = abs(UV.x - 0.5 + sway + (first_noise - 0.5) * y * 0.22);
	float width = 0.48 * pow(max(0.0, 1.0 - y), 0.72);
	float distance_value = width - x - (second_noise - 0.5) * 0.12;
	float mask = smoothstep(0.0, 0.065, distance_value) * smoothstep(0.0, 0.10, y) * (1.0 - smoothstep(0.75, 1.0, y));
	float core = clamp(1.0 - x / max(0.03, width), 0.0, 1.0) * (1.0 - y);
	float detail = dot(texture(uDetail, UV).rgb, vec3(0.299, 0.587, 0.114));
	vec3 color = mix(uColor, uHot, pow(core, 1.5) * (0.8 + detail * 0.4));
	ALBEDO = color;
	EMISSION = color * (1.3 + core + detail * 0.4);
	ALPHA = mask * uOpacity * (0.68 + detail * 0.25);
}
