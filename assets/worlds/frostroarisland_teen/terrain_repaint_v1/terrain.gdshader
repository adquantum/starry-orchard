shader_type spatial;
render_mode cull_back;
uniform sampler2D layer_weights : filter_linear_mipmap, repeat_disable;
uniform sampler2D snow_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ice_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
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
 ALBEDO=texture(snow_texture,uv).rgb*w.r+texture(road_texture,uv).rgb*w.g+texture(rock_texture,uv).rgb*w.b+texture(ice_texture,uv).rgb*w.a;
 ROUGHNESS=dot(w,vec4(0.97,0.92,0.95,0.60));
 SPECULAR=mix(0.12,0.24,w.a);
}
