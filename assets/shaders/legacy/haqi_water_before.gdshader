shader_type spatial;
render_mode blend_mix, cull_disabled;
uniform vec3 deep_color : source_color = vec3(0.035,0.32,0.38);
uniform vec3 rim_color : source_color = vec3(0.24,0.52,0.60);
varying vec3 world_pos;
void vertex() {
 world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 VERTEX.y+=sin(world_pos.x*0.08+TIME*1.1)*0.055+cos(world_pos.z*0.11-TIME*0.85)*0.035;
}
void fragment() {
 float a=sin(world_pos.x*1.8+world_pos.z*0.7+TIME*1.5);
 float b=cos(world_pos.z*2.2-world_pos.x*0.4-TIME*1.1);
 NORMAL=normalize(NORMAL+vec3(a*0.045,b*0.035,0.0));
 float fresnel=pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),3.0);
 float glint=pow(max(0.0,a*b),10.0)*0.09;
 ALBEDO=mix(deep_color,rim_color,fresnel)+glint;
 ROUGHNESS=0.24;METALLIC=0.12;SPECULAR=0.7;
 ALPHA=0.76+fresnel*0.2;
}
