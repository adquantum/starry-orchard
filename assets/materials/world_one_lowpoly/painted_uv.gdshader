shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painted_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D source_map : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_cutout=false;
uniform float alpha_cutoff=0.4;
uniform float source_alpha=1.0;
uniform vec4 mirror_uv_rect=vec4(0.0);
uniform float painted_roughness=0.95;
uniform float painted_specular=0.15;
void fragment() {
 // Keep the original cutout silhouette; generated RGB never defines geometry.
 if(use_cutout && texture(source_map,UV).a*source_alpha<alpha_cutoff) discard;
 vec2 painted_uv=UV;
 vec2 wrapped_uv=fract(UV);
 if(mirror_uv_rect.z>mirror_uv_rect.x && all(greaterThanEqual(wrapped_uv,mirror_uv_rect.xy-vec2(0.00001))) && all(lessThanEqual(wrapped_uv,mirror_uv_rect.zw+vec2(0.00001)))) {
  painted_uv.x=mirror_uv_rect.x+mirror_uv_rect.z-wrapped_uv.x;
 }
 ALBEDO=texture(painted_map,painted_uv).rgb;
 ROUGHNESS=painted_roughness;
 METALLIC=0.0;
 SPECULAR=painted_specular;
}
