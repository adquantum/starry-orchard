shader_type spatial;
render_mode blend_mix, cull_disabled;
uniform sampler2D terrain_height : filter_linear, repeat_disable;
uniform vec2 terrain_start;
uniform vec2 terrain_extent;
uniform float sea_level=3.0;
uniform vec3 deep_color : source_color=vec3(0.07,0.19,0.21);
uniform vec3 shallow_color : source_color=vec3(0.20,0.35,0.31);
uniform vec3 reflection_color : source_color=vec3(0.28,0.37,0.42);
uniform vec3 foam_color : source_color=vec3(0.58,0.69,0.64);
varying vec3 world_pos;
float hash21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise2(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);}
float waves(vec2 p){return noise2(p*0.19+vec2(TIME*0.032,-TIME*0.019))*0.65+noise2(p*0.47+vec2(-TIME*0.019,TIME*0.031))*0.35;}
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;VERTEX.y+=sin(world_pos.x*0.021+world_pos.z*0.013+TIME*0.7)*0.045;}
void fragment(){
 vec2 uv=(world_pos.xz-terrain_start)/terrain_extent;
 float valid=step(0.0,uv.x)*step(0.0,uv.y)*step(uv.x,1.0)*step(uv.y,1.0);
 float bottom=mix(sea_level-30.0,texture(terrain_height,uv).r,valid);
 float depth=max(sea_level-bottom,0.0);
 float w=waves(world_pos.xz);
 float dx=(waves(world_pos.xz+vec2(0.3,0))-w)*0.48;
 float dz=(waves(world_pos.xz+vec2(0,0.3))-w)*0.48;
 NORMAL=normalize((VIEW_MATRIX*vec4(normalize(vec3(-dx,1.0,-dz)),0.0)).xyz);
 float fresnel=pow(1.0-clamp(dot(NORMAL,normalize(VIEW)),0.0,1.0),4.0);
 vec3 water=mix(shallow_color,deep_color,smoothstep(0.15,8.0,depth));
 water*=0.95+0.07*w;
 water=mix(water,reflection_color,fresnel*0.48);
 float front=0.5+0.5*sin(depth*4.5-TIME*1.15+noise2(world_pos.xz*0.22)*3.0);
 float foam=smoothstep(0.68,0.91,front)*(1.0-smoothstep(0.15,1.6,depth))*smoothstep(0.015,0.15,depth);
 foam*=smoothstep(0.2,0.7,noise2(world_pos.xz*0.8+TIME*0.03));
 ALBEDO=mix(water,foam_color,foam*0.55);
 ROUGHNESS=0.36;METALLIC=0.0;SPECULAR=0.35;
 ALPHA=mix(0.38,0.94,smoothstep(0.0,4.0,depth))*smoothstep(0.0,0.12,depth)+foam*0.12;
}
