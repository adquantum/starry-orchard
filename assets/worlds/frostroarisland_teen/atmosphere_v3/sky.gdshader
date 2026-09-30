shader_type sky;
uniform vec3 horizon_color : source_color = vec3(0.71,0.76,0.80);
uniform vec3 zenith_color : source_color = vec3(0.40,0.59,0.76);
uniform vec3 cloud_color : source_color = vec3(0.78,0.82,0.86);
uniform float aurora_strength = 0.025;
void sky() {
 vec3 d=normalize(EYEDIR);float h=max(d.y,0.0);float az=atan(d.z,d.x);
 vec3 col=mix(horizon_color,zenith_color,pow(smoothstep(0.0,0.80,h),0.65));
 float shape=sin(az*3.0+h*9.0)+0.30*sin(az*7.0-h*12.0);
 float cloud=smoothstep(-0.20,1.0,shape)*smoothstep(0.015,0.13,h)*(1.0-smoothstep(0.35,0.62,h));
 col=mix(col,cloud_color,cloud*0.52);
 float center=0.64+0.05*sin(az*2.0);
 float ribbon=exp(-pow((h-center)/0.045,2.0))*smoothstep(0.25,0.85,sin(az*2.0));
 vec3 aurora=mix(vec3(0.30,0.58,0.55),vec3(0.47,0.39,0.62),0.5+0.5*sin(az));
 col=mix(col,aurora,ribbon*aurora_strength);
 if(d.y<0.0)col=mix(horizon_color,zenith_color,smoothstep(0.0,0.6,-d.y)*0.5);
 COLOR=col;
}
