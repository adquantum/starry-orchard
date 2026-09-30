shader_type sky;
uniform vec3 horizon_color : source_color = vec3(0.60,0.74,0.84);
uniform vec3 zenith_color : source_color = vec3(0.28,0.44,0.63);
void sky() {
 vec3 d=normalize(EYEDIR);
 float h=max(d.y,0.0);float az=atan(d.z,d.x);
 vec3 col=mix(horizon_color,zenith_color,smoothstep(0.0,0.85,h));
 float shape=sin(az*4.0+h*13.0)+0.38*sin(az*9.0-h*19.0);
 float cloud=smoothstep(0.20,0.75,shape)*smoothstep(0.015,0.10,h)*(1.0-smoothstep(0.35,0.55,h));
 col=mix(col,vec3(0.48,0.60,0.70),cloud*0.65);
 float ribbon=exp(-pow((h-0.64-0.05*sin(az*3.0))/0.035,2.0));
 col+=vec3(0.018,0.035,0.040)*ribbon*smoothstep(0.2,0.9,sin(az*2.0));
 if(d.y<0.0)col=mix(horizon_color,zenith_color,smoothstep(0.0,0.5,-d.y));
 COLOR=col;
}
