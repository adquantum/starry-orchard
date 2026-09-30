shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painted_albedo : source_color, filter_linear_mipmap;
uniform sampler2D original_alpha : filter_linear_mipmap;
uniform bool cutout = true;
uniform bool wood = false;
uniform int tree_kind = 1;
uniform float base_roughness = 0.96;
varying flat float variant_id;
varying float local_height;
// Explicit original foliage islands. Bark and branch UVs are excluded.
vec3 foliage_uv(vec2 uv) {
 uv = fract(uv); // Source GLBs use negative/repeating UVs, matching texture sampling.
 if (tree_kind == 1) {
  if (uv.x < 0.355 && uv.y < 0.465) return vec3(uv/vec2(0.355,0.465),1.0);
  if (uv.x >= 0.355 && uv.x < 0.72 && uv.y < 0.275) return vec3(((uv-vec2(0.355,0.0))/vec2(0.365,0.275)).yx,1.0);
 } else if (tree_kind == 2) {
  if (uv.x > 0.66 && uv.y < 0.355) return vec3((uv-vec2(0.66,0.0))/vec2(0.34,0.355),1.0);
  if (uv.x > 0.66 && uv.y >= 0.355 && uv.y < 0.70) return vec3((uv-vec2(0.66,0.355))/vec2(0.34,0.345),1.0);
 } else {
  if (uv.x < 0.64) return vec3(uv/vec2(0.64,1.0),1.0);
 }
 return vec3(0.0);
}
void vertex() {
 variant_id = INSTANCE_CUSTOM.r;
 local_height = VERTEX.y;
 // Silhouette changes are foliage cutout only. Vertex positions and normals stay exact.
}
void fragment() {
 vec3 base = texture(painted_albedo,UV).rgb;
 vec3 color = base;
 float alpha = cutout ? texture(original_alpha,UV).a : 1.0;
 float lightness = dot(base,vec3(0.2126,0.7152,0.0722));
 if (wood) {
  if (variant_id > 0.5 && variant_id < 1.5) {
   // Old stakes lose most white paint/snow and expose dark blue-gray wood.
   vec3 timber = mix(vec3(0.035,0.065,0.10),vec3(0.16,0.23,0.29),lightness);
   color = mix(base,timber,0.87);
  } else if (variant_id > 1.5) {
   float frost = max(smoothstep(5.8,8.7,local_height),smoothstep(0.42,0.75,lightness)*0.60);
   color = mix(base*vec3(0.68,0.82,0.93),vec3(0.86,0.94,0.99),frost*0.96);
  }
 } else {
  vec3 leaf = foliage_uv(UV);
  if (leaf.z > 0.5 && variant_id > 0.5 && variant_id < 1.5) {
   // Heavy coherent snow pads, distinct from the baseline's striped branches.
   float snow_pad = 1.0-smoothstep(0.22,0.43,abs(leaf.x-0.5));
   float cover = snow_pad * mix(0.82,0.96,smoothstep(0.08,0.48,lightness));
   color = mix(base,vec3(0.88,0.95,0.99),cover);
  } else if (leaf.z > 0.5 && variant_id > 1.5) {
   // Desnow leaves, and cut two broad outer foliage gaps while retaining stems.
   color = mix(vec3(0.028,0.085,0.11),vec3(0.10,0.24,0.28),lightness);
   float outer = smoothstep(0.07,0.15,abs(leaf.x-0.5));
   float gap_a = smoothstep(0.17,0.22,leaf.y)*(1.0-smoothstep(0.42,0.47,leaf.y));
   float gap_b = smoothstep(0.55,0.60,leaf.y)*(1.0-smoothstep(0.81,0.86,leaf.y));
   alpha *= 1.0-outer*max(gap_a,gap_b);
  }
 }
 ALBEDO = color;
 ALPHA = alpha;
 ALPHA_SCISSOR_THRESHOLD = 0.4;
 ROUGHNESS = base_roughness;
 SPECULAR = 0.18;
}
