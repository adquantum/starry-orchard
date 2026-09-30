shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 glow_color : source_color;
float edge_distance(vec2 p,vec2 a,vec2 b){vec2 e=b-a;return length(p-a-e*clamp(dot(p-a,e)/dot(e,e),0.0,1.0));}
void fragment(){
 vec2 p=vec2((UV.x-0.5)*0.58,(0.5-UV.y)*1.12+0.29);
 vec2 v[5]=vec2[5](vec2(-0.14,-0.14),vec2(0.14,-0.14),vec2(0.14,0.49),vec2(0.0,0.72),vec2(-0.14,0.49));
 float d=1.0;bool inside=true;
 for(int i=0;i<5;i++){vec2 a=v[i];vec2 b=v[(i+1)%5];d=min(d,edge_distance(p,a,b));vec2 e=b-a;if(e.x*(p.y-a.y)-e.y*(p.x-a.x)<0.0)inside=false;}
 float halo=exp(-d*d/0.0010)*(1.0-smoothstep(0.055,0.095,d));
 ALBEDO=glow_color.rgb*1.4;
 ALPHA=inside?0.0:halo*0.55;
}
