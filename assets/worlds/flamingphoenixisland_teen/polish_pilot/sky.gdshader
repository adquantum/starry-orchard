shader_type sky;
uniform vec3 zenith : source_color = vec3(0.30,0.24,0.40);
uniform vec3 horizon : source_color = vec3(0.78,0.58,0.43);
void sky(){
 float h=max(EYEDIR.y,0.0);
 vec3 col=mix(horizon,zenith,pow(clamp(h/0.72,0.0,1.0),0.62));
 vec2 p=EYEDIR.xz/(h+0.32)*1.4;
 float billow=0.5+0.22*sin(p.x*1.2+sin(p.y*0.8))+0.17*cos(p.y*1.5-p.x*0.32);
 float clouds=smoothstep(0.30,0.85,billow);
 col=mix(col,vec3(0.67,0.48,0.43),clouds*0.32*smoothstep(0.015,0.16,h));
 COLOR=col;
}
