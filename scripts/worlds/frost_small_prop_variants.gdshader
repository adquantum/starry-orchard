shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painted_albedo : source_color, filter_linear_mipmap;
uniform sampler2D original_alpha : filter_linear_mipmap;
uniform bool cutout = false;
uniform int prop_kind = 0; // box, mushroom, grass, ice shrub
uniform float bottom = 0.0;
uniform float height = 1.0;
uniform float base_roughness = 0.92;
varying flat float variant_id;
varying float relative_height;
varying float upward;
void vertex() {
 variant_id = INSTANCE_CUSTOM.r;
 relative_height = (VERTEX.y-bottom)/max(height,0.001);
 upward = max(NORMAL.y,0.0);
}
void fragment() {
 vec3 base = texture(painted_albedo,UV).rgb;
 vec3 color = base;
 float luma = dot(base,vec3(0.2126,0.7152,0.0722));
 bool b = variant_id > 0.5 && variant_id < 1.5;
 bool c = variant_id > 1.5;
 if (prop_kind == 0) {
  if (b) {
   float snow = max(smoothstep(0.58,0.86,relative_height),smoothstep(0.45,0.85,upward));
   color = mix(base*vec3(0.70,0.82,0.93),vec3(0.88,0.95,0.99),snow*0.96);
  } else if (c) {
   color = mix(vec3(0.03,0.06,0.085),vec3(0.15,0.22,0.27),luma);
  }
 } else if (prop_kind == 1) {
  float cap = smoothstep(0.25,0.57,relative_height);
  if (b) {
   float snow = cap*mix(0.68,0.97,smoothstep(0.1,0.7,upward));
   color = mix(base,vec3(0.85,0.95,0.99),snow);
  } else if (c) {
   vec3 ice = mix(vec3(0.065,0.10,0.21),vec3(0.25,0.31,0.46),luma);
   color = mix(base,ice,cap*0.95);
  }
 } else if (prop_kind == 2) {
  if (b) color = mix(base,vec3(0.82,0.94,0.98),smoothstep(0.13,0.80,relative_height)*0.90);
  else if (c) color = mix(vec3(0.025,0.09,0.13),vec3(0.10,0.25,0.29),luma);
 } else {
  if (b) color = mix(base,vec3(0.84,0.94,0.99),smoothstep(0.15,0.70,relative_height)*0.94);
  else if (c) color = mix(vec3(0.04,0.08,0.18),vec3(0.14,0.30,0.40),luma);
 }
 ALBEDO=color;
 ALPHA=cutout ? texture(original_alpha,UV).a : 1.0;
 ALPHA_SCISSOR_THRESHOLD=0.4;
 ROUGHNESS=base_roughness;
 SPECULAR=0.18;
}
