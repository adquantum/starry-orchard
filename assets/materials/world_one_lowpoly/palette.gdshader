shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, specular_disabled;
uniform sampler2D source_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 source_tint : source_color = vec4(1.0);
uniform vec4 shadow_color : source_color;
uniform vec4 body_color : source_color;
uniform vec4 light_color : source_color;
uniform vec4 accent_color : source_color;
uniform vec4 secondary_color : source_color;
uniform vec4 stone_color : source_color;
uniform float detail_lod = 3.5;
uniform bool architecture = false;
uniform bool has_map = true;
uniform float roof_start=0.0;
varying float local_height;
varying vec3 local_normal;
void vertex() { local_height=VERTEX.y; local_normal=NORMAL; }
void fragment() {
 vec4 source_pixel = has_map ? texture(source_map, UV) * source_tint : source_tint;
 ALPHA = source_pixel.a;
 ALPHA_SCISSOR_THRESHOLD = 0.45;
 vec3 c=has_map ? textureLod(source_map,UV,detail_lod).rgb*source_tint.rgb : source_tint.rgb;
 float hi=max(c.r,max(c.g,c.b));
 float lo=min(c.r,min(c.g,c.b));
 float sat=(hi-lo)/max(hi,0.001);
 float value=dot(c,vec3(0.2126,0.7152,0.0722));
 vec3 color=body_color.rgb;
 if (architecture) {
  color=local_height>roof_start && abs(normalize(local_normal).y)>0.15 ? accent_color.rgb : stone_color.rgb;
 } else {
  if(value<0.006) color=shadow_color.rgb;
  else if(sat<0.22) color=value>0.3 ? light_color.rgb : stone_color.rgb;
  else if(c.r>c.g*1.28 && c.r>c.b*1.1) color=secondary_color.rgb;
  else if(c.g>c.r*1.1 && c.g>c.b*1.03) color=accent_color.rgb;
  else if(value>0.5) color=light_color.rgb;
 }
 ALBEDO=color;
 // Derivatives follow the skinned triangles. Meshes, weights and animations stay unchanged.
 vec3 face_normal=normalize(cross(dFdx(VERTEX),dFdy(VERTEX)));
 if(dot(face_normal,NORMAL)<0.0) face_normal=-face_normal;
 NORMAL=face_normal;
 ROUGHNESS=1.0;
 METALLIC=0.0;
}
void light() {
 float facing=max(dot(NORMAL,LIGHT),0.0);
 float band=facing>0.72 ? 1.0 : (facing>0.32 ? 0.75 : (facing>0.04 ? 0.48 : 0.2));
 DIFFUSE_LIGHT+=LIGHT_COLOR*ATTENUATION*band/3.14159265;
}

