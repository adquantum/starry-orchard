shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painted_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D original_texture : source_color, filter_linear_mipmap_anisotropic;
void fragment(){
 ALBEDO=texture(painted_texture,UV).rgb;
 ALPHA=texture(original_texture,UV).a;
 ALPHA_SCISSOR_THRESHOLD=0.4;
 ROUGHNESS=0.9;
 SPECULAR=0.25;
}
