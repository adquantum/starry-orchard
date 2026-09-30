shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	float r = length(UV-vec2(0.5))*2.0;
	float halo = exp(-r*r*6.0)*(1.0-smoothstep(0.7,1.0,r));
	ALBEDO = tint.rgb;
	ALPHA = halo * 0.22;
}
