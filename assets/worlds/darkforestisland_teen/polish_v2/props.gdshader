shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painted_albedo : source_color, filter_linear_mipmap;
uniform sampler2D original_alpha : filter_linear_mipmap;
uniform bool cutout = false;
uniform int family = -1;
uniform float shoulder = 0.72;
varying flat float variant_id;
varying vec3 local_point;
void vertex(){variant_id=INSTANCE_CUSTOM.r;local_point=VERTEX;}
void fragment(){
 vec3 c=texture(painted_albedo,UV).rgb;
 vec2 u=fract(UV);
 float lum=dot(c,vec3(0.2126,0.7152,0.0722));
 if(family==0 && variant_id>0.5){
  // Dry branch billboard: no alpha edits; broad moss coverage differs by variant.
  float moss=smoothstep(0.38,0.79,u.y)*(0.6+0.4*sin(u.x*8.0+u.y*4.0));
  if(variant_id<1.5)c=mix(c*vec3(0.78,0.90,0.82),vec3(0.085,0.14,0.075),moss*0.65);
  else c=mix(c,vec3(lum)*vec3(0.82,0.64,0.54),0.70);
 }else if(family==1 && variant_id>0.5){
  float tip=1.0-smoothstep(0.15,0.65,u.y);
  if(variant_id<1.5)c=mix(c,vec3(0.30,0.16,0.055),tip*0.8);
  else c=mix(c,vec3(lum)*vec3(0.60,0.90,0.82),0.65);
 }else if(family==2 && variant_id>0.5){
  // Confirmed atlas: foliage only in left half above v=.68; trunk untouched.
  float leaf=(1.0-step(0.50,u.x))*(1.0-step(0.68,u.y));
  if(variant_id<1.5)c=mix(c,vec3(lum)*vec3(1.12,0.98,0.47),leaf*0.82);
  else c=mix(c,vec3(lum)*vec3(0.55,0.95,0.86),leaf*0.82);
 }
 // Compress bright albedo while keeping low values and hue intact.
 c/=1.0+max(c.r,max(c.g,c.b))*shoulder;
 ALBEDO=c;
 ALPHA=cutout?texture(original_alpha,UV).a:1.0;
 ALPHA_SCISSOR_THRESHOLD=0.4;
 ROUGHNESS=0.96;SPECULAR=0.12;
}
