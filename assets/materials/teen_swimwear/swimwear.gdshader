shader_type spatial;
render_mode cull_disabled;
uniform sampler2D base_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloth_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloth_mask : filter_linear_mipmap, repeat_enable;
uniform float cloth_roughness : hint_range(0.0,1.0) = 0.8;
void fragment() {
    vec4 base = texture(base_map,UV);
    if (base.a < 0.5) discard;
    float coverage = texture(cloth_mask,UV).r;
    ALBEDO = mix(base.rgb,texture(cloth_map,UV).rgb,coverage);
    ROUGHNESS = mix(0.85,cloth_roughness,coverage);
    METALLIC = 0.0;
    SPECULAR = 0.5;
}
