shader_type spatial;
render_mode blend_mix, cull_disabled;
uniform bool has_terrain_height = false;
uniform sampler2D terrain_height : filter_linear, repeat_disable;
uniform vec2 terrain_start;
uniform vec2 terrain_extent = vec2(1.0);
uniform float sea_level=3.0;
uniform vec3 deep_color : source_color=vec3(0.10,0.27,0.33);
uniform vec3 shallow_color : source_color=vec3(0.25,0.46,0.48);
uniform vec3 reflection_color : source_color=vec3(0.28,0.37,0.42);
uniform vec3 foam_color : source_color=vec3(0.58,0.69,0.64);
varying highp vec3 world_pos;
float hash21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise2(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);}
// Continuous directional waves: no square lattice in the visible normals.
float waves(vec2 p){return 0.5+0.22*sin(dot(p,vec2(0.31,0.17))+TIME*0.65)+0.13*sin(dot(p,vec2(-0.19,0.38))-TIME*0.48)+0.08*sin(dot(p,vec2(0.57,-0.24))+TIME*0.8);}
vec2 wave_gradient(vec2 p){return 0.22*vec2(0.31,0.17)*cos(dot(p,vec2(0.31,0.17))+TIME*0.65)+0.13*vec2(-0.19,0.38)*cos(dot(p,vec2(-0.19,0.38))-TIME*0.48)+0.08*vec2(0.57,-0.24)*cos(dot(p,vec2(0.57,-0.24))+TIME*0.8);}
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 uv=(world_pos.xz-terrain_start)/terrain_extent;
 float valid=step(0.0,uv.x)*step(0.0,uv.y)*step(uv.x,1.0)*step(uv.y,1.0);
 float bottom=sea_level-30.0;
 if(has_terrain_height){bottom=mix(bottom,texture(terrain_height,uv).r,valid);}
 float depth=max(sea_level-bottom,0.0);
 float w=waves(world_pos.xz);
 vec2 gradient=wave_gradient(world_pos.xz)*0.22;
 NORMAL=normalize((VIEW_MATRIX*vec4(normalize(vec3(-gradient.x,1.0,-gradient.y)),0.0)).xyz);
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
