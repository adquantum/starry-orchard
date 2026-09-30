shader_type sky;
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
// Entrance approach (-484,-28) toward the original altar (-690.12,134.48).
uniform float altar_azimuth = -0.9032563464053384;
uniform float red_glow_u = 0.1285231;
uniform float energy = 0.8;
void sky(){
 vec3 d=normalize(EYEDIR);
 float u=fract((atan(d.x,d.z)-altar_azimuth)/6.28318530718+red_glow_u);
 float v=acos(clamp(d.y,-1.0,1.0))/3.14159265359;
 COLOR=texture(panorama,vec2(u,v)).rgb*energy;
}
