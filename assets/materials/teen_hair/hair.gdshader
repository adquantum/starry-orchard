shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painted_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D original_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dye_mask : filter_linear_mipmap, repeat_enable;
uniform vec4 hair_color : source_color = vec4(0.8,0.6,0.3,1.0);
void fragment() {
 vec4 original = texture(original_map, UV);
 if (original.a < 0.5) { discard; }
 vec3 painted = texture(painted_map, UV).rgb;
 float tone = dot(painted,vec3(0.2126,0.7152,0.0722));
 float shade = mix(0.42,1.22,pow(clamp(tone,0.0,1.0),0.45));
 vec3 dyed = hair_color.rgb * shade;
 ALBEDO = mix(original.rgb,dyed,texture(dye_mask,UV).r);
 ROUGHNESS = 0.82;
 SPECULAR = 0.18;
}
