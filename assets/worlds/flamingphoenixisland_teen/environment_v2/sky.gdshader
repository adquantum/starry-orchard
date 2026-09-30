shader_type sky;
uniform sampler2D painted_sky : source_color, filter_linear_mipmap, repeat_enable;
void sky() {
 vec2 uv = SKY_COORDS;
 vec3 painted = texture(painted_sky,uv).rgb;
 // Blend a narrow longitude seam using the panorama's own edge colors.
 float edge = min(uv.x,1.0-uv.x);
 vec3 seam = (texture(painted_sky,vec2(0.002,uv.y)).rgb+texture(painted_sky,vec2(0.998,uv.y)).rgb)*0.5;
 COLOR = mix(seam,painted,smoothstep(0.0,0.018,edge));
}
