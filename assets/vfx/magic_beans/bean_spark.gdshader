shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec2 p = abs((UV-vec2(0.5))*2.0);
	float core = exp(-dot(p,p)*28.0);
	float star = exp(-p.x*55.0-p.y*5.0)+exp(-p.y*55.0-p.x*5.0);
	// Only a tiny white glint at the very center; trails retain their school hue.
	ALBEDO = mix(tint.rgb,vec3(1.0),core*0.06);
	ALPHA = (core+star*0.55)*(1.0-smoothstep(0.6,1.0,length(p)));
}
