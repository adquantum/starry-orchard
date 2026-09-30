shader_type spatial;
// Reuse the painted bridge atlas's wood-only strip; restrained weathered timber.
uniform sampler2D wood_atlas : source_color, filter_linear_mipmap;
void fragment() {
    vec3 grain=texture(wood_atlas,vec2(0.025+UV.x*0.16,0.20+UV.y*0.48)).rgb;
    float value=clamp(dot(grain,vec3(0.25,0.45,0.30))*2.0,0.0,1.0);
    ALBEDO=mix(vec3(0.16,0.105,0.065),vec3(0.46,0.34,0.23),value);
    ROUGHNESS=0.94;
    SPECULAR=0.16;
}
