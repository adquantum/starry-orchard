shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform sampler2D source_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 source_factor : source_color = vec4(1.0);
uniform vec4 school_color : source_color = vec4(1.0);
void fragment() {
	vec4 c=texture(source_map,UV)*source_factor;
	float hi=max(c.r,max(c.g,c.b));
	float lo=min(c.r,min(c.g,c.b));
	bool gold=c.r>c.b*1.4 && c.g>c.b*1.3 && c.r>c.g*0.95 && c.g>c.r*0.5;
	float replace=(gold || hi-lo<0.14)?0.0:0.8;
	vec3 recolor=school_color.rgb*clamp(hi*1.35,0.0,1.0);
	ALBEDO=mix(c.rgb,recolor,replace);
	ALPHA=c.a;
}
