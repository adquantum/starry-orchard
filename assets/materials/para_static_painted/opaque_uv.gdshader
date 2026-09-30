shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painted_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D source_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 source_tint : source_color = vec4(1.0);
uniform bool use_cutout = false;
uniform float alpha_cutoff = 0.4;
void fragment() {
    float original_alpha = texture(source_map,UV).a * source_tint.a;
    if (use_cutout && original_alpha < alpha_cutoff) discard;
    ALBEDO = texture(painted_map,UV).rgb * source_tint.rgb;
    ROUGHNESS = 0.95;
    METALLIC = 0.0;
    SPECULAR = 0.15;
}
