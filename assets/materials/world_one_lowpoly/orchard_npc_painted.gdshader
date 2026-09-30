shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painted_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D source_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D card_map : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_cutout = false;
uniform float alpha_cutoff = 0.4;
uniform float source_alpha = 1.0;
uniform vec4 card_rect = vec4(0.0);
void fragment() {
	if (use_cutout && texture(source_map, UV).a * source_alpha < alpha_cutoff) discard;
	vec2 wrapped = fract(UV);
	vec3 color = texture(painted_map, UV).rgb;
	// The merchant's held card uses the approved Empower face, including its UV mirror correction.
	if (card_rect.z > card_rect.x && all(greaterThanEqual(wrapped, card_rect.xy - vec2(0.00001))) && all(lessThanEqual(wrapped, card_rect.zw + vec2(0.00001)))) {
		wrapped.x = card_rect.x + card_rect.z - wrapped.x;
		color = texture(card_map, wrapped).rgb;
	}
	ALBEDO = color;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
	SPECULAR = 0.15;
}
