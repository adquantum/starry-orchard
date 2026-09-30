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
varying float terrain_slope;
void vertex(){terrain_slope=1.0-NORMAL.y;ground_uv=VERTEX.xz/tile_size;world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float hash21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float soft_noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);}
void fragment(){
 vec4 w=texture(layer_weights,ground_uv);
 w/=max(dot(w,vec4(1.0)),0.001);
 float slope=terrain_slope;
 float n=soft_noise(world_point.xz*0.11)*0.65+soft_noise(world_point.xz*0.031)*0.35;
 vec3 rock=mix(rock_color.rgb,rock_color.rgb*vec3(0.79,0.86,0.91),smoothstep(0.05,0.42,slope));
 vec3 base=grass_color.rgb*w.r+earth_color.rgb*w.g+rock*w.b+sand_color.rgb*w.a;
 // Existing entry and camp clearings only; no new path or object placement.
 float entry=1.0-smoothstep(10.0,28.0,length((world_point.xz-vec2(7.6,160.0))*vec2(1.0,0.65)));
 float camp=1.0-smoothstep(5.0,18.0,length(world_point.xz-vec2(-110.0,-280.0)));
 float clearing=max(entry,camp)*smoothstep(0.18,0.65,n)*(1.0-smoothstep(0.18,0.4,slope));
 base=mix(base,earth_color.rgb*0.94,clearing*0.60);
 ALBEDO=base*(0.94+n*0.12);
 ROUGHNESS=0.96;
 SPECULAR=0.12;
}
