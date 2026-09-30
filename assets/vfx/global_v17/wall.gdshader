shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform sampler2D school_pattern : source_color, repeat_enable, filter_linear_mipmap;
uniform vec4 school_color : source_color = vec4(1.0,0.3,0.05,1.0);
void fragment(){
	float phase=UV.x*2.0-TIME*0.035;
	float mirrored_u=1.0-abs(fract(phase)*2.0-1.0);
	vec4 tex=texture(school_pattern,vec2(mirrored_u,UV.y));
	float fade=smoothstep(0.015,0.10,UV.y)*(1.0-smoothstep(0.90,0.985,UV.y));
	float pulse=0.92+0.08*sin(TIME*1.7);
	ALBEDO=tex.rgb;
	EMISSION=tex.rgb*0.70+school_color.rgb*tex.a*0.18;
	ALPHA=tex.a*fade*0.46*pulse;
}
