shader_type spatial;
render_mode cull_back;
uniform sampler2D layer_weights : filter_linear_mipmap, repeat_disable;
uniform bool has_weights = false;
uniform float tile_size = 533.333313;
uniform vec4 fresh_snow : source_color = vec4(0.85,0.90,0.92,1.0);
uniform vec4 packed_snow : source_color = vec4(0.52,0.66,0.75,1.0);
uniform vec4 frozen_ground : source_color = vec4(0.40,0.52,0.62,1.0);
uniform vec4 ice_surface : source_color = vec4(0.43,0.70,0.78,1.0);
uniform vec4 dark_frozen_rock : source_color = vec4(0.24,0.33,0.44,1.0);
varying vec3 world_point;
varying vec3 terrain_normal;
varying vec2 ground_uv;
float hash_corner(vec2 p) {
 vec3 q=fract(vec3(p.x,p.y,p.x)*0.1031);
 q+=dot(q,q.yzx+33.33);
 return fract((q.x+q.y)*q.z);
}
float broad_shape(vec2 p) {
 vec2 cell=floor(p);vec2 f=fract(p);
 f=f*f*f*(f*(f*6.0-15.0)+10.0);
 return mix(mix(hash_corner(cell),hash_corner(cell+vec2(1,0)),f.x),
            mix(hash_corner(cell+vec2(0,1)),hash_corner(cell+vec2(1,1)),f.x),f.y);
}
void vertex() {
 ground_uv=VERTEX.xz/tile_size;
 world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 terrain_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
 vec4 w=has_weights?texture(layer_weights,ground_uv):vec4(1,0,0,0);
 w/=max(dot(w,vec4(1)),0.001);
 vec2 p=world_point.xz;
 // Rotate and stretch the sampling domain; broad feathered deposits, no tiled waves.
 vec2 drift_domain=vec2(p.x*0.81+p.y*0.59,-p.x*0.59+p.y*0.81);
 drift_domain*=vec2(0.055,0.10);
 float broad=broad_shape(drift_domain);
 float small=broad_shape(drift_domain*1.73+vec2(17.2,8.7));
 float drift=broad*0.72+small*0.28;
 // World-space shapes stay continuous across terrain tiles; no displacement.
 float slope=1.0-clamp(terrain_normal.y,0.0,1.0);
 float rock_share=smoothstep(0.12,0.46,slope);
 float rock=w.b*rock_share;
 float ground=w.b-rock;
 float natural_rock=w.r*smoothstep(0.32,0.62,slope)*0.65;
 rock+=natural_rock;
 float snow=max(w.r-natural_rock,0.0);
 vec3 snow_tint=mix(fresh_snow.rgb*vec3(0.70,0.81,0.90),fresh_snow.rgb,drift);
 // Sparse, broad wind-swept strokes within natural snow only.
 float wave=sin(p.x*0.85+p.y*0.24+broad*5.0);
 float wind=smoothstep(0.88,0.99,wave)*smoothstep(0.54,0.73,broad)*0.06;
 snow_tint+=vec3(wind);
 vec3 road_tint=mix(packed_snow.rgb*0.96,mix(packed_snow.rgb,fresh_snow.rgb,0.16),drift);
 vec3 ground_tint=mix(frozen_ground.rgb*0.96,mix(frozen_ground.rgb,packed_snow.rgb,0.45),drift);
 vec3 ice_tint=ice_surface.rgb*mix(0.88,1.08,drift);
 ALBEDO=snow_tint*snow+road_tint*w.g+ground_tint*ground+dark_frozen_rock.rgb*rock+ice_tint*w.a;
 ROUGHNESS=snow*0.96+w.g*0.88+ground*0.94+rock*0.95+w.a*0.48;
 SPECULAR=mix(0.16,0.30,w.a);
}
