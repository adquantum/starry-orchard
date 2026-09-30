shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painted_albedo : source_color, filter_linear_mipmap;
uniform sampler2D original_alpha : filter_linear_mipmap;
void fragment() {
 ALBEDO=texture(painted_albedo,UV).rgb;
 ALPHA=texture(original_alpha,UV).a;
 ALPHA_SCISSOR_THRESHOLD=0.4;
 ROUGHNESS=0.96;
 SPECULAR=0.18;
}
