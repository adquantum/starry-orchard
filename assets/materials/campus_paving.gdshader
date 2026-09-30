shader_type spatial;
varying vec3 wp;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=wp.xz*0.62;
 p.x+=mod(floor(p.y),2.0)*0.5;
 vec2 cell=floor(p),q=fract(p);
 float edge=min(min(q.x,1.0-q.x),min(q.y,1.0-q.y));
 float n=fract(sin(dot(cell,vec2(17.13,91.73)))*43758.5);
 float aa=max(fwidth(edge),0.003);
 float slab=smoothstep(0.012-aa,0.012+aa,edge);
 vec3 stone=mix(vec3(0.095,0.115,0.125),vec3(0.12,0.135,0.145),n);
 ALBEDO=mix(vec3(0.074,0.088,0.095),stone,slab);
 ROUGHNESS=0.96;
}


