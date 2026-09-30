shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D source_texture : source_color,filter_linear_mipmap,repeat_disable;
uniform sampler2D surface_texture : source_color,filter_linear_mipmap,repeat_disable;
uniform bool orient_runes=false;
uniform vec4 rune_regions[8];
float segment(float r,float a,float b,float c,float d){return mix(c,d,clamp((r-a)/(b-a),0.0,1.0));}
float atlas_radius(float r){
 if(r<3.95)return segment(r,0.0,3.95,0.0,350.0);
 if(r<4.14)return segment(r,3.95,4.14,350.0,365.0);
 if(r<6.19)return segment(r,4.14,6.19,365.0,479.0);
 if(r<6.50)return segment(r,6.19,6.50,479.0,497.0);
 if(r<7.62)return segment(r,6.50,7.62,497.0,559.0);
 if(r<7.79)return segment(r,7.62,7.79,559.0,580.0);
 return segment(r,7.79,8.30,580.0,614.0);
}
vec3 add_glyph(vec3 base,vec2 origin,float angle,vec2 uv,bool output_is_srgb){
 vec2 d=uv-origin;
 if(length(d)>0.062)return base;
 vec2 at=origin+vec2(cos(-angle)*d.x-sin(-angle)*d.y,sin(-angle)*d.x+cos(-angle)*d.y);
 vec3 ink=texture(source_texture,at).rgb;
 vec3 srgb=ink;
 if(!output_is_srgb)srgb=mix(ink*12.92,1.055*pow(max(ink,vec3(0.0)),vec3(1.0/2.4))-0.055,step(vec3(0.0031308),ink));
 float mask=smoothstep(0.48,0.69,srgb.r)*smoothstep(0.25,0.43,srgb.g)*smoothstep(1.20,1.50,srgb.g/max(srgb.b,0.01));
 vec3 gold=mix(vec3(0.38,0.23,0.09),vec3(0.78,0.59,0.30),clamp(srgb.r,0.0,1.0));
 return mix(base,gold,mask);
}
void fragment(){
 vec2 center=orient_runes?vec2(626.0,618.0):vec2(626.0,627.0);
 vec2 plane=(UV*1254.0-center)/(orient_runes?(612.0/8.3):(521.0/1.16));
 float r=length(plane);
 float sample_radius;
 if(orient_runes){sample_radius=atlas_radius(r);}
 else{
  if(r<0.67)sample_radius=segment(r,0.0,0.67,0.0,340.0);
  else if(r<0.86)sample_radius=segment(r,0.67,0.86,340.0,479.0);
  else sample_radius=segment(r,0.86,1.16,479.0,614.0);
 }
 vec2 tex_at=vec2(625.0,622.0)/1254.0+plane/max(r,0.00001)*sample_radius/1254.0;
 vec3 result=texture(surface_texture,tex_at).rgb;
 if(orient_runes){
  if(r>4.14 && r<6.19){
   float a=atan(plane.x,-plane.y);
   float d=abs(mod(a+0.314159265,0.62831853)-0.314159265)*r;
   float aa=max(fwidth(d),0.002);
   float line=1.0-smoothstep(0.008,0.008+aa,d);
   result=mix(result,vec3(0.46,0.32,0.15),line*0.65);
  }
  for(int i=0;i<8;i++)result=add_glyph(result,rune_regions[i].xy,rune_regions[i].w,UV,OUTPUT_IS_SRGB);
  result=add_glyph(result,vec2(239.0,613.0)/1254.0,0.0,UV,OUTPUT_IS_SRGB);
  result=add_glyph(result,vec2(1005.0,618.0)/1254.0,0.0,UV,OUTPUT_IS_SRGB);
 }
 ALBEDO=result;
 ROUGHNESS=0.85;
}
