shader_type spatial;
render_mode cull_back;
uniform sampler2D layer_weights : filter_linear_mipmap, repeat_disable;
uniform bool has_weights = false;
uniform float tile_size = 533.333313;
uniform vec4 snow_color : source_color = vec4(0.88,0.92,0.92,1.0);
uniform vec4 road_color : source_color = vec4(0.58,0.72,0.80,1.0);
uniform vec4 rock_color : source_color = vec4(0.32,0.43,0.55,1.0);
uniform vec4 ice_color : source_color = vec4(0.40,0.73,0.80,1.0);
varying vec3 world_point;
varying vec2 ground_uv;
void vertex(){ground_uv=VERTEX.xz/tile_size;world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec4 w=has_weights?texture(layer_weights,ground_uv):vec4(1.0,0.0,0.0,0.0);
 w/=max(dot(w,vec4(1.0)),0.001);
 // Broad low-contrast shapes instead of the old high-frequency dirt texture.
 float swath=sin(world_point.x*0.065+sin(world_point.z*0.04)*1.6)*sin(world_point.z*0.08);
 float bands=smoothstep(-0.3,0.3,swath)*0.045-0.02;
 ALBEDO=(snow_color.rgb*w.r+road_color.rgb*w.g+rock_color.rgb*w.b+ice_color.rgb*w.a)*(1.0+bands);
 ROUGHNESS=dot(w,vec4(0.96,0.86,0.93,0.34));
 SPECULAR=mix(0.15,0.4,w.a);
}
