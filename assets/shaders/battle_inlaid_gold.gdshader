shader_type spatial;
render_mode unshaded,cull_disabled;
uniform vec4 gold_color : source_color = vec4(0.82,0.64,0.36,1);
varying vec3 local_point;
void vertex(){local_point=VERTEX;}
void fragment(){
 float across=clamp(UV.y,0.0,1.0);
 float bevel=smoothstep(0.0,0.23,across)*(1.0-smoothstep(0.77,1.0,across));
 float lip=exp(-pow((across-0.28)/0.13,2.0));
 float patina=0.97+0.025*sin(local_point.x*13.0+local_point.z*8.0)*sin(local_point.z*19.0);
 ALBEDO=gold_color.rgb*(0.42+0.47*bevel+0.30*lip)*patina;
 ROUGHNESS=0.42;
}
