shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D painted : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D original_alpha : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float cutoff = 0.5;
uniform float surface_roughness = 0.9;
void fragment() {
	ALBEDO = texture(painted, UV).rgb * tint.rgb;
	ALPHA = texture(original_alpha, UV).a * tint.a;
	ALPHA_SCISSOR_THRESHOLD = cutoff;
	ROUGHNESS = surface_roughness;
}
