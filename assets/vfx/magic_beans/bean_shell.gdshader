shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity = 0.88;
void fragment() {
	float facing = max(dot(normalize(NORMAL), normalize(VIEW)), 0.0);
	float rim = pow(1.0-facing, 2.4);
	ALBEDO = tint.rgb * 0.65;
	EMISSION = tint.rgb * (0.16 + rim * 0.6);
	ROUGHNESS = 0.24;
	SPECULAR = 0.14;
	ALPHA = clamp(opacity + rim * 0.10, 0.0, 0.98);
}
