shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform sampler2D source_map : source_color, filter_linear_mipmap;
uniform vec4 source_factor : source_color = vec4(1.0);
uniform vec4 school_color : source_color;
uniform bool keep_green = false;
uniform bool thin_shield_glow = false;
uniform bool clear_center = false;
uniform bool floor_token = false;
uniform vec3 mesh_center;
uniform float mesh_factor = 1.0;
varying vec3 local_position;
void vertex(){local_position=(VERTEX-mesh_center)*mesh_factor;}
void fragment(){
 vec4 original=texture(source_map,UV)*source_factor;
 vec3 c=original.rgb;
 if(clear_center){
  vec2 plane=floor_token?local_position.xz:local_position.zy;
  float cover=1.0-smoothstep(0.15,0.23,length(plane));
  c=mix(c,vec3(0.10,0.24,0.10),cover);
 }
 float value=max(c.r,max(c.g,c.b));
 float neutral=min(c.r,min(c.g,c.b));
 vec3 tinted=school_color.rgb*value+vec3(neutral*0.3);
 ALBEDO=keep_green?c:tinted;
 float opacity=original.a;
 if(thin_shield_glow){
  // Erode only the transparent halo footprint; the shield face and its UVs stay fixed.
  float inner_alpha=original.a;
  for(int i=0;i<8;i++){
   float angle=float(i)*0.7853981634;
   vec2 offset=vec2(cos(angle),sin(angle))*0.052;
   vec2 sample_uv=fract(UV)+offset;
   float sample_alpha=(sample_uv.x<0.0 || sample_uv.x>1.0 || sample_uv.y<0.0 || sample_uv.y>1.0)?0.0:texture(source_map,sample_uv).a;
   inner_alpha=min(inner_alpha,sample_alpha);
  }
  float green_glow=smoothstep(0.38,0.72,c.g)*(1.0-smoothstep(0.42,0.78,c.r/max(c.g,0.001)));
  opacity=min(opacity,inner_alpha)*mix(1.0,0.42,green_glow);
 }
 ALPHA=opacity;
}


