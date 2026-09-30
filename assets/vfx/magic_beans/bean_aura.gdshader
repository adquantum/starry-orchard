shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float phase = 0.0;
uniform float power = 1.0;
void fragment() {
	vec2 p = (UV-vec2(0.5))*2.0;
	float r = length(p);
	float a = atan(p.y,p.x);
	float t = TIME*1.5 + phase;
	float rim_radius = 0.39 + sin(a*3.0+t)*0.018;
	float rim = exp(-pow((r-rim_radius)*85.0,2.0));
	float sweep = pow(0.5+0.5*sin(a*2.0-t*2.0),9.0);
	float arc = rim*(0.10+sweep*0.85);
	float haze = exp(-pow((r-0.40)*9.0,2.0))*0.08;
	ALBEDO = mix(tint.rgb,vec3(1.0),sweep*0.025);
	ALPHA = clamp((arc*0.35+haze)*power,0.0,0.55);
}
