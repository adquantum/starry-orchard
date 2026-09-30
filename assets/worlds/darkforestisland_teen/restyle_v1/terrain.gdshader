shader_type spatial;
render_mode cull_back;
uniform sampler2D layer_weights : filter_linear_mipmap, repeat_disable;
uniform float tile_size = 533.333313;
uniform vec4 grass_color : source_color = vec4(0.23,0.31,0.265,1.0);
uniform vec4 earth_color : source_color = vec4(0.36,0.30,0.245,1.0);
uniform vec4 rock_color : source_color = vec4(0.285,0.305,0.335,1.0);
uniform vec4 sand_color : source_color = vec4(0.46,0.425,0.35,1.0);
varying vec3 world_point;
varying vec2 ground_uv;
void vertex(){ground_uv=VERTEX.xz/tile_size;world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec4 w=texture(layer_weights,ground_uv);
 w/=max(dot(w,vec4(1.0)),0.001);
 // Low-frequency world-space color variation stays continuous across terrain tiles.
 float swath=sin(world_point.x*0.095+sin(world_point.z*0.061)*1.6)*sin(world_point.z*0.113);
 float bands=smoothstep(-0.25,0.25,swath)*0.065-0.03;
 ALBEDO=(grass_color.rgb*w.r+earth_color.rgb*w.g+rock_color.rgb*w.b+sand_color.rgb*w.a)*(1.0+bands);
 ROUGHNESS=0.96;
 SPECULAR=0.12;
}
