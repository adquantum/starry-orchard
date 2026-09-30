shader_type spatial;
render_mode cull_disabled;
uniform sampler2D original_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D painted_map : source_color, filter_linear_mipmap, repeat_enable;
// Data maps deliberately have no source_color hint: RGBA stores four dye weights.
uniform sampler2D dye_mask : filter_linear_mipmap, repeat_enable;
uniform sampler2D skin_mask : filter_linear_mipmap, repeat_enable;
uniform sampler2D skin_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 primary_color : source_color = vec4(0.24,0.48,0.63,1.0);
uniform vec4 secondary_color : source_color = vec4(0.18,0.25,0.34,1.0);
uniform vec4 trim_color : source_color = vec4(0.92,0.73,0.40,1.0);
uniform vec4 hardware_color : source_color = vec4(0.77,0.83,0.87,1.0);
void fragment() {
    vec3 protection=texture(skin_mask,UV).rgb;
    if (protection.g<0.5) discard;
    vec4 zones=texture(dye_mask,UV);
    float weight=dot(zones,vec4(1.0));
    vec3 base=texture(original_map,UV).rgb;
    base=mix(base,texture(skin_map,UV).rgb,protection.r);
    vec3 paint=texture(painted_map,UV).rgb;
    float tone=dot(paint,vec3(0.2126,0.7152,0.0722));
    float shade=mix(0.42,1.22,pow(max(tone,0.0),0.45));
    vec3 dye=(primary_color.rgb*zones.r+secondary_color.rgb*zones.g+trim_color.rgb*zones.b+hardware_color.rgb*zones.a)/max(weight,0.0001);
    ALBEDO=mix(base,dye*shade,clamp(weight,0.0,1.0));
    ROUGHNESS=mix(0.9,0.66,zones.a);
    METALLIC=0.04*zones.a;
    SPECULAR=0.2;
}
