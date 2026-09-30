shader_type spatial;
render_mode cull_disabled;

uniform sampler2D base_map : source_color, filter_linear_mipmap;
uniform sampler2D painted_map : source_color, filter_linear_mipmap;
uniform sampler2D cloth_mask : filter_linear;
uniform bool has_clothes = true;
uniform bool has_boots = false;
uniform sampler2D boots_map : source_color, filter_linear_mipmap;
uniform sampler2D boots_mask : filter_linear;

void fragment() {
	// Imported source atlases use repeating UVs, including negative V values.
	vec2 atlas_uv = fract(UV);
	vec4 base = texture(base_map, atlas_uv);
	float coverage = texture(cloth_mask, atlas_uv).a * float(has_clothes);
	// Boots are composited into this quadrant by TeenAvatar; keep their own art.
	if (atlas_uv.y >= 0.75 && atlas_uv.x < 0.5) {
		coverage = 0.0;
	}
	ALBEDO = mix(base.rgb, texture(painted_map, atlas_uv).rgb, coverage);
	if(has_boots && atlas_uv.x<0.5 && atlas_uv.y>=0.75){
		vec2 boot_uv=(atlas_uv-vec2(0.0,0.75))*vec2(2.0,4.0);
		ALBEDO=mix(base.rgb,texture(boots_map,boot_uv).rgb,texture(boots_mask,boot_uv).a);
	}
	ALPHA = base.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.85;
}
