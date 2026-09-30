shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform sampler2D source_texture : source_color,filter_linear_mipmap,repeat_enable;
uniform sampler2D bronze_texture : source_color,filter_linear_mipmap,repeat_disable;
uniform bool center_only=false;
uniform float opacity=1.0;
void fragment(){
 vec2 at=fract(UV);
 vec4 original=texture(source_texture,UV);
 if(center_only && at.y>=0.642){discard;}
 if(!center_only && at.y<0.642){discard;}
 vec3 result=original.rgb;
 if(at.y<0.64){
  vec2 pattern=vec2(0.5+at.x*0.5,clamp((at.y-0.10)/0.50,0.0,1.0));
  vec3 bronze=texture(bronze_texture,pattern).rgb*1.5;
  float inside=min(min(texture(source_texture,UV+vec2(0.024,0)).a,texture(source_texture,UV-vec2(0.024,0)).a),min(texture(source_texture,UV+vec2(0,0.006)).a,texture(source_texture,UV-vec2(0,0.006)).a));
  result=mix(vec3(0.62,0.40,0.16),bronze,smoothstep(0.1,0.9,inside));
 }
 ALBEDO=result;
 ALPHA=original.a*opacity;
}
