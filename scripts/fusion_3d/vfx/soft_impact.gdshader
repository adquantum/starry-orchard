shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity = 1.0;
uniform sampler2D painted_burst : source_color, filter_linear_mipmap, repeat_disable;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float core = exp(-r*r*42.0);
	vec4 painted = texture(painted_burst,UV);
	ALBEDO = painted.rgb * mix(tint.rgb,vec3(1.0),core*0.5);
	EMISSION = ALBEDO * (0.7 + core * 1.8);
	ALPHA = painted.a * opacity * 0.6;
}
