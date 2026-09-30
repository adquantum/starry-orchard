shader_type spatial;
uniform sampler2D source_ground : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D source_weights : filter_linear_mipmap, repeat_disable;
varying vec3 world_pos;
varying float slope;
float hash2(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise2(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*f*(f*(f*6.0-15.0)+10.0);return mix(mix(hash2(i),hash2(i+vec2(1,0)),f.x),mix(hash2(i+vec2(0,1)),hash2(i+vec2(1,1)),f.x),f.y);}
float pilot(vec2 p){return max(max(1.0-smoothstep(58.0,100.0,distance(p,vec2(-189.1875,-382.785156))),1.0-smoothstep(58.0,100.0,distance(p,vec2(-195,-150)))),1.0-smoothstep(58.0,100.0,distance(p,vec2(45,-240))));}
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;slope=clamp((MODEL_NORMAL_MATRIX*NORMAL).y,0.0,1.0);}
void fragment(){
 vec3 original=texture(source_ground,UV).rgb;
 vec4 w=texture(source_weights,UV); w/=max(dot(w,vec4(1)),0.001);
 float blend=pilot(world_pos.xz);
 float broad=noise2(world_pos.xz*0.038);
 float detail=clamp(dot(original,vec3(0.30,0.59,0.11)),0.0,0.55);
 vec3 ash=vec3(0.25,0.105,0.073)*(0.88+0.20*broad)+detail*0.18;
 vec3 road=vec3(0.43,0.265,0.125)*(0.92+0.12*broad)+detail*0.20;
 vec3 rock=mix(vec3(0.072,0.043,0.056),vec3(0.15,0.073,0.061),slope)* (0.9+0.16*broad)+detail*0.12;
 // Emission follows original red fissures, never invents a new lava boundary.
 float hot=smoothstep(0.10,0.52,original.r)*smoothstep(0.05,0.30,original.r-original.g);
 vec3 lava=mix(vec3(0.060,0.030,0.038),vec3(0.62,0.115,0.016),hot);
 vec3 layered=ash*w.r+road*w.g+rock*w.b+lava*w.a;
 ALBEDO=mix(original,layered,blend*0.60);
 float pulse=0.90+0.10*sin(TIME*1.4+world_pos.x*0.16+world_pos.z*0.13);
 EMISSION=vec3(1.0,0.19,0.018)*hot*w.a*blend*pulse*0.65;
 ROUGHNESS=mix(0.96,0.70,w.a*hot*blend); SPECULAR=0.25;
}
