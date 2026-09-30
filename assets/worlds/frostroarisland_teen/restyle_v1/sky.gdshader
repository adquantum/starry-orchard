shader_type sky;
void sky(){
 vec3 d=normalize(EYEDIR);
 float elevation=max(d.y,0.0);
 vec3 col=mix(vec3(0.64,0.77,0.85),vec3(0.17,0.30,0.52),smoothstep(0.0,0.95,elevation));
 float az=atan(d.z,d.x);
 float cloud_shape=sin(az*5.0+elevation*9.0)+0.45*sin(az*11.0-elevation*16.0);
 float clouds=smoothstep(0.25,0.5,cloud_shape)*smoothstep(0.05,0.16,elevation)*(1.0-smoothstep(0.38,0.57,elevation));
 col=mix(col,vec3(0.79,0.86,0.91),clouds*0.85);
 float ribbon_center=0.63+0.08*sin(az*3.0)+0.025*sin(az*9.0);
 float ribbon=exp(-pow((elevation-ribbon_center)/0.045,2.0));
 float segment=smoothstep(-0.25,0.5,sin(az*2.0+0.7));
 col+=mix(vec3(0.12,0.26,0.22),vec3(0.18,0.10,0.26),0.5+0.5*sin(az*4.0))*ribbon*segment*0.30;
 if(d.y<0.0){col=mix(vec3(0.64,0.77,0.85),vec3(0.29,0.40,0.52),smoothstep(0.0,0.45,-d.y));}
 COLOR=col;
}
