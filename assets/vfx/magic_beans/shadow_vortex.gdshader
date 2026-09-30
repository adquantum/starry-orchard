shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform float speed = 0.7;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float core = 1.0 - smoothstep(0.29, 0.32, r);
	float edge = exp(-pow((r - 0.34) * 35.0, 2.0));
	float arms = pow(0.5 + 0.5 * sin(a * 3.0 + r * 19.0 + TIME * speed * 4.0), 7.0);
	float envelope = smoothstep(0.31, 0.4, r) * (1.0 - smoothstep(0.45, 0.95, r));
	float mist = arms * envelope;
	float fine = pow(0.5+0.5*sin(a*7.0+r*38.0+TIME*speed*6.0),16.0)*envelope;
	float filament = exp(-pow((r-0.38-sin(a*2.0-TIME*speed)*0.025)*90.0,2.0));
	vec3 rim = mix(vec3(0.20, 0.13, 0.32), vec3(0.64, 0.51, 0.78), edge);
	ALBEDO = mix(rim, vec3(0.003, 0.002, 0.008), core);
	ALPHA = max(core, max(edge * 0.85, mist * 0.7+fine*0.35+filament*0.65));
}
