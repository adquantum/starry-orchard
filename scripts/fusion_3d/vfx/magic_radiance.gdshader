shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0);
uniform float strength = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}
void fragment() {
	float r = length((UV - 0.5) * 2.0);
	float core = exp(-r*r*65.0);
	float halo = exp(-r*r*7.0) * (1.0-smoothstep(0.65,1.0,r));
	ALBEDO = mix(tint.rgb,vec3(1.0),core*0.65);
	EMISSION = ALBEDO * 1.8;
	ALPHA = (core*0.7+halo*0.16)*strength;
}
