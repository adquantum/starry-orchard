shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec3 uColor : source_color = vec3(0.5, 0.8, 1.0);
uniform float uOpacity = 1.0;
uniform float uTime = 0.0;
uniform float uPattern = 0.0;
uniform sampler2D uDetail : source_color, filter_linear_mipmap;

float ring(float radius, float target, float width) {
	return 1.0 - smoothstep(width, width + 0.012, abs(radius - target));
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float mask = ring(radius, 0.82, 0.009) + ring(radius, 0.92, 0.004) * 0.65;
	float bars = step(0.75, cos(angle * 24.0 + uTime * 0.2)) * step(0.7, radius) * step(radius, 0.86);
	float inner = ring(radius, 0.53, 0.006) * 0.7;
	if (uPattern < 0.5) {
		mask += bars * 0.5 + inner;
		mask += abs(cos(angle * 3.0)) * pow(max(0.0, 1.0 - radius), 3.0) * 0.12;
	} else if (uPattern < 1.5) {
		mask = ring(radius, 0.8, 0.025) + ring(radius, 0.89, 0.008) * 0.4;
	} else {
		mask += ring(radius, 0.64 + 0.035 * sin(angle * 7.0 + uTime * 2.0), 0.01) * 0.4 + bars * 0.65;
	}
	float detail = dot(texture(uDetail, UV).rgb, vec3(0.299, 0.587, 0.114));
	float grain = mix(0.82, 1.25, detail);
	ALBEDO = uColor;
	EMISSION = uColor * (1.35 + detail * 0.5);
	ALPHA = clamp(mask * grain, 0.0, 1.0) * uOpacity;
}
