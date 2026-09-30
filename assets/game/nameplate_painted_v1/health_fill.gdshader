shader_type canvas_item;
uniform bool enemy = false;
void fragment() {
	vec4 sample_color = texture(TEXTURE, UV);
	if (enemy) {
		float brightness = max(sample_color.r, max(sample_color.g, sample_color.b));
		sample_color.rgb = vec3(1.0, 0.40, 0.46) * brightness;
	}
	COLOR = sample_color;
}
