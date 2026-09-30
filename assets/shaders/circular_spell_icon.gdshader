shader_type canvas_item;

uniform vec4 border_color : source_color = vec4(1.0, 0.65, 0.2, 1.0);
uniform float border_width = 0.075;
uniform float dim_amount = 0.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float distance_from_center = length(centered);
	if (distance_from_center > 0.5) {
		discard;
	}
	vec4 source = texture(TEXTURE, UV);
	float border = smoothstep(0.5 - border_width, 0.5 - border_width * 0.45, distance_from_center);
	vec3 color = mix(source.rgb, border_color.rgb, border * border_color.a);
	color = mix(color, color * 0.30, dim_amount);
	COLOR = vec4(color, source.a);
}
