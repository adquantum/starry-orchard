shader_type canvas_item;

uniform vec4 rim_color : source_color = vec4(0.95, 0.78, 0.30, 1.0);

void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(1.0, 1.24);
	float d = dot(p, p);
	if (d > 0.255) {
		discard;
	}
	vec4 tex = texture(TEXTURE, UV);
	float rim = smoothstep(0.215, 0.255, d);
	COLOR = mix(tex, rim_color, rim * 0.88);
}
