shader_type spatial;
render_mode cull_back;
uniform sampler2D layer_weights : filter_linear_mipmap, repeat_disable;
uniform sampler2D grass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lava_weights : filter_linear_mipmap, repeat_disable;
uniform sampler2D lava_crust : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lava_molten : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_lava = false;
uniform bool has_weights = false;
uniform float tile_size = 533.333313;
uniform float texture_world_size = 16.0;
varying highp vec3 world_point;
varying vec2 ground_uv;
void vertex(){ground_uv=VERTEX.xz/tile_size;world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec4 w=has_weights?texture(layer_weights,ground_uv):vec4(1.0,0.0,0.0,0.0);
 w/=max(dot(w,vec4(1.0)),0.001);
 vec2 uv=world_point.xz/texture_world_size;
 ALBEDO=texture(grass_texture,uv).rgb*w.r+texture(earth_texture,uv).rgb*w.g+texture(rock_texture,uv).rgb*w.b+texture(sand_texture,uv).rgb*w.a;
 ROUGHNESS=dot(w,vec4(0.98,0.97,0.95,0.98));
 SPECULAR=0.12;
 if(has_lava){
  vec3 lw=texture(lava_weights,ground_uv).rgb;
  float amount=clamp(lw.g+lw.b,0.0,1.0);
  vec2 flow=vec2(TIME*0.008,TIME*0.005);
  vec3 crust=texture(lava_crust,uv+flow*0.2).rgb;
  vec3 molten=texture(lava_molten,uv+flow).rgb;
  vec3 lava=(crust*lw.g+molten*lw.b)/max(amount,0.001);
  ALBEDO=mix(ALBEDO,lava,amount);
  float heat=clamp((lava.r-lava.b)*1.4,0.0,1.0);
  EMISSION=lava*heat*amount*(1.15+0.12*sin(TIME*0.7+world_point.x*0.04));
  ROUGHNESS=mix(ROUGHNESS,0.75,amount);
 }
}
