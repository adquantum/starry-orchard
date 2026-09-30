shader_type sky;
void sky(){
 float h=clamp(EYEDIR.y,0.0,1.0);
 vec3 base=mix(vec3(0.12,0.15,0.18),vec3(0.025,0.045,0.09),smoothstep(0.0,0.85,h));
 vec2 p=EYEDIR.xz/(max(EYEDIR.y,0.09)+0.35);
 float shapes=sin(p.x*2.1+sin(p.y*1.6))*sin(p.y*2.7+p.x*0.6);
 float cloud=smoothstep(0.22,0.52,shapes)*smoothstep(0.01,0.22,h)*(1.0-smoothstep(0.7,0.95,h));
 COLOR=mix(base,vec3(0.18,0.21,0.24),cloud*0.42);
}
