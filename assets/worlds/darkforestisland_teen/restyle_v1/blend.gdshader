shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D painted_albedo : source_color, filter_linear_mipmap;
uniform sampler2D original_alpha : filter_linear_mipmap;
uniform float shoulder = 0.0;
void fragment() {
 vec3 color = texture(painted_albedo,UV).rgb;
 ALBEDO = color / (1.0 + max(color.r,max(color.g,color.b))*shoulder);
 // Keep continuous original alpha: web strands must not become opaque cards or hard cutouts.
 ALPHA = texture(original_alpha,UV).a;
 ROUGHNESS = 0.96;
 SPECULAR = 0.12;
}
